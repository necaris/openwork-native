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
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(request.action)
                                    .font(.headline)
                            }
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
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                Button("Deny") {
                                    appState.resolvePermission(request, decision: .reject)
                                }
                                Button("Always Allow") {
                                    appState.resolvePermission(request, decision: .always)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.orange, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Activity") {
                ForEach(appState.activity) { item in
                    ActivityRow(item: item)
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

private struct ActivityRow: View {
    @EnvironmentObject private var appState: AppState
    let item: ActivityItem
    @State private var isExpanded = false
    @ScaledMetric private var iconWidth: CGFloat = 14

    var body: some View {
        if item.kind == .tool {
            toolRow
        } else {
            genericRow
        }
    }

    // Tool rows mirror a tool-call-only assistant message in the transcript: slim,
    // no inline subtitle (it's available as a hover tooltip instead), and clicking
    // jumps to and expands the originating message rather than expanding in place.
    private var toolRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: iconWidth)
            Text(item.title)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(item.state)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help(item.detail)
        .onTapGesture {
            guard let messageID = item.messageID else { return }
            appState.revealMessage(messageID)
        }
    }

    private var genericRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: item.kind.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: iconWidth)
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(item.state)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard isCollapsible else { return }
                withAnimation { isExpanded.toggle() }
            }

            if isCollapsible {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                } label: {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }

    private var isCollapsible: Bool {
        item.detail.count > 180 || item.detail.contains("\n")
    }

    private var summary: String {
        let firstLine = item.detail.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.detail
        guard firstLine.count > 120 else { return firstLine }
        return "\(firstLine.prefix(120))..."
    }
}

private extension ActivityItem.Kind {
    var symbolName: String {
        switch self {
        case .step: "checklist"
        case .tool: "wrench.and.screwdriver"
        case .todo: "checkmark.square"
        case .file: "doc.text"
        case .runtime: "cpu"
        }
    }
}
