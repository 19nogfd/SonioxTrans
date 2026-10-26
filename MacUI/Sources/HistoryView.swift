import SwiftUI

struct HistoryView: View {
    @ObservedObject var history = HistoryStore.shared
    @State private var selectedDay: Date?
    @State private var recordName = ""

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var activeDay: Date? {
        if let selectedDay, history.availableDays.contains(selectedDay) { return selectedDay }
        return history.availableDays.first
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("历史日期").font(.headline).padding(.horizontal, 12).padding(.top, 12)
                List(history.availableDays, id: \.self, selection: $selectedDay) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(history.title(for: day)).lineLimit(1)
                        Text(dayFormatter.string(from: day))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .tag(day)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 210)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    if let day = activeDay {
                        TextField("记录名称", text: $recordName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 220, maxWidth: 420)
                            .onSubmit { saveRecordName(day) }
                        Button("保存名称") { saveRecordName(day) }
                        Text(dayFormatter.string(from: day))
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("对话记录").font(.title3).bold()
                    }
                    Spacer()
                    Button("导出当天记录") {
                        if let day = activeDay { history.export(day: day) }
                    }
                    .disabled(activeDay == nil)
                }
                .padding()

                Divider()

                HStack(spacing: 0) {
                    Text("听到的日语原文").frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    Text("中文翻译").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.headline)
                .padding(.horizontal, 18)
                .frame(height: 42)

                Divider()

                if let day = activeDay {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(history.entries(on: day)) { item in
                                HistoryRow(item: item, timeFormatter: timeFormatter)
                                Divider()
                            }
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "text.bubble").font(.system(size: 32))
                        Text("还没有保存的对话")
                        Text("最终译文出现后会自动按日期保存")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .onAppear {
            if selectedDay == nil { selectedDay = history.availableDays.first }
            if let day = activeDay { recordName = history.title(for: day) }
        }
        .onChange(of: activeDay) { _, day in
            recordName = day.map(history.title) ?? ""
        }
    }

    private func saveRecordName(_ day: Date) {
        history.rename(day: day, to: recordName)
        recordName = history.title(for: day)
    }
}

private struct HistoryRow: View {
    let item: ConversationEntry
    let timeFormatter: DateFormatter

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            conversationCell(text: item.source)
            Divider()
            conversationCell(text: item.translated)
        }
        .background(Color.primary.opacity(0.025))
    }

    private func conversationCell(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(timeFormatter.string(from: item.timestamp))
                Text(item.speaker == "them" ? "系统音频" : "麦克风")
            }
            .font(.caption).foregroundColor(.secondary)
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
