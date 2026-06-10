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
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name)
                                            .font(.headline)
                                        Text(item.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        if !item.detail.isEmpty {
                                            Text(item.detail)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    
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
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Inventory")
    }
}
