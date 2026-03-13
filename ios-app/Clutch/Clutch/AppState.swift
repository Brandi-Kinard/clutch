import SwiftUI
import Observation

@Observable
final class AppState {
    // MARK: Navigation
    var showSession = false
    var usePhoneCamera = false

    // MARK: DAT / Connection
    var connectionStatus: ConnectionStatus = .disconnected

    // MARK: Language
    var selectedLanguage: AppLanguage = AppLanguage.all[0]

    // MARK: Settings (persisted)
    var wsURL: String {
        get { "wss://clutch-154259901703.us-central1.run.app/ws" }
        set { UserDefaults.standard.set(newValue, forKey: "wsURL") }
    }

    // MARK: Session
    var sessionStatus: SessionStatus = .idle
    var chatMessages: [ChatMessage] = []

    // MARK: Wizard
    var wizardSteps: [WizardStep] = []
    var wizardCurrentStep: Int = 0
    var wizardOpen: Bool = false
    var procedureTitle: String = ""

    // MARK: YouTube
    var youtubeVideos: [YouTubeVideo] = []
    var showYouTube: Bool = false

    // MARK: Products
    var productItems: [ProductItem] = []
    var showProducts: Bool = false
}
