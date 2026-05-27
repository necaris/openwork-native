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

            guard let executableURL = Self.locateOpenCode() else {
                AppLog.process.error("locateOpenCode failed — opencode not found on PATH")
                throw OpenCodeProcessError.missingExecutable
            }

            guard let port = PortAllocator.availablePort() else {
                AppLog.process.error("PortAllocator returned nil")
                throw OpenCodeProcessError.portUnavailable
            }
            AppLog.process.log("Starting OpenCode: executable=\(executableURL.path, privacy: .public) port=\(port, privacy: .public) workspace=\(workspace.path, privacy: .public)")

            outputBuffer = ""
            intentionallyStopping = false

            let process = Process()
            process.currentDirectoryURL = URL(fileURLWithPath: workspace.path)
            process.executableURL = executableURL
            process.arguments = ["serve", "--hostname", "127.0.0.1", "--port", String(port)]

            if let shellPath = Self.userShellPath() {
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = shellPath
                process.environment = environment
            }

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
                    AppLog.process.log("OpenCode exited: status=\(terminationStatus, privacy: .public) intentional=\(manager.intentionallyStopping, privacy: .public) outputLen=\(output.count, privacy: .public)")
                    if shouldReport {
                        AppLog.process.error("OpenCode exited unexpectedly: \(output, privacy: .public)")
                        onUnexpectedExit(output.isEmpty ? "OpenCode exited with status \(terminationStatus)." : output)
                    }
                }
            }

            try process.run()
            self.process = process
            AppLog.process.log("OpenCode process running pid=\(process.processIdentifier, privacy: .public) port=\(port, privacy: .public)")
            return OpenCodeRuntime(baseURL: URL(string: "http://127.0.0.1:\(port)")!, port: port)
        }
    }

    func stop() {
        queue.sync {
            guard let process else { return }
            intentionallyStopping = true
            AppLog.process.log("Stopping OpenCode pid=\(process.processIdentifier, privacy: .public) running=\(process.isRunning, privacy: .public)")
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
        AppLog.process.debug("opencode stdio: \(text, privacy: .public)")
        outputBuffer.append(text)
        if outputBuffer.count > 20_000 {
            outputBuffer.removeFirst(outputBuffer.count - 20_000)
        }
    }

    static func userShellPath() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "printf %s \"$PATH\""]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    static func locateOpenCode() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "opencode"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        var environment = ProcessInfo.processInfo.environment
        if let shellPath = userShellPath() {
            environment["PATH"] = shellPath
        }
        process.environment = environment

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            AppLog.process.error("locateOpenCode: 'which opencode' returned empty or non-executable path: \(path, privacy: .public)")
            return nil
        }
        AppLog.process.log("locateOpenCode: \(path, privacy: .public)")
        return URL(fileURLWithPath: path)
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
