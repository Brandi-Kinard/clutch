import Foundation
import UIKit
import MWDATCore
import MWDATCamera

/// Wraps the Meta Wearables DAT SDK for device registration, monitoring, and camera streaming.
@MainActor
final class DATManager {

    weak var appState: AppState?
    var onGlassesFrame: ((Data) -> Void)?

    private var deviceMonitorTask: Task<Void, Never>?
    private var streamSession: StreamSession?
    private var videoFrameToken: (any AnyListenerToken)?
    private var stateToken: (any AnyListenerToken)?
    private var errorToken: (any AnyListenerToken)?

    // Stored so startGlassesCamera() can use it when called later (after WS is ready)
    private var activeSelector: AutoDeviceSelector?

    // MARK: - SDK Lifecycle

    /// Call once at app launch before any UI. Silently ignores if already configured.
    static func configure() {
        try? Wearables.configure()
    }

    // MARK: - Registration

    /// Opens the Meta app pairing flow. Updates `appState.connectionStatus` on completion.
    func startRegistration() async {
        let currentState = Wearables.shared.registrationState
        print("[DATManager] startRegistration called, current state:", currentState.rawValue)

        if currentState == .registered {
            print("[DATManager] Already registered, starting device monitoring")
            startMonitoringDevices()
            return
        }

        guard currentState != .registering else {
            print("[DATManager] Already registering, skipping")
            return
        }

        appState?.connectionStatus = .connecting
        print("[DATManager] Starting registration...")
        do {
            try await Wearables.shared.startRegistration()
            print("[DATManager] startRegistration() returned, state:", Wearables.shared.registrationState.rawValue)
        } catch {
            print("[DATManager] Registration error:", error)
            appState?.connectionStatus = .disconnected
        }
    }

    // MARK: - Device Monitoring

    /// Watches for device availability and updates `connectionStatus`. Does NOT start streaming.
    /// Streaming only starts when the session is active — call `startGlassesCamera()` explicitly.
    func startMonitoringDevices() {
        deviceMonitorTask?.cancel()

        let selector = AutoDeviceSelector(wearables: Wearables.shared)
        activeSelector = selector

        // Watch registration state changes
        Task { [weak self] in
            for await state in Wearables.shared.registrationStateStream() {
                print("[DATManager] registrationState:", state.rawValue)
                if state == .registered {
                    self?.appState?.connectionStatus = .connecting
                }
            }
        }

        // Watch all devices (informational)
        Task { [weak self] in
            for await devices in Wearables.shared.devicesStream() {
                print("[DATManager] devicesStream: \(devices.count) device(s):", devices)
                if let first = devices.first {
                    print("[DATManager] Device found: \(first)")
                }
            }
        }

        // Watch the active device — update connectionStatus ONLY.
        // Camera streaming is started explicitly by SessionView after WebSocket is ready.
        deviceMonitorTask = Task { [weak self] in
            guard let self else { return }
            for await activeDevice in selector.activeDeviceStream() {
                if let deviceID = activeDevice {
                    print("[DATManager] Active device:", deviceID)
                    self.appState?.connectionStatus = .connected(deviceName: deviceID)
                    // Do NOT start streaming here — the WebSocket isn't open yet.
                } else {
                    print("[DATManager] No active device")
                    self.appState?.connectionStatus = .disconnected
                    // Glasses disconnected mid-session — tear down the stream.
                    self.stopGlassesCamera()
                }
            }
        }
    }

    func stopMonitoring() {
        deviceMonitorTask?.cancel()
        deviceMonitorTask = nil
        stopGlassesCamera()
    }

    // MARK: - Glasses Camera (called by SessionView after WebSocket is connected)

