import Foundation
import Combine

/// Common surface area for any controller that drives `GameView`.
///
/// `GameController` (single-player AI) and `OnlineGameController` (multiplayer) both
/// conform. Conformers are required to be `ObservableObject` so SwiftUI views can
/// observe `@Published` properties via `@ObservedObject`/`@StateObject`.
@MainActor
protocol GameControlling: ObservableObject {
    var state: GameState { get }
    var legalMoves: [Move] { get }
    var message: String { get }
    var canUndo: Bool { get }
    var isAIThinking: Bool { get }
    var aiDoubleOffered: Bool { get }
    var matchWinner: Player? { get }

    /// Whether the local human can currently offer a double.
    var canHumanOfferDouble: Bool { get }

    /// The player controlled by the local user. Always `.gold` for single-player.
    /// In online play this is the role the server assigned to us.
    var humanPlayer: Player { get }

    /// True when it is the local human's turn.
    var isHumanTurn: Bool { get }

    /// Optional match-target (points to win the match).
    var matchTarget: Int { get }

    func performRoll()
    func applyPlayerMove(_ move: Move)
    func undo()
    func offerDouble()
    func acceptDouble(by acceptor: Player)
    func rejectDouble(by rejector: Player)
}

extension GameController: GameControlling {}
