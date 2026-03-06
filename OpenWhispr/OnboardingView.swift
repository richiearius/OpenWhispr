import SwiftUI

struct OnboardingView: View {
    @AppStorage("baseTone") private var baseTone = "neutral"
    @AppStorage("userStyleDescription") private var styleDescription = ""
    @AppStorage("alwaysEnglish") private var alwaysEnglish = false
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

    var onComplete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to OpenWhispr")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("Set up your writing style. You can change these anytime in Settings.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 28)

            // Base Tone
            Text("BASE TONE")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .tracking(0.5)
                .padding(.horizontal, 24)

            Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("How should your dictation sound by default?")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)

                Picker("", selection: $baseTone) {
                    Text("Casual").tag("casual")
                    Text("Neutral").tag("neutral")
                    Text("Professional").tag("professional")
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Spacer().frame(height: 16)

            // Style Description
            Text("STYLE DESCRIPTION")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .tracking(0.5)
                .padding(.horizontal, 24)

            Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("Describe your writing style in a few words.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)

                TextField("e.g., Clean and direct, like Linear docs. No fluff.", text: $styleDescription)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text)
                    .padding(8)
                    .background(Theme.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Spacer().frame(height: 16)

            // Language
            Text("LANGUAGE")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .tracking(0.5)
                .padding(.horizontal, 24)

            Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("OpenWhispr transcribes any language automatically via Whisper.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)

                HStack {
                    Text("Always output in English")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Toggle("", isOn: $alwaysEnglish)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if alwaysEnglish {
                    Text("Non-English dictation will be translated to English before pasting.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Spacer()

            HStack {
                Spacer()
                Button("Get Started") {
                    onboardingCompleted = true
                    onComplete?()
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 440, height: 500)
        .background(Theme.bg)
        .preferredColorScheme(.light)
    }
}
