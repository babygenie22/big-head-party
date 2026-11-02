import SwiftUI
import CoreText

/// "Night studio": a dark, premium broadcast look that frames the realistic sets. Near-black
/// canvas, warm white type, one on-air red accent, deep per-game tones, fine light edges.
enum Theme {
    // Canvas and text.
    static let canvas = Color(red: 0.043, green: 0.043, blue: 0.051)  // #0B0B0D
    static let surface = Color(red: 0.094, green: 0.094, blue: 0.106) // #18181B
    static let ink = Color(red: 0.957, green: 0.945, blue: 0.925)     // #F4F1EC warm white
    static let inkSoft = ink.opacity(0.6)
    static let hairline = ink.opacity(0.12)
    // The accent (kept under its old name): on-air red. Text on it is white.
    static let coral = Color(red: 1.0, green: 0.357, blue: 0.227)     // #FF5B3A
    // Deep game tones (text on them stays warm white).
    static let sky = Color(red: 0.118, green: 0.227, blue: 0.373)     // #1E3A5F
    static let lime = Color(red: 0.122, green: 0.29, blue: 0.2)       // #1F4A33
    static let bubblegum = Color(red: 0.353, green: 0.122, blue: 0.22) // #5A1F38
    static let lilac = Color(red: 0.208, green: 0.169, blue: 0.369)   // #352B5E
    static let butter = Color(red: 0.353, green: 0.271, blue: 0.094)  // #5A4518
    static let blush = Color(red: 0.102, green: 0.086, blue: 0.094)   // the star's stage

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
    /// Display voice: SF Pro Heavy, tight like a broadcast lower third; scales with Dynamic Type.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style == .largeTitle ? .largeTitle : .headline).scaledValue(for: size),
                weight: .heavy).width(.condensed)
    }
    /// Buttons, scores and labels.
    static func party(_ size: CGFloat) -> Font { display(size, relativeTo: .headline) }
    /// Friendly UI text.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// Soft, lifted depth: a tight contact shadow plus a wide, faint ambient one.
struct SoftShadow: ViewModifier {
    var lift: CGFloat = 1
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.45), radius: 2 * lift, y: 1 * lift)
            .shadow(color: .black.opacity(0.35), radius: 14 * lift, y: 8 * lift)
    }
}

extension View {
    func softShadow(_ lift: CGFloat = 1) -> some View { modifier(SoftShadow(lift: lift)) }

    /// A rounded card in a candy (or white) fill, gently lifted off the canvas.
    func card(_ fill: Color = Theme.surface, cornerRadius: CGFloat = 24, lift: CGFloat = 1) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .softShadow(lift))
    }

    func pill(_ fill: Color = Theme.surface, lift: CGFloat = 0.6) -> some View {
        background(Capsule().fill(fill).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1)).softShadow(lift))
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
            .background(Circle().fill(color).overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1)).softShadow(0.6))
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

/// Announcer pop for game moments ("Perfect!", "KO!"): a tilted coral badge that springs in.
struct CalloutBadge: View {
    let text: String
    var size: CGFloat = 40

    var body: some View {
        Text(text)
            .font(.display(text.count > 12 ? size * 0.7 : size, relativeTo: .largeTitle))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.coral).softShadow(1.4))
            .rotationEffect(.degrees(-4))
            .transition(.asymmetric(insertion: .scale(scale: 0.3).combined(with: .opacity),
                                    removal: .scale(scale: 1.15).combined(with: .opacity)))
            .accessibilityAddTraits(.isStaticText)
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
