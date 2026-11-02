import SceneKit
import UIKit

/// Real places for the game sets: a 360° HDR photo (Poly Haven, CC0) is both the background
/// and the light, a matching sun casts real shadows, and an invisible floor catches them so
/// the characters stand on the photo's own ground.
///
/// Scale: 1 scene unit ≈ 0.57 m (a body is 2.5 units neck to feet).
enum Location {
    case gameShow, backyard, park, garage, warehouse

    var file: String {
        switch self {
        case .gameShow: return "neon_photostudio_2k"
        case .backyard: return "studio_garden_2k"
        case .park: return "je_gray_park_2k"
        case .garage: return "autoshop_01_2k"
        case .warehouse: return "empty_warehouse_01_2k"
        }
    }

    // Panoramas are pre-rotated when bundled (the background ignores contentsTransform), so the
    // interesting part already sits behind the action.

    /// Sun (or main lamp) direction as Euler angles, matched by eye to each photo.
    var sun: SCNVector3 {
        switch self {
        case .backyard, .park: return SCNVector3(-0.9, 0.6, 0)
        default: return SCNVector3(-1.2, 0.3, 0)
        }
    }

    var sunIntensity: CGFloat {
        switch self {
        case .backyard, .park: return 1400
        default: return 500
        }
    }

    /// Camera exposure for the photo (outdoor photos are brighter).
    var exposure: CGFloat {
        switch self {
        case .backyard, .park: return 0.3
        case .gameShow: return 0.6
        default: return 0.5
        }
    }

    func apply(to scene: SCNScene, camera: SCNNode) {
        guard let url = Bundle.main.url(forResource: file, withExtension: "hdr") else { return }
        scene.background.contents = url
        scene.lightingEnvironment.contents = url
        scene.lightingEnvironment.intensity = 1.0

        if let cam = camera.camera {
            cam.wantsHDR = true
            cam.exposureOffset = exposure
            cam.wantsExposureAdaptation = false
            cam.vignettingIntensity = 0.25
            cam.bloomIntensity = 0
            // A real lens: the far background softens a touch (it's a 2K photo anyway).
            cam.screenSpaceAmbientOcclusionIntensity = 0
            cam.screenSpaceAmbientOcclusionRadius = 0.25
        }

        let sunNode = SCNNode()
        let light = SCNLight()
        light.type = .directional
        light.intensity = sunIntensity
        light.color = UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1)
        light.castsShadow = true
        light.shadowRadius = 6
        light.shadowSampleCount = 16
        light.shadowMapSize = CGSize(width: 4096, height: 4096)
        light.shadowColor = UIColor(white: 0, alpha: 0.45)
        light.shadowBias = 2
        sunNode.light = light
        sunNode.eulerAngles = sun
        scene.rootNode.addChildNode(sunNode)

        // Shadow catcher: invisible except for the shadows falling on it.
        let floor = SCNFloor()
        floor.reflectivity = 0
        let m = SCNMaterial()
        m.lightingModel = .shadowOnly
        floor.materials = [m]
        let floorNode = SCNNode(geometry: floor)
        floorNode.castsShadow = false
        scene.rootNode.addChildNode(floorNode)
    }
}

/// Realistic surface materials for props, built from plain parameters plus the existing
/// normal maps (wood, painted metal, plastic, rubber, canvas).
enum Surface {
    static func paintedMetal(_ color: UIColor) -> SCNMaterial {
        let m = Accessories.material(color, roughness: 0.38, metalness: 0.15)
        m.clearCoat.contents = 0.4
        m.clearCoatRoughness.contents = 0.25
        return m
    }

    static let steel: SCNMaterial = {
        let m = Accessories.material(UIColor(white: 0.72, alpha: 1), roughness: 0.32, metalness: 1)
        return m
    }()

    static let chrome: SCNMaterial = Accessories.material(UIColor(white: 0.92, alpha: 1), roughness: 0.08, metalness: 1)

    static func plastic(_ color: UIColor) -> SCNMaterial {
        let m = Accessories.material(color, roughness: 0.28)
        m.clearCoat.contents = 0.5
        m.clearCoatRoughness.contents = 0.1
        return m
    }

    static let rubber: SCNMaterial = Accessories.material(UIColor(white: 0.08, alpha: 1), roughness: 0.9)

    /// Varnished wood: grain drawn procedurally, lit physically.
    static func wood(_ base: UIColor = UIColor(red: 0.55, green: 0.36, blue: 0.2, alpha: 1), planks: Int = 6) -> SCNMaterial {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).image { ctx in
            let c = base.rgba
            var rng = SeededRandom(seed: 5)
            let plank = 512.0 / CGFloat(planks)
            for p in 0..<planks {
                let shade = 0.85 + CGFloat(rng.next()) * 0.3
                UIColor(red: c.r * shade, green: c.g * shade, blue: c.b * shade, alpha: 1).setFill()
                ctx.fill(CGRect(x: CGFloat(p) * plank, y: 0, width: plank, height: 512))
                // Grain lines.
                for _ in 0..<26 {
                    let x = CGFloat(p) * plank + CGFloat(rng.next()) * plank
                    let w = 0.6 + CGFloat(rng.next()) * 1.6
                    UIColor(red: c.r * 0.7, green: c.g * 0.68, blue: c.b * 0.65, alpha: 0.35).setFill()
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: x, y: 0))
                    var y: CGFloat = 0
                    var xx = x
                    while y < 512 { y += 16; xx += CGFloat(rng.next() - 0.5) * 2; path.addLine(to: CGPoint(x: xx, y: y)) }
                    path.lineWidth = w
                    UIColor(red: c.r * 0.7, green: c.g * 0.68, blue: c.b * 0.65, alpha: 0.35).setStroke()
                    path.stroke()
                }
                UIColor(white: 0, alpha: 0.35).setFill()
                ctx.fill(CGRect(x: CGFloat(p) * plank, y: 0, width: 2, height: 512))
            }
        }
        let m = Accessories.material(.white, roughness: 0.45)
        m.diffuse.contents = image
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        m.clearCoat.contents = 0.5
        m.clearCoatRoughness.contents = 0.2
        return m
    }

    static func canvas(_ color: UIColor) -> SCNMaterial {
        let m = Fabric.cloth(color, roughness: 0.95, repeats: 30)
        m.normal.intensity = 0.25
        return m
    }

    /// Glass or clear acrylic.
    static let glass: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(white: 1, alpha: 0.08)
        m.roughness.contents = 0.02
        m.metalness.contents = 0
        m.transparency = 0.25
        m.blendMode = .alpha
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }()
}
