import Foundation

/// Deterministic interpreter for 2-axis lathe programs (Fanuc-style ISO,
/// LinuxCNC and grblHAL lathe mode).
///
/// Output uses the shared document model: `GPoint.x` = axial Z,
/// `GPoint.y` = radius, `GPoint.z` = 0. Feed per revolution (G95) and
/// constant surface speed (G96) are converted to mm/min per move so the
/// timeline and statistics work unchanged. Canned cycles (G70/G71/G72/G76,
/// G74/G75) are expanded into the passes a controller would run, so the
/// preview shows real roughing passes and thread passes.
///
/// Supported: G0–G3 (I/K or R arcs, G18 plane), G7/G8 diameter/radius mode,
/// U/W incremental words, G20/G21, G94/G95 and G98/G99 feed modes, G90/G91 as absolute/incremental (LinuxCNC
/// and grblHAL meaning, not the Fanuc group-A turning cycle), G94/G95,
/// G96/G97, G50 S and G96 D spindle limits, G32/G33 threading, T0101 tool
/// words, M3/M4/M5.
public struct LatheParser: Sendable {
    /// X words are diameters (Fanuc default; LinuxCNC G7). G7/G8 in the
    /// program override this.
    public var diameterMode: Bool
    /// Physical spindle limit, used when converting G96 to RPM.
    public var machineMaxRpm: Double?

    public init(diameterMode: Bool = true, machineMaxRpm: Double? = nil) {
        self.diameterMode = diameterMode
        self.machineMaxRpm = machineMaxRpm
    }

    struct Line {
        let number: Int
        let words: [GCodeParser.Word]
        func value(_ letter: Character) -> Double? { words.last { $0.letter == letter }?.value }
        func has(_ letter: Character) -> Bool { words.contains { $0.letter == letter } }
        func gCodes() -> [Double] { words.filter { $0.letter == "G" }.map(\.value) }
    }

    public func parse(_ source: String, fileName: String) -> GCodeDocument {
        var lines: [Line] = []
        var lineIndexByN: [Int: Int] = [:]
        var totalLines = 0
        var number = 0
        var scratch: [GCodeParser.Word] = []
        source.enumerateLines { raw, _ in
            number += 1
            totalLines = number
            scratch.removeAll(keepingCapacity: true)
            GCodeParser.scanWords(raw, into: &scratch)
            guard !scratch.isEmpty else { return }
            let line = Line(number: number, words: scratch)
            if let n = line.value("N") { lineIndexByN[Int(n.rounded())] = lines.count }
            lines.append(line)
        }
        var state = State(diameterMode: diameterMode, machineMaxRpm: machineMaxRpm)
        state.run(lines: lines, lineIndexByN: lineIndexByN)
        let changes = state.toolChanges.map {
            ToolChange(toolNumber: $0.tool, sourceLine: $0.line, firstMoveIndex: $0.moveIndex < state.moves.count ? $0.moveIndex : nil)
        }
        return GCodeDocument(fileName: fileName, totalLines: totalLines, moves: state.moves, toolChanges: changes, kind: .lathe, lathe: state.info)
    }

    /// Interpreter state. Positions are (z, r) in millimeters.
    struct State {
        var diameterMode: Bool
        let machineMaxRpm: Double?

        var z = 0.0, r = 0.0
        var motion = MoveType.rapid
        var threading = false
        var absolute = true
        var unitScale = 1.0
        var feed = 0.0 // mm/min or mm/rev depending on feedPerRev
        var feedPerRev = false
        var spindleOn = false
        var css = false
        var surfaceSpeed = 0.0 // m/min while css
        var rpm = 0.0
        var maxRpm: Double?
        var tool: Int?
        var moves: [GCodeMove] = []
        var toolChanges: [(tool: Int, line: Int, moveIndex: Int)] = []
        var info = LatheProgramInfo()

        // Two-block canned cycle parameters (Fanuc style).
        var roughDepth = 1.0, roughRetract = 0.5
        var threadFirst: (minDepth: Double, finishAllowance: Double, passes: Int)?

        init(diameterMode: Bool, machineMaxRpm: Double?) {
            self.diameterMode = diameterMode
            self.machineMaxRpm = machineMaxRpm
        }

        // MARK: Main loop

