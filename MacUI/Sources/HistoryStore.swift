import AppKit
import Foundation

struct ConversationEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let speaker: String
    let source: String
    let translated: String
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [ConversationEntry] = []
    @Published private(set) var recordTitles: [String: String] = [:]

    private let calendar = Calendar.current
    private let fileURL: URL
    private let titlesURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first!
        let directory = support.appendingPathComponent("SonioxTrans", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("conversations.json")
        titlesURL = directory.appendingPathComponent("conversation-titles.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    var availableDays: [Date] {
        let days = Set(entries.map { calendar.startOfDay(for: $0.timestamp) })
        return days.sorted(by: >)
    }

    func entries(on day: Date) -> [ConversationEntry] {
        entries.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func title(for day: Date) -> String {
        recordTitles[dayKey(day)] ?? defaultTitle(for: day)
    }

    func defaultTitle(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: day)
    }

    func rename(day: Date, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = dayKey(day)
        if trimmed.isEmpty || trimmed == defaultTitle(for: day) {
            recordTitles.removeValue(forKey: key)
        } else {
            recordTitles[key] = String(trimmed.prefix(80))
        }
        saveTitles()
    }

    func append(speaker: String, source: String, translated: String) {
        let original = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !translation.isEmpty else { return }

        // The backend sends progress subtitles before the final translation.
        guard translation != "识别中…", translation != "正在翻译…", translation != "翻译中…",
              !translation.hasPrefix("翻译失败：") else { return }

        if let last = entries.last,
           last.speaker == speaker,
           last.source == original,
           last.translated == translation,
           Date().timeIntervalSince(last.timestamp) < 10 {
            return
        }

        entries.append(ConversationEntry(id: UUID(), timestamp: Date(), speaker: speaker,
                                         source: original, translated: translation))
        save()
    }

    func export(day: Date) {
        let selected = entries(on: day)
        guard !selected.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        let text = selected.map { item in
            let speaker = item.speaker == "them" ? "系统音频" : "麦克风"
            return "[\(timeFormatter.string(from: item.timestamp))] \(speaker)\n原文：\(item.source)\n译文：\(item.translated)"
        }.joined(separator: "\n\n") + "\n"

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let safeTitle = title(for: day)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(safeTitle)-\(dateFormatter.string(from: day)).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "保存对话失败"
                alert.runModal()
            }
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([ConversationEntry].self, from: data) {
            entries = decoded.sorted { $0.timestamp < $1.timestamp }
        }
        if let data = try? Data(contentsOf: titlesURL),
           let decoded = try? decoder.decode([String: String].self, from: data) {
            recordTitles = decoded
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save conversation history: %@", error.localizedDescription)
        }
    }

    private func saveTitles() {
        do {
            let data = try encoder.encode(recordTitles)
            try data.write(to: titlesURL, options: .atomic)
        } catch {
            NSLog("Failed to save conversation titles: %@", error.localizedDescription)
        }
    }

    private func dayKey(_ day: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
