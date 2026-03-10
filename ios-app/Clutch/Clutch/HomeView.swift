import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var showRegistering = false

    var body: some View {
        @Bindable var state = state
        ZStack {
            CosmicGradientBackground()

            VStack(spacing: 0) {
                // Settings gear — top right
                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.75))
                            .glassCircle(size: 40)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // Hero
                VStack(spacing: 10) {
                    Text("Clutch")
                        .font(.system(size: 54, weight: .bold, design: .default))
                        .foregroundColor(.white)

                    Text("See it. Ask it. Do it.")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.60))

                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.connectionStatus.color)
                            .frame(width: 8, height: 8)
                        Text(state.connectionStatus.label)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .padding(.top, 6)
                }

                Spacer()

                // Action buttons + language selector
                VStack(spacing: 14) {
                    Button {
                        Task { await connectGlasses() }
                    } label: {
                        Label("Connect Glasses", systemImage: "eyeglasses")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .glassButton()
                    .buttonStyle(.plain)

                    Button {
                        state.usePhoneCamera = true
                        state.showSession = true
                    } label: {
                        Label("Use Phone Camera", systemImage: "camera.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .glassButton()
                    .buttonStyle(.plain)

                    languageSelector
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(wsURL: $state.wsURL) }
        .alert("Connecting to Meta App…", isPresented: $showRegistering) {
            Button("Cancel", role: .cancel) { showRegistering = false }
        } message: {
            Text("Follow the prompts in the Meta app to pair your glasses.")
        }
        .onChange(of: state.connectionStatus.label) { _, newValue in
            if newValue.starts(with: "Connected") {
                showRegistering = false
            }
        }
    }

    // MARK: - Language selector

    private var languageSelector: some View {
        HStack(spacing: 10) {
            ForEach(AppLanguage.all) { lang in
                let selected = state.selectedLanguage.id == lang.id
                Button {
                    state.selectedLanguage = lang
                } label: {
                    VStack(spacing: 4) {
                        Text(lang.flag).font(.title2)
                        Text(lang.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundColor(.white.opacity(selected ? 1.0 : 0.55))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.clutchViolet.opacity(selected ? 0.22 : 0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        selected ? Color.clutchPrimary : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func connectGlasses() async {
        state.usePhoneCamera = false
        showRegistering = true
        NotificationCenter.default.post(name: .clutchStartRegistration, object: nil)

        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if case .connected = state.connectionStatus {
                showRegistering = false
                state.showSession = true
                return
            }
        }
        showRegistering = false
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @Binding var wsURL: String
    @Environment(\.dismiss) private var dismiss
    @State private var draftURL = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend WebSocket URL") {
                    TextField("wss://...", text: $draftURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                Section {
                    Text("Default: wss://clutch-vyt2xlbryq-uc.a.run.app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        wsURL = draftURL
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { draftURL = wsURL }
    }
}

extension Notification.Name {
    static let clutchStartRegistration = Notification.Name("clutchStartRegistration")
}
