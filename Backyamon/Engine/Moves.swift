import Foundation

func opponent(of player: Player) -> Player {
    return player == .gold ? .red : .gold
}

func getTargetIndex(from pointIndex: Int, die: Int, player: Player) -> Int {
    return pointIndex + die * MOVE_DIRECTION[player]!
}

func isPointOpen(for player: Player, point: PointState?) -> Bool {
    guard let point = point else { return true }
    return point.player == player || point.count == 1
}

func getLegalMoves(state: GameState) -> [Move] {
    guard let dice = state.dice, !dice.remaining.isEmpty else { return [] }

    let player = state.currentPlayer
    let opp = opponent(of: player)
    var moves: [Move] = []
    let uniqueDice = Array(Set(dice.remaining))

    // Pieces on bar must move first
    if (state.bar[player] ?? 0) > 0 {
        for die in uniqueDice {
            let targetIdx = player == .gold ? die - 1 : 24 - die
            if targetIdx >= 0 && targetIdx < 24 && isPointOpen(for: player, point: state.points[targetIdx]) {
                moves.append(Move(from: .bar, to: .point(targetIdx), dieUsed: die))
            }
        }
        return moves
    }

    // Bearing off moves
    let bearOffMoves = getBearOffMoves(state: state)
    if !bearOffMoves.isEmpty {
        // Only return bear-off if canBearOff
        if canBearOff(state: state) {
            // Add bear-off plus regular moves (engine returns all legal moves including both)
            moves.append(contentsOf: bearOffMoves)
            // Also allow regular moves during bearing-off phase
            for i in 0..<24 {
                guard let point = state.points[i], point.player == player else { continue }
                for die in uniqueDice {
                    let target = getTargetIndex(from: i, die: die, player: player)
                    if target >= 0 && target < 24 && isPointOpen(for: player, point: state.points[target]) {
                        moves.append(Move(from: .point(i), to: .point(target), dieUsed: die))
                    }
                }
            }
            return moves
        }
    }

    // Regular moves
    for i in 0..<24 {
        guard let point = state.points[i], point.player == player else { continue }
        for die in uniqueDice {
            let target = getTargetIndex(from: i, die: die, player: player)
            if target >= 0 && target < 24 && isPointOpen(for: player, point: state.points[target]) {
                moves.append(Move(from: .point(i), to: .point(target), dieUsed: die))
            }
        }
    }

    return moves
}

func applyMove(state: GameState, move: Move) -> GameState {
    var s = cloneState(state)
    let player = s.currentPlayer
    let opp = opponent(of: player)

    // Remove die used
    if var dice = s.dice {
        if let idx = dice.remaining.firstIndex(of: move.dieUsed) {
            var rem = dice.remaining
            rem.remove(at: idx)
            s.dice = Dice(values: dice.values, remaining: rem)
        }
    }

    // Move from source
    switch move.from {
    case .bar:
        s.bar[player] = (s.bar[player] ?? 0) - 1
    case .point(let fromIdx):
        if let pt = s.points[fromIdx] {
            if pt.count == 1 {
                s.points[fromIdx] = nil
            } else {
                s.points[fromIdx] = PointState(player: player, count: pt.count - 1)
            }
        }
    }

    // Move to destination
    switch move.to {
    case .off:
        s.borneOff[player] = (s.borneOff[player] ?? 0) + 1
    case .point(let toIdx):
        let existing = s.points[toIdx]
        if let existing = existing, existing.player == opp, existing.count == 1 {
            // Hit blot — send opponent to bar
            s.bar[opp] = (s.bar[opp] ?? 0) + 1
            s.points[toIdx] = PointState(player: player, count: 1)
        } else if let existing = existing, existing.player == player {
            s.points[toIdx] = PointState(player: player, count: existing.count + 1)
        } else {
            s.points[toIdx] = PointState(player: player, count: 1)
        }
    }

    return s
}
