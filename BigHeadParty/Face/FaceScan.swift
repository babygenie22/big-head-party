import CoreGraphics

/// The Face ID-style scan: one camera session that takes the front photo and a photo of each
/// side with no button. Center your face and a short countdown takes the front photo; then
/// turn your head slowly one way and the other, and each side is taken as the head passes
/// through the right angle, without stopping. Pure bookkeeping, no camera: `GuidedCamera`
/// feeds it readings and takes the photos.
struct FaceScan {
    enum Step: Int { case front, firstSide, secondSide, done }

    /// What Vision saw in one frame. `box` is normalized, top-left origin, as shown on screen;
    /// positive `yaw` means the nose points to the right of the picture.
    struct Reading {
        var box: CGRect?
        var yaw = 0.0
        var roll = 0.0
        var brightness = 0.5
    }

    private(set) var step: Step = .front
    /// Which way the head was turned for the first side photo (+1: nose to the right of the
    /// picture). The second side photo must be turned the other way.
    private(set) var firstTurn = 0.0
    /// 3, 2, 1 while the face is centered and the front photo is about to be taken.
    private(set) var countdown: Int?
    /// How far the head is turned toward a side photo right now: −1 (far enough, to the left
    /// of the picture) … 0 (facing the camera) … +1 (far enough, to the right).
    private(set) var turn = 0.0

    /// How far a side photo is turned (Vision's yaw, radians): far enough to show the cheek and
    /// jaw, not so far that the far eye disappears and the photo can't be lined up.
    static let turnRange = 0.5...1.0
    /// Seconds per countdown number, and how many numbers.
    static let countStep = 0.7
    static let counts = 3
    /// The countdown survives the face slipping out of place for this long (a blink, a wobble).
    static let grace = 0.5
    /// Turning faster than this (radians a second) would blur the photo.
    static let tooFast = 1.0
    /// A photo that never comes back (camera interrupted) stops blocking the scan after this.
    static let photoTimeout = 6.0

    private var centeredSince: Double?
    private var lastGood = 0.0
    private var lastYaw = 0.0
    private var lastTime = 0.0
    private var busyUntil = 0.0
    private var pendingTurn = 0.0

    /// One look at the live picture. Returns what to tell the person, and whether to take the
    /// photo now.
    mutating func look(_ r: Reading, now: Double) -> (hint: GuidedCamera.Hint, shoot: Bool) {
        typealias Hint = GuidedCamera.Hint
        let speed = lastTime > 0 && now > lastTime ? abs(r.yaw - lastYaw) / (now - lastTime) : 0
        lastYaw = r.yaw
        lastTime = now
        turn = r.box == nil || step == .front ? 0 : max(-1, min(1, r.yaw / Self.turnRange.lowerBound))
        guard step != .done else { return (Hint(text: "All done!", symbol: "checkmark.circle.fill", ready: true), false) }
        if now < busyUntil { return (Hint(text: step == .front ? "Hold still…" : "Got it…", symbol: "camera.fill", ready: true), false) }

        if step == .front {
            let problem = frontProblem(r)
            if problem == nil {
                lastGood = now
                if centeredSince == nil { centeredSince = now }
            } else if now - lastGood > Self.grace {
                centeredSince = nil
            }
            guard let since = centeredSince else {
                countdown = nil
                return (problem ?? Hint(text: "Put your face in the oval", symbol: "face.dashed"), false)
            }
            let passed = Int((now - since) / Self.countStep)
            if passed >= Self.counts {
                begin(turn: 0, now: now)
                return (Hint(text: "Hold still…", symbol: "camera.fill", ready: true), true)
            }
            countdown = Self.counts - passed
            return (Hint(text: "Hold still…", symbol: "checkmark.circle.fill", ready: true), false)
        }

        // Sides: taken on the move, the moment the head is turned far enough.
        guard let box = r.box, box.width > 0.2 else { return (Hint(text: "Keep your face in view", symbol: "face.dashed"), false) }
        let oval = GuidedCamera.oval
        if abs(box.midX - oval.midX) > 0.2 || abs(box.midY - (oval.minY + oval.height * 0.55)) > 0.2 {
            return (Hint(text: "Keep your face in the oval", symbol: "viewfinder"), false)
        }
        let want = wantedTurn(yaw: r.yaw)
        let amount = r.yaw * want
        if amount < Self.turnRange.lowerBound {
            if step == .secondSide {
                return (Hint(text: "Now slowly turn the other way", symbol: want > 0 ? "arrow.right" : "arrow.left"), false)
            }
            return (Hint(text: "Slowly turn your head to one side", symbol: "arrow.left.and.right"), false)
        }
        if amount > Self.turnRange.upperBound { return (Hint(text: "Turn back a little", symbol: "eye"), false) }
        if speed > Self.tooFast { return (Hint(text: "A little slower", symbol: "tortoise.fill"), false) }
        begin(turn: want, now: now)
        return (Hint(text: "Got it…", symbol: "camera.fill", ready: true), true)
    }

    /// The backup shutter button: take the current step's photo now, whatever the pose.
    mutating func force(now: Double) -> Bool {
        guard step != .done, now >= busyUntil else { return false }
        begin(turn: step == .front ? 0 : wantedTurn(yaw: lastYaw), now: now)
        return true
    }

    /// The photo arrived: on to the next pose.
    mutating func shot() {
        busyUntil = 0
        switch step {
        case .front: step = .firstSide
        case .firstSide: firstTurn = pendingTurn; step = .secondSide
        case .secondSide, .done: step = .done
        }
    }

    /// The photo failed: same pose again.
    mutating func missed() {
        busyUntil = 0
    }

    private mutating func begin(turn: Double, now: Double) {
        pendingTurn = turn
        countdown = nil
        centeredSince = nil
        busyUntil = now + Self.photoTimeout
    }

    /// The first side can be either way; the second is the opposite of the first.
    private func wantedTurn(yaw: Double) -> Double {
        step == .secondSide ? -firstTurn : (yaw >= 0 ? 1 : -1)
    }

    /// What stops the front photo, if anything. Looser than the single-photo coaching: the
    /// scan should start counting as soon as the face is roughly in place.
    private func frontProblem(_ r: Reading) -> GuidedCamera.Hint? {
        typealias Hint = GuidedCamera.Hint
        guard let box = r.box else { return Hint(text: "Put your face in the oval", symbol: "face.dashed") }
        if box.width < 0.3 { return Hint(text: "Move closer", symbol: "plus.magnifyingglass") }
        if box.width > 0.72 { return Hint(text: "Back up a little", symbol: "minus.magnifyingglass") }
        let oval = GuidedCamera.oval
        if abs(box.midX - oval.midX) > 0.13 || abs(box.midY - (oval.minY + oval.height * 0.55)) > 0.13 {
            return Hint(text: "Center your face in the oval", symbol: "viewfinder")
        }
        if abs(r.yaw) > 0.3 { return Hint(text: "Look straight at the camera", symbol: "eye") }
        if abs(r.roll) > 0.3 { return Hint(text: "Keep your head level", symbol: "level") }
        if r.brightness < 0.2 { return Hint(text: "Too dark — face a window or a lamp", symbol: "sun.max") }
        return nil
    }
}
