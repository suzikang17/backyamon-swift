import Foundation

func canBearOff(state: GameState) -> Bool {
    let player = state.currentPlayer
    if (state.bar[player] ?? 0) > 0 { return false }

    let start = HOME_BOARD_START[player]!
    let end = HOME_BOARD_END[player]!
    let range = min(start, end)...max(start, end)

    var piecesOutside = 0
    for i in 0..<24 {
        if range.contains(i) { continue }
        if let pt = state.points[i], pt.player == player {
            piecesOutside += pt.count
        }
    }
    return piecesOutside == 0
}

func getBearOffMoves(state: GameState) -> [Move] {
    guard canBearOff(state: state) else { return [] }
    guard let dice = state.dice, !dice.remaining.isEmpty else { return [] }

    let player = state.currentPlayer
    let direction = MOVE_DIRECTION[player]!
    let homeStart = HOME_BOARD_START[player]!
    let homeEnd = HOME_BOARD_END[player]!
    let homeRange = min(homeStart, homeEnd)...max(homeStart, homeEnd)

    var moves: [Move] = []
    let uniqueDice = Array(Set(dice.remaining))

    for die in uniqueDice {
        for i in homeRange {
            guard let pt = state.points[i], pt.player == player else { continue }

            let target = i + die * direction
            let pastEnd = player == .gold ? target > 23 : target < 0

            if pastEnd {
                // Exact or higher die — check if no pieces further back
                let posFromEnd = player == .gold ? (23 - i) : i
                if die - 1 == posFromEnd {
                    // Exact bear-off
                    moves.append(Move(from: .point(i), to: .off, dieUsed: die))
                } else if die - 1 > posFromEnd {
                    // Higher die — only valid if no pieces on higher-indexed points (further from bearing off)
                    var hasFurtherPiece = false
                    if player == .gold {
                        for j in homeRange where j < i {
                            if let pt2 = state.points[j], pt2.player == player { hasFurtherPiece = true; break }
                        }
                    } else {
                        for j in homeRange where j > i {
                            if let pt2 = state.points[j], pt2.player == player { hasFurtherPiece = true; break }
                        }
                    }
                    if !hasFurtherPiece {
                        moves.append(Move(from: .point(i), to: .off, dieUsed: die))
                    }
                }
            } else if target >= 0 && target < 24 && isPointOpen(for: player, point: state.points[target]) {
                // Regular move within home board
                moves.append(Move(from: .point(i), to: .point(target), dieUsed: die))
            }
        }
    }

    return moves
}
