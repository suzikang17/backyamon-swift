import Foundation
import Combine

/// Drives an online match for a single local player. Mirrors the web
/// `OnlineGameController` but is rendered by the SwiftUI `BoardView`.
///
/// The server is authoritative for all state; this controller publishes the
/// latest received `GameState` and translates user gestures into socket emits.
@MainActor
final class OnlineGameController: ObservableObject {
    // MARK: Published surface (matches `GameController`'s `@Published` properties).
    @Published var state: GameState
    @Published var legalMoves: [Move] = []
    @Published var message: String = "Connecting..."
    @Published var canUndo: Bool = false
    @Published var isAIThinking: Bool = false
    @Published var aiDoubleOffered: Bool = false
    @Published var matchWinner: Player? = nil

    // MARK: Online-specific status flags.
    @Published var opponentName: String = "Opponent"
    @Published var isOpponentDisconnected: Bool = false
    @Published var lastError: String? = nil

    // MARK: Identity / role.
    let socket: SocketClient
    let roomId: String

    /// Local human's role (assigned by the server).
    private(set) var localPlayer: Player = .gold
    var humanPlayer: Player { localPlayer }
    var isHumanTurn: Bool { state.currentPlayer == localPlayer }

    /// We never offer doubles from the iOS client unless the server says we can.
    /// For now we don't expose the cube — server enforces.
    var canHumanOfferDouble: Bool {
        guard state.phase == .rolling, isHumanTurn else { return false }
        guard state.winner == nil else { return false }
        guard !state.doublingCube.offered else { return false }
        let holder = state.doublingCube.holder
        return holder == nil || holder == localPlayer
    }

    var matchTarget: Int { (state.matchLength + 1) / 2 }

    // MARK: Internal tracking.
    private var subscriptionTokens: [(event: String, token: UUID)] = []
    private var pendingFirstStart = true

    // MARK: Init.

    init(socket: SocketClient, roomId: String) {
        self.socket = socket
        self.roomId = roomId
        // Placeholder state until server delivers the real one.
        self.state = createInitialState(matchLength: 1)
        bindServerEvents()
        // Pull in equipped community assets so the match plays with custom
        // SFX/music/piece visuals. Reuses the room's socket connection.
        Task { [socket] in
            await AssetManager.shared.loadEquippedAssets(socket: socket)
        }
    }

    deinit {
        // Cannot touch `socket` here off the main actor in Swift 5.10 strict
        // concurrency, but `leaveOnDeinit` was already taken care of via
        // explicit `leave()`. The socket listeners are weak-bound; the
        // SocketClient owns its own teardown.
    }

    /// Explicit teardown — called from the view on disappear.
    func leave() {
        socket.leaveRoom(roomId)
        unbindServerEvents()
    }

    // MARK: User actions (called by `GameView` / `BoardView`).

    func performRoll() {
        guard isHumanTurn || state.phase == .rolling else {
            // Opening roll: either player can roll. We treat .rolling as roll-allowed.
            return
        }
        message = "Rolling..."
        socket.rollDice()
    }

    func applyPlayerMove(_ move: Move) {
        guard isHumanTurn, state.phase == .moving else { return }
        // Server is authoritative — we send and wait for `move-made`.
        socket.makeMove(move)
        // Optimistically clear legal moves so the UI feels responsive; the
        // server's `move-made` will deliver the next state shortly.
        legalMoves = []
    }

    /// Undo is not supported in online play.
    func undo() { /* no-op */ }

    func offerDouble() {
        guard canHumanOfferDouble else { return }
        socket.offerDouble()
        message = "You offer a double..."
    }

    func acceptDouble(by acceptor: Player) {
        guard acceptor == localPlayer else { return }
        socket.respondToDouble(accept: true)
        aiDoubleOffered = false
    }

    func rejectDouble(by rejector: Player) {
        guard rejector == localPlayer else { return }
        socket.respondToDouble(accept: false)
        aiDoubleOffered = false
    }

