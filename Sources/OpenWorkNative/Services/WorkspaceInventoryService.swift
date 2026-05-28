import Foundation

struct WorkspaceInventoryService: Sendable {
    func loadInventory(in workspace: Workspace) async -> [WorkspaceInventoryItem] {
        let root = URL(fileURLWithPath: workspace.path, isDirectory: true)
        var items: [WorkspaceInventoryItem] = []

        items.append(contentsOf: scan(kind: .skill, root: root, relativeDirectories: [".opencode/skills", ".claude/skills", ".agents/skills"]))
        items.append(contentsOf: scan(kind: .command, root: root, relativeDirectories: [".opencode/commands", ".agents/commands", "commands"]))
        items.append(contentsOf: scan(kind: .plugin, root: root, relativeDirectories: [".opencode/plugins", ".agents/plugins", "plugins"]))
        items.append(contentsOf: loadConfigItems(root: root))

        return items.sorted {
            if $0.kind.rawValue == $1.kind.rawValue {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return kindOrder($0.kind) < kindOrder($1.kind)
        }
    }

    private func scan(kind: WorkspaceInventoryKind, root: URL, relativeDirectories: [String]) -> [WorkspaceInventoryItem] {
        relativeDirectories.flatMap { relativeDirectory -> [WorkspaceInventoryItem] in
            let directory = root.appendingPathComponent(relativeDirectory, isDirectory: true)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return children.compactMap { child -> WorkspaceInventoryItem? in
                guard isInventoryEntry(child, kind: kind) else { return nil }
                let relativePath = relativePath(for: child, root: root)
                return WorkspaceInventoryItem(
                    kind: kind,
                    name: displayName(for: child),
                    path: relativePath,
                    detail: relativeDirectory
                )
            }
        }
    }

    private func isInventoryEntry(_ url: URL, kind: WorkspaceInventoryKind) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true { return true }
        return kind == .command && ["md", "txt"].contains(url.pathExtension.lowercased())
    }

    private func displayName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? url.lastPathComponent : name
    }

    private func loadConfigItems(root: URL) -> [WorkspaceInventoryItem] {
        let configURL = root.appendingPathComponent("opencode.json")
        guard let data = try? Data(contentsOf: configURL),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = value.objectValue else { return [] }

        var items: [WorkspaceInventoryItem] = []
        let mcpObject = object["mcp"]?.objectValue ?? object["mcpServers"]?.objectValue
        if let mcpObject {
            items.append(contentsOf: mcpObject.map { name, value in
                WorkspaceInventoryItem(
                    kind: .mcp,
                    name: name,
                    path: "opencode.json",
                    detail: value.displayValue
                )
            })
        }

        if let commandObject = object["command"]?.objectValue {
            items.append(contentsOf: commandObject.map { name, value in
                WorkspaceInventoryItem(
                    kind: .command,
                    name: name,
                    path: "opencode.json",
                    detail: value.displayValue
                )
            })
        }

        if let plugins = object["plugin"]?.arrayValue {
            items.append(contentsOf: plugins.enumerated().compactMap { index, value in
                guard let name = value.stringValue else { return nil }
                return WorkspaceInventoryItem(
                    kind: .plugin,
                    name: name,
                    path: "opencode.json",
                    detail: "plugin[\(index)]"
                )
            })
        }

        return items
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func kindOrder(_ kind: WorkspaceInventoryKind) -> Int {
        switch kind {
        case .skill: 0
        case .command: 1
        case .plugin: 2
        case .mcp: 3
        }
    }
}
