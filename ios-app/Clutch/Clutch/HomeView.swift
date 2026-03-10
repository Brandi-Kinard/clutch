import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var showRegistering = false

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    connectionBadge
                    actionButtons
                    languageSelector
                }
                .padding(20)
            }
        }
        .background(Color(.systemGroupedBackground))
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

    // MARK: - Subviews

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clutch")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text("Hands-free task assistant")
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.7))
                }
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.18))
    }

    private var connectionBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.connectionStatus.color)
                .frame(width: 10, height: 10)
            Text(state.connectionStatus.label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var actionButtons: some View {
        VStack(spacing: 14) {
            Button {
                Task { await connectGlasses() }
            } label: {
                Label("Connect Glasses", systemImage: "eyeglasses")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.1, green: 0.1, blue: 0.18))
            .cornerRadius(14)

            Button {
                state.usePhoneCamera = true
                state.showSession = true
            } label: {
                Label("Use Phone Camera", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.bordered)
            .cornerRadius(14)
        }
    }

    private var languageSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Language")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
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
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func connectGlasses() async {
        state.usePhoneCamera = false
        showRegistering = true
        // Trigger DAT registration (or skip if already registered)
        NotificationCenter.default.post(name: .clutchStartRegistration, object: nil)
        
        // Wait for connection (poll connectionStatus)
        for _ in 0..<30 { // up to 30 seconds
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if case .connected = state.connectionStatus {
                showRegistering = false
                state.showSession = true
                return
            }
        }
        // Timeout
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
