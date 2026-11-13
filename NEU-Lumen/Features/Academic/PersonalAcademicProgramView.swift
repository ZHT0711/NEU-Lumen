import SwiftUI
import Observation

@MainActor @Observable
private final class PersonalProgramStore {
    var programs: [PersonalAcademicProgram] = []
    var tree: AcademicProgramTree?
    var loading = false
    var error: String?
    private var owner: UUID?
    private var request = UUID()

    func load(session: SessionStore, program: PersonalAcademicProgram? = nil) async {
        let epoch = session.requestEpoch
        if owner != epoch { programs = []; tree = nil; error = nil; owner = epoch }
        guard session.phase == .loggedIn, let account = session.user?.sid, !account.isEmpty else { return }
        let token = UUID(); request = token; loading = true; error = nil
        defer { if request == token { loading = false } }
        do {
            if let program {
                tree = nil
                let value = try await session.client.fetchPersonalProgramTree(program, expectedAccount: account)
                guard session.requestEpoch == epoch, request == token, !Task.isCancelled else { return }
                tree = value
            } else {
                let values = try await session.client.fetchPersonalPrograms(expectedAccount: account)
                guard session.requestEpoch == epoch, request == token, !Task.isCancelled else { return }
                programs = values
            }
            session.persistWebSession()
        } catch {
            guard session.requestEpoch == epoch, request == token, !NetworkError.isCancellation(error) else { return }
            self.error = NetworkError.from(error).message
        }
    }
}

struct AcademicPlanView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store = PersonalProgramStore()
    @State private var web: NativeServiceWebLink?
    static let schoolURL = URL(string: "https://jwxt.neu.edu.cn/jwapp/sys/pyfagl/*default/index.do?forceApp=pyfagl#/pyfacxcd")!
    var body: some View {
        List {
            if store.loading { ProgressView("读取个人培养方案…") }
            if let error = store.error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("重新读取") { Task { await store.load(session: environment.session) } }
                    Button("打开学校培养方案查询") { web = NativeServiceWebLink(url: Self.schoolURL) }
                }
            }
            Section("个人培养方案查询") {
                ForEach(store.programs) { program in
                    NavigationLink { PersonalAcademicProgramDetail(program: program) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(program.name).font(.headline)
                            if let credits = program.minimumCredits { Text("最少要求 \(credits) 学分").font(.subheadline) }
                            Text(program.facts.map(\.value).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            Text("查看详情").font(.subheadline).foregroundStyle(AppTheme.accent)
                        }.padding(.vertical, 6)
                    }
                }
                if !store.loading && store.error == nil && store.programs.isEmpty {
                    ContentUnavailableView("学校未返回个人培养方案", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            Section {
                NavigationLink("已同步的课程表") { AcademicSyncedCoursesView() }
                Button("学校培养方案查询", systemImage: "globe") { web = NativeServiceWebLink(url: Self.schoolURL) }
            }
        }
        .navigationTitle("培养计划").navigationBarTitleDisplayMode(.inline)
        .task(id: environment.session.requestEpoch) { await store.load(session: environment.session) }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if store.error != nil || store.loading { Task { await store.load(session: environment.session) } }
        }
        .refreshable { await store.load(session: environment.session) }
        .sheet(item: $web) { link in NavigationStack { PortalWebViewScreen(url: link.url) } }
    }
}

