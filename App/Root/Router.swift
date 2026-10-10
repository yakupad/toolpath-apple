import CNCKit
import CNCRender
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

enum AppTab: Hashable {
    case workshop, jobs, calculate, library, ask
}

/// App-wide navigation state (the coordinator in MVVM-C terms).
@MainActor
@Observable
final class Router {
    var tab: AppTab = .workshop
    var jobsPath: [UUID] = []
    var isImporting = false
    var showSettings = false
    var showPaywall = false
    var importError: String?
    /// Files opened from outside (Files, AirDrop, Finder) before a model
    /// context was available.
    var pendingURLs: [URL] = []

    let analyses = AnalysisStore()

    func importFile(at url: URL) {
        pendingURLs.append(url)
    }

    /// Reads the files, saves them as jobs and opens the last one.
    func consumePending(into context: ModelContext) {
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        var lastID: UUID?
        for url in urls {
            do {
                let job = try JobImporter.makeJob(from: url)
                context.insert(job)
                lastID = job.id
            } catch {
                importError = error.localizedDescription
            }
        }
        try? context.save()
        if let lastID { open(job: lastID) }
    }

    func open(job id: UUID) {
        tab = .jobs
        jobsPath = [id]
    }
}

enum JobImporter {
    static let contentTypes: [UTType] = [UTType("com.yakupad.toolpath.gcode") ?? .plainText, .plainText, .text]
    static let maxBytes = 50 * 1024 * 1024

    enum ImportError: LocalizedError {
        case tooLarge, unreadable
        var errorDescription: String? {
            switch self {
            case .tooLarge: String(localized: "This file is larger than 50 MB.")
            case .unreadable: String(localized: "This file couldn't be read as G-code text.")
            }
        }
    }

    static func makeJob(from url: URL) throws -> JobFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= maxBytes else { throw ImportError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable
        }
        return JobFile(name: url.lastPathComponent, content: text)
    }

    static func sampleJob() -> JobFile {
        JobFile(name: "sample_sign.nc", content: SampleProgram.sign)
    }
}

/// Result of analyzing one job — computed off the main actor, cached by id.
struct JobAnalysis: Sendable {
    let document: GCodeDocument
    let findings: [Finding]
    let groups: [FindingGroup]
    let statistics: GCodeStatistics
    let geometry: ToolpathGeometry
    let timeline: GCodeTimeline
    let score: Int

    static func make(content: String, name: String, rapidRate: Double) -> JobAnalysis {
        let document = GCodeParser().parse(content, fileName: name)
        let findings = GCodeAnalyzer().analyze(document)
        return JobAnalysis(
            document: document,
            findings: findings,
            groups: FindingGroup.group(findings),
            statistics: GCodeStatistics(document: document, rapidRateMmPerMin: rapidRate),
            geometry: ToolpathGeometry(document: document, findings: findings),
            timeline: GCodeTimeline(document: document, rapidRateMmPerMin: rapidRate),
            score: SafetyScore.compute(findings)
        )
    }

    var dangerCount: Int { groups.filter { $0.severity == .danger }.reduce(0) { $0 + $1.count } }
    var cautionCount: Int { groups.filter { $0.severity == .caution }.reduce(0) { $0 + $1.count } }
}

@MainActor
@Observable
final class AnalysisStore {
    private(set) var results: [UUID: JobAnalysis] = [:]
    private var inFlight: Set<UUID> = []

    func analysis(for job: JobFile, rapidRate: Double) -> JobAnalysis? {
        if let cached = results[job.id] { return cached }
        load(job, rapidRate: rapidRate)
        return nil
    }

    func load(_ job: JobFile, rapidRate: Double) {
        let id = job.id
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        let content = job.content, name = job.name
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                JobAnalysis.make(content: content, name: name, rapidRate: rapidRate)
            }.value
            results[id] = result
            inFlight.remove(id)
            // Cache the summary on the model for lists and widgets.
            job.safetyScore = result.score
            job.dangerCount = result.dangerCount
            job.cautionCount = result.cautionCount
            job.estimatedMinutes = result.statistics.estimatedMachiningTimeMinutes
            job.toolCount = max(result.document.toolChanges.count, 1)
            let bounds = result.document.cuttingBounds ?? result.document.bounds
            job.widthMm = bounds.width
            job.heightMm = bounds.height
        }
    }

    func invalidate(_ id: UUID) { results[id] = nil }
}
