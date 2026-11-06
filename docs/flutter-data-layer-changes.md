# Flutter 版数据层迁移说明

本文记录 NEU-Lumen 当前 Swift 客户端的数据层实现，以及本轮慕课任务识别调整。范围覆盖认证、网络路由、校园卡、学习作业和成绩，可作为 Flutter 版的迁移清单。

数据读取由客户端的 HTTP 客户端、WebView 会话和解析器共同完成。下文接口地址均属于学校或学习平台。文中的 Dart 方法名是迁移建议，实际请求与字段以对应 Swift 源码为准。

## 1. 模块对应

| 能力 | 当前实现 | Flutter 迁移入口建议 |
| --- | --- | --- |
| Cookie、重定向、UA | `Core/Networking/HTTPClient.swift`、`CookieJar.swift` | 统一 HTTP transport 与完整 CookieJar |
| 校内和校外路由、CAS | `PortalClient.swift`、`WebVPN.swift`、`CASRequestGate.swift` | `PortalClient` 与访问路由管理 |
| 会话保存和账号切换 | `Core/Persistence/WebSessionStore.swift`、`Core/Services/SessionStore.swift`、`PortalRepository.swift` | 安全会话存储与按账号划分的 repository |
| 校园卡余额和流水 | `PortalClient.swift`、`CardWebBridge.swift`、`CardBalanceDocument.swift`、`CardModels.swift` | `loadCardOverview`、`loadBills`、WebView 卡务桥接 |
| CG 作业 | `Core/Models/CGAssignments.swift`、`PortalWebView.swift` | `loadCGAssignments` 与 DOM 读取脚本 |
| 慕课和学习通 | `LearningWebReader.swift`、`MOOCScripts.swift`、`ChaoxingAssignments.swift`、`LearningAssignments.swift` | `loadAssignments(platform, force)` |
| 教务成绩 | `AcademicResponse.swift`、`GradeModels.swift`、`PortalClient.swift` | `loadGrades` 与网页补充同步 |
| 校区推断 | `Core/Models/Campus.swift`、`PortalRepository.swift` | 自动校区与手动覆盖偏好 |

以上文件均位于 `NEU-Lumen/` 下，网络文件位于 `Core/Networking/`，仓库与桥接服务位于 `Core/Services/`。原生网页入口位于 `Features/Web/PortalWebView.swift`。

## 2. 认证、Cookie 与请求生命周期

### 2.1 HTTP 行为

- 手动处理重定向，逐跳吸收 `Set-Cookie`。当前最多跟随 10 跳。
- Cookie 保留 domain、path、Secure、过期时间及 host-only 语义。请求按目标地址挑选 Cookie，优先发送路径更具体的 Cookie。
- 解析多个 `Set-Cookie` 时兼容 `Expires` 中的逗号。
- HTTP 客户端与 WebView 使用一致 UA。WebVPN 票据可能与 UA 绑定。
- HTTP 与 WebView 双向交换 Cookie。先准备路由，再将新取得的 Cookie 注入浏览器。
- 会话通过本机 Keychain 保存 Cookie、UA 和用户资料，启动时恢复有效 Cookie。

Flutter 端需要同时覆盖原生 HTTP 与嵌入式浏览器，包含 HttpOnly Cookie。读取 JS 的 `document.cookie` 无法取得所有会话字段。

### 2.2 校内、校外和 CAS

- `ecard.neu.edu.cn:80` 与 `jwxt.neu.edu.cn:443` 用于可达性判断，单次超时 2.5 秒，结果缓存 10 分钟。
- 网络切换或业务失败时失效路由缓存，重新准备直连或 WebVPN 路由。
- 公网 CAS 入口为 `https://pass.neu.edu.cn/tpass/login`。
- WebVPN service 为 `https://webvpn.neu.edu.cn/login?cas_login=true`。
- 校外优先沿用当前会话持有的认证域。网关内取得的 CAS 会话继续通过网关换业务票据。
- 原生校内 API 的主机列表与网页服务的路由范围分别维护。网页支持学校子域名和已列入规则的校内 IP。
- WebVPN 包装、解包和 CAS `service` 回调处理集中在 `WebVPN.swift`。迁移时对照该文件的完整 URL 编码算法与测试向量。
- CAS 换票通过请求闸门协调，业务查询可按各模块需要并行。

