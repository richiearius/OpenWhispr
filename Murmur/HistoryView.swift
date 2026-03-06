import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var search = ""

    private var filtered: [DictationEntry] {
        if search.isEmpty { return store.entries }
        return store.entries.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search dictations…", text: $search)
                    .textFieldStyle(.plain)

                if !store.entries.isEmpty {
                    Button("Clear All") {
                        store.clear()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .font(.caption)
                }
            }
            .padding(12)
            .background(.bar)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "mic.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(store.entries.isEmpty ? "No dictations yet" : "No results")
                        .foregroundColor(.secondary)
                    Text("Hold Fn to start dictating")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filtered) { entry in
                            HistoryRow(entry: entry, onCopy: {
                                copyToClipboard(entry.text)
                            }, onDelete: {
                                store.delete(entry)
                            })
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Quick Paste Popup (Ctrl+Cmd+V)

struct HistoryPopupView: View {
    @ObservedObject var store: HistoryStore
    let onSelect: (String) -> Void
    @State private var search = ""

    private var filtered: [DictationEntry] {
        let list = Array(store.entries.prefix(20))
        if search.isEmpty { return list }
        return list.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(10)

            Divider()

            if filtered.isEmpty {
                VStack {
                    Spacer()
                    Text("No history")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filtered) { entry in
                            Button {
                                onSelect(entry.text)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.text)
                                        .font(.system(size: 12))
                                        .lineLimit(2)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(entry.date.formatted(.relative(presentation: .named)))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .background(Color.primary.opacity(0.001))
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 400)
    }
}

struct HistoryRow: View {
    let entry: DictationEntry
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text(entry.date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text(formatDuration(entry.durationSeconds))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if hovering {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Copy")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { hovering = $0 }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
    }
}
