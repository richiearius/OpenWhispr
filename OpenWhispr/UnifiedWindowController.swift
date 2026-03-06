import AppKit
import SwiftUI

class UnifiedWindowController {
    private var panel: NSPanel?
    private let historyStore: HistoryStore

    init(historyStore: HistoryStore) {
        self.historyStore = historyStore
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show(onboarding: Bool = false, onOnboardingComplete: (() -> Void)? = nil) {
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        let view = MainAppView(
            historyStore: historyStore,
            onboardingMode: onboarding,
            onOnboardingComplete: onOnboardingComplete
        )
        panel.contentView = NSHostingView(rootView: view)

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showNormal() {
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        let view = MainAppView(historyStore: historyStore)
        panel.contentView = NSHostingView(rootView: view)

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isFloatingPanel = true
        p.level = .floating
        p.becomesKeyOnlyIfNeeded = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.appearance = NSAppearance(named: .aqua)

        panel = p
    }
}
