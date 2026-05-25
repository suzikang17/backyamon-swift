import Foundation

func beachBumMove(state: GameState) -> Turn {
    let turns = getAllLegalTurns(state: state)
    let nonEmpty = turns.filter { !$0.isEmpty }
    guard !nonEmpty.isEmpty else { return [] }
    return nonEmpty.randomElement()!
}
