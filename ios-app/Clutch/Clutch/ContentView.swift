import SwiftUI
import MWDATCore

struct ContentView: View {
    @State private var appState = AppState()
    @State private var wsManager: WebSocketManager?
    @State private var audioManager = AudioManager()
    @State private var cameraManager = CameraManager()
    @State private var datManager: DATManager?

    var body: some View {
        @Bindable var appState = appState
        ZStack {
            if appState.showSession {
                if let ws = wsManager {
                    SessionView(
                        wsManager: ws,
                        audioManager: audioManager,
                        cameraManager: appState.usePhoneCamera ? cameraManager : nil,
                        datManager: datManager
                    )
                    .environment(appState)
                    .transition(.opacity)
                }
            } else {
                HomeView()
                    .environment(appState)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.showSession)
        .onAppear {
            let ws = WebSocketManager(appState: appState)
            wsManager = ws
            let dat = DATManager()
            dat.appState = appState
            dat.onGlassesFrame = { [weak ws] data in
                ws?.sendVideo(data)
            }
            datManager = dat
            dat.startMonitoringDevices()
        }
        
        .onOpenURL { url in
            print("[ContentView] Received URL: \(url)")
            guard
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
            else {
                print("[ContentView] URL not a DAT callback, ignoring")
                return
            }
            print("[ContentView] DAT callback URL detected, handling...")
            Task {
                do {
                    _ = try await Wearables.shared.handleUrl(url)
                    print("[ContentView] handleUrl succeeded")
                } catch {
                    print("[ContentView] handleUrl error:", error)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clutchStartRegistration)) { _ in
            Task { await datManager?.startRegistration() }
        }
    }
}
