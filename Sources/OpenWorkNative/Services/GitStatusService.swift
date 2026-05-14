import Foundation

struct GitStatusService: Sendable {
    func changedFiles(in workspace: Workspace) async -> [ChangedFile] {
        await Task.detached(priority: .utility) {
            Self.changedFilesSynchronously(in: workspace)
        }.value
    }

    private static func changedFilesSynchronously(in workspace: Workspace) -> [ChangedFile] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", workspace.path, "status", "--porcelain"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return Self.parsePorcelain(text)
    }

    static func parsePorcelain(_ output: String) -> [ChangedFile] {
        output
            .split(separator: "\n")
            .compactMap { line -> ChangedFile? in
                let line = String(line)
                guard line.count >= 4 else { return nil }
                let statusCode = String(line.prefix(2))
                let pathStart = line.index(line.startIndex, offsetBy: 3)
                let rawPath = String(line[pathStart...])
                let path = rawPath.components(separatedBy: " -> ").last ?? rawPath
                return ChangedFile(path: path, status: statusDescription(for: statusCode))
            }
    }

    private static func statusDescription(for code: String) -> String {
        if code.contains("A") { return "added" }
        if code.contains("D") { return "deleted" }
        if code.contains("R") { return "renamed" }
        if code.contains("M") { return "modified" }
        if code.contains("?") { return "untracked" }
        return "changed"
    }
}
