import UIKit
import Combine

enum HatStyle: String, Codable, CaseIterable, Identifiable {
    case none, partyHat, topHat, crown, headband, cowboy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .partyHat: return "Party"
        case .topHat: return "Top Hat"
        case .crown: return "Crown"
        case .headband: return "Sweatband"
        case .cowboy: return "Cowboy"
        }
    }
    var symbol: String {
        switch self {
        case .none: return "circle.slash"
        case .partyHat: return "party.popper"
        case .topHat: return "theatermasks"
        case .crown: return "crown"
        case .headband: return "figure.boxing"
        case .cowboy: return "sun.max"
        }
    }
}

/// Optional 3D hair volume on top of the painted/photo hair.
enum HairVolume: String, Codable, CaseIterable, Identifiable {
    case none, afro, bun, pompadour
    var id: String { rawValue }
    var label: String { rawValue == "none" ? "Natural" : rawValue.capitalized }
}

struct CharacterMeta: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var tagline: String
    var shape: FaceShape
    var hat: HatStyle
    var hairVolume: HairVolume
    var googlyEyes: Bool
    var skinRGB: [Float]
    var hairRGB: [Float]
    var shirtRGB: [Float]
    var isDefault: Bool
    var createdAt: Date
}

/// A playable big-head character: metadata + its face texture.
final class GameCharacter: Identifiable, ObservableObject, Equatable {
    @Published var meta: CharacterMeta
    let texture: UIImage
    var id: UUID { meta.id }
    var name: String { meta.name }

    init(meta: CharacterMeta, texture: UIImage) {
        self.meta = meta
        self.texture = texture
    }

    static func == (lhs: GameCharacter, rhs: GameCharacter) -> Bool { lhs.id == rhs.id }

    /// Face crop of the texture, used for avatars in menus.
    lazy var avatar: UIImage = {
        guard let cg = texture.cgImage else { return texture }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(x: 0.16 * w, y: 0.08 * h, width: 0.68 * w, height: 0.80 * h)
        return cg.cropping(to: rect).map { UIImage(cgImage: $0) } ?? texture
    }()
}
