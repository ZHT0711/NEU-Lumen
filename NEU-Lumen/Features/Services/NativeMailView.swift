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
    var body: some View {
        List {
            Section {
                if !store.email.isEmpty { Text(store.email).font(.subheadline).foregroundStyle(.secondary) }
                HStack {
                    Menu {
                        ForEach(store.folders) { folder in
                            Button(folder.name) { query = ""; Task { await store.selectFolder(folder) } }
                        }
                    } label: {
                        Label(store.folders.first(where: { $0.id == store.folderID })?.name ?? "收件箱", systemImage: "tray")
                    }.disabled(store.folders.isEmpty || store.busy)
                    Spacer()
                    Button("写邮件", systemImage: "square.and.pencil") {
                        if MFMailComposeViewController.canSendMail() { compose = true }
                        else { web = .compose }
                    }.disabled(store.email.isEmpty)
                }
                TextField("搜索邮件主题，回车查询", text: $query)
                    .submitLabel(.search).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { Task { await store.refresh(search: query) } }
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
                    Button { selectedMessage = message } label: { mailRow(message) }
                        .buttonStyle(.plain).disabled(store.busy)
                }
                if store.hasMore && !store.busy {
                    Button("加载更多邮件") { Task { await store.refresh(reset: false) } }
                }
            }
            Section {
                Button("重新同步", systemImage: "arrow.clockwise") { Task { await store.refresh(search: query) } }
                    .disabled(store.busy || store.loadingWeb)
                Menu("邮箱登录与网站") {
                    Button("学校邮箱网页登录") { web = .login }
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
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            store.invalidateIfNeeded(session: environment.session)
            if store.webView != nil && !active { await store.persist() }
            guard active else { return }
            await store.connect(session: environment.session, apps: environment.repository.apps)
        }
        .refreshable { await store.refresh(search: query) }
        .onChange(of: environment.session.requestEpoch) { _, _ in
            selectedMessage = nil; web = nil; compose = false
        }
        .onChange(of: scenePhase) { _, value in if value != .active { Task { await store.persist() } } }
        .onDisappear { Task { await store.persist() } }
        .sheet(item: $web, onDismiss: { Task { await store.refresh() } }) { reason in
            NativeMailWebSheet(store: store, reason: reason)
        }
        .sheet(item: $selectedMessage) { message in NativeMailReadingView(store: store, message: message) }
        .sheet(isPresented: $compose) { NativeMailComposer(sender: store.email) }
    }

    private func mailRow(_ message: NativeMailMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(message.unread == true ? Color.blue : Color.clear).frame(width: 7, height: 7)
                .padding(.top, 7).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(message.subject).font(message.unread == true ? .headline : .body).lineLimit(2)
                Text(message.sender).font(.subheadline).lineLimit(1).foregroundStyle(.secondary)
                if !message.dateText.isEmpty { Text(message.dateText).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

private enum MailWebReason: Identifiable {
    case login, compose, message(String)
    var id: String {
        switch self { case .login: "login"; case .compose: "compose"; case .message(let id): "message-" + id }
    }
}

private struct NativeMailWebSheet: View {
    let store: NativeMailStore
    let reason: MailWebReason
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let view = store.webView { NativeMailCanvas(view: view) }
                else { ContentUnavailableView("邮箱尚未准备好", systemImage: "envelope") }
            }
            .navigationTitle("学校邮箱").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
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
    @State private var compose = false
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
                    Button("写邮件", systemImage: "square.and.pencil") {
                        if MFMailComposeViewController.canSendMail() { compose = true } else { web = .compose }
                    }
                }
            }
            .task(id: message.id) {
                do { bodyData = try await store.read(message) }
                catch { if !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message } }
            }
            .sheet(item: $web) { reason in NativeMailWebSheet(store: store, reason: reason) }
            .sheet(isPresented: $compose) { NativeMailComposer(sender: store.email) }
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
