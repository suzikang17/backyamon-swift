import SwiftUI

struct GameOverView: View {
    let state: GameState
    let matchWinner: Player?
    let onPrimaryAction: () -> Void
    let onQuit: () -> Void

    var winMessage: String {
        switch state.winType {
        case "ya_mon": return "Ya Mon!"
        case "big_ya_mon": return "Big Ya Mon!"
        case "massive_ya_mon": return "Massive Ya Mon!"
        default: return "Game Over"
        }
    }

    var isHumanWinner: Bool { state.winner == .gold }
    var isMatchOver: Bool { matchWinner != nil }
    var isMatchPlay: Bool { state.matchLength > 1 }
    var isHumanMatchWinner: Bool { matchWinner == .gold }

    private var matchTarget: Int { (state.matchLength + 1) / 2 }
    private var goldScore: Int { state.matchScore[.gold] ?? 0 }
    private var redScore: Int { state.matchScore[.red] ?? 0 }

    private var primaryLabel: String {
        if isMatchOver { return "PLAY AGAIN" }
        if isMatchPlay { return "NEXT GAME" }
        return "REMATCH"
    }

    private var headlineText: String {
        if isMatchOver {
            return isHumanMatchWinner ? "YOU WIN THE MATCH!" : "CPU WINS THE MATCH!"
        }
        return isHumanWinner ? "YOU WIN" : "CPU WINS"
    }

    private var headlineColor: Color {
        let winnerIsHuman = isMatchOver ? isHumanMatchWinner : isHumanWinner
        return winnerIsHuman
            ? Color(red: 0.85, green: 0.72, blue: 0.45)
            : Color(red: 0.7, green: 0.2, blue: 0.2)
    }

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Text(headlineText)
                        .font(.custom("Georgia-Bold", size: isMatchOver ? 28 : 34))
                        .foregroundStyle(headlineColor)
                        .tracking(4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .shadow(color: headlineColor.opacity(0.45), radius: 14, y: 0)

                    // Decorative accent line
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, headlineColor.opacity(0.6), .clear],
                            startPoint: .leading,
                            endPoint: .trailing))
                        .frame(width: 160, height: 1)

                    Text(winMessage)
                        .font(.custom("Georgia", size: 22))
                        .foregroundStyle(.white)
                        .italic()

                    if isMatchPlay {
                        VStack(spacing: 6) {
                            Text("MATCH TO \(matchTarget)")
                                .font(.custom("Georgia-Bold", size: 11))
                                .tracking(3)
                                .foregroundStyle(Color.white.opacity(0.55))
                            HStack(spacing: 18) {
                                ScoreColumn(label: "YOU",
                                            value: goldScore,
                                            color: Color(red: 0.92, green: 0.78, blue: 0.45))
                                Text("–")
                                    .font(.custom("Georgia", size: 22))
                                    .foregroundStyle(Color.white.opacity(0.5))
                                ScoreColumn(label: "CPU",
                                            value: redScore,
                                            color: Color(red: 0.82, green: 0.22, blue: 0.20))
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        onPrimaryAction()
                    } label: {
                        Text(primaryLabel)
                            .font(.custom("Georgia-Bold", size: 16))
                            .tracking(3)
                            .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.08))
                            .frame(width: 220, height: 50)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.85, blue: 0.52),
                                        Color(red: 0.82, green: 0.65, blue: 0.32)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                            .shadow(color: Color(red: 0.92, green: 0.78, blue: 0.45).opacity(0.4), radius: 10, y: 4)
                    }

                    Button {
                        onQuit()
                    } label: {
                        Text("QUIT")
                            .font(.custom("Georgia-Bold", size: 14))
                            .tracking(3)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .frame(width: 220, height: 42)
                            .background(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(
                            colors: [
                                Color(red: 0.11, green: 0.16, blue: 0.11),
                                Color(red: 0.05, green: 0.08, blue: 0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(headlineColor.opacity(isMatchOver ? 0.7 : 0.3), lineWidth: isMatchOver ? 2 : 1)
                }
            )
            .shadow(color: Color.black.opacity(0.6), radius: 20, y: 6)
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.70)) {
                appeared = true
            }
        }
    }
}

private struct ScoreColumn: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Text("\(value)")
                .font(.custom("Georgia-Bold", size: 30))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.4), radius: 6)
        }
    }
}
