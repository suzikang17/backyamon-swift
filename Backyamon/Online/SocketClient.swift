import Foundation
import SocketIO

// MARK: - Server Phase Names

/// Phase strings emitted by the server. These differ from the local
/// `GamePhase` enum: the server also has `OPENING_ROLL` and `DOUBLING`.
enum ServerPhase: String, Codable {
    case openingRoll = "OPENING_ROLL"
    case rolling = "ROLLING"
    case moving = "MOVING"
    case doubling = "DOUBLING"
    case gameOver = "GAME_OVER"
}

// MARK: - Server JSON DTOs

/// `points` element from the server. JSON wire form: `{ player, count } | null`.
struct ServerPoint: Codable {
    let player: String   // "gold" | "red"
    let count: Int
}

/// Wire form for the doubling cube.
struct ServerDoublingCube: Codable {
    let value: Int
    let holder: String?   // "gold" | "red" | null
    let offered: Bool
}

/// Wire form for `dice`. `values` is sent as a fixed-length `[number, number]` array.
struct ServerDice: Codable {
    let values: [Int]      // length 2
    let remaining: [Int]
}

/// Full server `GameState` JSON. We decode permissively; some fields are optional.
struct ServerGameState: Codable {
    let points: [ServerPoint?]    // length 24
    let bar: [String: Int]        // { gold: 0, red: 0 }
    let borneOff: [String: Int]
    let currentPlayer: String     // "gold" | "red"
    let phase: String             // ServerPhase rawValue
    let dice: ServerDice?
    let doublingCube: ServerDoublingCube
    let matchScore: [String: Int]?
    let matchLength: Int?
    let isCrawford: Bool?
    let winner: String?
    let winType: String?
}

/// `move` JSON: `{ from: "bar" | number, to: "off" | number, dieUsed: number }`.
struct ServerMove: Codable {
    /// `"bar"` or an int. Encoded as an untyped value during JSON serialization.
    let from: ServerMoveEndpoint
    let to: ServerMoveEndpoint
    let dieUsed: Int
}

enum ServerMoveEndpoint: Codable {
    case bar
    case off
    case point(Int)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            switch s {
            case "bar": self = .bar
            case "off": self = .off
            default: throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unknown endpoint string: \(s)")
            }
            return
        }
        let i = try c.decode(Int.self)
        self = .point(i)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bar: try c.encode("bar")
        case .off: try c.encode("off")
        case .point(let i): try c.encode(i)
        }
    }
}

// MARK: - Identity

struct GuestIdentity: Codable {
    var playerId: String
    var displayName: String
    var username: String?
    var token: String
}

// MARK: - Conversion to local engine types

extension ServerGameState {
    /// Map server JSON into the local `GameState`. Unknown phases fall back to `.rolling`.
    func toGameState() -> GameState {
        let points: [PointState?] = self.points.map { p in
            guard let p = p else { return nil }
            guard let player = Player(rawValue: p.player) else { return nil }
            return PointState(player: player, count: p.count)
        }

        let bar: [Player: Int] = [
            .gold: self.bar["gold"] ?? 0,
            .red: self.bar["red"] ?? 0,
        ]
        let off: [Player: Int] = [
            .gold: self.borneOff["gold"] ?? 0,
            .red: self.borneOff["red"] ?? 0,
        ]

        let currentPlayer = Player(rawValue: self.currentPlayer) ?? .gold

        let localPhase: GamePhase
        switch ServerPhase(rawValue: self.phase) {
        case .gameOver: localPhase = .gameOver
        case .moving: localPhase = .moving
        case .openingRoll, .rolling, .doubling, .none: localPhase = .rolling
        }

        let dice: Dice? = self.dice.flatMap { d in
            guard d.values.count >= 2 else { return nil }
            return Dice(values: (d.values[0], d.values[1]), remaining: d.remaining)
        }

        let cube = DoublingCube(
            value: self.doublingCube.value,
            holder: self.doublingCube.holder.flatMap { Player(rawValue: $0) },
            offered: self.doublingCube.offered
        )

        let matchScore: [Player: Int] = [
            .gold: self.matchScore?["gold"] ?? 0,
            .red: self.matchScore?["red"] ?? 0,
        ]

        return GameState(
            points: points,
            bar: bar,
            borneOff: off,
            currentPlayer: currentPlayer,
            phase: localPhase,
            dice: dice,
            doublingCube: cube,
            matchScore: matchScore,
            matchLength: self.matchLength ?? 1,
            isCrawford: self.isCrawford ?? false,
            winner: self.winner.flatMap { Player(rawValue: $0) },
            winType: self.winType
        )
    }
}

