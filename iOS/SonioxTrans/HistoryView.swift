import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var history: HistoryStore
    @State private var search = ""
    @State private var renamedDay: String?
    @State private var editedName = ""

    private var filteredDays: [String] {
        guard !search.isEmpty else { return history.days }
        return history.days.filter { day in
            history.title(for: day).localizedCaseInsensitiveContains(search) ||
            history.entries(on: day).contains {
                $0.original.localizedCaseInsensitiveContains(search) ||
                $0.translation.localizedCaseInsensitiveContains(search)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredDays.isEmpty {
                    ContentUnavailableView("没有历史记录", systemImage: "clock")
                }
                ForEach(filteredDays, id: \.self) { day in
                    Section {
                        ForEach(history.entries(on: day)) { line in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(line.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                                Text(line.original).textSelection(.enabled)
                                Text(line.translation).fontWeight(.semibold).textSelection(.enabled)
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        HStack {
                            Text(history.title(for: day))
                            Spacer()
                            Button { renamedDay = day; editedName = history.title(for: day) } label: {
                                Image(systemName: "pencil")
                            }
                            if let url = try? history.exportMarkdown(day: day) {
                                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索记录、原文或译文")
            .navigationTitle("历史记录")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .alert("修改记录名称", isPresented: Binding(
                get: { renamedDay != nil },
                set: { if !$0 { renamedDay = nil } }
            )) {
                TextField("例如：经济学第 3 讲", text: $editedName)
                Button("保存") {
                    if let day = renamedDay { history.rename(day: day, to: editedName) }
                    renamedDay = nil
                }
                Button("取消", role: .cancel) { renamedDay = nil }
            }
        }
    }
}
