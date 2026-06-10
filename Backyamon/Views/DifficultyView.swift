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
            RadialGradient(
                colors: [
                    Theme.bgGlow,
                    Theme.bgDeep
                ],
                center: .top,
                startRadius: 80,
                endRadius: 600
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("CHOOSE YOUR OPPONENT")
                            .font(Theme.serifBold(18))
                            .foregroundStyle(.white)
                            .tracking(4)
                            .shadow(color: Theme.gold.opacity(0.3), radius: 10)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.clear, Theme.gold.opacity(0.6), .clear],
                                startPoint: .leading,
                                endPoint: .trailing))
                            .frame(width: 120, height: 1)
                    }
                    .padding(.top, 8)

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
                            .font(Theme.serifBold(14))
                            .foregroundStyle(Theme.textSecondary)
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
                            .font(Theme.serifBold(18))
                            .tracking(4)
                            .foregroundStyle(Theme.bg)
                            .frame(width: 220, height: 54)
                            .background(
                                selectedDifficulty != nil
                                    ? AnyShapeStyle(LinearGradient(
                                        colors: [
                                            Theme.goldBright,
                                            Theme.goldDeep
                                        ],
                                        startPoint: .top, endPoint: .bottom))
                                    : AnyShapeStyle(Color.gray.opacity(0.3))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(selectedDifficulty != nil ? 0.25 : 0), lineWidth: 0.8)
                            )
                            .shadow(color: Theme.gold.opacity(selectedDifficulty != nil ? 0.45 : 0),
                                    radius: 12, y: 4)
                    }
                    .disabled(selectedDifficulty == nil)
                    .animation(.easeInOut(duration: 0.25), value: selectedDifficulty)
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
                    .font(Theme.serifBold(20))
                    .foregroundStyle(isSelected
                        ? Theme.bg
                        : .white)
                Text(sub)
                    .font(Theme.serif(10))
                    .foregroundStyle(isSelected
                        ? Theme.bg.opacity(0.7)
                        : Color.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                        ? Theme.gold
                        : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected
                                ? Theme.gold
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

    private var accent: Color {
        switch difficulty {
        case .beachBum:  return Color(red: 0.40, green: 0.78, blue: 0.85)
        case .selector:  return Theme.gold
        case .kingTubby: return Theme.red
        }
    }

    private var icon: String {
        switch difficulty {
        case .beachBum:  return "beach.umbrella.fill"
        case .selector:  return "music.note"
        case .kingTubby: return "crown.fill"
        }
    }

    var body: some View {
        Button {
            selected = difficulty
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(isSelected ? 0.25 : 0.12))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Circle().stroke(accent.opacity(isSelected ? 0.6 : 0.25), lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(Theme.serifBold(18))
                        .foregroundStyle(.white)
                    Text(description)
                        .font(Theme.serif(13))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: isSelected
                                ? [Color.white.opacity(0.14), Color.white.opacity(0.06)]
                                : [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
                }
            )
            .shadow(color: isSelected ? accent.opacity(0.35) : .clear, radius: 12, y: 4)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }
}

extension Difficulty: Hashable {}
