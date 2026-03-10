import SwiftUI
import AVFoundation

struct SessionView: View {
    @Environment(AppState.self) private var state
    let wsManager: WebSocketManager
    let audioManager: AudioManager
    let cameraManager: CameraManager?   // nil when using glasses
    let datManager: DATManager?

    @State private var showWizard = false
    @State private var showYouTube = false
    @State private var permissionDenied = false

    var body: some View {
        @Bindable var state = state
        ZStack {
            CosmicGradientBackground(dimmed: true)

            VStack(spacing: 0) {
                // Status pill
                statusPill
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                // Chat area
                chatArea

                // Procedure card (shown when wizard steps are available)
                if !state.wizardSteps.isEmpty {
                    procedureCardButton
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                // Bottom toolbar
                bottomToolbar
            }
        }
        .sheet(isPresented: $state.wizardOpen) {
            WizardSheet(wsManager: wsManager)
                .environment(state)
        }
        .sheet(isPresented: $state.showYouTube) {
            YouTubeSheet()
                .environment(state)
        }
        .onAppear { startSession() }
        .onDisappear { endSession() }
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        HStack(spacing: 8) {
            if permissionDenied {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text("Permission Required")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            } else if cameraManager != nil {
                Image(systemName: "camera.fill")
                    .foregroundColor(.clutchPrimary)
                    .font(.caption)
                Text("Phone Camera")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Glasses Connected")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if state.sessionStatus == .thinking {
                        thinkingIndicator
                            .padding(.horizontal, 16)
                    }
                    ForEach(state.chatMessages) { msg in
                        ChatBubble(message: msg)
                            .padding(.horizontal, 16)
                            .id(msg.id)
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(minHeight: 80, maxHeight: .infinity)
            .onChange(of: state.chatMessages.count) { _, _ in
                if let last = state.chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ThinkingDot()
            Text("Thinking...")
                .font(.caption)
                .foregroundColor(.white.opacity(0.70))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Procedure Card

    private var procedureCardButton: some View {
        Button {
            state.wizardOpen = true
        } label: {
            HStack(spacing: 0) {
                // Gradient accent stripe on left edge
                LinearGradient(
                    colors: [.clutchPrimary, .clutchViolet],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(.trailing, 12)

                Image(systemName: "list.number")
                    .font(.title3)
                    .foregroundColor(.clutchPrimary)
                    .padding(.trailing, 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.procedureTitle.isEmpty ? "View Steps" : state.procedureTitle)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("\(state.wizardSteps.count) steps")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.60))
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.50))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 16) {
            // Session status + waveform
            HStack(spacing: 8) {
                Image(systemName: state.sessionStatus.icon)
                    .foregroundColor(state.sessionStatus.color)
                    .font(.caption)
                Text(state.sessionStatus.label)
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.80))

                if state.sessionStatus == .listening || state.sessionStatus == .speaking {
                    WaveformView()
                }
            }

            Spacer()

            // Stop button
            Button {
                endSession()
                state.showSession = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .glassButton()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    // MARK: - Session Lifecycle

    private func startSession() {
        Task {
            let micGranted = await audioManager.requestMicAccess()
            guard micGranted else {
                await MainActor.run { permissionDenied = true }
                return
            }

            let bluetoothConnected: Bool
            if case .connected = state.connectionStatus { bluetoothConnected = true } else { bluetoothConnected = false }
            audioManager.configureAudioSession(bluetoothOutput: bluetoothConnected)

            audioManager.onAudioCaptured = { [weak wsManager = wsManager] data in
                wsManager?.sendAudio(data)
            }
            audioManager.startCapture()

            if let cam = cameraManager {
                let camOk = await cam.requestAccessAndStart()
                if camOk {
                    cam.onFrame = { [weak wsManager = wsManager] data in
                        wsManager?.sendVideo(data)
                    }
                } else {
                    await MainActor.run { permissionDenied = true }
                }
            }

            wsManager.audioManager = audioManager
            wsManager.connect()
            await MainActor.run { state.sessionStatus = .listening }
        }
    }

    private func endSession() {
        wsManager.disconnect()
        audioManager.stopCapture()
        audioManager.stopPlayback()
        cameraManager?.stop()
        state.sessionStatus = .idle
        state.showSession = false
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
                userBubble
            } else {
                agentBubble
                Spacer(minLength: 60)
            }
        }
    }

    private var agentBubble: some View {
        Text(message.text)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 16)
            .frame(maxWidth: 280, alignment: .leading)
    }

    private var userBubble: some View {
        HStack(spacing: 0) {
            // Violet left border accent
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.clutchPrimary)
                .frame(width: 3)

            Text(message.text)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.clutchViolet.opacity(0.22))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 280, alignment: .trailing)
    }
}

// MARK: - CameraManager captureSession accessor

extension CameraManager {
    var captureSession: AVCaptureSession { session }
}