### 2.3 取消、重试和账号隔离

- 每轮操作保存账号 generation 和请求 UUID，响应落地前再次比较。
- 切换账号、退出登录或替换会话时更新 generation，停止旧浏览器，清理账号对应缓存。
- 真正取消请求时回到 idle 或保留已有 loaded 数据，用户可再次刷新。
- 同步失败保留上次已读数据，并显示本次失败提示。
- 余额有单独 revision。用户从网页同步的新余额优先于此前启动的后台查询结果。

## 3. 学习模块的数据契约

### 3.1 外部平台模型

| 类型 | 字段与语义 |
| --- | --- |
| `LearningPlatform` | `cg`、`mooc`、`chaoxing` |
| `LearningCourse` | `id`、`termID`、`title`、`url`、可空 `activeTermID`、`progress`、`deadline`、`progressWarning` |
| `LearningCourse.key` | `id + "." + termID` |
| `LearningCourseProgress` | 非负整数 `completed`、`total`，`fraction` 为任务点完成比例，total 为 0 时显示暂无任务点 |
| `LearningAssignment` | `id`、`courseKey`、`courseTitle`、`title`、`kind`、`url`、`deadline`、`deadlineText`、`statusText`、`completed`、`scoreText` |
| `LearningAssignmentReport` | `courses`、`assignments`、`warnings`、`refreshedCourseKeys`、`accountKey` |

`LearningAssignment.completed` 表示已经提交或已完成。`CGProblem` 使用下文的独立评判状态。

JS 到原生的作业桥接中，`deadline` 为 Unix 毫秒或 null。Swift 内存中保存 `Date`。Flutter 可使用 `DateTime.fromMillisecondsSinceEpoch`。进行跨语言导出时应显式约定 Unix 毫秒，Swift `JSONEncoder` 的默认日期编码需要另行配置。

下面是适合 Flutter 使用的规范化表示，示例 ID 和标题均为测试数据。

```json
{
  "courses": [{
    "id": "1", "termID": "2", "title": "示例课程",
    "url": "https://i.chaoxing.com/", "activeTermID": null,
    "progress": {"completed": 28, "total": 40},
    "deadline": null, "progressWarning": null
  }],
  "assignments": [{
    "id": "1.2.3", "courseKey": "1.2", "courseTitle": "示例课程",
    "title": "本周作业", "kind": "作业", "url": "https://i.chaoxing.com/",
    "deadline": null, "deadlineText": "", "statusText": "待批阅",
    "completed": true, "scoreText": ""
  }],
  "warnings": [], "refreshedCourseKeys": ["1.2"], "accountKey": "opaque-account-fingerprint"
}
```

### 3.2 部分成功与缓存合并

1. 只有 `accountKey` 相同才合并上次报告。
2. 本轮 `refreshedCourseKeys` 中的课程，用本轮全部作业替换旧作业。成功返回空列表也会清除旧作业。
3. 本轮读取失败的课程保留旧作业，并标记本次未读取。
4. 新结果按作业 ID 去重，保留课程归属。
5. 当前课程库存和作业报告保存在 repository 内存中。认证会话另行持久化。

外部账号指纹来自对应平台的会话字段并做 SHA-256。慕课使用 `NTESSTUDYSI`，学习通使用 `_uid`、`UID`。同步完成前再次检查浏览器中的账号标识，防止同步中切换外部账号后写入旧结果。

## 4. 慕课的改动

### 4.1 登录后同步全部课程中的作业

登录入口为 `https://www.icourse163.org/home.htm#/home/course`。

从 WebView CookieStore 取得 `NTESSTUDYSI`，用它作为请求的 `csrfKey`。课程发现接口为下列地址。

```text
POST https://www.icourse163.org/web/j/learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc?csrfKey=<session>
Content-Type: application/json;charset=UTF-8
Referer: https://www.icourse163.org/home.htm

{"type":30,"p":1,"psize":50,"courseType":1}
```

