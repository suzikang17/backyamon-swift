import Foundation
import Combine

enum Difficulty {
    case beachBum
    case selector
    case kingTubby
}

@MainActor
class GameController: ObservableObject {
    @Published var state: GameState
    @Published var legalMoves: [Move] = []
    @Published var message: String = "Roll to start!"
    @Published var canUndo: Bool = false
    @Published var isAIThinking: Bool = false
    @Published var aiDoubleOffered: Bool = false
    @Published var matchWinner: Player? = nil

    private var undoStack: [GameState] = []
    private(set) var difficulty: Difficulty
    let humanPlayer: Player = .gold
    private let maxCubeValue: Int = 64

    init(difficulty: Difficulty = .selector, matchLength: Int = 1) {
        self.difficulty = difficulty
        self.state = createInitialState(matchLength: matchLength)
        // Load equipped community assets (custom piece / SFX / music) in the
        // background. Local games still need their own SocketClient instance
        // to fetch the user's asset list and any equipped gallery items.
        let asyncClient = SocketClient()
        Task { [weak asyncClient] in
            guard let asyncClient else { return }
            do {
                try await asyncClient.connect(maxRetries: 3)
                _ = try await asyncClient.register()
                await AssetManager.shared.loadEquippedAssets(socket: asyncClient)
            } catch {
                // Silent failure — synthesised audio / default pieces remain.
            }
            asyncClient.disconnect()
        }
    }

    var isHumanTurn: Bool { state.currentPlayer == humanPlayer }

    /// Points needed to win the current match.
    var matchTarget: Int { (state.matchLength + 1) / 2 }

    /// Start a brand-new match (resets scores).
    func newGame(difficulty: Difficulty, matchLength: Int = 1) {
        self.difficulty = difficulty
        state = createInitialState(matchLength: matchLength)
        undoStack = []
        canUndo = false
        message = "Roll to start!"
        legalMoves = []
        aiDoubleOffered = false
        matchWinner = nil
        // Procedural reggae soundtrack — style follows difficulty.
        let style: MusicStyle
        switch difficulty {
        case .beachBum: style = .roots
        case .selector: style = .dub
        case .kingTubby: style = .dancehall
        }
        MusicEngine.shared.start(style: style, difficulty: difficulty)
        MusicEngine.shared.updateMood(from: state)
    }

    /// Start the next game in an ongoing match, preserving scores and matchLength.
    func nextGame() {
        let length = state.matchLength
        let scores = state.matchScore
        var fresh = createInitialState(matchLength: length)
        fresh.matchScore = scores
        // Crawford: if either player is 1 point from winning the match, this game is Crawford.
        let target = (length + 1) / 2
        let goldScore = scores[.gold] ?? 0
        let redScore = scores[.red] ?? 0
        if length > 1 && (goldScore == target - 1 || redScore == target - 1) {
            fresh.isCrawford = true
        }
        state = fresh
        undoStack = []
        canUndo = false
        legalMoves = []
        aiDoubleOffered = false
        message = state.isCrawford ? "Crawford game — no doubles" : "Roll to start!"
    }

    // MARK: - Doubling cube

    /// Whether the given player can currently offer a double.
    /// Allowed when it is their rolling phase, the cube is centered or they own it,
    /// and the cube hasn't already been offered or maxed out.
    func canOffer(player: Player) -> Bool {
        guard state.phase == .rolling,
              state.currentPlayer == player,
              state.winner == nil,
              !state.isCrawford,
              !state.doublingCube.offered,
              state.doublingCube.value < maxCubeValue else { return false }
        let holder = state.doublingCube.holder
        return holder == nil || holder == player
    }

    var canHumanOfferDouble: Bool { canOffer(player: humanPlayer) }

