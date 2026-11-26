import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 线上 API: https://ikanmh-api.kikyou1w.workers.dev
/// App 数据优先从这里拿；Worker 拿不到（非 200 或网络错）时自动切直连抓站
/// （DirectSiteClient：手机直接抓源站，桌面 UA，四域名按序兜底），UI 不用改。
/// 接口返回的数据本身不含任何广告元素，App 内也不接任何广告 SDK。
enum IkanmhAPI {
    static let baseURL = URL(string: "https://ikanmh-api.kikyou1w.workers.dev")!

    static func url(path: String, query: [String: String] = [:]) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url!
    }

    static func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url(path: path, query: query))
        request.setValue("Ikanmh-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    static func home() async throws -> HomeResponse {
        try await withFallback(
            { try await get("api/home") },
            { try await DirectSiteClient.shared.home() }
        )
    }

    static func booklist(tag: String?, area: Int?, end: Int?, page: Int) async throws -> BookListResponse {
        var q: [String: String] = ["page": String(page)]
        if let tag, !tag.isEmpty, tag != "全部" { q["tag"] = tag }
        if let area, area >= 0 { q["area"] = String(area) }
        if let end, end >= 0 { q["end"] = String(end) }
        return try await withFallback(
            { try await get("api/booklist", query: q) },
            { try await DirectSiteClient.shared.booklist(tag: tag, area: area, end: end, page: page) }
        )
    }

    static func update(page: Int) async throws -> UpdateResponse {
        try await withFallback(
            { try await get("api/update", query: ["page": String(page)]) },
            { try await DirectSiteClient.shared.update(page: page) }
        )
    }

    static func rank() async throws -> RankResponse {
        try await withFallback(
            { try await get("api/rank") },
            { try await DirectSiteClient.shared.rank() }
        )
    }

    static func search(keyword: String) async throws -> SearchResponse {
        try await withFallback(
            { try await get("api/search", query: ["keyword": keyword]) },
            { try await DirectSiteClient.shared.search(keyword: keyword) }
        )
    }

    static func book(id: Int) async throws -> BookDetail {
        try await withFallback(
            { try await get("api/book/\(id)") },
            { try await DirectSiteClient.shared.book(id: id) }
        )
    }

    static func chapter(id: Int) async throws -> ChapterDetail {
        try await withFallback(
            { try await get("api/chapter/\(id)") },
            { try await DirectSiteClient.shared.chapter(id: id) }
        )
    }

    /// 先走 Worker，失败（非 200、网络错、解析错）就切直连抓站
    private static func withFallback<T>(
        _ worker: () async throws -> T,
        _ direct: () async throws -> T
    ) async throws -> T {
        do {
            return try await worker()
        } catch {
            return try await direct()
        }
    }
}

enum APIError: LocalizedError {
    case http(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "网络错误 (\(code))"
        case .decoding: return "数据解析失败"
        }
    }
}

// MARK: - 数据模型

struct BookCard: Identifiable, Codable, Hashable {
    var id: Int
    var title: String
    var cover: String
    var stars: Int
    var intro: String
    var updated: String
    var clicks: Int

    init(id: Int, title: String, cover: String, stars: Int = 0, intro: String = "", updated: String = "", clicks: Int = 0) {
        self.id = id
        self.title = title
        self.cover = cover
        self.stars = stars
        self.intro = intro
        self.updated = updated
        self.clicks = clicks
    }

    // 注意：合成的 Decodable 遇到缺失 key 会直接抛错，不会用默认值，
    // 所以这里手写 decodeIfPresent（接口只在 popular 里返回 clicks）。
    // 写了自定义 init(from:) 后 CodingKeys 不再自动生成，必须显式声明。
    enum CodingKeys: String, CodingKey {
        case id, title, cover, stars, intro, updated, clicks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
        updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? ""
        clicks = try c.decodeIfPresent(Int.self, forKey: .clicks) ?? 0
    }
}

struct HomeResponse: Codable {
    var latest: [BookCard]
    var popular: [BookCard]
    var finished: [BookCard]

    enum CodingKeys: String, CodingKey {
        case latest, popular, finished
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latest = try c.decodeIfPresent([BookCard].self, forKey: .latest) ?? []
        popular = try c.decodeIfPresent([BookCard].self, forKey: .popular) ?? []
        finished = try c.decodeIfPresent([BookCard].self, forKey: .finished) ?? []
    }
}

