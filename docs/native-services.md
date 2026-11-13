# 原生校园服务

目前提供第一阶段适配，功能仍未与五个原站完整对齐。完整验收需要按登录账号逐项核对原站菜单、子页面、查询、表单、附件及提交后的结果。下表记录当前实现范围，网页跳转项仍属于待补齐的原生功能。

服务大厅的“原生服务”卡片和页面支持左右滑动切换。原学校应用图标、收藏及链接继续打开学校原站。原生入口集中在此处，避免在个人页和成绩页重复设置。

| 服务 | 原生能力 | 继续由学校页面完成 |
| --- | --- | --- |
| 教务 | 成绩、课表入口，校历、培养计划课程分组、状态筛选、详情与按账号保存的分页读取 | 选课、考试报名等写入业务 |
| 缴费 | 校园卡和网费余额、用量、宿舍电量查询、本月校园卡流水 | 学宿费待缴项目、金额核对、充值与支付确认 |
| WebVPN | 校园可达性、会话状态、认证更新入口、学校资源搜索 | 学校 WebVPN 认证和受保护网页；不提供系统级 VPN |
| 办事 | 原站动态服务目录，按对象、类别、部门、首字母和关键词筛选，完整办事指南、流程图和材料入口，以及门户返回的在办事项 | 申请表单、审批与附件文件查看仍待原生对齐 |
| 邮箱 | Coremail 文件夹、邮件列表、主题搜索、分页、文字正文、附件名称 | 登录认证、复杂正文、附件、学校网页写信；配置了系统邮件时可用系统原生写信窗口 |

缴费页展示已接入的校园账户数据，不能据此推断学宿费是否欠缴。接口没有返回进度、未读状态或余额时显示未读取/未知，不用 0 冒充。

邮箱读取通过登录学校 Coremail 的 WKWebView，在独立脚本世界中调用学校当前网页客户端使用的同源接口：`user:getAttrs`、`mbox:listMessages`、`getAllFolders`、`searchMessages` 与 `readMessage.jsp`。协议依据学校公开部署的 `coremail/bundle/{ $,X,M,C }.157e8.js` 客户端实现核对，不猜测发送或删除接口。邮件读取前后复核邮箱身份；首次邮箱地址不匹配校园学号时要求用户确认关联。正文只显示解码后的文字，不加载外部追踪图片。

登录按校园账号和服务隔离，使用 WKWebsiteDataStore 与 Keychain；注销清除对应会话并轮换 WebKit 配置。身份切换、页面跳转、账号代次改变时丢弃旧请求。学校会话过期仍需正常认证，不能保证永久免登录。邮箱列表不另行写入磁盘缓存。

iOS 26 的 Liquid Glass 用在切换导航控件，数据内容保持清晰的系统分组背景；减少透明度与增强对比度时提供不透明样式。使用系统动态字体、VoiceOver 标签和至少 44pt 的切换目标，不自动轮播。

Nightly 图片来自同次构建的实际模拟器页面，使用仅存在于临时 Debug 副本的合成数据，不表示真实校园账号联调或实体 iPhone 验证。

设计依据：[Apple HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)、[Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)。
