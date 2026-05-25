import Foundation

func selectorMove(state: GameState) -> Turn {
    let turns = getAllLegalTurns(state: state)
    let nonEmpty = turns.filter { !$0.isEmpty }
    guard !nonEmpty.isEmpty else { return [] }

    let player = state.currentPlayer
    var bestTurn = nonEmpty[0]
    var bestScore = Int.min

    for turn in nonEmpty {
        var s = state
        for move in turn { s = applyMove(state: s, move: move) }
        let score = evaluateBoard(state: s, for: player)
        if score > bestScore {
            bestScore = score
            bestTurn = turn
        }
    }

    return bestTurn
}

func evaluateBoard(state: GameState, for player: Player) -> Int {
    let opp = opponent(of: player)
    var score = 0

    // Pip count differential (lower is better for self)
    let myPips = calculatePipCount(state: state, for: player)
    let oppPips = calculatePipCount(state: state, for: opp)
    score += oppPips - myPips

    for i in 0..<24 {
        guard let pt = state.points[i] else { continue }
        if pt.player == player {
            if pt.count >= 2 { score += 10 }   // made point
            else { score -= 15 }               // blot
            // Home board bonus
            let homeStart = HOME_BOARD_START[player]!
            let homeEnd = HOME_BOARD_END[player]!
            let homeRange = min(homeStart, homeEnd)...max(homeStart, homeEnd)
            if homeRange.contains(i) { score += 5 }
        }
    }

    // Bar penalty
    score -= (state.bar[player] ?? 0) * 20
    score += (state.bar[opp] ?? 0) * 20

    // Borne off bonus
    score += (state.borneOff[player] ?? 0) * 5

    return score
}

func calculatePipCount(state: GameState, for player: Player) -> Int {
    var pips = 0
    let direction = MOVE_DIRECTION[player]!

    for i in 0..<24 {
        guard let pt = state.points[i], pt.player == player else { continue }
        // Distance to bear off
        let dist = player == .gold ? (24 - i) : (i + 1)
        pips += dist * pt.count
    }

    // Bar pieces have max distance
    pips += (state.bar[player] ?? 0) * 25

    return pips
}
