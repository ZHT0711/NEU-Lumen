import SwiftUI

/// 我的：账号信息、会话管理、关于与免责声明。
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmLogout = false

    private var version: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(name) (\(build))"
    }

    var body: some View {
        NavigationStack {
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
                    LabeledContent("登录会话", value: environment.session.client.hasLoginSession ? "已取得" : "需重新登录")
                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        Text("退出登录")
                    }
                }

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
            .navigationTitle("我的")
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
