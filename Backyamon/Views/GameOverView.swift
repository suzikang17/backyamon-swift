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

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Text(headlineText)
                        .font(.custom("Georgia-Bold", size: isMatchOver ? 30 : 36))
                        .foregroundStyle(headlineColor)
                        .tracking(4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    Text(winMessage)
                        .font(.custom("Georgia", size: 22))
                        .foregroundStyle(.white)
                        .italic()

                    if isMatchPlay {
                        VStack(spacing: 4) {
                            Text("MATCH TO \(matchTarget)")
                                .font(.custom("Georgia-Bold", size: 11))
                                .tracking(3)
                                .foregroundStyle(Color.white.opacity(0.55))
                            HStack(spacing: 16) {
                                VStack(spacing: 2) {
                                    Text("YOU")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(2)
                                        .foregroundStyle(Color.white.opacity(0.5))
                                    Text("\(goldScore)")
                                        .font(.custom("Georgia-Bold", size: 28))
                                        .foregroundStyle(Color(red: 0.85, green: 0.72, blue: 0.45))
                                }
                                Text("–")
                                    .font(.custom("Georgia", size: 22))
                                    .foregroundStyle(Color.white.opacity(0.5))
                                VStack(spacing: 2) {
                                    Text("CPU")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(2)
                                        .foregroundStyle(Color.white.opacity(0.5))
                                    Text("\(redScore)")
                                        .font(.custom("Georgia-Bold", size: 28))
                                        .foregroundStyle(Color(red: 0.7, green: 0.2, blue: 0.2))
                                }
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
                            .frame(width: 200, height: 46)
                            .background(Color(red: 0.85, green: 0.72, blue: 0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Button {
                        onQuit()
                    } label: {
                        Text("QUIT")
                            .font(.custom("Georgia-Bold", size: 16))
                            .tracking(3)
                            .foregroundStyle(.white)
                            .frame(width: 200, height: 46)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.08, green: 0.12, blue: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isMatchOver
                                ? headlineColor.opacity(0.6)
                                : Color.clear,
                                    lineWidth: isMatchOver ? 2 : 0)
                    )
            )
        }
    }
}