extension Move {
    /// Encode a local move into the server's wire format.
    func toServerJSON() -> [String: Any] {
        let fromJSON: Any = {
            switch self.from {
            case .bar: return "bar"
            case .point(let i): return i
            }
        }()
        let toJSON: Any = {
            switch self.to {
            case .off: return "off"
            case .point(let i): return i
            }
        }()
        return ["from": fromJSON, "to": toJSON, "dieUsed": self.dieUsed]
    }
}

// MARK: - Lobby DTOs

struct WaitingRoom: Decodable, Identifiable {
    let id: String
    let hostName: String
    let createdAt: String
}

struct LeaderboardPlayer: Decodable, Identifiable {
    var id: String { username }
    let username: String
    let createdAt: String?
    let wins: Int
    let losses: Int
    let points: Int
}

// MARK: - Persistence

private let kIdentityKey = "backyamon_guest_identity_v1"
private let kUsernameKey = "backyamon_username_v1"

private func loadIdentity() -> GuestIdentity? {
    guard let data = UserDefaults.standard.data(forKey: kIdentityKey) else { return nil }
    return try? JSONDecoder().decode(GuestIdentity.self, from: data)
}

private func saveIdentity(_ identity: GuestIdentity) {
    if let data = try? JSONEncoder().encode(identity) {
        UserDefaults.standard.set(data, forKey: kIdentityKey)
    }
    if let username = identity.username {
        UserDefaults.standard.set(username, forKey: kUsernameKey)
    }
}

private func savedUsername() -> String? {
    UserDefaults.standard.string(forKey: kUsernameKey)
}

// MARK: - SocketClient

/// Swift wrapper around Socket.IO that mirrors the web `SocketClient`.
///
/// Concurrency: all completion handlers fire on the main queue.
@MainActor
final class SocketClient {
    private let manager: SocketManager
    internal let socket: SocketIOClient
    private let serverURL: URL

    private(set) var identity: GuestIdentity?

    // External callbacks for connection lifecycle.
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onReconnect: (() -> Void)?

    // Generic event listeners. Key = event name. Value = handlers.
    private var listeners: [String: [UUID: ([Any]) -> Void]] = [:]

    init(serverURL: URL = URL(string: "https://api.backyamon.com")!) {
        self.serverURL = serverURL
        self.manager = SocketManager(
            socketURL: serverURL,
            config: [
                .log(false),
                .compress,
                .reconnects(true),
                .reconnectWait(1),
                .reconnectWaitMax(10),
                .reconnectAttempts(-1),
                .forceWebsockets(true),
            ]
        )
        self.socket = manager.defaultSocket
        self.identity = loadIdentity()

        bindCoreEvents()
    }

    // MARK: Connection

