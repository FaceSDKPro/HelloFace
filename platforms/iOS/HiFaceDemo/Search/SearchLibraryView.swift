import SwiftUI

struct SearchLibraryView: View {
    @StateObject private var model = SearchLibraryModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var isSuspended = true
    @FocusState private var queryFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsImportExit = false
    @State private var exitAfterImport = false

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                TextField(DemoL10n.text("输入 Face ID 查找"), text: $model.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .focused($queryFocused)
                    .onSubmit { queryFocused = false; model.lookup() }
                    .onChange(of: model.query) { value in
                        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           model.isLookup, !model.isWorking { model.clearLookup() }
                    }
                if !model.query.isEmpty {
                    Button(action: model.clearLookup) { Image(systemName: "xmark.circle.fill") }
                        .frame(minWidth: 36, minHeight: 36)
                        .accessibilityLabel(DemoL10n.text("清除查询"))
                }
                Button(DemoL10n.text("查找")) { queryFocused = false; model.lookup() }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 36)
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .frame(height: 40)
            .background(DemoTheme.searchSurface, in: RoundedRectangle(cornerRadius: 10))
            .disabled(model.isWorking)

            HStack(spacing: 7) {
                Circle().fill(model.hasError ? .red : DemoTheme.searchAccent)
                    .frame(width: 6, height: 6)
                Text(model.status).lineLimit(2)
                Spacer()
                if model.isWorking { ProgressView().tint(DemoTheme.searchAccent) }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
            .frame(minHeight: 22)

            records.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(DemoTheme.search.ignoresSafeArea())
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .navigationTitle(DemoL10n.text("人脸库"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(model.isImporting)
        .preferredColorScheme(.dark)
        .tint(DemoTheme.searchAccent)
        .onAppear {
            isVisible = true
            updatePageActivity(for: scenePhase)
        }
        .onDisappear { isVisible = false; isSuspended = true; model.stop() }
        .onChange(of: scenePhase, perform: updatePageActivity)
        .onChange(of: model.isImporting) { importing in
            if !importing { confirmsImportExit = false }
        }
        .demoDialog(isPresented: confirmsImportExit, onDismiss: { confirmsImportExit = false }) {
            CameraDialogTitle(title: DemoL10n.text("任务正在执行"),
                              subtitle: model.isStoppingImport
                                ? DemoL10n.text("正在停止并保存，请稍候…")
                                : DemoL10n.text("正在导入。停止后保存已完成结果并退出。"),
                              symbol: "square.and.arrow.down")
            if model.isStoppingImport {
                Button(DemoL10n.text("知道了")) { confirmsImportExit = false }
            } else {
                Button(DemoL10n.text("继续导入"), role: .cancel) { confirmsImportExit = false }
                Button(DemoL10n.text("停止并退出")) {
                    confirmsImportExit = false
                    exitAfterImport = true
                    if model.isImporting { model.requestStopImport() } else { dismiss() }
                }
            }
        }
        .demoDialog(isPresented: isVisible && !isSuspended && model.importNotice != nil,
                    onDismiss: finishImportNotice) {
            CameraDialogTitle(title: DemoL10n.text("导入结果"), subtitle: model.importNotice ?? "", symbol: "checkmark.circle")
            Button(exitAfterImport ? DemoL10n.text("返回") : DemoL10n.text("知道了"), action: finishImportNotice)
        }
        .demoDialog(isPresented: model.pendingDeleteFaceID != nil, onDismiss: model.cancelDelete) {
            CameraDialogTitle(
                title: DemoL10n.text("删除这条人脸？"),
                subtitle: DemoL10n.text("Face ID：{0}\n\n删除后需重新录入。", [String(describing: model.pendingDeleteFaceID ?? "")]),
                symbol: "trash"
            )
            Button(DemoL10n.text("删除"), role: .destructive, action: model.confirmDelete)
            Button(DemoL10n.text("取消"), role: .cancel, action: model.cancelDelete)
        }
        .demoDialog(isPresented: model.pendingImport != nil, onDismiss: model.cancelImport) {
            CameraDialogTitle(
                title: model.pendingImport?.title ?? DemoL10n.text("批量导入"),
                subtitle: model.pendingImport == .features
                    ? DemoL10n.text("导入内置的 1 万条 HF1 特征，覆盖同 Face ID 记录。")
                    : DemoL10n.text("联网导入 1 千张图片，覆盖同 Face ID 记录。跳过失败图片，保留已保存批次。"),
                symbol: "square.and.arrow.down"
            )
            Button(DemoL10n.text("开始导入"), action: model.confirmImport)
            Button(DemoL10n.text("取消"), role: .cancel, action: model.cancelImport)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: requestExit) {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }.accessibilityLabel(DemoL10n.text("返回"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(DemoL10n.text("刷新"), systemImage: "arrow.clockwise", action: model.clearLookup)
                    Button(FaceSearchDemoImportKind.features.title, systemImage: "doc.text") {
                        model.requestImport(.features)
                    }
                    Button(FaceSearchDemoImportKind.images.title, systemImage: "photo.on.rectangle") {
                        model.requestImport(.images)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 36, height: 36)
                }
                .disabled(model.isWorking || model.pendingDeleteFaceID != nil)
                .accessibilityLabel(DemoL10n.text("人脸库功能菜单"))
            }
        }
    }

    private func requestExit() {
        if model.isImporting { confirmsImportExit = true } else { dismiss() }
    }

    private func finishImportNotice() {
        model.dismissImportNotice()
        if exitAfterImport { dismiss() }
    }

    @ViewBuilder private var records: some View {
        if model.people.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.3")
                    .font(.system(size: 28))
                    .foregroundStyle(model.hasError ? .red : DemoTheme.searchAccent)
                    .frame(width: 68, height: 68)
                    .background((model.hasError ? Color.red : DemoTheme.searchAccent).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 17))
                Text(model.hasError ? DemoL10n.text("操作失败") : model.isWorking ? DemoL10n.text("正在读取…") :
                     (model.isLookup ? DemoL10n.text("未找到该 Face ID") : DemoL10n.text("当前范围内暂无已录入人脸")))
                    .font(.headline)
                Text(model.hasError ? DemoL10n.text("请重试，或使用右上角菜单刷新。") : model.isLookup
                     ? DemoL10n.text("请检查 Face ID，或清空输入返回全部记录。")
                     : DemoL10n.text("从右上角菜单导入演示数据。"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        } else if #available(iOS 16.0, *) {
            peopleList.scrollContentBackground(.hidden)
        } else {
            peopleList
        }
    }

    /// 系统弹窗的 inactive 保留导入；切后台才释放，返回后重读已提交数据。
    private func updatePageActivity(for phase: ScenePhase) {
        guard isVisible else { return }
        if phase == .background, !isSuspended {
            isSuspended = true
            model.stop()
        } else if phase == .active, isSuspended {
            isSuspended = false
            model.refresh()
        }
    }

    private var peopleList: some View {
        List(model.people) { person in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(person.id).font(.headline).lineLimit(2)
                    Text(DemoL10n.text("分组：{0}", [String(describing: person.group.isEmpty ? DemoL10n.text("未分组") : person.group)]) +
                         (person.tag.isEmpty ? "" : DemoL10n.text(" · 标签：{0}", [String(describing: person.tag)])))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(role: .destructive) {
                    model.requestDelete(faceID: person.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .frame(width: 44, height: 44)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                }
                .disabled(model.isWorking)
                .accessibilityLabel(Text(verbatim: DemoL10n.text("删除人脸 {0}", [String(describing: person.id)])))
            }
            .padding(.vertical, 7)
            .listRowBackground(DemoTheme.searchSurface)
            .onAppear { model.loadMoreIfNeeded(current: person) }
        }
        .listStyle(.plain)
    }
}
