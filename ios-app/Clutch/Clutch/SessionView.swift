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
        VStack(spacing: 0) {
            topBar
            cameraPreviewArea
            statusRow
            chatArea
            if !state.wizardSteps.isEmpty {
                procedureCardButton
            }
            stopRow
        }
        .background(Color(.systemGroupedBackground))
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

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("🔧 Clutch")
                .font(.headline.bold())
                .foregroundColor(.white)
            Spacer()
            Text(state.selectedLanguage.flag + " " + state.selectedLanguage.name)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.1, green: 0.1, blue: 0.18))
    }

    // MARK: - Camera preview

    private var cameraPreviewArea: some View {
        ZStack {
            Color.black
            if permissionDenied {
                VStack(spacing: 8) {
                    Image(systemName: "camera.slash.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red.opacity(0.8))
                    Text("Camera & Mic permission needed")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.8))
                    Text("Enable in Settings > Clutch")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            } else if let cameraManager {
                CameraPreviewView(session: cameraManager.captureSession)
                    .aspectRatio(4/3, contentMode: .fit)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Viewing through glasses")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(height: 180)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: state.sessionStatus.icon)
                .foregroundColor(state.sessionStatus.color)
            Text(state.sessionStatus.label)
                .font(.subheadline.bold())
                .foregroundColor(state.sessionStatus.color)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Chat area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(state.chatMessages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(minHeight: 80, maxHeight: .infinity)
            .onChange(of: state.chatMessages.count) { _, _ in
                if let last = state.chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Procedure card

    private var procedureCardButton: some View {
        Button {
            state.wizardOpen = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.number")
                    .font(.title3)
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.procedureTitle.isEmpty ? "View Steps" : state.procedureTitle)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("\(state.wizardSteps.count) steps")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.1, green: 0.1, blue: 0.18))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .cornerRadius(12)
    }

    // MARK: - Stop button

    private var stopRow: some View {
        Button {
            endSession()
            state.showSession = false
        } label: {
            Label("Stop Session", systemImage: "stop.circle.fill")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.85))
                .cornerRadius(14)
        }
        .padding(16)
    }

    // MARK: - Session lifecycle

    private func startSession() {
        Task {
            // Request microphone permission
            let micGranted = await audioManager.requestMicAccess()
            guard micGranted else {
                await MainActor.run { permissionDenied = true }
                return
            }

            let bluetoothConnected: Bool
            if case .connected = state.connectionStatus { bluetoothConnected = true } else { bluetoothConnected = false }
            audioManager.configureAudioSession(bluetoothOutput: bluetoothConnected)

            // Start audio capture
            audioManager.onAudioCaptured = { [weak wsManager = wsManager] data in
                wsManager?.sendAudio(data)
            }
            audioManager.startCapture()

            // Start camera (phone) and wire up frame sending
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

            // Start WebSocket
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
            if message.isUser { Spacer() }
            Text(message.text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(message.isUser ? Color.blue : Color(.systemGray4))
                .foregroundColor(message.isUser ? .white : .primary)
                .cornerRadius(16)
                .frame(maxWidth: 260, alignment: message.isUser ? .trailing : .leading)
            if !message.isUser { Spacer() }
        }
    }
}

// MARK: - Camera preview UIViewRepresentable

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            guard let session else { return }
            (layer as? AVCaptureVideoPreviewLayer)?.session = session
        }
    }

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        (layer as? AVCaptureVideoPreviewLayer)?.videoGravity = .resizeAspectFill
    }
}

// MARK: - CameraManager captureSession accessor

extension CameraManager {
    var captureSession: AVCaptureSession { session }
}
