import Foundation

func getAllLegalTurns(state: GameState) -> [Turn] {
    var results: [Turn] = []
    collectTurns(state: state, currentTurn: [], results: &results)

    if results.isEmpty { return [[]] }

    // Enforce max dice usage: filter to turns that used the most dice
    let maxUsed = results.map { $0.count }.max() ?? 0
    let maxTurns = results.filter { $0.count == maxUsed }

    // If only one die can be used, must use the higher die
    if maxUsed == 1 {
        guard let dice = state.dice else { return maxTurns }
        let uniqueDice = Set(dice.remaining)
        if uniqueDice.count > 1 {
            let maxDie = uniqueDice.max()!
            let filtered = maxTurns.filter { $0.first?.dieUsed == maxDie }
            return filtered.isEmpty ? maxTurns : filtered
        }
    }

    return maxTurns
}

private func collectTurns(state: GameState, currentTurn: Turn, results: inout [Turn]) {
    let moves = getLegalMoves(state: state)

    if moves.isEmpty {
        if !currentTurn.isEmpty {
            results.append(currentTurn)
        }
        return
    }

    // Deduplicate moves by (from, to, dieUsed) to avoid exponential blowup with doubles
    var seen = Set<MoveKey>()
    for move in moves {
        let key = MoveKey(move: move)
        if seen.contains(key) { continue }
        seen.insert(key)

        let nextState = applyMove(state: state, move: move)
        collectTurns(state: nextState, currentTurn: currentTurn + [move], results: &results)
    }
}

private struct MoveKey: Hashable {
    let fromBar: Bool
    let fromIdx: Int
    let toOff: Bool
    let toIdx: Int
    let die: Int

    init(move: Move) {
        switch move.from {
        case .bar: fromBar = true; fromIdx = -1
        case .point(let i): fromBar = false; fromIdx = i
        }
        switch move.to {
        case .off: toOff = true; toIdx = -1
        case .point(let i): toOff = false; toIdx = i
        }
        die = move.dieUsed
    }
}
