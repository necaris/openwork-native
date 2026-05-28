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

        }
        .navigationTitle("Activity")
    }
}
