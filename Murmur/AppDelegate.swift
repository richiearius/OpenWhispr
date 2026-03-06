import AppKit
import SwiftUI
import Combine
class AppDelegate: NSObject, NSApplicationDelegate {
    private var pillWindow: PillWindow!
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let history = HistoryStore()
    private let polisher = TextPolisher()
    private var fnMonitor: Any?
    private var localFnMonitor: Any?
    private var hotkeyEventTap: CFMachPort?
    private var isRecording = false
    private var recordingStartTime: Date?
    private var levelCancellable: AnyCancellable?
    private var modelCancellable: AnyCancellable?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Prompt for Accessibility permission if not granted
        requestAccessibilityIfNeeded()

        pillWindow = PillWindow()
        pillWindow.show()

        // Auto-download model
        modelCancellable = transcriber.$modelState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .checking:
                    break
                case .notDownloaded, .downloading:
                    if case .downloading(let p) = state {
                        self.pillWindow.setState(.downloading(progress: p))
                    }
                case .ready:
                    self.pillWindow.setState(.idle)
                case .error(let msg):
                    print("Model error: \(msg)")
                    self.pillWindow.setState(.idle)
                }
            }

        transcriber.checkAndDownload()
        polisher.setup()

        // Pipe audio levels to pill
        levelCancellable = recorder.levelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.pillWindow.pushLevel(level)
            }

        // Monitor Fn key
        fnMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }
        localFnMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }

        // Ctrl+Cmd+V — paste last transcription (CGEvent tap, works system-wide with Accessibility)
        setupHotkeyTap()

        // Right-click pill for menu
        pillWindow.onRightClick = { [weak self] in
            self?.showContextMenu()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "History", action: #selector(showHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Murmur", action: #selector(quit), keyEquivalent: ""))

        for item in menu.items {
            item.target = self
        }

        let location = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: location.x, y: location.y), in: nil)
    }

    private func handleFlags(_ event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)

        if fnPressed && !isRecording && transcriber.isModelReady {
            startRecording()
        } else if !fnPressed && isRecording {
            stopRecording()
        }
    }

    private func startRecording(locked: Bool = false) {
        isRecording = true
        recordingStartTime = Date()
        recorder.start()
        pillWindow.setState(locked ? .recordingLocked : .recording)
    }

    private func stopRecording() {
        isRecording = false
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        pillWindow.setState(.processing)

        recorder.stop { [weak self] audioURL in
            guard let self, let url = audioURL else {
                self?.pillWindow.setState(.idle)
                return
            }
            Task {
                var text = await self.transcriber.transcribe(fileURL: url)
                try? FileManager.default.removeItem(at: url)

                if let raw = text, !raw.isEmpty, self.polisher.isReady {
                    await MainActor.run { self.pillWindow.setState(.polishing) }
                    text = await self.polisher.polish(raw)
                }

                await MainActor.run {
                    if let text, !text.isEmpty {
                        self.history.add(text: text, durationSeconds: duration)
                        self.pasteText(text)
                    }
                    self.pillWindow.setState(.idle)
                }
            }
        }
    }

    private func setupHotkeyTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,  // listen only — don't swallow events
            eventsOfInterest: mask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                // Ctrl+Cmd+V (keyCode 9)
                if keyCode == 0x09 && flags.contains(.maskCommand) && flags.contains(.maskControl) {
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                    DispatchQueue.main.async { delegate.pasteLastTranscription() }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            print("[Hotkey] Failed to create CGEvent tap — check Accessibility permission")
            return
        }

        hotkeyEventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[Hotkey] CGEvent tap installed for Ctrl+Cmd+V")
    }

    private func pasteLastTranscription() {
        guard let lastEntry = history.entries.first else {
            pillWindow.setState(.error("No transcriptions yet"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.pillWindow.setState(.idle)
            }
            return
        }
        pasteText(lastEntry.text)
    }

    private func requestAccessibilityIfNeeded() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        if !trusted {
            print("Accessibility permission not granted — auto-paste won't work until granted.")
        }
    }

    private func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Check if we can auto-paste
        let trusted = AXIsProcessTrusted()
        let hasFocus = trusted && frontmostAppHasFocusedElement()

        guard trusted && hasFocus else {
            // Can't auto-paste — text is on clipboard, tell the user
            pillWindow.setState(.error("Copied — press Cmd+V to paste"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.pillWindow.setState(.idle)
            }
            return
        }

        // Auto-paste via simulated Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

            guard let keyDown, let keyUp else { return }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)

            // Restore clipboard after paste completes
            if let previous = previousContents {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    /// Relaxed check — just see if the frontmost app has ANY focused element
    private func frontmostAppHasFocusedElement() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        return result == .success && focusedElement != nil
    }

    @objc private func showHistory() {
        if let existing = historyWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = HistoryView(store: history)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Murmur — History"
        window.center()
        window.contentView = NSHostingView(rootView: historyView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }

    @objc private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Murmur — Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

}
