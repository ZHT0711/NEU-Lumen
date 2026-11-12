import Foundation
import Observation
import WebKit

/// Process-lifetime owner of WKDownload delegates, website stores and private files.
/// All session changes and delegate callbacks are serialized on the main actor.
@MainActor
@Observable
final class BrowserDownloadStore: NSObject, WKDownloadDelegate {
    static let shared = BrowserDownloadStore()
    private(set) var records: [BrowserDownloadRecord] = []
    private(set) var scope = UUID()
    private(set) var accountKey: String?
    private(set) var storageError: String?
    var activeCount: Int { records.filter { $0.state == .downloading }.count }

    @ObservationIgnored private let files: BrowserDownloadFiles
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var sessionEpoch: UUID?
    @ObservationIgnored private var jobs: [ObjectIdentifier: Job] = [:]
    @ObservationIgnored private var pending: Set<UUID> = []
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    private struct Job {
        let download: WKDownload
        // Preserve nonPersistent cookies and blob lifetime after the browser closes.
        let webView: WKWebView
        let id: UUID
        let scope: UUID
        let account: String
        var requiresPDF: Bool
    }

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrowserDownloads", isDirectory: true)
        files = BrowserDownloadFiles(root: base)
        super.init()
    }

    /// Root integration: call synchronously whenever authenticated identity/phase changes.
    /// nil logs out; switching accounts cancels old transfers but preserves completed files.
    func activate(account: String?, epoch: UUID? = nil) {
        let identity = account?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = identity.flatMap { $0.isEmpty ? nil : BrowserDownloadFiles.accountKey($0) }
        // Omitted epoch is neutral for the same account (anonymous fixtures/browser callers).
        // A supplied new epoch also invalidates same-account re-login and coalesced A-B-A changes.
        let nextEpoch = next == accountKey ? (epoch ?? sessionEpoch) : epoch
        guard next != accountKey || nextEpoch != sessionEpoch else { return }
        sessionEpoch = nextEpoch
        scope = UUID() // invalidate FIRST, including startDownload completion handlers
        pending.removeAll()
        progressTask?.cancel()
        progressTask = nil
        let oldJobs = Array(jobs.values)
        jobs.removeAll()
        if let old = accountKey {
            for index in records.indices where records[index].state == .downloading {
                records[index].state = .interrupted
                records[index].finishedAt = Date()
            }
            try? files.save(records, account: old)
        }
        for job in oldJobs { stop(job) }
        records = []
        accountKey = next
        ready = false
        storageError = nil
        guard let next else { return }
        do {
            var manifest = try files.load(account: next)
            let abandoned = manifest.interruptUnfinished()
            for id in abandoned { try files.remove(id, account: next) }
            records = manifest.records
            for index in records.indices where records[index].state == .completed {
                let record = records[index]
                if (try? files.finish(record, account: next, requirePDF: false)) == nil {
                    records[index].state = .failed
                    records[index].failure = .missingFile
                }
            }
            try files.save(records, account: next)
            ready = true
        } catch {
            storageError = "无法读取下载记录，已停止新下载以保护已有文件。请检查存储空间后重新登录。"
        }
    }

    func accepts(_ token: UUID) -> Bool { ready && accountKey != nil && scope == token }

    /// Called for WebKit attachment/download-attribute conversions; never replays a request.
    func adopt(_ download: WKDownload, from webView: WKWebView, scope token: UUID, requirePDF: Bool = false) {
        guard accepts(token), let accountKey else { download.cancel(nil); return }
        let record = BrowserDownloadRecord()
        records.insert(record, at: 0)
        guard persist() else { registrationFailed(record.id); download.cancel(nil); return }
        attach(download, webView: webView, id: record.id, token: token, account: accountKey, requirePDF: requirePDF)
    }

    /// The caller supplies the original WebKit request only after checking that it is a safe GET.
    /// No URLSession, copied cookie headers, unwrapped gateway URLs or persisted URLs.
    func start(_ request: URLRequest, in webView: WKWebView, scope token: UUID, requirePDF: Bool) {
        guard accepts(token), let accountKey,
              (request.httpMethod ?? "GET").uppercased() == "GET" else { return }
        let record = BrowserDownloadRecord(filename: requirePDF ? "原始文档.pdf" : "下载文件")
        records.insert(record, at: 0)
        guard persist() else { registrationFailed(record.id); return }
        pending.insert(record.id)
        webView.startDownload(using: request) { [weak self, webView] download in
            guard let self, self.accepts(token), self.pending.remove(record.id) != nil,
                  self.records.contains(where: { $0.id == record.id && $0.state == .downloading }) else {
                download.cancel(nil)
                return
            }
            self.attach(download, webView: webView, id: record.id, token: token,
                        account: accountKey, requirePDF: requirePDF)
        }
    }

    func cancel(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id && $0.state == .downloading }) else { return }
        pending.remove(id)
        let entry = jobs.first { $0.value.id == id }
        if let entry { jobs.removeValue(forKey: entry.key); stop(entry.value) }
        records[index].state = .cancelled
        records[index].finishedAt = Date()
        _ = persist()
        stopProgressIfIdle()
    }

    /// UI must confirm before calling this. Deletion is restricted to this account/UUID.
    func delete(_ id: UUID) {
        guard let key = accountKey, records.contains(where: { $0.id == id }) else { return }
        cancel(id)
        do {
            try files.remove(id, account: key)
            let remaining = records.filter { $0.id != id }
            try files.save(remaining, account: key)
            records = remaining
        } catch { storageError = "无法删除文件，请稍后重试。" }
    }

    func previewURL(for id: UUID) -> URL? {
        guard let key = accountKey,
              let record = records.first(where: { $0.id == id && $0.state == .completed }),
              (try? files.finish(record, account: key, requirePDF: false)) != nil else { return nil }
        return try? files.fileURL(record, account: key)
    }

    /// Generated webpage PDFs are labelled separately from unmodified response downloads.
    @discardableResult
    func saveWebpagePDF(_ data: Data, title: String, scope token: UUID) -> Bool {
        guard accepts(token), let key = accountKey else { return false }
        var record = BrowserDownloadRecord(filename: BrowserDownloadNames.sanitize(title, pdf: true), kind: .webpagePDF)
        record.mimeType = "application/pdf"
        do {
            let destination = try files.prepare(record, account: key)
            #if os(iOS)
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: destination, options: .atomic)
            #endif
            record.receivedBytes = try files.finish(record, account: key, requirePDF: true)
            record.totalBytes = record.receivedBytes > 0 ? record.receivedBytes : nil
            record.state = .completed
            record.finishedAt = Date()
            records.insert(record, at: 0)
            guard persist() else {
                registrationFailed(record.id)
                try? files.remove(record.id, account: key)
                return false
            }
            return true
        } catch {
            try? files.remove(record.id, account: key)
            storageError = "网页 PDF 保存失败，请检查可用空间后重试。"
            return false
        }
    }

    private func attach(_ download: WKDownload, webView: WKWebView, id: UUID, token: UUID,
                        account: String, requirePDF: Bool) {
        jobs[ObjectIdentifier(download)] = Job(download: download, webView: webView, id: id,
                                               scope: token, account: account, requiresPDF: requirePDF)
        download.delegate = self
        startProgress()
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let identifier = ObjectIdentifier(download)
        guard var job = jobs[identifier], accepts(job.scope),
              let index = records.firstIndex(where: { $0.id == job.id && $0.state == .downloading }) else {
            completionHandler(nil)
            return
        }
        let mime = BrowserDownloadNames.mime(response.mimeType)
        let suggested = BrowserDownloadNames.sanitize(suggestedFilename)
        job.requiresPDF = job.requiresPDF || BrowserDownloadNames.isPDF(mime) || suggested.lowercased().hasSuffix(".pdf")
        jobs[identifier] = job
        let http = response as? HTTPURLResponse
        if let http, !(200...299).contains(http.statusCode) {
            completionHandler(nil)
            fail(download, reason: .response)
            return
        }
        if job.requiresPDF && BrowserDownloadNames.isHTML(mime) {
            completionHandler(nil)
            fail(download, reason: .notPDF)
            return
        }
        records[index].filename = BrowserDownloadNames.sanitize(suggestedFilename, pdf: job.requiresPDF)
        records[index].mimeType = mime
        records[index].totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        do {
            let destination = try files.prepare(records[index], account: job.account)
            guard persist() else { throw CocoaError(.fileWriteUnknown) }
            completionHandler(destination)
        } catch {
            completionHandler(nil)
            fail(download, reason: .storage)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let job = jobs[ObjectIdentifier(download)], accepts(job.scope),
              let index = records.firstIndex(where: { $0.id == job.id && $0.state == .downloading }) else { return }
        do {
            let size = try files.finish(records[index], account: job.account, requirePDF: job.requiresPDF)
            records[index].receivedBytes = size
            records[index].totalBytes = size > 0 ? size : nil
            records[index].state = .completed
            records[index].finishedAt = Date()
            guard persist() else { fail(download, reason: .storage); return }
            jobs.removeValue(forKey: ObjectIdentifier(download))
            download.delegate = nil
            stopProgressIfIdle()
        } catch BrowserDownloadValidationError.notPDF { fail(download, reason: .notPDF) }
        catch { fail(download, reason: .storage) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        // Error descriptions and resumeData can contain signed URLs or credentials: never store them.
        fail(download, reason: .network)
    }

    private func fail(_ download: WKDownload, reason: BrowserDownloadRecord.Failure) {
        guard let job = jobs.removeValue(forKey: ObjectIdentifier(download)), job.scope == scope else { return }
        download.delegate = nil
        if let index = records.firstIndex(where: { $0.id == job.id }) {
            records[index].state = .failed
            records[index].failure = reason
            records[index].finishedAt = Date()
        }
        try? files.remove(job.id, account: job.account)
        _ = persist()
        stopProgressIfIdle()
    }

    private func stop(_ job: Job) {
        job.download.delegate = nil
        let disk = files
        // Retain only the website environment until cancellation settles, not the store/download.
        job.download.cancel { [webView = job.webView, id = job.id, key = job.account] _ in
            _ = webView
            try? disk.remove(id, account: key)
        }
    }

    private func registrationFailed(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].state = .failed
        records[index].failure = .storage
        records[index].finishedAt = Date()
    }

    @discardableResult
    private func persist() -> Bool {
        guard let accountKey else { return false }
        do { try files.save(records, account: accountKey); return true }
        catch {
            storageError = "下载记录保存失败，请检查可用空间。未保存的记录可能在重启后丢失。"
            return false
        }
    }

    private func startProgress() {
        guard progressTask == nil else { return }
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                if self == nil { return }
                self?.sampleProgress()
            }
        }
    }

    private func sampleProgress() {
        for job in jobs.values where job.scope == scope {
            guard let index = records.firstIndex(where: { $0.id == job.id && $0.state == .downloading }) else { continue }
            let progress = job.download.progress // WKDownload conforms to Foundation.ProgressReporting.
            records[index].receivedBytes = max(0, progress.completedUnitCount)
            if progress.totalUnitCount > 0 { records[index].totalBytes = progress.totalUnitCount }
        }
        // Do not rewrite metadata on every tick. Transitions are atomic; after a crash status is interrupted.
    }

    private func stopProgressIfIdle() {
        guard jobs.isEmpty else { return }
        progressTask?.cancel()
        progressTask = nil
    }
}