- `courseType=1` 为普通课程，`courseType=2` 为学校 SPOC，两类分别分页读取后合并。
- 每页 50 条，最多 20 页。达到上限时显示尚未取全提示。
- 外层 `result` 内再包含 `result` 数组及 `pagination`。当前兼容总数字段 `total`、`totleCount`、`totalCount`。
- 数组条目使用 `id`、`name`、`mode`、`schoolPanel.shortName`、`termPanel.id`。
- 课程路由 ID 为学校简称与数字课程 ID 的组合，例如 `NEU-1`。
- mode 为 0 时使用 `/learn/NEU-1?tid=2`，其他模式使用 `/spoc/learn/NEU-1?tid=2`。
- 同时兼容当前页课程链接和无 href 的 JS 课程卡片。卡片解析作为接口异常时的补充，失败会保留明确提示。

### 4.2 读取课程结构及任务

```text
POST /web/j/courseBean.getLastLearnedMocTermDto.rpc?csrfKey=<session>
Content-Type: application/json;charset=UTF-8
{"termId":2}

POST /web/j/courseBean.getMocTermDto.rpc?csrfKey=<session>
Content-Type: application/x-www-form-urlencoded;charset=UTF-8
termId=2&gatewayType=3
```

上述地址的 origin 均为 `https://www.icourse163.org`，Referer 为课程地址。

- 解析 RPC 返回的 `chapters`，也兼容新学习页 `self.__next_f.push` 中的大纲结构。
- 新学习页会补读 `/mooc/learn/<course>/assessments?tid=<term>`。
- SPOC 的路由学期与 `moocTermDto.id` 或 `termDto.id` 可能不同，按需读取实际学期。
- 主观作业已经提交的依据包括 `test.userSubmitStatus > 0`、`usedTryCount > 0` 和有效个人成绩。`userScore=0` 也属于有效成绩。
- 已保存但未提交的草稿保持待完成。互评期单独标注，提交记录在互评期继续保留。
- 同轮来自 RPC 的个人提交记录与大纲元数据合并，已有提交证据优先保留。

### 4.3 本轮修复的任务边界

- 课程、章节、课时等容器在遍历时单独处理。
- 任务通过 `contentType`、嵌套 `test.type`、显式任务类型和 `homeworks`、`quizzes`、`tests` 等任务集合识别。
- 慕课展示层只输出作业和测验，任务类型分别对应 3 和 2。
- 考试、讨论和视频课程会在慕课作业输出时过滤。
- 课程名称用于作业分组，空课程分组会隐藏。
- 作业 ID 包含课程、学期、章节、课时和任务标识，兼容不同周使用相同作业标题。

完整 JS 解析器在 `MOOCScripts.swift`。移植其中来自 MOOC_reminder 的代码时，保留仓库内 `Resources/MOOC-reminder-LICENSE.txt` 的 MIT 许可声明。

## 5. 学习通作业、课程进度和截止日期

登录入口为 `https://i.chaoxing.com/`，完成平台认证后沿用该会话访问以下接口。

| 用途 | 请求 |
| --- | --- |
| 已选班级和课程 | `GET https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1` |
| 全课程任务点 | `GET https://mooc1-api.chaoxing.com/gas/clazz?id=<clazz>&personid=<cpi>&view=json&fields=<fields>` |
| 课程页面 | `GET https://mooc1.chaoxing.com/visit/stucoursemiddle?courseid=<id>&clazzid=<clazz>&cpi=<cpi>&ismooc2=1&v=2` |
| 作业分页 | `GET https://mooc1.chaoxing.com/mooc-ans/mooc2/work/list?courseId=<id>&classId=<clazz>&cpi=<cpi>&enc=<workEnc>&pageNum=<page>` |

任务点查询的 fields 如下。

```text
id,course.fields(id,knowledge.fields(id,parentnodeid,layer,finishcount,unfinishcount,jobcount).type(video))
```

### 5.1 课程与任务点

