import SwiftUI

struct WizardSheet: View {
    @Environment(AppState.self) private var state
    var wsManager: WebSocketManager?

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geo in
                    let pct = state.wizardSteps.isEmpty ? 0.0
                        : CGFloat(state.wizardCurrentStep + 1) / CGFloat(state.wizardSteps.count)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color(.systemGray5))
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * pct)
                            .animation(.easeInOut(duration: 0.3), value: pct)
                    }
                }
                .frame(height: 4)

                if !state.wizardSteps.isEmpty {
                    let step = state.wizardSteps[state.wizardCurrentStep]
                    let total = state.wizardSteps.count
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Step badge
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 36, height: 36)
                                    Text("\(step.number)")
                                        .font(.headline.bold())
                                        .foregroundColor(.white)
                                }
                                Text("Step \(step.number) of \(total)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            // Instruction
                            Text(step.instruction)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)

                            // Tools needed
                            if !step.toolsNeeded.isEmpty {
                                HStack {
                                    Image(systemName: "wrench")
                                        .foregroundColor(.secondary)
                                    Text(step.toolsNeeded.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // AI-generated image (after instruction)
                            if let dataURL = step.imageDataURL,
                               let uiImage = Data.fromDataURL(dataURL) {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(12)
                                    Text("AI-generated")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                        .padding(8)
                                }
                            }
                        }
                        .padding(20)
                    }

                    // Navigation buttons
                    HStack(spacing: 12) {
                        Button {
                            if state.wizardCurrentStep > 0 {
                                state.wizardCurrentStep -= 1
                                notifyStepChange()
                            }
                        } label: {
                            Text("Back")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.wizardCurrentStep == 0)

                        Button {
                            skip()
                        } label: {
                            Text("Skip")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            advance()
                        } label: {
                            Text(state.wizardCurrentStep == total - 1 ? "Done" : "Next →")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(state.procedureTitle.isEmpty ? "Steps" : state.procedureTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { state.wizardOpen = false }
                }
            }
        }
    }

    private func advance() {
        let total = state.wizardSteps.count
        if state.wizardCurrentStep < total - 1 {
            state.wizardCurrentStep += 1
            notifyStepChange()
        } else {
            state.wizardOpen = false
            state.showYouTube = !state.youtubeVideos.isEmpty
        }
    }

    private func skip() {
        advance()
    }

    private func notifyStepChange() {
        wsManager?.sendStepChange(
            stepNumber: state.wizardCurrentStep + 1,
            total: state.wizardSteps.count
        )
    }
}
