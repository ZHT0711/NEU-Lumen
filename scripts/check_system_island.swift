import Foundation
import CoreGraphics
import ImageIO
import Vision

// The fixture app itself only displays ProgressView. NEU TEST can be visible here
// only if SpringBoard actually expanded the WidgetKit presentation above Settings.
guard CommandLine.arguments.count == 3 else { fatalError("Expected screenshot and source kind") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let kind = CommandLine.arguments[2]
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.usesLanguageCorrection = false
if !kind.hasPrefix("screen:") {
    request.regionOfInterest = CGRect(x: 0, y: 0.65, width: 1, height: 0.35)
}
try VNImageRequestHandler(url: url).perform([request])
let rows = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
let text = rows.joined(separator: " ")
let normalized = text.replacingOccurrences(of: " ", with: "")
if kind.hasPrefix("screen:") {
    let screen = String(kind.dropFirst("screen:".count))
    let expected: [String: [String]] = [
        "services": ["服务大厅", "学习与生活", "成绩分析", "校园地图"],
        "services-art": ["原生服务", "校园资讯", "下载中心"],
        "grades": ["学习", "成绩"],
        "mooc": ["学习", "作业"],
        "chaoxing": ["学习", "作业"],
        "services-directory": ["服务大厅", "应用目录", "服务分类"],
        "native-electricity": ["缴费大厅", "宿舍电费", "查询并记住房间"],
        "native-bills": ["缴费大厅", "校园卡月流水", "刷新所选月份"],
        "native-analysis": ["成绩分析", "成绩概览", "分数分布"],
        "native-map": ["校园地图", "楼内导航", "教学楼"],
        "campus-journey": ["跨楼路线", "起点建筑", "终点建筑"],
        "indoor-navigation": ["楼内导航", "校区与教学楼", "起点与终点", "A102"],
        "indoor-points": ["一号楼", "起点", "楼门平面图", "本层电梯位置"],
        "indoor-route": ["楼内导航", "导航路线", "合成楼层图"],
        "native-library": ["图书馆", "馆藏书刊检索", "我的借阅与续借"],
        "native-telephone": ["查询条件", "合成部门", "合成办公室", "00000000"],
        "card": ["校园卡", "校园卡余额", "校园卡充值", "月流水"],
        "native-payment": ["缴费大厅", "校园卡余额", "充值网费"],
        "native-vpn": ["WebVPN", "访问状态", "资源目录"],
        "native-affairs": ["办事大厅", "我的在办事项"],
        "native-mail": ["学校邮箱", "收件箱"],
        "native-news": ["校园资讯", "资讯频道"],
        "native-agenda": ["校园日程", "查看日期"],
        "native-downloads": ["下载中心", "已完成"],
        "notifications": ["提醒与通知", "后台自动刷新"],
        "academic-services": ["全部教务功能", "合成学籍信息查询", "合成考试报名"],
        "academic-exams": ["考试安排", "合成考试"],
    ]
    guard let terms = expected[screen], terms.allSatisfy({ normalized.contains($0) }) else {
        fatalError("Screenshot content missing for " + screen + "; OCR: " + text)
    }
    if screen == "native-mail" {
        // Measured Vision text bounds from THIS simulator image, not source arithmetic.
        // In the old layout, the batch label occupied the navigation title's row.
        let boxes = (request.results ?? []).compactMap { observation -> (text: String, rect: CGRect)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string.replacingOccurrences(of: " ", with: ""), observation.boundingBox)
        }
        guard let title = boxes.first(where: { $0.text.contains("学校邮箱") })?.rect,
              let switcher = boxes.first(where: { $0.text.contains("左右滑动或长按切换服务") })?.rect,
              let batch = boxes.first(where: { $0.text.contains("批量操作") })?.rect,
              switcher.maxY + 0.005 < title.minY,
              batch.maxY + 0.005 < switcher.minY else {
            fatalError("Mail navigation, switcher and batch rows overlap or are missing; OCR: " + text)
        }
        print("PASS: actual mailbox title, switcher and batch text bounds are vertically separated")
    }
    print("PASS: rendered screenshot content " + screen)
} else {
let letters = text.uppercased().filter(\.isLetter)
guard letters.contains("NEUTEST") else { fatalError("System expanded title missing; OCR: " + text) }
let expected = kind == "nextCourse" ? "距上课" : kind == "custom" ? "距截止" : "剩余电量"
guard text.replacingOccurrences(of: " ", with: "").contains(expected) else {
    fatalError("System expanded metric missing or clipped: " + expected + "; OCR: " + text)
}
print("PASS: actual system expanded \(kind); title and metric visible above Settings; simulator synthetic data")
}
