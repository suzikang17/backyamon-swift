import Foundation

func checkWinner(state: GameState) -> Player? {
    for player in Player.allCases {
        if (state.borneOff[player] ?? 0) >= PIECES_PER_PLAYER {
            return player
        }
    }
    return nil
}

func getWinType(winner: Player, state: GameState) -> WinType {
    let loser = opponent(of: winner)
    let loserBorneOff = state.borneOff[loser] ?? 0
    let loserOnBar = state.bar[loser] ?? 0

    if loserBorneOff > 0 {
        return "ya_mon"
    }

    let loserInWinnerHome = countPiecesInRange(for: loser, state: state,
                                               range: HOME_BOARD_START[winner]!...HOME_BOARD_END[winner]!)
    if loserOnBar > 0 || loserInWinnerHome > 0 {
        return "massive_ya_mon"
    }

    return "big_ya_mon"
}

private func countPiecesInRange(for player: Player, state: GameState, range: ClosedRange<Int>) -> Int {
    var count = 0
    let lo = min(range.lowerBound, range.upperBound)
    let hi = max(range.lowerBound, range.upperBound)
    for i in lo...hi {
        if let pt = state.points[i], pt.player == player {
            count += pt.count
        }
    }
    return count
}

func getPointsWon(winType: WinType, cubeValue: Int) -> Int {
    let multiplier: Int
    switch winType {
    case "ya_mon": multiplier = 1
    case "big_ya_mon": multiplier = 2
    case "massive_ya_mon": multiplier = 3
    default: multiplier = 1
    }
    return multiplier * cubeValue
}
