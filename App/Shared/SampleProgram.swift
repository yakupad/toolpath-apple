import Foundation

/// A small, safe sample program so new users can explore without a file:
/// a rounded rectangle profile with an inner pocket and an S-curve, 2 passes.
enum SampleProgram {
    static let sign: String = {
        var lines = [
            "(Toolpath sample — 120 x 60 mm sign, zero at lower-left, Z0 on stock top)",
            "(T1: 1/4in flat endmill, 2 flute)",
            "G21 G90 G17",
            "T1 M6",
            "S18000 M3",
            "G0 Z5",
        ]
        for (pass, depth) in [-1.5, -3.0].enumerated() {
            lines.append("(Profile pass \(pass + 1))")
            lines += [
                "G0 X10 Y0",
                "G1 Z\(depth) F300",
                "G1 X110 Y0 F1200",
                "G3 X120 Y10 I0 J10",
                "G1 X120 Y50",
                "G3 X110 Y60 I-10 J0",
                "G1 X10 Y60",
                "G3 X0 Y50 I0 J-10",
                "G1 X0 Y10",
                "G3 X10 Y0 I10 J0",
                "G0 Z5",
            ]
        }
        lines.append("(Inner pocket)")
        for (pass, depth) in [-1.0, -2.0].enumerated() {
            lines.append("(Pocket pass \(pass + 1))")
            lines.append("G0 X20 Y15")
            lines.append("G1 Z\(depth) F300")
            var y = 15.0
            var leftToRight = true
            while y <= 45 {
                lines.append("G1 X\(leftToRight ? 100 : 20) Y\(y) F1200")
                y += 5
                if y <= 45 { lines.append("G1 Y\(y)") }
                leftToRight.toggle()
            }
            lines.append("G0 Z5")
        }
        lines.append("(S-curve engraving)")
        lines += [
            "G0 X30 Y30",
            "G1 Z-2.5 F300",
            "G2 X50 Y30 I10 J0 F1000",
            "G3 X70 Y30 I10 J0",
            "G2 X90 Y30 I10 J0",
            "G0 Z10",
            "M5",
            "G0 X0 Y0",
            "M30",
        ]
        return lines.joined(separator: "\n")
    }()
}
