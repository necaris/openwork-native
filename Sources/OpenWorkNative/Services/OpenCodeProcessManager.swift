import Darwin
import Foundation

struct OpenCodeRuntime {
    let baseURL: URL
    let port: Int
}

enum OpenCodeProcessError: LocalizedError {
    case missingExecutable
    case portUnavailable

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "OpenCode is not installed or is not on PATH."
        case .portUnavailable:
            "Could not allocate a localhost port for OpenCode."
        }
    }
}

final class OpenCodeProcessManager: @unchecked Sendable {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var outputBuffer = ""
    private var intentionallyStopping = false
    private let queue = DispatchQueue(label: "com.opencode.process")

    func start(for workspace: Workspace, onUnexpectedExit: @escaping @Sendable (String) -> Void) throws -> OpenCodeRuntime {
        return try queue.sync {
            if process?.isRunning == true {
                let port = PortAllocator.availablePort() ?? 4096
                return OpenCodeRuntime(baseURL: URL(string: "http://127.0.0.1:\(port)")!, port: port)
            }

            guard Self.hasOpenCodeOnPath() else {
                throw OpenCodeProcessError.missingExecutable
            }

            guard let port = PortAllocator.availablePort() else {
                throw OpenCodeProcessError.portUnavailable
            }

            outputBuffer = ""
            intentionallyStopping = false

            let process = Process()
            process.currentDirectoryURL = URL(fileURLWithPath: workspace.path)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["opencode", "serve", "--hostname", "127.0.0.1", "--port", String(port)]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let manager = self else { return }
                manager.queue.async {
                    manager.appendOutput(data)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let manager = self else { return }
                manager.queue.async {
                    manager.appendOutput(data)
                }
            }

            process.terminationHandler = { [weak self] process in
                let terminationStatus = process.terminationStatus
                guard let manager = self else { return }
                manager.queue.async {
                    manager.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                    manager.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                    let output = manager.outputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    let shouldReport = !manager.intentionallyStopping && terminationStatus != 0
                    manager.process = nil
                    if shouldReport {
                        onUnexpectedExit(output.isEmpty ? "OpenCode exited with status \(terminationStatus)." : output)
                    }
                }
            }

            try process.run()
            self.process = process
            return OpenCodeRuntime(baseURL: URL(string: "http://127.0.0.1:\(port)")!, port: port)
        }
    }

    func stop() {
        queue.sync {
            guard let process else { return }
            intentionallyStopping = true
            if process.isRunning {
                process.terminate()
            }
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            stderrPipe?.fileHandleForReading.readabilityHandler = nil
            self.process = nil
        }
    }

    func capturedOutput() -> String {
        queue.sync { outputBuffer.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func appendOutput(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        outputBuffer.append(text)
        if outputBuffer.count > 20_000 {
            outputBuffer.removeFirst(outputBuffer.count - 20_000)
        }
    }

    private static func hasOpenCodeOnPath() -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        return path.split(separator: ":").contains { directory in
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("opencode").path
            return FileManager.default.isExecutableFile(atPath: candidate)
        }
    }
}

enum PortAllocator {
    static func availablePort() -> Int? {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return nil }
        defer { close(socketDescriptor) }

        var value: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return nil }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(socketDescriptor, sockaddrPointer, &length)
            }
        }
        guard result == 0 else { return nil }
        return Int(UInt16(bigEndian: boundAddress.sin_port))
    }
}
