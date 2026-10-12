import SwiftUI

struct SearchLibraryView: View {
    @StateObject private var model = SearchLibraryModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var isSuspended = true
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                TextField("输入 Face ID 查找", text: $model.query)
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
                        .accessibilityLabel("清除查询")
                }
                Button("查找") { queryFocused = false; model.lookup() }
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
        .navigationTitle("人脸库")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.pendingDeleteFaceID != nil || model.pendingImport != nil)
        .preferredColorScheme(.dark)
        .tint(DemoTheme.searchAccent)
        .onAppear {
            isVisible = true
            updatePageActivity(for: scenePhase)
        }
        .onDisappear { isVisible = false; isSuspended = true; model.stop() }
        .onChange(of: scenePhase, perform: updatePageActivity)
        .demoDialog(isPresented: model.pendingDeleteFaceID != nil, onDismiss: model.cancelDelete) {
            CameraDialogTitle(
                title: "删除这条人脸？",
                subtitle: "Face ID：\(model.pendingDeleteFaceID ?? "")\n\n删除后将无法搜索到这条人脸，需重新录入才能恢复。",
                symbol: "trash"
            )
            Button("删除", role: .destructive, action: model.confirmDelete)
            Button("取消", role: .cancel, action: model.cancelDelete)
        }
        .demoDialog(isPresented: model.pendingImport != nil, onDismiss: model.cancelImport) {
            CameraDialogTitle(
                title: model.pendingImport?.title ?? "批量导入",
                subtitle: model.pendingImport == .features
                    ? "从 App 内置 JSON 分批写入 1 万条 HF1 人脸特征，同 Face ID 记录会被覆盖。"
                    : "联网下载内置 JSON 中的1千张人脸图片，逐张提取特征并覆盖同 Face ID 记录。失败图片会跳过，已提交批次会保留。",
                symbol: "square.and.arrow.down"
            )
            Button("开始导入", action: model.confirmImport)
            Button("取消", role: .cancel, action: model.cancelImport)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("刷新", systemImage: "arrow.clockwise", action: model.clearLookup)
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
                .accessibilityLabel("人脸库功能菜单")
            }
        }
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
                Text(model.hasError ? "操作失败" : model.isWorking ? "正在读取…" :
                     (model.isLookup ? "未找到该 Face ID" : "当前范围内暂无已录入人脸"))
                    .font(.headline)
                Text(model.hasError ? "请根据上方提示重试，或使用右上角菜单刷新。" : model.isLookup
                     ? "请检查 Face ID，或清空输入返回全部记录。"
                     : "可从右上角菜单导入演示数据。")
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
                    Text("分组：\(person.group.isEmpty ? "未分组" : person.group)" +
                         (person.tag.isEmpty ? "" : " · 标签：\(person.tag)"))
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
                .accessibilityLabel(Text(verbatim: "删除人脸 \(person.id)"))
            }
            .padding(.vertical, 7)
            .listRowBackground(DemoTheme.searchSurface)
            .onAppear { model.loadMoreIfNeeded(current: person) }
        }
        .listStyle(.plain)
    }
}
