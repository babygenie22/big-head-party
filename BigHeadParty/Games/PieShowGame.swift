import SceneKit
import SwiftUI

/// "The Pie-Q Test": a trivia game show. Answer right and the pie hits your opponent;
/// answer wrong (or run out the clock) and it hits you. Fewest pies to the face wins.
final class PieShowGame: ObservableObject {
    enum Phase: Equatable { case intro, asking, cpuThinking, reveal, finished }

    @Published var phase: Phase = .intro
    @Published var question: TriviaQuestion?
    @Published var turn = 0
    @Published var round = 0
    @Published var timeLeft: Double = 0
    @Published var picked: Int?
    @Published var pies = [0, 0]
    @Published var hostLine = ""

    let players: [GameCharacter]
    let vsCPU: Bool
    let totalRounds = 6
    let answerTime: Double = 10
    let stage: PieStage
    weak var view: SCNView?

    private var questions: [TriviaQuestion]
    private var timer: Timer?
    private var generation = 0

    init(players: [GameCharacter], vsCPU: Bool) {
        self.players = players
        self.vsCPU = vsCPU
        stage = PieStage(characters: players)
        questions = TriviaBank.all.shuffled()
    }

    var currentName: String { players[turn].name }
    var isHumanTurn: Bool { !(vsCPU && turn == 1) }

    var winnerIndex: Int? {
        guard phase == .finished, pies[0] != pies[1] else { return nil }
        return pies[0] < pies[1] ? 0 : 1
    }

    // MARK: - Flow

    func start() {
        generation += 1
        phase = .intro
        hostLine = "Welcome to THE PIE-Q TEST! Get it right and your opponent eats dessert. Get it wrong… well."
        stage.focus(on: nil)
        after(3.2) { [weak self] in self?.nextQuestion() }
    }

    func stop() {
        generation += 1
        timer?.invalidate()
    }

    private func nextQuestion() {
        guard round < totalRounds else { return finish() }
        question = questions[round % questions.count]
        picked = nil
        stage.focus(on: turn)
        if isHumanTurn {
            phase = .asking
            hostLine = vsCPU ? "This one's for you, \(currentName)!" : "Hand the phone to \(currentName)!"
            startClock()
        } else {
            phase = .cpuThinking
            hostLine = "\(currentName) is thinking… (it's not their strong suit)"
            startClock()
            after(Double.random(in: 1.6...3.4)) { [weak self] in
                guard let self, let q = self.question else { return }
                let correct = Double.random(in: 0...1) < 0.55
                let wrong = (0..<q.options.count).filter { $0 != q.answer }.randomElement() ?? q.answer
                self.resolve(pick: correct ? q.answer : wrong)
            }
        }
    }

    func answer(_ index: Int) {
        guard phase == .asking else { return }
        resolve(pick: index)
    }

    private func resolve(pick: Int) {
        guard let q = question, phase == .asking || phase == .cpuThinking else { return }
        timer?.invalidate()
        generation += 1
        picked = pick
        phase = .reveal
        let correct = pick == q.answer
        let target = correct ? 1 - turn : turn
        if pick < 0 {
            hostLine = "TIME! The pie waits for no one."
        } else if correct {
            hostLine = "Correct! \(q.quip) Pie goes to \(players[target].name)!"
        } else {
            hostLine = "WRONG! It was \"\(q.options[q.answer])\". Dessert is served."
        }
        after(1.4) { [weak self] in
            guard let self else { return }
            self.stage.focus(on: target)
            self.stage.throwPie(at: target) { [weak self] in
                self?.pies[target] += 1
            }
            self.after(2.6) { [weak self] in
                guard let self else { return }
                self.round += 1
                self.turn = 1 - self.turn
                self.nextQuestion()
            }
        }
    }

    private func finish() {
        phase = .finished
        question = nil
        stage.focus(on: nil)
        if let w = winnerIndex {
            hostLine = "\(players[w].name) wins with the cleanest face in show business!"
            stage.cheer(w)
            after(1.2) { [weak self] in self?.stage.throwPie(at: 1 - w) }   // a victory pie for the loser
        } else {
            hostLine = "A TIE! You know what that means… pies for everyone!"
            after(0.8) { [weak self] in
                self?.stage.throwPie(at: 0)
                self?.stage.throwPie(at: 1)
            }
        }
    }

    func snapshot() -> UIImage? { view?.snapshot() }

    // MARK: - Timing

    private func startClock() {
        timeLeft = answerTime
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.timeLeft = max(0, self.timeLeft - 0.1)
            if self.timeLeft <= 0, self.phase == .asking {
                t.invalidate()
                self.resolve(pick: -1)
            }
        }
    }

    /// Main-thread delay that is cancelled by `stop()` or by a newer step.
    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.generation == gen else { return }
            work()
        }
    }
}
