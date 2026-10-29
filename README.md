# Big Head Party

An iOS party game. Upload a photo of a friend or family member. On-device AI maps their face, a 3D head is sculpted to match it, and they get dropped into slapstick mini-games: pied on a game show or knocked silly in a bobblehead boxing ring.

- **iOS app:** `BigHeadParty.xcodeproj` (SwiftUI + SceneKit + Vision, iOS 17+, no third-party dependencies)
- **Playable web prototype:** `web-prototype/index.html` (three.js + MediaPipe). Try the face pipeline in a browser today.
- **Game design research:** [`docs/GAME_IDEAS.md`](docs/GAME_IDEAS.md). Ten concepts ranked, plus the fighting-game vs. game-show comparison.

## The flow

1. **First launch: attract mode.** Two house characters (Grandpa Gus and Aunt Linda) take turns getting pied on a live 3D game-show set, so you see the payoff before doing anything.
2. **How it works.** Four steps: photo → AI face map → 3D head → pie it.
3. **Play nice.** Privacy and consent page: processed on device, photos never uploaded, only use photos of people who are in on the joke.
4. **Home.** Rotating 3D hero head you can poke (Pie / Bonk / Scream / Clean), a big **Make a Big Head** button, both game modes, and your cast.
5. **Face Studio.** Pick or take a photo. You see the AI's face box and 76 landmarks appear on the photo as each step checks off. Then the new head appears in 3D: drag to spin, test expressions, name them, and add a hat, 3D hair or googly eyes.
6. **Match setup.** Pick two characters (custom or house) and choose **vs Computer** or **2 Players, 1 Phone**.
7. **Play**, then **Snap** a screenshot to share, or hit **Rematch**.

### House cast (default characters)
Grandpa Gus · Aunt Linda · Coach Brick · Baby Benny · Disco Dolores · Sir Reginald. Their faces are painted procedurally into the same texture layout a photo uses, so they share every system with player-made heads.

### Game modes (built)
| Mode | What happens | Face reactions used |
|---|---|---|
| **Slap Champs** | Turn-based slap contest, 6 slaps. Stop the power needle in the gold zone. A perfect slap plays in slow motion with a close-up. 100 HP each; a KO topples the loser. | sideways cheek skew, puff, jaw drop, neck wobble, sweat spray |
| **Dunk Tank** | A crosshair drifts over a target. Hit the bullseye and the person on the plank drops into the water and comes up soaked (glossy, darker, dripping). Five balls each, then the roles swap. | "oh no" jaw drop, smug cheek puff on a miss, wet skin |
| **Whack-a-Head** | 30 seconds. Faces pop out of a 3×3 board; tap to bonk. Golden heads +3, bonking Baby Benny −2. Your own face pops up most. Best score is saved. | squish, wobble, stars |
| **The Pie-Q Test** | Game-show trivia, 6 questions, alternating turns. Right answer: the pie hits your opponent. Wrong answer or timeout: it hits you. Cream accumulates. Fewest pies wins; ties mean pies for everyone. | jaw-drop "oh no" before impact, pancake squish, wobble, cream raycast onto the face, tin slides off |
| **Bobble Boxing** | 60-second bout. Jab / Hook / Uppercut buttons, hold BLOCK. CPU opponent reads your punches sometimes. K.O. = head spins and the boxer topples. 2P mode splits the controls left/right. | sideways skew on hooks, cheek puff, uppercut jaw-drop, spring-wobble on the neck, stars and sweat |

## How the face becomes a 3D head (on device)

```
photo ─► Vision: 76 landmarks + person segmentation
      ─► similarity align (pupils → fixed texture spots, proportions preserved)
      ─► 1024² face texture: photo × (person mask · feathered oval) over sampled skin/hair fill
      ─► HeadMeshBuilder: 13k-vertex head sculpted to THIS face's jawline, nose, mouth, chin
      ─► 5 blend shapes (squish, mouthOpen, puff, skewLeft, skewRight) + bobblehead wobble
```

**Realism details:** ears shaped and coloured from the person's skin tone, glossy corneas so the eyes catch light, a skin-pore normal map with a light clear-coat sheen, hair-strand texture on the crown and back (hair colour detected from the photo), proportioned bodies with arms and legs, soft shadows, and a **Big heads / Real heads** setting (home screen, top right) for cartoon or realistic proportions.

**Web prototype extra:** the browser version also uses MediaPipe's 478 *3D* landmarks to give each face its real depth (nose, brow, eye sockets, cheeks). It fits the AI depth to the head template with least squares and spreads the difference over a smoothed grid. The iOS app doesn't have that yet: Apple's Vision only gives 2D landmarks, so iOS needs the MediaPipe iOS SDK or a server-side 3D fit (see the roadmap).

The key idea: the photo is never stretched to fit a generic head. The **head is bent to fit the photo**. Skull rings follow the measured face contour. A relief field places brow ridge, eye sockets, cheekbones, nose ridge and tip, lips and chin at the person's own landmark positions. UVs come from the same frontal projection the texture uses, so the photo's nose lands on the mesh's nose.

