# 数据层维护索引

| 模块 | 实现 |
| --- | --- |
| HTTP / Cookie / CAS / WebVPN | `Core/Networking/` |
| 账号会话与业务数据 | `SessionStore.swift`、`PortalRepository.swift` |
| 校园卡与教务 | `CardWebBridge.swift`、`CardBalanceDocument.swift`、`AcademicResponse.swift` |
| 学习平台解析 | `MOOCScripts.swift`、`CGAssignments.swift`、`ChaoxingAssignments.swift` |
| 网页认证与同步 | `Features/Web/PortalWebView.swift` |

路径均相对于 `NEU-Lumen/`，接口与字段以源码为准。

维护时保持：Cookie 域/路径/HttpOnly/UA 语义，账号隔离与旧响应失效，部分成功合并，真实零余额，提交状态与完成状态的区别。不要把演示夹具打进 IPA。移植慕课解析代码须保留 `Resources/MOOC-reminder-LICENSE.txt`。

## 检查

```sh
node Tests/AcademicBridge/check.mjs
node Tests/Learning/check.mjs
node Tests/Learning/cg-login.mjs
node Tests/OffCampusLogin/document.mjs
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Swift 原生测试、Release IPA、模拟器 UI 与 Widget 扩展检查见 [工作流](../.github/workflows/build-unsigned.yml)。编译警告阻止发布。模拟器测试不代替真实校园账号联调。

每次通过检查的 Nightly 附带同一构建的运行截图、ZIP 和 `ui-preview.json`（提交、运行编号、模拟器、演示数据声明、图片哈希）。
