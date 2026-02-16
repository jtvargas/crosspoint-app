import SwiftUI

// MARK: - Filter

/// Controls which log entries are visible.
private enum LogFilter: String, CaseIterable {
    case all
    case errors
    case queue
    case device
    case conversion
    case rss

    var displayName: String {
        switch self {
        case .all:        return loc(.debugFilterAll)
        case .errors:     return loc(.debugFilterErrors)
        case .queue:      return loc(.debugFilterQueue)
        case .device:     return loc(.debugFilterDevice)
        case .conversion: return loc(.debugFilterConversion)
        case .rss:        return loc(.debugFilterRSS)
        }
    }

    /// Whether a log entry matches this filter.
    func matches(_ entry: DebugLogger.Entry) -> Bool {
        switch self {
        case .all:        return true
        case .errors:     return entry.level == .error
        case .queue:      return entry.category == .queue
        case .device:     return entry.category == .device
        case .conversion: return entry.category == .conversion
        case .rss:        return entry.category == .rss
        }
    }
}

// MARK: - DebugLogView

/// Displays persistent debug logs with category filtering, copy, share, and clear actions.
struct DebugLogView: View {
    @State private var selectedFilter: LogFilter = .all
    @State private var showClearConfirm = false
    @State private var showShareSheet = false

    private var logger: DebugLogger { DebugLogger.shared }

    private var filteredEntries: [DebugLogger.Entry] {
        logger.entries.filter { selectedFilter.matches($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            logList
        }
        .navigationTitle(loc(.debugLogs))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyAllToClipboard()
                    } label: {
                        Label(loc(.debugLogsCopyAll), systemImage: "doc.on.doc")
                    }

                    Button {
                        showShareSheet = true
                    } label: {
                        Label(loc(.debugLogsShare), systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label(loc(.debugLogsClear), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(logger.entries.isEmpty)
            }
        }
        .alert(loc(.debugLogsClearTitle), isPresented: $showClearConfirm) {
            Button(loc(.debugLogsClear), role: .destructive) {
                logger.clearAll()
            }
            Button(loc(.cancel), role: .cancel) {}
        } message: {
            Text(loc(.debugLogsClearMessage))
        }
        .sheet(isPresented: $showShareSheet) {
            let text = logger.exportAsText()
            #if os(iOS)
            DebugLogShareSheet(text: text)
            #else
            DebugLogShareView(text: text)
            #endif
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LogFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.displayName)
                            .font(.subheadline.weight(selectedFilter == filter ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedFilter == filter
                                    ? AppColor.accent.opacity(0.15)
                                    : Color.secondary.opacity(0.08),
                                in: .capsule
                            )
                            .foregroundStyle(
                                selectedFilter == filter ? AppColor.accent : .secondary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Log List

    private var logList: some View {
        Group {
            if filteredEntries.isEmpty {
                ContentUnavailableView {
                    Label(loc(.debugLogsEmpty), systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(loc(.debugLogsEmptyDescription))
                }
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        logEntryRow(entry)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Log Entry Row

    private func logEntryRow(_ entry: DebugLogger.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: entry.level.icon)
                    .font(.caption2)
                    .foregroundStyle(colorForLevel(entry.level))

                Text(entry.category.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1), in: .capsule)

                Spacer()

                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                copyEntryToClipboard(entry)
            } label: {
                Label(loc(.copyURL), systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Helpers

    private func colorForLevel(_ level: DebugLogger.Level) -> Color {
        switch level {
        case .info:    return AppColor.accent
        case .warning: return AppColor.warning
        case .error:   return AppColor.error
        }
    }

    private func copyAllToClipboard() {
        let text = logger.exportAsText()
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func copyEntryToClipboard(_ entry: DebugLogger.Entry) {
        let text = entry.fileLine
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Share Helpers (iOS)

#if os(iOS)
/// UIActivityViewController wrapper for sharing log text as a .txt file.
private struct DebugLogShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crossx-debug-log.txt")
        try? text.data(using: .utf8)?.write(to: tempURL)
        return UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
#endif

// MARK: - Share Helpers (macOS)

#if os(macOS)
/// NSSharingServicePicker wrapper for sharing log text as a .txt file.
private struct DebugLogShareView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("crossx-debug-log.txt")
            try? text.data(using: .utf8)?.write(to: tempURL)
            let picker = NSSharingServicePicker(items: [tempURL])
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
