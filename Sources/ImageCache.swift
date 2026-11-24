import SwiftUI
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// 图片缓存：内存 NSCache + 磁盘 Caches/ikanmh-images，磁盘上限 500MB，超了删最旧的。
/// 只存图片，不碰其他数据；下载失败不写入缓存。
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let maxDiskBytes: Int64 = 500 * 1024 * 1024
    private var inFlight: [String: Task<Data?, Never>] = [:]

    private let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("ikanmh-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        memory.totalCostLimit = 100 * 1024 * 1024
        memory.countLimit = 300
    }

    /// 先内存，再磁盘，都没有就下载；同一 URL 同一时间只下一个。
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString
        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        if let data = loadFromDisk(url), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString, cost: data.count)
            return img
        }
        if let existing = inFlight[key] {
            guard let data = await existing.value, let img = UIImage(data: data) else { return nil }
            memory.setObject(img, forKey: key as NSString, cost: data.count)
            return img
        }
        let task = Task<Data?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
                return data
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        guard let data = await task.value else {
            inFlight[key] = nil
            return nil
        }
        inFlight[key] = nil
        guard let img = UIImage(data: data) else { return nil }
        memory.setObject(img, forKey: key as NSString, cost: data.count)
        storeToDisk(url, data: data)
        return img
    }

    /// 后台预加载一批 URL，已缓存或正在下的直接跳过。
    func prefetch(urls: [URL]) async {
        for url in urls {
            Task { _ = await self.image(for: url) }
        }
    }

    // MARK: - 磁盘

    private func fileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = hash.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    private func loadFromDisk(_ url: URL) -> Data? {
        try? Data(contentsOf: fileURL(for: url))
    }

    private func storeToDisk(_ url: URL, data: Data) {
        do {
            try data.write(to: fileURL(for: url), options: .atomic)
            pruneIfNeeded()
        } catch {
            // 写缓存失败不影响显示，忽略。
        }
    }

    /// 磁盘超 500MB 时按修改时间从最旧的开始删，直到不超。
    private func pruneIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var total: Int64 = 0
        var infos: [(URL, Int64, Date)] = []
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let date = values.contentModificationDate else { continue }
            total += Int64(size)
            infos.append((file, Int64(size), date))
        }
        guard total > maxDiskBytes else { return }
        infos.sort { $0.2 < $1.2 }
        for (file, size, _) in infos {
            if total <= maxDiskBytes { break }
            try? fm.removeItem(at: file)
            total -= size
        }
    }
}

// MARK: - 带缓存的图片视图

enum CachedImagePhase {
    case empty
    case success(UIImage)
    case failure
}

/// 先查缓存，有就直接显示，没有就下载并写缓存。
/// content 拿到加载状态和一个重试动作（重试会重新请求，失败结果不进缓存）。
struct CachedImage<Content: View>: View {
    var url: String
    var prefetchURLs: [String] = []
    @ViewBuilder var content: (CachedImagePhase, @escaping () -> Void) -> Content

    @State private var phase: CachedImagePhase = .empty
    @State private var retryNonce = 0

    var body: some View {
        content(phase) { retryNonce += 1 }
            .task(id: "\(url)-\(retryNonce)") { await load() }
            .onAppear { prefetch() }
    }

    private func load() async {
        phase = .empty
        guard let u = URL(string: url) else {
            phase = .failure
            return
        }
        if let img = await ImageCache.shared.image(for: u) {
            phase = .success(img)
        } else {
            phase = .failure
        }
    }

    private func prefetch() {
        guard !prefetchURLs.isEmpty else { return }
        let urls = prefetchURLs.compactMap { URL(string: $0) }
        guard !urls.isEmpty else { return }
        Task { await ImageCache.shared.prefetch(urls: urls) }
    }
}
