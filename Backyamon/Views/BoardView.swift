import SwiftUI

// MARK: - Layout

/// Pure geometry for the board. Single source of truth for where every point,
/// bar slot, tray slot, and checker sits — used both by the Canvas scaffold and
/// by the individual checker views so they always line up.
private struct BLayout {
    let size: CGSize

    var pad: CGFloat { 10 }
    var boardW: CGFloat { size.width - 2 * pad }
    var boardH: CGFloat { size.height - 2 * pad }

    var zionW: CGFloat { boardW * 0.05 }
    var barW: CGFloat { boardW * 0.055 }
    var playW: CGFloat { boardW - barW - zionW }
    var pw: CGFloat { playW / 12 }
    var halfH: CGFloat { boardH / 2 }

    var playX: CGFloat { pad }
    var barX: CGFloat { playX + 6 * pw }
    var zionX: CGFloat { barX + barW + 6 * pw }

    func pointCX(_ idx: Int) -> CGFloat {
        switch idx {
        case 0...5:   return barX + barW + CGFloat(5 - idx) * pw + pw / 2
        case 6...11:  return playX + CGFloat(11 - idx) * pw + pw / 2
        case 12...17: return playX + CGFloat(idx - 12) * pw + pw / 2
        default:      return barX + barW + CGFloat(idx - 18) * pw + pw / 2
        }
    }

    func baseY(_ idx: Int) -> CGFloat { idx < 12 ? pad : pad + boardH }
    func tipY(_ idx: Int) -> CGFloat  { pad + halfH }

    var barCX: CGFloat { barX + barW / 2 }

    // MARK: Checker placement

    func checkerRadius(pointCount: Int) -> CGFloat {
        min(pw * 0.42, halfH / (2.0 + CGFloat(max(pointCount, 1) - 1) * 1.9))
    }

    func pointCheckerCenter(_ idx: Int, order: Int, count: Int) -> CGPoint {
        let r = checkerRadius(pointCount: count)
        let isTop = idx < 12
        let cy = isTop
            ? pad + r + CGFloat(order) * r * 1.9
            : pad + boardH - r - CGFloat(order) * r * 1.9
        return CGPoint(x: pointCX(idx), y: cy)
    }

    var barR: CGFloat { min(barW * 0.42, 14.0) }

    func barCheckerCenter(player: Player, order: Int) -> CGPoint {
        let r = barR
        let isTop = player == .gold
        let cy = isTop
            ? pad + r + CGFloat(order) * r * 1.9
            : pad + boardH - r - CGFloat(order) * r * 1.9
        return CGPoint(x: barCX, y: cy)
    }

    var offR: CGFloat { min(zionW * 0.38, 12.0) }

    func offCheckerCenter(player: Player, order: Int) -> CGPoint {
        let r = offR
        let cx = zionX + zionW / 2
        let cy = player == .gold
            ? pad + boardH - r - CGFloat(order) * r * 1.9
            : pad + r + CGFloat(order) * r * 1.9
        return CGPoint(x: cx, y: cy)
    }
}

// MARK: - Checker entities

/// Logical location of a checker. Equatable so a checker view can detect when
/// its own slot changed and run a jump.
enum CheckerSlot: Equatable, Hashable {
    case point(Int, order: Int)
    case bar(order: Int)
    case off(order: Int)

    var order: Int {
        switch self {
        case .point(_, let o), .bar(let o), .off(let o): return o
        }
    }
}

/// How a checker arrived at its current slot — drives the flourish it plays.
enum MoveKind {
    case normal
    case hit      // knocked to the bar by an opponent landing
    case bearOff  // taken off the board into the tray
}

/// A single checker with a stable identity that persists across game-state
/// changes, so SwiftUI can animate it from its old slot to its new one.
struct CheckerEntity: Identifiable {
    let id: Int
    let player: Player
    var slot: CheckerSlot
    var kind: MoveKind = .normal
}

// MARK: - Hit result

private enum HitResult {
    case point(Int)
    case bar
    case off
}

// MARK: - BoardView

struct BoardView: View {
    let state: GameState
    let legalMoves: [Move]
    @Binding var selectedFrom: MoveFrom?
    let onMove: (Move) -> Void

    @ObservedObject private var assetManager = AssetManager.shared

    @State private var entities: [CheckerEntity] = []
    @State private var nextCheckerId = 0

    /// Whether a custom community piece is equipped. SVG rendering with
    /// SwiftUI is non-trivial — for now this just signals the renderer to
    /// use a distinct fill colour so the user can tell their custom piece is
    /// active.
    private var customPieceEquipped: Bool {
        assetManager.equippedPieceSvg != nil
    }

