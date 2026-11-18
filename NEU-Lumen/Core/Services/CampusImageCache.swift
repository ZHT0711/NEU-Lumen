import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Persistent copies of public images, with a separate budget for decoded pixels.
actor CampusImageCache {
    static let serviceIcons = CampusImageCache(folder: "ServiceIcons", maxPixels: 128,
        maxDownloadBytes: 2_000_000, memoryBudget: 8_000_000, diskBudget: 24_000_000)
    static let floorMaps = CampusImageCache(folder: "FloorMaps", maxPixels: 4096,
        maxDownloadBytes: 20_000_000, memoryBudget: 48_000_000, diskBudget: 72_000_000)

    private let directory: URL?
    private let maxPixels: Int
    private let maxDownloadBytes: Int
    private let diskBudget: Int
    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var diskBytes: Int?

    init(folder: String, maxPixels: Int, maxDownloadBytes: Int, memoryBudget: Int, diskBudget: Int,
         cacheRoot: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) {
        directory = cacheRoot?.appendingPathComponent(folder, isDirectory: true)
        self.maxPixels = maxPixels
        self.maxDownloadBytes = maxDownloadBytes
        self.diskBudget = diskBudget
        memory.totalCostLimit = memoryBudget
    }

    func image(at url: URL, fetch: @escaping @Sendable (URL) async throws -> Data) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let image = memory.object(forKey: url as NSURL) { return image }
        if let pending = inFlight[url] { return await pending.value }
        // A recycled cell can leave while the shared download still populates the cache.
        let task = Task {
            defer { inFlight[url] = nil }
            return await read(url, fetch: fetch)
        }
        inFlight[url] = task
        return await task.value
    }

    private func read(_ url: URL, fetch: (URL) async throws -> Data) async -> UIImage? {
        let file = directory.map {
            $0.appendingPathComponent(SHA256.hash(data: Data(url.absoluteString.utf8))
                .map { String(format: "%02x", $0) }.joined())
        }
        if let file, let data = try? Data(contentsOf: file) {
            if let image = decode(data, for: url) { return image }
            try? FileManager.default.removeItem(at: file)
            diskBytes = nil
        }
        guard let data = try? await fetch(url), let image = decode(data, for: url) else { return nil }
        if let directory, let file {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                diskBytes = diskBytes.map { $0 + data.count }
                if diskBytes.map({ $0 > diskBudget }) ?? true { trimDisk(in: directory) }
            } catch {
                // Keep the decoded image available when the system disk cache is unavailable.
            }
        }
        return image
    }

    private func decode(_ data: Data, for url: URL) -> UIImage? {
        guard !data.isEmpty, data.count <= maxDownloadBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: bitmap)
        memory.setObject(image, forKey: url as NSURL, cost: bitmap.bytesPerRow * bitmap.height)
        return image
    }

    private func trimDisk(in directory: URL) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) else { return }
        let entries = files.compactMap { file -> (file: URL, size: Int, date: Date)? in
            guard let values = try? file.resourceValues(forKeys: keys), let size = values.fileSize else { return nil }
            return (file, size, values.contentModificationDate ?? .distantPast)
        }
        var size = entries.reduce(0) { $0 + $1.size }
        if size > diskBudget {
            // Leave room for several new files before scanning the directory again.
            for entry in entries.sorted(by: { $0.date < $1.date }) where size > diskBudget * 3 / 4 {
                if (try? FileManager.default.removeItem(at: entry.file)) != nil { size -= entry.size }
            }
        }
        diskBytes = size
    }
}
