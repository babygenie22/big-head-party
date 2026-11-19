import SwiftUI

/// The face scan: hold your face in the circle, then look to one side and the other. There is
/// no shutter button. The camera takes each photo itself, the ring round the circle fills as
/// you go, and the photos drop into the three slots underneath.
struct FaceScanView: View {
    /// The front photo (with its depth, when measured) and the side photos that were taken.
    let onDone: (UIImage, FaceDepth?, [UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var camera = GuidedCamera()
    @State private var finished = false
    @State private var flash = 0.0

    var body: some View {
        ZStack {
            // Kept dark on purpose: a bright screen would tint the selfie.
            Theme.deep.ignoresSafeArea()
            VStack(spacing: 0) {
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

                Spacer(minLength: 12)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.party(26))
                        .foregroundStyle(Theme.surface)
                        .multilineTextAlignment(.center)
                        .id(title)
                        .transition(.opacity)
                    Text(correction)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.butter)
                        .frame(height: 22)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                .padding(.horizontal, 24)
                .animation(.easeOut(duration: 0.2), value: title)

                Spacer(minLength: 16)
                viewfinder
                    .padding(.horizontal, 30)

                Spacer(minLength: 20)
                HStack(spacing: 18) {
                    slot("Front", index: 0)
                    slot("Side", index: 1)
                    slot("Side", index: 2)
                }

                Spacer(minLength: 12)
                Button("Skip the sides") { finish() }
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.surface.opacity(0.8))
                    .frame(height: 44)
                    .opacity(canSkip ? 1 : 0)
                    .disabled(!canSkip)
                    .padding(.bottom, 10)
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
        .onChange(of: camera.scanStep) { _, step in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash = 0.85
            withAnimation(.easeOut(duration: 0.4)) { flash = 0 }
            if step == .done {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { finish() }
            }
        }
    }

    // MARK: Words

    private var title: String {
        switch camera.scanStep {
        case .front: return "Look straight ahead"
        case .firstSide: return "Slowly turn your head to one side"
        case .secondSide: return "Now slowly turn the other way"
        case .done: return "All done!"
        }
    }

    /// What to fix, when something is in the way. Empty while things are going well, and when
    /// the hint only repeats the title.
    private var correction: String {
        let hint = camera.hint
        if camera.scanStep == .done || hint.ready || hint.text == title { return "" }
        return hint.text
    }

    /// The front photo is in, so the sides are optional from here.
    private var canSkip: Bool { camera.scanStep == .firstSide || camera.scanStep == .secondSide }

    private func finish() {
        guard !finished, let front = camera.scanFront else { return }
        finished = true
        onDone(front.image, front.depth, camera.scanSides)
        dismiss()
    }

    // MARK: Viewfinder

    /// The live picture in a circle, zoomed so the face fills it, with the progress ring round it.
    private var viewfinder: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                CameraPreview(session: camera.session)
                    .frame(width: d * 1.3, height: d * 1.3 * 4 / 3)
                    .frame(width: d, height: d)
                    .clipShape(Circle())
                Circle().fill(Color.white.opacity(flash)).frame(width: d, height: d).allowsHitTesting(false)
                if camera.scanStep == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: d * 0.3, weight: .heavy))
                        .foregroundStyle(Theme.surface)
                        .shadow(color: .black.opacity(0.45), radius: 10)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                }
                ring.frame(width: d + 22, height: d + 22)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(duration: 0.35), value: camera.scanStep)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// One ring, three jobs. Front: it sweeps round from the top while the face is held in
    /// place. Sides: each half fills from its middle as the head turns toward it, and stays
    /// filled once that side's photo is taken.
    private var ring: some View {
        let step = camera.scanStep
        // How full each half is (0…1). `scanTurn` is the way the first side photo was turned.
        func half(_ direction: Double) -> Double {
            switch step {
            case .front: return 0
            case .firstSide: return max(0, camera.scanTurnNow * direction)
            case .secondSide: return camera.scanTurn == direction ? 1 : max(0, camera.scanTurnNow * direction)
            case .done: return 1
            }
        }
        let line = StrokeStyle(lineWidth: 7, lineCap: .round)
        return ZStack {
            Circle().stroke(Theme.surface.opacity(0.22), lineWidth: 7)
            if step == .front {
                Circle().trim(from: 0, to: camera.scanHold)
                    .stroke(Theme.success, style: line)
                    .rotationEffect(.degrees(-90))
            } else {
                // Right half is centered on 0 (trim runs clockwise from the right), left on 0.5.
                Circle().trim(from: 0, to: 0.25 * half(1)).stroke(Theme.success, style: line)
                Circle().trim(from: 1 - 0.25 * half(1), to: 1).stroke(Theme.success, style: line)
                Circle().trim(from: 0.5 - 0.25 * half(-1), to: 0.5 + 0.25 * half(-1)).stroke(Theme.success, style: line)
            }
        }
        .animation(.linear(duration: 0.12), value: camera.scanHold)
        .animation(.linear(duration: 0.12), value: camera.scanTurnNow)
        .accessibilityHidden(true)
    }

    // MARK: Photos taken

    private func slot(_ label: String, index: Int) -> some View {
        let photo = index < camera.scanThumbs.count ? camera.scanThumbs[index] : nil
        let current = camera.scanStep.rawValue == index
        return VStack(spacing: 6) {
            ZStack {
                Circle().fill(Theme.surface.opacity(0.1))
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Image(systemName: index == 0 ? "face.smiling" : "arrow.left.and.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.surface.opacity(current ? 0.9 : 0.35))
                }
                Circle().strokeBorder(photo != nil ? Theme.success : Theme.surface.opacity(current ? 0.9 : 0.25), lineWidth: 3)
            }
            .frame(width: 60, height: 60)
            .overlay(alignment: .bottomTrailing) {
                if photo != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.success, Theme.surface)
                        .offset(x: 3, y: 3)
                }
            }
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.surface.opacity(photo != nil || current ? 1 : 0.5))
        }
        .animation(.spring(duration: 0.35), value: camera.scanThumbs.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(photo != nil ? "\(label) photo taken" : "\(label) photo to do")
    }
}
