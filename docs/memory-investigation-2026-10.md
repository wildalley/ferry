# Background memory investigation — 2026-10-15

## Report and measurements

A Linux user reported high client memory after prolonged use, mostly with the
window hidden in the tray or minimized. The system monitor showed about 1 GiB;
subsequent reads of the running process showed roughly 1.2 GiB RSS. The supervised
`sing-box` core was a separate process using about 100 MiB.

Summing RSS across **all** mappings labelled `[anon:dart-heap]` gave about 22 MiB.
Most resident memory was in native heap and other anonymous mappings.
These mappings identify where memory resides; they do not identify its allocator
or prove a Flutter engine or graphics-driver leak. Native rendering allocations
remain a hypothesis requiring profiling if growth continues.

The existing data stores were already bounded: the log retains 500 entries and
each traffic history retains 60 samples. They did not explain the observed
gigabyte-scale resident footprint.

## Changes in 0.1.5-12

- Desktop hide/show and minimize/restore explicitly update presentation
  visibility. Flutter hidden/paused/resumed lifecycle events also control it.
- The retained navigator goes offstage and its tickers stop while hidden. This
  prevents painting and animation work without losing the selected page or
  scroll position. The dashboard's one-second uptime timer also stops.
- The log page allows at most one pending follow-scroll callback. Previously,
  every state notification could enqueue another callback while frames were
  suspended, even though the log itself was bounded. The callback also checks
  that its page is still mounted before using the scroll controller.

The tunnel and runtime subscriptions continue running. Statistics keep updating
within their existing caps, and the tray can still reflect connection changes.

## Verification

`test/background_presentation_test.dart` covers four behaviors:

1. Closing into a mocked tray hides presentation without shutdown; activation
   shows and focuses the same application.
2. Minimizing stops animations and uptime frame requests while 1,000 traffic/log
   updates still reach the bounded stores; restoring retains the home element.
3. Hidden/resumed lifecycle events park and restore presentation without
   shutting down the controller.
4. Delivering 2,000 separate traffic/log batches without drawing a frame adds
   exactly one follow-scroll callback. Restoring retains the log page and follows
   its latest entry; disposal before a queued callback is safe.

Validation commands:

```bash
flutter analyze --no-pub
flutter test --no-pub
scripts/package.sh arch
```

The Arch package `singbox-client-0.1.5-12-x86_64.pkg.tar.zst` was installed through
the system package manager. After the user restarted the application, its mapped
`libapp.so` inode matched the installed library, whose SHA-256 matched the release
bundle. This confirmed that the new process loaded the repaired build.

The initial post-restart client reading was approximately 300 MiB RSS and the core
about 84 MiB. This is a fresh-process baseline, **not** evidence that long-running
growth has stopped. RSS fluctuates with sampling and workload, and includes
shared resident pages; it is not interchangeable with PSS or private memory.

## Remaining validation

Repeat the user's normal connected workload with the window mostly in the tray
or minimized, comparing process memory over several hours against the fresh
baseline. Check the visible dashboard and log page separately if growth remains.
Record client and core memory independently, with elapsed time, visibility state,
and consistent RSS/PSS/private-memory measurements. Avoid config files, node
credentials, and API secrets in diagnostic output.

The callback accumulation is bounded by the regression test. The native-memory
root cause and day-long stability remain unconfirmed; resolving those requires a
longer run and, if necessary, native allocation profiling. Desktop interaction
tests use mocked platform channels and do not establish behavior across all
compositors, graphics drivers, or Windows installations.
