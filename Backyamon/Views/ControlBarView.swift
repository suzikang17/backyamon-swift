import SwiftUI

struct ControlBarView<Game: GameControlling>: View {
    @ObservedObject var game: Game
    @ObservedObject private var sound = SoundManager.shared
    @ObservedObject private var music = MusicEngine.shared

    private let gold = Theme.gold

    var body: some View {
        HStack(spacing: 8) {
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

            Spacer()

            if game.state.phase == .rolling && game.isHumanTurn {
                RollButton(action: { game.performRoll() })
            } else if game.isAIThinking {
                Text("thinking…")
                    .font(Theme.serifItalic(14))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 130, height: 48)
            } else {
                Color.clear.frame(width: 130, height: 48)
            }

            Spacer()

            if game.canHumanOfferDouble {
                Button {
                    game.offerDouble()
                } label: {
                    Text("2×")
                        .font(Theme.serifBold(14))
                        .tracking(1)
                        .foregroundStyle(gold)
                        .frame(width: 48, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(gold.opacity(0.7), lineWidth: 1)
                        )
                        .frame(width: 48, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Offer double")
            } else {
                Text("×\(game.state.doublingCube.value)")
                    .font(Theme.serif(12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 48, height: 34)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.5), Color.black.opacity(0.25)],
                startPoint: .bottom,
                endPoint: .top
            )
        )
        .overlay(
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, gold.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing))
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

private struct IconButton: View {
    let systemName: String
    let active: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active
                    ? Theme.gold
                    : Color.white.opacity(0.55))
                .frame(width: 38, height: 38)
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
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

private struct RollButton: View {
    let action: () -> Void
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text("ROLL")
                .font(Theme.serifBold(18))
                .tracking(5)
                .foregroundStyle(Theme.bg)
                .frame(width: 140, height: 48)
                .background(
                    LinearGradient(
                        colors: [
                            Theme.goldBright,
                            Theme.goldDeep
                        ],
                        startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.8)
                )
                .shadow(color: Theme.gold.opacity(pulse ? 0.7 : 0.4),
                        radius: pulse ? 16 : 10, y: 4)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
