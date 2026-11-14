import SwiftUI

struct AcademicServicesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var query = ""
    @State private var category = "全部"
    @State private var page: NativeServiceWebLink?
    private var repo: PortalRepository { environment.repository }
    private var categories: [String] { ["全部"] + Array(Set(repo.academicServices.map(\.category))).sorted() }
    private var filtered: [AcademicServiceItem] {
        repo.academicServices.filter {
            (category == "全部" || $0.category == category) && (query.isEmpty || $0.path.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        List {
            Section {
                Picker("功能分类", selection: $category) { ForEach(categories, id: \.self) { Text($0).tag($0) } }
                Text("当前账号可见的 \(repo.academicServices.count) 项功能，来自学校实时授权目录。")
                    .font(.footnote).foregroundStyle(.secondary)
            } footer: {
                Text("查询、选课、考试、学籍、培养、评教及其他功能按学校当前权限显示。进入后原生呈现可识别的查询条件、表格和表单；操作先核对再交由学校处理，复杂控件可切回原页面。")
            }
            if repo.academicServicesState == .loading { ProgressView("读取学校全部功能…") }
            if let error = repo.academicServicesError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("重新读取目录") { Task { await repo.loadAcademicServices(force: true) } }
                    Button("打开教务原站") { page = NativeServiceWebLink(url: NativeCampusService.academic.fallbackURL) }
                }
            }
            if filtered.isEmpty, repo.academicServicesState == .loaded {
                ContentUnavailableView.search(text: query)
            }
            ForEach(Array(Dictionary(grouping: filtered, by: \.category).keys).sorted(), id: \.self) { name in
                Section(name) {
                    ForEach(filtered.filter { $0.category == name }) { service in
                        Button {
                            if let url = service.url { page = NativeServiceWebLink(url: url) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "rectangle.grid.1x2").foregroundStyle(AppTheme.accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(service.title).foregroundStyle(.primary)
                                    Text(service.path).font(.caption).foregroundStyle(.secondary)
                                    if service.url == nil { Text("学校暂未提供可解析入口，请在原站查看").font(.caption).foregroundStyle(.orange) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: service.isSchoolAcademicPage ? "chevron.right" : "arrow.up.right.square")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 5).multilineTextAlignment(.leading)
                        }.disabled(service.url == nil)
                    }
                }
            }
        }
        .navigationTitle("全部教务功能").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索学校功能、栏目或办理事项")
        .task(id: environment.session.requestEpoch) { category = "全部"; page = nil; await repo.loadAcademicServices() }
        .refreshable { await repo.loadAcademicServices(force: true) }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if repo.academicServicesError != nil || repo.academicServicesState == .loading { Task { await repo.loadAcademicServices(force: true) } }
        }
        .sheet(item: $page) { link in NavigationStack { PortalWebViewScreen(url: link.url, nativeService: .academic) } }
    }
}

struct AcademicExamsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var term = ""
    @State private var query = ""
    private var repo: PortalRepository { environment.repository }
    private var exams: [AcademicExam] {
        repo.academicExams(term: term).filter {
            query.isEmpty || [$0.title, $0.place, $0.type].contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
    var body: some View {
        List {
            Section {
                Picker("考试学期", selection: $term) { ForEach(repo.academicTerms) { Text($0.name).tag($0.code) } }
                    .onChange(of: term) { old, new in if old != new, !new.isEmpty { Task { await repo.loadAcademicExams(term: new) } } }
                NavigationLink("查询其他考试与报名业务") { AcademicServicesView() }
            }
            if case .failed(let message) = repo.academicState(for: .terms) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("重新读取学校学期") {
                    Task {
                        await repo.loadAcademicQuery(.terms, force: true)
                        term = (repo.academicTerms.first { $0.current } ?? repo.academicTerms.first)?.code ?? ""
                    }
                }
            }
            if repo.academicExamsState(term: term) == .loading { ProgressView("读取学校考试安排…") }
            if let error = repo.academicExamsError(term: term) {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("重新读取考试安排") { Task { await repo.loadAcademicExams(term: term, force: true) } }
            }
            if let date = repo.academicExamsDate(term: term) {
                Text("学校考试安排 · " + date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            if exams.isEmpty, repo.academicExamsState(term: term) == .loaded {
                ContentUnavailableView("暂无已发布的考试安排", systemImage: "calendar.badge.checkmark", description: Text("学校未提供具体时间的考试不会安排定时通知。"))
            }
            ForEach(exams) { exam in
                Section {
                    Text(exam.title).font(.headline)
                    if !exam.type.isEmpty { LabeledContent("考试类型", value: exam.type) }
                    LabeledContent("日期", value: exam.dateText.isEmpty ? "学校未提供" : exam.dateText)
                    LabeledContent("时间", value: exam.timeText.isEmpty ? "学校未提供" : exam.timeText)
                    LabeledContent("地点", value: exam.place.isEmpty ? "学校未提供" : exam.place)
                    if !exam.seat.isEmpty { LabeledContent("座位号", value: exam.seat) }
                    if !exam.teachers.isEmpty { LabeledContent("监考教师", value: exam.teachers) }
                    if let date = exam.start {
                        Text(date > Date() ? "可在“提醒与通知”中开启考试提醒" : "此考试时间已过")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.textSelection(.enabled)
            }
        }
        .navigationTitle("考试安排").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索课程、地点或考试类型")
        .task(id: environment.session.requestEpoch) {
            await repo.loadAcademicQuery(.terms)
            term = (repo.academicTerms.first { $0.current } ?? repo.academicTerms.first)?.code ?? ""
            if !term.isEmpty { await repo.loadAcademicExams(term: term) }
        }
        .refreshable { await repo.loadAcademicExams(term: term, force: true) }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if repo.academicExamsError(term: term) != nil || repo.academicExamsState(term: term) == .loading {
                Task { await repo.loadAcademicExams(term: term, force: true) }
            }
        }
    }
}
