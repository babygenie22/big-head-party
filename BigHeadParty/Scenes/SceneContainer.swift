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
        let view = FramingSCNView(frame: .zero)
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
        view.setNeedsLayout()
    }
}

/// Every scene was framed (in the web prototype) for a 4:4.3 viewport, with a vertical field of view.
/// A full-screen portrait phone is about half that wide, so a vertical FOV crops the sides away.
/// This keeps the whole designed frame visible: on views narrower than the design, the camera holds
/// the designed *width* instead of the height.
final class FramingSCNView: SCNView {
    static let designAspect: CGFloat = 4.0 / 4.3
    /// Extra width on narrow screens, so things at the edge of the designed frame don't touch the bezel.
    static let narrowMargin: CGFloat = 1.08
    private var designFOV: [ObjectIdentifier: CGFloat] = [:]

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let camera = pointOfView?.camera, bounds.width > 0, bounds.height > 0 else { return }
        let base = designFOV[ObjectIdentifier(camera)] ?? camera.fieldOfView
        designFOV[ObjectIdentifier(camera)] = base
        if bounds.width / bounds.height >= Self.designAspect {
            camera.projectionDirection = .vertical
            camera.fieldOfView = base
        } else {
            let halfV = base * .pi / 360
            camera.projectionDirection = .horizontal
            camera.fieldOfView = 2 * atan(tan(halfV) * Self.designAspect * Self.narrowMargin) * 180 / .pi
        }
    }
}
