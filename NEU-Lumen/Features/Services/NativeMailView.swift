import SwiftUI
import WebKit
import MessageUI

struct NativeMailView: View {
    var active = true
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = NativeMailStore()
    @State private var query = ""
    @State private var selectedMessage: NativeMailMessage?
    @State private var web: MailWebReason?
    @State private var compose = false
    @State private var search = NativeMailSearch()
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var moving = false
    @State private var downloads = false
    var body: some View {
        List {
            Section {
                if !store.email.isEmpty { Text(store.email).font(.subheadline).foregroundStyle(.secondary) }
                HStack {
                    Menu {
                        ForEach(store.folders) { folder in
                            Button(folderTitle(folder)) { query = ""; search = NativeMailSearch(); selection = []; Task { await store.selectFolder(folder) } }
                        }
                    } label: {
                        Label(store.folders.first(where: { $0.id == store.folderID })?.name ?? "收件箱", systemImage: "tray")
                    }.disabled(store.folders.isEmpty || store.busy)
                    Spacer()
                    Button("写邮件", systemImage: "square.and.pencil") {
                        web = .compose
                    }.disabled(store.email.isEmpty)
                }
                TextField("搜索邮件主题，回车查询", text: $query)
                    .submitLabel(.search).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { applySearch() }
                DisclosureGroup("高级搜索") {
                    TextField("发件人", text: $search.from).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("收件人", text: $search.to).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("仅未读", isOn: $search.unreadOnly)
                    Toggle("包含普通附件", isOn: $search.attachedOnly)
                    Toggle("仅星标", isOn: $search.flaggedOnly)
                    Button("查询") { applySearch() }.disabled(store.busy)
                    Button("清除搜索条件") { query = ""; search = NativeMailSearch(); applySearch() }.disabled(store.busy)
                }
            }
            if let candidate = store.bindingCandidate {
                Section("确认邮箱关联") {
                    Text("将「\(candidate)」关联到当前校园账号？")
                    Button("确认并读取邮箱") { Task { await store.confirmBinding() } }
                    Button("更换登录邮箱") { web = .login }
                }
            }
            if store.needsLogin || (!store.loaded && !store.loadingWeb && !store.busy) {
                Section {
                    Button("登录学校邮箱", systemImage: "person.crop.circle.badge.checkmark") { web = .login }
                    Text("使用学校正常认证。邮箱登录保存在本机，按校园账号隔离；退出校园账号时清除。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message = store.error {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            if let warning = store.persistenceWarning {
                Section { Text(warning).font(.footnote).foregroundStyle(.orange) }
            }
            Section {
                if store.busy || store.loadingWeb { ProgressView("正在同步学校邮箱…") }
                if store.loaded && store.messages.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "当前文件夹没有邮件" : "没有匹配的邮件", systemImage: "tray")
                }
                ForEach(store.messages) { message in
                    HStack {
                        if selecting {
                            Button {
                                if selection.contains(message.id) { selection.remove(message.id) } else { selection.insert(message.id) }
                            } label: { Image(systemName: selection.contains(message.id) ? "checkmark.circle.fill" : "circle") }
                                .accessibilityLabel("选择邮件「\(message.subject)」")
                        }
                        Button { selectedMessage = message } label: { mailRow(message) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(message.unread == true ? "标为已读" : "标为未读") {
                                    Task { _ = await store.update([message.id], mutation: .read(message.unread == true)) }
                                }
                                Button(message.flagged == true ? "取消星标" : "添加星标") {
                                    Task { _ = await store.update([message.id], mutation: .flagged(message.flagged != true)) }
                                }
                            }
                    }.disabled(store.busy)
                }
                if store.hasMore && !store.busy {
                    Button("加载更多邮件") { Task { await store.refresh(reset: false) } }
                }
            }
            Section {
                Button("重新同步", systemImage: "arrow.clockwise") { applySearch() }
                    .disabled(store.busy || store.loadingWeb)
                Menu("邮箱登录与网站") {
                    Button("学校邮箱网页登录") { web = .login }
                    Button("系统邮件写信") { compose = true }.disabled(!MFMailComposeViewController.canSendMail())
                    Button("下载管理") { downloads = true }
                    Button("切换到教工邮箱") {
                        Task { await store.connect(session: environment.session, apps: environment.repository.apps,
                            server: URL(string: "https://mail.neu.edu.cn/coremail/")); web = .login }
                    }
                    Button("切换到新版学生邮箱") {
                        Task { await store.connect(session: environment.session, apps: environment.repository.apps,
                            server: NativeCampusService.mail.fallbackURL); web = .login }
                    }
                }
            }
        }
        .privacySensitive()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "完成选择" : "批量操作") { selecting.toggle(); selection = [] }
                    .disabled(store.messages.isEmpty || store.busy)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack {
                    Button(selection.count == store.messages.count ? "取消全选" : "全选") {
                        selection = selection.count == store.messages.count ? [] : Set(store.messages.map(\.id))
                    }
                    Text("\(selection.count) 封").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu("标记") {
                        Button("标为已读") { updateSelection(.read(true)) }
                        Button("标为未读") { updateSelection(.read(false)) }
                        Button("添加星标") { updateSelection(.flagged(true)) }
                        Button("取消星标") { updateSelection(.flagged(false)) }
                    }.disabled(selection.isEmpty)
                    Button("移动") { moving = true }.disabled(selection.isEmpty)
                }.padding().background(.regularMaterial).disabled(store.busy)
            }
        }
        .confirmationDialog("移动所选 \(selection.count) 封邮件到", isPresented: $moving, titleVisibility: .visible) {
            ForEach(store.folders.filter { $0.id != store.folderID }) { folder in
                Button(folder.name) { updateSelection(.move(folder.id)) }
            }
        }
        .onChange(of: store.messages) { _, messages in selection.formIntersection(Set(messages.map(\.id))) }
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            store.invalidateIfNeeded(session: environment.session)
            if store.webView != nil && !active { await store.persist() }
            guard active else { return }
            await store.connect(session: environment.session, apps: environment.repository.apps)
        }
        .refreshable { await store.refresh() }
        .onChange(of: environment.session.requestEpoch) { _, _ in
            selectedMessage = nil; web = nil; compose = false; selection = []; selecting = false; downloads = false
        }
        .onChange(of: scenePhase) { _, value in if value != .active { Task { await store.persist() } } }
        .onDisappear { Task { await store.persist() } }
        .sheet(item: $web, onDismiss: { Task { await store.refresh() } }) { reason in
            NativeMailWebSheet(store: store, reason: reason)
        }
        .sheet(item: $selectedMessage, onDismiss: { Task { await store.refresh() } }) { message in NativeMailReadingView(store: store, message: message) }
        .sheet(isPresented: $compose) { NativeMailComposer(sender: store.email) }
        .sheet(isPresented: $downloads) { BrowserDownloadsView(store: BrowserDownloadStore.shared) }
    }

    private func applySearch() {
        search.subject = query; selection = []
        Task { await store.refresh(advanced: search) }
    }
    private func updateSelection(_ mutation: NativeMailMutation) {
        let ids = selection
        Task { if await store.update(ids, mutation: mutation) { selection = [] } }
    }
    private func folderTitle(_ folder: NativeMailFolder) -> String {
        folder.name + (folder.unread.map { "（\($0) 未读）" } ?? "")
    }

    private func mailRow(_ message: NativeMailMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(message.unread == true ? Color.blue : Color.clear).frame(width: 7, height: 7)
                .padding(.top, 7).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(message.subject).font(message.unread == true ? .headline : .body).lineLimit(2)
                Text(message.sender).font(.subheadline).lineLimit(1).foregroundStyle(.secondary)
                if message.flagged == true { Label("星标", systemImage: "star.fill").font(.caption).foregroundStyle(.orange) }
                if !message.dateText.isEmpty { Text(message.dateText).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

private enum MailWebReason: Identifiable {
    case login, compose, message(String), reply(String, String)
    var id: String {
        switch self {
        case .login: "login"
        case .compose: "compose"
        case .message(let id): "message-" + id
        case .reply(let id, let kind): kind + "-" + id
        }
    }
}

private struct NativeMailWebSheet: View {
    let store: NativeMailStore
    let reason: MailWebReason
    @Environment(\.dismiss) private var dismiss
    @State private var downloads = false
    var body: some View {
        NavigationStack {
            Group {
                if let view = store.webView { NativeMailCanvas(view: view) }
                else { ContentUnavailableView("邮箱尚未准备好", systemImage: "envelope") }
            }
            .navigationTitle("学校邮箱").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu("邮箱工具", systemImage: "ellipsis.circle") {
                        Button("下载管理", systemImage: "arrow.down.circle") { downloads = true }
                        Button("重新打开邮箱入口", systemImage: "arrow.clockwise") { store.reloadLogin() }
                    }
                }
            }
            .sheet(isPresented: $downloads) { BrowserDownloadsView(store: BrowserDownloadStore.shared) }
            .task { await navigate() }
            .onChange(of: store.loaded) { _, loaded in
                guard loaded else { return }
                if case .login = reason { dismiss() }
                else { Task { await navigate() } }
            }
        }
    }
    private func navigate() async {
        switch reason {
        case .login: if store.webView?.url == nil { store.reloadLogin() }
        case .compose: await store.showWebMail(compose: true)
        case .message(let id): await store.showWebMail(messageID: id)
        case .reply(let id, let kind): await store.showWebMail(messageID: id, compose: true, reply: kind)
        }
    }
}

