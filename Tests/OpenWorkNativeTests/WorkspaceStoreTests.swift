import Foundation
import Testing
@testable import OpenWorkNative

@Test func workspaceStorePrunesMissingRecentWorkspaces() throws {
    let defaults = try makeDefaults()
    let existing = try makeTemporaryDirectory()
    let missing = existing.appendingPathComponent("missing")
    let store = WorkspaceStore(defaults: defaults)

    store.saveRecentWorkspaces([
        Workspace(path: missing.path),
        Workspace(path: existing.path)
    ])

    let loaded = store.loadRecentWorkspaces()

    #expect(loaded == [Workspace(path: existing.path)])
}

@Test func workspaceStorePersistsLastSessionPerWorkspace() throws {
    let defaults = try makeDefaults()
    let store = WorkspaceStore(defaults: defaults)
    let first = Workspace(path: "/tmp/first")
    let second = Workspace(path: "/tmp/second")

    store.saveLastSessionID("ses_first", for: first)
    store.saveLastSessionID("ses_second", for: second)

    #expect(store.loadLastSessionID(for: first) == "ses_first")
    #expect(store.loadLastSessionID(for: second) == "ses_second")
}

@MainActor
@Test func appStateRestoresMostRecentValidWorkspace() throws {
    let defaults = try makeDefaults()
    let workspaceURL = try makeTemporaryDirectory()
    let workspace = Workspace(path: workspaceURL.path)
    let store = WorkspaceStore(defaults: defaults)
    store.saveRecentWorkspaces([workspace])
    store.saveLastSessionID("ses_recent", for: workspace)

    let state = AppState(workspaceStore: store)

    #expect(state.currentWorkspace == workspace)
    #expect(state.recentWorkspaces == [workspace])
    #expect(state.runtimeDetail == workspace.path || state.runtimeStatus == .failed)
}

@MainActor
@Test func appStatePersistsSelectedSessionForCurrentWorkspace() throws {
    let defaults = try makeDefaults()
    let workspaceURL = try makeTemporaryDirectory()
    let workspace = Workspace(path: workspaceURL.path)
    let store = WorkspaceStore(defaults: defaults)
    let state = AppState(workspaceStore: store)
    state.currentWorkspace = workspace

    state.selectedSessionID = "ses_selected"

    #expect(store.loadLastSessionID(for: workspace) == "ses_selected")
}

private func makeDefaults() throws -> UserDefaults {
    let suiteName = "OpenWorkNativeTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("OpenWorkNativeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
