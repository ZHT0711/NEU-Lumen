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
</p>

<p align="center">
  <a href="https://github.com/ZHT0711/NEU-Lumen/releases/tag/nightly">下载 Nightly</a> ·
  <a href="https://github.com/ZHT0711/NEU-Lumen/actions/workflows/build-unsigned.yml">构建记录</a>
</p>

## 运行截图

最近一次通过快速检查的 Nightly：App 实际运行于 iPhone 模拟器，使用演示数据；非实体真机截图。每次出包同步更新以下 10 张关键页面截图。

<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/home-light.png" width="245" alt="首页" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/home-dark.png" width="245" alt="深色首页" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/schedule-light.png" width="245" alt="课表" />
</p>
<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/services-light.png" width="245" alt="校园服务" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/services-art-light.png" width="245" alt="校园主题简笔画卡面" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/native-map-light.png" width="245" alt="校园地图" />
</p>
<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/indoor-navigation-light.png" width="245" alt="原生楼内导航" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/indoor-route-light.png" width="245" alt="原生路线绘制（合成楼层图）" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/indoor-points-light.png" width="245" alt="楼层与教室选择" />
</p>
<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/native-vpn-light.png" width="245" alt="原生 WebVPN 资源目录（合成演示）" />
</p>

[全部截图](https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/NEU-Lumen-ui-preview.zip) · [对应提交与截图来源](https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/ui-preview.json)

网页工具 → **下载管理**：下载原始 PDF 和网页附件，查看进度、预览、分享或存储到“文件”。“导出网页为 PDF”与原文件下载分开；下载按账号保存在本机，系统挂起后不保证继续。

## 原生服务与实时活动

首页铃铛 → **提醒与通知**：课程、考试、日程、作业截止、账户阈值和校园动态提醒，可配置后台自动刷新。系统决定后台运行时机；时间已知的提醒提前交给系统安排，离线仍可触发。详见 [提醒与后台刷新](docs/reminders.md)。

服务大厅 → **原生服务**：按学习与生活、校园资源分组，卡面保留校园主题简笔画。提供资讯频道搜索、每日校园日程和附件下载中心。iOS 26 导航使用 Liquid Glass，兼顾减少透明度、增强对比度和动态字体。

个人培养方案详情支持多级思维导图与大纲、课组要求和课程查询；缴费支持项目与订单入口、月份流水检索和明细，办事支持目录、指南、进度和表单核对，邮箱支持组合搜索、批量操作、前后封阅读与普通附件下载。能力边界见 [原生服务说明](docs/native-services.md) 与 [教务说明](docs/academic-queries.md)。

电费入口直达学校电费专页。教务增加按当前账号权限读取的完整功能目录和原生考试安排，业务页支持原生查询条件、表格、表单及操作核对。自定义灵动岛支持 SF Symbols 主图标、行内符号和更简洁的内容布局。

校园地图内置 Pathly 原生楼内导航：19 栋教学楼，原生选楼、选层和选教室，支持路线偏好、楼层图缩放以及楼门/电梯参考图。WebVPN 提供学校资源分类、搜索、本机收藏和最近访问。

实时活动展开区支持课程、校园卡、网费、电量、作业、个人日程、今日概览、学业概览和自定义内容；窄屏或大字体按可用空间精简详情，点击可查看完整页面。展开布局为系统顶部区域和传感器预留空间。

## 安装

下载 [未签名 IPA](https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/NEU-Lumen-iOS-unsigned.ipa)，使用 Sideloadly、AltStore 或开发者证书签名后安装。

定时计划：北京时间每天 **03:17** 一次，Actions 可能延迟或跳过；`main` 更新及手动触发也会构建。Nightly 使用原生测试、设备/模拟器零警告编译和关键页面快速检查；正式版另跑完整交互回归与全量截图。检查通过才更新对应安装包、截图 ZIP 和来源清单。

本地构建：macOS + Xcode，运行 `bash build_ios_unsigned.sh`。

---

第三方校园工具，非学校官方应用。会话保存在本机，学校名称及图像仅用于界面展示。素材来源见 [说明](docs/asset-sources.md)。
