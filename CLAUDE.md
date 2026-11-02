# Big Head Party: notes for Claude Code

iOS party game. A photo of a friend becomes a 3D "big head" character that gets pied, slapped, dunked, bonked and boxed in five mini-games. SwiftUI + SceneKit + Apple Vision, iOS 17+, no third-party dependencies. Owner: Apple developer account `domqinvestments@gmail.com`. Bundle ID `com.domqinvestments.bigheadparty`. Repo `babygenie22/big-head-party` (public), branch `main`.

## Current status (handoff)
- The app compiles cleanly with Xcode 16.4 for the simulator and for devices (GitHub Actions `ios-build.yml` on every push to `main`).
- CI launches it in an iPhone simulator and screenshots every screen. The intro, home, Face Studio and all five games run with no crashes. Screenshots are in the `simulator-screenshots` artifact of each run.
- **Not yet done: running on a real iPhone.** The previous (cloud) session couldn't reach a Mac. **First job here: install it on the owner's iPhone** with `./scripts/install-on-iphone.sh`, fix any build, signing or runtime errors, then play-test every screen on the device.
- TestFlight is wired up (`.github/workflows/testflight.yml`, guide in `docs/TESTFLIGHT.md`) but the four repo secrets are not set yet. On a Mac that's signed into Xcode you can skip the secrets: Product → Archive in Xcode, then Distribute App → TestFlight. The app record must exist in App Store Connect first.

## Build / run / test
- Open `BigHeadParty.xcodeproj` (Xcode 16+). It uses synchronized folders (objectVersion 77): any file under `BigHeadParty/` is in the target automatically, with no pbxproj edits. There's a shared scheme `BigHeadParty`.
- Install on a plugged-in iPhone: `./scripts/install-on-iphone.sh`. It reads the team from Xcode's accounts (override with `TEAM_ID=...`), builds Release with automatic signing, then installs and launches through `xcrun devicectl`. The phone needs Developer Mode on.
- CLI simulator build: `xcodebuild -project BigHeadParty.xcodeproj -scheme BigHeadParty -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- **Debug-only launch arguments** (see `HomeView.startDebugScenarioIfRequested`):
  - `-hasSeenIntro YES` skips the intro.
  - `-demoGame pieShow|slap|dunk|whack|boxing` opens a game straight away.
  - `-studioTestImage /path/photo.jpg` runs Face Studio on that photo and writes `debug-texture.png`, `debug-landmarks.png` and `debug-shape.json` next to it.
  - `-headSize real|big` sets the head size.
- Swift 5 language mode. No strict concurrency and no default MainActor. Games are `ObservableObject` classes driven by `DispatchQueue.main` and `GameClock`.

## Architecture
- `Face/`: the photo → 3D head pipeline.
  - `FaceAnalyzer`: Vision landmarks (rev 3 → rev 2 → estimate from the face box if landmarks collapse) plus person segmentation.
  - `FaceTextureBuilder`: aligns the photo into a 1024² texture (pupils at fixed UVs), applies the mask, samples skin and hair colour, paints hair strands.
  - `HeadMeshBuilder`: sculpts a ~13k-vertex head to the person's jawline, nose, mouth and chin. Builds 5 morph targets: squish, mouthOpen, puff, skewLeft, skewRight.
  - `FaceShape`: texture-space face model.
- `Scenes/`:
  - `HeadRig`: the live head. Morph pulses, wobble, cream splats raycast onto the mesh, wet and golden looks.
  - `Accessories`: hats, hair volume, ears, corneas, googly eyes.
  - `Bodies`: `Contestant` = head + proportioned body. Also the `HeadSize` big/real setting.
  - `Effects`: particles, lights, camera, skin normal map, banners.
  - `PieThrower`, `ShowcaseStage`, and `SceneContainer` (SCNView in SwiftUI, with `onTap`).
- `Games/`: `PieShowGame` + `PieStage` + `Trivia` (The Pie-Q Test), `SlapGame` (+ `GameClock`), `DunkGame`, `WhackGame`, `BoxingGame`.
- `Views/`: Intro (attract demo), Home (game grid, cast, head-size menu), FaceStudio, Cast, MatchSetup + `GameHost`, PieShow, Boxing, MiniGameViews (Slap/Dunk/Whack).
- `Characters/`: `GameCharacter` / `CharacterMeta`, `CharacterStore` (custom faces saved to Documents as texture PNG + JSON; the original photo is never stored), and `DefaultCast` (6 procedurally painted house characters).
- `web-prototype/index.html`: the same pipeline in three.js + MediaPipe (478 3D landmarks with per-person depth), playable in a browser. MediaPipe model files go in `web-prototype/mp/` (git-ignored; `fetch-models.sh`).

## Known issues / next steps
1. **Real-device testing first.** Check Face Studio with real photos and the camera. On the CI simulator, Vision returned collapsed landmarks and an empty person mask; both have fallbacks now, but confirm a real iPhone uses the measured path (the estimate warning should *not* appear for a clear front-facing photo).
2. On the Slap Champs perfect slap, it's unverified whether setting `SCNAction.speed` on running actions (`setSlowMotion`) actually slows them. Perfect slaps are also choreographed slower, so the moment reads either way.
3. Per-person 3D face depth exists only in the web prototype (MediaPipe). For iOS, consider the MediaPipe iOS SDK or a server-side FLAME fit.
4. Store readiness:
   - Done: app icon, privacy manifest, `ITSAppUsesNonExemptEncryption = NO`, iPhone-only.
   - Still needed: a consent checkbox on photo upload, sound effects, App Store screenshots and metadata.
5. Game ideas still to build: `docs/GAME_IDEAS.md` (Bobble Kart, Bobble Sumo, Wedding Cake Wars).

## Conventions
- Commit messages: short imperative subject plus a body explaining why. Push to `main`, and CI runs on pushes that touch app code.
- Keep the web prototype's head sculptor (`buildHead` in `web-prototype/index.html`) in sync with `HeadMeshBuilder.swift` when changing the geometry.
- Never commit secrets. Signing goes through Xcode's account or the GitHub repo secrets in `docs/TESTFLIGHT.md`.
