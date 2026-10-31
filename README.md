# NEU-Lumen

[![Build unsigned iOS IPA](https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml/badge.svg)](https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml)

NEU-Lumen 是东北大学「一号通门户」（https://personal.neu.edu.cn/portal）的**原生 SwiftUI** iOS 客户端，
是 [NEUPortal](https://github.com/ZHT0711)（Flutter 多端版）的 iOS 原生重写版本。

零第三方依赖，全部使用 SwiftUI 与 Apple 系统框架实现；编译完全交给 GitHub Actions 云端完成，
本机不需要 Mac / Xcode。

## 当前功能

- 统一身份认证 CAS 登录（RSA-PKCS1v15 加密 + 票据重定向，系统 Security 框架实现）
- 「保持登录」：凭据经钥匙串加密保存，重启自动静默续登；会话过期自动重登并重试
- 首页仪表盘：数据条、下一节课横幅、今日课程时间轴（进行中标记）、常用应用、办事动态、校园资讯
- 课表：教学周网格（第1-2节…第9-10节真实作息）、周次切换、假期/考试周提示、本机自定义日程上格
- 服务大厅：全部校内应用（图标/分类/访问量）+ 门户热搜词 + 本地即时过滤
- 成绩：教务系统真实数据（CASTGC → jwapp 会话），全部学期、GPA / 加权平均分 / 学分统计、五级制换算
- 打开网页：WKWebView 注入会话 Cookie，各业务系统 SSO 免登录直达，Safari 兜底
- 液态玻璃：iOS 26+ 使用系统 `glassEffect`，低版本回退系统材质；东大蓝主题

## 目录结构

```text
NEU-Lumen/
├── App/          应用入口、根路由与标签栏
├── Components/   可复用的纯 SwiftUI 组件（玻璃卡片、远程图片、状态视图）
├── Core/
│   ├── Models/       门户 / 课表 / 成绩数据模型
│   ├── Networking/   HTTP、Cookie 罐、CAS RSA 加密与门户 API
│   ├── Persistence/  钥匙串凭据与本机日程持久化
│   ├── Services/     会话状态机、业务仓储与学期模型
│   └── Support/      容错 JSON 取值与日期解析工具
└── Features/     按产品功能拆分的页面
```

视图只负责展示和局部交互；网络请求集中在 `PortalClient`，登录状态集中在 `SessionStore`，
业务数据集中在 `PortalRepository`（与 Hanairo 的分层一致）。

## 构建

### 云端构建（推荐）

GitHub Actions 会在 main 分支、Pull Request、`v*` 标签和手动触发时自动构建未签名 IPA
（Actions 页 → 对应 run → Artifacts 下载）；打 `v*` 标签会自动创建 GitHub Release 并附 IPA。

### 本地构建（需要 macOS + Xcode 16+）

```bash
bash build_ios_unsigned.sh
# 产物：build/NEU-Lumen-iOS-unsigned.ipa
```

使用 Xcode 打开 `NEU-Lumen.xcodeproj` 运行 `NEU-Lumen` Scheme 也可以（最低支持 iOS 17.0）。

## 安装未签名 IPA 到 iPhone（任选其一）

| 方式 | 签名 | 有效期 |
| --- | --- | --- |
| Sideloadly / AltStore（Windows 可用）+ 个人 Apple ID | 免费 | 7 天，到期重签 |
| 苹果开发者账号（$99/年）+ 证书 | 付费 | 1 年 |
| TrollStore（特定 iOS 版本） | 永久 | 永久 |

## 性能设计

- 单个 `URLSession` 复用连接，重定向手动逐跳跟随、吸收每一跳 Set-Cookie（对齐 CAS 跨域流程）
- 首页五个业务接口 `async let` 并行拉取，单接口失败不阻塞其它区块，失败自动回退离线演示数据并明确标注
- 周课表按教学周缓存，同一周切换不重复请求教务；成绩整表缓存，仅手动/下拉刷新
- 正则与 `DateFormatter` 静态编译/创建一次；列表全部 Lazy 容器；课程块颜色由 FNV-1a 稳定哈希生成
- JSON 解析单次 `JSONSerialization` 完成；图片走 `AsyncImage` + 系统 URLCache

## 已知限制

- 统一认证的二次短信验证未实现：如触发设备二次认证，请先在网页端完成设备信任绑定再登录
  （与 NEUPortal 行为一致）
- 校外网络下门户与教务依赖学校 WebVPN，未内置 WebVPN 换票逻辑；校园网内全功能可用
- 校园卡余额门户端返回 `***`，卡余额/流水/电费等一卡通直连接口属于后续计划

## 隐私与安全

- 密码默认只参与本次认证；勾选「保持登录」后经系统钥匙串加密保存在本机，
  仅用于静默续登，**不上传、不打日志**，退出登录即清除
- 「记住账号」仅保存学号
- 本项目为个人工具，与东北大学官方无关；Bundle ID `edu.neu.lumen` 为非正式标识，
  请勿冒充学校应用；请遵守学校相关使用规定
