# Big Head Party — "Candy studio" design

Light, bright and modern: a warm canvas, candy-colored stages, real renders of the games as
posters, chunky display type and soft lifted depth. Tokens and components live in
`BigHeadParty/Views/Theme.swift`. Built with the Impeccable, Taste and Design Motion
Principles skills.

- **Canvas:** `Theme.canvas` (#FFF4EC). Cards are white (`Theme.surface`) or candy fills.
- **Text:** `Theme.ink` (#2B1B2E plum-black), `Theme.inkSoft` for supporting copy. Text on candy
  fills stays ink; on coral it's white.
- **Candy colors:** coral (primary actions, selection), blush (the star's stage), bubblegum,
  butter, sky, lime, lilac. Each game owns one for its label: Pie-Q bubblegum, Slap butter,
  Dunk sky, Whack lime, Boxing lilac.
- **Type:** Bricolage Grotesque ExtraBold (bundled, OFL) via `Font.display()` / `.party()` for
  titles, names, buttons and scores; SF Rounded (`Font.ui()`) for everything else. Both scale
  with Dynamic Type. Sentence case.
- **Depth:** `softShadow()`: a tight contact shadow plus a wide faint one. No outlines, no hard
  block shadows.
- **Components:** `.card()`, `.pill()`, `CandyButtonStyle` (squishy pill), `IconButtonStyle`
  (round white), `PressScaleButtonStyle` (cards and chips), `AvatarView`.
- **Home:** the star is live on a blush stage (tap for a pie); games are a mosaic of real
  renders (`cover-<game>` assets) in varied sizes. No eyebrow labels above headings.
- **Icons:** SF Symbols only, no emoji. Touch targets at least 44 pt.
- **Game sets:** `Scenes/CandySet.swift`. Each game is a candy-colored set: soft gradient
  backdrop, matte floor, unlit backdrop walls in true colors, rounded Bricolage signs. Pie-Q
  bubblegum game show, Slap butter sunburst, Dunk sky carnival, Whack lilac arcade, Boxing
  daylight lilac ring. Cameras run at normal exposure with auto exposure and vignette off; the
  lights are dimmed instead, so skin looks the same as on the home screen.
- **Posters:** `cover-<game>` assets are crops of the real sets; re-shoot them when a set changes.
- **Exception:** the camera screen stays dark so a bright screen doesn't tint selfies.
