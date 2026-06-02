import SwiftUI

struct ControlBarView<Game: GameControlling>: View {
    @ObservedObject var game: Game
    @ObservedObject private var sound = SoundManager.shared
    @ObservedObject private var music = MusicEngine.shared

    var body: some View {
        HStack(spacing: 20) {
            // Undo
            Button {
                game.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title2)
                    .foregroundStyle(game.canUndo ? Color.white : Color.white.opacity(0.2))
            }
            .disabled(!game.canUndo)

            // Mute toggle
            Button {
                sound.toggleMute()
            } label: {
                Image(systemName: sound.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(sound.isMuted
                        ? Color(red: 0.85, green: 0.72, blue: 0.45).opacity(0.5)
                        : Color(red: 0.85, green: 0.72, blue: 0.45))
            }

            // Music toggle
            Button {
                music.toggleMusic()
            } label: {
                Image(systemName: music.isMusicEnabled ? "music.note" : "music.note.slash")
                    .font(.title3)
                    .foregroundStyle(music.isMusicEnabled
                        ? Color(red: 0.85, green: 0.72, blue: 0.45)
                        : Color(red: 0.85, green: 0.72, blue: 0.45).opacity(0.5))
            }

            Spacer()

            // Roll button
            if game.state.phase == .rolling && game.isHumanTurn {
                Button {
                    game.performRoll()
                } label: {
                    Text("ROLL")
                        .font(.custom("Georgia-Bold", size: 18))
                        .tracking(4)
                        .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.08))
                        .frame(width: 120, height: 46)
                        .background(Color(red: 0.85, green: 0.72, blue: 0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } else if game.isAIThinking {
                Text("thinking...")
                    .font(.custom("Georgia", size: 14))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .italic()
            } else {
                Color.clear.frame(width: 140, height: 46)
            }

            Spacer()

            // Double button (visible when human may offer a double)
            if game.canHumanOfferDouble {
                Button {
                    game.offerDouble()
                } label: {
                    Text("2×")
                        .font(.custom("Georgia-Bold", size: 14))
                        .tracking(1)
                        .foregroundStyle(Color(red: 0.85, green: 0.72, blue: 0.45))
                        .frame(width: 48, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(red: 0.85, green: 0.72, blue: 0.45), lineWidth: 1)
                        )
                }
            } else {
                // Cube value label fallback
                Text("×\(game.state.doublingCube.value)")
                    .font(.custom("Georgia", size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 48, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
    }
}
