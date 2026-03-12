import SwiftUI
import AVFoundation

struct SessionView: View {
    @Environment(AppState.self) private var state
    let wsManager: WebSocketManager
    let audioManager: AudioManager
    let cameraManager: CameraManager?   // nil when using glasses
    let datManager: DATManager?

    @State private var permissionDenied = false
    @State private var micMuted = false
    @State private var cameraOff = false

    var body: some View {
        @Bindable var state = state
        ZStack {
            CosmicGradientBackground(
                dimmed: true,
                pulsing: state.sessionStatus == .speaking
            )

            VStack(spacing: 0) {
                // Status pill
                statusPill
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                // Chat area (includes inline procedure + video cards)
                chatArea
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomToolbar
        }
        .sheet(isPresented: $state.wizardOpen) {
            WizardSheet(wsManager: wsManager)
                .environment(state)
        }
        .sheet(isPresented: $state.showYouTube) {
            YouTubeSheet()
                .environment(state)
        }
        .sheet(isPresented: $state.showProducts) {
            ProductsSheet()
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
                    ForEach(state.chatMessages) { msg in
                        ChatBubble(message: msg)
                            .padding(.horizontal, 16)
                            .id(msg.id)
                    }

                    // Thinking indicator after last message
                    if state.sessionStatus == .thinking {
                        thinkingIndicator
                            .padding(.horizontal, 16)
                            .id("thinking")
                    }

                    // Inline procedure card
                    if !state.wizardSteps.isEmpty {
                        inlineProcedureCard
                            .padding(.horizontal, 16)
                            .id("procedure-card")
                    }

                    // Inline YouTube card
                    if !state.youtubeVideos.isEmpty {
                        inlineYouTubeCard
                            .padding(.horizontal, 16)
                            .id("youtube-card")
                    }

                    // Inline Products card
                    if !state.productItems.isEmpty {
                        inlineProductsCard
                            .padding(.horizontal, 16)
                            .id("products-card")
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(minHeight: 80, maxHeight: .infinity)
            // Empty state overlay
            .overlay {
                if state.chatMessages.isEmpty && state.sessionStatus != .thinking {
                    Text("Start talking")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .onChange(of: state.chatMessages.count) { _, _ in
                if let last = state.chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: state.wizardSteps.isEmpty) { _, isEmpty in
                if !isEmpty {
                    withAnimation { proxy.scrollTo("procedure-card", anchor: .bottom) }
                }
            }
            .onChange(of: state.youtubeVideos.isEmpty) { _, isEmpty in
                if !isEmpty {
                    withAnimation { proxy.scrollTo("youtube-card", anchor: .bottom) }
                }
            }
            .onChange(of: state.productItems.isEmpty) { _, isEmpty in
                if !isEmpty {
                    withAnimation { proxy.scrollTo("products-card", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Thinking Indicator

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

    // MARK: - Inline Procedure Card

    private var inlineProcedureCard: some View {
        Button {
            state.wizardCurrentStep = 0   // always start from step 1 when re-opening
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
                .padding(.trailing, 10)

                Image(systemName: "list.number")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.55, green: 0.35, blue: 0.95))
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.procedureTitle.isEmpty ? "Steps Ready" : state.procedureTitle)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(state.wizardSteps.count) steps")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.60))
                }

                Spacer()

                // "Tap to start" badge
                Text("Tap to start")
                    .font(.caption2.bold())
                    .foregroundColor(Color(red: 0.55, green: 0.35, blue: 0.95))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.25)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline YouTube Card

    private var inlineYouTubeCard: some View {
        Button {
            state.showYouTube = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title3)
                    .foregroundColor(Color(red: 0.55, green: 0.35, blue: 0.95))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Related Videos")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    let count = state.youtubeVideos.count
                    Text("\(count) video\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.60))
                }

                Spacer()

                // "Tap to watch" badge
                Text("Tap to watch")
                    .font(.caption2.bold())
                    .foregroundColor(Color(red: 0.55, green: 0.35, blue: 0.95))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.25)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Products Card

    private var inlineProductsCard: some View {
        Button {
            state.showProducts = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cart.fill")
                    .font(.title3)
                    .foregroundColor(Color(red: 0.55, green: 0.35, blue: 0.95))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Products Nearby")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    let count = state.productItems.count
                    Text("\(count) result\(count == 1 ? "" : "s") found")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.60))
                }

                Spacer()

                Text("Tap to shop")
                    .font(.caption2.bold())
                    .foregroundColor(Color(red: 0.55, green: 0.35, blue: 0.95))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.25)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Floating Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 10) {
            // Mute mic
            Button {
                micMuted.toggle()
                if micMuted { audioManager.stopCapture() } else { audioManager.startCapture() }
            } label: {
                Image(systemName: micMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 17))
                    .foregroundColor(micMuted ? .red.opacity(0.85) : .white)
                    .glassCircle(size: 44)
            }
            .buttonStyle(.plain)

            // Camera toggle (visual state only — glasses-only app)
            Button { cameraOff.toggle() } label: {
                Image(systemName: cameraOff ? "video.slash.fill" : "video.fill")
                    .font(.system(size: 17))
                    .foregroundColor(cameraOff ? .red.opacity(0.85) : .white)
                    .glassCircle(size: 44)
            }
            .buttonStyle(.plain)

            // Language menu pill
            Menu {
                ForEach(AppLanguage.all) { lang in
                    Button {
                        state.selectedLanguage = lang
                    } label: {
                        Label(
                            lang.flag + "  " + lang.name,
                            systemImage: state.selectedLanguage.id == lang.id ? "checkmark" : ""
                        )
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .medium))
                    Text(state.selectedLanguage.flag)
                        .font(.system(size: 15))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassButton()
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
        // Inner padding of the floating pill
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Floating pill background: liquid glass with rounded corners and shadow
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.clutchViolet.opacity(0.10))
                )
                .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 6)
        )
        // Outer margins: keeps pill away from screen edges and home indicator
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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
                // Phone camera path
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

            // Glasses camera path: start AFTER WebSocket is connected so the
            // StreamSession doesn't get an internalError from launching too early.
            if cameraManager == nil {
                await datManager?.startGlassesCamera()
            }
        }
    }

    private func endSession() {
        wsManager.disconnect()
        audioManager.stopCapture()
        audioManager.stopPlayback()
        cameraManager?.stop()
        // Stop glasses stream when session ends
        if cameraManager == nil {
            datManager?.stopGlassesCamera()
        }
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
        VStack(alignment: .leading, spacing: 8) {
            // Annotation image (if this is a highlight result)
            if let dataURL = message.imageDataURL,
               let uiImage = Data.fromDataURL(dataURL) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.clutchPrimary.opacity(0.45), lineWidth: 1)
                    )
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
        }
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
