# NEU-Lumen

<p align="center">
  <img src="NEU-Lumen/Assets.xcassets/NEULogo.imageset/logo.png" width="250" alt="NEU-Lumen" />
</p>

<p align="center">东北大学「一号通门户」的原生 SwiftUI 客户端</p>

<p align="center">
  <a href="https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml"><img src="https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml/badge.svg" alt="Build" /></a>
  <a href="https://github.com/ZHT0711/NEU-Lumen/releases/tag/nightly"><img src="https://img.shields.io/badge/nightly-unsigned%20IPA-1769aa" alt="Nightly IPA" /></a>
  <img src="https://img.shields.io/badge/iOS-17%2B-111111" alt="iOS 17+" />
  <img src="https://img.shields.io/badge/SwiftUI-native-0d7c66" alt="SwiftUI" />
</p>

NEU-Lumen 将统一认证、课表、校园卡、成绩、作业和校园服务集中在一个轻量的 iOS 应用中。项目不依赖第三方运行库，网络、会话和缓存均由 Apple 系统框架与项目内模块完成。

## 产品预览

以下图片记录早期版本的界面。当前版本使用 ActivityKit 与 WidgetKit 实现系统实时活动，最新模拟器截图随 Actions 构建产物提供。

<p align="center">
  <img src="docs/screenshots/live-activity-collapsed.jpg" width="190" alt="系统灵动岛收起状态" />
  <img src="docs/screenshots/live-activity-expanded.jpg" width="190" alt="系统灵动岛展开状态" />
  <img src="docs/screenshots/live-activity-lockscreen.jpg" width="190" alt="锁屏 Live Activity" />
</p>

每次构建也会在 Actions 产物中生成首页、课表、服务、学习和浏览器截图；打开最近一次 workflow 的 **Artifacts → NEU-Lumen-ui-preview** 即可查看完整演示集。

<p align="center">
  <img src="NEU-Lumen/Assets.xcassets/NEUEmblem.imageset/emblem.png" width="110" alt="东北大学校徽" />
  <img src="NEU-Lumen/Assets.xcassets/FutureTechnologyEmblem.imageset/emblem.png" width="110" alt="未来技术学院院徽" />
  <img src="NEU-Lumen/Assets.xcassets/AquaCore.imageset/avatar.png" width="110" alt="NEU-AquaCore 组织头像" />
</p>

- **系统实时活动**由 ActivityKit 创建，WidgetKit 扩展提供锁屏、灵动岛紧凑、最小和展开样式，支持课程倒计时、余额和自定义文字。
- **学院身份**使用已有学院图片。未来技术学院显示对应院徽，其余学院使用东北大学校徽。
- **海洋之心彩蛋**：连续点击「走进东大」标题三次，查看团队致意并进入 [NEU-AquaCore](https://github.com/NEU-AquaCore)。

## 功能

### 校园信息

- CAS 统一身份认证，支持校内直连与校外 WebVPN。
- 首页仪表盘：问候、教学周、下一节课、校园卡、常用服务和校园资讯。
- 课表网格：周次切换、连堂合并、冲突分列、自定义日程、节假日与调课。
- 成绩：学期成绩、GPA、加权平均分、学分统计和教务网页同步。
- 校园卡：余额、月度流水、网费和电费。

### 学习与作业

- NEUCSECG、慕课、学习通分别展示课程、作业、截止日期和进度。
- 平台 Cookie 按校园账号隔离并写入系统钥匙串；应用重启后自动恢复。
- NEUCSECG 入口会自动完成「校园统一登录」按钮点击，再进入平台。
- 作业数据另存为账号隔离缓存；退出登录时一并清理学习平台会话。

### Live Activity

Live Activity 的配置入口是 **我的 → 锁屏与灵动岛**。

1. 选择下一节课、校园卡余额或自定义文字。
2. 开启「启用实时活动」，应用在前台且所选数据可用时向系统创建实时活动。
3. 配置页展示实际运行状态和失败原因，也可手动开启已结束的活动。

请在系统设置中允许 NEU-Lumen 使用实时活动。课程和余额采用当前账号已加载的数据，修改配置或应用内数据变化时同步更新。进入后台后，系统继续显示已发布内容和课程倒计时。课程结束或余额同步超过 30 分钟后提示打开应用更新。自定义文字保留到活动结束，系统活动最长持续时间由 iOS 管理。

退出登录、关闭功能或切换账号时清理旧活动。手动结束后可在配置页重新开启。

## 构建与下载

### Nightly

[打开 Nightly 预发布页](https://github.com/ZHT0711/NEU-Lumen/releases/tag/nightly) 下载最近一次通过检查的未签名 IPA。推送到 `main` 会触发构建；每日北京时间约 03:17 也会自动构建。

未签名 IPA 需要使用 Sideloadly、AltStore 或开发者证书签名后安装。

### 本地构建

需要 macOS 与 Xcode 16+：

```bash
bash build_ios_unsigned.sh
# build/NEU-Lumen-iOS-unsigned.ipa
```

也可以用 Xcode 打开 `NEU-Lumen.xcodeproj`，运行 `NEU-Lumen` scheme。最低支持 iOS 17.0；Live Activity 需要系统允许实时活动，系统灵动岛需要支持该硬件的 iPhone。

## 项目结构

```text
NEU-Lumen/
├── App/          应用入口、主题、路由和标签栏
├── Components/   玻璃卡片、学院徽章等通用组件
├── Core/
│   ├── Models/       课表、门户、成绩、作业和校园卡模型
│   ├── Networking/   HTTP、CAS、WebVPN、Cookie 和网页读取
│   ├── Persistence/  钥匙串、网页登录会话和本地缓存
│   └── Services/     SessionStore、PortalRepository、Live Activity
├── Features/     首页、课表、服务、学习、我的和网页浏览器
└── NEU-LumenLiveActivity/  锁屏与系统灵动岛 Widget Extension
```

核心职责保持分离：`SessionStore` 管理账号与会话，`PortalRepository` 管理业务数据，`PortalBrowser` 负责网页认证和平台同步，`DynamicIslandActivityManager` 管理 Live Activity 生命周期。

## CI 工作流

`.github/workflows/build-unsigned.yml` 会依次执行：

- Swift / Node / Python 解析回归测试
- 原生 Release unsigned IPA 构建
- 模拟器 UI、浏览器与原生 ActivityKit 生命周期检查
- 真机及模拟器产物中 WidgetKit 扩展的可执行文件、入口、版本和深层链接校验
- 编译日志告警检查
- IPA 与 UI 截图产物上传

模拟器验证使用临时数据夹具，不会把测试账号或测试数据打进发布包。

## 隐私与安全

- 密码只用于认证；勾选保持登录后，经系统钥匙串加密保存。
- 网页 Cookie、作业缓存和账号数据按学号隔离，均保存在本机。
- 不上传密码、不记录认证日志；退出登录会清除对应会话。
- 本项目是第三方个人工具，与东北大学官方无关。

## 相关项目

- [NEU-AquaCore](https://github.com/NEU-AquaCore)
- [NEUPortal](https://github.com/ZHT0711)
- [holiday-cn](https://github.com/NateScarlet/holiday-cn)

## 许可证与免责声明

项目中的学校名称、校徽、学院徽章和组织头像仅用于校园工具界面展示。请遵守学校相关服务的使用规定，不要将本项目冒充官方应用。
