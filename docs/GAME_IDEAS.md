# Big Head Party: game ideas & which genre fits best

The core hook: **your actual friend's face on a 3D character, reacting to slapstick.** Everything below is judged on one question: *how much screen time does the face get, and how funny is what happens to it?*

## What makes a face-swap game work

Principles drawn from what has already worked (JibJab's "Elf Yourself", Reface, Snapchat face swap, Mii-style avatars, and the classic "big head mode" cheat):

1. **The face must be big and on camera most of the time.** Full-body characters shrink faces to a few pixels in wide shots. Big-head proportions, close cameras and podiums that hide bodies keep the face as the star. This also lets us focus on faces and skip bodies, as planned.
2. **Physical comedy reads instantly.** Pies, slaps, wobble and squash-and-stretch are funny without explanation, and they stay family-friendly. Nobody needs to learn a combo system to laugh at Grandma getting pied.
3. **Rounds of 30 seconds to 3 minutes.** It's a pass-the-phone party game. Sessions end on a punchline, and the punchline is a screenshot.
4. **Every round should end in a shareable moment.** A slow-motion splat, a K.O. spin, a cream-covered face. Each one is a free ad for the app.
5. **Reactions beat realism.** A face that squishes, puffs and wobbles is funnier than a perfectly lit static face. The face mesh needs blend shapes (we built 5) more than it needs pores.
6. **Keep it consensual and kind.** Slapstick, not humiliation. No violence beyond cartoon level, and no adult content. App Store review is actively targeting face-swap/"nudify" misuse (Apple's Oct 2026 guideline update), so the content policy *is* the product strategy.

## The ideas (ranked)

| # | Idea | Face screen-time | Funny factor | Build cost | Party/2P | Verdict |
|---|------|:---:|:---:|:---:|:---:|---|
| 1 | **The Pie-Q Test**: game-show trivia; wrong answer = pie to the face | ★★★★★ | ★★★★★ | Low | ★★★★★ | **Built (v0.1).** Best fit. |
| 2 | **Bobble Boxing**: big-head boxers, wobbly heads, squishy punches | ★★★★☆ | ★★★★★ | Medium | ★★★★☆ | **Built (v0.1).** The "fighting game" pick. |
| 3 | **Dunk Tank**: throw balls at a target; hit it and your uncle drops into the water, hair soaked | ★★★★☆ | ★★★★☆ | Low | ★★★★☆ | **Built (v0.2).** |
| 4 | **Slap Champs**: turn-based slap contest; timing meter sets power, cheeks ripple in slow-mo | ★★★★★ | ★★★★★ | Low | ★★★★★ | **Built (v0.2).** The slow-mo face ripple is the whole joke |
| 5 | **Whack-a-Head**: family faces pop up out of holes; bonk with a foam hammer | ★★★★☆ | ★★★★☆ | Very low | ★★★☆☆ | **Built (v0.2).** Great casual/kids mode |
| 6 | **Wedding Cake Wars**: tag-team food fight at a wedding, cakes & spaghetti | ★★★★☆ | ★★★★☆ | Medium | ★★★★☆ | Seasonal and event-friendly (weddings, birthdays) |
| 7 | **Bobble Kart**: kart racing; the head sticks out of the kart and catches bugs and banana peels | ★★★☆☆ | ★★★☆☆ | High | ★★★★☆ | Fun, but faces get small at speed |
| 8 | **Talent Show Judges**: your friends sit as judges and react to your silly act (boo, cry, laugh) | ★★★★★ | ★★★☆☆ | Medium | ★★☆☆☆ | Good for "look at Dad's face" reaction memes |
| 9 | **Bobble Sumo**: shove each other out of a ring; heads bounce like balloons | ★★★☆☆ | ★★★★☆ | Medium | ★★★★★ | Great local multiplayer |
| 10 | **Mug Shot Soap Opera**: auto-generated dramatic soap-opera scenes starring your family (face close-ups + zoom + dun-dun-DUN) | ★★★★★ | ★★★★☆ | Low | ★★☆☆☆ | Viral content generator more than a game |

## Fighting game vs. game show, compared directly

You asked whether this works better as a fighting game (boxing) or a game show (pies). Short answer: **the game show is the better fit for the core hook, and boxing is the better *second* mode.** That's why both are built.

**Game show (pie-in-face)**
- ✅ The camera can sit 1–2 metres from a face the whole time. Contestants stand behind podiums, so bodies don't matter.
- ✅ Zero skill barrier. Grandma can play. Trivia gives the round a reason to happen.
- ✅ The pie is the perfect payoff: big, readable, harmless. The cream sticks around, so faces get messier as the game goes on.
- ✅ Turn-based, so pass-and-play on one phone works naturally.
- ⚠️ Needs a large question bank, or user-made questions ("How old is Uncle Ray?"), for replay value.

**Fighting game (boxing)**
- ✅ Instantly understood fantasy: "I'm going to box my brother."
- ✅ Hits drive face reactions (skew, squish, jaw drop, wobble) many times per minute, so it's very expressive.
- ⚠️ Needs a body, animation and game feel. We sidestep that with bobblehead proportions and a 3/4 camera that keeps both faces visible.
- ⚠️ "Punching a real person's face" needs a cartoon tone to stay fun rather than mean. Hence foam-looking gloves, stars, wobble and no blood. Keep it there.
- ⚠️ Real-time combat is harder to balance than trivia.

**Recommendation:** launch as a *party hub* ("Big Head Party") with the Pie-Q Test as the hero mode and Bobble Boxing as the second. Add Slap Champs and Dunk Tank next; both reuse existing systems (pie stage, morphs, wobble physics).

## How the 3D face works (and how to make it more realistic)

**Today (v0.1, fully on-device, no server):**
1. Apple Vision detects the face and 76 landmarks (`VNDetectFaceLandmarksRequest` rev 3), plus person segmentation to drop the background.
2. A similarity transform puts the pupils on fixed spots in a 1024² texture. Proportions are *not* warped, so the person still looks like themselves.
3. The **head sculptor** builds a 13k-vertex head whose jawline follows their face contour. Nose, lips, chin, brow and cheekbones are placed at *their* measured positions. UVs match the texture exactly, so their nose lands on the 3D nose.
4. Skin and hair colors sampled from the photo fill the sides, back and crown of the head.
5. Five blend shapes (squish, jaw-drop, cheek-puff, skew-left/right) plus bobblehead spring physics drive all reactions.

**Upgrade path for more realism**, in order of effort:
- **MediaPipe Face Landmarker (478 3D points).** Real per-person depth for nose, brow and cheeks instead of a parametric relief. On-device, free. (The web prototype in `/web-prototype` already uses it.)
- **FLAME / 3DMM fitting on a server.** Recent single-image methods (e.g. Pixel3DMM, 2025) recover accurate head shape. Most published methods are benchmarked on desktop GPUs, so plan on a cloud endpoint rather than on-device.
- **Image-to-3D head generators** (Gaussian-splat or mesh avatars, e.g. FastAvatar-style). Best realism, but ~30 s+ on a datacenter GPU and much heavier to animate. Better suited to a "premium portrait" feature than to every character.
- **Texture inpainting.** Use an image model to fill the sides and back of the head, and ears and hair, from the frontal photo instead of flat sampled colors.

## Must-haves before App Store submission

- Consent checkbox: "I have permission to use this person's photo." Plus an in-app report/delete flow.
- On-device processing is a selling point. Say so in the privacy nutrition label and keep it true (no photo upload in v1).
- Block obvious misuse: no nudity/body generation, no realistic violence. Pies, foam gloves and cartoon physics only.
- Handle minors carefully: kids' faces in the default cast are illustrated, not photos.
- Avoid trademarks: "Pie Face" is a Hasbro brand, hence **"The Pie-Q Test"**.
