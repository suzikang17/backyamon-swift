import Foundation

enum Player: String, Codable, CaseIterable {
    case gold = "gold"
    case red = "red"
}

struct PointState: Equatable {
    let player: Player
    let count: Int
}

enum GamePhase: String {
    case rolling
    case moving
    case gameOver
}

typealias WinType = String
// "ya_mon" | "big_ya_mon" | "massive_ya_mon"

struct Dice {
    let values: (Int, Int)
    var remaining: [Int]
}

struct DoublingCube {
    var value: Int
    var holder: Player?
    var offered: Bool
}

enum MoveFrom: Equatable, Hashable {
    case point(Int)
    case bar
}

enum MoveTo: Equatable, Hashable {
    case point(Int)
    case off
}

struct Move: Equatable {
    let from: MoveFrom
    let to: MoveTo
    let dieUsed: Int
}

struct GameState {
    var points: [PointState?]      // 24 elements, index 0-23
    var bar: [Player: Int]
    var borneOff: [Player: Int]
    var currentPlayer: Player
    var phase: GamePhase
    var dice: Dice?
    var doublingCube: DoublingCube
    var matchScore: [Player: Int]
    var matchLength: Int
    var isCrawford: Bool
    var winner: Player?
    var winType: WinType?
}

typealias Turn = [Move]