    /// Starts the glasses camera stream with up to 3 retry attempts.
    /// Safe to call even if a dead stream exists — tears it down and creates a fresh one.
    func startGlassesCamera() async {
        guard let selector = activeSelector else {
            print("[DATManager] No active device selector — cannot start glasses camera")
            return
        }

        // Tear down any stale session from a previous (failed) start
        if streamSession != nil {
            print("[DATManager] Tearing down stale StreamSession before fresh start")
            stopGlassesCamera()
        }

        // Check and request camera permission once, before the retry loop
        print("[DATManager] Checking camera permission...")
        do {
            let permStatus = try await Wearables.shared.checkPermissionStatus(.camera)
            print("[DATManager] Camera permission status:", permStatus)
            if permStatus != .granted {
                print("[DATManager] Requesting camera permission...")
                let newStatus = try await Wearables.shared.requestPermission(.camera)
                print("[DATManager] Camera permission after request:", newStatus)
                if newStatus != .granted {
                    print("[DATManager] Camera permission denied, cannot stream")
                    return
                }
            }
        } catch {
            print("[DATManager] Permission check/request error:", error)
        }

        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            print("[DATManager] Creating StreamSession (attempt \(attempt)/\(maxAttempts))...")

            let session = StreamSession(deviceSelector: selector)
            streamSession = session

            // Wire up frame forwarding for this session attempt
            var frameCount = 0
            let hasCallback = onGlassesFrame != nil
            videoFrameToken = session.videoFramePublisher.listen { [weak self] frame in
                guard let self, hasCallback else { return }
                frameCount += 1
                if frameCount <= 3 || frameCount % 30 == 0 {
                    print("[DATManager] Video frame #\(frameCount) received")
                }
                Task.detached {
                    guard let uiImage = frame.makeUIImage(),
                          let jpegData = uiImage.jpegData(compressionQuality: 0.5) else {
                        print("[DATManager] Failed to convert frame to JPEG")
                        return
                    }
                    await MainActor.run {
                        self.onGlassesFrame?(jpegData)
                    }
                }
            }

            // Attempt to start and wait for a definitive success/failure signal
            let succeeded = await attemptStart(session: session)

            if succeeded {
                print("[DATManager] StreamSession started successfully (attempt \(attempt)/\(maxAttempts))")
                return
            }

            // Failed — clean up before possibly retrying
            stopGlassesCamera()

            if attempt < maxAttempts {
                print("[DATManager] StreamSession failed (attempt \(attempt)/\(maxAttempts)), retrying in 2s...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } else {
                print("[DATManager] StreamSession failed after \(maxAttempts) attempts, giving up")
            }
        }
    }

    /// Starts `session` and awaits a success/failure signal from the state and error publishers.
    /// Returns `true` if the session reached `.started`, `false` if it stopped, errored, or timed out.
    ///
    /// Uses `withCheckedContinuation` to bridge the callback publishers into async/await.
    /// The `done` guard is safe because all signal calls hop to the MainActor serial executor,
    /// ensuring the continuation is resumed exactly once.
    private func attemptStart(session: StreamSession) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var done = false

            // Signals the continuation at most once. All calls hop to MainActor
            // so the serial executor guarantees `done` is read/written safely.
            func signal(success: Bool) {
                Task { @MainActor in
                    guard !done else { return }
                    done = true
                    cont.resume(returning: success)
                }
            }

            // Watch state transitions: .started = success, .stopped = failure
            stateToken = session.statePublisher.listen { state in
                print("[DATManager] StreamSession state:", state)
                if state == .streaming {
                    signal(success: true)
                } else if state == .stopped {
                    signal(success: false)
                }
            }

            // Any error = failure
            errorToken = session.errorPublisher.listen { error in
                print("[DATManager] StreamSession error:", error)
                signal(success: false)
            }

            // 5-second safety timeout in case no state/error event fires
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                signal(success: false)
            }

            // Actually start the session
            Task {
                print("[DATManager] Starting StreamSession...")
                await session.start()
                print("[DATManager] StreamSession.start() returned")
            }
        }
    }

    // MARK: - Cleanup

    /// Stops the glasses camera stream and cancels all listener tokens.
    func stopGlassesCamera() {
        if let token = videoFrameToken {
            Task { await token.cancel() }
            videoFrameToken = nil
        }
        if let token = stateToken {
            Task { await token.cancel() }
            stateToken = nil
        }
        if let token = errorToken {
            Task { await token.cancel() }
            errorToken = nil
        }
        if let session = streamSession {
            Task { await session.stop() }
            streamSession = nil
        }
    }
}
