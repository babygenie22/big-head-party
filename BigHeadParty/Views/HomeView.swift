import SwiftUI

final class ShowcaseHolder: ObservableObject {
    let stage = ShowcaseStage(character: nil)
    @Published var shownID: UUID?

    func show(_ character: GameCharacter?, animated: Bool = true) {
        guard let character, character.id != shownID else { return }
        shownID = character.id
        stage.show(character, animated: animated)
    }
}

enum GameKind: String, Identifiable, CaseIterable {
    case pieShow, slap, dunk, whack, boxing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pieShow: return "The Pie-Q Test"
        case .slap: return "Slap Champs"
        case .dunk: return "Dunk Tank"
        case .whack: return "Whack-a-Head"
        case .boxing: return "Bobble Boxing"
        }
    }
    var blurb: String {
        switch self {
        case .pieShow: return "Game-show trivia. Wrong answer? Pie to the face."
        case .slap: return "Time the meter. Perfect slaps go slow-mo."
        case .dunk: return "Hit the bullseye. Splash."
        case .whack: return "Bonk the faces. Not the baby."
        case .boxing: return "Big heads. Wobbly knockouts."
        }
    }
    var symbol: String {
        switch self {
        case .pieShow: return "birthday.cake.fill"
        case .slap: return "hand.raised.fill"
        case .dunk: return "drop.fill"
        case .whack: return "hammer.fill"
        case .boxing: return "figure.boxing"
        }
    }
    var color: Color {
        switch self {
        case .pieShow: return Theme.bubblegum
        case .slap: return Theme.butter
        case .dunk: return Theme.sky
        case .whack: return Theme.lime
        case .boxing: return Theme.lilac
        }
    }
    /// A real render of the game, used as its poster.
    var cover: String { "cover-\(rawValue)" }
    /// Whack-a-Head is solo; everything else is head-to-head.
    var isSolo: Bool { self == .whack }
}

