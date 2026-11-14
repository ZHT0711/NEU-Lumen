import SwiftUI
import WebKit

struct NativeServiceDocumentView: View {
    let browser: PortalBrowser
    let service: NativeCampusService
    let showWebsite: () -> Void
    @Environment(AppEnvironment.self) private var environment
    @State private var document: NativeServiceDocument?
    @State private var values: [String: String] = [:]
    @State private var error: String?
    @State private var busy = false
    @State private var pendingAction: NativeServiceDocument.Action?
    @State private var confirmedAction: NativeServiceDocument.Action?
    @State private var request = UUID()
    @State private var fieldRevisions: [String: UUID] = [:]
    private static let world = WKContentWorld.world(name: "NEULumen.ServiceDocument")

    var body: some View {
        List {
            if browser.isLoading || busy { ProgressView("读取学校页面…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("重新读取") { Task { await read() } }
                    Button("打开学校页面") { Task { await openWebsite() } }
                }
            }
            if let document {
                ForEach(Array(document.notices.enumerated()), id: \.offset) { _, notice in
                    Text(notice).foregroundStyle(.orange).textSelection(.enabled)
                }
                if !document.fields.isEmpty {
                    Section(service == .affairs ? "申请表单" : service == .academic ? "查询条件与业务表单" : "查询与缴费信息") {
                        ForEach(document.fields) { field in fieldEditor(field) }
                    }
                }
                ForEach(document.tables) { table in
                    Section(table.title) {
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(row.enumerated()), id: \.offset) { index, value in
                                    if index < table.headers.count && !table.headers[index].isEmpty {
                                        LabeledContent(table.headers[index], value: value.isEmpty ? "未提供" : value)
                                    } else if !value.isEmpty { Text(value) }
                                }
                            }.font(.subheadline).textSelection(.enabled).padding(.vertical, 4)
                        }
                        if table.truncated { Text("本页已显示前 200 行，可通过学校分页继续查看。").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if !document.actions.isEmpty {
                    Section("学校页面操作") {
                        ForEach(document.actions) { action in
                            Button {
                                if action.query == true { Task { await activate(action) } }
                                else { pendingAction = action }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.title)
                                    if !action.context.isEmpty && action.query != true { Text(action.context).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                if document.needsWeb || (document.fields.isEmpty && document.tables.isEmpty) {
                    Section {
                        Text("当前页面含学校自定义控件、附件或认证流程时，可在学校页面继续办理。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section { Button("在学校页面继续", systemImage: "arrow.up.right.square") { Task { await openWebsite() } } }
            }
        }
        .disabled(busy)
        .privacySensitive()
        .task(id: String(browser.isLoading) + (browser.currentURL?.absoluteString ?? "") + environment.session.requestEpoch.uuidString) {
            document = nil; values = [:]; pendingAction = nil; confirmedAction = nil; fieldRevisions = [:]
            if !browser.isLoading { await read() }
        }
        .refreshable { await read(preservingEdits: true) }
        .onDisappear { fieldRevisions = [:] }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !busy, !browser.isLoading, pendingAction == nil, confirmedAction == nil else { continue }
                let status = try? await execute(command: "watch")
                guard status?["changed"] as? Bool == true, pendingAction == nil, confirmedAction == nil else { continue }
                await read(preservingEdits: true)
            }
        }
        .sheet(item: $pendingAction, onDismiss: {
            guard let action = confirmedAction else { return }
            confirmedAction = nil
            Task { await activate(action) }
        }) { action in
            NavigationStack {
                List {
                    Section("学校操作") {
                        Text(action.title).font(.headline)
                        if !action.context.isEmpty { Text(action.context).textSelection(.enabled) }
                    }
                    if let document {
                        Section("当前表单内容") {
                            ForEach(document.fields) { field in LabeledContent(field.label, value: displayValue(field)) }
                        }
                    }
                    Section {
                        Text("继续后执行学校页面的对应操作，并展示学校返回的页面以核对办理或订单结果。").font(.footnote)
                        Button("继续「\(action.title)」") {
                            confirmedAction = action
                            pendingAction = nil
                        }.disabled(busy)
                    }
                }
                .navigationTitle("核对操作").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { pendingAction = nil } } }
            }
        }
    }

    @ViewBuilder private func fieldEditor(_ field: NativeServiceDocument.Field) -> some View {
        let binding = Binding(get: { values[field.id] ?? field.value }, set: { value in
            values[field.id] = value
            if ["select", "radio", "checkbox", "toggle", "choice", "multiselect", "date", "time", "datetime-local"].contains(field.kind) {
                queueUpdate(field, value: value)
            }
        })
        let title = field.label + (field.required ? " *" : "")
        if field.readOnly {
            LabeledContent(title, value: field.value).textSelection(.enabled)
        } else if ["checkbox", "toggle"].contains(field.kind) {
            Toggle(title, isOn: Binding(get: { binding.wrappedValue == "true" }, set: { binding.wrappedValue = String($0) }))
        } else if field.kind == "choice" {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(title, value: field.value.isEmpty ? "请选择" : field.value)
                if field.options.isEmpty {
                    Button("选择\(field.label)", systemImage: "chevron.down") { Task { await open(field) } }
                } else {
                    ForEach(Array(field.options.enumerated()), id: \.offset) { _, option in
                        Button(option.title) { queueUpdate(field, value: option.value) }
                    }
                }
            }
        } else if field.kind == "multiselect" {
            VStack(alignment: .leading) {
                Text(title).font(.subheadline)
                ForEach(Array(field.options.enumerated()), id: \.offset) { _, option in
                    Toggle(option.title, isOn: Binding(get: { selectedValues(binding.wrappedValue).contains(option.value) }, set: { selected in
                        var choices = selectedValues(binding.wrappedValue)
                        if selected { choices.insert(option.value) } else { choices.remove(option.value) }
                        let ordered = field.options.filter { choices.contains($0.value) }.map(\.value)
                        if let data = try? JSONEncoder().encode(ordered), let value = String(data: data, encoding: .utf8) { binding.wrappedValue = value }
                    }))
                }
            }
        } else if ["date", "time", "datetime-local"].contains(field.kind) {
            VStack(alignment: .leading) {
                if dateValue(field.value, kind: field.kind) == nil {
                    Text("\(title)：\(field.value.isEmpty ? "请选择" : field.value)").font(.subheadline)
                }
                if binding.wrappedValue.isEmpty {
                    Button(field.kind == "date" ? "设为今天" : "使用当前时间") { binding.wrappedValue = dateText(Date(), kind: field.kind) }
                }
                DatePicker(title, selection: Binding(get: { dateValue(binding.wrappedValue, kind: field.kind) ?? Date() }, set: {
                    binding.wrappedValue = dateText($0, kind: field.kind)
                }), displayedComponents: field.kind == "time" ? [.hourAndMinute] : field.kind == "date" ? [.date] : [.date, .hourAndMinute])
                    .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
            }
        } else if field.kind == "select" || field.kind == "radio" {
            Picker(title, selection: binding) {
                if !field.options.contains(where: { $0.value == binding.wrappedValue }) { Text("请选择").tag(binding.wrappedValue) }
                ForEach(Array(field.options.enumerated()), id: \.offset) { _, option in Text(option.title).tag(option.value) }
            }
        } else if field.kind == "textarea" {
            VStack(alignment: .leading) {
                Text(title).font(.subheadline)
                TextEditor(text: binding).frame(minHeight: 100)
            }
        } else {
            TextField(title, text: binding, prompt: Text(field.kind == "date" ? "YYYY-MM-DD" : title))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(field.kind == "number" ? .decimalPad : field.kind == "email" ? .emailAddress : .default)
        }
    }

    private func execute(command: String, actionID: String = "", fieldValues: [String: String]? = nil) async throws -> [String: Any] {
        let session = environment.session
        let epoch = session.requestEpoch
        guard session.phase == .loggedIn, let url = browser.webView.url else { throw CancellationError() }
        let original = WebVPN.unwrap(url) ?? url
        guard original.scheme == "https", original.user == nil, original.password == nil,
              original.port == nil || original.port == 443, let host = original.host?.lowercased(), service.owns(host: host) else {
            throw NetworkError(message: "请先在学校页面完成认证并进入\(service.title)，再切换原生视图")
        }
        let raw = try await browser.webView.callAsyncJavaScript(NativeServiceDocument.bridge, arguments: [
            "command": command, "token": document?.token ?? "", "actionID": actionID, "values": fieldValues ?? values,
        ], in: nil, contentWorld: Self.world)
        guard session.phase == .loggedIn, session.requestEpoch == epoch, !Task.isCancelled else { throw CancellationError() }
        guard command == "act" || browser.webView.url == url else { throw CancellationError() }
        guard let result = raw as? [String: Any] else { throw NetworkError(message: "学校页面暂未提供可读取内容") }
        if let code = result["error"] as? String {
            if code == "validation" { throw NetworkError(message: (result["message"] as? String) ?? "请在学校页面检查必填字段") }
            throw NetworkError(message: "学校页面内容已变化，请重新读取并核对后继续")
        }
        return result
    }

    private func read(preservingEdits: Bool = false, changedKey: String? = nil) async {
        let drafts: [String: String] = preservingEdits ? Dictionary((document?.fields ?? []).compactMap { field in
            guard let key = field.key, key != changedKey, let value = values[field.id], value != field.value else { return nil }
            return (key, value)
        }, uniquingKeysWith: { first, _ in first }) : [:]
        let token = UUID(); request = token
        busy = true
        defer { if request == token { busy = false } }
        do {
            if service == .payment { await browser.prefillElectricityRoom(environment.repository.electricRoomCode) }
            let raw = try await execute(command: "read")
            let result = try JSONDecoder().decode(NativeServiceDocument.self, from: JSONSerialization.data(withJSONObject: raw))
            guard request == token else { return }
            document = result
            values = Dictionary(uniqueKeysWithValues: result.fields.map { field in
                let draft = field.key.flatMap { drafts[$0] }
                let valid = draft.map { value in
                    !["select", "radio"].contains(field.kind) || field.options.contains { $0.value == value }
                } ?? false
                return (field.id, valid ? draft! : field.value)
            })
            error = nil
            if result.requiresWebsite == true { showWebsite() }
        } catch {
            guard request == token, !NetworkError.isCancellation(error) else { return }
            document = nil; values = [:]; self.error = NetworkError.from(error).message
        }
    }

    private func selectedValues(_ text: String) -> Set<String> {
        guard let data = text.data(using: .utf8), let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values)
    }

    private func displayValue(_ field: NativeServiceDocument.Field) -> String {
        let value = values[field.id] ?? field.value
        if ["checkbox", "toggle"].contains(field.kind) { return value == "true" ? "已选" : "未选" }
        if field.kind == "multiselect" { return field.options.filter { selectedValues(value).contains($0.value) }.map(\.title).joined(separator: "、") }
        return field.options.first { $0.value == value }?.title ?? value
    }

    private func dateFormatter(kind: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = kind == "time" ? "HH:mm" : kind == "datetime-local" ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    private func dateValue(_ text: String, kind: String) -> Date? { dateFormatter(kind: kind).date(from: text) }
    private func dateText(_ date: Date, kind: String) -> String { dateFormatter(kind: kind).string(from: date) }

    private func open(_ field: NativeServiceDocument.Field) async {
        guard !busy else { return }
        busy = true
        do {
            _ = try await execute(command: "open", actionID: field.id, fieldValues: [:])
            try await Task.sleep(for: .milliseconds(150))
            await read(preservingEdits: true)
        } catch {
            if !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message }
        }
        busy = false
    }

    private func queueUpdate(_ field: NativeServiceDocument.Field, value: String) {
        let key = field.key ?? field.id
        let revision = UUID()
        fieldRevisions[key] = revision
        Task { await update(field, value: value, revision: revision) }
    }

    private func update(_ field: NativeServiceDocument.Field, value: String, revision: UUID) async {
        let key = field.key ?? field.id
        while busy {
            guard fieldRevisions[key] == revision, !Task.isCancelled else { return }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard fieldRevisions[key] == revision, !Task.isCancelled,
              let current = document?.fields.first(where: { ($0.key ?? $0.id) == key }) else { return }
        busy = true
        do {
            _ = try await execute(command: "change", actionID: current.id, fieldValues: [current.id: value])
            try await Task.sleep(for: .milliseconds(200))
            await read(preservingEdits: true, changedKey: fieldRevisions[key] == revision ? current.key : nil)
        } catch {
            if !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message }
        }
        busy = false
    }

    private func activate(_ action: NativeServiceDocument.Action) async {
        guard !busy, document != nil else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await execute(command: "act", actionID: action.id)
            guard result["activated"] as? Bool == true else { return }
            document = nil; values = [:]
            if service == .academic || action.query == true {
                try await Task.sleep(for: .milliseconds(250))
                await read()
            } else { showWebsite() }
        } catch {
            if !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message }
            document = nil
        }
    }

    private func openWebsite() async {
        guard document != nil else { showWebsite(); return }
        busy = true
        defer { busy = false }
        do {
            _ = try await execute(command: "fill")
            showWebsite()
        } catch {
            if !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message }
            document = nil
        }
    }
}

