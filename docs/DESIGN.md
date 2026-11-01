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
- **Exceptions:** 3D game stages keep their own lit sets; the camera screen stays dark so a
  bright screen doesn't tint selfies.
