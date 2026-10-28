import UIKit
import Combine

/// Owns the cast: built-in characters plus faces the player created.
/// Custom faces are stored only on this device (texture PNG + JSON). The original photo is never saved.
final class CharacterStore: ObservableObject {
    @Published private(set) var characters: [GameCharacter] = []

    private let folder: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Characters", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init() {
        characters = loadCustom() + DefaultCast.make()
    }

    var custom: [GameCharacter] { characters.filter { !$0.meta.isDefault } }
    var defaults: [GameCharacter] { characters.filter { $0.meta.isDefault } }

    /// The character to feature on the home screen: the newest custom face, else a default.
    var star: GameCharacter? { custom.first ?? defaults.first }

    func character(id: UUID) -> GameCharacter? { characters.first { $0.id == id } }

    func add(meta: CharacterMeta, texture: UIImage) {
        let c = GameCharacter(meta: meta, texture: texture)
        if let png = texture.pngData() { try? png.write(to: folder.appendingPathComponent("\(meta.id).png"), options: .atomic) }
        persist(meta)
        characters.insert(c, at: 0)
    }

    func update(_ character: GameCharacter) {
        objectWillChange.send()
        if !character.meta.isDefault { persist(character.meta) }
    }

    func delete(_ character: GameCharacter) {
        guard !character.meta.isDefault else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(character.id).png"))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(character.id).json"))
        characters.removeAll { $0.id == character.id }
    }

    private func persist(_ meta: CharacterMeta) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(meta) {
            try? data.write(to: folder.appendingPathComponent("\(meta.id).json"), options: .atomic)
        }
    }

    private func loadCustom() -> [GameCharacter] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> GameCharacter? in
                guard let data = try? Data(contentsOf: url),
                      let meta = try? decoder.decode(CharacterMeta.self, from: data),
                      let image = UIImage(contentsOfFile: url.deletingPathExtension().appendingPathExtension("png").path)
                else { return nil }
                return GameCharacter(meta: meta, texture: image)
            }
            .sorted { $0.meta.createdAt > $1.meta.createdAt }
    }
}
