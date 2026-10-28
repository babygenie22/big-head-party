import SwiftUI

enum Theme {
    static let pink = Color(red: 1.0, green: 0.27, blue: 0.55)
    static let yellow = Color(red: 1.0, green: 0.82, blue: 0.2)
    static let teal = Color(red: 0.2, green: 0.85, blue: 0.85)
    static let blue = Color(red: 0.2, green: 0.45, blue: 1.0)
    static let red = Color(red: 0.95, green: 0.2, blue: 0.2)
    static let purple = Color(red: 0.36, green: 0.13, blue: 0.62)
    static let deep = Color(red: 0.08, green: 0.03, blue: 0.16)

    static var background: some View {
        LinearGradient(colors: [purple, deep], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

extension Font {
    static func party(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
}

/// Big, squishy, game-y buttons.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.pink
    var textColor: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.party(20))
            .foregroundStyle(textColor)
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(color)
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: configuration.isPressed ? 1 : 6)
            )
            .offset(y: configuration.isPressed ? 5 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct AvatarView: View {
    let character: GameCharacter
    var size: CGFloat = 64
    var ring: Color = .white

    var body: some View {
        Image(uiImage: character.avatar)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(ring, lineWidth: size > 50 ? 4 : 2))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
            .accessibilityLabel(character.name)
    }
}

/// Wobbly title text.
struct PartyTitle: View {
    let text: String
    var size: CGFloat = 44
    @State private var wiggle = false

    var body: some View {
        Text(text)
            .font(.party(size))
            .foregroundStyle(LinearGradient(colors: [Theme.yellow, Theme.pink], startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(0.5), radius: 0, x: 3, y: 4)
            .rotationEffect(.degrees(wiggle ? 2 : -2))
            .scaleEffect(wiggle ? 1.03 : 0.98)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: wiggle)
            .onAppear { wiggle = true }
    }
}

/// Shows a captured moment with a share button.
struct SnapshotSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Frame-worthy.").font(.party(28))
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)
            ShareLink(item: Image(uiImage: image), preview: SharePreview("Big Head Party", image: Image(uiImage: image))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.teal, textColor: .black))
            .padding(.horizontal, 40)
            Button("Done") { dismiss() }.font(.headline)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