private struct NativeMailCanvas: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct NativeMailReadingView: View {
    let store: NativeMailStore
    let message: NativeMailMessage
    @Environment(\.dismiss) private var dismiss
    @State private var bodyData: NativeMailBody?
    @State private var error: String?
    @State private var web: MailWebReason?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(bodyData?.subject ?? message.subject).font(.title2.bold()).textSelection(.enabled)
                    Text(bodyData?.sender ?? message.sender).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(message.dateText).font(.caption).foregroundStyle(.secondary)
                    Divider()
                    if let bodyData {
                        if bodyData.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("此邮件没有可读取的文字正文。").foregroundStyle(.secondary)
                            Button("在学校邮箱查看完整邮件") { web = .message(message.id) }
                        } else {
                            Text(bodyData.text).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !bodyData.attachments.isEmpty {
                            Divider()
                            ForEach(Array(bodyData.attachments.enumerated()), id: \.offset) { _, name in
                                Label(name, systemImage: "paperclip").font(.subheadline)
                            }
                            Button("在学校邮箱查看附件") { web = .message(message.id) }
                        }
                    } else if let error {
                        Text(error).foregroundStyle(.secondary)
                        Button("在学校邮箱查看") { web = .message(message.id) }
                    } else { ProgressView("读取邮件正文…") }
                }.padding(20)
            }
            .navigationTitle("邮件").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("邮件操作", systemImage: "ellipsis.circle") {
                        Button("回复") { web = .reply(message.id, "reply") }
                        Button("回复全部") { web = .reply(message.id, "replyall") }
                        Button("转发") { web = .reply(message.id, "forward") }
                        Button("写新邮件") { web = .compose }
                        Button("查看完整邮件与附件") { web = .message(message.id) }
                    }
                }
            }
            .task(id: message.id) {
                do { bodyData = try await store.read(message) }
                catch { if !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message } }
            }
            .sheet(item: $web) { reason in NativeMailWebSheet(store: store, reason: reason) }
        }
    }
}

/// Sending stays an explicit action in the system composer, with its visible From field.
private struct NativeMailComposer: UIViewControllerRepresentable {
    let sender: String
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setPreferredSendingEmailAddress(sender)
        return controller
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let close: @MainActor () -> Void
        init(close: @escaping @MainActor () -> Void) { self.close = close }
        nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            Task { @MainActor in close() }
        }
    }
}
