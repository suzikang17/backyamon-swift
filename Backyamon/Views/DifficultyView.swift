import SwiftUI

/// Match-length selection (1 = single game, otherwise best-of-N).
struct MatchSelection: Hashable {
    let difficulty: Difficulty
    let matchLength: Int
}

struct DifficultyView: View {
    @State private var selectedDifficulty: Difficulty? = nil
    @State private var matchLength: Int = 1
    @State private var navigateToGame = false

    private let matchOptions: [(length: Int, label: String, sub: String)] = [
        (1, "1", "Single"),
        (3, "3", "First to 2"),
        (5, "5", "First to 3"),
        (7, "7", "First to 4")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.12, blue: 0.08)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Text("CHOOSE YOUR OPPONENT")
                        .font(.custom("Georgia-Bold", size: 22))
                        .foregroundStyle(.white)
                        .tracking(3)

                    VStack(spacing: 16) {
                        DifficultyCard(
                            name: "Beach Bum",
                            description: "Plays random moves.\nPerfect for a chill game.",
                            difficulty: .beachBum,
                            selected: $selectedDifficulty
                        )
                        DifficultyCard(
                            name: "Selector",
                            description: "Uses strategy to make\nsmart positional choices.",
                            difficulty: .selector,
                            selected: $selectedDifficulty
                        )
                        DifficultyCard(
                            name: "King Tubby",
                            description: "Deep search AI.\nDifficult to beat.",
                            difficulty: .kingTubby,
                            selected: $selectedDifficulty
                        )
                    }

                    VStack(spacing: 12) {
                        Text("MATCH LENGTH")
                            .font(.custom("Georgia-Bold", size: 14))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .tracking(3)

                        HStack(spacing: 8) {
                            ForEach(matchOptions, id: \.length) { opt in
                                MatchLengthChip(
                                    label: opt.label,
                                    sub: opt.sub,
                                    isSelected: matchLength == opt.length
                                ) {
                                    matchLength = opt.length
                                }
                            }
                        }
                    }

                    Button {
                        navigateToGame = true
                    } label: {
                        Text("LET'S PLAY")
                            .font(.custom("Georgia-Bold", size: 18))
                            .tracking(3)
                            .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.08))
                            .frame(width: 200, height: 50)
                            .background(selectedDifficulty != nil
                                ? Color(red: 0.85, green: 0.72, blue: 0.45)
                                : Color.gray.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .disabled(selectedDifficulty == nil)
                    .navigationDestination(isPresented: $navigateToGame) {
                        GameView(difficulty: selectedDifficulty ?? .beachBum, matchLength: matchLength)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct MatchLengthChip: View {
    let label: String
    let sub: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.custom("Georgia-Bold", size: 20))
                    .foregroundStyle(isSelected
                        ? Color(red: 0.08, green: 0.12, blue: 0.08)
                        : .white)
                Text(sub)
                    .font(.custom("Georgia", size: 10))
                    .foregroundStyle(isSelected
                        ? Color(red: 0.08, green: 0.12, blue: 0.08).opacity(0.7)
                        : Color.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                        ? Color(red: 0.85, green: 0.72, blue: 0.45)
                        : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected
                                ? Color(red: 0.85, green: 0.72, blue: 0.45)
                                : Color.white.opacity(0.15),
                                    lineWidth: 1)
                    )
            )
        }
    }
}

struct DifficultyCard: View {
    let name: String
    let description: String
    let difficulty: Difficulty
    @Binding var selected: Difficulty?

    var isSelected: Bool { selected == difficulty }

    var body: some View {
        Button {
            selected = difficulty
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.custom("Georgia-Bold", size: 18))
                        .foregroundStyle(.white)
                    Text(description)
                        .font(.custom("Georgia", size: 14))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.85, green: 0.72, blue: 0.45))
                        .font(.title2)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                        ? Color.white.opacity(0.12)
                        : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected
                                ? Color(red: 0.85, green: 0.72, blue: 0.45).opacity(0.6)
                                : Color.clear, lineWidth: 1)
                    )
            )
        }
    }
}

extension Difficulty: Hashable {}
