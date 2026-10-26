import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var wsManager = WebSocketManager.shared
    @AppStorage("sonioxApiKey") private var apiKey = ""
    @AppStorage("sonioxRegion") private var region = "jp"
    @AppStorage("subtitleDisplayMode") private var displayMode = "overlay"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("日语 → 中文字幕").font(.headline)
            Text("Soniox stt-rt-v5 · 原文与译文一体输出")
                .font(.caption).foregroundColor(.secondary)
            SecureField("Soniox API Key", text: $apiKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Picker("Soniox 项目地域", selection: $region) {
                Text("日本（推荐）").tag("jp")
                Text("美国 / 默认").tag("us")
            }
            Text("开始后会将音频发送到 Soniox。每条音频流约 $0.18/小时；同时启用两种输入会产生两条流。")
                .font(.caption).foregroundColor(.secondary)
            Divider()
            Toggle("麦克风：教授或你说的日语", isOn: $wsManager.micEnabled)
            Toggle("BlackHole：电脑播放的日语", isOn: $wsManager.sysEnabled)
            Text("建议先单独测试一种输入。更换输入或地域后，请停止并重新开始。")
                .font(.caption).foregroundColor(.secondary)
            Picker("字幕显示方式", selection: $displayMode) {
                Text("屏幕悬浮字幕").tag("overlay")
                Text("实时字幕窗口").tag("window")
            }
            .pickerStyle(.segmented)
            .onChange(of: displayMode) { _, newValue in
                NotificationCenter.default.post(name: .subtitleDisplayModeChanged,
                                                object: newValue)
            }
            if displayMode == "overlay" {
                Toggle("解锁悬浮框位置", isOn: $wsManager.isUIUnlocked)
            } else {
                Button("显示实时字幕窗口") {
                    NotificationCenter.default.post(name: .showLiveSubtitleWindow, object: nil)
                }
            }
            HStack {
                Button("开始翻译") {
                    wsManager.mySourceText = ""
                    wsManager.myTranslatedText = ""
                    wsManager.theirSourceText = ""
                    wsManager.theirTranslatedText = ""
                    wsManager.sendCommand(action: "start", params: [
                        "api_key": apiKey,
                        "region": region,
                        "mic_enabled": wsManager.micEnabled,
                        "sys_enabled": wsManager.sysEnabled
                    ])
                }
                .disabled(!wsManager.isConnected || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("停止") { wsManager.sendCommand(action: "stop") }
                    .disabled(!wsManager.isConnected)
            }
            Text("使用 Soniox 语义断句，短暂停顿会尽量保留在同一句中。")
                .font(.caption).foregroundColor(.secondary)
            Button("打开对话记录") {
                NotificationCenter.default.post(name: .showConversationHistory, object: nil)
            }
            Text("最终原文和译文会自动按日期保存。")
                .font(.caption).foregroundColor(.secondary)
            Divider()
            HStack(alignment: .top) {
                Circle().fill(wsManager.isConnected ? Color.green : Color.red)
                    .frame(width: 9, height: 9).padding(.top, 3)
                Text(wsManager.statusMessage).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("退出应用") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(20)
    }
}

extension Notification.Name {
    static let showConversationHistory = Notification.Name("showConversationHistory")
    static let subtitleDisplayModeChanged = Notification.Name("subtitleDisplayModeChanged")
    static let showLiveSubtitleWindow = Notification.Name("showLiveSubtitleWindow")
}
