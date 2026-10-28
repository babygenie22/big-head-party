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
| `Games/*` | Pie-Q Test stage and logic, trivia bank, Bobble Boxing |
| `Views/*` | Intro/demo, Home, Face Studio, Cast, Match setup, game screens |

## Build & run

Requires a Mac with **Xcode 16 or newer**, and iOS 17+ on the device or simulator.

1. Open `BigHeadParty.xcodeproj`. It uses Xcode 16's synchronized folders, so every file in `BigHeadParty/` is included automatically.
2. Select the **BigHeadParty** target → *Signing & Capabilities* → choose your team (and change the bundle id `com.example.bigheadparty` if needed).
3. Run on a **real iPhone** for the best results. Vision's person segmentation and the camera aren't available in the Simulator. Without segmentation the app still works and shows a warning that edges may be busy.

If the project file gives you trouble, regenerate it with XcodeGen: `brew install xcodegen && xcodegen` (spec in `project.yml`).

### What was verified here, and what wasn't
This was written in a Linux container with no Xcode or iOS SDK, so **the iOS app has not been compiled or run yet.**
- All Swift files pass the Swift 6 parser (`swiftc -parse`).
- The head sculptor (`HeadMeshBuilder` + `FaceShape`) was compiled on Linux against a SceneKit shim. Its meshes were exported and rendered (base, wide-jaw and baby shapes, plus all five blend shapes). No NaNs, watertight, sensible proportions.
- The same algorithm, ported to JavaScript in `web-prototype/`, was run end-to-end on a real photo in headless Chromium: MediaPipe landmarks → aligned texture → sculpted head → squish/jaw-drop/splat → game show.
- Expect a few compile fixes on the first Xcode build: typical API-signature nits that need the real SDK to catch.

## Web prototype

`web-prototype/index.html` is the same pipeline in a single page: MediaPipe Face Landmarker (478 points) + selfie segmentation → the ported head sculptor → three.js, with the attract demo, Face Studio (Pie / Squish / Bonk / Puff / Yell, hats, googly eyes) and a 6-question Pie-Q Test. If the AI can't load, it falls back to tap-to-place (eyes, mouth, chin).

Run locally:
```bash
cd web-prototype
./fetch-models.sh          # optional: local copies of the MediaPipe wasm/models (otherwise CDN)
python3 -m http.server 8000   # then open http://localhost:8000
```

## Roadmap
- **Realism:** MediaPipe's 478-point 3D landmarks on iOS for per-person depth. Server-side FLAME/3DMM fitting for accurate head shape. Inpainting for the ears, sides and back of the head.
- **Modes:** Slap Champs, Dunk Tank Derby, Whack-a-Relative, Wedding Cake Wars (see `docs/GAME_IDEAS.md`).
- **Juice:** sound effects and a host voice, slow-motion replays, a share-video export, custom trivia ("How old is Uncle Ray?").
- **Store readiness:** consent checkbox on upload, report/delete flow, app icon, privacy nutrition label (on-device only).
