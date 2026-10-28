# Obsidian Signal design handoff

Generated with Google Stitch MCP on 2026-08-28.

- Stitch project: `projects/13673201704756137298`
- Design system: `assets/13690083369528402681`
- Project title: SingBox Client
- Visual system: Obsidian Signal

## Screens

- `SingBox Home` — disconnected mobile state (`f138010213974d5bbccc0bd87cb12033`)
- `SingBox Home (Connected)` — connected mobile state (`eb682977b8e44d4886316ea1ebacfe22`)
- `Nodes List` — mobile node selection (`2f770bc8685c4c2496b63a79ff3cd9ca`)
- `Settings` — mobile configuration (`aa85b91da92245ad86dcf24e2b45942c`)
- `Overview — SingBox` — desktop dashboard (`7e1ba17d99ec4a5d871e209151d5ccf7`)
- `Settings — Obsidian Signal` — refreshed mobile configuration (`c719162dee81486997e4bdd87122f41b`)

Preview exports (`home-disconnected.png`, `home-connected.png`, `nodes.png`, `settings.png`, and `desktop-overview.png`) are kept in this directory for implementation review. The Flutter code intentionally recreates the design using native widgets and CustomPaint rather than embedding generated HTML.

## Synapse V4

The app now carries the **Synapse V4** visual refresh: the existing information
architecture with obsidian panels, violet signal artwork, and a new ribbon icon.

- Reference sheet: [`synapse-v4.png`](synapse-v4.png)
- Implementation plan: [`synapse-v4.md`](synapse-v4.md)
- Shipped refresh and artwork provenance: [`refresh-2026-09.md`](refresh-2026-09.md)

The dated refresh notes supersede the earlier plan's no-bitmap constraint:
the latest user brief explicitly requested a generated icon and the reference's
sculptural art direction. All controls, data, and charts remain native Flutter.

## 渡 Ferry (2026-10)

Supersedes Synapse V4 and the Kinetix brand. The previews the direction was
chosen from (three concepts, then the merged light/dark set) live on the design
canvas; the shipped tokens are in `lib/ui/theme.dart`.

- **Name** — 渡 / Ferry: crossing the water, which is what a proxy does.
- **Colour** — one brand colour, violet (`#5A33E6` light / `#6A3BF0` dark),
  for the connect switch, the tide gauge, selected tabs and the mark, over
  neutral surfaces and a faint 40px grid. Mint is the only accent and means
  "connected". Surfaces are solid; nothing is frosted or translucent.
- **Signature** — `TideGauge` (`lib/ui/tide_gauge.dart`): the hero's basin,
  whose water level is the live rate on a 1 KB/s–16 MB/s log scale. It rolls one
  beat per traffic reading and shows a dashed low-water line while disconnected.
- **Connect control** — a pill switch with a paper-plane knob: on the left
  and violet when off; on the right, white, over a violet track when on. The
  settings switches and menus share its language (solid track, no outline;
  card-coloured menus with a hairline edge).
- **Type** — titles, the exit name and live rates in a serif (Source Serif 4,
  bundled, with the system's Noto Serif CJK for Han); Inter for body; JetBrains
  Mono for data.
- **Nodes** — a region's flag (emoji; the code on Windows) instead of letters;
  the selected row gets a violet edge and a check.
- **Mark** — a white paper plane over a wave on a violet plate
  (`paintBrandMark` in `lib/ui/brand.dart`): "send" reads at any size, which
  is what makes it recognisable as a connection tool.
- **Icons** — launcher, app, tray and Windows icons are rendered from code:
  `RENDER_ICONS=1 flutter test test/render_icons_test.dart`.
