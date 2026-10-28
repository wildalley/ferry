/// Opens a web page in the user's browser.
///
/// Small enough not to warrant a plugin: one intent on Android, one command
/// on each desktop. Returns false when nothing could be opened, so the caller
/// can fall back to copying the link.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'app_paths.dart' show appControlChannel;

const _channel = MethodChannel(appControlChannel);

Future<bool> openExternalUrl(String url) async {
  // Release pages only ever come from the GitHub API over https; refusing
  // anything else keeps this from turning into a command or intent launcher.
  if (!url.startsWith('https://')) return false;
  try {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    }
    final (String command, List<String> args) =
        switch (Platform.operatingSystem) {
      'windows' => ('rundll32', ['url.dll,FileProtocolHandler', url]),
      'macos' => ('open', [url]),
      _ => ('xdg-open', [url]),
    };
    await Process.start(command, args, mode: ProcessStartMode.detached);
    return true;
  } on Object {
    return false;
  }
}
