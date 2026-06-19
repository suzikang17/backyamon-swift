import SwiftUI

/// Scoreboard + dice + message, floated across the top of the board as a
/// translucent strip (it reads as part of the felt rather than stealing
/// vertical space from the board the way a solid top bar would).
struct BoardHUDOverlay<Game: GameControlling>: View {
    @ObservedObject var game: Game

    var body: some View {
        VStack(spacing: 4) {
            if game.state.matchLength > 1 {
                HStack(spacing: 6) {
                    Text("MATCH TO \(game.matchTarget)")
                        .font(Theme.serifBold(10))
                        .tracking(2)
                        .foregroundStyle(Theme.textSecondary)
                    if game.state.isCrawford {
                        Text("• CRAWFORD")
                            .font(Theme.serifBold(10))
                            .tracking(2)
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
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
                .font(Theme.serif(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.5), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct PlayerScore: View {
    let label: String
    let score: Int
    let color: Color
    let isActive: Bool

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .scaleEffect(isActive && pulse ? 1.35 : 1.0)
                    .shadow(color: color.opacity(isActive ? 0.65 : 0),
                            radius: pulse ? 6 : 2)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isActive ? 0.92 : 0.55))
                    .tracking(2)
            }
            Text("\(score)")
                .font(Theme.serifBold(28))
                .foregroundStyle(color)
                .shadow(color: color.opacity(isActive ? 0.4 : 0), radius: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(score) points\(isActive ? ", their turn" : "")")
        .onAppear {
            guard !reduceMotion, !pulse else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
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
        case .gold: return Theme.gold
        case .red:  return Theme.red
        case .none: return Color.white.opacity(0.45)
        }
    }

    private var displayValue: Int {
        cube.value == 1 ? 64 : cube.value
    }

    var body: some View {
        // Dark fill + gold numeral so the cube can't be mistaken for a
        // third die next to the ivory dice in the HUD.
        let size: CGFloat = 30
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1.5)
            Text("\(displayValue)")
                .font(Theme.serifBold(13))
                .foregroundStyle(Theme.gold)
        }
        .padding(.leading, 6)
        .opacity(cube.offered ? 0.65 : 1.0)
        .scaleEffect(cube.offered ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: cube.offered)
        .accessibilityLabel("Doubling cube at \(cube.value)")
    }
}

// MARK: - Roll overlay

/// Light overlay shown over the board when it's the local player's turn to
/// roll. Two large dice sit over a dimmed board; swiping up (or tapping)
/// tumbles them and performs the roll.
struct RollDiceOverlay<Game: GameControlling>: View {
    @ObservedObject var game: Game

    @State private var faces: (Int, Int) = (1, 1)
    @State private var tumbling = false
    @State private var dragY: CGFloat = 0
    @State private var hintBob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)

            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    DieFace(value: faces.0)
                    DieFace(value: faces.1)
                }
                .offset(y: dragY)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 5)

                if !tumbling {
                    VStack(spacing: 6) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.gold)
                            .offset(y: hintBob ? -5 : 3)
                        Text("Swipe up to roll")
                            .font(Theme.serifItalic(14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .opacity(Double(max(0, 1 + dragY / 70)))
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    guard !tumbling else { return }
                    dragY = min(0, value.translation.height)
                }
                .onEnded { value in
                    guard !tumbling else { return }
                    if value.translation.height < -40 {
                        roll()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragY = 0 }
                    }
                }
        )
        .onTapGesture {
            if !tumbling { roll() }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Roll dice")
        .accessibilityHint("Swipe up or double tap to roll")
        .accessibilityAction { if !tumbling { roll() } }
        .onAppear {
            if let dice = game.state.dice { faces = dice.values }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                hintBob = true
            }
        }
    }

    private func roll() {
        guard !tumbling else { return }
        guard !reduceMotion else {
            game.performRoll()
            return
        }
        tumbling = true
        HapticManager.shared.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { dragY = -36 }
        Task { @MainActor in
            for _ in 0..<9 {
                faces = (Int.random(in: 1...6), Int.random(in: 1...6))
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
            game.performRoll()
            if let dice = game.state.dice { faces = dice.values }
        }
    }
}

/// A single large die face with a quick 3D tumble whenever its value changes.
private struct DieFace: View {
    let value: Int
    var size: CGFloat = 62

    @State private var rotation: Double = 0

    private let pips: [Int: [(Double, Double)]] = [
        1: [(0.5, 0.5)],
        2: [(0.28, 0.28), (0.72, 0.72)],
        3: [(0.28, 0.28), (0.5, 0.5), (0.72, 0.72)],
        4: [(0.28, 0.28), (0.72, 0.28), (0.28, 0.72), (0.72, 0.72)],
        5: [(0.28, 0.28), (0.72, 0.28), (0.5, 0.5), (0.28, 0.72), (0.72, 0.72)],
        6: [(0.28, 0.22), (0.72, 0.22), (0.28, 0.5), (0.72, 0.5), (0.28, 0.78), (0.72, 0.78)]
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.98, blue: 0.92),
                                              Color(red: 0.86, green: 0.82, blue: 0.74)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2)
                        .stroke(Color(red: 0.55, green: 0.50, blue: 0.40), lineWidth: 1)
                )

            ForEach(Array((pips[value] ?? []).enumerated()), id: \.0) { _, pip in
                Circle()
                    .fill(Color(red: 0.10, green: 0.08, blue: 0.06))
                    .frame(width: size * 0.16, height: size * 0.16)
                    .offset(x: (pip.0 - 0.5) * size * 0.72,
                            y: (pip.1 - 0.5) * size * 0.72)
            }
        }
        .rotation3DEffect(.degrees(rotation), axis: (x: 1, y: 1, z: 0))
        .onChange(of: value) { _, _ in
            withAnimation(.easeOut(duration: 0.12)) { rotation += 200 }
        }
    }
}
