import SwiftUI

// MARK: - Layout

private struct BLayout {
    let size: CGSize

    var pad: CGFloat { 6 }
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
        ctx.fill(Path(roundedRect: board, cornerRadius: 6),
                 with: .color(Color(red: 0.12, green: 0.22, blue: 0.14)))
        let bar = CGRect(x: lay.barX, y: lay.pad, width: lay.barW, height: lay.boardH)
        ctx.fill(Path(bar), with: .color(Color(red: 0.09, green: 0.17, blue: 0.11)))
        var line = Path()
        line.move(to: CGPoint(x: lay.playX, y: lay.pad + lay.halfH))
        line.addLine(to: CGPoint(x: lay.zionX, y: lay.pad + lay.halfH))
        ctx.stroke(line, with: .color(Color.black.opacity(0.3)), lineWidth: 1)
    }

    private func drawPoints(ctx: GraphicsContext, lay: BLayout) {
        for i in 0..<24 {
            let dark = i % 2 == 0
            let fill = dark
                ? Color(red: 0.6, green: 0.12, blue: 0.12)
                : Color(red: 0.82, green: 0.72, blue: 0.52)
            let cx = lay.pointCX(i)
            var tri = Path()
            tri.move(to: CGPoint(x: cx - lay.pw * 0.45, y: lay.baseY(i)))
            tri.addLine(to: CGPoint(x: cx + lay.pw * 0.45, y: lay.baseY(i)))
            tri.addLine(to: CGPoint(x: cx, y: lay.tipY(i)))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(fill.opacity(0.85)))
        }
    }

    private func drawHighlights(ctx: GraphicsContext, lay: BLayout) {
        if let from = selectedFrom {
            switch from {
            case .bar:
                let r = CGRect(x: lay.barX, y: lay.pad, width: lay.barW, height: lay.boardH)
                ctx.fill(Path(r), with: .color(Color.yellow.opacity(0.25)))
            case .point(let idx):
                let cx = lay.pointCX(idx)
                let r = CGRect(x: cx - lay.pw / 2,
                               y: idx < 12 ? lay.pad : lay.pad + lay.halfH,
                               width: lay.pw, height: lay.halfH)
                ctx.fill(Path(r), with: .color(Color.yellow.opacity(0.2)))
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
                ctx.fill(Path(r), with: .color(Color.green.opacity(0.3)))
            case .point(let idx):
                let cx = lay.pointCX(idx)
                let r = CGRect(x: cx - lay.pw / 2,
                               y: idx < 12 ? lay.pad : lay.pad + lay.halfH,
                               width: lay.pw, height: lay.halfH)
                ctx.fill(Path(r), with: .color(Color.green.opacity(0.2)))
            }
        }
    }

    private func drawCheckers(ctx: GraphicsContext, lay: BLayout) {
        for i in 0..<24 {
            guard let pt = state.points[i] else { continue }
            let cx = lay.pointCX(i)
            let count = pt.count
            let r = min(lay.pw * 0.42, lay.halfH / CGFloat(max(count, 5) + 1))
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
        // When the user has equipped a custom piece, swap in a distinct
        // reggae-green / bright-red fill so they can tell it's active. Full
        // SVG-to-Canvas rendering is non-trivial in SwiftUI; this is a clear
        // visual signal that the customisation took effect.
        let fill: Color
        let stroke: Color
        if customPieceEquipped {
            fill = player == .gold
                ? Color(red: 0.0, green: 0.68, blue: 0.32)
                : Color(red: 0.92, green: 0.32, blue: 0.18)
            stroke = player == .gold
                ? Color(red: 0.0, green: 0.4, blue: 0.18)
                : Color(red: 0.55, green: 0.1, blue: 0.05)
        } else {
            fill = player == .gold
                ? Color(red: 0.88, green: 0.76, blue: 0.48)
                : Color(red: 0.62, green: 0.12, blue: 0.12)
            stroke = player == .gold
                ? Color(red: 0.6, green: 0.48, blue: 0.25)
                : Color(red: 0.35, green: 0.05, blue: 0.05)
        }
        ctx.fill(Path(ellipseIn: rect), with: .color(fill))
        ctx.stroke(Path(ellipseIn: rect), with: .color(stroke), lineWidth: 1.5)
    }

    private func drawBearOffTray(ctx: GraphicsContext, lay: BLayout) {
        let tray = CGRect(x: lay.zionX, y: lay.pad, width: lay.zionW, height: lay.boardH)
        ctx.fill(Path(tray), with: .color(Color(red: 0.09, green: 0.17, blue: 0.11)))

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
