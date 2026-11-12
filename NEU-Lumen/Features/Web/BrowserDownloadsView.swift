import SwiftUI
import QuickLook

/// Mount once at AppRootView.background, not inside an individual browser sheet.
@MainActor
struct BrowserDownloadCoordinator: View {
    @Environment(AppEnvironment.self) private var environment

    private struct Identity: Equatable {
        let account: String?
        let epoch: UUID
    }

    private var identity: Identity {
        let session = environment.session
        let account: String?
        if session.phase == .loggedIn, let user = session.user {
            let value = user.sid.isEmpty ? user.uid : user.sid
            account = value.isEmpty ? nil : value
        } else { account = nil }
        return Identity(account: account, epoch: session.requestEpoch)
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: identity, initial: true) { _, value in
                BrowserDownloadStore.shared.activate(account: value.account, epoch: value.epoch)
            }
            .accessibilityHidden(true)
    }
}

@MainActor
struct BrowserDownloadsView: View {
    let store: BrowserDownloadStore
    @Environment(\.dismiss) private var dismiss
    @State private var preview: URL?
    @State private var shared: BrowserSharedFile?
    @State private var deleting: BrowserDownloadRecord?
    @State private var showDelete = false
    @State private var missingFile = false

    init(store: BrowserDownloadStore) { self.store = store }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.storageError {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                if store.records.isEmpty {
                    ContentUnavailableView("暂无下载", systemImage: "arrow.down.circle",
                        description: Text(store.accountKey == nil ? "登录后可查看当前账号的下载。" : "网页附件和原始 PDF 将保存在这里。"))
                        .listRowBackground(Color.clear)
                } else {
                    downloadSection("正在下载", states: [.downloading])
                    downloadSection("已完成", states: [.completed])
                    downloadSection("未完成", states: [.failed, .cancelled, .interrupted])
                }
                Section {
                    Text("文件仅对当前账号可见并保存在本机，不参与备份。关闭网页不会主动取消下载；应用被系统挂起时不保证继续下载。中断后请回原网页重新下载，不支持断点续传。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("下载管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .quickLookPreview($preview)
            .sheet(item: $shared) { file in
                BrowserDownloadShareSheet(url: file.url)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog("删除这条下载及其本机文件？", isPresented: $showDelete, titleVisibility: .visible) {
                Button("删除下载", role: .destructive) {
                    if let deleting { store.delete(deleting.id) }
                    deleting = nil
                }
                Button("取消", role: .cancel) { deleting = nil }
            } message: { Text(deleting?.filename ?? "") }
            .alert("无法打开文件", isPresented: $missingFile) {
                Button("好", role: .cancel) {}
            } message: { Text("文件已不存在或当前账号已改变，请回原网页重新下载。") }
            .onChange(of: store.scope) { _, _ in
                // Dismiss private URLs immediately on account changes, including a presented share sheet.
                preview = nil
                shared = nil
                deleting = nil
                showDelete = false
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func downloadSection(_ title: String, states: [BrowserDownloadRecord.State]) -> some View {
        let items = store.records.filter { states.contains($0.state) }
        if !items.isEmpty {
            Section(title) { ForEach(items) { row($0) } }
        }
    }

    private func row(_ record: BrowserDownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: record.state == .completed ? "doc.fill" : "arrow.down.doc")
                    .foregroundStyle(record.state == .failed ? Color.orange : Color.accentColor)
                    .font(.title3).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.filename).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(record.kind == .webpagePDF ? "网页导出 PDF · 非原文件" : "原始文件")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    if record.state == .downloading {
                        Button("取消下载", systemImage: "xmark.circle") { store.cancel(record.id) }
                    }
                    if record.state == .completed {
                        Button("预览文件", systemImage: "eye") { open(record, sharing: false) }
                        Button("分享 / 存到“文件”", systemImage: "square.and.arrow.up") { open(record, sharing: true) }
                    }
                    Button("删除", systemImage: "trash", role: .destructive) {
                        deleting = record
                        showDelete = true
                    }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 36, height: 36) }
                    .accessibilityLabel("管理下载：\(record.filename)")
            }
            if record.state == .downloading {
                if let fraction = record.fraction { ProgressView(value: fraction) }
                else { ProgressView().controlSize(.small) }
            }
            HStack {
                Text(status(record))
                    .foregroundStyle(record.state == .failed ? Color.orange : Color.secondary)
                Spacer()
                if record.state == .downloading {
                    Button("取消") { store.cancel(record.id) }.buttonStyle(.borderless)
                } else if record.state == .completed {
                    Button("预览") { open(record, sharing: false) }.buttonStyle(.borderless)
                    Button { open(record, sharing: true) } label: { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.borderless).accessibilityLabel("分享或存到文件")
                }
            }.font(.caption)
            if let failure = record.failure {
                Text(failure.message).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-download-\(record.state.rawValue)")
    }

    private func status(_ record: BrowserDownloadRecord) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: record.receivedBytes, countStyle: .file)
        switch record.state {
        case .downloading:
            if let total = record.totalBytes {
                return "\(bytes) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
            }
            return "已下载 \(bytes)"
        case .completed: return "已完成 · \(bytes)"
        case .failed: return "下载失败 · \(bytes)"
        case .cancelled: return "已取消 · \(bytes)"
        case .interrupted: return "已中断 · 请回原网页重新下载"
        }
    }

    private func open(_ record: BrowserDownloadRecord, sharing: Bool) {
        guard let url = store.previewURL(for: record.id) else { missingFile = true; return }
        if sharing { shared = BrowserSharedFile(url: url) } else { preview = url }
    }
}

private struct BrowserDownloadShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
