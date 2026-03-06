import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .history: return "clock"
        case .settings: return "gear"
        }
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .frame(width: 16)
            Text(item.rawValue)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
        }
        .foregroundColor(isSelected ? Theme.text : isHovered ? Theme.text : Theme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.sidebarSel : isHovered ? Theme.sidebarSel.opacity(0.5) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .onTapGesture { action() }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SidebarItem.allCases) { item in
                SidebarRow(item: item, isSelected: selection == item) {
                    selection = item
                }
            }
            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
        .frame(width: 140)
    }
}
