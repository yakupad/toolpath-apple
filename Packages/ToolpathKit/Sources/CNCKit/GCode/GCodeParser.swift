import Foundation

/// Deterministic G-code interpreter. Resolves modal state (motion mode, units,
/// absolute/incremental, feed, spindle, tool) across lines the way a real
/// controller would, and emits one `GCodeMove` per motion command.
///
/// This is the "deterministic trust" layer: nothing downstream re-derives
/// positions or units, and no LLM ever touches these numbers.
public struct GCodeParser: Sendable {
    public init() {}

    public func parse(_ source: String, fileName: String) -> GCodeDocument {
        var position = GPoint.zero
        var motionMode = MoveType.rapid
        var absoluteMode = true
        var unitScale = 1.0 // 1.0 = mm, 25.4 = inch -> mm
        var feedRate = 0.0
        var spindleOn = false
        var spindleSpeed = 0.0
        var pendingTool: Int?
        var activeTool: Int?

        var moves: [GCodeMove] = []
        moves.reserveCapacity(source.utf8.count / 24)
        var m6Changes: [(tool: Int, line: Int, moveIndex: Int)] = []
        var tOnlyChanges: [(tool: Int, line: Int, moveIndex: Int)] = []
        var lastToolSelection: Int?

        var lineNumber = 0
        var totalLines = 0
        var words: [Word] = []
        words.reserveCapacity(8)

        source.enumerateLines { rawLine, _ in
            lineNumber += 1
            totalLines = lineNumber
            words.removeAll(keepingCapacity: true)
            Self.scanWords(rawLine, into: &words)
            if words.isEmpty { return }

            var x: Double?, y: Double?, z: Double?, i: Double?, j: Double?
            var hasM6 = false
            var tWord: Int?

            for word in words {
                switch word.letter {
                case "G":
                    switch Int(word.value.rounded()) {
                    case 0: motionMode = .rapid
                    case 1: motionMode = .linear
                    case 2: motionMode = .arcClockwise
                    case 3: motionMode = .arcCounterClockwise
                    case 20: unitScale = 25.4
                    case 21: unitScale = 1.0
                    case 90: absoluteMode = true
                    case 91: absoluteMode = false
                    default: break
                    }
                case "M":
                    switch Int(word.value.rounded()) {
                    case 3, 4: spindleOn = true
                    case 5: spindleOn = false
                    case 6: hasM6 = true
                    default: break
                    }
                case "X": x = word.value
                case "Y": y = word.value
                case "Z": z = word.value
                case "I": i = word.value
                case "J": j = word.value
                case "F": feedRate = word.value * unitScale
                case "S": spindleSpeed = word.value
                case "T": tWord = Int(word.value.rounded())
                default: break
                }
            }

            if let t = tWord {
                pendingTool = t
                if t != lastToolSelection {
                    tOnlyChanges.append((t, lineNumber, moves.count))
                    lastToolSelection = t
                }
            }
            if hasM6, let t = pendingTool {
                activeTool = t
                m6Changes.append((t, lineNumber, moves.count))
            } else if tWord != nil, activeTool == nil {
                // GRBL-style posts often emit "T1" without M6 (GRBL ignores M6);
                // treat the first selection as the active tool.
                activeTool = tWord
            }

            guard x != nil || y != nil || z != nil else { return }

            func resolve(_ value: Double?, _ current: Double) -> Double {
                guard let value else { return current }
                let scaled = value * unitScale
                return absoluteMode ? scaled : current + scaled
            }
            let target = GPoint(x: resolve(x, position.x), y: resolve(y, position.y), z: resolve(z, position.z))

            var arcCenter: GPoint?
            if motionMode == .arcClockwise || motionMode == .arcCounterClockwise, i != nil || j != nil {
                arcCenter = GPoint(
                    x: position.x + (i ?? 0) * unitScale,
                    y: position.y + (j ?? 0) * unitScale,
                    z: position.z
                )
            }

            moves.append(GCodeMove(
                index: moves.count,
                sourceLine: lineNumber,
                type: motionMode,
                start: position,
                end: target,
                feedRate: feedRate,
                spindleOn: spindleOn,
                spindleSpeed: spindleSpeed,
                toolNumber: activeTool ?? pendingTool,
                arcCenter: arcCenter
            ))
            position = target
        }

        let changes = (m6Changes.isEmpty ? tOnlyChanges : m6Changes).map { change in
            ToolChange(
                toolNumber: change.tool,
                sourceLine: change.line,
                firstMoveIndex: change.moveIndex < moves.count ? change.moveIndex : nil
            )
        }
        return GCodeDocument(fileName: fileName, totalLines: totalLines, moves: moves, toolChanges: changes)
    }

    struct Word {
        let letter: Character
        let value: Double
    }

    /// Splits one line into letter/number words, skipping `( … )` and `;`
    /// comments. Accepts signed and leading-dot numbers (`X-.5`, `Z+2`).
    static func scanWords(_ line: String, into words: inout [Word]) {
        let bytes = Array(line.utf8)
        var index = 0
        let count = bytes.count
        while index < count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "(") {
                while index < count, bytes[index] != UInt8(ascii: ")") { index += 1 }
                index += 1
                continue
            }
            if byte == UInt8(ascii: ";") { return }
            let upper = byte & 0xDF
            guard upper >= UInt8(ascii: "A"), upper <= UInt8(ascii: "Z") else {
                index += 1
                continue
            }
            var cursor = index + 1
            while cursor < count, bytes[cursor] == UInt8(ascii: " ") || bytes[cursor] == UInt8(ascii: "\t") {
                cursor += 1
            }
            let numberStart = cursor
            if cursor < count, bytes[cursor] == UInt8(ascii: "-") || bytes[cursor] == UInt8(ascii: "+") {
                cursor += 1
            }
            var sawDigit = false
            while cursor < count, (bytes[cursor] >= UInt8(ascii: "0") && bytes[cursor] <= UInt8(ascii: "9")) || bytes[cursor] == UInt8(ascii: ".") {
                if bytes[cursor] != UInt8(ascii: ".") { sawDigit = true }
                cursor += 1
            }
            if sawDigit,
               let text = String(bytes: bytes[numberStart..<cursor], encoding: .ascii),
               let value = Double(text) {
                words.append(Word(letter: Character(Unicode.Scalar(upper)), value: value))
                index = cursor
            } else {
                index += 1
            }
        }
    }
}
