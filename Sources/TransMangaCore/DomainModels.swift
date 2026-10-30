import Foundation
import SwiftUI
import CoreGraphics

extension Notification.Name {
    static let transMangaTranslate = Notification.Name("transMangaTranslate")
    static let transMangaToggleClickThrough = Notification.Name("transMangaToggleClickThrough")
    static let transMangaToggleAutoWatch = Notification.Name("transMangaToggleAutoWatch")
    static let transMangaToggleCards = Notification.Name("transMangaToggleCards")
}

enum AppTab: Int, CaseIterable, Identifiable {
    case home = 0
    case log = 1
    case glossary = 2

    var id: Int { rawValue }

    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .log: return "text.bubble.fill"
        case .glossary: return "character.book.closed.fill"
        }
    }
}

enum TranslationError: LocalizedError, Equatable {
    case invalidEndpointURL
    case serverUnreachable
    case modelNotInstalled(String)
    case requestTimedOut(String)
    case httpStatus(Int)
    case emptyOrInvalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpointURL:
            return "Invalid local Ollama endpoint URL."
        case .serverUnreachable:
            return "Cannot reach Ollama on 127.0.0.1:11434. Make sure Ollama is installed."
        case .modelNotInstalled(let model):
            return "Model '\(model)' is not installed. Run 'ollama pull \(model)' in Terminal."
        case .requestTimedOut(let model):
            return "Translation timed out waiting for '\(model)'. Try again once the model finishes loading."
        case .httpStatus(let code):
            return "Ollama returned HTTP \(code)."
        case .emptyOrInvalidResponse:
            return "Ollama returned an empty translation response."
        }
    }
}

struct OrientedLineMask: Identifiable {
    let id = UUID()
    let centerX: CGFloat
    let centerY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotationRadians: Double
    let sampleBox: CGRect
    var backgroundColor: Color = .white
}

struct OverlayTranslationBox: Identifiable {
    let id: UUID
    let index: Int
    var text: String
    let boundingBox: CGRect
    let centerX: CGFloat
    let centerY: CGFloat
    let orientedWidth: CGFloat
    let orientedHeight: CGFloat
    let rotationRadians: Double
    let lineMasks: [OrientedLineMask]
    let backgroundColor: Color
    let textColor: Color
    var isManualSelection: Bool = false
}

struct RecognizedBlock: Identifiable {
    var id = UUID()
    let index: Int
    let japaneseText: String
    var englishText: String
    let boundingBox: CGRect
    let centerX: CGFloat
    let centerY: CGFloat
    let orientedWidth: CGFloat
    let orientedHeight: CGFloat
    let rotationRadians: Double
    var lineMasks: [OrientedLineMask]
    var breakdownText: String? = nil
    var isBreakingDown: Bool = false
}

struct GlossaryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var japanese: String
    var english: String
}
