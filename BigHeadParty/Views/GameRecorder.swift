import SwiftUI
import ReplayKit

/// Records the game screen (with its sound) so players can share the carnage. Stopping opens
/// Apple's preview, where they trim, save to Photos or share. ReplayKit asks for permission itself.
final class GameRecorder: NSObject, ObservableObject, RPPreviewViewControllerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed = 0
    @Published var failure: String?
    private var timer: Timer?

    var isAvailable: Bool { RPScreenRecorder.shared().isAvailable }

    func toggle() { isRecording ? stop() : start() }

    func start() {
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false
        recorder.startRecording { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    // The user tapping "Don't Allow" isn't worth an alert.
                    if (error as NSError).code != RPRecordingErrorCode.userDeclined.rawValue {
                        self.failure = error.localizedDescription
                    }
                    return
                }
                self.isRecording = true
                self.elapsed = 0
                self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.elapsed += 1 }
            }
        }
    }

    /// Stops and shows the preview (also used when the game closes mid-recording).
    func stop() {
        guard isRecording else { return }
        isRecording = false
        timer?.invalidate()
        timer = nil
        RPScreenRecorder.shared().stopRecording { [weak self] preview, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let preview else {
                    self.failure = error?.localizedDescription ?? "The recording couldn't be saved."
                    return
                }
                preview.previewControllerDelegate = self
                preview.modalPresentationStyle = .fullScreen
                Self.topViewController()?.present(preview, animated: true)
            }
        }
    }

    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        previewController.dismiss(animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

/// Small record button that sits over every game.
struct RecordButton: View {
    @ObservedObject var recorder: GameRecorder
    @State private var pulse = false

    var body: some View {
        Button { recorder.toggle() } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    
                    .opacity(recorder.isRecording && pulse ? 0.3 : 1)
                Text(recorder.isRecording ? String(format: "%d:%02d", recorder.elapsed / 60, recorder.elapsed % 60) : "REC")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .monospacedDigit()
                if recorder.isRecording { Image(systemName: "stop.fill").font(.caption2) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .pill(recorder.isRecording ? Theme.coral : Theme.surface)
        }
        .foregroundStyle(Theme.ink)
        .accessibilityLabel(recorder.isRecording ? "Stop recording and share" : "Record this game")
        .onChange(of: recorder.isRecording) { _, on in
            pulse = false
            if on { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { pulse = true } }
        }
        .alert("Recording problem", isPresented: Binding(get: { recorder.failure != nil }, set: { if !$0 { recorder.failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.failure ?? "")
        }
    }
}
