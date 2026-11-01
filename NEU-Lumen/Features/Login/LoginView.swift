import SwiftUI

/// 统一身份认证登录：RSA 加密提交，密码默认只参与本次认证；
/// 勾选「保持登录」后凭据经 Keychain 加密存本机用于静默续登。
/// 新设备登录会进入图形码 + 短信二次认证流程。
struct LoginView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var username = ""
    @State private var password = ""
    @State private var keepLoggedIn = true
    @State private var showPassword = false

    // 二次认证
    @State private var captchaData: Data?
    @State private var graphicCode = ""
    @State private var smsCode = ""
    @State private var smsRequested = false
    @State private var secondAuthBusy = false
    @State private var secondAuthError: String?

    private var isLoading: Bool {
        environment.session.phase == .loggingIn
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                if environment.session.needsSecondAuth {
                    secondAuthCard
                } else {
                    credentialCard
                    if let error = environment.session.lastError {
                        errorBanner(error)
                    }
                    loginButton
                }

                VStack(spacing: 6) {
                    Text("使用东北大学统一身份认证（CAS）登录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("校外或移动网络下如提示「账号不存在」，请切换至校园网 WiFi 后重试")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .task {
            if username.isEmpty {
                username = environment.session.rememberedUsername
            }
            if environment.session.needsSecondAuth {
                await loadCaptcha()
            }
        }
        .onChange(of: environment.session.needsSecondAuth) { _, needed in
            if needed {
                Task { await loadCaptcha() }
            }
        }
    }

    // MARK: - 账号密码

    private var credentialCard: some View {
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
    }

    private var loginButton: some View {
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
    }

    private func errorBanner(_ error: String) -> some View {
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

    // MARK: - 二次认证

    private var secondAuthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("新设备短信验证", systemImage: "shield.lefthalf.filled.badge.checkmark")
                    .font(.subheadline.bold())
                Text("检测到新设备登录，需要完成短信二次认证：先输入图片中的图形码获取短信，再填入短信验证码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Group {
                        if let data = captchaData, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 38)
                        } else {
                            ProgressView()
                                .frame(height: 38)
                        }
                    }
                    .frame(width: 104)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    TextField("图形码", text: $graphicCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button {
                        Task { await loadCaptcha() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                if smsRequested {
                    TextField("短信验证码", text: $smsCode)
                        .keyboardType(.numberPad)
                    if secondAuthBusy {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在验证…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            Task { await submitSecondAuth() }
                        } label: {
                            Text("验证并登录")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(smsCode.isEmpty)
                    }
                } else if secondAuthBusy {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在发送短信…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task { await sendSMS() }
                    } label: {
                        Text("发送短信验证码")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(graphicCode.isEmpty)
                }

                if let error = secondAuthError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("返回重新登录") {
                    smsRequested = false
                    smsCode = ""
                    graphicCode = ""
                    captchaData = nil
                    secondAuthError = nil
                    environment.session.cancelSecondAuth()
                }
                .font(.footnote)
            }
            .padding(18)
        }
    }

    private func loadCaptcha() async {
        secondAuthError = nil
        do {
            captchaData = try await environment.session.client.fetchSecondAuthCaptcha()
        } catch {
            secondAuthError = (error as? NetworkError)?.message ?? error.localizedDescription
        }
    }

    private func sendSMS() async {
        secondAuthBusy = true
        secondAuthError = nil
        defer { secondAuthBusy = false }
        do {
            try await environment.session.client.requestSecondAuthSMS(graphicCode: graphicCode)
            smsRequested = true
        } catch {
            secondAuthError = (error as? NetworkError)?.message ?? error.localizedDescription
            await loadCaptcha()
        }
    }

    private func submitSecondAuth() async {
        secondAuthBusy = true
        secondAuthError = nil
        defer { secondAuthBusy = false }
        do {
            let user = try await environment.session.client.submitSecondAuth(smsCode: smsCode)
            environment.session.completeSecondAuth(
                username: username,
                password: password,
                keep: keepLoggedIn,
                user: user
            )
        } catch {
            secondAuthError = (error as? NetworkError)?.message ?? error.localizedDescription
            smsCode = ""
        }
    }

    // MARK: - 头部与动作

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
