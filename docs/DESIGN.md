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
Whack at a county fair in a park at sunset (`Scenes/Fairground.swift`: striped prize booth with
plush bears, marquee sign and chasing bulbs, scalloped awning, bunting, balloons, a boardwalk with
confetti, popcorn and cotton candy; only props near the board show under the score bar), Boxing in an empty
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
- Hair is a 3D shell grown from the scalp on the head's own vertex grid (`Scenes/Hair.swift`):
  thick over the crown, thinning to a ragged hairline, combed into clumps, tinted halfway toward
  the photo's own hair. Bald heads (crown filled with skin) get none. Styles: natural, bun (coiled),
  long (hangs free below the ears), afro, pompadour. It follows the face's blend shapes, and gets
  wet and golden with the head.
- Every head has a neck; the home screen and Face Studio show a head-and-shoulders bust.
- Heads are alive between hits (`HeadRig` "Signs of life"): they blink (a `blink` blend shape that
  closes the photo's own eyelids), glance around and fidget. Fidgets never run over an expression
  a game is driving. Eyes are part of the photo, so they can't turn on their own: the head turns.
- Dunk Tank sits in a carnival booth (`Scenes/DunkBooth.swift`): wooden stage, striped backdrop,
  marquee, bunting, balloons, ladder, bulbs round the target. It shares the fair's helpers.
- Skin detail comes from each person's own photo (`Scenes/SkinDetail.swift`): brightness is read
  as height and turned into a normal map over the whole head texture, so their wrinkles, pores
  and stubble catch the light. Built once per character at first use, not stored.
- What happens to a face stays on it (`SkinMarks`, same file): a slap leaves a red handprint
  that fades in seconds, punches flush and then bruise for the rest of the fight, in a small
  texture that multiplies the photo. Wet skin is darker and glossy with beads of water (a
  droplet normal map on the clear coat). `-demoLook slap|bruise|wet` previews them at home.
- Pie cream sags after it lands: for a few seconds the thick parts run down the face
  (`CreamCoat.settle`).
- Side photos (optional, Face Studio): a photo with the head turned about halfway to each side
  fills in the cheeks, jaw and temples, which one front photo can only smear. `Face/SideFit.swift`
  lines the photo up with the head (the turn from how much the eyes are squeezed together, then
  scale, tilt and shift from the landmarks), matches its colour to the front texture and cuts it
  out; `Scenes/SideOverlay.swift` wears it as a skin-tight layer over that side, blended in by
  vertex alpha wherever the side camera saw the skin more squarely than the front one. Stored as
  `<id>-side<n>.png` beside the face, with the line-up in `CharacterMeta.sides`.
- Face scan (Face Studio, "Scan My Face"): one selfie-camera session takes the front photo and both side
  photos with no button. The live picture sits in a big circle. `FaceScan` takes the front photo once
  the face has been in place for about a second (the ring sweeps round), then takes each side on the
  move as the head turns through the right angle (not if it turns too fast; each half of the ring fills
  as the head turns). The photos drop into three slots under the circle. `GuidedCamera` takes the
  photos, at the camera's full resolution. Photo head textures are 3072² and side textures up to 2048 px.
  The side photos go through the same `SideFit` as hand-picked ones once the head is built.
- Pie and mallet are real models. Pie hits add cream to a head-shaped coat (`CreamCoat` in
  `Scenes/Cream.swift`) that spreads and thickens with every pie, with runs dripping down,
  whipped dollops and crust crumbs. The first pie hits the middle; later ones land all over the
  face. Built before the first throw so nothing is computed mid-throw.
- **Posters:** `cover-<game>` are crops of the real sets with signs hidden; re-shoot them when a
  set changes.