        mutating func run(lines: [Line], lineIndexByN: [Int: Int]) {
            var skip = Set<Int>()
            var index = 0
            while index < lines.count {
                defer { index += 1 }
                if skip.contains(index) { continue }
                let line = lines[index]
                let gs = line.gCodes()
                applyModes(line, gCodes: gs)

                if gs.contains(71) || gs.contains(72) {
                    let facing = gs.contains(72)
                    if let p = line.value("P"), let q = line.value("Q") {
                        guard let range = profileRange(Int(p.rounded()), Int(q.rounded()), lineIndexByN) else { continue }
                        range.forEach { skip.insert($0) }
                        let allowanceX = (line.value("U") ?? 0) * unitScale / 2
                        let allowanceZ = (line.value("W") ?? 0) * unitScale
                        roughCycle(profile: Array(lines[range]), facing: facing,
                                   allowanceR: allowanceX, allowanceZ: allowanceZ, line: line.number)
                    } else {
                        // First block: depth of cut (radius) and retract.
                        if let u = line.value(facing ? "W" : "U") { roughDepth = max(abs(u) * unitScale, 0.05) }
                        if let rr = line.value("R") { roughRetract = abs(rr) * unitScale }
                    }
                    continue
                }
                if gs.contains(70), let p = line.value("P"), let q = line.value("Q") {
                    if let range = profileRange(Int(p.rounded()), Int(q.rounded()), lineIndexByN) {
                        for profileLine in lines[range] { execute(profileLine, gCodes: profileLine.gCodes(), applyModesFirst: true) }
                    }
                    continue
                }
                if gs.contains(76) {
                    threadCycle(line)
                    continue
                }
                if gs.contains(74) || gs.contains(75) {
                    peckCycle(line, alongZ: gs.contains(74))
                    continue
                }
                execute(line, gCodes: gs, applyModesFirst: false)
            }
        }

        func profileRange(_ p: Int, _ q: Int, _ map: [Int: Int]) -> ClosedRange<Int>? {
            guard let a = map[p], let b = map[q], a <= b else { return nil }
            return a...b
        }

        // MARK: Modal words

        mutating func applyModes(_ line: Line, gCodes: [Double]) {
            for g in gCodes {
                switch Int(g.rounded()) {
                case 0: motion = .rapid; threading = false
                case 1: motion = .linear; threading = false
                case 2: motion = .arcClockwise; threading = false
                case 3: motion = .arcCounterClockwise; threading = false
                case 32, 33: motion = .linear; threading = true
                case 7: diameterMode = true
                case 8: diameterMode = false
                case 20: unitScale = 25.4
                case 21: unitScale = 1
                case 90: absolute = true
                case 91: absolute = false
                // G94/G95 (LinuxCNC, grblHAL) and G98/G99 (Fanuc lathe).
                case 94, 98: feedPerRev = false
                case 95, 99: feedPerRev = true
                case 96:
                    css = true
                    if let d = line.value("D") { maxRpm = d }
                case 97: css = false
                case 50:
                    if let s = line.value("S") { maxRpm = s }
                default: break
                }
            }
            let isG50 = gCodes.contains { Int($0.rounded()) == 50 }
            if let s = line.value("S"), !isG50 {
                // In CSS mode S is surface speed (m/min, or ft/min in inch mode).
                if css { surfaceSpeed = unitScale == 1 ? s : s * 0.3048 } else { rpm = s }
            }
            if let f = line.value("F") { feed = f * unitScale }
            if threading, let k = line.value("K"), line.value("F") == nil { feed = k * unitScale }
            for m in line.words where m.letter == "M" {
                switch Int(m.value.rounded()) {
                case 3, 4: spindleOn = true
                case 5: spindleOn = false
                default: break
                }
            }
            if let t = line.value("T") {
                let raw = Int(t.rounded())
                let toolNumber = raw >= 100 ? raw / 100 : raw
                if toolNumber != tool {
                    tool = toolNumber
                    toolChanges.append((toolNumber, line.number, moves.count))
                }
            }
        }

        // MARK: Motion

        /// Target (z, r) of a line's axis words, or nil when it has none.
        func target(of line: Line) -> (z: Double, r: Double)? {
            let xw = line.value("X"), zw = line.value("Z"), uw = line.value("U"), ww = line.value("W")
            guard xw != nil || zw != nil || uw != nil || ww != nil else { return nil }
            let radial = diameterMode ? 0.5 : 1.0
            var nr = r, nz = z
            if let xw { nr = absolute ? xw * unitScale * radial : r + xw * unitScale * radial }
            if let uw { nr = r + uw * unitScale * radial }
            if let zw { nz = absolute ? zw * unitScale : z + zw * unitScale }
            if let ww { nz = z + ww * unitScale }
            return (nz, nr)
        }

