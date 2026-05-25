import Foundation

// MARK: - Player Profile DTOs
//
// These mirror the JSON payloads emitted by the server for the
// `get-player-profile` and `get-recent-matches` socket events.

/// One row in a player's recent-matches list (server: `get-player-profile`).
struct RecentMatch: Decodable, Identifiable, Hashable {
    let id: String
    let opponent: String
    /// `"win"` or `"loss"` — kept as a raw string for forward-compat.
    let result: String
    /// `"ya_mon" | "big_ya_mon" | "massive_ya_mon"`.
    let winType: String
    let pointsWon: Int
    /// ISO-8601 timestamp string emitted by the server.
    let completedAt: String

    var isWin: Bool { result == "win" }
}

/// A single head-to-head record vs. another opponent.
struct HeadToHeadEntry: Decodable, Identifiable, Hashable {
    var id: String { opponent }
    let opponent: String
    let wins: Int
    let losses: Int
}

/// Full player profile returned from `get-player-profile`.
struct PlayerProfile: Decodable, Hashable {
    let username: String
    let wins: Int
    let losses: Int
    let winPct: Int
    let recentMatches: [RecentMatch]
    let headToHead: [HeadToHeadEntry]

    var totalGames: Int { wins + losses }

    // Win-type breakdown is derived from the recent matches list since the
    // server does not currently return aggregate breakdown counts.
    var yaMonWins: Int {
        recentMatches.filter { $0.isWin && $0.winType == "ya_mon" }.count
    }
    var bigYaMonWins: Int {
        recentMatches.filter { $0.isWin && $0.winType == "big_ya_mon" }.count
    }
    var massiveYaMonWins: Int {
        recentMatches.filter { $0.isWin && $0.winType == "massive_ya_mon" }.count
    }
}

/// Lobby leaderboard row (server: `list-players` -> `player-list`).
/// Note: a similar shape (`LeaderboardPlayer`) already exists in
/// SocketClient.swift; we re-export an alias here for callers that prefer
/// the `LeaderboardEntry` name used by the spec.
typealias LeaderboardEntry = LeaderboardPlayer

/// Lobby recent-matches feed row (server: `get-recent-matches`).
struct LobbyRecentMatch: Decodable, Identifiable, Hashable {
    let id: String
    let goldPlayer: String
    let redPlayer: String
    let winner: String?
    let winType: String
    let pointsWon: Int
    let completedAt: String

    var loser: String? {
        guard let w = winner else { return nil }
        return w == goldPlayer ? redPlayer : goldPlayer
    }
}

// MARK: - Helpers

/// Pretty-print server win-type codes.
func formatWinType(_ winType: String) -> String {
    switch winType {
    case "ya_mon": return "Ya Mon"
    case "big_ya_mon": return "Big Ya Mon"
    case "massive_ya_mon": return "Massive Ya Mon"
    default: return winType
    }
}

/// Convert an ISO-8601 timestamp into a coarse "time ago" string.
func timeAgo(_ isoString: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: isoString)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: isoString)
    }
    guard let date else { return isoString }

    let diff = Date().timeIntervalSince(date)
    let mins = Int(diff / 60)
    if mins < 1 { return "just now" }
    if mins < 60 { return "\(mins)m ago" }
    let hours = mins / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    if days < 30 { return "\(days)d ago" }
    let df = DateFormatter()
    df.dateStyle = .short
    return df.string(from: date)
}
