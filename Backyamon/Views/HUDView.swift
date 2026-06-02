import SwiftUI

struct HUDView<Game: GameControlling>: View {
    @ObservedObject var game: Game
    /// Labels for the two scoreboards. Defaults to "YOU"/"CPU" for AI play;
    /// online mode passes "YOU"/opponent display name.
    var leftLabel: String = "YOU"
    var rightLabel: String = "CPU"

    var body: some View {
        VStack(spacing: 4) {
            if game.state.matchLength > 1 {
                HStack(spacing: 6) {
                    Text("MATCH TO \(game.matchTarget)")
                        .font(.custom("Georgia-Bold", size: 10))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0.65))
                    if game.state.isCrawford {
                        Text("• CRAWFORD")
                            .font(.custom("Georgia-Bold", size: 10))
                            .tracking(2)
                            .foregroundStyle(Color(red: 0.85, green: 0.72, blue: 0.45))
                    }
                }
                .padding(.top, 2)
            }

            HStack(alignment: .center, spacing: 0) {
                PlayerScore(
                    label: leftLabel,
                    score: game.state.matchScore[game.humanPlayer] ?? 0,
                    color: game.humanPlayer == .gold
                        ? Color(red: 0.92, green: 0.78, blue: 0.45)
                        : Color(red: 0.82, green: 0.22, blue: 0.20),
                    isActive: game.state.currentPlayer == game.humanPlayer
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        if let dice = game.state.dice {
                            DieView(value: dice.values.0,
                                    used: !dice.remaining.contains(dice.values.0))
                            DieView(value: dice.values.1,
                                    used: !dice.remaining.contains(dice.values.1))
                        }
                        DoublingCubeView(cube: game.state.doublingCube)
                    }
                    Text(game.message)
                        .font(.custom("Georgia", size: 13))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)

                PlayerScore(
                    label: rightLabel,
                    score: game.state.matchScore[opponent(of: game.humanPlayer)] ?? 0,
                    color: opponent(of: game.humanPlayer) == .gold
                        ? Color(red: 0.92, green: 0.78, blue: 0.45)
                        : Color(red: 0.82, green: 0.22, blue: 0.20),
                    isActive: game.state.currentPlayer != game.humanPlayer
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
    }
}

struct PlayerScore: View {
    let label: String
    let score: Int
    let color: Color
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isActive ? 0.85 : 0.45))
                    .tracking(2)
            }
            Text("\(score)")
                .font(.custom("Georgia-Bold", size: 28))
                .foregroundStyle(color)
                .shadow(color: color.opacity(isActive ? 0.4 : 0), radius: 6)
        }
    }
}

struct DieView: View {
    let value: Int
    let used: Bool

    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0

    private let pipPositions: [Int: [(Double, Double)]] = [
        1: [(0.5, 0.5)],
        2: [(0.25, 0.25), (0.75, 0.75)],
        3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
        4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
        5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
        6: [(0.25, 0.2), (0.75, 0.2), (0.25, 0.5), (0.75, 0.5), (0.25, 0.8), (0.75, 0.8)]
    ]

    var body: some View {
        let size: CGFloat = 34
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(used
                      ? LinearGradient(colors: [Color(white: 0.22), Color(white: 0.14)],
                                       startPoint: .top, endPoint: .bottom)
                      : LinearGradient(colors: [Color(red: 1.0, green: 0.98, blue: 0.92),
                                                 Color(red: 0.86, green: 0.82, blue: 0.74)],
                                       startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(used ? Color.black.opacity(0.5) : Color(red: 0.55, green: 0.50, blue: 0.40), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1.5)

            ForEach(Array((pipPositions[value] ?? []).enumerated()), id: \.0) { _, pos in
                Circle()
                    .fill(used ? Color(white: 0.42) : Color(red: 0.10, green: 0.08, blue: 0.06))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .shadow(color: Color.white.opacity(used ? 0 : 0.4), radius: 0.5, x: 0, y: -0.4)
                    .offset(x: (pos.0 - 0.5) * size * 0.7,
                            y: (pos.1 - 0.5) * size * 0.7)
            }
        }
        .rotation3DEffect(.degrees(rotation), axis: (x: 1, y: 1, z: 0))
        .scaleEffect(scale)
        .onChange(of: value) { _, _ in
            rotation = 0
            scale = 0.6
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                rotation = 360
                scale = 1.0
            }
        }
    }
}

struct DoublingCubeView: View {
    let cube: DoublingCube

    private var borderColor: Color {
        switch cube.holder {
        case .gold: return Color(red: 0.92, green: 0.78, blue: 0.45)
        case .red:  return Color(red: 0.82, green: 0.22, blue: 0.20)
        case .none: return Color.white.opacity(0.45)
        }
    }

    private var displayValue: Int {
        cube.value == 1 ? 64 : cube.value
    }

    var body: some View {
        let size: CGFloat = 30
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.98, blue: 0.92),
                                               Color(red: 0.86, green: 0.82, blue: 0.74)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1.5)
            Text("\(displayValue)")
                .font(.custom("Georgia-Bold", size: 14))
                .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.08))
        }
        .opacity(cube.offered ? 0.65 : 1.0)
        .scaleEffect(cube.offered ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: cube.offered)
    }
}