        mutating func execute(_ line: Line, gCodes: [Double], applyModesFirst: Bool) {
            if applyModesFirst { applyModes(line, gCodes: gCodes) }
            // Reference returns, machine coordinates and coordinate setting
            // (G28/G30/G53, G50 X Z, G92) don't move along the program path.
            let nonPath: Set<Int> = [28, 30, 53, 50, 92, 10]
            if gCodes.contains(where: { nonPath.contains(Int($0.rounded())) }) { return }
            guard let t = target(of: line) else { return }
            var center: (z: Double, r: Double)?
            if motion == .arcClockwise || motion == .arcCounterClockwise {
                if line.has("I") || line.has("K") {
                    // Arc centre offsets are radius values on every common control.
                    center = (z + (line.value("K") ?? 0) * unitScale, r + (line.value("I") ?? 0) * unitScale)
                } else if let radius = line.value("R") {
                    center = Self.arcCenter(from: (z, r), to: t, radius: radius * unitScale, clockwise: motion == .arcClockwise)
                }
            }
            emit(motion, to: t, center: center, line: line.number)
        }

        mutating func emit(_ type: MoveType, to t: (z: Double, r: Double), center: (z: Double, r: Double)? = nil, line: Int) {
            let isArc = type == .arcClockwise || type == .arcCounterClockwise
            let moveType = isArc && center == nil ? .linear : type
            let radiusForSpeed = max(abs((r + t.r) / 2), 0.5)
            let spindle = effectiveRpm(atRadius: radiusForSpeed)
            let feedMmPerMin = (feedPerRev || threading) ? feed * spindle : feed
            if css, moveType != .rapid, spindleOn {
                if maxRpm == nil, info.cssWithoutLimitLine == nil { info.cssWithoutLimitLine = line }
                let smallest = min(abs(r), abs(t.r))
                info.minimumCssRadius = min(info.minimumCssRadius ?? smallest, smallest)
            }
            moves.append(GCodeMove(
                index: moves.count,
                sourceLine: line,
                type: moveType,
                start: GPoint(x: z, y: r, z: 0),
                end: GPoint(x: t.z, y: t.r, z: 0),
                feedRate: moveType == .rapid ? 0 : feedMmPerMin,
                spindleOn: spindleOn,
                spindleSpeed: spindle,
                toolNumber: tool,
                arcCenter: center.map { GPoint(x: $0.z, y: $0.r, z: 0) }
            ))
            z = t.z
            r = t.r
        }

        func effectiveRpm(atRadius radius: Double) -> Double {
            guard css else { return rpm }
            var value = surfaceSpeed * 1000 / (2 * .pi * radius)
            if let maxRpm, maxRpm > 0 { value = min(value, maxRpm) }
            if let machineMaxRpm, machineMaxRpm > 0 { value = min(value, machineMaxRpm) }
            return value
        }

        static func arcCenter(from a: (z: Double, r: Double), to b: (z: Double, r: Double), radius: Double, clockwise: Bool) -> (z: Double, r: Double)? {
            let dz = b.z - a.z, dr = b.r - a.r
            let chord = (dz * dz + dr * dr).squareRoot()
            guard chord > 1e-9, abs(radius) >= chord / 2 - 1e-9 else { return nil }
            let h = max(radius * radius - chord * chord / 4, 0).squareRoot()
            let mz = (a.z + b.z) / 2, mr = (a.r + b.r) / 2
            // Unit vector to the left of the chord direction.
            let lz = -dr / chord, lr = dz / chord
            // Short arcs (R > 0): CCW centre lies left of the chord, CW right.
            let sign: Double = (clockwise ? -1 : 1) * (radius >= 0 ? 1 : -1)
            return (mz + sign * h * lz, mr + sign * h * lr)
        }

        // MARK: Canned cycles

        /// Positions of a profile (N p … N q), interpreted from the current
        /// point without emitting moves.
        func profilePoints(_ profile: [Line]) -> [(z: Double, r: Double)] {
            var probe = self
            probe.moves = []
            for line in profile { probe.execute(line, gCodes: line.gCodes(), applyModesFirst: true) }
            // The first block only brings the tool from the cycle start to the
            // profile; the profile itself begins where that move ends.
            guard let first = probe.moves.first else { return [] }
            var points: [(z: Double, r: Double)] = [(first.end.x, first.end.y)]
            for move in probe.moves.dropFirst() {
                for p in Tessellator.polyline(for: move, arcSegments: 12).dropFirst()
                where points.last.map({ $0.z != p.x || $0.r != p.y }) ?? true {
                    points.append((p.x, p.y))
                }
            }
            return points
        }