    // MARK: Server event bindings.

    private func bindServerEvents() {
        bind("room-joined") { [weak self] data in
            self?.handleRoomJoined(data: data)
        }
        bind("game-start") { [weak self] data in
            self?.handleGameStart(data: data)
        }
        bind("opening-roll-tied") { [weak self] data in
            self?.handleOpeningRollTied(data: data)
        }
        bind("opening-roll-result") { [weak self] data in
            self?.handleOpeningRollResult(data: data)
        }
        bind("dice-rolled") { [weak self] data in
            self?.handleDiceRolled(data: data)
        }
        bind("move-made") { [weak self] data in
            self?.handleMoveMade(data: data)
        }
        bind("turn-ended") { [weak self] data in
            self?.handleTurnEnded(data: data)
        }
        bind("game-over") { [weak self] data in
            self?.handleGameOver(data: data)
        }
        bind("double-offered") { [weak self] data in
            self?.handleDoubleOffered(data: data)
        }
        bind("double-response") { [weak self] data in
            self?.handleDoubleResponse(data: data)
        }
        bind("opponent-disconnected") { [weak self] _ in
            self?.isOpponentDisconnected = true
            self?.message = "Opponent disconnected..."
        }
        bind("opponent-reconnected") { [weak self] _ in
            self?.isOpponentDisconnected = false
            self?.message = "Opponent reconnected!"
        }
        bind("opponent-left") { [weak self] _ in
            self?.message = "Opponent left the room"
            self?.isOpponentDisconnected = true
        }
        bind("error") { [weak self] data in
            guard let dict = data.first as? [String: Any],
                  let msg = dict["message"] as? String else { return }
            self?.lastError = msg
        }
    }

    private func bind(_ event: String, handler: @escaping ([Any]) -> Void) {
        let token = socket.on(event) { args in
            Task { @MainActor in handler(args) }
        }
        subscriptionTokens.append((event, token))
    }

    private func unbindServerEvents() {
        for (event, token) in subscriptionTokens {
            socket.off(event, token: token)
        }
        subscriptionTokens.removeAll()
    }

    // MARK: Event handlers.

    private func handleRoomJoined(data: [Any]) {
        guard let dict = data.first as? [String: Any] else { return }
        if let playerStr = dict["player"] as? String,
           let player = Player(rawValue: playerStr) {
            self.localPlayer = player
        }
        if let oppDict = dict["opponent"] as? [String: Any],
           let name = oppDict["displayName"] as? String {
            self.opponentName = name
        }
        if let stateJSON = dict["state"] {
            if let s = decodeState(from: stateJSON) {
                self.state = s.toGameState()
            }
        }
        message = isHumanTurn
            ? "Your turn — tap to roll!"
            : "Waiting for opponent..."
    }

    private func handleGameStart(data: [Any]) {
        guard let dict = data.first as? [String: Any] else { return }
        if let stateJSON = dict["state"],
           let s = decodeState(from: stateJSON) {
            self.state = s.toGameState()
        }
        message = "Game on! Tap to roll for opening."
    }

    private func handleOpeningRollTied(data: [Any]) {
        guard let dict = data.first as? [String: Any],
              let g = dict["goldDie"] as? Int,
              let r = dict["redDie"] as? Int else { return }
        message = "Tied \(g)-\(r)! Roll again..."
    }

