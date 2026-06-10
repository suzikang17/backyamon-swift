import SwiftUI

/// Game screen for single-player (AI) matches.
struct GameView: View {
    private let difficulty: Difficulty
    private let matchLength: Int
    @StateObject private var game: GameController
    @State private var selectedFrom: MoveFrom? = nil
    @State private var showQuitConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(difficulty: Difficulty, matchLength: Int = 1) {
        self.difficulty = difficulty
        self.matchLength = matchLength
        _game = StateObject(wrappedValue: GameController(difficulty: difficulty,
                                                        matchLength: matchLength))
    }

    var body: some View {
        ZStack {
            Theme.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HUDView(game: game, leftLabel: "YOU", rightLabel: "CPU")

                Spacer(minLength: 8)

                GeometryReader { geo in
                    BoardView(
                        state: game.state,
                        legalMoves: game.legalMoves,
                        selectedFrom: $selectedFrom,
                        onMove: { move in
                            game.applyPlayerMove(move)
                            selectedFrom = nil
                        }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                Spacer(minLength: 8)

                ControlBarView(game: game)
            }

            if game.aiDoubleOffered && game.state.winner == nil {
                DoubleOfferOverlay(
                    proposedValue: min(game.state.doublingCube.value * 2, 64),
                    onAccept: { game.acceptDouble(by: .gold) },
                    onReject: { game.rejectDouble(by: .gold) }
                )
            }

            if game.state.phase == .gameOver {
                GameOverView(
                    state: game.state,
                    matchWinner: game.matchWinner,
                    onPrimaryAction: {
                        if game.matchWinner != nil {
                            game.newGame(difficulty: difficulty, matchLength: matchLength)
                        } else if game.state.matchLength > 1 {
                            game.nextGame()
                        } else {
                            game.newGame(difficulty: difficulty, matchLength: matchLength)
                        }
                    },
                    onQuit: { dismiss() }
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                QuitGameButton { showQuitConfirm = true }
            }
        }
        .confirmationDialog("Leave this game?",
                            isPresented: $showQuitConfirm,
                            titleVisibility: .visible) {
            Button("Leave Game", role: .destructive) { dismiss() }
            Button("Keep Playing", role: .cancel) { }
        } message: {
            Text("Your current game will be lost.")
        }
        .onAppear {
            game.newGame(difficulty: difficulty, matchLength: matchLength)
        }
    }
}

/// Compact themed quit affordance for game screens — the nav bar background
/// is hidden, so this is the only chrome over the felt.
struct QuitGameButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().stroke(Theme.gold.opacity(0.3), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Leave game")
    }
}

/// Game screen for online matches. Driven by an `OnlineGameController` which
/// receives state from the server via `SocketClient`.
struct OnlineGameView: View {
    @StateObject private var game: OnlineGameController
    @State private var selectedFrom: MoveFrom? = nil
    @State private var showQuitConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(socket: SocketClient, roomId: String) {
        _game = StateObject(wrappedValue: OnlineGameController(socket: socket, roomId: roomId))
    }

    var body: some View {
        ZStack {
            Theme.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HUDView(game: game, leftLabel: "YOU", rightLabel: game.opponentName.uppercased())

                if game.isOpponentDisconnected {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.gold)
                        Text("Opponent disconnected — waiting for reconnect")
                            .font(Theme.serif(12))
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.4))
                }

                Spacer(minLength: 8)

                GeometryReader { geo in
                    BoardView(
                        state: game.state,
                        legalMoves: game.legalMoves,
                        selectedFrom: $selectedFrom,
                        onMove: { move in
                            game.applyPlayerMove(move)
                            selectedFrom = nil
                        }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                Spacer(minLength: 8)

                ControlBarView(game: game)
            }

            if game.aiDoubleOffered && game.state.winner == nil {
                DoubleOfferOverlay(
                    proposedValue: min(game.state.doublingCube.value * 2, 64),
                    onAccept: { game.acceptDouble(by: game.humanPlayer) },
                    onReject: { game.rejectDouble(by: game.humanPlayer) }
                )
            }

            if game.state.phase == .gameOver {
                GameOverView(
                    state: game.state,
                    matchWinner: game.matchWinner,
                    onPrimaryAction: { dismiss() },
                    onQuit: { dismiss() }
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                QuitGameButton { showQuitConfirm = true }
            }
        }
        .confirmationDialog("Leave this match?",
                            isPresented: $showQuitConfirm,
                            titleVisibility: .visible) {
            Button("Leave Match", role: .destructive) { dismiss() }
            Button("Keep Playing", role: .cancel) { }
        } message: {
            Text("Leaving forfeits the match to your opponent.")
        }
        .onDisappear {
            game.leave()
        }
    }
}

private struct DoubleOfferOverlay: View {
    let proposedValue: Int
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("OPPONENT DOUBLES")
                        .font(Theme.serifBold(18))
                        .tracking(3)
                        .foregroundStyle(Theme.red)
                    Text("Stakes go to \(proposedValue)")
                        .font(Theme.serif(16))
                        .italic()
                        .foregroundStyle(.white)
                }

                HStack(spacing: 16) {
                    Button(action: onReject) {
                        Text("DROP")
                            .font(Theme.serifBold(14))
                            .tracking(3)
                            .foregroundStyle(.white)
                            .frame(width: 130, height: 44)
                            .background(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Button(action: onAccept) {
                        Text("TAKE")
                            .font(Theme.serifBold(14))
                            .tracking(3)
                            .foregroundStyle(Theme.bg)
                            .frame(width: 130, height: 44)
                            .background(Theme.gold)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.gold.opacity(0.5), lineWidth: 1)
                    )
            )
        }
    }
}
