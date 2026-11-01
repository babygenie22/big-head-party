import SwiftUI
import SceneKit

/// Attract mode: two default characters take turns getting pied, on loop.
final class DemoDirector: ObservableObject {
    let stage: PieStage
    @Published var caption = ""
    private var timer: Timer?
    private var next = 0
    private var count = 0

    init(store: CharacterStore) {
        let cast = store.defaults
        let a = cast.first { $0.name == "Grandpa Gus" } ?? cast[0]
        let b = cast.first { $0.name == "Aunt Linda" } ?? cast[1]
        stage = PieStage(characters: [a, b])
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: true) { [weak self] _ in self?.beat() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.beat() }
    }

    func stop() { timer?.invalidate() }

    private func beat() {
        count += 1
        if count % 5 == 0 {
            caption = "Fresh faces!"
            stage.cleanUp()
            stage.focus(on: nil)
            return
        }
        let target = next
        next = 1 - next
        let victim = stage.rigs[target].character.name
        caption = ["\(victim) never saw it coming.", "\(victim): 0. Pie: 1.", "Dessert is served, \(victim)."].randomElement()!
        stage.focus(on: target)
        stage.throwPie(at: target)
    }
}

struct IntroView: View {
    let onFinish: () -> Void
    @EnvironmentObject private var store: CharacterStore
    @State private var page = 0

    var body: some View {
        ZStack {
            Theme.background
            TabView(selection: $page) {
                DemoPage { withAnimation { page = 1 } }.tag(0)
                HowItWorksPage { withAnimation { page = 2 } }.tag(1)
                PlayNicePage(onFinish: onFinish).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}

private struct DemoPage: View {
    let onNext: () -> Void
    @EnvironmentObject private var store: CharacterStore
    @StateObject private var director: DemoDirectorBox = DemoDirectorBox()

    var body: some View {
        VStack(spacing: 14) {
            PartyTitle(text: "Big Head\nParty", size: 52)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            Text("Turn your friends & family into 3D characters.\nThen hit them with pies.")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink.opacity(0.8))
            ZStack(alignment: .bottom) {
                if let d = director.director {
                    SceneContainer(scene: d.stage.scene, pointOfView: d.stage.camera)
                    DemoCaption(director: d)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .sticker(Theme.deep, cornerRadius: 22, drop: 6)
            .frame(maxHeight: .infinity)
            .padding(.horizontal)
            Button("Show me how") { onNext() }
                .buttonStyle(ChunkyButtonStyle())
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
        }
        .onAppear {
            if director.director == nil { director.director = DemoDirector(store: store) }
            director.director?.start()
        }
        .onDisappear { director.director?.stop() }
    }
}

/// Lets the demo be created lazily once the environment store is available.
final class DemoDirectorBox: ObservableObject {
    @Published var director: DemoDirector?
}

private struct DemoCaption: View {
    @ObservedObject var director: DemoDirector
    var body: some View {
        Text(director.caption)
            .font(.party(18))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .stickerCapsule(Theme.cream)
            .padding(.bottom, 14)
            .animation(.spring, value: director.caption)
    }
}

private struct HowItWorksPage: View {
    let onNext: () -> Void
    private let steps: [(String, String, String)] = [
        ("camera.viewfinder", "Snap or upload a photo", "Any clear, front-facing photo of a friend or family member."),
        ("point.3.filled.connected.trianglepath.dotted", "AI maps their face", "On-device AI finds 76 landmarks and separates them from the background."),
        ("cube.transparent", "We sculpt a 3D head", "The head is shaped to *their* jaw, nose, mouth and chin, then their face is wrapped onto it."),
        ("party.popper", "Pie it. Box it. Share it.", "Drop them into game shows and boxing matches. Faces squish, wobble and splat."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PartyTitle(text: "How it works", size: 38).frame(maxWidth: .infinity)
                .padding(.top, 40)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        Circle().fill([Theme.bubblegum, Theme.sky, Theme.mint, Theme.tomato][i])
                            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.outline))
                            .background(Circle().fill(Theme.ink).offset(x: 3, y: 3))
                            .frame(width: 54, height: 54)
                        Image(systemName: step.0).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(i + 1). \(step.1)").font(.party(20)).foregroundStyle(Theme.ink)
                        Text(LocalizedStringKey(step.2)).font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.ink.opacity(0.75))
                    }
                }
            }
            Spacer()
            Button("Next") { onNext() }
                .buttonStyle(ChunkyButtonStyle(color: Theme.sky))
                .padding(.bottom, 50)
        }
        .padding(.horizontal, 28)
    }
}

private struct PlayNicePage: View {
    let onFinish: () -> Void
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "hand.raised.fingers.spread.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.ink)
                .frame(width: 120, height: 120)
                .sticker(Theme.bubblegum, cornerRadius: 60, drop: 5)
            PartyTitle(text: "Play nice", size: 40)
            VStack(alignment: .leading, spacing: 14) {
                Label("Photos are processed on your iPhone. They never leave your device.", systemImage: "iphone")
                Label("We keep the face texture, not the original photo. Delete anyone anytime.", systemImage: "trash")
                Label("Only use photos of people who are in on the joke.", systemImage: "person.2.fill")
                Label("It's slapstick. No mean stuff, no grown-up stuff.", systemImage: "face.smiling")
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(20)
            .sticker(Theme.cream, cornerRadius: 20)
            Spacer()
            Button("Let's party!") { onFinish() }
                .buttonStyle(ChunkyButtonStyle())
                .padding(.bottom, 50)
        }
        .padding(.horizontal, 28)
    }
}
