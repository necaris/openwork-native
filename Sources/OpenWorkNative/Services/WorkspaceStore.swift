import Foundation

struct WorkspaceStore {
    private let key = "recentWorkspaces"
    private let lastSessionKey = "lastSessionByWorkspace"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRecentWorkspaces() -> [Workspace] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let stored = (try? JSONDecoder().decode([Workspace].self, from: data)) ?? []
        let manager = FileManager.default
        let valid = stored.filter { workspace in
            var isDirectory: ObjCBool = false
            return manager.fileExists(atPath: workspace.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        if valid.count != stored.count {
            saveRecentWorkspaces(valid)
        }
        return valid
    }

    func saveRecentWorkspaces(_ workspaces: [Workspace]) {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        defaults.set(data, forKey: key)
    }

    func loadLastSessionID(for workspace: Workspace) -> String? {
        lastSessionByWorkspace()[workspace.path]
    }

    func saveLastSessionID(_ sessionID: String?, for workspace: Workspace) {
        var sessions = lastSessionByWorkspace()
        sessions[workspace.path] = sessionID
        defaults.set(sessions, forKey: lastSessionKey)
    }

    private func lastSessionByWorkspace() -> [String: String] {
        defaults.dictionary(forKey: lastSessionKey) as? [String: String] ?? [:]
    }
}
