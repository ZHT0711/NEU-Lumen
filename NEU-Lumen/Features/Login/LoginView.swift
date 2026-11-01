import SwiftUI

/// 统一身份认证登录：RSA 加密提交，密码默认只参与本次认证；
/// 勾选「保持登录」后凭据经 Keychain 加密存本机用于静默续登。
struct LoginView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var username = ""
    @State private var password = ""
    @State private var keepLoggedIn = true
    @State private var showPassword = false

    private var isLoading: Bool {
        environment.session.phase == .loggingIn
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "person.text.rectangle")
                                .foregroundStyle(.secondary)
                            TextField("学号 / 工号", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .disabled(isLoading)
                        }
                        Divider()
                        HStack {
                            Image(systemName: "lock")
                                .foregroundStyle(.secondary)
                            Group {
                                if showPassword {
                                    TextField("密码", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField("密码", text: $password)
                                }
                            }
                            .disabled(isLoading)
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        Toggle(isOn: $keepLoggedIn) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("保持登录")
                                    .font(.subheadline)
                                Text("凭据加密保存到本机钥匙串，重启自动续登")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isLoading)
                    }
                    .padding(18)
                }

                if let error = environment.session.lastError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.footnote)
                        Text(error)
                            .font(.footnote)
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button(action: login) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                            Text("登录中…")
                        } else {
                            Text("登录")
                                .bold()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading || username.isEmpty || password.isEmpty)

                VStack(spacing: 6) {
                    Text("使用东北大学统一身份认证（CAS）登录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("校外或移动网络下如提示「账号不存在」，请切换校园网或先登录校园 WebVPN")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .task {
            if username.isEmpty {
                username = environment.session.rememberedUsername
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [AppTheme.accent, AppTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 92, height: 92)
                Image("NEUEmblem")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
            }
            VStack(spacing: 5) {
                Text("NEU-Lumen")
                    .font(.title.bold())
                Text("东北大学一号通门户 · 原生 iOS 客户端")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image("NEUMotto")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .accessibilityLabel("校训：知行合一")
            }
        }
        .padding(.bottom, 8)
    }

    private func login() {
        guard !isLoading else { return }
        Task {
            await environment.session.performLogin(username: username, password: password, keep: keepLoggedIn)
        }
    }
}
