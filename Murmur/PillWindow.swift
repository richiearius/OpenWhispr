import AppKit
import SwiftUI
import Combine

enum PillState: Equatable {
    case idle
    case downloading(progress: Double)
    case recording
    case recordingLocked
    case processing
    case polishing
    case error(String)
}

class PillWindow: NSPanel {
    private let pillState = PillStateModel()
    private var hostingView: NSHostingView<PillView>!
    var onRightClick: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 32, height: 8),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Allow right-click in idle, block other mouse events
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = false

        hostingView = NSHostingView(rootView: PillView(state: pillState))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        contentView = hostingView

        updateFrame()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func mouseDown(with event: NSEvent) {
        // Swallow — don't steal focus
    }

    func show() {
        orderFrontRegardless()
    }

    func setState(_ state: PillState) {
        DispatchQueue.main.async {
            self.pillState.state = state
            self.updateFrame()
        }
    }

    func pushLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.pillState.pushLevel(level)
        }
    }

    private func updateFrame() {
        guard let screen = NSScreen.main else { return }

        let size: NSSize
        switch pillState.state {
        case .idle:
            size = NSSize(width: 32, height: 8)
            hasShadow = false
        case .downloading:
            size = NSSize(width: 220, height: 32)
            hasShadow = true
        case .recording, .recordingLocked:
            size = NSSize(width: 200, height: 40)
            hasShadow = true
        case .processing:
            size = NSSize(width: 160, height: 32)
            hasShadow = true
        case .polishing:
            size = NSSize(width: 140, height: 32)
            hasShadow = true
        case .error:
            size = NSSize(width: 280, height: 32)
            hasShadow = true
        }

        let x = (screen.frame.width - size.width) / 2
        let y: CGFloat = 12

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }

        hostingView.frame = NSRect(origin: .zero, size: size)
    }
}

class PillStateModel: ObservableObject {
    @Published var state: PillState = .idle
    @Published var levels: [Float] = Array(repeating: 0, count: 24)

    func pushLevel(_ level: Float) {
        levels.append(level)
        if levels.count > 24 {
            levels.removeFirst()
        }
    }
}

// MARK: - Views

struct PillView: View {
    @ObservedObject var state: PillStateModel

    var body: some View {
        Group {
            switch state.state {
            case .idle:
                idlePill
            case .downloading(let progress):
                downloadingPill(progress: progress)
            case .recording:
                recordingPill
            case .recordingLocked:
                recordingLockedPill
            case .processing:
                processingPill
            case .polishing:
                polishingPill
            case .error(let msg):
                errorPill(message: msg)
            }
        }
    }

    // Tiny translucent bar when idle
    private var idlePill: some View {
        Capsule()
            .fill(.white.opacity(0.15))
            .frame(width: 32, height: 5)
            .padding(.top, 1.5)
    }

    private func downloadingPill(progress: Double) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text("Downloading model… \(Int(progress * 100))%")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .frame(width: 220, height: 32)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var recordingPill: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
                .padding(.trailing, 4)

            ForEach(0..<state.levels.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.8))
                    .frame(width: 3, height: barHeight(for: state.levels[i]))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 200, height: 40)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var recordingLockedPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8))
                .foregroundColor(.orange)
                .padding(.trailing, 4)

            ForEach(0..<state.levels.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.8))
                    .frame(width: 3, height: barHeight(for: state.levels[i]))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 200, height: 40)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var processingPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text("Transcribing…")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .frame(width: 160, height: 32)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var polishingPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
            Text("Polishing…")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .frame(width: 140, height: 32)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func errorPill(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 32)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func barHeight(for level: Float) -> CGFloat {
        let min: CGFloat = 3
        let max: CGFloat = 22
        return min + CGFloat(level) * (max - min)
    }
}
