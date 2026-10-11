import CNCKit
import Foundation
import Network
import Observation

/// Read-only live monitor for Wi-Fi controllers (FluidNC, grblHAL).
///
/// Safety: the only byte this class ever sends is `?` — GRBL's real-time
/// status query. It cannot start, stop, jog or change anything on the
/// machine. Control is deliberately out of scope.
@MainActor
@Observable
final class MachineMonitor {
    enum Transport: String, CaseIterable, Identifiable {
        case telnet, webSocket
        var id: String { rawValue }
        var defaultPort: UInt16 { self == .telnet ? 23 : 81 }
    }

    enum Phase: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var phase: Phase = .disconnected
    private(set) var status: ControllerStatus?
    private(set) var lastEvent: ControllerEvent?
    private(set) var lastUpdate: Date?

    private var connection: NWConnection?
    private var pollTask: Task<Void, Never>?
    private var buffer = ""
    private static let statusQuery = Data("?".utf8)

    func connect(host: String, port: UInt16, transport: Transport) {
        disconnect()
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else {
            phase = .failed(String(localized: "Enter the controller's address."))
            return
        }
        let parameters: NWParameters
        if transport == .webSocket {
            parameters = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        } else {
            parameters = .tcp
        }
        let endpoint: NWEndpoint = transport == .webSocket
            ? .url(URL(string: "ws://\(host):\(port)/")!)
            : .hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        phase = .connecting

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state) }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receive(on: connection, isWebSocket: transport == .webSocket)
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        connection?.cancel()
        connection = nil
        if phase != .disconnected { phase = .disconnected }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            phase = .connected
            startPolling()
        case let .failed(error), let .waiting(error):
            phase = .failed(error.localizedDescription)
            pollTask?.cancel()
        case .cancelled:
            phase = .disconnected
        default:
            break
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sendStatusQuery()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func sendStatusQuery() {
        guard let connection else { return }
        let isWebSocket = connection.parameters.defaultProtocolStack.applicationProtocols.first is NWProtocolWebSocket.Options
        if isWebSocket {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "status", metadata: [metadata])
            connection.send(content: Self.statusQuery, contentContext: context, isComplete: true, completion: .idempotent)
        } else {
            connection.send(content: Self.statusQuery, completion: .idempotent)
        }
    }

    private nonisolated func receive(on connection: NWConnection, isWebSocket: Bool) {
        let handler: @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void = { [weak self] data, _, _, error in
            if let data, let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in self?.ingest(text) }
            }
            if error == nil { self?.receive(on: connection, isWebSocket: isWebSocket) }
        }
        if isWebSocket {
            connection.receiveMessage(completion: handler)
        } else {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096, completion: handler)
        }
    }

    private func ingest(_ text: String) {
        buffer += text
        while let range = buffer.rangeOfCharacter(from: .newlines) {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            process(line)
        }
        // WebSocket frames may carry a full report without a newline.
        if buffer.hasPrefix("<"), buffer.hasSuffix(">") {
            process(buffer)
            buffer = ""
        }
        if buffer.count > 8192 { buffer = "" }
    }

    private func process(_ line: String) {
        if let parsed = ControllerStatus.parse(line) {
            status = parsed
            lastUpdate = .now
        } else if let event = ControllerEvent.parse(line) {
            lastEvent = event
        }
    }
}