    /// Connect with bounded retries and exponential backoff. Resolves on first success.
    func connect(maxRetries: Int = 5, onRetry: ((Int, Int) -> Void)? = nil) async throws {
        for attempt in 1...maxRetries {
            do {
                try await connectOnce()
                return
            } catch {
                if attempt == maxRetries { throw error }
                onRetry?(attempt, maxRetries)
                let delaySeconds = min(pow(2.0, Double(attempt - 1)), 16.0)
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
    }

    private func connectOnce() async throws {
        if socket.status == .connected { return }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false

            // 10s connection timeout.
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !resumed {
                    resumed = true
                    cont.resume(throwing: SocketClientError.timeout)
                }
            }

            socket.once(clientEvent: .connect) { _, _ in
                guard !resumed else { return }
                resumed = true
                timeoutTask.cancel()
                cont.resume()
            }
            socket.once(clientEvent: .error) { data, _ in
                guard !resumed else { return }
                resumed = true
                timeoutTask.cancel()
                let msg = (data.first as? String) ?? "Connect error"
                cont.resume(throwing: SocketClientError.connection(msg))
            }
            socket.connect()
        }
    }

    func disconnect() {
        socket.disconnect()
    }

    var isConnected: Bool { socket.status == .connected }

    // MARK: Auth

