import Foundation

struct WorkspaceInventoryService: Sendable {
    var homeDirectory: URL
    var environment: [String: String]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    func loadInventory(in workspace: Workspace) async -> [WorkspaceInventoryItem] {
        let root = URL(fileURLWithPath: workspace.path, isDirectory: true)
        let home = homeDirectory
        var items: [WorkspaceInventoryItem] = []

        items.append(contentsOf: scan(kind: .skill, root: root, relativeDirectories: [".opencode/skills", ".claude/skills", ".agents/skills"]))
        items.append(contentsOf: scan(kind: .command, root: root, relativeDirectories: [".opencode/commands", ".agents/commands", "commands"]))
        items.append(contentsOf: scan(kind: .plugin, root: root, relativeDirectories: [".opencode/plugins", ".agents/plugins", "plugins"]))
        
        items.append(contentsOf: scanAbsolute(kind: .skill, root: home.appendingPathComponent(".agents/skills", isDirectory: true), label: "global"))
        items.append(contentsOf: scanAbsolute(kind: .command, root: home.appendingPathComponent(".agents/commands", isDirectory: true), label: "global"))
        items.append(contentsOf: scanAbsolute(kind: .plugin, root: home.appendingPathComponent(".agents/plugins", isDirectory: true), label: "global"))

        items.append(contentsOf: loadWorkspaceConfigItems(root: root))
        items.append(contentsOf: loadGlobalConfigItems(home: home))

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

    private func scanAbsolute(kind: WorkspaceInventoryKind, root: URL, label: String) -> [WorkspaceInventoryItem] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.compactMap { child -> WorkspaceInventoryItem? in
            guard isInventoryEntry(child, kind: kind) else { return nil }
            return WorkspaceInventoryItem(
                kind: kind,
                name: displayName(for: child),
                path: child.path,
                detail: label
            )
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

    private func loadWorkspaceConfigItems(root: URL) -> [WorkspaceInventoryItem] {
        configCandidates(root: root).flatMap { configURL in
            loadConfigItems(configURL: configURL, displayPath: relativePath(for: configURL, root: root), source: "workspace config")
        }
    }

    private func loadGlobalConfigItems(home: URL) -> [WorkspaceInventoryItem] {
        var configRoot: URL
        if let xdgConfigHome = environment["XDG_CONFIG_HOME"], !xdgConfigHome.isEmpty {
            configRoot = URL(fileURLWithPath: xdgConfigHome, isDirectory: true).appendingPathComponent("opencode", isDirectory: true)
        } else {
            configRoot = home.appendingPathComponent(".config/opencode", isDirectory: true)
        }

        return configCandidates(root: configRoot).flatMap { configURL in
            loadConfigItems(configURL: configURL, displayPath: configURL.path, source: "global config")
        }
    }

    private func configCandidates(root: URL) -> [URL] {
        [
            root.appendingPathComponent("opencode.json"),
            root.appendingPathComponent("opencode.jsonc"),
            root.appendingPathComponent(".opencode/opencode.json"),
            root.appendingPathComponent(".opencode/opencode.jsonc")
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func loadConfigItems(configURL: URL, displayPath: String, source: String) -> [WorkspaceInventoryItem] {
        guard let data = try? Data(contentsOf: configURL),
              let value = decodeConfig(data: data, pathExtension: configURL.pathExtension),
              let object = value.objectValue else { return [] }

        var items: [WorkspaceInventoryItem] = []
        let mcpObject = object["mcp"]?.objectValue ?? object["mcpServers"]?.objectValue
        if let mcpObject {
            items.append(contentsOf: mcpObject.map { name, value in
                WorkspaceInventoryItem(
                    kind: .mcp,
                    name: name,
                    path: displayPath,
                    detail: mcpDetail(name: name, value: value, source: source)
                )
            })
        }

        if let commandObject = object["command"]?.objectValue {
            items.append(contentsOf: commandObject.map { name, value in
                WorkspaceInventoryItem(
                    kind: .command,
                    name: name,
                    path: displayPath,
                    detail: "\(source): \(value.displayValue)"
                )
            })
        }

        if let plugins = object["plugin"]?.arrayValue {
            items.append(contentsOf: plugins.enumerated().compactMap { index, value in
                guard let name = value.stringValue else { return nil }
                return WorkspaceInventoryItem(
                    kind: .plugin,
                    name: name,
                    path: displayPath,
                    detail: "\(source): plugin[\(index)]"
                )
            })
        }

        return items
    }

    private func decodeConfig(data: Data, pathExtension: String) -> JSONValue? {
        let normalizedData: Data
        if pathExtension.lowercased() == "jsonc", let text = String(data: data, encoding: .utf8) {
            normalizedData = Data(stripJSONC(from: text).utf8)
        } else {
            normalizedData = data
        }
        return try? JSONDecoder().decode(JSONValue.self, from: normalizedData)
    }

    private func stripJSONC(from text: String) -> String {
        var output = ""
        var iterator = text.makeIterator()
        var inString = false
        var escaped = false
        var pendingSlash = false
        var inLineComment = false
        var inBlockComment = false
        var previousWasStar = false

        while let character = iterator.next() {
            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    output.append(character)
                }
                continue
            }

            if inBlockComment {
                if previousWasStar && character == "/" {
                    inBlockComment = false
                    previousWasStar = false
                } else {
                    previousWasStar = character == "*"
                    if character == "\n" { output.append(character) }
                }
                continue
            }

            if pendingSlash {
                if !inString && character == "/" {
                    pendingSlash = false
                    inLineComment = true
                    continue
                }
                if !inString && character == "*" {
                    pendingSlash = false
                    inBlockComment = true
                    previousWasStar = false
                    continue
                }
                output.append("/")
                pendingSlash = false
            }

            if character == "/" {
                pendingSlash = true
                continue
            }

            if character == "\"" && !escaped {
                inString.toggle()
            }

            output.append(character)
            escaped = inString && character == "\\" && !escaped
            if character != "\\" { escaped = false }
        }

        if pendingSlash { output.append("/") }
        return removeTrailingCommas(from: output)
    }

    private func removeTrailingCommas(from text: String) -> String {
        var characters = Array(text)
        var inString = false
        var escaped = false
        var index = characters.startIndex

        while index < characters.endIndex {
            let character = characters[index]
            if character == "\"" && !escaped {
                inString.toggle()
            }
            escaped = inString && character == "\\" && !escaped
            if character != "\\" { escaped = false }

            if !inString && character == "," {
                var next = characters.index(after: index)
                while next < characters.endIndex, characters[next].isWhitespace {
                    next = characters.index(after: next)
                }
                if next < characters.endIndex, characters[next] == "}" || characters[next] == "]" {
                    characters.remove(at: index)
                    continue
                }
            }
            index = characters.index(after: index)
        }

        return String(characters)
    }

    private func mcpDetail(name: String, value: JSONValue, source: String) -> String {
        guard let object = value.objectValue else {
            return "\(source): \(value.displayValue)"
        }

        var parts: [String] = [source]
        if let type = object["type"]?.stringValue, !type.isEmpty {
            parts.append("type: \(type)")
        }

        if let command = object["command"] {
            parts.append("command: \(commandDisplayValue(command, args: object["args"]))")
        } else if let url = object["url"]?.stringValue {
            parts.append("url: \(url)")
        } else if let transport = object["transport"]?.stringValue {
            parts.append("transport: \(transport)")
        } else if object.isEmpty {
            parts.append(name)
        }

        if let env = object["env"]?.objectValue, !env.isEmpty {
            parts.append("env: \(env.count) variable\(env.count == 1 ? "" : "s")")
        }

        return parts.joined(separator: " · ")
    }

    private func commandDisplayValue(_ command: JSONValue, args: JSONValue?) -> String {
        var commandParts: [String] = []
        if let commandString = command.stringValue {
            commandParts.append(commandString)
        } else if let commandArray = command.arrayValue {
            commandParts.append(contentsOf: commandArray.compactMap(\.stringValue))
        } else {
            commandParts.append(command.displayValue)
        }

        if let args = args?.arrayValue {
            commandParts.append(contentsOf: args.compactMap(\.stringValue))
        }

        return commandParts.joined(separator: " ")
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
