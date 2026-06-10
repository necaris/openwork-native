import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        List {
            if appState.inventory.isEmpty {
                Text("No skills, commands, plugins, or MCP entries detected")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(WorkspaceInventoryKind.allCases, id: \.rawValue) { kind in
                    let items = appState.inventory.filter { $0.kind == kind }
                    if !items.isEmpty {
                        Section("\(kind.rawValue) (\(items.count))") {
                            ForEach(items) { item in
                                InventoryRow(item: item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Inventory")
    }
}

private struct InventoryRow: View {
    @EnvironmentObject private var appState: AppState
    let item: WorkspaceInventoryItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.headline)
                    if let status = item.status {
                        InventoryStatusBadge(status: status, detail: item.statusDetail)
                    }
                }
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.slashCommand != nil || !item.path.isEmpty {
                Menu {
                    if let command = item.slashCommand {
                        Button("Copy Slash Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                    }
                    if !item.path.isEmpty {
                        Button("Reveal in Finder") {
                            appState.revealInventoryItem(item)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .help(item.path.isEmpty ? item.name : item.path)
    }
}

private struct InventoryStatusBadge: View {
    let status: String
    let detail: String?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .help(detail ?? status)
    }

    private var color: Color {
        switch status {
        case "connected": .green
        case "failed", "error": .red
        case "disabled": .gray
        default: .orange
        }
    }
}
