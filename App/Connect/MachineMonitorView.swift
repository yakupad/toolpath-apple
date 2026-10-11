import CNCDesign
import CNCKit
import SwiftUI

/// Live, read-only view of a Wi-Fi controller: state, positions, feed,
/// spindle and alarms. Beta.
struct MachineMonitorView: View {
    @Bindable var machine: Machine
    @State private var monitor = MachineMonitor()
    @AppStorage("monitor.transport") private var transportRaw = MachineMonitor.Transport.telnet.rawValue

    private var transport: MachineMonitor.Transport { .init(rawValue: transportRaw) ?? .telnet }

    var body: some View {
        Form {
            Section {
                TextField("Controller address", text: $machine.monitorHost)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                Picker("Connection", selection: $transportRaw) {
                    Text("Telnet (grblHAL, FluidNC)").tag(MachineMonitor.Transport.telnet.rawValue)
                    Text("WebSocket (FluidNC)").tag(MachineMonitor.Transport.webSocket.rawValue)
                }
                connectButton
            } footer: {
                Text("Read-only: Toolpath only asks the controller for its status. It never sends motion or settings commands.")
            }

            if let status = monitor.status {
                Section {
                    HStack {
                        StateBadge(state: status.state)
                        Spacer()
                        if let updated = monitor.lastUpdate {
                            Text(updated, style: .relative).font(.caption).foregroundStyle(TP.Palette.textSecondary)
                        }
                    }
                    if let w = status.resolvedWorkPosition {
                        HStack {
                            ValueLabel("X", value: w.x.formatted(.number.precision(.fractionLength(3))), unit: "mm", size: 26)
                            Spacer()
                            ValueLabel("Y", value: w.y.formatted(.number.precision(.fractionLength(3))), unit: "mm", size: 26)
                            Spacer()
                            ValueLabel("Z", value: w.z.formatted(.number.precision(.fractionLength(3))), unit: "mm", size: 26)
                        }
                    }
                    HStack {
                        if let feed = status.feed { ValueLabel("Feed", value: Int(feed).formatted(), unit: "mm/min", size: 20) }
                        Spacer()
                        if let spindle = status.spindle { ValueLabel("Spindle", value: Int(spindle).formatted(), unit: "rpm", size: 20) }
                        Spacer()
                        if let line = status.lineNumber { ValueLabel("Line", value: line.formatted(), size: 20) }
                    }
                } header: {
                    Text("Work position")
                }
            }

            if let event = monitor.lastEvent {
                Section("Last message") {
                    switch event {
                    case let .alarm(code):
                        if let message = AlarmDecoder.lookup(.alarm, code) {
                            AlarmCard(message: message, hasHomingSwitches: machine.hasHomingSwitches)
                        }
                    case let .error(code):
                        if let message = AlarmDecoder.lookup(.error, code) {
                            AlarmCard(message: message, hasHomingSwitches: machine.hasHomingSwitches)
                        }
                    case let .message(text):
                        Text(text).font(.tpCode)
                    }
                }
            }
        }
        .navigationTitle("Live monitor (beta)")
        .onDisappear { monitor.disconnect() }
        .sensoryFeedback(.error, trigger: monitor.lastEvent)
    }

    @ViewBuilder
    private var connectButton: some View {
        switch monitor.phase {
        case .connected:
            Button("Disconnect", role: .destructive) { monitor.disconnect() }
        case .connecting:
            HStack { ProgressView(); Text("Connecting…") }
        case let .failed(reason):
            VStack(alignment: .leading, spacing: 6) {
                Text(reason).font(.footnote).foregroundStyle(TP.Palette.danger)
                Button("Try again") { connect() }
            }
        case .disconnected:
            Button("Connect") { connect() }
                .disabled(machine.monitorHost.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func connect() {
        let parts = machine.monitorHost.trimmingCharacters(in: .whitespaces).split(separator: ":")
        let host = parts.first.map(String.init) ?? ""
        let port = parts.count > 1 ? UInt16(parts[1]) ?? transport.defaultPort : transport.defaultPort
        monitor.connect(host: host, port: port, transport: transport)
    }
}

struct StateBadge: View {
    let state: ControllerStatus.State

    var body: some View {
        Text(state == .unknown ? "—" : state.rawValue)
            .font(.headline)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .run, .jog, .home: TP.Palette.success
        case .hold, .door, .tool: TP.Palette.caution
        case .alarm: TP.Palette.danger
        default: TP.Palette.textSecondary
        }
    }
}
