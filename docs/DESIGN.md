# Big Head Party — "Daylight studio" design

Realistic people in real places, framed by a bright, airy UI that lets the sets and faces carry
the color. Replaces the earlier "Candy studio" and "Night studio" looks. Tokens and components live in `BigHeadParty/Views/Theme.swift`.

## Screens
- **Canvas:** `Theme.canvas` (#F3EFE8 warm paper); cards `Theme.surface` (white) with a 1 pt
  `Theme.hairline` edge and a faint shadow.
- **Text:** `Theme.ink` (#1A1917 near-black), `Theme.inkSoft` for supporting copy.
- **Accent:** one on-air red (`Theme.coral`, #EC4A29) for primary actions and selection; white
  text on it. Per-game tones are soft and muted (Pie-Q rose, Slap sand, Dunk mist blue, Whack
  sage, Boxing lavender), with ink text.
- **Type:** SF Pro Heavy Condensed via `Font.display()` / `.party()` for titles, names, buttons and
  scores (a broadcast lower-third voice); SF Pro (`Font.ui()`) for everything else. Scales with
  Dynamic Type. Sentence case.
- **Game tiles:** Pie-Q featured full width, then a 2×2 grid. Each tile is a soft-toned card with
  the poster in a framed window and the name, icon and player count below it.
- **Icons:** SF Symbols only, no emoji. Touch targets at least 44 pt.
- **Camera screen:** stays dark so the screen doesn't tint selfies.

## Game sets — real places (`Scenes/Location.swift`)
Each game sits in a real 360° HDR photo (Poly Haven, CC0) that is both the background and the
light, with a matching sun for shadows and an invisible shadow-catcher floor:
Pie-Q in a neon photo studio (black gloss riser, painted-metal podiums, LED strips), Slap in a
house's back garden (wooden deck, stump), Dunk in an open park (glass tank, steel frame, tarp),
Whack in an auto shop (red arcade cabinet, rubber top, chrome rims, bulbs), Boxing in an empty
warehouse (canvas ring, steel posts, cloth ropes). Props use `Surface` materials (painted metal,
steel, chrome, plastic, wood, canvas, glass).

HDRs are clamped (the sun in some photos is ~150,000× white and breaks the lighting) and
pre-rotated when bundled, since the background ignores `contentsTransform`. Re-run the scratch
`clamphdr.py in out 24 [roll]` when adding one.

## Characters and props
- Bodies are realistic skinned glTF models (`Models/body-*.glb`, generated, heads cut at the
  neck, loaded with GLTFKit2 in `Scenes/RealBody.swift`); toy bodies are the fallback. Arms move
  through proxy nodes (slap) or two-bone IK to the gloves (boxing).
- The default cast wears baked photo faces (`Cast/<id>.jpg` + `.json`, made with the player
  photo pipeline). Big heads are the default; real heads are in the menu.
- Pie and mallet are real models. Pie hits add cream to a head-shaped coat (`CreamCoat` in
  `Scenes/Cream.swift`) that spreads and thickens with every pie, with runs dripping down,
  whipped dollops and crust crumbs. The first pie hits the middle; later ones land all over the
  face. Built before the first throw so nothing is computed mid-throw.
- **Posters:** `cover-<game>` are crops of the real sets with signs hidden; re-shoot them when a
  set changes.