    /// Human-initiated offer. Pauses for the AI's decision.
    func offerDouble() {
        guard isHumanTurn, canOffer(player: humanPlayer) else { return }
        var s = cloneState(state)
        s.doublingCube.offered = true
        state = s
        SoundManager.shared.play(.doubleOffered)
        message = "You offer a double..."

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run {
                guard let self else { return }
                if self.aiShouldAcceptDouble() {
                    self.acceptDouble(by: .red)
                } else {
                    self.rejectDouble(by: .red)
                }
            }
        }
    }

    /// AI offers a double during its rolling phase. Surfaces UI prompt.
    private func aiOfferDouble() {
        guard !isHumanTurn, canOffer(player: .red) else { return }
        var s = cloneState(state)
        s.doublingCube.offered = true
        state = s
        SoundManager.shared.play(.doubleOffered)
        message = "Opponent offers a double!"
        aiDoubleOffered = true
    }

    /// Accept a pending offer on behalf of `acceptor`. Cube doubles, acceptor becomes holder.
    func acceptDouble(by acceptor: Player) {
        guard state.doublingCube.offered else { return }
        var s = cloneState(state)
        s.doublingCube.value = min(s.doublingCube.value * 2, maxCubeValue)
        s.doublingCube.holder = acceptor
        s.doublingCube.offered = false
        state = s
        aiDoubleOffered = false
        if acceptor == humanPlayer {
            message = "You accept — cube is now \(s.doublingCube.value)"
            // AI was the offerer; resume its rolling turn.
            if !isHumanTurn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.resumeAITurnAfterDouble()
                }
            }
        } else {
            message = "Opponent accepts — cube is now \(s.doublingCube.value)"
        }
    }

    /// After a double was resolved, let the AI proceed with its roll + moves.
    private func resumeAITurnAfterDouble() {
        guard !isHumanTurn, state.phase == .rolling, state.winner == nil else { return }
        isAIThinking = true
        message = "Opponent thinking..."

        let capturedDifficulty = difficulty

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let dice = generateDice()
            await MainActor.run {
                var s = self.state
                s.dice = dice
                s.phase = .moving
                self.state = s
                SoundManager.shared.play(.diceRoll)
                self.message = "Opponent rolled \(dice.values.0) and \(dice.values.1)"
            }

            try? await Task.sleep(nanoseconds: 500_000_000)

            let currentState = await self.state
            let turn: Turn
            switch capturedDifficulty {
            case .beachBum: turn = beachBumMove(state: currentState)
            case .selector:  turn = selectorMove(state: currentState)
            case .kingTubby: turn = kingTubbyMove(state: currentState)
            }

            for move in turn {
                let st = await self.state
                let next = applyMove(state: st, move: move)
                await MainActor.run {
                    self.playSoundFor(move: move, prev: st, next: next)
                    self.state = next
                    MusicEngine.shared.updateMood(from: next)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }

            await MainActor.run {
                self.isAIThinking = false
                if let winner = checkWinner(state: self.state) {
                    self.handleGameOver(winner: winner,
                                        winType: getWinType(winner: winner, state: self.state))
                } else {
                    self.endTurn()
                }
            }
        }
    }

    /// Reject a pending offer. The offerer wins immediately at the current cube value.
    func rejectDouble(by rejector: Player) {
        guard state.doublingCube.offered else { return }
        var s = cloneState(state)
        s.doublingCube.offered = false
        state = s
        aiDoubleOffered = false
        let winner = opponent(of: rejector)
        // Drop = ya_mon at current cube value (no gammon/backgammon on rejection).
        handleGameOver(winner: winner, winType: "ya_mon")
    }

    /// Simple AI accept heuristic: accept unless the board is decisively bad for AI.
    private func aiShouldAcceptDouble() -> Bool {
        let score = evaluateBoard(state: state, for: .red)
        // Negative score means AI is behind. A large deficit -> drop.
        return score > -60
    }

    /// AI offer heuristic: offer when AI is clearly ahead but game isn't over.
    private func aiShouldOfferDouble() -> Bool {
        guard canOffer(player: .red) else { return false }
        let score = evaluateBoard(state: state, for: .red)
        return score > 70
    }

    // Human player rolls
    func performRoll() {
        guard state.phase == .rolling, isHumanTurn else { return }
        undoStack.append(cloneState(state))
        var s = cloneState(state)
        let dice = generateDice()
        s.dice = dice
        s.phase = .moving
        state = s
        SoundManager.shared.play(.diceRoll)
        HapticManager.shared.medium()
        updateLegalMoves()
        message = "Rolled \(dice.values.0) and \(dice.values.1)"
        canUndo = !undoStack.isEmpty

        if legalMoves.isEmpty {
            message = "No moves — passing"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.endTurn()
            }
        }
    }

    func applyPlayerMove(_ move: Move) {
        guard isHumanTurn, state.phase == .moving else { return }
        undoStack.append(cloneState(state))
        let prev = state
        state = applyMove(state: state, move: move)
        playSoundFor(move: move, prev: prev, next: state)
        MusicEngine.shared.updateMood(from: state)
        updateLegalMoves()
        canUndo = true

        if let winner = checkWinner(state: state) {
            handleGameOver(winner: winner, winType: getWinType(winner: winner, state: state))
            return
        }

        if state.dice?.remaining.isEmpty != false || legalMoves.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.endTurn()
            }
        }
    }

    /// Pick an SFX + haptic based on what happened during a move.
    /// - bear-off (to == .off) -> bearOff + success haptic
    /// - opponent's bar count increased -> pieceHit + heavy haptic
    /// - otherwise -> pieceMove + light haptic
    private func playSoundFor(move: Move, prev: GameState, next: GameState) {
        let isHuman = prev.currentPlayer == humanPlayer
        if move.to == .off {
            SoundManager.shared.play(.bearOff)
            if isHuman { HapticManager.shared.success() }
            return
        }
        let opp = opponent(of: prev.currentPlayer)
        let prevOppBar = prev.bar[opp] ?? 0
        let nextOppBar = next.bar[opp] ?? 0
        if nextOppBar > prevOppBar {
            SoundManager.shared.play(.pieceHit)
            HapticManager.shared.heavy()
        } else {
            SoundManager.shared.play(.pieceMove)
            if isHuman { HapticManager.shared.light() }
        }
    }

    func undo() {
        guard !undoStack.isEmpty, isHumanTurn else { return }
        state = undoStack.removeLast()
        updateLegalMoves()
        canUndo = !undoStack.isEmpty
    }

    private func endTurn() {
        var s = cloneState(state)
        s.currentPlayer = opponent(of: s.currentPlayer)
        s.phase = .rolling
        s.dice = nil
        state = s
        legalMoves = []
        undoStack = []
        canUndo = false

        if isHumanTurn {
            SoundManager.shared.play(.turnStart)
            message = "Your turn — roll!"
        } else {
            triggerAI()
        }
    }

    private func triggerAI() {
        guard !isHumanTurn else { return }

        // Consider doubling before rolling.
        if aiShouldOfferDouble() {
            aiOfferDouble()
            return
        }

        isAIThinking = true
        message = "Opponent thinking..."

        let capturedDifficulty = difficulty

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let dice = generateDice()
            await MainActor.run {
                var s = self.state
                s.dice = dice
                s.phase = .moving
                self.state = s
                SoundManager.shared.play(.diceRoll)
                self.message = "Opponent rolled \(dice.values.0) and \(dice.values.1)"
            }

            try? await Task.sleep(nanoseconds: 500_000_000)

            let currentState = await self.state
            let turn: Turn
            switch capturedDifficulty {
            case .beachBum: turn = beachBumMove(state: currentState)
            case .selector:  turn = selectorMove(state: currentState)
            case .kingTubby: turn = kingTubbyMove(state: currentState)
            }

            for move in turn {
                let st = await self.state
                let next = applyMove(state: st, move: move)
                await MainActor.run {
                    self.playSoundFor(move: move, prev: st, next: next)
                    self.state = next
                    MusicEngine.shared.updateMood(from: next)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }

            await MainActor.run {
                self.isAIThinking = false
                if let winner = checkWinner(state: self.state) {
                    self.handleGameOver(winner: winner,
                                        winType: getWinType(winner: winner, state: self.state))
                } else {
                    self.endTurn()
                }
            }
        }
    }

    private func updateLegalMoves() {
        legalMoves = getLegalMoves(state: state)
    }

    private func handleGameOver(winner: Player, winType: WinType) {
        var s = cloneState(state)
        s.winner = winner
        s.winType = winType
        s.phase = .gameOver
        let pts = getPointsWon(winType: winType, cubeValue: s.doublingCube.value)
        s.matchScore[winner] = (s.matchScore[winner] ?? 0) + pts
        state = s
        legalMoves = []
        if winner == humanPlayer {
            SoundManager.shared.play(.victory)
            HapticManager.shared.success()
        } else {
            SoundManager.shared.play(.defeat)
            HapticManager.shared.error()
        }
        MusicEngine.shared.stop()
        switch winType {
        case "ya_mon":          message = "\(winner.rawValue.capitalized) wins — Ya Mon!"
        case "big_ya_mon":      message = "\(winner.rawValue.capitalized) wins — Big Ya Mon!"
        case "massive_ya_mon":  message = "\(winner.rawValue.capitalized) wins — Massive Ya Mon!"
        default:                message = "\(winner.rawValue.capitalized) wins!"
        }

        // Check if the series is over.
        let target = matchTarget
        let winnerScore = s.matchScore[winner] ?? 0
        if s.matchLength > 1 && winnerScore >= target {
            matchWinner = winner
        }
    }
}
