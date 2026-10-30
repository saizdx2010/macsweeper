# Figcraft design board

Design-first workspace for the minimal UI redesign. Pick a direction here before any SwiftUI changes.

| Path | What |
|------|------|
| `MacSweeper.figcraft.html` | The board: 4 directions (Overview + Results each), 41-icon set, 4 app icon concepts, motion specs and tokens. Open in a browser. |
| `icons/*.svg` | Exported 24 × 24 line icons (black stroke, ready for Figma or an Xcode template asset). |
| `app-icons/*.svg` | 1024 × 1024 app icon concepts on the macOS 824 px grid. |
| `previews/*.png` | Static screenshots of each board section. |

The board's `<symbol>` sprite and `ICONS` list are the source of truth. After editing them, re-export:

```sh
python3 scripts/export-design-assets.py
```

To bring the board into Figma, drag the SVGs in directly, or import the HTML with an HTML-to-Figma plugin.