struct HomeView: View {
    @EnvironmentObject private var store: CharacterStore
    @AppStorage("hasSeenIntro") private var hasSeenIntro = true
    @StateObject private var hero = ShowcaseHolder()
    @State private var showStudio = false
    @State private var showCast = false
    @State private var setupGame: GameKind?
    @State private var debugGame: GameConfig?
    @State private var debugStudio: IdentifiableImage?
    @AppStorage(HeadSize.storageKey) private var headSize: HeadSize = .big

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    starStage
                    Button {
                        showStudio = true
                    } label: {
                        Label("Make a big head", systemImage: "camera.fill")
                    }
                    .buttonStyle(CandyButtonStyle())
                    sectionTitle("Pick a game")
                    gameMosaic
                    castRow
                    comingSoon
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(Self.debugScrollAnchor)
        }
        .onAppear {
            hero.show(store.star, animated: false)
            startDebugScenarioIfRequested()
        }
        .onChange(of: store.characters.map(\.id)) { _, _ in hero.show(store.star) }
        .fullScreenCover(isPresented: $showStudio) { FaceStudioView() }
        .fullScreenCover(item: $debugStudio) { FaceStudioView(testImage: $0.image) }
        .fullScreenCover(item: $debugGame) { GameHost(config: $0) }
        .sheet(isPresented: $showCast) { CastView() }
        .sheet(item: $setupGame) { kind in MatchSetupView(kind: kind) }
    }

    /// Debug: `-homeBottom YES` opens the home screen scrolled to the end (for screenshots).
    private static var debugScrollAnchor: UnitPoint {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "homeBottom") { return .bottom }
        if UserDefaults.standard.bool(forKey: "homeGames") { return UnitPoint(x: 0.5, y: 0.62) }
        #endif
        return .top
    }

    /// Debug builds only: launch arguments that jump straight to a screen, used by the CI
    /// simulator run to screenshot every game (`-demoGame slap`) and the photo pipeline
    /// (`-studioTestImage /path/to/photo.jpg`).
    private func startDebugScenarioIfRequested() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "studioTestImage"), let image = UIImage(contentsOfFile: path) {
            debugStudio = IdentifiableImage(image: image)
        } else if let raw = defaults.string(forKey: "demoGame"), let kind = GameKind(rawValue: raw), store.defaults.count >= 2 {
            let cast = store.defaults
            debugGame = GameConfig(kind: kind, players: kind.isSolo ? [cast[0]] : [cast[0], cast[1]], vsCPU: true)
        } else if defaults.bool(forKey: "studioCamera") {
            showStudio = true
        }
        #endif
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            PartyTitle(text: "Big Head Party", size: 34)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Menu {
                Picker("Head size", selection: $headSize) {
                    ForEach(HeadSize.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: headSize == .big ? "person.crop.circle.badge.plus" : "person.crop.circle")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24)
                    .padding(10)
                    .background(Circle().fill(Theme.surface).softShadow(0.6))
            }
            .accessibilityLabel("Head size: \(headSize.label)")
            Button { hasSeenIntro = false } label: { Image(systemName: "play.fill") }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Watch the demo again")
        }
        .padding(.top, 6)
    }

    /// The thesis: today's star, big and live. Tap them and they get a pie.
    private var starStage: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Theme.blush
                Circle().fill(.white.opacity(0.7)).frame(width: 280, height: 280).blur(radius: 40).offset(y: -20)
                SceneContainer(scene: hero.stage.scene, pointOfView: hero.stage.camera,
                               onTap: { _, _ in hero.stage.throwPie() })
                if let star = store.star {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(star.name).font(.display(28)).foregroundStyle(Theme.ink)
                        Text("Tap them for a pie").font(.ui(13)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(18)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .softShadow(1.2)

            HStack(spacing: 8) {
                reactButton("Bonk", "hand.point.right.fill") { hero.stage.react(.skewLeft) }
                reactButton("Scream", "mouth.fill") { hero.stage.react(.mouthOpen) }
                reactButton("Clean up", "drop.fill") { hero.stage.clean() }
            }
        }
    }

    private func reactButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.ui(14, .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .pill()
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.display(24)).foregroundStyle(Theme.ink).padding(.top, 6)
    }

    /// One featured game, then an even two-column grid.
    private var gameMosaic: some View {
        VStack(spacing: 14) {
            gameTile(.pieShow, imageHeight: 200, featured: true)
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    gameTile(.slap, imageHeight: 132)
                    gameTile(.dunk, imageHeight: 132)
                }
                GridRow {
                    gameTile(.boxing, imageHeight: 132)
                    gameTile(.whack, imageHeight: 132)
                }
            }
        }
    }

    /// A candy card with an ink outline: the poster sits in a framed window up top, and the
    /// name sits below it on the game's color, so it never fights the art.
    private func gameTile(_ kind: GameKind, imageHeight: CGFloat, featured: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return Button { setupGame = kind } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Clear base sets the size; the poster fills it without pushing the layout wider.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight)
                    .overlay { Image(kind.cover).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.ink, lineWidth: 2))
                    .overlay(alignment: .topTrailing) {
                        Text(kind.isSolo ? "Solo" : "2 players")
                            .font(.ui(11, .heavy))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(.white))
                            .padding(8)
                    }
                HStack(spacing: 10) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: featured ? 17 : 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: featured ? 38 : 30, height: featured ? 38 : 30)
                        .background(Circle().fill(.white))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                            .font(.display(featured ? 24 : 17))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if featured { Text(kind.blurb).font(.ui(13)).foregroundStyle(Theme.ink.opacity(0.75)).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer(minLength: 0)
                    if featured {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.ink))
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 6)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
            .padding(8)
            .background(shape.fill(kind.color))
            .overlay(shape.stroke(Theme.ink, lineWidth: 2.5))
            .softShadow()
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("\(kind.title). \(kind.blurb)")
    }

    private var castRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Your cast")
                Spacer()
                Button("See all") { showCast = true }
                    .font(.ui(15, .bold))
                    .foregroundStyle(Theme.coral)
                    .frame(minHeight: 44)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    Button { showStudio = true } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 70, height: 70)
                                .background(Circle().fill(Theme.coral).softShadow(0.6))
                            Text("New").font(.ui(12, .bold)).foregroundStyle(Theme.ink)
                        }
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    ForEach(store.characters) { c in
                        Button { hero.show(c) } label: {
                            VStack(spacing: 6) {
                                AvatarView(character: c, size: 64, ring: hero.shownID == c.id ? Theme.coral : nil)
                                Text(c.name).font(.ui(12, .bold)).foregroundStyle(Theme.ink).lineLimit(1).frame(width: 80)
                            }
                        }
                        .buttonStyle(PressScaleButtonStyle())
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Coming soon")
            HStack(spacing: 8) {
                teaser("Bobble Kart", "car.fill")
                teaser("Sumo", "figure.wrestling")
                teaser("Cake Wars", "gift.fill")
            }
        }
    }

    private func teaser(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.ui(13, .bold))
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Capsule().fill(Theme.ink.opacity(0.06)))
    }
}

/// Gentle squish for tappable cards and chips.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