- 已选课响应读取 `channelList[].content`。班级使用 `content.id` 和 `content.cpi`，课程使用 `content.course.data[]`。
- 课程截止日期来自 `content.endDate`。支持 Unix 秒或毫秒、ISO 时间及学校常见日期字符串。
- 仅提供年月日时按北京时间当日 23:59:59 处理。日期和进度均允许为空。
- 任务点响应沿 `data → course.data → knowledge.data` 展开，并按课程 ID 匹配。
- 统计叶子节点任务点，排除已计入子节点的父级汇总，并按节点 ID 去重。
- 已完成量读取 `finishcount` 或 `jobFinishedCount`，未完成量读取 `unfinishcount` 或 `jobUnfinishedCount`。
- 总量使用 `jobcount`，或由已完成量与未完成量相加。缺少足够字段时报告进度未读取。
- 课程卡片显示任务点百分比、已完成量和总量，并单独显示课程截止日期。
- 进度查询与作业查询分别处理失败。取得的课程进度和截止日期可在作业列表失败时继续展示。

### 5.2 作业列表

- 先从课程页面读取 `workEnc`，再读取所有作业分页。当前上限 100 页，页间等待 500 毫秒。
- 作业条目读取 `li[data]`、`.overHidden2`、`.status` 和 `.time`，分页读取 `#page li`。
- 未交、未提交和待互评保持待完成。已提交、待批阅、已批阅、已完成等状态标记已提交或完成。
- 作业截止日期与课程截止日期分别保存。剩余时长型作业截止时间以同步时刻估算，并保留平台原始文字。
- 作业详情 URL 限制为平台 HTTP 或 HTTPS 地址。

## 6. CG 作业的改动

平台入口从服务目录中的 CG 应用取得，默认地址为 `http://neucsecg.neu.edu.cn`。校外网页经过 WebVPN 时，保留网关路径前缀。

- 在已登录网页会话里运行 `CGAssignmentReport.browserScript`，逐份读取当前与历史作业。
- 侧栏链接使用 `/assignment/index.jsp?assignID=...`，收集全部作业后遍历。
- 截止日期读取页面“作业时间”区间的结束时间，使用北京时间解析。
- 兼容传统题目链接与 `openAILeftFrame` 包装的 `problemContent.jsp?problemID=...` 不透明题目 ID。
- 逐题保存题目名称、地址、提交时间、得分及各组测试数据结果。
- 页面声明的总题数保存为 `expectedProblemCount`，题目读取不全时保持统计未完成。
- 单份作业读取失败时保留该份作业的未读取状态与警告。

CG 题目状态使用四种值。

| 值 | 判定 |
| --- | --- |
| `notSubmitted` | 页面明确显示未提交 |
| `needsWork` | 已有错误、部分正确、超时等评判结果 |
| `complete` | 已读取测试全部正确，且已声明的测试数量读取完整，或页面明确给出完全正确 |
| `submitted` | 已提交但评判仍待确认，包含部分测试结果待公布 |

整份作业完成需要页面读取成功、题目存在、全部预期题目已读取且全部完全正确。Flutter 端应保留 `loaded`、`expectedProblemCount`、`statusText`、`late`、`history` 和 `warnings`。

## 7. 校园卡 403、余额及流水的改动

### 7.1 会话建立与 WebView 兜底

- 先准备校内或 WebVPN 路由，再沿 CAS service `http://ecard.neu.edu.cn/selflogin/login.aspx` 建立卡务会话。
- 读取学校签名 SSO 表单中的 `username`、`timestamp`、`auid`，提交到 `/selfsearch/SSOLogin.aspx`。
- 请求携带对应页面的 Referer 和匹配请求地址的 Origin。
- 原生 HTTP 被站点拒绝时使用 `CardWebBridge`，在 WebKit 中建立会话并读取相同业务页面。
- WebView 卡务请求复用会话与 Referer，串行协调有状态页面操作。
- 用户在可见卡务网页完成认证后可直接同步余额，桥接沿用其 WebsiteDataStore，并同步回 CookieJar。

### 7.2 主钱包余额

