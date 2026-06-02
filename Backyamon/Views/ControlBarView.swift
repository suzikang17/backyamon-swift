import SwiftUI

struct ControlBarView<Game: GameControlling>: View {
    @ObservedObject var game: Game
    @ObservedObject private var sound = SoundManager.shared
    @ObservedObject private var music = MusicEngine.shared

    private let gold = Color(red: 0.92, green: 0.78, blue: 0.45)

    var body: some View {
        HStack(spacing: 14) {
            IconButton(systemName: "arrow.uturn.backward",
                       active: game.canUndo,
                       action: { game.undo() })
                .disabled(!game.canUndo)

            IconButton(systemName: sound.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       active: !sound.isMuted,
                       action: { sound.toggleMute() })

            IconButton(systemName: music.isMusicEnabled ? "music.note" : "music.note.slash",
                       active: music.isMusicEnabled,
                       action: { music.toggleMusic() })

            Spacer()

            if game.state.phase == .rolling && game.isHumanTurn {
                RollButton(action: { game.performRoll() })
            } else if game.isAIThinking {
                Text("thinking…")
                    .font(.custom("Georgia-Italic", size: 14))
                    .foregroundStyle(Color.white.opacity(0.45))
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
                        .font(.custom("Georgia-Bold", size: 14))
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
                }
            } else {
                Text("×\(game.state.doublingCube.value)")
                    .font(.custom("Georgia", size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active
                    ? Color(red: 0.92, green: 0.78, blue: 0.45)
                    : Color.white.opacity(0.25))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(Color.white.opacity(active ? 0.06 : 0.02))
                )
                .overlay(
                    Circle()
                        .stroke(active
                            ? Color(red: 0.92, green: 0.78, blue: 0.45).opacity(0.25)
                            : Color.clear, lineWidth: 0.8)
                )
        }
    }
}

private struct RollButton: View {
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            Text("ROLL")
                .font(.custom("Georgia-Bold", size: 18))
                .tracking(5)
                .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.08))
                .frame(width: 140, height: 48)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.85, blue: 0.52),
                            Color(red: 0.82, green: 0.65, blue: 0.32)
                        ],
                        startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.8)
                )
                .shadow(color: Color(red: 0.92, green: 0.78, blue: 0.45).opacity(pulse ? 0.7 : 0.4),
                        radius: pulse ? 16 : 10, y: 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
