import SwiftUI

struct MainAppView: View {
    @ObservedObject var historyStore: HistoryStore
    @State private var selection: SidebarItem = .history
    var onboardingMode: Bool = false
    var onOnboardingComplete: (() -> Void)?

    var body: some View {
        if onboardingMode {
            OnboardingView(onComplete: onOnboardingComplete)
                .background(Theme.bg)
                .preferredColorScheme(.light)
        } else {
            HStack(spacing: 0) {
                SidebarView(selection: $selection)
                    .background(Theme.sidebarBg)

                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1)

                Group {
                    switch selection {
                    case .history:
                        HistoryView(store: historyStore)
                    case .settings:
                        ScrollView {
                            SettingsContentView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
            }
            .preferredColorScheme(.light)
        }
    }
}
