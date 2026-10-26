import AVFoundation
import Foundation

@MainActor
final class TranslationSession: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "等待开始"
    @Published var currentOriginal = ""
    @Published var currentTranslation = ""
    @Published private(set) var sessionLines: [TranscriptLine] = []

    weak var history: HistoryStore?
    private let service = SonioxService()
    private var capture: MicrophoneCapture?
    private var generation = UUID()

    func start(apiKey: String, region: SonioxRegion) async {
        guard !isRunning else { return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { status = "请输入 Soniox API Key"; return }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { status = CaptureError.permissionDenied.localizedDescription; return }

        generation = UUID()
        let activeGeneration = generation
        isRunning = true
        status = "正在连接 Soniox \(region.title)节点…"
        currentOriginal = ""
        currentTranslation = ""
        sessionLines = []
        do {
            try await service.connect(apiKey: key, region: region) { [self] original, translation in
                await handleUpdate(original: original,
                                   translation: translation,
                                   generation: activeGeneration)
            } final: { [self] original, translation in
                await handleFinal(original: original,
                                  translation: translation,
                                  generation: activeGeneration)
            }

            let microphone = MicrophoneCapture()
            try microphone.start { [service] data in
                Task {
                    try? await service.sendAudio(data)
                }
            }
            capture = microphone
            status = "实时翻译中：日语 → 中文"
        } catch {
            status = "启动失败：\(error.localizedDescription)"
            await stop()
        }
    }

    func stop() async {
        generation = UUID()
        capture?.stop()
        capture = nil
        await service.stop()
        isRunning = false
        if !status.contains("失败") && !status.contains("中断") && !status.contains("Soniox") {
            status = "已停止"
        }
    }

    private func handleUpdate(original: String, translation: String, generation activeGeneration: UUID) async {
        guard generation == activeGeneration else { return }
        if original.isEmpty, translation.hasPrefix("Soniox ") || translation.hasPrefix("连接中断") {
            status = translation
            await stop()
        } else {
            currentOriginal = original
            currentTranslation = translation.isEmpty ? "翻译中…" : translation
        }
    }

    private func handleFinal(original: String, translation: String, generation activeGeneration: UUID) {
        guard generation == activeGeneration else { return }
        let line = TranscriptLine(original: original,
                                  translation: translation.isEmpty ? "（未返回译文）" : translation)
        sessionLines.append(line)
        history?.append(original: line.original, translation: line.translation)
        currentOriginal = ""
        currentTranslation = ""
    }
}
