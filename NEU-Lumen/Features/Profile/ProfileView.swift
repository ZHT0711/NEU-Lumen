import SwiftUI

/// 我的：账号信息、会话管理、关于与免责声明。
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var path: [AppDestination] = []
    @Environment(\.colorScheme) private var colorScheme
    private var campusInk: Color {
        colorScheme == .dark ? Color(red: 0.59, green: 0.69, blue: 0.95) : AppTheme.accent
    }
    @State private var showWebLogin = false
    @State private var confirmLogout = false

    private var version: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(name) (\(build))"
    }

    private var campusExploreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("走进东大", systemImage: "building.columns").font(.headline)
            Button {
                path.append(.web(URL(string: "https://www.neu.edu.cn/xygk/dxwh.htm")!))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自强不息\n知行合一")
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .tracking(4)
                        Label("东大精神，日常相伴", systemImage: "arrow.up.right")
                            .font(.caption)
                    }
                    Spacer()
                }
                .foregroundStyle(campusInk)
                .padding(20)
                .frame(minHeight: 136)
                .background {
                    ZStack {
                    AppTheme.accent.opacity(0.045)
                    GeometryReader { geometry in
                        CampusLineArt()
                            .stroke(campusInk.opacity(0.12), lineWidth: 1)
                            .frame(width: geometry.size.width * 0.62, height: 145)
                            .offset(x: geometry.size.width * 0.44, y: 10)
                    }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            HStack {
                campusLink("东大官网", icon: "globe.asia.australia", url: "https://www.neu.edu.cn/")
                campusLink("校史纵览", icon: "building.columns", url: "https://www.neu.edu.cn/xygk/lsyg.htm")
            }
        }
    }

    private func campusLink(_ title: String, icon: String, url: String) -> some View {
        Button { path.append(.web(URL(string: url)!)) } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AppTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image("NEUEmblemDark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(environment.session.user?.displayName ?? "未登录")
                                .font(.headline)
                            Text(environment.session.user?.sid ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let details = environment.session.user?.identityDetails, !details.isEmpty {
                                Text(details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let email = environment.session.user?.email, !email.isEmpty {
                                Text(email).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    if environment.session.user?.hasCoreProfile != true {
                        Text("个人资料尚未同步完整").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = environment.session.profileSyncError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    Button(environment.session.refreshingProfile ? "正在同步…" : "刷新个人资料") {
                        Task { await environment.session.refreshUserProfile() }
                    }
                    .disabled(environment.session.refreshingProfile)
                }

                Section("会话") {
                    LabeledContent("记住的账号", value: environment.session.rememberedUsername.isEmpty ? "未保存" : environment.session.rememberedUsername)
                    LabeledContent("保持登录", value: environment.session.usesWebSession ? "已开启（网页登录会话）" :
                        (environment.session.hasSavedCredentials ? "已开启（钥匙串加密）" : "关闭"))
                    if let error = environment.session.sessionSaveError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    Button("更新网页登录（保留账号和收藏）") { showWebLogin = true }
                    LabeledContent("登录会话", value: environment.session.client.hasLoginSession ? "已取得" : "需重新登录")
                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        Text("退出登录")
                    }
                }

                Section { campusExploreSection }

                Section("关于") {
                    VStack(spacing: 10) {
                        Image("NEULogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                        Image("NEUMotto")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 26)
                            .accessibilityLabel("校训：知行合一")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    LabeledContent("版本", value: version)
                    LabeledContent("数据来源", value: "东北大学一号通门户")
                    Link(destination: URL(string: "https://github.com/ZHT0711/NEU-Lumen")!) {
                        LabeledContent("GitHub 仓库", value: "ZHT0711/NEU-Lumen")
                    }
                }

                Section {
                    Text("NEU-Lumen 是东北大学一号通门户（personal.neu.edu.cn）的第三方原生 iOS 客户端，与学校官方无关。凭据仅保存在本机钥匙串，不上传、不打日志；请遵守学校相关使用规定。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("隐私与免责声明")
                }
            }
            .tracksTabBarScrolling()
            .sheet(isPresented: $showWebLogin) {
                WebLoginSheet { await environment.session.completeWebLogin($0) }
            }
            .navigationTitle("我的")
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .web(let url): PortalWebViewScreen(url: url)
                case .card: CardView()
                }
            }
            .alert("退出登录？", isPresented: $confirmLogout) {
                Button("退出", role: .destructive) {
                    environment.session.logout()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除本机保存的会话与凭据。")
            }
        }
    }
}
