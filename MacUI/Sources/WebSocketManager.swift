import AppKit
import Foundation
import Combine

struct WSMessage: Codable {
    var type: String?
    var speaker: String?
    var source: String?
    var translated: String?
    var is_final: Bool?
    var message: String?
    var value: Double?
}

class WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()
    
    // Published states for SwiftUI bindings
    @Published var isConnected = false
    @Published var statusMessage = "就绪"
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading = false
    
    @Published var mySourceText = ""
    @Published var myTranslatedText = ""
    @Published var theirSourceText = ""
    @Published var theirTranslatedText = ""
    
    @Published var isUIUnlocked = false {
        didSet {
            DispatchQueue.main.async {
                for window in NSApplication.shared.windows where window is SubtitleOverlayWindow {
                    // The overlay always accepts scrolling, selection and copy.
                    // Unlocking only controls whether its background can be dragged.
                    window.ignoresMouseEvents = false
                    window.isMovableByWindowBackground = self.isUIUnlocked
                }
            }
        }
    }
    
    @Published var micEnabled = true {
        didSet { sendCommand(action: "update_settings", params: ["mic_enabled": micEnabled]) }
    }
    @Published var sysEnabled = false {
        didSet { sendCommand(action: "update_settings", params: ["sys_enabled": sysEnabled]) }
    }
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var retryWork: DispatchWorkItem?
    private var handshakeWork: DispatchWorkItem?
    private var connectionID = 0
    private var retryCount = 0
    private var shouldReconnect = false

    // connection-retry-v1: serialize connection state on the main queue.
    func connect() {
        DispatchQueue.main.async {
            self.shouldReconnect = true
            self.retryCount = 0
            self.openConnection()
        }
    }

    private func openConnection() {
        guard shouldReconnect else { return }
        retryWork?.cancel()
        handshakeWork?.cancel()
        pingTimer?.invalidate()
        connectionID += 1
        let id = connectionID
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        statusMessage = "正在连接本机后端…"
        var request = URLRequest(url: URL(string: "ws://127.0.0.1:8766")!)
        request.timeoutInterval = 5
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        receiveMessage(task, id: id)

        let timeout = DispatchWorkItem { [weak self] in
            self?.connectionFailed(id: id, reason: "握手超时")
        }
        handshakeWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: timeout)
        task.sendPing { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self, self.connectionID == id else { return }
                if let error = error {
                    self.connectionFailed(id: id, reason: error.localizedDescription)
                    return
                }
                self.handshakeWork?.cancel()
                self.handshakeWork = nil
                self.isConnected = true
                self.retryCount = 0
                self.statusMessage = "连接成功"
                self.sendCommand(action: "status")
                self.pingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                    task.sendPing { error in
                        if let error = error {
                            DispatchQueue.main.async {
                                self?.connectionFailed(id: id, reason: error.localizedDescription)
                            }
                        }
                    }
                }
            }
        }
    }

    private func connectionFailed(id: Int, reason: String) {
        guard id == connectionID else { return }
        connectionID += 1 // Ignore callbacks from the failed connection.
        let retryID = connectionID
        handshakeWork?.cancel()
        pingTimer?.invalidate()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        NSLog("Backend WebSocket connection failed: %@", reason)
        guard shouldReconnect else { return }
        guard retryCount < 10 else {
            statusMessage = "无法连接本机后端：\(reason)。点击开始翻译可重试连接"
            return
        }
        retryCount += 1
        let delay = min(Double(retryCount), 5)
        statusMessage = "等待本机后端，\(Int(delay)) 秒后重连（\(retryCount)/10）"
        let retry = DispatchWorkItem { [weak self] in
            guard let self = self, self.connectionID == retryID else { return }
            self.openConnection()
        }
        retryWork = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: retry)
    }

    func disconnect() {
        DispatchQueue.main.async {
            self.shouldReconnect = false
            self.connectionID += 1
            self.retryWork?.cancel()
            self.handshakeWork?.cancel()
            self.pingTimer?.invalidate()
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil
            self.isConnected = false
            self.statusMessage = "已断开连接"
        }
    }

    private func receiveMessage(_ task: URLSessionWebSocketTask, id: Int) {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.connectionID == id else { return }
                switch result {
                case .failure(let error):
                    self.connectionFailed(id: id, reason: error.localizedDescription)
                case .success(let message):
                    switch message {
                    case .string(let text): self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default: break
                    }
                    self.receiveMessage(task, id: id)
                }
            }
        }
    }

    private func handleMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        do {
            let msg = try JSONDecoder().decode(WSMessage.self, from: data)
            DispatchQueue.main.async {
                if msg.type == "status" {
                    self.statusMessage = msg.message ?? ""
                    // 当状态包含 "准备下载" 或 "正在下载" 时开启下载模式，完成初始化则关闭
                    if self.statusMessage.contains("下载") {
                        self.isDownloading = true
                    } else if self.statusMessage.contains("准备完毕") || self.statusMessage.contains("翻译中") {
                        self.isDownloading = false
                        self.downloadProgress = 0
                    }
                } else if msg.type == "progress" {
                    self.downloadProgress = msg.value ?? 0
                    self.isDownloading = true
                } else if msg.type == "subtitle" {
                    if msg.speaker == "me" {
                        self.mySourceText = msg.source ?? ""
                        self.myTranslatedText = msg.translated ?? ""
                    } else if msg.speaker == "them" {
                        self.theirSourceText = msg.source ?? ""
                        self.theirTranslatedText = msg.translated ?? ""
                    }
                    if msg.is_final == true {
                        HistoryStore.shared.append(speaker: msg.speaker ?? "",
                                                   source: msg.source ?? "",
                                                   translated: msg.translated ?? "")
                    }
                }
            }
        } catch {
            print("Failed to decode JSON: \(error)")
        }
    }
    
    func sendCommand(action: String, params: [String: Any] = [:]) {
        DispatchQueue.main.async {
            guard self.isConnected, let task = self.webSocketTask else {
                if action == "start" {
                    self.statusMessage = "尚未连接；连接就绪后请再次点击开始翻译"
                    self.connect()
                } else if action == "stop" {
                    self.statusMessage = "未连接后端，停止指令未发送"
                }
                return
            }
            let msg: [String: Any] = ["action": action, "params": params]
            guard let data = try? JSONSerialization.data(withJSONObject: msg),
                  let text = String(data: data, encoding: .utf8) else { return }
            let id = self.connectionID
            task.send(.string(text)) { error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.connectionFailed(id: id, reason: error.localizedDescription)
                    }
                }
            }
        }
    }
}