    /// Compact fingerprint of all checker positions; drives reconciliation.
    private var boardSignature: String {
        var parts: [String] = []
        for p in state.points {
            if let p { parts.append("\(p.player == .gold ? "g" : "r")\(p.count)") }
            else { parts.append("_") }
        }
        parts.append("bg\(state.bar[.gold] ?? 0)br\(state.bar[.red] ?? 0)")
        parts.append("og\(state.borneOff[.gold] ?? 0)or\(state.borneOff[.red] ?? 0)")
        return parts.joined(separator: ",")
    }

    var body: some View {
        GeometryReader { geo in
            let lay = BLayout(size: geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let boardRect = CGRect(x: lay.pad, y: lay.pad, width: lay.boardW, height: lay.boardH)
                    ctx.clip(to: Path(roundedRect: boardRect, cornerRadius: 6))
                    drawBackground(ctx: ctx, lay: lay)
                    drawPoints(ctx: ctx, lay: lay)
                    drawTray(ctx: ctx, lay: lay)
                    drawHighlights(ctx: ctx, lay: lay)
                }

                checkerLayer(lay: lay)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, lay: lay)
            }
        }
        .onAppear { reconcile() }
        .onChange(of: boardSignature) { _, _ in reconcile() }
    }

    // MARK: Checker layer (animated SwiftUI views)

    @ViewBuilder
    private func checkerLayer(lay: BLayout) -> some View {
        ForEach(entities) { entity in
            let center = placement(for: entity, lay: lay)
            CheckerView(player: entity.player,
                        radius: radius(for: entity, lay: lay),
                        custom: customPieceEquipped)
                .position(center)
                .animation(.spring(response: 0.34, dampingFraction: 0.78), value: center)
                .modifier(CheckerMotionEffect(trigger: entity.slot, kind: entity.kind))
                .zIndex(entity.kind == .normal ? Double(entity.slot.order) : 100)
                .allowsHitTesting(false)
        }
    }

    private func radius(for entity: CheckerEntity, lay: BLayout) -> CGFloat {
        switch entity.slot {
        case .point(let i, _):
            return lay.checkerRadius(pointCount: state.points[i]?.count ?? 1)
        case .bar:
            return lay.barR
        case .off:
            return lay.offR
        }
    }

    private func placement(for entity: CheckerEntity, lay: BLayout) -> CGPoint {
        switch entity.slot {
        case .point(let i, let order):
            let count = state.points[i]?.count ?? (order + 1)
            return lay.pointCheckerCenter(i, order: order, count: count)
        case .bar(let order):
            return lay.barCheckerCenter(player: entity.player, order: order)
        case .off(let order):
            return lay.offCheckerCenter(player: entity.player, order: order)
        }
    }

    // MARK: Reconciliation (stable identity)

    private func reconcile() {
        let hadEntities = !entities.isEmpty
        var result: [CheckerEntity] = []
        for player in Player.allCases {
            let desired = desiredSlots(for: player)
            let existing = entities.filter { $0.player == player }
            result.append(contentsOf: match(player: player, desired: desired, existing: existing))
        }
        entities = result.sorted { $0.id < $1.id }

        // Haptic punctuation for special events (skip the initial build).
        if hadEntities {
            if result.contains(where: { $0.kind == .hit }) {
                HapticManager.shared.heavy()
            } else if result.contains(where: { $0.kind == .bearOff }) {
                HapticManager.shared.success()
            }
        }
    }

    private func kind(old: CheckerSlot?, new: CheckerSlot) -> MoveKind {
        if case .off = new { return .bearOff }
        if case .bar = new, let old, case .point = old { return .hit }
        return .normal
    }

    private func desiredSlots(for player: Player) -> [CheckerSlot] {
        var slots: [CheckerSlot] = []
        for i in 0..<state.points.count {
            if let pt = state.points[i], pt.player == player {
                for order in 0..<pt.count { slots.append(.point(i, order: order)) }
            }
        }
        for order in 0..<(state.bar[player] ?? 0) { slots.append(.bar(order: order)) }
        for order in 0..<(state.borneOff[player] ?? 0) { slots.append(.off(order: order)) }
        return slots
    }

    /// Pair desired slots to existing entities, keeping identity for slots that
    /// didn't change and routing leftovers (the checkers that actually moved)
    /// to leftover entities so they animate from their old position.
    private func match(player: Player, desired: [CheckerSlot], existing: [CheckerEntity]) -> [CheckerEntity] {
        var oldSlotById: [Int: CheckerSlot] = [:]
        for e in existing { oldSlotById[e.id] = e.slot }

        var bySlot: [CheckerSlot: [Int]] = [:]
        for e in existing { bySlot[e.slot, default: []].append(e.id) }

        var kept: [CheckerEntity] = []
        var leftoverSlots: [CheckerSlot] = []
        for slot in desired {
            if var ids = bySlot[slot], !ids.isEmpty {
                kept.append(CheckerEntity(id: ids.removeFirst(), player: player, slot: slot, kind: .normal))
                bySlot[slot] = ids
            } else {
                leftoverSlots.append(slot)
            }
        }

        var leftoverIds = bySlot.values.flatMap { $0 }
        for slot in leftoverSlots {
            let id: Int
            if !leftoverIds.isEmpty {
                id = leftoverIds.removeFirst()
            } else {
                id = nextCheckerId
                nextCheckerId += 1
            }
            kept.append(CheckerEntity(id: id, player: player, slot: slot,
                                      kind: kind(old: oldSlotById[id], new: slot)))
        }

        return kept
    }

    // MARK: Scaffold drawing (static)

    private func drawBackground(ctx: GraphicsContext, lay: BLayout) {
        let board = CGRect(x: lay.pad, y: lay.pad, width: lay.boardW, height: lay.boardH)
        ctx.fill(Path(roundedRect: board, cornerRadius: 8),
                 with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.13, green: 0.27, blue: 0.18),
                        Color(red: 0.09, green: 0.20, blue: 0.13)
                    ]),
                    startPoint: CGPoint(x: 0, y: lay.pad),
                    endPoint: CGPoint(x: 0, y: lay.pad + lay.boardH)))

        let trim = Path(roundedRect: board.insetBy(dx: 1, dy: 1), cornerRadius: 7)
        ctx.stroke(trim, with: .color(Color(red: 0.72, green: 0.55, blue: 0.28).opacity(0.4)), lineWidth: 1)

        let bar = CGRect(x: lay.barX, y: lay.pad, width: lay.barW, height: lay.boardH)
        ctx.fill(Path(bar), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.04, green: 0.09, blue: 0.06), location: 0),
                .init(color: Color(red: 0.09, green: 0.18, blue: 0.12), location: 0.5),
                .init(color: Color(red: 0.04, green: 0.09, blue: 0.06), location: 1)
            ]),
            startPoint: CGPoint(x: lay.barX, y: 0),
            endPoint: CGPoint(x: lay.barX + lay.barW, y: 0)))

        var line = Path()
        line.move(to: CGPoint(x: lay.playX, y: lay.pad + lay.halfH))
        line.addLine(to: CGPoint(x: lay.zionX, y: lay.pad + lay.halfH))
        ctx.stroke(line, with: .color(Color.black.opacity(0.45)), lineWidth: 1)
    }

    private func drawPoints(ctx: GraphicsContext, lay: BLayout) {
        for i in 0..<24 {
            let dark = i % 2 == 0
            let baseFill = dark
                ? Color(red: 0.78, green: 0.20, blue: 0.18)
                : Color(red: 0.92, green: 0.82, blue: 0.60)
            let tipFill = dark
                ? Color(red: 0.42, green: 0.06, blue: 0.06)
                : Color(red: 0.58, green: 0.46, blue: 0.30)
            let cx = lay.pointCX(i)
            var tri = Path()
            tri.move(to: CGPoint(x: cx - lay.pw * 0.45, y: lay.baseY(i)))
            tri.addLine(to: CGPoint(x: cx + lay.pw * 0.45, y: lay.baseY(i)))
            tri.addLine(to: CGPoint(x: cx, y: lay.tipY(i)))
            tri.closeSubpath()
            ctx.fill(tri, with: .linearGradient(
                Gradient(colors: [baseFill, tipFill]),
                startPoint: CGPoint(x: cx, y: lay.baseY(i)),
                endPoint: CGPoint(x: cx, y: lay.tipY(i))))
            ctx.stroke(tri, with: .color(Color.black.opacity(0.25)), lineWidth: 0.5)
        }
    }

    private func drawTray(ctx: GraphicsContext, lay: BLayout) {
        let tray = CGRect(x: lay.zionX, y: lay.pad, width: lay.zionW, height: lay.boardH)
        ctx.fill(Path(tray), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.10, green: 0.22, blue: 0.15), location: 0),
                .init(color: Color(red: 0.13, green: 0.27, blue: 0.18), location: 0.5),
                .init(color: Color(red: 0.10, green: 0.22, blue: 0.15), location: 1)
            ]),
            startPoint: CGPoint(x: lay.zionX, y: 0),
            endPoint: CGPoint(x: lay.zionX + lay.zionW, y: 0)))
        var seam = Path()
        seam.move(to: CGPoint(x: lay.zionX, y: lay.pad))
        seam.addLine(to: CGPoint(x: lay.zionX, y: lay.pad + lay.boardH))
        ctx.stroke(seam, with: .color(Color(red: 0.72, green: 0.55, blue: 0.28).opacity(0.3)), lineWidth: 0.5)
    }

    private func drawHighlights(ctx: GraphicsContext, lay: BLayout) {
        let selColor = Color(red: 1.0, green: 0.85, blue: 0.35)
        let destColor = Color(red: 0.35, green: 0.95, blue: 0.55)

        if let from = selectedFrom {
            switch from {
            case .bar:
                let r = CGRect(x: lay.barX, y: lay.pad, width: lay.barW, height: lay.boardH)
                ctx.fill(Path(r), with: .color(selColor.opacity(0.22)))
            case .point(let idx):
                let cx = lay.pointCX(idx)
                let isTop = idx < 12
                let r = CGRect(x: cx - lay.pw / 2,
                               y: isTop ? lay.pad : lay.pad + lay.halfH,
                               width: lay.pw, height: lay.halfH)
                ctx.fill(Path(r), with: .linearGradient(
                    Gradient(colors: [selColor.opacity(0.35), selColor.opacity(0.05)]),
                    startPoint: CGPoint(x: cx, y: isTop ? lay.pad : lay.pad + lay.boardH),
                    endPoint: CGPoint(x: cx, y: lay.pad + lay.halfH)))
            }
        }

        let destSet: Set<MoveTo>
        if let from = selectedFrom {
            destSet = Set(legalMoves.filter { $0.from == from }.map { $0.to })
        } else {
            destSet = []
        }

        for dest in destSet {
            switch dest {
            case .off:
                let r = CGRect(x: lay.zionX, y: lay.pad, width: lay.zionW, height: lay.boardH)
                ctx.fill(Path(r), with: .color(destColor.opacity(0.32)))
            case .point(let idx):
                let cx = lay.pointCX(idx)
                let isTop = idx < 12
                let r = CGRect(x: cx - lay.pw / 2,
                               y: isTop ? lay.pad : lay.pad + lay.halfH,
                               width: lay.pw, height: lay.halfH)
                ctx.fill(Path(r), with: .linearGradient(
                    Gradient(colors: [destColor.opacity(0.38), destColor.opacity(0.05)]),
                    startPoint: CGPoint(x: cx, y: isTop ? lay.pad : lay.pad + lay.boardH),
                    endPoint: CGPoint(x: cx, y: lay.pad + lay.halfH)))
                var tri = Path()
                tri.move(to: CGPoint(x: cx - lay.pw * 0.45, y: lay.baseY(idx)))
                tri.addLine(to: CGPoint(x: cx + lay.pw * 0.45, y: lay.baseY(idx)))
                tri.addLine(to: CGPoint(x: cx, y: lay.tipY(idx)))
                tri.closeSubpath()
                ctx.stroke(tri, with: .color(destColor.opacity(0.85)), lineWidth: 1.5)
            }
        }
    }

    // MARK: Tap Handling

    private func handleTap(at location: CGPoint, lay: BLayout) {
        let hit = hitTest(location, lay: lay)

        switch hit {
        case .none:
            selectedFrom = nil

        case .some(.bar):
            if legalMoves.contains(where: { $0.from == .bar }) {
                selectedFrom = .bar
            } else {
                selectedFrom = nil
            }

        case .some(.off):
            guard let from = selectedFrom else { return }
            if let move = legalMoves.first(where: { $0.from == from && $0.to == .off }) {
                selectedFrom = nil
                onMove(move)
            }

        case .some(.point(let idx)):
            if let from = selectedFrom {
                if let move = legalMoves.first(where: { $0.from == from && $0.to == .point(idx) }) {
                    selectedFrom = nil
                    onMove(move)
                } else if legalMoves.contains(where: { $0.from == .point(idx) }) {
                    selectedFrom = .point(idx)
                } else {
                    selectedFrom = nil
                }
            } else {
                if legalMoves.contains(where: { $0.from == .point(idx) }) {
                    selectedFrom = .point(idx)
                }
            }
        }
    }

    private func hitTest(_ location: CGPoint, lay: BLayout) -> HitResult? {
        let x = location.x
        let y = location.y

        if x >= lay.zionX { return .off }
        if x >= lay.barX && x <= lay.barX + lay.barW { return .bar }

        for i in 0..<24 {
            let cx = lay.pointCX(i)
            let isTop = i < 12
            guard x >= cx - lay.pw / 2 && x <= cx + lay.pw / 2 else { continue }
            let minY = isTop ? lay.pad : lay.pad + lay.halfH
            let maxY = isTop ? lay.pad + lay.halfH : lay.pad + lay.boardH
            if y >= minY && y <= maxY { return .point(i) }
        }

        return nil
    }
}

