import SwiftUI

/// "Toy box": sunny packaging yellow, black ink outlines, sticker-colored pieces with hard
/// offset shadows — like a bobblehead in its collector box.
enum Theme {
    // Ground and ink.
    static let paper = Color(red: 1.0, green: 0.875, blue: 0.29)      // #FFDF4A
    static let cream = Color(red: 1.0, green: 0.97, blue: 0.88)       // #FFF7E0
    static let ink = Color(red: 0.09, green: 0.075, blue: 0.06)       // #17130F
    // Sticker colors (one per game, plus players).
    static let tomato = Color(red: 1.0, green: 0.35, blue: 0.21)      // #FF5A36
    static let sky = Color(red: 0.30, green: 0.66, blue: 1.0)         // #4DA8FF
    static let mint = Color(red: 0.24, green: 0.86, blue: 0.52)       // #3DDC84
    static let bubblegum = Color(red: 1.0, green: 0.56, blue: 0.82)   // #FF8FD0
    static let lilac = Color(red: 0.73, green: 0.61, blue: 1.0)       // #B99CFF

    // Roles used across screens.
    static let pink = bubblegum
    static let yellow = paper
    static let teal = mint
    static let blue = sky
    static let red = tomato
    /// Selection rings and "your turn" markers: must read on yellow paper.
    static let highlight = tomato
    /// Night-time stage behind 3D scenes (kept dark so lit heads pop).
    static let deep = Color(red: 0.12, green: 0.09, blue: 0.07)

    static let outline: CGFloat = 3
    static let drop: CGFloat = 5

    static var background: some View {
        ZStack {
            paper
            HalftoneDots().foregroundStyle(ink.opacity(0.06))
        }
        .ignoresSafeArea()
    }
}

/// The packaging print texture behind every screen.
struct HalftoneDots: View {
    var spacing: CGFloat = 16
    var radius: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var row = 0
            var y: CGFloat = 0
            while y < size.height + spacing {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
                while x < size.width + spacing {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += spacing
                }
                y += spacing * 0.87
                row += 1
            }
            ctx.fill(path, with: .foreground)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension Font {
    static func party(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
}

/// A die-cut sticker: flat fill, thick ink outline, hard ink shadow down and to the right.
struct Sticker<S: InsettableShape>: ViewModifier {
    var fill: Color
    var shape: S
    var drop: CGFloat = Theme.drop

    func body(content: Content) -> some View {
        content
            .background(
                shape
                    .fill(fill)
                    .overlay(shape.strokeBorder(Theme.ink, lineWidth: Theme.outline))
                    .background(shape.fill(Theme.ink).offset(x: drop, y: drop))
            )
    }
}

extension View {
    func sticker(_ fill: Color = Theme.cream, cornerRadius: CGFloat = 20, drop: CGFloat = Theme.drop) -> some View {
        modifier(Sticker(fill: fill, shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), drop: drop))
    }

    func stickerCapsule(_ fill: Color = Theme.cream, drop: CGFloat = 3) -> some View {
        modifier(Sticker(fill: fill, shape: Capsule(), drop: drop))
    }
}

/// Big, squishy, game-y buttons: a sticker that presses down into its shadow.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.tomato
    var textColor: Color = Theme.ink
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return configuration.label
            .font(.party(20))
            .foregroundStyle(textColor)
            .padding(.vertical, 15)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background(
                shape.fill(enabled ? color : Theme.cream)
                    .overlay(shape.strokeBorder(Theme.ink, lineWidth: Theme.outline))
            )
            .offset(x: pressed ? Theme.drop : 0, y: pressed ? Theme.drop : 0)
            .background(shape.fill(Theme.ink).offset(x: Theme.drop, y: Theme.drop))
            .opacity(enabled ? 1 : 0.55)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, new in new }
    }
}

/// Small round sticker buttons for toolbars and reactions.
struct StickerIconButtonStyle: ButtonStyle {
    var color: Color = Theme.cream

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(10)
            .background(Circle().fill(color).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2.5)))
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
            .background(Circle().fill(Theme.ink).offset(x: 3, y: 3))
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct AvatarView: View {
    let character: GameCharacter
    var size: CGFloat = 64
    /// A colored ring around the outline marks selection or a player's side.
    var ring: Color?

    var body: some View {
        Image(uiImage: character.avatar)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(Theme.cream)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: size > 50 ? 3 : 2))
            .padding(ring == nil ? 0 : 4)
            .background(Circle().fill(ring ?? .clear))
            .overlay(Circle().strokeBorder(ring == nil ? .clear : Theme.ink, lineWidth: 2))
            .background(Circle().fill(Theme.ink).offset(x: 3, y: 3))
            .accessibilityLabel(character.name)
    }
}

/// Title lettering: ink with a sticker-colored offset shadow, gently wobbling.
struct PartyTitle: View {
    let text: String
    var size: CGFloat = 44
    var shadow: Color = Theme.tomato
    @State private var wiggle = false

    var body: some View {
        Text(text)
            .font(.party(size))
            .foregroundStyle(Theme.ink)
            .background(
                Text(text).font(.party(size)).foregroundStyle(shadow).offset(x: 3, y: 4)
            )
            .rotationEffect(.degrees(wiggle ? 1.5 : -1.5))
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: wiggle)
            .onAppear { wiggle = true }
    }
}

/// Shows a captured moment with a share button.
struct SnapshotSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            PartyTitle(text: "Frame-worthy.", size: 30)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(6)
                .sticker(Theme.cream, cornerRadius: 22)
                .padding(.horizontal)
            ShareLink(item: Image(uiImage: image), preview: SharePreview("Big Head Party", image: Image(uiImage: image))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.mint))
            .padding(.horizontal, 40)
            Button("Done") { dismiss() }.font(.party(17)).foregroundStyle(Theme.ink)
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
