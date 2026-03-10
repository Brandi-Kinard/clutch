import SwiftUI

struct WizardSheet: View {
    @Environment(AppState.self) private var state
    var wsManager: WebSocketManager?

    @State private var showCompletion = false

    var body: some View {
        ZStack {
            CosmicGradientBackground()

            if showCompletion {
                completionScreen
            } else {
                mainContent
            }
        }
        .presentationBackground(.clear)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerBar

            if !state.wizardSteps.isEmpty {
                let step = state.wizardSteps[state.wizardCurrentStep]
                let total = state.wizardSteps.count

                progressBar(pct: CGFloat(state.wizardCurrentStep + 1) / CGFloat(total))
                    .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Step badge
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().stroke(Color.clutchPrimary, lineWidth: 2))
                                    .frame(width: 40, height: 40)
                                Text("\(step.number)")
                                    .font(.headline.bold())
                                    .foregroundColor(.clutchPrimary)
                            }
                            Text("Step \(step.number) of \(total)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.60))
                            Spacer()
                        }

                        // Instruction
                        Text(step.instruction)
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        // Tools needed
                        if !step.toolsNeeded.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "wrench.fill")
                                    .font(.caption)
                                    .foregroundColor(.clutchPrimary)
                                Text(step.toolsNeeded.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassCard(cornerRadius: 10)
                        }

                        // AI-generated image
                        if let dataURL = step.imageDataURL,
                           let uiImage = Data.fromDataURL(dataURL) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.clutchPrimary.opacity(0.40), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 4)

                                Text("AI-generated")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.ultraThinMaterial))
                                    .foregroundColor(.white)
                                    .padding(10)
                            }
                        }
                    }
                    .padding(20)
                }

                navButtons(total: total)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        ZStack {
            // Title with horizontal inset to avoid overlapping close button
            Text(state.procedureTitle.isEmpty ? "Steps" : state.procedureTitle)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 56) // reserve space for 32pt circle + margins

            HStack {
                Spacer()
                Button { state.wizardOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.80))
                        .glassCircle(size: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Progress Bar

    private func progressBar(pct: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.clutchPrimary, .clutchViolet],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * pct)
                    .animation(.easeInOut(duration: 0.35), value: pct)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 20)
    }

    // MARK: - Nav Buttons (Back / Next+Done, no Skip)

    private func navButtons(total: Int) -> some View {
        HStack {
            // Back
            Button {
                if state.wizardCurrentStep > 0 {
                    state.wizardCurrentStep -= 1
                    notifyStepChange()
                }
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(state.wizardCurrentStep == 0 ? .white.opacity(0.30) : .white)
                    .glassCircle(size: 52)
            }
            .buttonStyle(.plain)
            .disabled(state.wizardCurrentStep == 0)

            Spacer()

            // Next / Done
            let isLast = state.wizardCurrentStep == total - 1
            Button { advance() } label: {
                Image(systemName: isLast ? "checkmark" : "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .glassCircle(size: 52, highlighted: isLast)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Completion Screen

    private var completionScreen: some View {
        VStack(spacing: 0) {
            headerBar

            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.clutchPrimary)

                VStack(spacing: 8) {
                    Text("All Done!")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Text("How did it go?")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.60))
                }

                // Feedback faces
                HStack(spacing: 16) {
                    ForEach(["😡", "😔", "😐", "🙂", "😁"], id: \.self) { emoji in
                        Button {
                            closeAfterCompletion()
                        } label: {
                            Text(emoji)
                                .font(.title2)
                                .padding(12)
                                .glassCircle(size: 52)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(32)
            .glassCard(cornerRadius: 24)
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Logic

    private func advance() {
        let total = state.wizardSteps.count
        if state.wizardCurrentStep < total - 1 {
            state.wizardCurrentStep += 1
            notifyStepChange()
        } else {
            showCompletion = true
        }
    }

    private func skip() {
        advance()
    }

    private func closeAfterCompletion() {
        // Videos are now shown inline in chat — no auto-open sheet
        state.wizardOpen = false
    }

    private func notifyStepChange() {
        wsManager?.sendStepChange(
            stepNumber: state.wizardCurrentStep + 1,
            total: state.wizardSteps.count
        )
    }
}
