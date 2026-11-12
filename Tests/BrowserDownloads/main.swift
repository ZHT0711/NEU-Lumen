import Foundation

var checks = 0
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    if try !condition() { throw NSError(domain: "BrowserDownloadsTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func rejects(_ body: () throws -> Void, _ message: String) throws {
    do { try body() } catch { checks += 1; return }
    try require(false, message)
}

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("BrowserDownloadsTests-\(UUID().uuidString)")
defer { try? fm.removeItem(at: root) }
let disk = BrowserDownloadFiles(root: root)
let keyA = BrowserDownloadFiles.accountKey("fixture-A")
let keyB = BrowserDownloadFiles.accountKey("fixture-B")
try require(keyA.count == 64 && keyA != keyB, "SHA256 account isolation")
try require(!keyA.contains("fixture-A"), "No plaintext identity in account path")
try require(keyA == BrowserDownloadFiles.accountKey("fixture-A"), "Stable account identity")
try rejects({ _ = try disk.accountDirectory("../../private") }, "Reject account traversal")
try rejects({ _ = try disk.accountDirectory(String(repeating: "G", count: 64)) }, "Only lowercase hex keys")

let hostile = ["", ".", "..", "../../secret.pdf", "..\\..\\file.pdf", "a\u{0}b\n.pdf", "\u{202e}fdp.exe",
               String(repeating: "📚", count: 400) + ".pdf", String(repeating: "e\u{301}", count: 500),
               "x" + String(repeating: "\u{301}", count: 500) + ".pdf", " report.PDF ", ":hidden/file"]
for name in hostile {
    let safe = BrowserDownloadNames.sanitize(name)
    try require(!safe.isEmpty && safe.utf8.count <= 180, "UTF8 filename limit")
    try require(!safe.contains("/") && !safe.contains("\\") && !safe.hasPrefix("."), "Single non-hidden component")
    try require(!safe.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format }), "No controls or bidi formatting")
    try require(BrowserDownloadNames.sanitize(safe) == safe, "Sanitizer is idempotent")
}
try require(BrowserDownloadNames.sanitize("证书", pdf: true) == "证书.pdf", "Extensionless PDF suggested name")
try require(BrowserDownloadNames.isPDF("Application/PDF; charset=binary"), "MIME is case/parameter insensitive")
try require(BrowserDownloadNames.isHTML("application/xhtml+xml"), "Login XHTML detection")
try require(BrowserDownloadNames.mime("text/html\nCookie: x") == nil, "Reject metadata control characters")

var first = BrowserDownloadRecord(filename: "同名.pdf")
var second = BrowserDownloadRecord(filename: "同名.pdf")
first.mimeType = "application/pdf"
second.mimeType = "application/pdf"
let original = Data("%PDF-1.7\n% fixture original bytes\n%%EOF\n".utf8)
let firstURL = try disk.prepare(first, account: keyA)
let secondURL = try disk.prepare(second, account: keyA)
try require(firstURL != secondURL && firstURL.lastPathComponent == secondURL.lastPathComponent, "Same filenames never overwrite")
try require(firstURL.path.contains(keyA) && !firstURL.path.contains("fixture-A"), "Hash/UUID/name layout")
try original.write(to: firstURL)
try Data("%PDF-1.7\nSECOND\n%%EOF\n".utf8).write(to: secondURL)
try require(try disk.finish(first, account: keyA, requirePDF: true) == Int64(original.count), "PDF original byte count")
try require(try Data(contentsOf: firstURL) == original, "PDF raw bytes unchanged")
try rejects({ _ = try disk.prepare(first, account: keyA) }, "Never reuse a UUID destination")

first.state = .completed
first.receivedBytes = Int64(original.count)
first.finishedAt = Date()
try disk.save([first, second], account: keyA)
try require(try disk.load(account: keyA).records == [first, second], "Atomic manifest round trip")
try require(try disk.load(account: keyB).records.isEmpty, "Another account cannot see A history")
try disk.save([], account: keyB)
try require(try disk.load(account: keyA).records.count == 2, "B save preserves A manifest")
var restarted = try disk.load(account: keyA)
try require(restarted.interruptUnfinished() == [second.id], "Restart identifies unfinished UUID")
try require(restarted.records[0].state == .completed && restarted.records[1].state == .interrupted, "Restart preserves completed state")
try disk.remove(second.id, account: keyA)
try disk.save(restarted.records, account: keyA)
try require(fm.fileExists(atPath: firstURL.path) && !fm.fileExists(atPath: secondURL.path), "Partial cleanup preserves completed bytes")

let manifestData = try BrowserDownloadManifest(records: [first]).encoded()
let object = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
let encodedRecords = object["records"] as! [[String: Any]]
let allowed = Set(["id", "filename", "mimeType", "state", "kind", "receivedBytes", "totalBytes", "createdAt", "finishedAt", "failure"])
try require(Set(encodedRecords[0].keys).isSubset(of: allowed), "Metadata schema contains no request/cookie/token/URL fields")
var badName = first
badName.filename = "../escape.pdf"
try rejects({ _ = try BrowserDownloadManifest(records: [badName]).encoded() }, "Reject untrusted path in manifest")
var corrupt = object
var corruptRecords = encodedRecords
corruptRecords[0]["filename"] = "../escape.pdf"
corrupt["records"] = corruptRecords
try rejects({ _ = try BrowserDownloadManifest.decode(JSONSerialization.data(withJSONObject: corrupt)) }, "Reject decoded traversal")
try rejects({ _ = try BrowserDownloadManifest(records: [first, first]).encoded() }, "Reject duplicate IDs")
try rejects({ _ = try BrowserDownloadManifest.decode(Data("not-json".utf8)) }, "Reject corrupt manifest")
var version = object
version["version"] = 999
try rejects({ _ = try BrowserDownloadManifest.decode(JSONSerialization.data(withJSONObject: version)) }, "Fail closed on unknown version")
var negative = first
negative.receivedBytes = -1
try rejects({ _ = try BrowserDownloadManifest(records: [negative]).encoded() }, "Reject negative byte counts")
let html = BrowserDownloadRecord(filename: "login.pdf")
let htmlURL = try disk.prepare(html, account: keyA)
try Data("<html>Login required %PDF-not-a-document</html>".utf8).write(to: htmlURL)
try rejects({ _ = try disk.finish(html, account: keyA, requirePDF: true) }, "HTML cannot masquerade as original PDF")
let symlink = BrowserDownloadRecord(filename: "alias.pdf")
let symlinkURL = try disk.prepare(symlink, account: keyA)
try fm.createSymbolicLink(at: symlinkURL, withDestinationURL: firstURL)
try rejects({ _ = try disk.fileURL(symlink, account: keyA) }, "Reject symlink escape")
try disk.remove(first.id, account: keyA)
try require(!fm.fileExists(atPath: firstURL.path), "Delete selected UUID")
try require(fm.fileExists(atPath: htmlURL.path), "Delete does not remove another download")
print("PASS: \(checks) offline browser-download filename, manifest, account and raw-byte checks")
