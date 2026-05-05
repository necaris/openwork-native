import Foundation

final class OpenCodeProcessManager {
    private var process: Process?

    func start(for workspace: Workspace) throws {
        if process?.isRunning == true { return }

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: workspace.path)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["opencode", "serve"]
        try process.run()
        self.process = process
    }

    func stop() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }
}
