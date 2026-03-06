import SwiftUI

struct SettingsView: View {
    @StateObject private var transcriber = Transcriber()
    @StateObject private var polisher = TextPolisher()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Murmur")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Speech Recognition") {
                VStack(alignment: .leading, spacing: 8) {
                    switch transcriber.modelState {
                    case .checking:
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        }
                    case .ready:
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("On-device recognition ready (Whisper base, multilingual)")
                        }
                    case .error(let msg):
                        HStack {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                            Text(msg).lineLimit(3)
                        }
                    default:
                        EmptyView()
                    }
                }
                .padding(8)
            }

            GroupBox("Text Polishing") {
                VStack(alignment: .leading, spacing: 8) {
                    switch polisher.state {
                    case .unavailable:
                        HStack {
                            Image(systemName: "minus.circle").foregroundColor(.orange)
                            Text("Polishing model not available")
                        }
                    case .ready:
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Qwen3 0.6B (on-device, Metal GPU)")
                        }
                    case .error(let msg):
                        HStack {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                            Text(msg).lineLimit(3)
                        }
                    }
                }
                .font(.system(size: 12))
                .padding(8)
            }

            GroupBox("Usage") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold **Fn** to start dictating")
                    Text("Release **Fn** to stop and paste")
                    Text("Right-click pill for menu")
                    Text("**Ctrl+Cmd+V** to paste from history")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(8)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 360, height: 320)
        .onAppear {
            transcriber.checkAndDownload()
            polisher.setup()
        }
    }
}
