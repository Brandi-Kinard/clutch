import Foundation

/// Manages the WebSocket connection to the Clutch backend.
/// All public methods are called from the main actor.
final class WebSocketManager {

    private var wsTask: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)
    private var receiveTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let maxRetries = 3
    private var active = false

    private weak var appState: AppState?
    // Injected so audio playback can be triggered without coupling to Main actor
    var audioManager: AudioManager?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Connect / Disconnect

    func connect() {
        guard let state = appState, let url = URL(string: state.wsURL) else { return }
        active = true
        reconnectAttempts = 0
        openSocket(url: url)
    }

    func disconnect() {
        active = false
        receiveTask?.cancel()
        receiveTask = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
    }

    // MARK: - Send helpers

    func sendAudio(_ data: Data) {
        let msg: [String: Any] = [
            "type": "audio",
            "data": data.base64EncodedString(),
            "mime_type": "audio/pcm;rate=16000"
        ]
        sendJSON(msg)
    }

    func sendVideo(_ data: Data) {
        let msg: [String: Any] = [
            "type": "video",
            "data": data.base64EncodedString()
        ]
        sendJSON(msg)
    }

    func sendText(_ text: String) {
        sendJSON(["type": "text", "text": text])
    }

    func sendConfig(language: String) {
        sendJSON(["type": "config", "language": language])
    }

    func sendStepChange(stepNumber: Int, total: Int) {
        sendJSON(["type": "step_change", "step_number": stepNumber, "total_steps": total])
    }

    // MARK: - Private

    private func openSocket(url: URL) {
        wsTask = urlSession.webSocketTask(with: url)
        wsTask?.maximumMessageSize = 16 * 1024 * 1024
        wsTask?.resume()
        print("[WS] Socket opened to \(url)")

        // Send initial language config
        if let lang = appState?.selectedLanguage.id {
            sendConfig(language: lang)
        }

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let wsTask else { return }
        do {
            while active {
                let message = try await wsTask.receive()
                switch message {
                case .string(let str):
                    print("[WS] Received: \(str.prefix(200))")
                    await handleMessage(str)
                case .data(let data):
                    if let str = String(data: data, encoding: .utf8) {
                        await handleMessage(str)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            if active {
                await scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ str: String) async {
        guard
            let data = str.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        await MainActor.run {
            switch type {
            case "audio":
                audioManager?.isMuted = true
                if let b64 = json["data"] as? String,
                   let audioData = Data(base64Encoded: b64) {
                    print("[WS] Playing audio chunk: \(audioData.count) bytes")
                    audioManager?.playAudio(audioData)
                }

            case "text":
                if let text = json["text"] as? String,
                   let clean = filterAgentText(text) {
                    appState?.chatMessages.append(ChatMessage(text: clean, isUser: false))
                }

            case "input_transcription":
                if let text = json["text"] as? String, !text.isEmpty {
                    let partial = json["partial"] as? Bool ?? true
                    if !partial {
                        appState?.chatMessages.append(ChatMessage(text: text, isUser: true))
                    }
                }

            case "output_transcription":
                if let text = json["text"] as? String, !text.isEmpty {
                    let partial = json["partial"] as? Bool ?? true
                    if !partial, let clean = filterAgentText(text) {
                        appState?.chatMessages.append(ChatMessage(text: clean, isUser: false))
                    }
                }

            case "annotation":
                if let imageURL = json["image"] as? String {
                    let label = json["label"] as? String ?? ""
                    appState?.chatMessages.append(ChatMessage(
                        text: label.isEmpty ? "Highlighted" : label,
                        isUser: false,
                        imageDataURL: imageURL
                    ))
                }

            case "tool_result":
                if let results = json["results"] as? [[String: Any]] {
                    for r in results {
                        if let tool = r["tool"] as? String {
                            handleToolResult(tool: tool, result: r["result"])
                        }
                    }
                }

            case "advance_step":
                advanceWizardStep()

            case "turn_complete":
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak audioManager] in audioManager?.isMuted = false }
                if appState?.sessionStatus == .thinking || appState?.sessionStatus == .speaking {
                    appState?.sessionStatus = .listening
                }

            case "interrupted":
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak audioManager] in audioManager?.isMuted = false }
                audioManager?.stopPlayback()
                appState?.sessionStatus = .listening

            default:
                break
            }
        }
    }

    @MainActor
    private func handleToolResult(tool: String, result: Any?) {
        switch tool {
        case "generate_steps":
            guard let dict = result as? [String: Any],
                  let stepsArr = dict["steps"] as? [[String: Any]] else { return }
            guard let stepsData = try? JSONSerialization.data(withJSONObject: stepsArr),
                  let steps = try? JSONDecoder().decode([WizardStep].self, from: stepsData) else { return }
            appState?.wizardSteps = steps
            appState?.wizardCurrentStep = 0
            if let first = steps.first {
                let title = first.instruction
                    .split(separator: ".").first
                    .map(String.init) ?? first.instruction
                appState?.procedureTitle = String(title.prefix(50))
            }

        case "search_youtube":
            guard let arr = result as? [[String: Any]] else { return }
            appState?.youtubeVideos = arr.compactMap { item in
                guard let url = item["video_url"] as? String else { return nil }
                return YouTubeVideo(
                    title: item["title"] as? String ?? "Video",
                    videoURL: url,
                    thumbnailURL: item["thumbnail_url"] as? String
                )
            }

        default:
            break
        }
    }

    @MainActor
    private func advanceWizardStep() {
        guard let state = appState, state.wizardOpen else { return }
        let total = state.wizardSteps.count
        if state.wizardCurrentStep < total - 1 {
            state.wizardCurrentStep += 1
            sendStepChange(stepNumber: state.wizardCurrentStep + 1, total: total)
        }
    }

    private func scheduleReconnect() async {
        guard reconnectAttempts < maxRetries else {
            await MainActor.run { appState?.sessionStatus = .idle }
            return
        }
        reconnectAttempts += 1
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard active, let state = appState, let url = URL(string: state.wsURL) else { return }
        openSocket(url: url)
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let wsTask,
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        wsTask.send(.string(str)) { _ in }
    }

    // MARK: - Text filter

    /// Returns cleaned text or nil if the text should be dropped (internal-process leak).
    private func filterAgentText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Drop markdown bold headers
        if trimmed.hasPrefix("**") { return nil }
        // Drop if contains backticks
        if trimmed.contains("`") { return nil }
        // Drop if contains internal-process phrases or tool names
        let lower = trimmed.lowercased()
        let blocked = [
            "generating instructions", "confirming ready state", "advancing the process",
            "initiating", "i've initiated", "i plan to generate", "i'm prepared to commence",
            "generate_steps", "search_youtube", "advance_step", "annotate_image"
        ]
        for phrase in blocked where lower.contains(phrase) { return nil }
        // Strip markdown formatting
        let clean = trimmed
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
