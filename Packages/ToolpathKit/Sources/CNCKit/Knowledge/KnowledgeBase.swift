import Foundation

/// One `##` section of the curated knowledge base.
public struct KnowledgeSection: Sendable, Hashable, Identifiable {
    public var id: String { "\(source)#\(title)" }
    public let source: String
    public let title: String
    public let body: String
}

/// Local, offline retrieval over the curated markdown notes. Plain BM25
/// keyword scoring — the corpus is tiny (dozens of sections), so this is
/// instant and needs no embeddings service.
public struct KnowledgeBase: Sendable {
    public let sections: [KnowledgeSection]
    private let tokens: [[String: Int]]
    private let lengths: [Int]
    private let documentFrequency: [String: Int]
    private let averageLength: Double

    public init(markdownFiles: [(name: String, text: String)]) {
        var sections: [KnowledgeSection] = []
        for file in markdownFiles {
            var title: String?
            var body: [String] = []
            func flush() {
                if let title, !body.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections.append(KnowledgeSection(source: file.name, title: title,
                                                     body: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                body = []
            }
            for line in file.text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("## ") {
                    flush()
                    title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if !line.hasPrefix("# ") {
                    body.append(String(line))
                }
            }
            flush()
        }
        self.sections = sections
        let tokenized = sections.map { Self.termCounts(Self.tokenize($0.title + " " + $0.title + " " + $0.body)) }
        tokens = tokenized
        lengths = tokenized.map { $0.values.reduce(0, +) }
        var df: [String: Int] = [:]
        for counts in tokenized { for term in counts.keys { df[term, default: 0] += 1 } }
        documentFrequency = df
        averageLength = lengths.isEmpty ? 1 : Double(lengths.reduce(0, +)) / Double(lengths.count)
    }

    public func search(_ query: String, limit: Int = 3) -> [KnowledgeSection] {
        let terms = Set(Self.tokenize(query))
        guard !terms.isEmpty else { return [] }
        let n = Double(sections.count)
        let k1 = 1.4, b = 0.75
        var scored: [(Int, Double)] = []
        for (index, counts) in tokens.enumerated() {
            var score = 0.0
            for term in terms {
                guard let tf = counts[term].map(Double.init) else { continue }
                let df = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (n - df + 0.5) / (df + 0.5))
                let norm = tf * (k1 + 1) / (tf + k1 * (1 - b + b * Double(lengths[index]) / averageLength))
                score += idf * norm
            }
            if score > 0 { scored.append((index, score)) }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { sections[$0.0] }
    }

    static let stopWords: Set<String> = ["the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "is", "it", "my", "i", "with", "why", "what", "how", "does", "do", "when", "be", "are", "this", "that", "can", "at", "as", "by", "from", "keep", "too"]

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { stem(String($0)) }
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }

    /// Tiny suffix stripper so "chattering"/"chatter", "bits"/"bit" match.
    static func stem(_ word: String) -> String {
        for suffix in ["ing", "ed", "es", "s"] where word.count - suffix.count >= 3 && word.hasSuffix(suffix) {
            return String(word.dropLast(suffix.count))
        }
        return word
    }

    static func termCounts(_ terms: [String]) -> [String: Int] {
        terms.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
