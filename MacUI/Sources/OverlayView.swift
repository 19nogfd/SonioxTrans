import SwiftUI

private struct TranscriptItem: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let speaker: String
    let source: String
    let translated: String
    let isFinal: Bool
}

private func transcriptItems(history: HistoryStore, manager: WebSocketManager) -> [TranscriptItem] {
    var items = history.entries(on: Date()).map {
        TranscriptItem(id: "history-\($0.id.uuidString)", timestamp: $0.timestamp,
                       speaker: $0.speaker, source: $0.source,
                       translated: $0.translated, isFinal: true)
    }

    func appendCurrent(speaker: String, source: String, translated: String) {
        let original = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }
        let translation = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        let alreadySaved = items.last(where: { $0.speaker == speaker }).map {
            $0.source == original && $0.translated == translation
        } ?? false
        guard !alreadySaved else { return }
        items.append(TranscriptItem(id: "live-\(speaker)", timestamp: Date(), speaker: speaker,
                                    source: original,
                                    translated: translation.isEmpty ? "等待翻译…" : translation,
                                    isFinal: false))
    }

    appendCurrent(speaker: "them", source: manager.theirSourceText,
                  translated: manager.theirTranslatedText)
    appendCurrent(speaker: "me", source: manager.mySourceText,
                  translated: manager.myTranslatedText)
    return items
}

private struct TranscriptHistoryGrid: View {
    let items: [TranscriptItem]
    let darkStyle: Bool
    @State private var hoveredSourceID: String?
    @State private var followsLatest = true

    private var lastID: String { items.last?.id ?? "empty" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("听到的日语原文")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                Divider()
                Text("中文翻译")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            .font(.headline)
            .foregroundColor(darkStyle ? .white.opacity(0.9) : .primary)
            .frame(height: 42)

            Divider().overlay(darkStyle ? Color.white.opacity(0.2) : Color.clear)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        if items.isEmpty {
                            Text("等待语音输入…")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(36)
                        } else {
                            ForEach(items) { item in
                                TranscriptRow(item: item, darkStyle: darkStyle,
                                              hoveredSourceID: $hoveredSourceID)
                                Divider().overlay(darkStyle ? Color.white.opacity(0.12) : Color.clear)
                            }
                        }
                        Color.clear.frame(height: 1).id("transcript-bottom")
                    }
                }
                .onAppear {
                    if followsLatest { proxy.scrollTo("transcript-bottom", anchor: .bottom) }
                }
                .onChange(of: lastID) { _, _ in
                    if followsLatest {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo("transcript-bottom", anchor: .bottom)
                        }
                    }
                }
            }

            Divider().overlay(darkStyle ? Color.white.opacity(0.2) : Color.clear)
            HStack {
                Text("共 \(items.filter(\.isFinal).count) 条已保存对话")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Toggle("跟随最新", isOn: $followsLatest)
                    .toggleStyle(.checkbox).font(.caption)
                    .foregroundColor(darkStyle ? .white.opacity(0.8) : .primary)
            }
            .padding(.horizontal, 14).frame(height: 34)
        }
    }
}

private struct TranscriptRow: View {
    let item: TranscriptItem
    let darkStyle: Bool
    @Binding var hoveredSourceID: String?

    private var highlighted: Bool { hoveredSourceID == item.id }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            transcriptCell(text: item.source, isSource: true)
                .contentShape(Rectangle())
                .onHover { inside in
                    hoveredSourceID = inside ? item.id : nil
                }
            Divider().overlay(darkStyle ? Color.white.opacity(0.16) : Color.clear)
            transcriptCell(text: item.translated, isSource: false)
        }
        .background(rowBackground)
        .animation(.easeInOut(duration: 0.12), value: highlighted)
    }

    private var rowBackground: Color {
        if highlighted {
            return darkStyle ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.14)
        }
        return darkStyle ? Color.white.opacity(0.035) : Color.primary.opacity(0.025)
    }

    private func transcriptCell(text: String, isSource: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(item.speaker == "them" ? Color.blue : Color.green)
                    .frame(width: 7, height: 7)
                Text(item.speaker == "them" ? "系统音频" : "麦克风")
                Text(item.timestamp, style: .time)
                if !item.isFinal { Text("处理中") }
            }
            .font(.caption2).foregroundColor(.secondary)

            Text(text)
                .font(.system(size: isSource ? 16 : 18,
                              weight: isSource ? .regular : .semibold))
                .foregroundColor(darkStyle ? .white : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct MergedOverlayView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject private var history = HistoryStore.shared

    private var items: [TranscriptItem] {
        transcriptItems(history: history, manager: wsManager)
    }

    var body: some View {
        VStack(spacing: 6) {
            if wsManager.isUIUnlocked {
                Text("拖拽空白处移动字幕框")
                    .font(.caption).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.orange.opacity(0.9)).cornerRadius(6)
            }
            TranscriptHistoryGrid(items: items, darkStyle: true)
                .background(Color.black.opacity(0.76))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.13), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color.clear)
    }
}

struct LiveTranscriptView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject private var history = HistoryStore.shared
    @AppStorage("sonioxApiKey") private var apiKey = ""
    @AppStorage("sonioxRegion") private var region = "jp"

    private var items: [TranscriptItem] {
        transcriptItems(history: history, manager: wsManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(wsManager.isConnected ? Color.green : Color.red)
                    .frame(width: 9, height: 9)
                Text(wsManager.statusMessage).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(14)
            Divider()
            TranscriptHistoryGrid(items: items, darkStyle: false)
            Divider()
            HStack(spacing: 12) {
                Button("开始翻译") { startTranslation() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!wsManager.isConnected ||
                              apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("停止") { wsManager.sendCommand(action: "stop") }
                    .disabled(!wsManager.isConnected)
                Button("历史记录") {
                    NotificationCenter.default.post(name: .showConversationHistory, object: nil)
                }
                Spacer()
                Text("输入设置请在菜单栏中修改")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(minWidth: 760, minHeight: 440)
    }

    private func startTranslation() {
        wsManager.mySourceText = ""
        wsManager.myTranslatedText = ""
        wsManager.theirSourceText = ""
        wsManager.theirTranslatedText = ""
        wsManager.sendCommand(action: "start", params: [
            "api_key": apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            "region": region,
            "mic_enabled": wsManager.micEnabled,
            "sys_enabled": wsManager.sysEnabled
        ])
    }
}