private struct PersonalAcademicProgramDetail: View {
    let program: PersonalAcademicProgram
    @Environment(AppEnvironment.self) private var environment
    @State private var store = PersonalProgramStore()
    @State private var collapsed = Set<String>()
    @State private var selected: AcademicProgramNode?
    @State private var query = ""
    @State private var zoom = 1.0
    @State private var showOutline = false
    @ScaledMetric(relativeTo: .body) private var nodeScale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var web: NativeServiceWebLink?
    var body: some View {
        VStack(spacing: 0) {
            if store.loading { ProgressView("读取培养方案详情与课组层级…").padding() }
            if let error = store.error {
                ErrorStateView(message: error) { Task { await store.load(session: environment.session, program: program) } }
                Button("打开学校详情") { web = NativeServiceWebLink(url: AcademicPlanView.schoolURL) }.padding()
            }
            if let tree = store.tree {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tree.program.name).font(.headline)
                    HStack {
                        if let credits = tree.program.minimumCredits { Text("最少要求 \(credits) 学分").font(.subheadline) }
                        Spacer()
                        Menu("展开与缩放", systemImage: "slider.horizontal.3") {
                            Button(showOutline ? "查看思维导图" : "查看层级大纲") { showOutline.toggle() }
                            if !showOutline {
                                Button("展开全部") { collapsed = [] }
                                Button("收起到平台") { collapsed = Set(tree.nodes.filter { $0.parentID != nil }.map(\.id)) }
                                Button("恢复大小") { zoom = 1 }
                            }
                        }
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索平台或课组", text: $query)
                        if !showOutline {
                            Button("缩小", systemImage: "minus.magnifyingglass") { zoom = max(0.4, zoom - 0.15) }
                                .frame(minWidth: 44, minHeight: 44)
                            Text(zoom.formatted(.percent.precision(.fractionLength(0)))).font(.caption).monospacedDigit()
                            Button("放大", systemImage: "plus.magnifyingglass") { zoom = min(1.8, zoom + 0.15) }
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }.labelStyle(.iconOnly)
                }.padding(16)
                Divider()
                if showOutline { outline(tree) } else { diagram(tree) }
                Text(showOutline ? "展开层级，点课组查看课程。" : "拖动查看分支，点课组查看课程，点展开按钮折叠下级。")
                    .font(.caption).foregroundStyle(.secondary).padding(10)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("培养方案详情").navigationBarTitleDisplayMode(.inline)
        .task(id: environment.session.requestEpoch) {
            selected = nil; collapsed = []; query = ""
            showOutline = typeSize.isAccessibilitySize
            await store.load(session: environment.session, program: program)
            if let tree = store.tree { collapsed = Set(tree.nodes.filter(\.inherited).map(\.id)) }
        }
        .sheet(item: $selected) { node in
            if let tree = store.tree { AcademicProgramCourses(tree: tree, node: node) }
        }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if store.error != nil || store.loading { Task { await store.load(session: environment.session, program: program) } }
        }
        .sheet(item: $web) { link in NavigationStack { PortalWebViewScreen(url: link.url) } }
    }

