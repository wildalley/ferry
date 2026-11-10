# Ferry design and icon sources

The current interface uses violet surfaces, a paper plane over a wave, and a
faint grid. Light/dark themes and English/Chinese share the same components.
Earlier Obsidian Signal, Synapse and alternative brand concepts have been removed
from the working tree; they remain in Git history.

## Maintained sources

- `lib/ui/theme.dart`: palette, type and spacing tokens.
- `lib/ui/brand.dart`: `paintBrandMark`, the source for the app and platform icons.
- `lib/ui/components.dart`: the code-rendered grid and shared controls.
- `lib/ui/tide_gauge.dart`: the live traffic gauge.
- `test/render_icons_test.dart`: renders Android launchers, app/tray images,
  Windows ICO and `docs/design/icon/linux/` PNGs.
- `test/visual_snapshot_test.dart` and `test/snapshots/`: visual regression
  fixtures; these are test baselines, not unused design previews.

Titles and live readings use Source Serif 4 with platform CJK fallback, body
text uses Inter, and data uses JetBrains Mono. Fonts and their licenses remain
under `assets/fonts/`. Essential controls and charts are native Flutter widgets
or code-rendered shapes.

## Updating the mark

Change `paintBrandMark`, then generate and review the platform resources:

```sh
scripts/build-icons.sh
flutter test test/android_resources_test.dart test/brand_ui_test.dart
```

The script delegates to `RENDER_ICONS=1 flutter test test/render_icons_test.dart`;
there is no separate raster master or legacy SVG generation path to keep in sync.
Commit the generated resources together with the source change. Linux packaging
requires all four checked-in icon sizes and reports missing files explicitly.

Only refresh visual baselines after reviewing an intentional interface change:

```sh
VISUAL_SNAPSHOTS=1 flutter test --update-goldens test/visual_snapshot_test.dart
```

Current layouts must continue to respect reduced motion, large text, keyboard
navigation and dark/light contrast. Tests using mocked platform channels do not
replace desktop compositor or Android device validation.