// MARK: - Checker view

/// A single checker, rendered to match the old Canvas look. Being a real view
/// means it can move, scale, and (later) swap to a custom asset.
struct CheckerView: View {
    let player: Player
    let radius: CGFloat
    let custom: Bool

    var body: some View {
        let centerColor: Color
        let edgeColor: Color
        let stroke: Color
        if custom {
            centerColor = player == .gold
                ? Color(red: 0.20, green: 0.92, blue: 0.50)
                : Color(red: 1.0, green: 0.48, blue: 0.30)
            edgeColor = player == .gold
                ? Color(red: 0.0, green: 0.48, blue: 0.22)
                : Color(red: 0.62, green: 0.15, blue: 0.06)
            stroke = player == .gold
                ? Color(red: 0.0, green: 0.30, blue: 0.12)
                : Color(red: 0.38, green: 0.06, blue: 0.02)
        } else {
            centerColor = player == .gold
                ? Color(red: 0.98, green: 0.88, blue: 0.62)
                : Color(red: 0.85, green: 0.22, blue: 0.20)
            edgeColor = player == .gold
                ? Color(red: 0.68, green: 0.54, blue: 0.28)
                : Color(red: 0.42, green: 0.06, blue: 0.06)
            stroke = player == .gold
                ? Color(red: 0.42, green: 0.32, blue: 0.14)
                : Color(red: 0.22, green: 0.03, blue: 0.03)
        }

        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.35))
                .offset(y: radius * 0.12)

            Circle()
                .fill(RadialGradient(
                    colors: [centerColor, edgeColor],
                    center: UnitPoint(x: 0.28, y: 0.28),
                    startRadius: 0,
                    endRadius: radius * 1.25))

            Circle()
                .strokeBorder(stroke, lineWidth: 1.0)

            Circle()
                .strokeBorder(stroke.opacity(0.45), lineWidth: 0.6)
                .padding(radius * 0.38)

            if radius >= 6 {
                Ellipse()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: radius * 0.7, height: radius * 0.45)
                    .offset(x: -radius * 0.3, y: -radius * 0.45)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

