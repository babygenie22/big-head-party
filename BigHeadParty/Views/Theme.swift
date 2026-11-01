import SwiftUI
import CoreText

/// "Candy studio": a warm, light canvas; candy-colored stages and real game renders; chunky
/// Bricolage Grotesque for display moments; soft, lifted depth instead of outlines.
enum Theme {
    // Canvas and text.
    static let canvas = Color(red: 1.0, green: 0.957, blue: 0.925)    // #FFF4EC
    static let surface = Color.white
    static let ink = Color(red: 0.169, green: 0.106, blue: 0.180)     // #2B1B2E plum-black
    static let inkSoft = ink.opacity(0.62)
    // Candy colors. Text on them stays ink, except on coral (white, bold).
    static let coral = Color(red: 1.0, green: 0.42, blue: 0.29)       // #FF6B4A
    static let sky = Color(red: 0.50, green: 0.78, blue: 1.0)         // #7FC8FF
    static let lime = Color(red: 0.73, green: 0.91, blue: 0.42)       // #B9E86A
    static let bubblegum = Color(red: 1.0, green: 0.62, blue: 0.75)   // #FF9EC0
    static let lilac = Color(red: 0.79, green: 0.71, blue: 1.0)       // #C9B6FF
    static let butter = Color(red: 1.0, green: 0.85, blue: 0.42)      // #FFD86B
    static let blush = Color(red: 1.0, green: 0.84, blue: 0.89)       // #FFD6E4 the star's stage

    // Roles.
    static let highlight = coral
    static let blue = Color(red: 0.25, green: 0.55, blue: 1.0)        // player 1
    static let red = Color(red: 1.0, green: 0.36, blue: 0.40)         // player 2
    static let success = Color(red: 0.36, green: 0.78, blue: 0.42)
    /// Dark surround for the camera only, so a bright screen doesn't tint selfies.
    static let deep = Color(red: 0.11, green: 0.08, blue: 0.12)

    static var background: some View { canvas.ignoresSafeArea() }

    /// Registers the bundled display face once at launch.
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "BricolageGrotesque", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    /// Display voice: Bricolage Grotesque ExtraBold (its 96 pt optical size), scaling with Dynamic Type.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("BricolageGrotesque-96ptExtraBold", size: size, relativeTo: style)
    }
    /// Buttons, scores and labels.
    static func party(_ size: CGFloat) -> Font { display(size, relativeTo: .headline) }
    /// Friendly UI text.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Soft, lifted depth: a tight contact shadow plus a wide, faint ambient one.
struct SoftShadow: ViewModifier {
    var lift: CGFloat = 1
    func body(content: Content) -> some View {
        content
            .shadow(color: Theme.ink.opacity(0.10), radius: 2 * lift, y: 1 * lift)
            .shadow(color: Theme.ink.opacity(0.10), radius: 14 * lift, y: 8 * lift)
    }
}

extension View {
    func softShadow(_ lift: CGFloat = 1) -> some View { modifier(SoftShadow(lift: lift)) }

    /// A rounded card in a candy (or white) fill, gently lifted off the canvas.
    func card(_ fill: Color = Theme.surface, cornerRadius: CGFloat = 24, lift: CGFloat = 1) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill).softShadow(lift))
    }

    func pill(_ fill: Color = Theme.surface, lift: CGFloat = 0.6) -> some View {
        background(Capsule().fill(fill).softShadow(lift))
    }
}

/// Primary buttons: chunky candy pills that squish when pressed.
struct CandyButtonStyle: ButtonStyle {
    var color: Color = Theme.coral
    var textColor: Color? = nil
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.party(20))
            .foregroundStyle(textColor ?? (color == Theme.coral ? .white : Theme.ink))
            .padding(.vertical, 17)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(enabled ? color : Theme.ink.opacity(0.08)).softShadow(pressed ? 0.3 : 1))
            .scaleEffect(pressed ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.6)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, new in new }
    }
}

/// Round white icon buttons for toolbars and HUDs.
struct IconButtonStyle: ButtonStyle {
    var color: Color = Theme.surface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .frame(minWidth: 24, minHeight: 24)
            .padding(10)
            .background(Circle().fill(color).softShadow(0.6))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

struct AvatarView: View {
    let character: GameCharacter
    var size: CGFloat = 64
    /// A colored ring marks selection or a player's side.
    var ring: Color?

    var body: some View {
        Image(uiImage: character.avatar)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(Theme.blush)
            .clipShape(Circle())
            .padding(size > 50 ? 3 : 2)
            .background(Circle().fill(Theme.surface))
            .padding(ring == nil ? 0 : 3)
            .background(Circle().fill(ring ?? .clear))
            .softShadow(0.6)
            .accessibilityLabel(character.name)
    }
}

/// Display lettering for screen titles.
struct PartyTitle: View {
    let text: String
    var size: CGFloat = 44

    var body: some View {
        Text(text)
            .font(.display(size, relativeTo: .largeTitle))
            .foregroundStyle(Theme.ink)
            .tracking(-0.5)
    }
}

/// Shows a captured moment with a share button.
struct SnapshotSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            PartyTitle(text: "Frame-worthy", size: 32)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .softShadow(1.4)
                .padding(.horizontal)
            ShareLink(item: Image(uiImage: image), preview: SharePreview("Big Head Party", image: Image(uiImage: image))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(CandyButtonStyle())
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