| File | Role |
|---|---|
| `Face/FaceAnalyzer.swift` | Vision landmarks (rev 3), pupils, nose, lips, contour; person segmentation |
| `Face/FaceTextureBuilder.swift` | CoreImage alignment, masking, skin/hair sampling, composite |
| `Face/FaceShape.swift` | Shared texture-space face model; standard shape; sanity clamps |
| `Face/HeadMeshBuilder.swift` | The head sculptor and blend shapes |
| `Scenes/HeadRig.swift` | Live head: morph animation, wobble physics, cream splats raycast onto the mesh |
| `Scenes/Accessories.swift` | Hats, 3D hair volumes, googly eyes, torso |
| `Scenes/PieThrower.swift`, `Effects.swift` | Pie arc and impact, particles, lights, camera shake |
| `Scenes/Bodies.swift` | Proportioned bodies, `Contestant` (head + body), head-size setting |
| `Face/HairStrands.swift` | Hair-strand texture painter |
| `Games/*` | Pie-Q Test, trivia bank, Bobble Boxing, Slap Champs, Dunk Tank, Whack-a-Head |
| `Views/*` | Intro/demo, Home, Face Studio, Cast, Match setup, game screens |

## Play it on your iPhone
- **One command on your Mac:** plug in your iPhone (tap Trust, turn on Developer Mode), make sure Xcode is signed in with your Apple ID, then run
  `cd ~/big-head-party && git pull && ./scripts/install-on-iphone.sh`. It builds, signs, installs and launches the game.
- **TestFlight (recommended, no Mac needed):** follow [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md). GitHub Actions signs the app with your Apple Developer account and uploads it. You install it from the TestFlight app and can invite family.
- **Every push to `main`** is compiled on a macOS runner (`.github/workflows/ios-build.yml`). The run launches the app in an iPhone Simulator, screenshots every screen and produces an unsigned `.ipa` you can sideload with Sideloadly or AltStore.

## Build & run

Requires a Mac with **Xcode 16 or newer**, and iOS 17+ on the device or simulator.

1. Open `BigHeadParty.xcodeproj`. It uses Xcode 16's synchronized folders, so every file in `BigHeadParty/` is included automatically.
2. Select the **BigHeadParty** target → *Signing & Capabilities* → choose your team (bundle id: `com.domqinvestments.bigheadparty`).
3. Run on a **real iPhone** for the best results. Vision's person segmentation and the camera aren't available in the Simulator. Without segmentation the app still works and shows a warning that edges may be busy.

If the project file gives you trouble, regenerate it with XcodeGen: `brew install xcodegen && xcodegen` (spec in `project.yml`).

### What was verified here, and what wasn't
This was written in a Linux container with no Xcode or iOS SDK, so **the iOS app has not been compiled or run yet.**
- All Swift files pass the Swift 6 parser (`swiftc -parse`).
- The head sculptor (`HeadMeshBuilder` + `FaceShape`) was compiled on Linux against a SceneKit shim. Its meshes were exported and rendered (base, wide-jaw and baby shapes, plus all five blend shapes). No NaNs, watertight, sensible proportions.
- The same algorithm, ported to JavaScript in `web-prototype/`, was run end-to-end on a real photo in headless Chromium: MediaPipe landmarks → aligned texture → sculpted head → squish/jaw-drop/splat → game show.
- Expect a few compile fixes on the first Xcode build: typical API-signature nits that need the real SDK to catch.

## Web prototype

`web-prototype/index.html` is the same pipeline in a single page: MediaPipe Face Landmarker (478 3D points) + selfie segmentation → the ported head sculptor with per-person depth → three.js. It includes the attract demo, Face Studio (Pie / Squish / Bonk / Puff / Yell, hats, googly eyes), and four games: The Pie-Q Test, Slap Champs, Dunk Tank and Whack-a-Head. If the AI can't load, it falls back to tap-to-place (eyes, mouth, chin).

Run locally:
```bash
cd web-prototype
./fetch-models.sh          # optional: local copies of the MediaPipe wasm/models (otherwise CDN)
python3 -m http.server 8000   # then open http://localhost:8000
```

## Roadmap
- **Realism:** bring the web prototype's per-person 3D depth to iOS (MediaPipe iOS SDK, or a server-side FLAME/3DMM fit). Inpainting for the sides and back of the head. Real teeth/tongue inside the mouth for the jaw-drop.
- **Modes:** Bobble Kart, Bobble Sumo, Wedding Cake Wars (see `docs/GAME_IDEAS.md`).
- **Juice:** sound effects and a host voice, slow-motion replays, a share-video export, custom trivia ("How old is Uncle Ray?").
- **Store readiness:** consent checkbox on upload, report/delete flow, app icon, privacy nutrition label (on-device only).
