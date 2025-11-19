import SwiftUI


struct CheckerboardBackground: View {
    var cell: CGFloat = 12
    var c1: Color = Color(NSColor.windowBackgroundColor) // white
    var c2: Color = Color.white.opacity(0.5) // gray

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            Canvas { ctx, _ in
                let cols = Int(ceil(size.width / cell))
                let rows = Int(ceil(size.height / cell))
                for y in 0..<rows {
                    for x in 0..<cols {
                        let isDark = (x + y).isMultiple(of: 2)
                        let rect = CGRect(x: CGFloat(x) * cell,
                                          y: CGFloat(y) * cell,
                                          width: cell, height: cell)
                        ctx.fill(Path(rect), with: .color(isDark ? c2 : c1))
                    }
                }
            }
        }
    }
}
