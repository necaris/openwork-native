import Foundation

struct WorkspaceStore {
    private let key = "recentWorkspaces"

    func loadRecentWorkspaces() -> [Workspace] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
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
        UserDefaults.standard.set(data, forKey: key)
    }
}
