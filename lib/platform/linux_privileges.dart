/// Granting the engine the capability a tun needs, through polkit.
///
/// Android gets its tun from `VpnService`: one dialog, and the fd arrives with
/// no capabilities involved. Linux has no such dialog — creating a tun device
/// and installing routes needs `CAP_NET_ADMIN` — so the equivalent is a file
/// capability on the `sing-box` binary, set once by root. `pkexec` is what asks:
/// polkit puts up the same authentication dialog the desktop uses for mounting a
/// disk or installing a package, and runs `setcap` on the other side of it.
///
/// File capabilities are applied by the kernel at `execve` of that file, and the
/// controller spawns `sing-box` as its own child, so granting them to the binary
/// is enough. Nothing here elevates the app itself, and no privileged helper is
/// installed: what survives is one attribute on one file.
///
/// The cost is that a package upgrade replaces the binary and the attribute goes
/// with it. That is not worth a helper daemon — the prompt simply comes back the
/// next time a tun is started.
library;

import 'dart:io';

import 'linux_system_proxy.dart' show CommandRunner;

/// The capability set a tun inbound needs.
///
/// `cap_net_admin` creates the interface and writes the routes; `cap_net_raw` is
/// what sing-box's own documentation pairs with it, for the sockets the tun
/// stack opens. `+ep` makes them effective without the binary having to raise
/// them itself.
const tunCapabilities = 'cap_net_admin,cap_net_raw';

/// Results stay structured until the UI translates a recovery instruction.
enum TunAuthorization {
  granted,
  required,
  declined,
  missingTools,
  authenticationFailed,
  unsafePath,
  nixosSetupRequired,
  checkFailed,
  failed,
}

/// Reads and grants the file capabilities the tun mode needs.
class LinuxPrivileges {
  LinuxPrivileges({
    CommandRunner? runner,
    Iterable<String>? trustedRoots,
    Iterable<String>? searchPaths,
    bool Function(String path)? exists,
    Future<String?> Function(String path)? securePath,
    Future<String> Function(String path)? resolvePath,
  }) : _run = runner ?? _runProcess,
       _exists = exists ?? _fileExists,
       _securePath = securePath ?? resolveSecurePath,
       _resolvePath =
           resolvePath ?? ((path) => File(path).resolveSymbolicLinks()),
       _trustedRoots = List.unmodifiable(trustedRoots ?? defaultTrustedRoots),
       _searchPaths = List.unmodifiable(searchPaths ?? defaultSearchPaths);

  /// Directories whose contents may be handed to an elevated `setcap`.
  ///
  /// The binary path can come from `SINGBOX_BINARY`, which is process
  /// environment and therefore an input. Running `setcap` as root against an
  /// arbitrary path would turn that input into a capability grant on a file of
  /// the caller's choosing, so only the system locations a distribution installs
  /// an engine into are eligible. A binary outside them still runs — it just has
  /// to be granted by hand, which is a developer's own business.
  static const defaultTrustedRoots = [
    '/usr/bin/',
    '/usr/sbin/',
    '/usr/local/bin/',
    '/usr/local/sbin/',
    '/usr/lib/',
    '/bin/',
    '/sbin/',
    '/opt/',
  ];

  /// Where `pkexec`, `setcap` and `getcap` are looked for.
  ///
  /// Absolute paths rather than a `PATH` search: `pkexec` runs its argument as
  /// root, and resolving that argument through an environment variable the
  /// caller controls is how a PATH-injection bug is written.
  static const defaultSearchPaths = [
    '/run/wrappers/bin',
    '/run/current-system/sw/bin',
    '/usr/bin',
    '/usr/sbin',
    '/bin',
    '/sbin',
  ];

  final CommandRunner _run;
  final Future<String> Function(String) _resolvePath;
  final Future<String?> Function(String) _securePath;

  /// Whether a tool is installed. Injectable so the argv can be asserted on a
  /// host that has no `pkexec` — a CI container, for one.
  final bool Function(String path) _exists;

  final List<String> _trustedRoots;
  final List<String> _searchPaths;

  /// Checks the actual target: getcap does not follow a symlink to a wrapper.
  Future<TunAuthorization> inspectTunCapabilities(String binary) async {
    final getcap = _locate('getcap');
    if (getcap == null) return TunAuthorization.missingTools;
    final trustedGetcap = await _securePath(getcap);
    if (trustedGetcap == null) return TunAuthorization.unsafePath;
    try {
      final target = await _resolvePath(binary);
      final result = await _run(trustedGetcap, [target]);
      if (result.exitCode != 0) return TunAuthorization.checkFailed;
      final output = '${result.stdout}'.trimRight();
      final prefix = '$target ';
      final capabilities = output.startsWith(prefix)
          ? output.substring(prefix.length)
          : '';
      return capabilitiesPresent(capabilities)
          ? TunAuthorization.granted
          : TunAuthorization.required;
    } on Object {
      return TunAuthorization.checkFailed;
    }
  }

  Future<bool?> hasTunCapabilities(String binary) async =>
      switch (await inspectTunCapabilities(binary)) {
        TunAuthorization.granted => true,
        TunAuthorization.required => false,
        _ => null,
      };

