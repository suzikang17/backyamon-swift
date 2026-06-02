import SwiftUI

// MARK: - Layout

private struct BLayout {
    let size: CGSize

    var pad: CGFloat { 10 }
    var boardW: CGFloat { size.width - 2 * pad }
    var boardH: CGFloat { size.height - 2 * pad }

    var zionW: CGFloat { boardW * 0.075 }
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

    /// Whether a custom community piece is equipped. SVG rendering with
    /// SwiftUI is non-trivial — for now this just signals the renderer to
    /// use a distinct fill colour so the user can tell their custom piece is
    /// active.
    private var customPieceEquipped: Bool {
        assetManager.equippedPieceSvg != nil
    }

    var body: some View {
        GeometryReader { geo in
            let lay = BLayout(size: geo.size)
            Canvas { ctx, _ in
                let boardRect = CGRect(x: lay.pad, y: lay.pad, width: lay.boardW, height: lay.boardH)
                ctx.clip(to: Path(roundedRect: boardRect, cornerRadius: 6))
                drawBackground(ctx: ctx, lay: lay)
                drawPoints(ctx: ctx, lay: lay)
                drawHighlights(ctx: ctx, lay: lay)
                drawCheckers(ctx: ctx, lay: lay)
                drawBarCheckers(ctx: ctx, lay: lay)
                drawBearOffTray(ctx: ctx, lay: lay)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, lay: lay)
            }
        }
    }

    // MARK: Drawing

    private func drawBackground(ctx: GraphicsContext, lay: BLayout) {
        let board = CGRect(x: lay.pad, y: lay.pad, width: lay.boardW, height: lay.boardH)
        // Felt-style gradient (richer green, subtle vertical depth)
        ctx.fill(Path(roundedRect: board, cornerRadius: 8),
                 with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.13, green: 0.27, blue: 0.18),
                        Color(red: 0.09, green: 0.20, blue: 0.13)
                    ]),
                    startPoint: CGPoint(x: 0, y: lay.pad),
                    endPoint: CGPoint(x: 0, y: lay.pad + lay.boardH)))

        // Inner border (warm gold trim, evokes wood frame)
        let trim = Path(roundedRect: board.insetBy(dx: 1, dy: 1), cornerRadius: 7)
        ctx.stroke(trim, with: .color(Color(red: 0.72, green: 0.55, blue: 0.28).opacity(0.4)), lineWidth: 1)

        // Recessed bar with side-shaded gradient
        let bar = CGRect(x: lay.barX, y: lay.pad, width: lay.barW, height: lay.boardH)
        ctx.fill(Path(bar), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.04, green: 0.09, blue: 0.06), location: 0),
                .init(color: Color(red: 0.09, green: 0.18, blue: 0.12), location: 0.5),
                .init(color: Color(red: 0.04, green: 0.09, blue: 0.06), location: 1)
            ]),
            startPoint: CGPoint(x: lay.barX, y: 0),
            endPoint: CGPoint(x: lay.barX + lay.barW, y: 0)))

        // Center separator
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
            // Base→tip gradient gives each point a satin sheen
            ctx.fill(tri, with: .linearGradient(
                Gradient(colors: [baseFill, tipFill]),
                startPoint: CGPoint(x: cx, y: lay.baseY(i)),
                endPoint: CGPoint(x: cx, y: lay.tipY(i))))
            // Hairline edge for crispness
            ctx.stroke(tri, with: .color(Color.black.opacity(0.25)), lineWidth: 0.5)
        }
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
                // Soft fade toward center
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
                // Outline the target triangle
                var tri = Path()
                tri.move(to: CGPoint(x: cx - lay.pw * 0.45, y: lay.baseY(idx)))
                tri.addLine(to: CGPoint(x: cx + lay.pw * 0.45, y: lay.baseY(idx)))
                tri.addLine(to: CGPoint(x: cx, y: lay.tipY(idx)))
                tri.closeSubpath()
                ctx.stroke(tri, with: .color(destColor.opacity(0.85)), lineWidth: 1.5)
            }
        }
    }

    private func drawCheckers(ctx: GraphicsContext, lay: BLayout) {
        for i in 0..<24 {
            guard let pt = state.points[i] else { continue }
            let cx = lay.pointCX(i)
            let count = pt.count
            let r = min(lay.pw * 0.42, lay.halfH / (2.0 + CGFloat(max(count, 1) - 1) * 1.9))
            let isTop = i < 12
            for j in 0..<count {
                let offset = CGFloat(j) * r * 1.9
                let cy = isTop ? lay.pad + r + offset : lay.pad + lay.boardH - r - offset
                drawChecker(ctx: ctx, cx: cx, cy: cy, r: r, player: pt.player)
            }
        }
    }

    private func drawBarCheckers(ctx: GraphicsContext, lay: BLayout) {
        for player in Player.allCases {
            let count = state.bar[player] ?? 0
            guard count > 0 else { continue }
            let r = min(lay.barW * 0.42, 14.0)
            let isTop = player == .gold
            for j in 0..<count {
                let offset = CGFloat(j) * r * 1.9
                let cy = isTop ? lay.pad + r + offset : lay.pad + lay.boardH - r - offset
                drawChecker(ctx: ctx, cx: lay.barCX, cy: cy, r: r, player: player)
            }
        }
    }

    private func drawChecker(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat, player: Player) {
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

        let centerColor: Color
        let edgeColor: Color
        let stroke: Color
        if customPieceEquipped {
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

        // Drop shadow — small offset so stacked pieces still read cleanly
        let shadowOffset = r * 0.12
        let shadowRect = rect.offsetBy(dx: 0, dy: shadowOffset)
        ctx.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.35)))

        // Main body with off-center radial gradient (light from upper-left)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [centerColor, edgeColor]),
            center: CGPoint(x: cx - r * 0.22, y: cy - r * 0.22),
            startRadius: 0,
            endRadius: r * 1.25))

        // Outline
        ctx.stroke(Path(ellipseIn: rect), with: .color(stroke), lineWidth: 1.0)

        // Inset bevel ring — gives a "stone" or "puck" feel
        let innerR = r * 0.62
        let innerRect = CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2)
        ctx.stroke(Path(ellipseIn: innerRect), with: .color(stroke.opacity(0.45)), lineWidth: 0.6)

        // Specular highlight (only for radius >= 6 to avoid noise on tiny stacks)
        if r >= 6 {
            let hw = r * 0.7
            let hh = r * 0.45
            let highlightRect = CGRect(x: cx - r * 0.3 - hw / 2,
                                       y: cy - r * 0.45 - hh / 2,
                                       width: hw,
                                       height: hh)
            ctx.fill(Path(ellipseIn: highlightRect),
                     with: .color(Color.white.opacity(0.28)))
        }
    }

    private func drawBearOffTray(ctx: GraphicsContext, lay: BLayout) {
        let tray = CGRect(x: lay.zionX, y: lay.pad, width: lay.zionW, height: lay.boardH)
        // Recessed look — darker on the edges, slightly lighter mid
        ctx.fill(Path(tray), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.04, green: 0.08, blue: 0.06), location: 0),
                .init(color: Color(red: 0.08, green: 0.15, blue: 0.10), location: 0.5),
                .init(color: Color(red: 0.04, green: 0.08, blue: 0.06), location: 1)
            ]),
            startPoint: CGPoint(x: lay.zionX, y: 0),
            endPoint: CGPoint(x: lay.zionX + lay.zionW, y: 0)))

        let cx = lay.zionX + lay.zionW / 2
        let r = min(lay.zionW * 0.38, 12.0)

        let goldOff = state.borneOff[.gold] ?? 0
        for j in 0..<goldOff {
            let cy = lay.pad + lay.boardH - r - CGFloat(j) * r * 1.9
            drawChecker(ctx: ctx, cx: cx, cy: cy, r: r, player: .gold)
        }
        let redOff = state.borneOff[.red] ?? 0
        for j in 0..<redOff {
            let cy = lay.pad + r + CGFloat(j) * r * 1.9
            drawChecker(ctx: ctx, cx: cx, cy: cy, r: r, player: .red)
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
