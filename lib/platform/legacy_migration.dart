/// Carries a desktop install's data across the rename from SingBox Client to
/// 渡 Ferry.
///
/// Both of the places the app keeps things are named after it, so the rename
/// moved them and a first launch would otherwise open empty — no
/// subscriptions, no nodes, no settings:
///
/// * the preferences file, which `shared_preferences` keeps under the
///   application ID on Linux (`~/.local/share/<app id>/`) and under the
///   company and product name on Windows (`%APPDATA%\<company>\<product>\`);
/// * the data directory — rule-sets and the engine's cache — under
///   [desktopDataDirName] on Linux and `%LOCALAPPDATA%\<name>` on Windows.
///
/// Copied, never moved: the old copy stays as it was, so nothing is lost if
/// the new version is rolled back, and an old instance still running is not
/// pulled out from under. Each item is copied only when the new location lacks
/// it, so this runs harmlessly on every launch and never overwrites what the
/// new version has written since.
///
/// Android cannot be migrated: a new application ID is a new app with its own
/// sandbox, which this one has no access to.
library;

import 'dart:io';

/// The preferences file name `shared_preferences` uses on the desktop.
const _prefsFile = 'shared_preferences.json';

/// Data-directory entries worth keeping. The rendered config is regenerated on
/// every connect and the instance socket belongs to whichever process made it.
const _dataEntries = ['rule-sets', 'cache.db'];

/// Copies whatever the old locations hold and the new ones do not.
///
/// [environment] and [windows] are injectable for tests. Never throws: a
/// migration that fails leaves a fresh install, which is a worse start but not
/// a reason to refuse to start at all.
Future<void> migrateLegacyDesktopData({
  Map<String, String>? environment,
  bool? windows,
}) async {
  final env = environment ?? Platform.environment;
  final isWindows = windows ?? Platform.isWindows;
  if (!isWindows && !Platform.isLinux && windows == null) return;

  final pairs = <(String, String)>[];
  if (isWindows) {
    final roaming = env['APPDATA'];
    if (roaming != null && roaming.isNotEmpty) {
      pairs.add((
        '$roaming\\com.wildalley\\SingBox Client\\$_prefsFile',
        '$roaming\\com.wildalley\\Ferry\\$_prefsFile',
      ));
    }
    final local = env['LOCALAPPDATA'] ?? env['APPDATA'];
    if (local != null && local.isNotEmpty) {
      for (final entry in _dataEntries) {
        pairs.add(('$local\\SingBox Client\\$entry', '$local\\Ferry\\$entry'));
      }
    }
  } else {
    final root = _xdgDataRoot(env);
    if (root != null) {
      pairs.add((
        '$root/com.wildalley.singbox_client/$_prefsFile',
        '$root/com.wildalley.ferry/$_prefsFile',
      ));
      for (final entry in _dataEntries) {
        pairs.add(('$root/singbox-client/$entry', '$root/ferry/$entry'));
      }
    }
  }

  for (final (from, to) in pairs) {
    try {
      await _copyIfMissing(from, to, posix: !isWindows);
    } on Object {
      // One item failing — a locked cache, a permission — should not stop the
      // rest; the preferences file is the one that matters most.
    }
  }
}

/// `$XDG_DATA_HOME`, or `~/.local/share`.
String? _xdgDataRoot(Map<String, String> env) {
  final xdg = env['XDG_DATA_HOME'];
  if (xdg != null && xdg.startsWith('/')) return xdg;
  final home = env['HOME'];
  return home == null || home.isEmpty ? null : '$home/.local/share';
}

Future<void> _copyIfMissing(
  String from,
  String to, {
  required bool posix,
}) async {
  final type = FileSystemEntity.typeSync(from, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (FileSystemEntity.typeSync(to, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return;
  }
  final parent = File(to).parent;
  if (!parent.existsSync()) {
    await parent.create(recursive: true);
    // The data directory holds node credentials; keep it the owner's alone,
    // as app_paths does for a directory it creates itself.
    if (posix) await Process.run('chmod', ['700', parent.path]);
  }
  if (type == FileSystemEntityType.directory) {
    await _copyDirectory(Directory(from), Directory(to));
  } else if (type == FileSystemEntityType.file) {
    await File(from).copy(to);
  }
}

Future<void> _copyDirectory(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entity in from.list(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final target = '${to.path}${Platform.pathSeparator}$name';
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(target));
    } else if (entity is File) {
      await entity.copy(target);
    }
  }
}