    /// Register/re-register with the server. If we have a cached token, the server
    /// restores our identity; otherwise it issues a fresh guest.
    func register() async throws -> GuestIdentity {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GuestIdentity, Error>) in
            var resumed = false
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !resumed {
                    resumed = true
                    cont.resume(throwing: SocketClientError.timeout)
                }
            }

            socket.once("registered") { [weak self] data, _ in
                guard !resumed, let self else { return }
                guard let dict = data.first as? [String: Any],
                      let playerId = dict["playerId"] as? String,
                      let displayName = dict["displayName"] as? String,
                      let token = dict["token"] as? String else {
                    resumed = true
                    timeoutTask.cancel()
                    cont.resume(throwing: SocketClientError.decoding("registered"))
                    return
                }
                let username = dict["username"] as? String
                let id = GuestIdentity(
                    playerId: playerId,
                    displayName: username ?? displayName,
                    username: username,
                    token: token
                )
                self.identity = id
                saveIdentity(id)

                // If server lost our username but we cached one locally, try to reclaim it.
                if username == nil, let saved = savedUsername() {
                    Task {
                        _ = try? await self.claimUsername(saved)
                        if !resumed {
                            resumed = true
                            timeoutTask.cancel()
                            cont.resume(returning: self.identity ?? id)
                        }
                    }
                    return
                }

                resumed = true
                timeoutTask.cancel()
                cont.resume(returning: id)
            }

            let token = self.identity?.token ?? loadIdentity()?.token
            if let token {
                socket.emit("register", ["token": token])
            } else {
                socket.emit("register", [String: Any]())
            }
        }
    }

    /// Claim a username. Resolves to the canonical username.
    func claimUsername(_ username: String) async throws -> String {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            var resumed = false
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !resumed {
                    resumed = true
                    cont.resume(throwing: SocketClientError.timeout)
                }
            }

            socket.once("username-claimed") { [weak self] data, _ in
                guard !resumed, let self else { return }
                resumed = true
                timeoutTask.cancel()
                guard let dict = data.first as? [String: Any],
                      let claimed = dict["username"] as? String else {
                    cont.resume(throwing: SocketClientError.decoding("username-claimed"))
                    return
                }
                if var id = self.identity {
                    id.username = claimed
                    id.displayName = claimed
                    if let newToken = dict["token"] as? String {
                        id.token = newToken
                    }
                    self.identity = id
                    saveIdentity(id)
                }
                cont.resume(returning: claimed)
            }

            socket.once("username-error") { data, _ in
                guard !resumed else { return }
                resumed = true
                timeoutTask.cancel()
                let msg = (data.first as? [String: Any])?["message"] as? String ?? "Username error"
                cont.resume(throwing: SocketClientError.server(msg))
            }

            socket.emit("claim-username", ["username": username])
        }
    }

    // MARK: Room management

    /// Create a new room. Resolves to the room ID/code.
    func createRoom(name: String? = nil) async throws -> String {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            var resumed = false
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !resumed {
                    resumed = true
                    cont.resume(throwing: SocketClientError.timeout)
                }
            }

            socket.once("room-created") { data, _ in
                guard !resumed else { return }
                resumed = true
                timeoutTask.cancel()
                guard let dict = data.first as? [String: Any],
                      let id = dict["roomId"] as? String else {
                    cont.resume(throwing: SocketClientError.decoding("room-created"))
                    return
                }
                cont.resume(returning: id)
            }
            socket.once("error") { data, _ in
                guard !resumed else { return }
                resumed = true
                timeoutTask.cancel()
                let msg = (data.first as? [String: Any])?["message"] as? String ?? "Create room failed"
                cont.resume(throwing: SocketClientError.server(msg))
            }

            if let name, !name.isEmpty {
                socket.emit("create-room", ["roomName": name])
            } else {
                socket.emit("create-room", [String: Any]())
            }
        }
    }

    /// Join a specific room by code. Resolves when `room-joined` arrives.
    func joinRoom(_ roomId: String) async throws {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !resumed {
                    resumed = true
                    cont.resume(throwing: SocketClientError.timeout)
                }
            }

            socket.once("room-joined") { _, _ in
                guard !resumed else { return }
                resumed = true
                timeoutTask.cancel()
                cont.resume()
            }
            socket.once("error") { data, _ in
                guard !resumed else { return }
                resumed = true
                timeoutTask.cancel()
                let msg = (data.first as? [String: Any])?["message"] as? String ?? "Join failed"
                cont.resume(throwing: SocketClientError.server(msg))
            }
            socket.emit("join-room", ["roomId": roomId.uppercased()])
        }
    }

    func quickMatch() {
        socket.emit("quick-match")
    }

    func leaveQueue() {
        socket.emit("leave-queue")
    }

    func listRooms() {
        socket.emit("list-rooms")
    }

    func listPlayers() {
        socket.emit("list-players")
    }

    func leaveRoom(_ roomId: String) {
        socket.emit("leave-room", ["roomId": roomId])
    }

    func reconnectToGame(playerId: String, roomId: String) {
        socket.emit("reconnect-to-game", ["playerId": playerId, "roomId": roomId])
    }

    // MARK: Game actions

    func rollDice() {
        socket.emit("roll-dice")
    }

    func makeMove(_ move: Move) {
        socket.emit("make-move", ["move": move.toServerJSON()])
    }

    func endTurn() {
        socket.emit("end-turn")
    }

    func offerDouble() {
        socket.emit("offer-double")
    }

    func respondToDouble(accept: Bool) {
        socket.emit("respond-double", ["accept": accept])
    }

    // MARK: Generic event subscription

    @discardableResult
    func on(_ event: String, _ handler: @escaping ([Any]) -> Void) -> UUID {
        let key = UUID()
        listeners[event, default: [:]][key] = handler

        // Lazily attach the socket-level handler exactly once per event.
        if listeners[event]?.count == 1 {
            socket.on(event) { [weak self] data, _ in
                guard let self else { return }
                let entries = self.listeners[event] ?? [:]
                for cb in entries.values { cb(data) }
            }
        }
        return key
    }

    func off(_ event: String, token: UUID) {
        listeners[event]?[token] = nil
        if listeners[event]?.isEmpty == true {
            listeners[event] = nil
            socket.off(event)
        }
    }

    func offAll(event: String) {
        listeners[event] = nil
        socket.off(event)
    }

    // MARK: Internal

    private func bindCoreEvents() {
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            self?.onConnect?()
        }
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.onDisconnect?()
        }
        socket.on(clientEvent: .reconnect) { [weak self] _, _ in
            self?.onReconnect?()
        }
    }

    deinit {
        socket.removeAllHandlers()
    }
}

// MARK: - Errors

enum SocketClientError: LocalizedError {
    case timeout
    case connection(String)
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "Request timed out"
        case .connection(let m): return "Connection error: \(m)"
        case .server(let m): return m
        case .decoding(let m): return "Decoding error: \(m)"
        }
    }
}
