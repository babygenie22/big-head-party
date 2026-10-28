import SwiftUI
import SceneKit

/// Hosts an SCNView in SwiftUI and hands the view back so games can take snapshots.
struct SceneContainer: UIViewRepresentable {
    let scene: SCNScene
    var pointOfView: SCNNode?
    var allowsCameraControl = false
    var onViewCreated: ((SCNView) -> Void)?

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
        onViewCreated?(view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene { view.scene = scene }
        if let pointOfView, view.pointOfView !== pointOfView { view.pointOfView = pointOfView }
    }
}
