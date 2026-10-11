import CNCKit
import Foundation

/// Deterministic answers for devices without Apple Intelligence (unsupported
/// hardware or regions): decoded alarm codes plus the best-matching workshop
/// notes. No model, no network.
enum OfflineAnswer {
    static func compose(for question: String, hasHomingSwitches: Bool) -> ChatMessage {
        var parts: [String] = []
        var tools: [String] = []

        let alarms = AlarmDecoder.decode(question)
        if !alarms.isEmpty {
            tools.append("decode_controller_alarm")
            for m in alarms {
                let steps = m.steps(machineHasHomingSwitches: hasHomingSwitches)
                    .enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                parts.append("**\(m.kind == .alarm ? "ALARM" : "error"):\(m.code) — \(m.title)**\n\(m.meaning)\n\(steps)")
            }
        }

        let notes = Knowledge.base.search(expand(question), limit: 2)
        if !notes.isEmpty {
            tools.append("search_knowledge_base")
            parts += notes.map { "**\($0.title)**\n\($0.body)" }
        }

        if mentionsCuttingNumbers(question) {
            parts.append(String(localized: "For RPM, feed and depth of cut, use the Feeds & Speeds calculator in the Calculate tab — it works from your machine's limits."))
        }

        if parts.isEmpty {
            parts.append(String(localized: "I couldn't find this in the workshop notes. Try different words — for example the material, the symptom or the alarm code."))
        }
        return ChatMessage(role: .assistant, text: parts.joined(separator: "\n\n"), toolsUsed: tools)
    }

    /// The notes are written in English; translate common workshop words so
    /// questions in other app languages still find them.
    static func expand(_ question: String) -> String {
        let lower = question.lowercased()
        let extra = glossary.compactMap { key, value in lower.contains(key) ? value : nil }
        return ([question] + extra).joined(separator: " ")
    }

    private static func mentionsCuttingNumbers(_ q: String) -> Bool {
        let l = q.lowercased()
        return ["rpm", "feed", "speed", "devir", "ilerleme", "hız", "drehzahl", "vorschub", "velocidad", "avance", "velocità", "avanzamento", "обороты", "подача"].contains { l.contains($0) }
    }

    private static let glossary: [String: String] = [
        // Turkish
        "titre": "chatter vibration", "yanık": "burning burn marks", "yanma": "burning", "eriy": "melting", "erime": "melting",
        "kırıl": "tool breakage", "kırdı": "tool breakage", "yüzey": "surface finish", "pürüz": "surface finish", "bağla": "workholding",
        "kayd": "workholding shifts", "alüminyum": "aluminum", "pirinç": "brass", "çelik": "steel",
        "paslanmaz": "stainless steel", "bakır": "copper", "polikarbonat": "polycarbonate", "naylon": "nylon", "forex": "pvc foam board", "köpük": "foam xps pvc", "strafor": "xps foam", "mum": "machinable wax", "pcb": "fr4 pcb", "devre": "fr4 pcb", "karbon": "carbon fiber", "bambu": "bamboo", "akrilik": "acrylic", "pleksi": "acrylic", "kontrplak": "plywood",
        "ahşap": "hardwood softwood wood", "çam": "softwood pine", "meşe": "hardwood oak", "freze": "end mill",
        "uç": "end mill bit flutes", "ağız": "flutes", "kaplama": "coatings", "talaş": "chip", "toz": "dust",
        "gözlük": "eye protection PPE", "güvenlik": "safety PPE", "acil": "emergency stop",
        "birim": "units G20 G21", "inç": "units G20", "sıfır": "work coordinate offsets G54",
        "iş mili": "spindle M3 M5", "takım değiş": "tool change M6", "soğutma": "coolant M8",
        // German
        "ratter": "chatter", "verbrannt": "burning", "schmelz": "melting", "bruch": "tool breakage",
        "oberfläche": "surface finish", "spann": "workholding", "aluminium": "aluminum", "messing": "brass",
        "stahl": "steel", "sperrholz": "plywood", "holz": "wood", "fräser": "end mill",
        // Spanish / Italian
        "vibra": "chatter", "quema": "burning", "bruciat": "burning", "rotura": "tool breakage",
        "rottura": "tool breakage", "acabado": "surface finish", "finitura": "surface finish",
        "sujeción": "workholding", "bloccaggio": "workholding", "aluminio": "aluminum", "alluminio": "aluminum",
        "latón": "brass", "ottone": "brass", "acero": "steel", "acciaio": "steel", "madera": "wood", "legno": "wood",
        "fresa": "end mill",
        // Russian
        "вибрац": "chatter", "горит": "burning", "подгор": "burning", "плав": "melting", "слом": "tool breakage", "алюмин": "aluminum",
        "латун": "brass", "сталь": "steel", "фанер": "plywood", "дерев": "wood", "фрез": "end mill",
    ]
}
