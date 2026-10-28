import SwiftUI

struct CastView: View {
    @EnvironmentObject private var store: CharacterStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = ShowcaseHolder()
    @State private var selected: GameCharacter?
    @State private var confirmDelete = false

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 16) {
                        if let selected {
                            ZStack(alignment: .bottom) {
                                SceneContainer(scene: preview.stage.scene, pointOfView: preview.stage.camera, allowsCameraControl: true)
                                    .frame(height: 280)
                                VStack(spacing: 4) {
                                    Text(selected.name).font(.party(24))
                                    Text(selected.meta.tagline).font(.subheadline).opacity(0.75)
                                }
                                .padding(.bottom, 10)
                            }
                            .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.06)))
                            if !selected.meta.isDefault {
                                Button(role: .destructive) { confirmDelete = true } label: {
                                    Label("Remove from cast", systemImage: "trash")
                                }
                            }
                        }
                        section("Your faces", store.custom, empty: "No custom faces yet. Tap Face Studio on the home screen to make one!")
                        section("House cast", store.defaults, empty: "")
                    }
                    .padding()
                }
            }
            .navigationTitle("Cast")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onAppear {
                if selected == nil { select(store.star) }
            }
            .confirmationDialog("Remove \(selected?.name ?? "")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let s = selected { store.delete(s) }
                    selected = nil
                    preview.shownID = nil
                    select(store.star)
                }
            } message: {
                Text("Their face texture is deleted from this device.")
            }
        }
    }

    private func select(_ c: GameCharacter?) {
        guard let c else { return }
        selected = c
        preview.show(c)
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [GameCharacter], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.party(20))
            if list.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(list) { c in
                        Button { select(c) } label: {
                            VStack(spacing: 6) {
                                AvatarView(character: c, size: 80, ring: selected?.id == c.id ? Theme.yellow : .white)
                                Text(c.name).font(.caption.weight(.bold)).lineLimit(1)
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
