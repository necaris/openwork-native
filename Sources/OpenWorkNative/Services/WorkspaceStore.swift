import Foundation

struct WorkspaceStore {
    private let key = "recentWorkspaces"

    func loadRecentWorkspaces() -> [Workspace] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Workspace].self, from: data)) ?? []
    }

    func saveRecentWorkspaces(_ workspaces: [Workspace]) {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
