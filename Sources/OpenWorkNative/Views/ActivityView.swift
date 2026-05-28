import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section("Permissions") {
                if appState.permissionRequests.isEmpty {
                    Text("No pending requests")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.permissionRequests) { request in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(request.action)
                                .font(.headline)
                            Text(request.target)
                                .font(.caption)
                                .textSelection(.enabled)
                            Text(request.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Session: \(request.sessionTitle)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Allow Once") {
                                    appState.resolvePermission(request, decision: .once)
                                }
                                Button("Deny") {
                                    appState.resolvePermission(request, decision: .reject)
                                }
                                Button("Always Allow") {
                                    appState.resolvePermission(request, decision: .always)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Activity") {
                ForEach(appState.activity) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title)
                                .font(.headline)
                            Spacer()
                            Text(item.state)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Changed Files") {
                if appState.changedFiles.isEmpty {
                    Text("No changed files detected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.changedFiles) { file in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(file.path)
                                Text(file.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Open") {
                                    appState.openInExternalEditor(file)
                                }
                                Button("Reveal in Finder") {
                                    appState.revealInFinder(file)
                                }
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(file.path, forType: .string)
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }

            Section("Inventory") {
                if appState.inventory.isEmpty {
                    Text("No skills, commands, plugins, or MCP entries detected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(WorkspaceInventoryKind.allCases, id: \.rawValue) { kind in
                        let items = appState.inventory.filter { $0.kind == kind }
                        if !items.isEmpty {
                            DisclosureGroup("\(kind.rawValue) (\(items.count))") {
                                ForEach(items) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name)
                                                .font(.headline)
                                            Text(item.path)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .textSelection(.enabled)
                                            if !item.detail.isEmpty {
                                                Text(item.detail)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                        Spacer()
                                        Menu {
                                            if let command = item.slashCommand {
                                                Button("Copy Slash Command") {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(command, forType: .string)
                                                }
                                            }
                                            Button("Reveal in Finder") {
                                                appState.revealInventoryItem(item)
                                            }
                                            Button("Copy Path") {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(item.path, forType: .string)
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                        }
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Activity")
    }
}