        /// G71 (turning) / G72 (facing) multiple repetitive roughing cycle.
        mutating func roughCycle(profile: [Line], facing: Bool, allowanceR: Double, allowanceZ: Double, line: Int) {
            let start = (z: z, r: r)
            let points = profilePoints(profile).map { (z: $0.z + allowanceZ, r: $0.r + allowanceR) }
            guard points.count >= 2 else { return }
            let savedMotion = motion
            let depth = roughDepth, retract = roughRetract

            if !facing {
                // Passes at decreasing radius, cutting along -Z to the profile.
                let lowest = points.map(\.r).min() ?? start.r
                var level = start.r - depth
                while level > lowest + 1e-6 {
                    let endZ = Self.crossingZ(points, atRadius: level) ?? points.last!.z
                    emit(.rapid, to: (start.z, level), line: line)
                    emit(.linear, to: (endZ, level), line: line)
                    emit(.linear, to: (endZ + retract, level + retract), line: line)
                    emit(.rapid, to: (start.z, level + retract), line: line)
                    level -= depth
                }
            } else {
                // Passes at decreasing Z, cutting toward the centre to the profile.
                let deepest = points.map(\.z).min() ?? start.z
                var level = start.z - depth
                while level > deepest + 1e-6 {
                    let endR = Self.crossingR(points, atZ: level) ?? points.last!.r
                    emit(.rapid, to: (level, start.r), line: line)
                    emit(.linear, to: (level, endR), line: line)
                    emit(.linear, to: (level + retract, endR + retract), line: line)
                    emit(.rapid, to: (level + retract, start.r), line: line)
                    level -= depth
                }
            }
            // Final pass along the profile (still leaving the finish allowance).
            emit(.rapid, to: points[0], line: line)
            for p in points.dropFirst() { emit(.linear, to: p, line: line) }
            emit(.rapid, to: start, line: line)
            motion = savedMotion
        }

        /// First Z along the profile where it reaches `radius`.
        static func crossingZ(_ points: [(z: Double, r: Double)], atRadius radius: Double) -> Double? {
            for (a, b) in zip(points, points.dropFirst()) where (a.r - radius) * (b.r - radius) <= 0 && a.r != b.r {
                let t = (radius - a.r) / (b.r - a.r)
                return a.z + (b.z - a.z) * t
            }
            return nil
        }

        static func crossingR(_ points: [(z: Double, r: Double)], atZ zValue: Double) -> Double? {
            for (a, b) in zip(points, points.dropFirst()) where (a.z - zValue) * (b.z - zValue) <= 0 && a.z != b.z {
                let t = (zValue - a.z) / (b.z - a.z)
                return a.r + (b.r - a.r) * t
            }
            return nil
        }

