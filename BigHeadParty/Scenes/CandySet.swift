import SceneKit
import UIKit

/// Shared pieces for the game sets in the app's "Candy studio" look: bright candy colors,
/// soft gradient backdrops, matte floors and rounded signs in the display face.
enum CandySet {
    // Mirrors Theme's candy palette for SceneKit.
    static let coral = UIColor(red: 1.0, green: 0.42, blue: 0.29, alpha: 1)
    static let sky = UIColor(red: 0.50, green: 0.78, blue: 1.0, alpha: 1)
    static let lime = UIColor(red: 0.73, green: 0.91, blue: 0.42, alpha: 1)
    static let bubblegum = UIColor(red: 1.0, green: 0.62, blue: 0.75, alpha: 1)
    static let lilac = UIColor(red: 0.79, green: 0.71, blue: 1.0, alpha: 1)
    static let butter = UIColor(red: 1.0, green: 0.85, blue: 0.42, alpha: 1)
    static let blush = UIColor(red: 1.0, green: 0.84, blue: 0.89, alpha: 1)
    static let cream = UIColor(red: 1.0, green: 0.957, blue: 0.925, alpha: 1)
    static let ink = UIColor(red: 0.169, green: 0.106, blue: 0.180, alpha: 1)
    static let player1 = UIColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1)
    static let player2 = UIColor(red: 1.0, green: 0.36, blue: 0.40, alpha: 1)

    /// Soft top-to-bottom wash for `scene.background`.
    static func backdrop(_ top: UIColor, _ bottom: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 512)).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
        }
    }

    /// Bright, soft studio lighting for a candy set: brighter ambient, gentler shadows, a pastel
    /// rim. Built on the shared studio rig so heads keep the look they have on the home screen.
    ///
    /// The shared camera pulls exposure down 0.7 stops to tame the bright rig, which also greys out
    /// unlit signs and backdrops. Here the camera runs at normal exposure and the lights are dimmed
    /// instead (auto exposure also used to darken these bright sets): lit surfaces keep their look,
    /// unlit ones show true colors.
    static func light(_ scene: SCNScene, rim: UIColor, camera: SCNNode, level: CGFloat = 0.42) {
        Effects.addStudioLights(to: scene, rim: rim, fill: UIColor(red: 1, green: 0.93, blue: 0.95, alpha: 1))
        let k = level   // 0.42 tuned by eye on photo and painted heads; brighter sets want less
        camera.camera?.exposureOffset = 0
        // Auto exposure darkened the bright sets; the vignette greyed their corners.
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.vignettingIntensity = 0
        scene.lightingEnvironment.intensity *= k
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let light = node.light else { return }
            light.intensity *= k
            switch light.type {
            case .ambient: light.intensity = 420 * k
            case .directional:
                light.shadowRadius = 12
                light.shadowSampleCount = 16
                light.shadowColor = UIColor(red: 0.35, green: 0.15, blue: 0.3, alpha: 0.22)
            default: break
            }
        }
    }

    /// Matte floor with the faintest sheen.
    static func floor(_ color: UIColor) -> SCNNode {
        let f = SCNFloor()
        f.reflectivity = 0.04
        f.reflectionFalloffEnd = 2
        let m = Accessories.material(color, roughness: 0.85)
        f.materials = [m]
        return SCNNode(geometry: f)
    }

    /// Rounded sign: candy pill with the title in Bricolage, plus a soft drop shadow, on a
    /// transparent plane that ignores scene lighting.
    static func sign(_ text: String, fill: UIColor, ink: UIColor = CandySet.ink, width: CGFloat = 7) -> SCNNode {
        let size = CGSize(width: 1024, height: 280)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let plate = UIBezierPath(roundedRect: CGRect(x: 40, y: 40, width: 944, height: 190), cornerRadius: 95)
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: UIColor(white: 0, alpha: 0.22).cgColor)
            fill.setFill(); plate.fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            let font = UIFont(name: "BricolageGrotesque-96ptExtraBold", size: 118) ?? .systemFont(ofSize: 118, weight: .black)
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: style, .kern: -2]
            let h = (text as NSString).size(withAttributes: attrs).height
            (text as NSString).draw(in: CGRect(x: 40, y: 40 + (190 - h) / 2 - 4, width: 944, height: h + 8), withAttributes: attrs)
        }
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.isDoubleSided = false
        m.writesToDepthBuffer = false
        let plane = SCNPlane(width: width, height: width * size.height / size.width)
        plane.materials = [m]
        return SCNNode(geometry: plane)
    }

    /// Wide soft stripes (a candy-shop awning) for back walls.
    static func stripes(_ a: UIColor, _ b: UIColor, count: Int = 12) -> UIImage {
        Effects.stripes(a, b, count: count)
    }

    /// A sunburst in two close tints, for game-show backdrops.
    static func sunburst(_ base: UIColor, _ ray: UIColor, rays: Int = 28) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512)).image { ctx in
            base.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
            ray.setFill()
            let c = CGPoint(x: 512, y: 330)
            for i in 0..<rays where i % 2 == 0 {
                let a0 = CGFloat(i) / CGFloat(rays) * 2 * .pi, a1 = CGFloat(i + 1) / CGFloat(rays) * 2 * .pi
                let p = UIBezierPath()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + 1300 * cos(a0), y: c.y + 1300 * sin(a0)))
                p.addLine(to: CGPoint(x: c.x + 1300 * cos(a1), y: c.y + 1300 * sin(a1)))
                p.close(); p.fill()
            }
        }
    }

    /// A backdrop wall in its true colors (unlit: lit walls this far back fell off to grey).
    static func wall(_ contents: Any, width: CGFloat, height: CGFloat, at position: SCNVector3) -> SCNNode {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = contents
        let node = SCNNode(geometry: SCNPlane(width: width, height: height))
        node.geometry?.materials = [m]
        node.position = position
        return node
    }
}
