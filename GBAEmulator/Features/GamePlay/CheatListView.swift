import SwiftUI

struct CheatListView: View {
    @ObservedObject var viewModel: GamePlayViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Cheat?
    @State private var pendingDeletion: Cheat?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if viewModel.cheats.isEmpty {
                        Text("暂无金手指，点击 + 添加代码。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.cheats) { cheat in
                        HStack {
                            Button {
                                editing = cheat
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cheat.name).foregroundStyle(.primary)
                                    Text(cheat.format.title).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("编辑 \(cheat.name)")
                            Toggle(cheat.name, isOn: Binding(
                                get: { cheat.isEnabled },
                                set: { enabled in
                                    var entries = viewModel.cheats
                                    guard let index = entries.firstIndex(where: { $0.id == cheat.id }) else { return }
                                    entries[index].isEnabled = enabled
                                    commit(entries)
                                }
                            ))
                            .labelsHidden()
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { pendingDeletion = cheat }
                            Button("编辑") { editing = cheat }.tint(.blue)
                        }
                        .contextMenu {
                            Button("编辑") { editing = cheat }
                            Button("删除", role: .destructive) { pendingDeletion = cheat }
                        }
                    }
                } footer: {
                    Text("修改在继续游戏后生效。关闭或删除代码不会撤销已写入的游戏数据；建议先备份存档。")
                }
            }
            .navigationTitle("Cheat List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("添加金手指", systemImage: "plus") {
                        editing = Cheat(name: "", code: "")
                    }
                    .accessibilityIdentifier("addCheatButton")
                }
            }
            .sheet(item: $editing) { cheat in
                CheatEditorView(cheat: cheat) { edited in
                    var entries = viewModel.cheats
                    if let index = entries.firstIndex(where: { $0.id == edited.id }) {
                        entries[index] = edited
                    } else {
                        entries.append(edited)
                    }
                    try viewModel.updateCheats(entries)
                }
            }
            .alert("金手指错误", isPresented: Binding(
                get: { viewModel.cheatError != nil },
                set: { if !$0 { viewModel.cheatError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.cheatError ?? "")
            }
            .confirmationDialog("删除此金手指？", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let cheat = pendingDeletion {
                        commit(viewModel.cheats.filter { $0.id != cheat.id })
                    }
                    pendingDeletion = nil
                }
            }
        }
    }

    private func commit(_ cheats: [Cheat]) {
        do { try viewModel.updateCheats(cheats) }
        catch { viewModel.cheatError = error.localizedDescription }
    }
}

private struct CheatEditorView: View {
    @State var cheat: Cheat
    let save: (Cheat) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $cheat.name)
                    .accessibilityIdentifier("cheatNameField")
                Picker("代码格式", selection: $cheat.format) {
                    ForEach(Cheat.Format.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                Section("代码（每行一条，同组代码一起添加）") {
                    TextEditor(text: $cheat.code)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .accessibilityLabel("金手指代码")
                        .accessibilityIdentifier("cheatCodeField")
                }
                Toggle("启用", isOn: $cheat.isEnabled)
                Text("支持 GameShark、Action Replay、CodeBreaker 和原始 VBA 代码（如 02000000:01）。代码必须匹配当前游戏及版本。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("编辑金手指")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try save(cheat.validated())
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(cheat.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cheat.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveCheatButton")
                }
            }
            .alert("无法保存金手指", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }
}