  /// Asks polkit once, then verifies the capability on the same canonical file.
  /// NixOS wrappers are configured declaratively; never mutate the Nix store.
  Future<TunAuthorization> grantTunCapabilities(String binary) async {
    String target;
    try {
      target = await _resolvePath(binary);
    } on Object {
      return TunAuthorization.unsafePath;
    }
    if (isNixPath(binary) || isNixPath(target)) {
      return TunAuthorization.nixosSetupRequired;
    }
    if (!mayElevate(binary)) return TunAuthorization.unsafePath;
    final canonical = await _securePath(binary);
    if (canonical == null || !mayElevate(canonical)) {
      return TunAuthorization.unsafePath;
    }
    final argv = elevationCommand(canonical);
    if (argv == null) return TunAuthorization.missingTools;
    final pkexec = await _securePath(argv[0]);
    final setcap = await _securePath(argv[2]);
    if (pkexec == null || setcap == null) return TunAuthorization.unsafePath;
    try {
      final result = await _run(pkexec, [argv[1], setcap, ...argv.sublist(3)]);
      final outcome = outcomeOf(result.exitCode);
      if (outcome != TunAuthorization.granted) return outcome;
      return await inspectTunCapabilities(canonical) == TunAuthorization.granted
          ? TunAuthorization.granted
          : TunAuthorization.failed;
    } on Object {
      return TunAuthorization.failed;
    }
  }

  static bool isNixPath(String path) =>
      path.startsWith('/nix/store/') ||
      path.startsWith('/run/current-system/') ||
      path.startsWith('/run/wrappers/') ||
      path.startsWith('/run/wrappers.');

  /// Absolute argv, no shell; disable the terminal fallback in a GUI process.
  List<String>? elevationCommand(String binary) {
    final pkexec = _locate('pkexec');
    final setcap = _locate('setcap');
    if (pkexec == null || setcap == null) return null;
    return [
      pkexec,
      '--disable-internal-agent',
      setcap,
      '$tunCapabilities+ep',
      binary,
    ];
  }

  /// Whether [binary] is one this will run an elevated `setcap` against.
  ///
  /// Absolute, named `sing-box`, and inside [defaultTrustedRoots]. See that
  /// constant for why the last condition is not paranoia.
  bool mayElevate(String binary) {
    if (!binary.startsWith('/') ||
        binary.split('/').contains('..') ||
        binary.split('/').contains('.')) {
      return false;
    }
    if (binary.split('/').last != 'sing-box') return false;
    return _trustedRoots.any(binary.startsWith);
  }

  /// Resolve before elevation, then require root ownership and no group/other
  /// write permission for the file and every ancestor. The canonical path is
  /// passed to setcap, so swapping a user-owned symlink cannot redirect it.
  static Future<String?> resolveSecurePath(String path) async {
    try {
      final canonical = await File(path).resolveSymbolicLinks();
      if (await FileSystemEntity.type(canonical) != FileSystemEntityType.file) {
        return null;
      }
      final paths = <String>[canonical];
      var parent = File(canonical).parent;
      while (true) {
        paths.add(parent.path);
        if (parent.path == '/') break;
        parent = parent.parent;
      }
      final statPath = defaultSearchPaths
          .map((dir) => '$dir/stat')
          .where(_fileExists)
          .firstOrNull;
      if (statPath == null) return null;
      final stat = await Process.run(statPath, [
        '-Lc',
        '%u:%a',
        '--',
        ...paths,
      ]);
      if (stat.exitCode != 0) return null;
      final lines = '${stat.stdout}'.trim().split('\n');
      if (lines.length != paths.length) return null;
      for (var index = 0; index < lines.length; index++) {
        final fields = lines[index].split(':');
        if (fields.length != 2) return null;
        final owner = int.tryParse(fields[0]);
        final mode = int.tryParse(fields[1], radix: 8);
        if (owner == null ||
            mode == null ||
            !ownershipSafe(paths[index], owner, mode, directory: index > 0)) {
          return null;
        }
      }
      return canonical;
    } on Object {
      return null;
    }
  }

  /// Nix's store can be group-writable with the sticky bit. Root-owned children
  /// remain protected there; no other writable directory gets this exception.
  static bool ownershipSafe(
    String path,
    int owner,
    int mode, {
    bool directory = false,
  }) {
    if (owner != 0) return false;
    if (mode & 0x12 == 0) return true; // 0022 octal
    return directory &&
        path == '/nix/store' &&
        mode & 0x200 != 0 &&
        mode & 0x2 == 0; // sticky, never world-writable
  }

  /// Track flags per capability; an effective flag on an unrelated capability
  /// must not make a permitted-only TUN capability look usable.
  static bool capabilitiesPresent(String output) {
    final lines = output.trim().split('\n');
    if (lines.length != 1) return false;
    final flags = <String, Set<String>>{};
    final clauses = RegExp(
      r'(?:^|\s)(cap_[a-z0-9_]+(?:,cap_[a-z0-9_]+)*)([=+\-])([eip]+)(?=\s|$)',
    );
    for (final match in clauses.allMatches(lines.single)) {
      for (final name in match[1]!.split(',')) {
        final current = flags.putIfAbsent(name, () => <String>{});
        if (match[2] == '=') current.clear();
        if (match[2] == '-') {
          current.removeAll(match[3]!.split(''));
        } else {
          current.addAll(match[3]!.split(''));
        }
      }
    }
    return [
      'cap_net_admin',
      'cap_net_raw',
    ].every((name) => flags[name]?.containsAll(['e', 'p']) ?? false);
  }

  /// pkexec distinguishes a dismissed dialog (126) from inability to obtain
  /// authentication (127), which can also mean a missing agent or denied policy.
  static TunAuthorization outcomeOf(int exitCode) => switch (exitCode) {
    0 => TunAuthorization.granted,
    126 => TunAuthorization.declined,
    127 => TunAuthorization.authenticationFailed,
    _ => TunAuthorization.failed,
  };

  /// First existing `dir/name` from [_searchPaths].
  String? _locate(String name) {
    for (final dir in _searchPaths) {
      final candidate = '$dir/$name';
      if (_exists(candidate)) return candidate;
    }
    return null;
  }

  static bool _fileExists(String path) => File(path).existsSync();

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments);
}
