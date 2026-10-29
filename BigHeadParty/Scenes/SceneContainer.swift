import SwiftUI
import SceneKit

/// Hosts an SCNView in SwiftUI and hands the view back so games can take snapshots.
struct SceneContainer: UIViewRepresentable {
    let scene: SCNScene
    var pointOfView: SCNNode?
    var allowsCameraControl = false
    var onViewCreated: ((SCNView) -> Void)?
    /// Called with the tap location (in view points) and the view, for games that need hit-testing.
    var onTap: ((CGPoint, SCNView) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var onTap: ((CGPoint, SCNView) -> Void)?
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let view = g.view as? SCNView else { return }
            onTap?(g.location(in: view), view)
        }
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = scene
        view.pointOfView = pointOfView
        view.allowsCameraControl = allowsCameraControl
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        if allowsCameraControl {
            view.defaultCameraController.interactionMode = .orbitTurntable
            view.defaultCameraController.inertiaEnabled = true
            view.defaultCameraController.maximumVerticalAngle = 35
            view.defaultCameraController.minimumVerticalAngle = -20
        }
        if onTap != nil {
            context.coordinator.onTap = onTap
            view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        }
        onViewCreated?(view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        if view.scene !== scene { view.scene = scene }
        if let pointOfView, view.pointOfView !== pointOfView { view.pointOfView = pointOfView }
    }
}
