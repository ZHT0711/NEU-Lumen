# 贡献指南

欢迎为 NEU-Lumen 报告问题、完善文档或提交代码。GitHub Issues 和 Pull Requests 均可使用中文。

## 报告问题

- 在 [Issues](https://github.com/ZHT0711/NEU-Lumen/issues) 搜索相关问题。报告时提供 Nightly 构建编号或提交 SHA、iOS 版本、机型、复现步骤、预期行为和实际结果。注明使用真机或模拟器、校园网或校外网络，以及是否通过 WebVPN。
- 日志、截图和测试夹具请使用合成或脱敏数据。提交前移除账号、学号、密码、验证码、Cookie、令牌和可识别个人身份的教务或财务信息。
- 涉及凭据、会话隔离或隐私泄露的问题，请私下联系维护者。如需通过 Issue 建立联系，只留下联系请求，省略漏洞细节与原始数据。

## 本地运行

使用 macOS、当前稳定版 Xcode、iPhone 模拟器运行时、Python 3 和 Node.js。Xcode 版本可参考最近一次成功构建的 **Select Xcode** 日志。应用和实时活动扩展的最低系统版本为 iOS 17。详见 [构建工作流](.github/workflows/build-unsigned.yml)。

1. Fork 仓库，从 `main` 创建主题分支。
2. 打开 `NEU-Lumen.xcodeproj`，选择共享方案 `NEU-Lumen` 和一个 iPhone 模拟器，在 Xcode 中运行。
3. 需要设备构建时，在仓库根目录运行 `bash build_ios_unsigned.sh`。输出为 `build/NEU-Lumen-iOS-unsigned.ipa`，安装到真机需要签名。

## 运行检查

可在仓库根目录先运行 Python 检查和工作流使用的部分 Node.js 检查。

```bash
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 Tests/Performance/check.py
node Tests/AcademicBridge/check.mjs
node Tests/Learning/check.mjs
node Tests/Learning/cg-login.mjs
node Tests/OffCampusLogin/document.mjs
```

原生 Swift 回归由工作流中的 `swiftc` 命令运行。修改对应代码时，可在 macOS 上运行相关步骤。面向 `main` 的 PR 由 Actions 检查原生测试、设备和模拟器编译以及关键页面。设备和模拟器编译需要零警告。详见 [构建工作流](.github/workflows/build-unsigned.yml)。

真机验证个人小组件时，在 Xcode 中为应用和 WidgetKit 扩展选择同一个开发团队，并让两个签名配置都授权同一个已注册的 App Group。用自有标识签名时，将项目构建设置 `NEU_LUMEN_WIDGET_GROUP` 改为你注册的组，应用和扩展会读取同一个值。Unsigned Nightly 的最终共享权限由安装签名决定。参见 [Apple App Groups 文档](https://developer.apple.com/documentation/xcode/configuring-app-groups)。

## 提交 Pull Request

- 将 PR 发往 `main`，说明改动原因、关联 Issue、验证命令和实际结果。界面变更附脱敏截图，注明真机或模拟器、iOS 版本和数据来源。
- 使用较新系统的 API 时，为 iOS 17 保留可用的路径。涉及系统权限、校园登录、会话、通知或实时活动时，说明测试覆盖的设备、网络和账号场景。
- 新增素材、数据或移植代码时，注明来源、许可和必要的署名。在 [素材来源](docs/asset-sources.md) 中记录素材及数据来源，保留第三方许可文件。
- 提交你有权贡献的内容。原创贡献按仓库的 [MIT 许可](LICENSE) 提供，第三方内容遵循其各自的许可和权利声明。
