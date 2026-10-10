import CNCDesign
import CNCKit
import CNCRender
import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = false
    @State private var step = 0
    @State private var preset: MachinePreset?
    @State private var tools: Set<String> = ["eighth", "quarter"]
    @State private var acceptedSafety = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<4) { i in
                    Capsule().fill(i <= step ? TP.Palette.accent : TP.Palette.separator).frame(height: 4)
                }
            }
            .padding(.horizontal, TP.Metric.gutter)
            .padding(.top, 12)

            Group {
                switch step {
                case 0: hero
                case 1: machineStep
                case 2: toolsStep
                default: safetyStep
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            VStack(spacing: 8) {
                Button(primaryTitle) { advance() }
                    .buttonStyle(.tpPrimary)
                    .disabled(step == 3 && !acceptedSafety)
                    .opacity(step == 3 && !acceptedSafety ? 0.5 : 1)
                if step == 1 || step == 2 {
                    Button("Skip for now") { withAnimation(.snappy) { step += 1 } }
                }
            }
            .padding(TP.Metric.gutter)
        }
        .background(TP.Palette.canvas)
        .interactiveDismissDisabled()
    }

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case 0: "Set up my workshop"
        case 3: "Start using Toolpath"
        default: "Continue"
        }
    }

    private func advance() {
        if step < 3 {
            withAnimation(.snappy) { step += 1 }
            return
        }
        if let preset {
            let machine = Machine(name: preset.name)
            machine.presetID = preset.id
            machine.travelX = preset.x
            machine.travelY = preset.y
            machine.travelZ = preset.z
            machine.maxSpindleRpm = preset.maxRpm
            machine.minSpindleRpm = preset.minRpm
            machine.isActive = true
            context.insert(machine)
        }
        for option in StarterTool.all where tools.contains(option.id) {
            context.insert(option.make())
        }
        try? context.save()
        onboarded = true
        dismiss()
    }

    // MARK: Steps

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeroToolpath()
                .frame(height: 340)
                .clipShape(.rect(cornerRadius: 28))
                .padding(.top, 20)
            Text("See it before\nyou cut it.")
                .font(.system(size: 40, weight: .bold))
                .tracking(-0.8)
            Text("Check every G-code file, get feeds you can trust, and follow the job from your lock screen.")
                .font(.title3)
                .foregroundStyle(TP.Palette.textSecondary)
        }
        .padding(.horizontal, TP.Metric.gutter)
    }

    private var machineStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Which machine do you run?").font(.largeTitle.bold())
                Text("We'll load its travel and spindle limits so every check fits your machine.")
                    .foregroundStyle(TP.Palette.textSecondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(MachinePreset.all) { option in
                        Button { preset = option } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: "cube.transparent").font(.title2).foregroundStyle(TP.Palette.accentText)
                                Spacer(minLength: 8)
                                Text(option.name).font(.headline).multilineTextAlignment(.leading)
                                Text("\(Int(option.x)) × \(Int(option.y)) mm").font(.caption).foregroundStyle(TP.Palette.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                            .padding(14)
                            .background(preset == option ? TP.Palette.accent.opacity(0.12) : TP.Palette.card, in: .rect(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(preset == option ? TP.Palette.accent : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sensoryFeedback(.selection, trigger: preset)
            }
            .padding(TP.Metric.gutter)
        }
    }

    private var toolsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which bits do you own?").font(.largeTitle.bold())
            Text("Pre-flight and feeds use your own tools. Add more anytime in Library.")
                .foregroundStyle(TP.Palette.textSecondary)
            ForEach(StarterTool.all) { option in
                Button {
                    if tools.contains(option.id) { tools.remove(option.id) } else { tools.insert(option.id) }
                } label: {
                    HStack {
                        Image(systemName: tools.contains(option.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(tools.contains(option.id) ? TP.Palette.success : TP.Palette.textTertiary)
                        Text(option.title).font(.headline)
                        Spacer()
                    }
                    .frame(minHeight: TP.Metric.target)
                    .padding(.horizontal, 14)
                    .background(TP.Palette.card, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(TP.Metric.gutter)
    }

    private var safetyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 52))
                .foregroundStyle(TP.Palette.accent)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("Starting points, not guarantees").font(.largeTitle.bold())
            Text("Toolpath checks your files and calculates conservative values, but your machine, stock and setup are unique. Always make a test cut, keep your hands clear, and wear eye and ear protection.")
                .foregroundStyle(TP.Palette.textSecondary)
            Toggle("I understand and will verify settings before cutting", isOn: $acceptedSafety)
                .font(.headline)
                .padding(14)
                .background(TP.Palette.card, in: .rect(cornerRadius: 16))
        }
        .padding(TP.Metric.gutter)
    }
}

@MainActor
struct StarterTool: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let make: () -> Tool

    static let all: [StarterTool] = [
        .init(id: "eighth", title: "1/8\" flat end mill, 2 flute") { Tool(nickname: "1/8\" flat 2F", diameterMm: 3.175, flutes: 2) },
        .init(id: "quarter", title: "1/4\" flat end mill, 2 flute") { Tool(nickname: "1/4\" flat 2F", diameterMm: 6.35, flutes: 2) },
        .init(id: "vbit", title: "60° V-bit") { Tool(nickname: "60° V-bit", diameterMm: 12.7, flutes: 2, shape: .vBit) },
        .init(id: "ball", title: "1/8\" ball nose") { Tool(nickname: "1/8\" ball nose", diameterMm: 3.175, flutes: 2, shape: .ball) },
        .init(id: "compression", title: "1/4\" compression bit") { Tool(nickname: "1/4\" compression", diameterMm: 6.35, flutes: 2, shape: .compression) },
    ]
}

/// The onboarding hero: the sample sign drawing itself, on a loop.
struct HeroToolpath: View {
    @State private var geometry = ToolpathGeometry(
        document: GCodeParser().parse(SampleProgram.sign, fileName: "sample"),
        findings: []
    )
    @State private var progress = 0.0
    @State private var camera = OrbitCamera.isometric

    var body: some View {
        ToolpathCanvas(geometry: geometry, camera: camera, drawProgress: progress)
            .task {
                while !Task.isCancelled {
                    progress = 0
                    withAnimation(.easeInOut(duration: 3.2)) { progress = 1 }
                    withAnimation(.easeInOut(duration: 8)) { camera.yaw = OrbitCamera.isometric.yaw + 0.5 }
                    try? await Task.sleep(for: .seconds(4.5))
                    withAnimation(.easeInOut(duration: 1.5)) { camera.yaw = OrbitCamera.isometric.yaw }
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
            .accessibilityHidden(true)
    }
}
