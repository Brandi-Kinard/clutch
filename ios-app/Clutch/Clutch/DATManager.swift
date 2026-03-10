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
    private var autoSelector: AutoDeviceSelector?

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
        
        // Already registered — just make sure we're monitoring devices
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

    // MARK: - Device monitoring

    func startMonitoringDevices() {
        deviceMonitorTask?.cancel()

        let selector = AutoDeviceSelector(wearables: Wearables.shared)
        autoSelector = selector

        // Watch registration state changes
        Task { [weak self] in
            for await state in Wearables.shared.registrationStateStream() {
                print("[DATManager] registrationState:", state.rawValue)
                if state == .registered {
                    self?.appState?.connectionStatus = .connecting
                }
            }
        }

        // Watch all devices (the key stream)
        Task { [weak self] in
            for await devices in Wearables.shared.devicesStream() {
                print("[DATManager] devicesStream: \(devices.count) device(s):", devices)
                if let first = devices.first {
                    print("[DATManager] Device found: \(first)")
                }
            }
        }

        // Watch active device via AutoDeviceSelector
        deviceMonitorTask = Task { [weak self] in
            guard let self else { return }
            for await activeDevice in selector.activeDeviceStream() {
                if let deviceID = activeDevice {
                    print("[DATManager] Active device found:", deviceID)
                    self.appState?.connectionStatus = .connected(deviceName: deviceID)
                    await self.startGlassesCamera(selector: selector)
                } else {
                    print("[DATManager] No active device")
                    self.appState?.connectionStatus = .disconnected
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

    // MARK: - Glasses camera

    private func startGlassesCamera(selector: AutoDeviceSelector) async {
        guard streamSession == nil else {
            print("[DATManager] StreamSession already exists, skipping")
            return
        }
        // Check and request camera permission before streaming
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
        
        print("[DATManager] Creating StreamSession...")
        let session = StreamSession(deviceSelector: selector)
        streamSession = session

        // Listen for stream state changes
        let _ = session.statePublisher.listen { state in
            print("[DATManager] StreamSession state:", state)
        }

        // Listen for errors
        let _ = session.errorPublisher.listen { error in
            print("[DATManager] StreamSession error:", error)
        }

        var frameCount = 0
        videoFrameToken = session.videoFramePublisher.listen { [weak self] frame in
            guard let self else { return }
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

        Task {
            print("[DATManager] Starting StreamSession...")
            await session.start()
            print("[DATManager] StreamSession.start() returned")
        }
    }

    private func stopGlassesCamera() {
        if let token = videoFrameToken {
            Task { await token.cancel() }
            videoFrameToken = nil
        }
        if let session = streamSession {
            Task { await session.stop() }
            streamSession = nil
        }
    }
}
