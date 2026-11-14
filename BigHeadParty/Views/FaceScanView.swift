import SwiftUI

/// The Face ID-style scan: look straight, turn one way, turn the other. The camera takes each
/// photo itself when the pose is right, and the ring round the face fills in as it goes.
struct FaceScanView: View {
    /// The front photo (with its depth, when measured) and the side photos that were taken.
    let onDone: (UIImage, FaceDepth?, [UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = GuidedCamera()
    @State private var finished = false
    @State private var flash = 0.0

    var body: some View {
        ZStack {
            // Kept dark on purpose: a bright screen would tint the selfie.
            Theme.deep.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Button {
                        finished = true   // closing cancels, even in the moment after the last photo
                        dismiss()
                    } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.horizontal)

                Label(camera.hint.text, systemImage: camera.hint.symbol)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .pill(camera.hint.ready ? Theme.lime : Theme.surface)
                    .id(camera.hint.text)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .accessibilityAddTraits(.updatesFrequently)

                GeometryReader { geo in
                    let o = GuidedCamera.oval
                    ZStack(alignment: .topLeading) {
                        CameraPreview(session: camera.session)
                        ring
                            .frame(width: o.width * geo.size.width, height: o.height * geo.size.height)
                            .offset(x: o.minX * geo.size.width, y: o.minY * geo.size.height)
                        if let count = camera.scanCountdown {
                            Text("\(count)")
                                .font(.system(size: 120, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.surface)
                                .shadow(color: .black.opacity(0.5), radius: 8)
                                .frame(width: o.width * geo.size.width, height: o.height * geo.size.height)
                                .offset(x: o.minX * geo.size.width, y: o.minY * geo.size.height)
                                .id(count)
                                .transition(.scale(scale: 1.4).combined(with: .opacity))
                                .accessibilityLabel("Taking the photo in \(count)")
                        }
                        Color.white.opacity(flash).allowsHitTesting(false)
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.surface.opacity(0.6), lineWidth: 3))
                .padding(.horizontal, 10)
                .animation(.easeOut(duration: 0.2), value: camera.scanCountdown)

                HStack(spacing: 8) {
                    stepPill("Front", index: 0)
                    stepPill("One side", index: 1)
                    stepPill("Other side", index: 2)
                }

                Spacer(minLength: 0)
                HStack {
                    Color.clear.frame(width: 110, height: 44)
                    Spacer()
                    Button { camera.scanShutter() } label: {
                        // A backup only: the scan takes every photo by itself.
                        ZStack {
                            Circle().fill(Theme.surface.opacity(0.25)).frame(width: 48, height: 48)
                            Image(systemName: "camera.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.surface)
                        }
                    }
                    .accessibilityLabel("Take this photo now")
                    Spacer()
                    Button("Skip sides") { finish() }
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.surface)
                        .frame(width: 110, height: 44)
                        .opacity(canSkip ? 1 : 0)
                        .disabled(!canSkip)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .padding(.top, 8)

            if camera.denied { CameraDeniedCard() }
        }
        .onAppear {
            camera.beginScan()
            #if DEBUG
            // `-studioScan N`: layout check with N photos taken and no camera (simulator).
            if UserDefaults.standard.object(forKey: "studioScan") != nil {
                camera.debugScan(step: UserDefaults.standard.integer(forKey: "studioScan"))
                return
            }
            #endif
            camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.scanCountdown) { _, count in
            if count != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        .onChange(of: camera.scanStep) { _, step in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash = 0.7
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
            if step == .done {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { finish() }
            }
        }
    }

    /// The front photo is in, so the sides are optional from here.
    private var canSkip: Bool { camera.scanStep == .firstSide || camera.scanStep == .secondSide }

    private func finish() {
        guard !finished, let front = camera.scanFront else { return }
        finished = true
        onDone(front.image, front.depth, camera.scanSides)
        dismiss()
    }

    // MARK: Ring

    private enum Mark { case waiting, next, done }

    /// Four arcs round the face: top and bottom for the front photo, left and right for the
    /// sides. The side arc that fills is the one the head was turned toward.
    private var ring: some View {
        let step = camera.scanStep.rawValue
        let front: Mark = step > 0 ? .done : .next
        func side(_ direction: Double) -> Mark {
            switch step {
            case 0: return .waiting
            case 1: return .next
            case 2: return camera.scanTurn == direction ? .done : .next
            default: return .done
            }
        }
        // A side that's still to do fills from its middle as the head turns toward it.
        func filling(_ direction: Double, center: Double) -> some View {
            let amount = side(direction) == .next ? max(0, camera.scanTurnNow * direction) : 0
            return OvalArc(start: center - 50 * amount, end: center + 50 * amount)
                .stroke(Theme.success, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .opacity(amount > 0.05 ? 1 : 0)
                .animation(.linear(duration: 0.1), value: amount)
        }
        return ZStack {
            arc(235, 305, front)
            arc(55, 125, front)
            arc(-50, 50, side(1))
            arc(130, 230, side(-1))
            filling(1, center: 0)
            filling(-1, center: 180)
        }
    }

    private func arc(_ start: Double, _ end: Double, _ mark: Mark) -> some View {
        OvalArc(start: start, end: end)
            .stroke(mark == .done ? Theme.success : (mark == .next ? Theme.butter : Theme.surface.opacity(0.35)),
                    style: StrokeStyle(lineWidth: mark == .done ? 7 : 4, lineCap: .round, dash: mark == .done ? [] : [10, 9]))
            .animation(.easeOut(duration: 0.25), value: mark)
    }

    private func stepPill(_ title: String, index: Int) -> some View {
        let step = camera.scanStep.rawValue
        let done = step > index
        return Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .pill(done ? Theme.lime : Theme.surface)
            .opacity(done || step == index ? 1 : 0.55)
            .accessibilityLabel(done ? "\(title), done" : title)
    }
}

/// Part of an oval's outline. Degrees, 0 at the right, clockwise on screen.
private struct OvalArc: Shape {
    var start: Double
    var end: Double

    func path(in rect: CGRect) -> Path {
        var unit = Path()
        unit.addArc(center: CGPoint(x: 0.5, y: 0.5), radius: 0.5, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        return unit.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}