- 首页路径由 `PortalClient.cardHomePath` 管理，兼容 `/selfsearch/User/baseinfo.aspx`。
- 兼容 input.value、ASP.NET label 和“主钱包余额”等可见文本。
- 浏览器快照将动态 input.value 写回克隆节点，并收集同源 iframe 或 frame 文档。
- 主钱包、补助余额和卡状态分别解析。主钱包字段缺失时展示未读取提示。
- 支持真实 0 元余额以及逗号分隔金额。
- 失败时保留上次真实余额，取消时恢复可重试状态。

### 7.3 月流水及其它查询入口

- 流水页面为 `/selfsearch/User/ConsumeInfo.aspx`。
- 查询和翻页均继承最新页面的 hidden fields，包含 ASP.NET ViewState、EventValidation 等字段。
- 日期查询使用 `ctl00$ContentPlaceHolder1$txtStartDate`、`txtEndDate`，查询类型使用 `rbtnType=0`，按钮字段为 `btnSearch`。
- 翻页时 `__EVENTTARGET=ctl00$ContentPlaceHolder1$AspNetPager1`，`__EVENTARGUMENT` 为页码。
- 单月最多读取 10 页，超过时返回 `truncated=true`。历史月按账号和年月缓存，强制刷新可重新读取。
- `CardBill` 包含 `time`、`timeText`、`subject`、`amount`、`fee`、`balanceAfter`、`station`。amount 正值表示充值，负值表示消费。
- 存款、补助、圈存、取款、消费、交易汇总和捡到卡作为校园卡面板的网页查询入口，按当前页面菜单文字找到对应链接，兼容 frame 菜单。

## 8. 成绩、校区与网页权限

### 8.1 成绩

教务 origin 为 `https://jwxt.neu.edu.cn`。

- CAS 建立教务会话后读取 `api/home/student/schoolCalendars.do`。
- 对各学期读取 `api/home/student/scores.do?termCode=<code>`。
- 返回 `GradeReport.semesters` 与 `failedTerms`。部分学期失败时继续保留成功学期。
- 切到“成绩”时加载成绩，账号变化时失效旧请求和缓存。
- 网页成绩补充同步使用 `AcademicResponse.browserScript` 和 `AcademicResponse.browserReport`。Flutter 可复用相同解析字段和部分成功策略。

### 8.2 校区

`Campus.inferred` 优先读取资料中的明确校区词，再用学院和专业关键词匹配。未知返回 null。用户可在“我的”中设置手动校区覆盖。该规则和对应偏好会影响首页建筑背景。

### 8.3 网页权限

校园乐跑等网页的定位、媒体和方向传感器请求由 WebView 与系统权限流程承接。Flutter 迁移需连同原生平台权限声明及 WebView 的权限回调一起实现，分别处理用户允许和拒绝。iOS 对照 `PortalWebView.swift` 与 App 的 Info.plist 配置，回归检查见 `scripts/test_web_permissions.py`。

## 9. 回归与交付约束

| 检查 | 入口 |
| --- | --- |
| 慕课任务类型、课程误识别、主观提交、互评、元数据合并 | `node Tests/Learning/check.mjs` |
| 教务网页桥接 | `node Tests/AcademicBridge/check.mjs` |
| 登录页面与域隔离 | `node Tests/OffCampusLogin/document.mjs` |
| 权限、网络策略和发版脚本 | `python -m unittest discover -s scripts -p 'test_*.py'` |
| Swift 原生数据模型、会话、校园卡、学习通进度与日期 | `Tests/OffCampusLogin/main.swift`，编译命令见构建工作流 |
| 模拟器 DOM 和真实入口联调 | `scripts/prepare_ui_validation.py`、`scripts/validate_ui.sh` |

模拟器夹具覆盖一键读取跨页的 51 门普通课程和 1 门 SPOC，并检查提交状态。夹具使用虚构数据，位于一次性构建副本中。

GitHub Actions 保持北京时间每日 03:17 定时构建，main 更新触发自动构建并在全部检查通过后更新滚动 nightly。手动触发创建带北京时间日期和构建编号的独立 nightly 预发布。发布前检查原生测试、真机编译和模拟器编译日志，编译警告会阻止发布。

上述自动检查覆盖数据和浏览器夹具。真实账号在不同校园网络下的登录、外部平台页面变化，以及教师设置的课程截止日期，仍需在设备上核对。
