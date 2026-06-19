import SwiftUI

/// Thin vertical control sliver pinned to the left edge of the game screen.
/// Holds quit, the primary ROLL action, the doubling control, and the utility
/// toggles as small stacked buttons so the board can own the rest of the width.
struct LeftSliverBar<Game: GameControlling>: View {
    @ObservedObject var game: Game
    let leftLabel: String
    let rightLabel: String
    let onQuit: () -> Void

    @ObservedObject private var sound = SoundManager.shared
    @ObservedObject private var music = MusicEngine.shared

    private let gold = Theme.gold

    private var humanColor: Color { game.humanPlayer == .gold ? Theme.gold : Theme.red }
    private var opponentColor: Color { opponent(of: game.humanPlayer) == .gold ? Theme.gold : Theme.red }

    var body: some View {
        VStack(spacing: 12) {
            IconButton(systemName: "xmark",
                       active: false,
                       label: "Leave game",
                       action: onQuit)

            SliverScore(label: leftLabel,
                        score: game.state.matchScore[game.humanPlayer] ?? 0,
                        color: humanColor,
                        isActive: game.state.currentPlayer == game.humanPlayer)

            SliverScore(label: rightLabel,
                        score: game.state.matchScore[opponent(of: game.humanPlayer)] ?? 0,
                        color: opponentColor,
                        isActive: game.state.currentPlayer != game.humanPlayer)

            Spacer(minLength: 4)

            if game.isAIThinking {
                Image(systemName: "hourglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 46, height: 46)
            } else {
                Color.clear.frame(width: 46, height: 46)
            }

            if game.canHumanOfferDouble {
                Button {
                    game.offerDouble()
                } label: {
                    Text("2×")
                        .font(Theme.serifBold(14))
                        .tracking(1)
                        .foregroundStyle(gold)
                        .frame(width: 40, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(gold.opacity(0.7), lineWidth: 1)
                        )
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Offer double")
            } else {
                Text("×\(game.state.doublingCube.value)")
                    .font(Theme.serif(12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 40, height: 30)
            }

            Spacer(minLength: 4)

            IconButton(systemName: "arrow.uturn.backward",
                       active: game.canUndo,
                       label: "Undo move",
                       action: { game.undo() })
                .disabled(!game.canUndo)

            IconButton(systemName: sound.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       active: !sound.isMuted,
                       label: sound.isMuted ? "Unmute sound effects" : "Mute sound effects",
                       action: { sound.toggleMute() })

            IconButton(systemName: music.isMusicEnabled ? "music.note" : "music.note.slash",
                       active: music.isMusicEnabled,
                       label: music.isMusicEnabled ? "Turn music off" : "Turn music on",
                       action: { music.toggleMusic() })
        }
        .padding(.vertical, 10)
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.25)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, gold.opacity(0.3), .clear],
                    startPoint: .top,
                    endPoint: .bottom))
                .frame(width: 0.5),
            alignment: .trailing
        )
    }
}

/// Compact score readout for the left sliver — colored dot + label + number,
/// with a glow on the player whose turn it is.
private struct SliverScore: View {
    let label: String
    let score: Int
    let color: Color
    let isActive: Bool

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .shadow(color: color.opacity(isActive ? 0.8 : 0), radius: 3)
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isActive ? 0.9 : 0.5))
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text("\(score)")
                .font(Theme.serifBold(17))
                .foregroundStyle(color)
                .shadow(color: color.opacity(isActive ? 0.4 : 0), radius: 5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(score) points\(isActive ? ", their turn" : "")")
    }
}

// MARK: - Shared buttons

struct IconButton: View {
    let systemName: String
    let active: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active
                    ? Theme.gold
                    : Color.white.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(active ? 0.06 : 0.03))
                )
                .overlay(
                    Circle()
                        .stroke(active
                            ? Theme.gold.opacity(0.25)
                            : Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

