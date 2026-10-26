import Foundation

actor SonioxService {
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var accumulator = TokenAccumulator()

    func connect(apiKey: String, region: SonioxRegion,
                 update: @escaping @Sendable (String, String) async -> Void,
                 final: @escaping @Sendable (String, String) async -> Void) async throws {
        var request = URLRequest(url: region.websocketURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        task.resume()

        let configuration: [String: Any] = [
            "model": "stt-rt-v5",
            "audio_format": "pcm_s16le",
            "sample_rate": 16_000,
            "num_channels": 1,
            "language_hints": ["ja"],
            "language_hints_strict": true,
            "enable_language_identification": true,
            "enable_endpoint_detection": true,
            "endpoint_sensitivity": -0.25,
            "endpoint_latency_adjustment_level": 0,
            "max_endpoint_delay_ms": 3_000,
            "translation": ["type": "one_way", "target_language": "zh"],
            "client_reference_id": "sonioxtrans-ios"
        ]
        let data = try JSONSerialization.data(withJSONObject: configuration)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(update: update, final: final)
        }
    }

    func sendAudio(_ data: Data) async throws {
        guard let socket else { throw SessionError.disconnected }
        try await socket.send(.data(data))
    }

    func stop() async {
        if let socket {
            try? await socket.send(.data(Data()))
            socket.cancel(with: .normalClosure, reason: nil)
        }
        receiveTask?.cancel()
        receiveTask = nil
        socket = nil
        accumulator = TokenAccumulator()
    }

    private func receiveLoop(update: @escaping @Sendable (String, String) async -> Void,
                             final: @escaping @Sendable (String, String) async -> Void) async {
        do {
            while !Task.isCancelled, let socket {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let value): data = value
                @unknown default: continue
                }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let error = object["error_message"] as? String {
                    let type = object["error_type"] as? String ?? "service_error"
                    await update("", "Soniox \(type)：\(error)")
                    return
                }
                guard let tokens = object["tokens"] as? [[String: Any]] else { continue }
                let result = accumulator.consume(tokens)
                if !result.0.isEmpty || !result.1.isEmpty { await update(result.0, result.1) }
                if result.2 {
                    let completed = accumulator.take(previewOriginal: result.0, previewTranslation: result.1)
                    if !completed.0.isEmpty { await final(completed.0, completed.1) }
                }
            }
        } catch {
            if !Task.isCancelled {
                await update("", "连接中断：\(error.localizedDescription)")
            }
        }
    }
}

enum SessionError: LocalizedError {
    case disconnected
    var errorDescription: String? { "Soniox 尚未连接" }
}