        /// G76 threading: Fanuc two-block or LinuxCNC single-block form.
        mutating func threadCycle(_ line: Line) {
            let hasTarget = line.has("X") || line.has("Z") || line.has("U") || line.has("W")
            if !hasTarget {
                // Fanuc first block: P(mm rr aa) Q(min depth µm) R(finish µm).
                let p = Int((line.value("P") ?? 10000).rounded())
                threadFirst = (minDepth: (line.value("Q") ?? 50) / 1000, finishAllowance: (line.value("R") ?? 20) / 1000, passes: max(p / 10000, 1))
                return
            }
            let start = (z: z, r: r)
            let savedMotion = motion, savedThreading = threading, savedFeed = feed
            var depths: [Double] = []
            let endZ: Double
            let finalR: Double

            if line.has("I") || line.has("J") || line.has("K") && !line.has("F") {
                // LinuxCNC: P pitch, Z end, I peak offset from drive line, J first cut, K full depth, R degression.
                let pitch = (line.value("P") ?? 1) * unitScale
                endZ = target(of: Line(number: line.number, words: line.words.filter { $0.letter == "Z" }))?.z ?? z
                let peak = start.r + (line.value("I") ?? 0) * unitScale
                let first = max((line.value("J") ?? 0.1) * unitScale, 0.01)
                let full = max((line.value("K") ?? first) * unitScale, first)
                let degression = max(line.value("R") ?? 1, 1)
                let inward: Double = peak <= start.r ? -1 : 1
                var n = 1.0
                while depths.count < 200 {
                    let d = min(first * pow(n, 1 / degression), full)
                    depths.append(d)
                    if d >= full { break }
                    n += 1
                }
                finalR = peak
                feed = pitch
                emitThreadPasses(depths: depths.map { peak + inward * $0 }, startR: start.r, startZ: start.z, endZ: endZ, line: line.number)
            } else {
                // Fanuc second block: X final minor diameter, P thread height (µm), Q first depth (µm), F lead.
                guard let t = target(of: line) else { return }
                endZ = t.z
                finalR = t.r
                let height = (line.value("P") ?? 1000) / 1000 * unitScale
                let first = max((line.value("Q") ?? 200) / 1000 * unitScale, 0.01)
                let minDepth = (threadFirst?.minDepth ?? 0.05) * unitScale
                feed = (line.value("F") ?? 1) * unitScale
                let outward: Double = finalR <= start.r ? 1 : -1
                var n = 1.0, previous = 0.0
                while depths.count < 200 {
                    var d = first * n.squareRoot()
                    if d - previous < minDepth { d = previous + minDepth }
                    d = min(d, height)
                    depths.append(d)
                    previous = d
                    if d >= height { break }
                    n += 1
                }
                for _ in 1..<(threadFirst?.passes ?? 1) { depths.append(height) }
                emitThreadPasses(depths: depths.map { finalR + outward * (height - $0) }, startR: start.r, startZ: start.z, endZ: endZ, line: line.number)
            }
            _ = finalR
            emit(.rapid, to: start, line: line.number)
            motion = savedMotion
            threading = savedThreading
            feed = savedFeed
        }

        mutating func emitThreadPasses(depths radii: [Double], startR: Double, startZ: Double, endZ: Double, line: Int) {
            for passR in radii {
                threading = false
                emit(.rapid, to: (startZ, passR), line: line)
                threading = true
                emit(.linear, to: (endZ, passR), line: line)
                threading = false
                emit(.rapid, to: (endZ, startR), line: line)
                emit(.rapid, to: (startZ, startR), line: line)
            }
        }

        /// G74 (peck along Z, face drilling/grooving) and G75 (along X,
        /// grooving/parting), shown as one feed to depth and a rapid return.
        mutating func peckCycle(_ line: Line, alongZ: Bool) {
            guard let t = target(of: line) else {
                if let e = line.value("R") { roughRetract = abs(e) * unitScale }
                return
            }
            let start = (z: z, r: r)
            if alongZ {
                emit(.rapid, to: (start.z, t.r), line: line.number)
                emit(.linear, to: (t.z, t.r), line: line.number)
                emit(.rapid, to: (start.z, t.r), line: line.number)
            } else {
                emit(.rapid, to: (t.z, start.r), line: line.number)
                emit(.linear, to: (t.z, t.r), line: line.number)
                emit(.rapid, to: (t.z, start.r), line: line.number)
            }
            emit(.rapid, to: start, line: line.number)
        }
    }
}

/// Recognises lathe programs, so a file opened without a lathe profile is
/// still read the right way.
public enum LatheDetector {
    /// Whether any line programs a Y axis word (comments ignored).
    public static func hasYAxis(_ source: String) -> Bool {
        var found = false
        var words: [GCodeParser.Word] = []
        source.enumerateLines { raw, stop in
            words.removeAll(keepingCapacity: true)
            GCodeParser.scanWords(raw, into: &words)
            if words.contains(where: { $0.letter == "Y" }) { found = true; stop = true }
        }
        return found
    }

    public static func isLikelyLathe(_ source: String) -> Bool {
        var score = 0
        var sawY = false
        var words: [GCodeParser.Word] = []
        var lines = 0
        source.enumerateLines { raw, stop in
            lines += 1
            if lines > 4000 { stop = true; return }
            words.removeAll(keepingCapacity: true)
            GCodeParser.scanWords(raw, into: &words)
            for w in words {
                switch w.letter {
                case "Y": sawY = true
                case "G":
                    switch Int(w.value.rounded()) {
                    case 96, 95, 76, 71, 72, 70, 7, 18: score += 2
                    case 33, 32: score += 1
                    default: break
                    }
                case "U", "W": score += 1
                case "T" where w.value >= 100: score += 1
                default: break
                }
            }
        }
        return !sawY && score >= 2
    }
}
