import Foundation
import SwiftUI

// MARK: - Enums

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected(deviceName: String)

    var label: String {
        switch self {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected(let name): return "Connected to \(name)"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        }
    }
}

enum SessionStatus {
    case idle, listening, thinking, speaking

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .gray
        case .listening: return .green
        case .thinking: return .orange
        case .speaking: return Color(red: 0.6, green: 0.2, blue: 0.8)
        }
    }

    var icon: String {
        switch self {
        case .idle: return "circle.fill"
        case .listening: return "mic.fill"
        case .thinking: return "ellipsis.circle.fill"
        case .speaking: return "speaker.wave.2.fill"
        }
    }
}

// MARK: - Data Models

struct WizardStep: Identifiable, Codable {
    var id: Int { number }
    let number: Int
    let instruction: String
    let toolsNeeded: [String]
    let imageSearchQuery: String
    let imageDataURL: String?

    enum CodingKeys: String, CodingKey {
        case number, instruction
        case toolsNeeded = "tools_needed"
        case imageSearchQuery = "image_search_query"
        case imageDataURL = "image_data_url"
    }

    /// Decode imageDataURL as nil if JSON null
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        instruction = try c.decode(String.self, forKey: .instruction)
        toolsNeeded = (try? c.decode([String].self, forKey: .toolsNeeded)) ?? []
        imageSearchQuery = (try? c.decode(String.self, forKey: .imageSearchQuery)) ?? ""
        imageDataURL = try? c.decodeIfPresent(String.self, forKey: .imageDataURL)
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    var imageDataURL: String? = nil
}

struct YouTubeVideo: Identifiable {
    let id = UUID()
    let title: String
    let videoURL: String
    let thumbnailURL: String?
}

struct ProductItem: Identifiable {
    let id = UUID()
    let name: String
    let price: String
    let store: String
    let rating: Double
    let reviews: Int
    let distanceMi: Double?
    let thumbnail: String
    let url: String
}

struct AppLanguage: Identifiable {
    let id: String
    let name: String
    let flag: String

    static let all: [AppLanguage] = [
        AppLanguage(id: "en", name: "English", flag: "🇺🇸"),
        AppLanguage(id: "es", name: "Español", flag: "🇪🇸"),
        AppLanguage(id: "vi", name: "Tiếng Việt", flag: "🇻🇳"),
        AppLanguage(id: "fr", name: "Français", flag: "🇫🇷"),
    ]
}

// MARK: - Helpers

extension Data {
    /// Convert a `data:image/...;base64,...` URL to a UIImage
    static func fromDataURL(_ dataURL: String) -> UIImage? {
        guard dataURL.hasPrefix("data:"),
              let commaIdx = dataURL.firstIndex(of: ",") else { return nil }
        let b64 = String(dataURL[dataURL.index(after: commaIdx)...])
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}