    private func handleOpeningRollResult(data: [Any]) {
        guard let dict = data.first as? [String: Any],
              let firstStr = dict["firstPlayer"] as? String,
              let firstPlayer = Player(rawValue: firstStr) else { return }

        let goldDie = dict["goldDie"] as? Int ?? 0
        let redDie = dict["redDie"] as? Int ?? 0

        // Build dice from the server payload so the HUD can display them.
        if let diceJSON = dict["dice"] as? [String: Any],
           let values = diceJSON["values"] as? [Int],
           values.count >= 2,
           let remaining = diceJSON["remaining"] as? [Int] {
            var s = state
            s.dice = Dice(values: (values[0], values[1]), remaining: remaining)
            s.currentPlayer = firstPlayer
            s.phase = .moving
            self.state = s
            updateLegalMoves()
        }

        let myDie = localPlayer == .gold ? goldDie : redDie
        let theirDie = localPlayer == .gold ? redDie : goldDie
        if firstPlayer == localPlayer {
            message = "Rolled \(myDie) vs \(theirDie) — you go first!"
        } else {
            message = "Opponent rolled \(theirDie) vs \(myDie) — they go first"
        }
    }

    private func handleDiceRolled(data: [Any]) {
        guard let dict = data.first as? [String: Any],
              let diceJSON = dict["dice"] as? [String: Any],
              let values = diceJSON["values"] as? [Int],
              values.count >= 2,
              let remaining = diceJSON["remaining"] as? [Int] else { return }

        var s = state
        s.dice = Dice(values: (values[0], values[1]), remaining: remaining)
        s.phase = .moving
        self.state = s
        updateLegalMoves()
        if isHumanTurn {
            message = "Rolled \(values[0]) and \(values[1])"
        } else {
            message = "Opponent rolled \(values[0]) and \(values[1])"
        }
    }

    private func handleMoveMade(data: [Any]) {
        guard let dict = data.first as? [String: Any],
              let stateJSON = dict["state"],
              let s = decodeState(from: stateJSON) else { return }
        self.state = s.toGameState()
        updateLegalMoves()
    }

    private func handleTurnEnded(data: [Any]) {
        guard let dict = data.first as? [String: Any],
              let stateJSON = dict["state"],
              let s = decodeState(from: stateJSON) else { return }
        self.state = s.toGameState()
        legalMoves = []
        if state.phase == .gameOver { return }
        if isHumanTurn {
            message = "Your turn — tap to roll!"
        } else {
            message = "Opponent's turn..."
        }
    }

    private func handleGameOver(data: [Any]) {
        guard let dict = data.first as? [String: Any],
              let winnerStr = dict["winner"] as? String,
              let winner = Player(rawValue: winnerStr) else { return }
        let winType = dict["winType"] as? String ?? "ya_mon"
        var s = state
        s.winner = winner
        s.winType = winType
        s.phase = .gameOver
        self.state = s
        legalMoves = []
        message = winner == localPlayer ? "Ya Mon! You win!" : "You lose!"
    }

    private func handleDoubleOffered(data: [Any]) {
        guard let dict = data.first as? [String: Any],
              let cubeValue = dict["currentCubeValue"] as? Int else { return }
        var s = state
        s.doublingCube.offered = true
        // Server has already doubled the cube to currentCubeValue.
        s.doublingCube.value = cubeValue
        self.state = s
        aiDoubleOffered = true
        message = "Opponent doubles! Stakes to \(cubeValue)"
    }

    private func handleDoubleResponse(data: [Any]) {
        guard let dict = data.first as? [String: Any],
              let accepted = dict["accepted"] as? Bool,
              let stateJSON = dict["state"],
              let s = decodeState(from: stateJSON) else { return }
        self.state = s.toGameState()
        aiDoubleOffered = false
        message = accepted ? "Double accepted!" : "Double declined!"
    }

    // MARK: Helpers.

    private func updateLegalMoves() {
        if isHumanTurn, state.phase == .moving {
            legalMoves = getLegalMoves(state: state)
        } else {
            legalMoves = []
        }
    }

    /// Reserialize a `[String: Any]` payload into our typed `ServerGameState`.
    private func decodeState(from raw: Any) -> ServerGameState? {
        guard JSONSerialization.isValidJSONObject(raw) else { return nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: raw)
            return try JSONDecoder().decode(ServerGameState.self, from: data)
        } catch {
            return nil
        }
    }
}

extension OnlineGameController: GameControlling {}
