import Foundation

private let TIME_LIMIT: TimeInterval = 1.8
private let SEARCH_DEPTH = 2

// All 21 unique dice combinations with weights (doubles=1, others=2)
private let ALL_DICE_COMBOS: [(Int, Int, Int)] = {
    var combos: [(Int, Int, Int)] = []
    for d1 in 1...6 {
        for d2 in d1...6 {
            let weight = d1 == d2 ? 1 : 2
            combos.append((d1, d2, weight))
        }
    }
    return combos
}()

func kingTubbyMove(state: GameState) -> Turn {
    let turns = getAllLegalTurns(state: state)
    let nonEmpty = turns.filter { !$0.isEmpty }
    guard !nonEmpty.isEmpty else { return [] }

    let player = state.currentPlayer
    let deadline = Date().addingTimeInterval(TIME_LIMIT)
    var bestTurn = nonEmpty[0]
    var bestScore = Int.min

    for turn in nonEmpty {
        var s = state
        for move in turn { s = applyMove(state: s, move: move) }
        let score = expectiminimax(state: s, depth: SEARCH_DEPTH - 1,
                                   maximizing: false, player: player,
                                   alpha: Int.min, beta: Int.max, deadline: deadline)
        if score > bestScore {
            bestScore = score
            bestTurn = turn
        }
        if Date() > deadline { break }
    }

    return bestTurn
}

private func expectiminimax(state: GameState, depth: Int, maximizing: Bool,
                             player: Player, alpha: Int, beta: Int, deadline: Date) -> Int {
    if let winner = checkWinner(state: state) {
        return winner == player ? 10000 : -10000
    }
    if depth == 0 { return evaluateBoard(state: state, for: player) }
    if Date() > deadline { return evaluateBoard(state: state, for: player) }

    // Chance node: average over all dice rolls
    let totalWeight = ALL_DICE_COMBOS.reduce(0) { $0 + $1.2 }
    var expectedValue = 0.0

    for (d1, d2, weight) in ALL_DICE_COMBOS {
        let remaining = d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
        var diceState = cloneState(state)
        diceState.dice = Dice(values: (d1, d2), remaining: remaining)
        diceState.phase = .moving

        let currentPlayer = maximizing ? player : opponent(of: player)
        diceState.currentPlayer = currentPlayer

        let turns = getAllLegalTurns(state: diceState)
        let nonEmpty = turns.filter { !$0.isEmpty }

        var nodeScore: Int
        if nonEmpty.isEmpty {
            nodeScore = evaluateBoard(state: diceState, for: player)
        } else if maximizing {
            var best = Int.min
            var a = alpha
            for turn in nonEmpty {
                var s = diceState
                for move in turn { s = applyMove(state: s, move: move) }
                let v = expectiminimax(state: s, depth: depth - 1, maximizing: false,
                                       player: player, alpha: a, beta: beta, deadline: deadline)
                best = max(best, v)
                a = max(a, v)
                if a >= beta || Date() > deadline { break }
            }
            nodeScore = best
        } else {
            var worst = Int.max
            var b = beta
            for turn in nonEmpty {
                var s = diceState
                for move in turn { s = applyMove(state: s, move: move) }
                let v = expectiminimax(state: s, depth: depth - 1, maximizing: true,
                                       player: player, alpha: alpha, beta: b, deadline: deadline)
                worst = min(worst, v)
                b = min(b, v)
                if alpha >= b || Date() > deadline { break }
            }
            nodeScore = worst
        }

        expectedValue += Double(weight * nodeScore)
    }

    return Int(expectedValue / Double(totalWeight))
}
