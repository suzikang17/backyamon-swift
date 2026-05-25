import Foundation

let PIECES_PER_PLAYER = 15

// Gold moves +1 (toward index 23), Red moves -1 (toward index 0)
let MOVE_DIRECTION: [Player: Int] = [.gold: 1, .red: -1]

let HOME_BOARD_START: [Player: Int] = [.gold: 18, .red: 0]
let HOME_BOARD_END: [Player: Int] = [.gold: 23, .red: 5]

// (index, count) pairs for initial setup
let INITIAL_POSITIONS: [Player: [(Int, Int)]] = [
    .gold: [(0, 2), (11, 5), (16, 3), (18, 5)],
    .red:  [(23, 2), (12, 5), (7, 3), (5, 5)]
]
