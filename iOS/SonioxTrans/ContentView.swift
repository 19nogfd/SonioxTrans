import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: TranslationSession
    @EnvironmentObject private var history: HistoryStore
    @State private var apiKey = ""
    @State private var region: SonioxRegion = .us
    @State private var showsHistory = false
    @State private var followsLatest = true
    @State private var keyStatus = ""

    private var visibleLines: [TranscriptLine] {
        var result = session.sessionLines
        let source = session.currentOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !source.isEmpty {
            result.append(TranscriptLine(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                         timestamp: Date(), original: source,
                                         translation: session.currentTranslation))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectionPanel
                Divider()
                transcriptHeader
                Divider()
                transcriptList
                Divider()
                controlBar
            }
            .navigationTitle("SonioxTrans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsHistory = true } label: {
                        Label("历史记录", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showsHistory) { HistoryView() }
            .onAppear {
                if apiKey.isEmpty { apiKey = SecureKeyStore.load() }
            }
        }
    }

    private var connectionPanel: some View {
        VStack(spacing: 10) {
            SecureField("输入一次 Soniox API Key", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .padding(11)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            Picker("项目地域", selection: $region) {
                ForEach(SonioxRegion.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(session.isRunning)

            HStack(spacing: 8) {
                Circle().fill(session.isRunning ? Color.green : Color.secondary)
                    .frame(width: 9, height: 9)
                Text(session.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text(apiKey.isEmpty ? "API Key 将安全保存在本机 Keychain。" : "API Key 已由本机 Keychain 安全保管。")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if !apiKey.isEmpty {
                    Button("清除 Key", role: .destructive) {
                        SecureKeyStore.clear()
                        apiKey = ""
                        keyStatus = "已清除"
                    }
                    .font(.caption2)
                    .disabled(session.isRunning)
                }
            }
            if !keyStatus.isEmpty {
                Text(keyStatus).font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal).padding(.vertical, 12)
    }

    private var transcriptHeader: some View {
        HStack(spacing: 0) {
            Text("听到的日语原文")
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Text("中文翻译")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        }
        .font(.subheadline.bold()).padding(.horizontal).frame(height: 40)
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if visibleLines.isEmpty {
                        ContentUnavailableView("等待日语语音", systemImage: "waveform",
                                               description: Text("点击开始翻译后对着麦克风说话"))
                            .padding(.top, 55)
                    }
                    ForEach(visibleLines) { line in
                        TranscriptRow(line: line,
                                      isProcessing: line.id.uuidString.hasSuffix("000000000001"))
                        Divider()
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onChange(of: visibleLines) { _, _ in
                if followsLatest {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    do {
                        try SecureKeyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        keyStatus = "API Key 已保存"
                        Task { await session.start(apiKey: apiKey, region: region) }
                    } catch {
                        keyStatus = error.localizedDescription
                    }
                } label: {
                    Label("开始翻译", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isRunning || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive) {
                    Task { await session.stop() }
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!session.isRunning)
            }
            Toggle("自动跟随最新字幕", isOn: $followsLatest)
                .font(.caption).toggleStyle(.switch)
        }
        .padding()
    }
}

private struct TranscriptRow: View {
    let line: TranscriptLine
    let isProcessing: Bool
    @State private var highlighted = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(line.original, weight: .regular)
            Divider()
            cell(line.translation.isEmpty ? "翻译中…" : line.translation, weight: .semibold)
        }
        .background(highlighted ? Color.accentColor.opacity(0.12) : Color.clear)
        .contextMenu {
            Button("复制原文") { UIPasteboard.general.string = line.original }
            Button("复制译文") { UIPasteboard.general.string = line.translation }
        }
        .onTapGesture { withAnimation { highlighted.toggle() } }
    }

    private func cell(_ text: String, weight: Font.Weight) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if isProcessing { Text("处理中").font(.caption2).foregroundStyle(.orange) }
            Text(text).font(.body.weight(weight)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