struct BookListResponse: Decodable {
    var list: [BookCard]
    var page: Int
    var total_pages: Int

    enum CodingKeys: String, CodingKey {
        case list, page, total_pages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        list = try c.decodeIfPresent([BookCard].self, forKey: .list) ?? []
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        total_pages = try c.decodeIfPresent(Int.self, forKey: .total_pages) ?? 1
    }
}

struct RankItem: Identifiable, Codable, Hashable {
    var rank: Int
    var id: Int
    var title: String
    var cover: String
}

enum RankKey: String, CaseIterable, Identifiable {
    case newBooks = "新书榜"
    case total = "总榜"
    case monthly = "月榜"
    case finished = "完结榜"
    case recommended = "推荐"
    var id: String { rawValue }
}

struct RankResponse: Decodable {
    var newBooks: [RankItem]
    var total: [RankItem]
    var monthly: [RankItem]
    var finished: [RankItem]
    var recommended: [RankItem]

    enum CodingKeys: String, CodingKey {
        case newBooks = "新书榜"
        case total = "总榜"
        case monthly = "月榜"
        case finished = "完结榜"
        case recommended = "推荐"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        newBooks = try c.decodeIfPresent([RankItem].self, forKey: .newBooks) ?? []
        total = try c.decodeIfPresent([RankItem].self, forKey: .total) ?? []
        monthly = try c.decodeIfPresent([RankItem].self, forKey: .monthly) ?? []
        finished = try c.decodeIfPresent([RankItem].self, forKey: .finished) ?? []
        recommended = try c.decodeIfPresent([RankItem].self, forKey: .recommended) ?? []
    }

    func list(for key: RankKey) -> [RankItem] {
        switch key {
        case .newBooks: return newBooks
        case .total: return total
        case .monthly: return monthly
        case .finished: return finished
        case .recommended: return recommended
        }
    }
}

struct SearchResponse: Decodable {
    var keyword: String
    var total: Int
    var list: [BookCard]

    enum CodingKeys: String, CodingKey {
        case keyword, total, list
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyword = try c.decodeIfPresent(String.self, forKey: .keyword) ?? ""
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        list = try c.decodeIfPresent([BookCard].self, forKey: .list) ?? []
    }
}

struct ChapterRef: Identifiable, Codable, Hashable {
    var id: Int
    var title: String
}

struct BookDetail: Codable, Hashable {
    var id: Int
    var title: String
    var alias: String
    var author: String
    var status: String
    var area: String
    var updated: String
    var views: Int
    var tags: [String]
    var stars: Int
    var cover: String
    var description: String
    var chapters: [ChapterRef]
    var first_chapter: Int

    enum CodingKeys: String, CodingKey {
        case id, title, alias, author, status, area, updated, views, tags, stars, cover, description, chapters, first_chapter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        alias = try c.decodeIfPresent(String.self, forKey: .alias) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        area = try c.decodeIfPresent(String.self, forKey: .area) ?? ""
        updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? ""
        views = try c.decodeIfPresent(Int.self, forKey: .views) ?? 0
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        chapters = try c.decodeIfPresent([ChapterRef].self, forKey: .chapters) ?? []
        first_chapter = try c.decodeIfPresent(Int.self, forKey: .first_chapter) ?? 0
    }
}

struct ChapterDetail: Decodable {
    var id: Int
    var book_id: Int
    var book_title: String
    var title: String
    var images: [String]
    var prev: ChapterRef?
    var next: ChapterRef?
    var chapters: [ChapterRef]

    enum CodingKeys: String, CodingKey {
        case id, book_id, book_title, title, images, prev, next, chapters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        book_id = try c.decodeIfPresent(Int.self, forKey: .book_id) ?? 0
        book_title = try c.decodeIfPresent(String.self, forKey: .book_title) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? []
        prev = try c.decodeIfPresent(ChapterRef.self, forKey: .prev)
        next = try c.decodeIfPresent(ChapterRef.self, forKey: .next)
        chapters = try c.decodeIfPresent([ChapterRef].self, forKey: .chapters) ?? []
    }
}
