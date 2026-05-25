import Foundation

func createInitialState(matchLength: Int = 1) -> GameState {
    var points: [PointState?] = Array(repeating: nil, count: 24)

    for (player, positions) in INITIAL_POSITIONS {
        for (idx, count) in positions {
            points[idx] = PointState(player: player, count: count)
        }
    }

    return GameState(
        points: points,
        bar: [.gold: 0, .red: 0],
        borneOff: [.gold: 0, .red: 0],
        currentPlayer: .gold,
        phase: .rolling,
        dice: nil,
        doublingCube: DoublingCube(value: 1, holder: nil, offered: false),
        matchScore: [.gold: 0, .red: 0],
        matchLength: matchLength,
        isCrawford: false,
        winner: nil,
        winType: nil
    )
}

func cloneState(_ state: GameState) -> GameState {
    return GameState(
        points: state.points,
        bar: state.bar,
        borneOff: state.borneOff,
        currentPlayer: state.currentPlayer,
        phase: state.phase,
        dice: state.dice,
        doublingCube: state.doublingCube,
        matchScore: state.matchScore,
        matchLength: state.matchLength,
        isCrawford: state.isCrawford,
        winner: state.winner,
        winType: state.winType
    )
}
