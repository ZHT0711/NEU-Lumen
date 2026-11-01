# NEU-Lumen

[![Build unsigned iOS IPA](https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml/badge.svg)](https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml)

NEU-Lumen 是东北大学「一号通门户」（https://personal.neu.edu.cn/portal）的**原生 SwiftUI** iOS 客户端，
是 [NEUPortal](https://github.com/ZHT0711)（Flutter 多端版）的 iOS 原生重写版本。

零第三方依赖，全部使用 SwiftUI 与 Apple 系统框架实现；编译与 iOS 模拟器检查交给 GitHub Actions 云端完成，
本机不需要 Mac / Xcode。

## 当前功能

- 统一身份认证 CAS 登录（RSA-PKCS1v15 加密 + 票据重定向，系统 Security 框架实现）
- 「保持登录」：凭据经钥匙串加密保存，重启自动静默续登；会话过期自动重登并重试
- 首页仪表盘：东大蓝建筑矢量线稿背景、校徽与「知行合一」题字、个性化问候 / 日期 / 教学周、下一节课与课表直达、校园卡、常用应用、今日课程、校园数据、办事动态与资讯
- 课表：教学周网格（第1-2节…第9-10节真实作息）、周次切换、假期/考试周提示、本机自定义日程上格；连堂课程按日期合并为一个跨节次块，冲突课程分列
- 服务大厅：按门户分类展示筛选入口与数量，分类按应用数排序；支持分类与关键词联合筛选、重置、空结果跨分类查找，应用网格适配屏幕宽度与系统字号
- 成绩：教务系统真实数据（CASTGC → jwapp 会话），全部学期、GPA / 加权平均分 / 学分统计、五级制换算；原生接口失败时可打开教务网页完成认证并同步回应用，部分学期失败保留成功结果
- 校园卡：一卡通余额 / 按自然月流水（图表 + 明细，单月最多 10 页）/ 网费（余额 + 流量）/ 电费（房间码本机保存），校外自动经 WebVPN
- 校园浏览器：液态玻璃悬浮胶囊工具栏、当前页面标题和地址、前进 / 后退 / 刷新 / 停止、回入口、查找、缩放、桌面版切换、分享 / 复制当前链接、Safari、PDF 导出、附件下载与系统分享、网页弹窗和失败重试；使用当前账号的临时 WebKit 会话
- 服务大厅智慧搜索：门户热搜词 + 本地即时过滤 + 一键跳转智搜平台全校搜索（SSO 免登录）
- 液态玻璃：iOS 26+ 使用系统 `glassEffect`，低版本回退系统材质；东大蓝主题与校徽 / 「知行合一」题字标识

## 目录结构

```text
NEU-Lumen/
├── App/          应用入口、根路由与标签栏
├── Components/   可复用的纯 SwiftUI 组件（玻璃卡片、远程图片、状态视图）
├── Core/
│   ├── Models/       门户 / 课表 / 成绩数据模型
│   ├── Networking/   HTTP、Cookie 罐、CAS RSA 加密、WebVPN 网关编码与门户 API
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
（Actions 页 → 对应 run → Artifacts 下载）；同时运行分类、课表、成绩解析、Cookie 与网页同步回归检查，并生成首页深浅色、课表、服务、成绩和浏览器截图。截图使用临时模拟器夹具，发布 IPA 不包含测试数据入口；打 `v*` 标签会自动创建 GitHub Release 并附 IPA。

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

## 校外访问（WebVPN）

启动请求前探测校园网（ecard:80 / jwxt:443 任一可达，结果缓存 10 分钟）：

- 校园网内直连全部系统；
- 校外对 `ecard` / `jwxt` 等校园网专属主机自动改写为 Wengine 网关地址
  （AES-128-CFB128、IV=密钥，密钥来自学校 WebVPN 前端，写在 `Core/Networking/WebVPN.swift`），
  票据用公网一号通的 CASTGC 经 `webvpn.neu.edu.cn/login?cas_login=true` 换取；
- `portal` / `pass` / `pay` / `personal` 属公网可达主机，校外仍直连。

## 性能设计

- 单个 `URLSession` 复用连接，重定向手动逐跳跟随、吸收每一跳 Set-Cookie（对齐 CAS 跨域流程）
- 首页五个业务接口 `async let` 并行拉取，单接口失败不阻塞其它区块，失败自动回退离线演示数据并明确标注
- 周课表按教学周缓存，同一周切换不重复请求教务；成绩整表缓存，仅手动/下拉刷新
- 正则与 `DateFormatter` 静态编译/创建一次；列表全部 Lazy 容器；课程块颜色由 FNV-1a 稳定哈希生成
- JSON 解析单次 `JSONSerialization` 完成；图片走 `AsyncImage` + 系统 URLCache

## 已知限制

- 统一认证的二次短信验证未实现：如触发设备二次认证，请先在网页端完成设备信任绑定再登录
  （与 NEUPortal 行为一致）
- 统一认证的二次短信验证未实现：如触发设备二次认证，请先在网页端完成设备信任绑定再登录
  （与 NEUPortal 行为一致）
- WebVPN 网关密钥来自学校前端，学校更换后需同步更新 `WebVPN.key`
- 电费接口 23:00–6:00 常不可达，失败时请白天再试

## 隐私与安全

- 密码默认只参与本次认证；勾选「保持登录」后经系统钥匙串加密保存在本机，
  仅用于静默续登，**不上传、不打日志**，退出登录即清除
- 「记住账号」仅保存学号
- 本项目为个人工具，与东北大学官方无关；Bundle ID `edu.neu.lumen` 为非正式标识，
  请勿冒充学校应用；请遵守学校相关使用规定
