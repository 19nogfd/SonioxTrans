import Foundation
import SwiftUI

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var lines: [TranscriptLine] = []
    @Published private(set) var dayNames: [String: String] = [:]

    private struct Archive: Codable {
        var lines: [TranscriptLine]
        var dayNames: [String: String]
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SonioxTrans", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.json")
    }

    init() { load() }

    func dayKey(_ date: Date) -> String { Self.dayFormatter.string(from: date) }

    var days: [String] {
        Array(Set(lines.map { dayKey($0.timestamp) })).sorted(by: >)
    }

    func entries(on day: String) -> [TranscriptLine] {
        lines.filter { dayKey($0.timestamp) == day }.sorted { $0.timestamp < $1.timestamp }
    }

    func append(original: String, translation: String) {
        let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        lines.append(TranscriptLine(original: source,
                                    translation: translation.trimmingCharacters(in: .whitespacesAndNewlines)))
        save()
    }

    func rename(day: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { dayNames.removeValue(forKey: day) } else { dayNames[day] = clean }
        save()
    }

    func title(for day: String) -> String { dayNames[day] ?? day }

    func exportMarkdown(day: String) throws -> URL {
        var text = "# \(title(for: day))\n\n"
        let time = DateFormatter()
        time.timeStyle = .short
        for line in entries(on: day) {
            text += "## \(time.string(from: line.timestamp))\n\n"
            text += "**日语原文**\n\n\(line.original)\n\n"
            text += "**中文翻译**\n\n\(line.translation)\n\n"
        }
        let safeName = title(for: day).replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(Archive.self, from: data) else { return }
        lines = archive.lines
        dayNames = archive.dayNames
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Archive(lines: lines, dayNames: dayNames)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
