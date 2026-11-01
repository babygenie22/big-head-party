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
                            VStack(spacing: 4) {
                                ZStack {
                                    Theme.sky
                                    Circle().fill(Theme.cream.opacity(0.35)).frame(width: 220, height: 220)
                                    SceneContainer(scene: preview.stage.scene, pointOfView: preview.stage.camera, allowsCameraControl: true)
                                }
                                .frame(height: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ink, lineWidth: Theme.outline))
                                .padding(12)
                                Text(selected.name).font(.party(24))
                                Text(selected.meta.tagline).font(.system(size: 15, weight: .semibold, design: .rounded)).opacity(0.7)
                                    .padding(.bottom, 14)
                            }
                            .foregroundStyle(Theme.ink)
                            .sticker(Theme.cream, cornerRadius: 24, drop: 6)
                            if !selected.meta.isDefault {
                                Button(role: .destructive) { confirmDelete = true } label: {
                                    Label("Remove from cast", systemImage: "trash")
                                        .font(.system(size: 15, weight: .black, design: .rounded))
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 16).padding(.vertical, 9)
                                        .stickerCapsule(Theme.tomato)
                                }
                            }
                        }
                        section("Your faces", store.custom, empty: "No custom faces yet. Tap “Make a big head” on the home screen to add one.")
                        section("House cast", store.defaults, empty: "")
                    }
                    .padding()
                }
            }
            .navigationTitle("Cast")
            .toolbarBackground(Theme.paper, for: .navigationBar)
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
            Text(title).font(.party(22)).foregroundStyle(Theme.ink)
            if list.isEmpty {
                Text(empty).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.ink.opacity(0.7))
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(list) { c in
                        Button { select(c) } label: {
                            VStack(spacing: 6) {
                                AvatarView(character: c, size: 80, ring: selected?.id == c.id ? Theme.highlight : nil)
                                Text(c.name).font(.system(size: 12, weight: .heavy, design: .rounded)).lineLimit(1)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
