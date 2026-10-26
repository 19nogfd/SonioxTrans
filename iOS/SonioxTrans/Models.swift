import Foundation

struct TranscriptLine: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let original: String
    let translation: String

    init(id: UUID = UUID(), timestamp: Date = Date(), original: String, translation: String) {
        self.id = id
        self.timestamp = timestamp
        self.original = original
        self.translation = translation
    }
}

enum SonioxRegion: String, CaseIterable, Identifiable {
    case us
    case jp

    var id: String { rawValue }
    var title: String { self == .jp ? "日本" : "美国 / 默认" }
    var websocketURL: URL {
        URL(string: self == .jp
            ? "wss://stt-rt.jp.soniox.com/transcribe-websocket"
            : "wss://stt-rt.soniox.com/transcribe-websocket")!
    }
}

struct TokenAccumulator {
    private(set) var original = ""
    private(set) var translation = ""

    mutating func consume(_ tokens: [[String: Any]]) -> (String, String, Bool) {
        var temporaryOriginal = ""
        var temporaryTranslation = ""
        var endpoint = false
        for token in tokens {
            guard let text = token["text"] as? String else { continue }
            let final = token["is_final"] as? Bool == true
            if text == "<end>" || text == "<fin>" {
                endpoint = endpoint || final
                continue
            }
            let translated = token["translation_status"] as? String == "translation"
            if final {
                if translated { translation += text } else { original += text }
            } else if translated {
                temporaryTranslation += text
            } else {
                temporaryOriginal += text
            }
        }
        return (original + temporaryOriginal, translation + temporaryTranslation, endpoint)
    }

    mutating func take(previewOriginal: String, previewTranslation: String) -> (String, String) {
        let result = (previewOriginal.trimmingCharacters(in: .whitespacesAndNewlines),
                      previewTranslation.trimmingCharacters(in: .whitespacesAndNewlines))
        original = ""
        translation = ""
        return result
    }
}
