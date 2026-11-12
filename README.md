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

最近一次通过检查的 Nightly：App 实际运行于 iPhone 模拟器，使用演示数据；非实体真机截图。

<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/home-light.png" width="245" alt="首页" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/home-dark.png" width="245" alt="深色首页" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/schedule-light.png" width="245" alt="课表" />
</p>
<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/services-light.png" width="245" alt="校园服务" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/grades-light.png" width="245" alt="成绩" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/card-light.png" width="245" alt="校园卡" />
</p>
<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/mooc-light.png" width="245" alt="慕课作业" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/chaoxing-light.png" width="245" alt="学习通" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/profile-light.png" width="245" alt="我的" />
</p>

[全部截图](https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/NEU-Lumen-ui-preview.zip) · [对应提交与截图来源](https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/ui-preview.json)

<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/live-activity-light.png" width="245" alt="实时活动配置" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/live-activity-custom-light.png" width="245" alt="自定义模板与内容预览" />
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/profile-dark.png" width="245" alt="深色个人页与学院徽章" />
</p>

<p align="center">
  <img src="https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/downloads-light.png" width="245" alt="浏览器下载管理" />
</p>

网页工具 → **下载管理**：下载原始 PDF 和网页附件，查看进度、预览、分享或存储到“文件”。“导出网页为 PDF”与原文件下载分开；下载按账号保存在本机，系统挂起后不保证继续。

## 安装

下载 [未签名 IPA](https://github.com/ZHT0711/NEU-Lumen/releases/download/nightly/NEU-Lumen-iOS-unsigned.ipa)，使用 Sideloadly、AltStore 或开发者证书签名后安装。

定时计划：北京时间每天 **03:17** 一次，Actions 可能延迟或跳过；`main` 更新及手动触发也会构建。只有全部检查通过才更新 Nightly 和截图。

本地构建：macOS + Xcode，运行 `bash build_ios_unsigned.sh`。

---

第三方校园工具，非学校官方应用。会话保存在本机，学校名称及图像仅用于界面展示。素材来源见 [说明](docs/asset-sources.md)。
