import AppKit
import SwiftUI
import Combine

enum PillState: Equatable {
    case idle
    case downloading(progress: Double)
    case recording
    case recordingLocked
    case recordingSummarize
    case recordingLockedSummarize
    case recordingQuestion
    case processing
    case polishing
    case error(String)
    case learned(String)
    case answer(String)
}

class PillWindow: NSPanel {
    private let pillState = PillStateModel()
    private var hostingView: NSHostingView<PillView>!
    var onRightClick: (() -> Void)?
    var onIdleClick: (() -> Void)?

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

        // Enable mouse tracking for hover detection
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        hostingView.addTrackingArea(trackingArea)

        updateFrame()
    }

    override func mouseEntered(with event: NSEvent) {
        pillState.isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        pillState.isHovered = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func mouseDown(with event: NSEvent) {
        // Click on answer pill copies to clipboard
        if case .answer(let text) = pillState.state {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            pillState.state = .learned("Copied to clipboard")
            updateFrame()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.pillState.state = .idle
                self?.updateFrame()
            }
            return
        }
        // Click idle pill to start locked recording
        if case .idle = pillState.state {
            onIdleClick?()
            return
        }
        // Swallow — don't steal focus
    }

    func show() {
        orderFrontRegardless()
    }

    var currentState: PillState { pillState.state }
    var isHovered: Bool { pillState.isHovered }

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
        case .recording, .recordingLocked, .recordingSummarize, .recordingLockedSummarize, .recordingQuestion:
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
        case .learned:
            size = NSSize(width: 260, height: 32)
            hasShadow = true
        case .answer:
            size = NSSize(width: 360, height: 72)
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
    @Published var isHovered: Bool = false
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
            case .recordingSummarize:
                recordingSummarizePill
            case .recordingQuestion:
                recordingQuestionPill
            case .recordingLockedSummarize:
                recordingLockedSummarizePill
            case .processing:
                processingPill
            case .polishing:
                polishingPill
            case .error(let msg):
                errorPill(message: msg)
            case .learned(let msg):
                learnedPill(message: msg)
            case .answer(let msg):
                answerPill(message: msg)
            }
        }
    }

    // Tiny translucent bar when idle — highlights on hover
    private var idlePill: some View {
        Capsule()
            .fill(.white.opacity(state.isHovered ? 0.4 : 0.15))
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(state.isHovered ? 0.3 : 0), lineWidth: 1)
            )
            .frame(width: 32, height: 5)
            .padding(.top, 1.5)
            .animation(.easeInOut(duration: 0.15), value: state.isHovered)
            .onHover { hovering in
                state.isHovered = hovering
            }
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

    private var recordingSummarizePill: some View {
        HStack(spacing: 3) {
            Image(systemName: "text.redaction")
                .font(.system(size: 8))
                .foregroundColor(.purple)
                .padding(.trailing, 4)

            ForEach(0..<state.levels.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.purple.opacity(0.6))
                    .frame(width: 3, height: barHeight(for: state.levels[i]))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 200, height: 40)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var recordingQuestionPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 8))
                .foregroundColor(.blue)
                .padding(.trailing, 4)

            ForEach(0..<state.levels.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.blue.opacity(0.6))
                    .frame(width: 3, height: barHeight(for: state.levels[i]))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 200, height: 40)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var recordingLockedSummarizePill: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8))
                .foregroundColor(.purple)
                .padding(.trailing, 4)

            ForEach(0..<state.levels.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.purple.opacity(0.6))
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

    private func learnedPill(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(width: 260, height: 32)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func answerPill(message: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundColor(.blue)
                Text("Answer")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("click to copy")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func barHeight(for level: Float) -> CGFloat {
        let min: CGFloat = 3
        let max: CGFloat = 22
        return min + CGFloat(level) * (max - min)
    }
}
