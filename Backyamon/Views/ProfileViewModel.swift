import Foundation
import SwiftUI

/// View model backing `ProfileView`.
///
/// Fetches player data via `SocketClient` socket events with ack callbacks
/// (`get-player-profile`, `get-recent-matches`).
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: PlayerProfile?
    @Published var loading: Bool = true
    @Published var errorMessage: String?

    let username: String
    let client: SocketClient

    init(username: String, client: SocketClient) {
        self.username = username
        self.client = client
    }

    /// Load (or reload) the profile from the server.
    func load() async {
        loading = true
        errorMessage = nil
        do {
            profile = try await fetchProfile(username: username)
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    // MARK: - Networking

    private func fetchProfile(username: String) async throws -> PlayerProfile {
        try await client.getPlayerProfile(username: username)
    }
}

// MARK: - SocketClient extensions for profile/lobby data

extension SocketClient {
    /// Call `get-player-profile` with an ack callback and decode the result.
    func getPlayerProfile(username: String) async throws -> PlayerProfile {
        let dict = try await emitWithAck(
            event: "get-player-profile",
            payload: ["username": username]
        )
        if let err = dict["error"] as? String {
            throw SocketClientError.server(err)
        }
        return try decodeProfile(from: dict)
    }

    /// Call `get-recent-matches` for the lobby feed.
    func getRecentMatches(limit: Int = 10) async throws -> [LobbyRecentMatch] {
        let dict = try await emitWithAck(
            event: "get-recent-matches",
            payload: ["limit": limit]
        )
        guard let arr = dict["matches"] as? [[String: Any]] else { return [] }
        return arr.compactMap { decodeLobbyMatch(from: $0) }
    }

    /// Emit a socket event with a single dictionary payload and await the
    /// server's ack callback. Times out after 10s.
    func emitWithAck(
        event: String,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any], Error>) in
            var resumed = false
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !resumed {
                    resumed = true
                    cont.resume(throwing: SocketClientError.timeout)
                }
            }

            // Use SocketIO's emitWithAck which delivers ack data as the first
            // element of the response array.
            self.socket.emitWithAck(event, with: [payload]).timingOut(after: 10) { data in
                guard !resumed else { return }
                resumed = true
                timeoutTask.cancel()
                if let first = data.first as? [String: Any] {
                    cont.resume(returning: first)
                } else {
                    cont.resume(throwing: SocketClientError.decoding(event))
                }
            }
        }
    }
}

// MARK: - Decoding helpers

private func decodeProfile(from dict: [String: Any]) throws -> PlayerProfile {
    guard let username = dict["username"] as? String else {
        throw SocketClientError.decoding("get-player-profile: username")
    }
    let wins = (dict["wins"] as? Int) ?? 0
    let losses = (dict["losses"] as? Int) ?? 0
    let winPct = (dict["winPct"] as? Int) ?? 0

    let recentRaw = dict["recentMatches"] as? [[String: Any]] ?? []
    let recent: [RecentMatch] = recentRaw.compactMap { d in
        guard let id = d["id"] as? String,
              let opponent = d["opponent"] as? String,
              let result = d["result"] as? String,
              let winType = d["winType"] as? String else { return nil }
        let pts = (d["pointsWon"] as? Int) ?? 0
        let completed = (d["completedAt"] as? String) ?? ""
        return RecentMatch(
            id: id,
            opponent: opponent,
            result: result,
            winType: winType,
            pointsWon: pts,
            completedAt: completed
        )
    }

    let h2hRaw = dict["headToHead"] as? [[String: Any]] ?? []
    let h2h: [HeadToHeadEntry] = h2hRaw.compactMap { d in
        guard let opponent = d["opponent"] as? String else { return nil }
        let wins = (d["wins"] as? Int) ?? 0
        let losses = (d["losses"] as? Int) ?? 0
        return HeadToHeadEntry(opponent: opponent, wins: wins, losses: losses)
    }

    return PlayerProfile(
        username: username,
        wins: wins,
        losses: losses,
        winPct: winPct,
        recentMatches: recent,
        headToHead: h2h
    )
}

private func decodeLobbyMatch(from d: [String: Any]) -> LobbyRecentMatch? {
    guard let id = d["id"] as? String,
          let gold = d["goldPlayer"] as? String,
          let red = d["redPlayer"] as? String,
          let winType = d["winType"] as? String else { return nil }
    let winner = d["winner"] as? String
    let pts = (d["pointsWon"] as? Int) ?? 0
    let completed = (d["completedAt"] as? String) ?? ""
    return LobbyRecentMatch(
        id: id,
        goldPlayer: gold,
        redPlayer: red,
        winner: winner,
        winType: winType,
        pointsWon: pts,
        completedAt: completed
    )
}
