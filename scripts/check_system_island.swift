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
        "services": ["原生服务", "服务大厅"],
        "services-art": ["原生服务", "校园资讯", "下载中心"],
        "grades": ["学习", "成绩"],
        "mooc": ["学习", "作业"],
        "chaoxing": ["学习", "作业"],
        "native-payment": ["缴费大厅", "校园卡余额"],
        "native-vpn": ["WebVPN", "访问状态"],
        "native-affairs": ["办事大厅", "我的在办事项"],
        "native-mail": ["学校邮箱", "收件箱"],
        "native-news": ["校园资讯", "资讯频道"],
        "native-agenda": ["校园日程", "查看日期"],
        "native-downloads": ["下载中心", "已完成"],
    ]
    guard let terms = expected[screen], terms.allSatisfy({ normalized.contains($0) }) else {
        fatalError("Screenshot content missing for " + screen + "; OCR: " + text)
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
