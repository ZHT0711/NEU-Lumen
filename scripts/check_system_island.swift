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
request.regionOfInterest = CGRect(x: 0, y: 0.65, width: 1, height: 0.35)
try VNImageRequestHandler(url: url).perform([request])
let rows = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
let text = rows.joined(separator: " ")
let letters = text.uppercased().filter(\.isLetter)
guard letters.contains("NEUTEST") else { fatalError("System expanded title missing; OCR: " + text) }
let expected = kind == "nextCourse" ? "距上课" : kind == "custom" ? "距截止" : "剩余电量"
guard text.replacingOccurrences(of: " ", with: "").contains(expected) else {
    fatalError("System expanded metric missing or clipped: " + expected + "; OCR: " + text)
}
print("PASS: actual system expanded \(kind); title and metric visible above Settings; simulator synthetic data")