    private func diagram(_ tree: AcademicProgramTree) -> some View {
        let layout = AcademicProgramLayout(tree: tree, collapsed: collapsed, query: query)
        let width = CGFloat(layout.columns * 284 + 24) * nodeScale, height = CGFloat(layout.height + 24) * nodeScale
        let positions = Dictionary(uniqueKeysWithValues: layout.items.map { ($0.id, CGPoint(x: CGFloat($0.depth * 284 + 136) * nodeScale, y: CGFloat($0.y + 12) * nodeScale)) })
        return ScrollView([.horizontal, .vertical]) {
            if layout.items.isEmpty { ContentUnavailableView.search(text: query).frame(width: 320, height: 200) }
            else {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for item in layout.items {
                            guard let parentID = item.node.parentID, let parent = positions[parentID], let child = positions[item.id] else { continue }
                            let start = CGPoint(x: parent.x + 116 * nodeScale, y: parent.y), end = CGPoint(x: child.x - 116 * nodeScale, y: child.y)
                            var path = Path(); path.move(to: start)
                            path.addCurve(to: end, control1: CGPoint(x: start.x + 28, y: start.y), control2: CGPoint(x: end.x - 28, y: end.y))
                            context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 1.5)
                        }
                    }.frame(width: width, height: height).accessibilityHidden(true)
                    ForEach(layout.items) { item in
                        nodeCard(item.node, tree: tree).frame(width: 232 * nodeScale, height: 110 * nodeScale).position(positions[item.id]!)
                    }
                }.frame(width: width, height: height)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(width: width * zoom, height: height * zoom, alignment: .topLeading)
            }
        }
    }

    private func outline(_ tree: AcademicProgramTree) -> some View {
        let layout = AcademicProgramLayout(tree: tree, collapsed: [], query: query)
        let visible = Set(layout.items.map(\.id))
        func branch(_ node: AcademicProgramNode) -> ProgramOutlineBranch {
            let children = tree.children(of: node.id).filter { visible.contains($0.id) }.map(branch)
            return ProgramOutlineBranch(node: node, children: children.isEmpty ? nil : children)
        }
        let roots = tree.nodes.filter { $0.parentID == nil && visible.contains($0.id) }.map(branch)
        return List {
            if roots.isEmpty { ContentUnavailableView.search(text: query) }
            OutlineGroup(roots, children: \.children) { branch in
                Button { selected = branch.node } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(branch.node.name).foregroundStyle(.primary)
                        if let credits = branch.node.minimumCredits { Text("至少 \(credits) 学分").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
            }
        }
    }

    private func nodeCard(_ node: AcademicProgramNode, tree: AcademicProgramTree) -> some View {
        HStack(spacing: 4) {
            Button { selected = node } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(node.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    Text(node.minimumCredits.map { "至少 \($0) 学分" } ?? "学分要求未提供").font(.caption).foregroundStyle(.secondary)
                    Text([node.kind, node.minimumGroups.map { "至少完成 \($0) 个课组" }, node.mustPass ? "必过" : nil,
                          node.inherited ? "继承" : nil, node.referenced ? "引用" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.buttonStyle(.plain).accessibilityLabel(node.name + "，查看课程")
            if !tree.children(of: node.id).isEmpty {
                Button {
                    if collapsed.contains(node.id) { collapsed.remove(node.id) } else { collapsed.insert(node.id) }
                } label: { Image(systemName: collapsed.contains(node.id) ? "plus.circle" : "minus.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel((collapsed.contains(node.id) ? "展开" : "收起") + node.name)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(node.parentID == nil ? AppTheme.accent : Color.secondary.opacity(0.3), lineWidth: 1.5))
    }
}

private struct ProgramOutlineBranch: Identifiable {
    let node: AcademicProgramNode
    let children: [ProgramOutlineBranch]?
    var id: String { node.id }
}

private struct AcademicProgramCourses: View {
    let tree: AcademicProgramTree
    let node: AcademicProgramNode
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var courses: [AcademicPageCourse] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    @State private var selected: AcademicPageCourse?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(node.name).font(.headline)
                    if let credits = node.minimumCredits { LabeledContent("至少达到学分", value: credits) }
                    if let count = node.minimumGroups { LabeledContent("至少完成课组", value: count) }
                }
                if loading { ProgressView("读取学校课组课程…") }
                if let error { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
                ForEach(courses.filter { $0.matches(query) }) { course in
                    Button { selected = course } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(course.name).foregroundStyle(.primary)
                            Text([course.code, course.creditsText.map { $0 + " 学分" }, course.category, course.suggestedTerm].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !loading && error == nil && courses.isEmpty { Text("学校未返回本节点的课程").foregroundStyle(.secondary) }
            }
            .navigationTitle("课组课程").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索课程名称或代码")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task(id: environment.session.requestEpoch) { await load() }
            .onChange(of: environment.session.networkRevision) { _, _ in
                if error != nil || loading { Task { await load() } }
            }
            .sheet(item: $selected) { AcademicCourseDetail(course: $0) }
        }
    }
    private func load() async {
        let epoch = environment.session.requestEpoch
        courses = []; selected = nil; loading = true; error = nil
        guard let account = environment.session.user?.sid, !account.isEmpty else { loading = false; return }
        do {
            let result = try await environment.session.client.fetchPersonalProgramCourses(tree, node: node, expectedAccount: account)
            guard epoch == environment.session.requestEpoch, !Task.isCancelled else { return }
            courses = result; loading = false
        } catch {
            guard epoch == environment.session.requestEpoch, !NetworkError.isCancellation(error) else { return }
            self.error = NetworkError.from(error).message; loading = false
        }
    }
}
