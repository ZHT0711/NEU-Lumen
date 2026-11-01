import SwiftUI

/// 我的：账号信息、会话管理、关于与免责声明。
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmLogout = false

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
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
                            Text(environment.session.user?.name ?? "未登录")
                                .font(.headline)
                            Text(environment.session.user?.sid ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let identity = environment.session.user?.identity, !identity.isEmpty {
                                Text("\(identity) · \(environment.session.user?.department ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("会话") {
                    LabeledContent("记住的账号", value: environment.session.rememberedUsername.isEmpty ? "未保存" : environment.session.rememberedUsername)
                    LabeledContent("保持登录", value: environment.session.hasSavedCredentials ? "已开启（钥匙串加密）" : "关闭")
                    LabeledContent("门户会话", value: environment.session.client.isLoggedIn ? "有效" : "无效")
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