/// Animatable bundle for a checker's flourish: a vertical hop, a scale, and a
/// rotation wobble.
private struct CheckerMotion: Equatable, Animatable {
    var y: CGFloat = 0
    var scale: CGFloat = 1
    var angle: Double = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, Double>> {
        get { AnimatablePair(y, AnimatablePair(scale, angle)) }
        set { y = newValue.first; scale = newValue.second.first; angle = newValue.second.second }
    }
}

/// Plays a flourish whenever the checker's slot changes — combined with the
/// position spring this arcs (jumps) the checker to its destination. The shape
/// of the arc depends on what happened: a normal hop, a harder knock when hit
/// to the bar, or a pop when borne off. Reads naturally in any direction.
private struct CheckerMotionEffect: ViewModifier {
    let trigger: CheckerSlot
    let kind: MoveKind

    // Per-kind shape of the flourish. Keeping the same three tracks for every
    // kind (just different values) keeps the keyframe builder happy.
    private var hopHeight: CGFloat {
        switch kind {
        case .normal:  return -24
        case .hit:     return -46
        case .bearOff: return -18
        }
    }
    private var scalePeak: CGFloat {
        switch kind {
        case .normal:  return 1.0
        case .hit:     return 1.14
        case .bearOff: return 1.28
        }
    }
    private var anglePeak: Double { kind == .hit ? -22 : 0 }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CheckerMotion(), trigger: trigger) { view, m in
            view.offset(y: m.y)
                .scaleEffect(m.scale)
                .rotationEffect(.degrees(m.angle))
        } keyframes: { _ in
            KeyframeTrack(\.y) {
                CubicKeyframe(hopHeight, duration: 0.16)
                CubicKeyframe(0, duration: 0.20)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(scalePeak, duration: 0.16)
                CubicKeyframe(1.0, duration: 0.20)
            }
            KeyframeTrack(\.angle) {
                CubicKeyframe(anglePeak, duration: 0.16)
                CubicKeyframe(anglePeak * -0.45, duration: 0.11)
                CubicKeyframe(0, duration: 0.09)
            }
        }
    }
}
