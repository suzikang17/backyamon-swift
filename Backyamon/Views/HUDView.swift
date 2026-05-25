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
                // Score (local player, i.e. humanPlayer)
                VStack(spacing: 2) {
                    Text(leftLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .tracking(2)
                    Text("\(game.state.matchScore[game.humanPlayer] ?? 0)")
                        .font(.custom("Georgia-Bold", size: 28))
                        .foregroundStyle(Color(red: 0.85, green: 0.72, blue: 0.45))
                }
                .frame(maxWidth: .infinity)

                // Message / dice display
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

                // Opponent score
                VStack(spacing: 2) {
                    Text(rightLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .tracking(2)
                    Text("\(game.state.matchScore[opponent(of: game.humanPlayer)] ?? 0)")
                        .font(.custom("Georgia-Bold", size: 28))
                        .foregroundStyle(Color(red: 0.7, green: 0.2, blue: 0.2))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
    }
}

struct DieView: View {
    let value: Int
    let used: Bool

    private let pipPositions: [Int: [(Double, Double)]] = [
        1: [(0.5, 0.5)],
        2: [(0.25, 0.25), (0.75, 0.75)],
        3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
        4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
        5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
        6: [(0.25, 0.2), (0.75, 0.2), (0.25, 0.5), (0.75, 0.5), (0.25, 0.8), (0.75, 0.8)]
    ]

    var body: some View {
        let size: CGFloat = 32
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(used ? Color(white: 0.2) : Color(red: 0.96, green: 0.94, blue: 0.88))
                .frame(width: size, height: size)

            ForEach(Array((pipPositions[value] ?? []).enumerated()), id: \.0) { _, pos in
                Circle()
                    .fill(used ? Color(white: 0.45) : Color(white: 0.1))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .offset(x: (pos.0 - 0.5) * size * 0.7,
                            y: (pos.1 - 0.5) * size * 0.7)
            }
        }
    }
}

struct DoublingCubeView: View {
    let cube: DoublingCube

    private var borderColor: Color {
        switch cube.holder {
        case .gold: return Color(red: 0.85, green: 0.72, blue: 0.45)
        case .red:  return Color(red: 0.7, green: 0.2, blue: 0.2)
        case .none: return Color.white.opacity(0.4)
        }
    }

    private var displayValue: Int {
        cube.value == 1 ? 64 : cube.value
    }

    var body: some View {
        let size: CGFloat = 28
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.96, green: 0.94, blue: 0.88))
                .frame(width: size, height: size)
            RoundedRectangle(cornerRadius: 5)
                .stroke(borderColor, lineWidth: 2)
                .frame(width: size, height: size)
            Text("\(displayValue)")
                .font(.custom("Georgia-Bold", size: 13))
                .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.08))
        }
        .opacity(cube.offered ? 0.65 : 1.0)
        .scaleEffect(cube.offered ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: cube.offered)
    }
}
