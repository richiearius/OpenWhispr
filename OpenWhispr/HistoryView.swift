import SwiftUI
import AppKit

// MARK: - Date grouping

private struct DateGroup: Identifiable {
    let id: String // label
    let label: String
    let entries: [DictationEntry]
}

private func groupByDate(_ entries: [DictationEntry]) -> [DateGroup] {
    let calendar = Calendar.current
    var groups: [(key: String, label: String, entries: [DictationEntry])] = []
    var currentKey = ""
    var currentEntries: [DictationEntry] = []
    var currentLabel = ""

    for entry in entries {
        let label = dateLabel(for: entry.date, calendar: calendar)
        if label != currentKey {
            if !currentEntries.isEmpty {
                groups.append((key: currentKey, label: currentLabel, entries: currentEntries))
            }
            currentKey = label
            currentLabel = label
            currentEntries = [entry]
        } else {
            currentEntries.append(entry)
        }
    }
    if !currentEntries.isEmpty {
        groups.append((key: currentKey, label: currentLabel, entries: currentEntries))
    }

    return groups.map { DateGroup(id: $0.key, label: $0.label, entries: $0.entries) }
}

private func dateLabel(for date: Date, calendar: Calendar) -> String {
    if calendar.isDateInToday(date) { return "TODAY" }
    if calendar.isDateInYesterday(date) { return "YESTERDAY" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date).uppercased()
}

private func timeLabel(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "hh:mm a"
    return formatter.string(from: date)
}

// MARK: - History View

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
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textSecondary)
                    .font(.system(size: 13))
                TextField("Search dictations…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text)

                if !store.entries.isEmpty {
                    Button(action: { store.clear() }) {
                        Text("Clear All")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Rectangle().fill(Theme.divider).frame(height: 1)

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "mic.slash")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textSecondary.opacity(0.4))
                    Text(store.entries.isEmpty ? "No dictations yet" : "No results")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                    Text("Hold Fn to start dictating")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupByDate(filtered)) { group in
                            // Date header
                            Text(group.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                                .tracking(0.5)
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .padding(.bottom, 8)

                            // Table rows
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                HistoryRow(entry: entry, onCopy: {
                                    copyToClipboard(entry.text)
                                }, onDelete: {
                                    store.delete(entry)
                                })

                                if index < group.entries.count - 1 {
                                    Rectangle()
                                        .fill(Theme.divider)
                                        .frame(height: 1)
                                        .padding(.leading, 100)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Theme.bg)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - History Row (table style)

struct HistoryRow: View {
    let entry: DictationEntry
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Time column
            Text(timeLabel(for: entry.date))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 80, alignment: .leading)
                .padding(.leading, 20)

            // Text column
            Text(entry.text)
                .font(.system(size: 13))
                .foregroundColor(Theme.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Hover actions
            if hovering {
                HStack(spacing: 6) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .padding(.trailing, 20)
            }
        }
        .padding(.vertical, 10)
        .background(hovering ? Theme.sidebarSel.opacity(0.3) : Color.clear)
        .onHover { hovering = $0 }
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
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textSecondary)
                    .font(.system(size: 13))
                TextField("Search…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(Theme.divider).frame(height: 1)

            if filtered.isEmpty {
                VStack {
                    Spacer()
                    Text("No history")
                        .foregroundColor(Theme.textSecondary)
                        .font(.system(size: 13))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                onSelect(entry.text)
                            } label: {
                                HStack(alignment: .top, spacing: 0) {
                                    Text(timeLabel(for: entry.date))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(Theme.textSecondary)
                                        .frame(width: 70, alignment: .leading)

                                    Text(entry.text)
                                        .font(.system(size: 12))
                                        .lineLimit(2)
                                        .foregroundColor(Theme.text)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)

                            if index < filtered.count - 1 {
                                Rectangle()
                                    .fill(Theme.divider)
                                    .frame(height: 1)
                                    .padding(.leading, 84)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 360, height: 400)
        .background(Theme.bg)
        .preferredColorScheme(.light)
    }
}
