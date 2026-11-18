# NEU-Lumen

<p align="center">
  <img src="NEU-Lumen/Assets.xcassets/NEULogo.imageset/logo.png" width="220" alt="NEU-Lumen" />
</p>

<p align="center">东北大学一号通 · iOS 17+</p>

<p align="center">
  <a href="https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml"><img src="https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml/badge.svg" alt="Build" /></a>
  <a href="https://github.com/ZHT0711/NEU-Lumen/releases/tag/nightly"><img src="https://img.shields.io/badge/nightly-unsigned%20IPA-1769aa" alt="Nightly IPA" /></a>
  <img src="https://img.shields.io/badge/iOS-17%2B-111111" alt="iOS 17+" />
  <img src="https://img.shields.io/badge/SwiftUI-native-0d7c66" alt="SwiftUI" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License" /></a>
</p>

<p align="center">
  <a href="https://github.com/ZHT0711/NEU-Lumen/releases/tag/nightly">下载 Nightly</a> ·
  <a href="https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml">构建记录</a>
</p>

## 运行截图

最近一次通过快速检查的 Nightly：App 实际运行于 iPhone 模拟器，使用演示数据；首页智能摘要使用明确标注的合成输出，不代表实际模型推理。每次出包同步更新以下 10 张关键页面截图，非实体真机截图。

<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/home-light.png" width="245" alt="首页" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/card-light.png" width="245" alt="校园卡余额、月流水与独立充值入口" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/schedule-light.png" width="245" alt="课表" />
</p>
<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/services-light.png" width="245" alt="校园服务" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/academic-center-light.png" width="245" alt="学业查询与单一标题（合成演示）" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/native-analysis-light.png" width="245" alt="成绩分析与无背景标题（合成演示）" />
</p>
<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/services-art-light.png" width="245" alt="点击指示条打开服务切换面板（浅色）" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/services-art-dark.png" width="245" alt="服务切换面板与各服务校园线稿（深色）" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/native-map-light.png" width="245" alt="校园地图与预置楼门" />
</p>
<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/campus-journey-light.png" width="245" alt="跨楼路线与预置入口（尚未现场实测）" />
</p>

[全部截图](https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/NEU-Lumen-ui-preview.zip) · [对应提交与截图来源](https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/ui-preview.json)

网页工具 → **下载管理**：下载原始 PDF 和网页附件，查看进度、预览、分享或存储到“文件”。“导出网页为 PDF”与原文件下载分开；下载按账号保存在本机，系统挂起后不保证继续。

## 原生服务与实时活动

首页铃铛 → **提醒与通知**：课程、考试、日程、作业截止、账户阈值和校园动态提醒，可配置后台自动刷新。系统决定后台运行时机；时间已知的提醒提前交给系统安排，离线仍可触发。详见 [提醒与后台刷新](docs/reminders.md)。

服务大厅 → **原生服务**：按学习与生活、校园资源分组，卡面保留校园主题简笔画。提供资讯频道搜索、每日校园日程和附件下载中心。点按标题或蓝色指示条可打开服务切换面板，卡片使用各自校园线稿并标出当前服务；支持深浅色、大字体与长按拖动切换。

个人培养方案详情支持多级思维导图与大纲、课组要求和课程查询；缴费支持项目与订单入口、月份流水检索和明细，办事支持目录、指南、进度和表单核对，邮箱支持组合搜索、批量操作、前后封阅读与普通附件下载。能力边界见 [原生服务说明](docs/native-services.md) 与 [教务说明](docs/academic-queries.md)。

电费入口直达学校电费专页。教务增加按当前账号权限读取的完整功能目录和原生考试安排，业务页支持原生查询条件、表格、表单及操作核对。自定义灵动岛支持 SF Symbols 主图标、行内符号和更简洁的内容布局。

校园地图内置 Pathly 原生楼内导航：19 栋楼与 57 个预置入口，原生选楼、选层和选教室，支持路线偏好、楼层图缩放以及楼门/电梯参考图。入口按 Pathly 楼门图与公开地图配准，并按当前地图坐标系转换，修复国内底图的整体偏移；尚未现场实测，可在跨楼路线中微调。WebVPN 提供学校资源分类、搜索、本机收藏和最近访问。

网页登录可开启“本机自动登录”：认证并核对账号后将密码保存到钥匙串，会话过期时尝试续登；验证码和二次认证仍在学校页面完成。账号设置支持清除保存的密码。

实时活动展开区支持课程、校园卡、网费、电量、作业、个人日程、今日概览、学业概览和自定义内容；窄屏或大字体按可用空间精简详情，点击可查看完整页面。展开布局为系统顶部区域和传感器预留空间。

小组件提供「下一节课」「今日课表」「待交作业」和「校园入口」，包含主屏幕与锁屏布局。在「我的 → 小组件」开启个人摘要共享后，使用有 App Group 权限的签名可显示课表和作业。校园入口可直接打开地图、图书馆、校园卡和缴费大厅。

「快捷指令」中的 NEU-Lumen 操作可打开 12 项原生服务，以及课表、作业、校园卡和考试安排。在解锁设备后，还可以查询当前校园账号已同步的下一节课、今日课表、待交作业和近期考试。Siri 中的调用取决于系统、设备、语言和地区支持。

「我的 → WebDAV 备份」可手动备份和恢复首页与课表设置、服务收藏及本机自建日程。使用自备的 HTTPS WebDAV 文件夹，连接凭据保存在本机钥匙串。

## 安装

下载 [未签名 IPA](https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/NEU-Lumen-iOS-unsigned.ipa)，使用 Sideloadly、AltStore 或开发者证书签名后安装。

定时计划：北京时间每天 **03:17** 一次，Actions 可能延迟或跳过；`main` 更新及手动触发也会构建。Nightly 使用原生测试、设备/模拟器零警告编译和关键页面快速检查；正式版另跑完整交互回归与全量截图。检查通过才更新对应安装包、截图 ZIP 和来源清单。

本地构建：macOS + Xcode，运行 `bash build_ios_unsigned.sh`。

## 贡献与许可

欢迎报告问题或提交改进。参见 [贡献指南](CONTRIBUTING.md)。

原创代码与配套文档采用 [MIT 许可](LICENSE)，第三方代码、数据和学校标识遵循各自的许可及权利声明。参见 [素材来源](docs/asset-sources.md) 和 [随应用分发的第三方许可](NEU-Lumen/Resources)。

---

第三方校园工具，非学校官方应用。会话保存在本机，学校名称及图像仅用于界面展示。素材来源见 [说明](docs/asset-sources.md)。
