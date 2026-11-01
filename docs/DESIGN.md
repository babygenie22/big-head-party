# Big Head Party — "Toy box" design

The app looks like bobblehead packaging: sunny yellow card stock, black ink outlines, and
sticker-colored pieces with hard offset shadows. Tokens and components live in
`BigHeadParty/Views/Theme.swift`.

- **Ground:** `Theme.paper` (#FFDF4A) with a faint halftone dot print (`Theme.background`).
- **Ink:** `Theme.ink` (#17130F) for all text, outlines (3 pt) and shadows (5 pt down-right, no blur).
- **Surfaces:** `Theme.cream` (#FFF7E0) panels via `.sticker()` / `.stickerCapsule()`.
- **Sticker colors:** tomato (primary actions, highlights), sky (3D windows), mint (success,
  "ready"), bubblegum, lilac. Each game owns one: Pie-Q bubblegum, Slap tomato, Dunk sky,
  Whack mint, Boxing lilac.
- **Type:** SF Rounded. `.party()` (black) for titles and buttons; heavy/bold rounded for body.
  Sentence case.
- **Buttons:** `ChunkyButtonStyle` (sticker that presses into its shadow, light haptic);
  `StickerIconButtonStyle` for round icon buttons.
- **Signature:** the home-screen star stands in a collector box ("Series 1 · Collect 'em all").
- **Icons:** SF Symbols only, no emoji.
- **Exceptions:** 3D game stages keep their own lit sets; the camera screen stays dark so a
  bright screen doesn't tint selfies.
