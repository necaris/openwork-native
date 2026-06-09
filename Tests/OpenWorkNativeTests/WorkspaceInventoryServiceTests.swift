import Foundation
import Testing
@testable import OpenWorkNative

@Test func inventoryServiceDetectsSkillsCommandsPluginsAndMCP() async throws {
    let root = try makeTemporaryDirectory()
    try makeDirectory(root.appendingPathComponent(".opencode/skills/ship-it", isDirectory: true))
    try makeDirectory(root.appendingPathComponent(".opencode/commands", isDirectory: true))
    try "Run tests".write(
        to: root.appendingPathComponent(".opencode/commands/test.md"),
        atomically: true,
        encoding: .utf8
    )
    try makeDirectory(root.appendingPathComponent(".opencode/plugins/local-plugin", isDirectory: true))
    try #"{"mcp":{"filesystem":{"command":"node","args":["server.js"]}},"command":{"review":{"template":"Review the diff"}},"plugin":["opencode-wakatime"]}"#.write(
        to: root.appendingPathComponent("opencode.json"),
        atomically: true,
        encoding: .utf8
    )

    let inventory = await WorkspaceInventoryService().loadInventory(in: Workspace(path: root.path))

    #expect(inventory.contains(WorkspaceInventoryItem(kind: .skill, name: "ship-it", path: ".opencode/skills/ship-it", detail: ".opencode/skills")))
    #expect(inventory.contains(WorkspaceInventoryItem(kind: .command, name: "test", path: ".opencode/commands/test.md", detail: ".opencode/commands")))
    #expect(inventory.contains(WorkspaceInventoryItem(kind: .plugin, name: "local-plugin", path: ".opencode/plugins/local-plugin", detail: ".opencode/plugins")))
    #expect(inventory.contains { item in
        item.kind == .mcp
            && item.name == "filesystem"
            && item.path == "opencode.json"
            && item.detail.contains("command: node")
    })
    #expect(inventory.contains { item in
        item.kind == .command
            && item.name == "review"
            && item.path == "opencode.json"
            && item.slashCommand == "/review"
    })
    #expect(inventory.contains(WorkspaceInventoryItem(kind: .plugin, name: "opencode-wakatime", path: "opencode.json", detail: "plugin[0]")))
}

@Test func inventoryCommandAndSkillItemsExposeSlashCommands() {
    let command = WorkspaceInventoryItem(kind: .command, name: "review", path: ".agents/commands/review.md", detail: ".agents/commands")
    let skill = WorkspaceInventoryItem(kind: .skill, name: "review", path: ".agents/skills/review", detail: ".agents/skills")
    let plugin = WorkspaceInventoryItem(kind: .plugin, name: "review", path: ".opencode/plugins/review", detail: ".opencode/plugins")

    #expect(command.slashCommand == "/review")
    #expect(skill.slashCommand == "/review")
    #expect(plugin.slashCommand == nil)
}

private func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("OpenWorkNativeInventoryTests-\(UUID().uuidString)", isDirectory: true)
    try makeDirectory(url)
    return url
}

private func makeDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}
