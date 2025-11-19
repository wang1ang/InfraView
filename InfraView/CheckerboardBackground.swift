import SwiftUI


struct CheckerboardBackground: View {
    @Environment(\.displayScale) private var displayScale
    var cell: CGFloat = 12
    var c1: Color = Color(NSColor.windowBackgroundColor) // white
    var c2: Color = Color.white.opacity(0.5) // gray

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let scale = displayScale
            let cellPx = max(1, Int(cell * scale))
            let cellPt = CGFloat(cellPx) / scale

            Canvas { ctx, _ in
                let cols = Int(ceil(size.width / cellPt))
                let rows = Int(ceil(size.height / cellPt))
                for y in 0..<rows {
                    for x in 0..<cols {
                        let isDark = (x + y).isMultiple(of: 2)
                        let rect = CGRect(x: CGFloat(x) * cellPt,
                                          y: CGFloat(y) * cellPt,
                                          width: cellPt, height: cellPt)
                        ctx.fill(Path(rect), with: .color(isDark ? c2 : c1))
                    }
                }
            }
        }
    }
}
