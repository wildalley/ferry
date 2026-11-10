import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferry/data/importer.dart';

/// Run separate processes with flutter test, using --dart-define=MODE=sync
/// or MODE=isolate and --dart-define=COUNT=10000.
void main() => test('import latency benchmark', () async {
      const mode = String.fromEnvironment('MODE', defaultValue: 'isolate');
      const count = int.fromEnvironment('COUNT', defaultValue: 10000);
      final importer = Importer();
      final payload = jsonEncode({
        'outbounds': List.generate(
            count,
            (i) => {
                  'type': 'trojan',
                  'tag': 'Node $i',
                  'server': 'node$i.example.invalid',
                  'server_port': 443,
                  'password': 'benchmark-only',
                })
      });
      final before = ProcessInfo.currentRss;
      var maxTickGap = 0;
      final watch = Stopwatch()..start();
      var previousTick = 0;
      final tick = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final now = watch.elapsedMicroseconds;
        final gap = now - previousTick;
        if (gap > maxTickGap) maxTickGap = gap;
        previousTick = now;
      });
      final result = mode == 'sync'
          ? importer.importSingBoxConfig(payload)
          : await importer.importText(payload);
      final elapsed = watch.elapsedMicroseconds;
      await Future<void>.delayed(const Duration(milliseconds: 3));
      tick.cancel();
      importer.dispose();
      stdout.writeln(jsonEncode({
        'mode': mode,
        'nodes': result.nodes.length,
        'inputBytes': utf8.encode(payload).length,
        'elapsedUs': elapsed,
        'maxMainIsolateTickGapUs': maxTickGap,
        'rssBefore': before,
        'rssAfter': ProcessInfo.currentRss,
        'peakRss': ProcessInfo.maxRss
      }));
    });
