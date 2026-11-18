import SwiftUI

struct WebDAVBackupView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("lumen.home.quickServiceCount") private var quickServiceCount = 4
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var configuration: WebDAVConfiguration?
    @State private var owner: AccountScope?
    @State private var operation: Task<Void, Never>?
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var pending: Confirmation?
    @State private var showConfirmation = false

    private struct AccountScope: Equatable {
        let account: String
        let epoch: UUID
    }

    private struct Confirmation {
        enum Action {
            case upload(WebDAVConfiguration, Data, WebDAVBackupClient.UploadCondition)
            case restore(PersonalBackup)
        }

        let scope: AccountScope
        let action: Action

        var title: String {
            switch action {
            case .upload: "覆盖远端备份？"
            case .restore: "恢复个人设置与收藏？"
            }
        }

        var detail: String {
            switch action {
            case .upload: "会用当前设备的数据替换服务器上的 NEU-Lumen 备份。"
            case .restore(let backup):
                "备份时间：\(backup.savedAt.formatted(date: .abbreviated, time: .shortened))。包含 \(backup.favoriteIDs.count) 个收藏和 \(backup.events.count) 条自建日程。设置与收藏会被替换，日程会合并并保留本机已有记录。"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("HTTPS 文件夹地址", text: $address, prompt: Text("https://dav.example.com/lumen/"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("WebDAV 用户名", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("WebDAV 密码或应用专用密码", text: $password)
                    .textContentType(.password)
                Button("保存连接") { saveConnection() }
                    .disabled(owner == nil)
            } header: {
                Text("WebDAV 连接")
            } footer: {
                Text("请使用你已有权限的文件夹。连接信息保存在本机钥匙串。")
            }

            Section {
                Button("备份到 WebDAV", systemImage: "arrow.up.circle") { prepareUpload() }
                Button("从 WebDAV 恢复", systemImage: "arrow.down.circle") { prepareRestore() }
                if operation != nil { ProgressView("正在与 WebDAV 通信…") }
                if let message { Text(message).foregroundStyle(.secondary) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            } header: {
                Text("手动备份与恢复")
            } footer: {
                Text("备份包含首页与课表设置、服务收藏和本机自建日程。备份通过 HTTPS 写入所选文件夹中的 JSON 文件，服务器可读取其中的内容。")
            }
            .disabled(!hasSavedDraft || operation != nil || showConfirmation)

            if configuration != nil {
                Section {
                    Button("移除此设备的 WebDAV 连接", role: .destructive) { clearConnection() }
                }
                .disabled(operation != nil || showConfirmation)
            }
        }
        .disabled(operation != nil)
        .navigationTitle("WebDAV 备份")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: currentScope) { await loadConnection() }
        .onDisappear { operation?.cancel() }
        .confirmationDialog(pending?.title ?? "确认", isPresented: $showConfirmation,
                            titleVisibility: .visible, presenting: pending) { change in
            switch change.action {
            case .upload:
                Button("覆盖备份", role: .destructive) { confirm(change) }
            case .restore:
                Button("恢复并合并日程") { confirm(change) }
            }
            Button("取消", role: .cancel) { pending = nil }
        } message: { change in
            Text(change.detail)
        }
    }

    private var currentScope: AccountScope? {
        guard environment.session.phase == .loggedIn, let user = environment.session.user else { return nil }
        let key = user.sid.isEmpty ? user.uid : user.sid
        return key.isEmpty ? nil : AccountScope(account: key, epoch: environment.session.requestEpoch)
    }

    private var hasSavedDraft: Bool {
        guard let configuration, owner == currentScope else { return false }
        return configuration.collectionURL.absoluteString == address
            && configuration.username == username && configuration.password == password
    }

    private func loadConnection() async {
        operation?.cancel()
        owner = nil
        configuration = nil
        address = ""
        username = ""
        password = ""
        pending = nil
        showConfirmation = false
        message = nil
        errorMessage = nil
        guard let scope = currentScope else { return }
        await environment.repository.ensureLoadedForCurrentUser()
        guard !Task.isCancelled, scope == currentScope, environment.repository.hasCurrentLiveActivityAccount else { return }
        owner = scope
        do {
            if let saved = try WebDAVConfigurationStore.load(account: scope.account) { use(saved) }
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveConnection() {
        guard let owner, owner == currentScope else { return }
        report {
            let saved = try WebDAVConfiguration(collectionURL: address, username: username, password: password)
            try WebDAVConfigurationStore.save(saved, account: owner.account)
            use(saved)
            message = "已保存 WebDAV 连接。"
        }
    }

    private func use(_ saved: WebDAVConfiguration) {
        configuration = saved
        address = saved.collectionURL.absoluteString
        username = saved.username
        password = saved.password
    }

    private func clearConnection() {
        guard let owner, owner == currentScope else { return }
        report {
            try WebDAVConfigurationStore.clear(account: owner.account)
            configuration = nil
            address = ""
            username = ""
            password = ""
            message = "已移除此设备的连接。"
        }
    }

    private func report(_ action: () throws -> Void) {
        message = nil
        errorMessage = nil
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private func requireCurrent(_ scope: AccountScope) throws {
        try Task.checkCancellation()
        guard owner == scope, currentScope == scope, environment.repository.hasCurrentLiveActivityAccount else {
            throw PersonalBackup.BackupError.accountChanged
        }
    }

    private func run(_ action: @escaping @MainActor (AccountScope) async throws -> Void) {
        guard operation == nil, let scope = currentScope else { return }
        message = nil
        errorMessage = nil
        operation = Task {
            defer { operation = nil }
            do {
                try requireCurrent(scope)
                try await action(scope)
            } catch is CancellationError {
                // The page or its campus session is no longer current.
            } catch {
                if !Task.isCancelled, scope == currentScope {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func prepareUpload() {
        guard let configuration, hasSavedDraft else { return }
        run { scope in
            let data = try backup().encoded()
            let client = WebDAVBackupClient()
            let remote = try await client.download(using: configuration)
            try requireCurrent(scope)
            if let remote {
                let condition: WebDAVBackupClient.UploadCondition = remote.etag.map { .matching($0) } ?? .replace
                pending = Confirmation(scope: scope, action: .upload(configuration, data, condition))
                showConfirmation = true
            } else {
                try await client.upload(data, using: configuration, condition: .createOnly)
                try requireCurrent(scope)
                message = "已备份到 WebDAV。"
            }
        }
    }

    private func prepareRestore() {
        guard let configuration, hasSavedDraft else { return }
        run { scope in
            let remote = try await WebDAVBackupClient().download(using: configuration)
            try requireCurrent(scope)
            guard let remote else {
                message = "该 WebDAV 文件夹中还没有备份。"
                return
            }
            pending = Confirmation(scope: scope, action: .restore(try PersonalBackup.decode(remote.data)))
            showConfirmation = true
        }
    }

    private func confirm(_ change: Confirmation) {
        pending = nil
        run { scope in
            guard change.scope == scope else { throw PersonalBackup.BackupError.accountChanged }
            switch change.action {
            case let .upload(configuration, data, condition):
                try await WebDAVBackupClient().upload(data, using: configuration, condition: condition)
                try requireCurrent(scope)
                message = "已更新 WebDAV 备份。"
            case .restore(let backup):
                try restore(backup)
                message = "已恢复个人设置、收藏和自建日程。"
            }
        }
    }

    private func backup() -> PersonalBackup {
        let repository = environment.repository
        let settings = PersonalBackup.Settings(
            quickServiceCount: HomeQuickServiceCount.normalized(quickServiceCount),
            campus: repository.campusOverride?.rawValue,
            semester: SemesterSettings.shared.isCustomized ? SemesterSettings.shared.configuration : nil,
            smartHolidays: repository.holidays.enabled,
            schoolDayOverrides: repository.holidays.overrides,
            replacementDays: repository.holidays.replacementDates
        )
        let events = PlannerEventStore.shared.events.filter { $0.kind == "custom" && $0.deletable }
        return PersonalBackup(settings: settings, favoriteIDs: repository.favorites.ids, events: events)
    }

    private func restore(_ backup: PersonalBackup) throws {
        let planner = PlannerEventStore.shared
        do { try planner.restore(backup.mergingEvents(into: planner.events)) }
        catch { throw PersonalBackup.BackupError.localWriteFailed }
        let repository = environment.repository
        let settings = backup.settings
        quickServiceCount = settings.quickServiceCount
        repository.setCampusOverride(settings.campus.flatMap(Campus.init(rawValue:)))
        repository.favorites.restore(ids: backup.favoriteIDs)
        repository.holidays.restore(enabled: settings.smartHolidays, overrides: settings.schoolDayOverrides,
                                    replacementDates: settings.replacementDays)
        if let semester = settings.semester { SemesterSettings.shared.save(semester) }
        else { SemesterSettings.shared.reset() }
    }
}
