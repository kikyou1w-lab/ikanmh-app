import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - 直连抓站兜底
//
// 源站自 2026-11-26 下午起对 Cloudflare Workers 出口 IP 一律回 520，
// Worker 接口全挂；但用户手机的网络没被拦，本机直连源站全是 200。
// DirectSiteClient 让 App 在 Worker 拿不到数据时直接抓源站 HTML 解析，
// 返回和 Worker 接口完全相同的模型对象，UI 不用改。
// 解析规则从 ~/workspace/ikanmh-api/worker.js 原样移植（桌面版面）。
//
// 关键：请求头必须用桌面版 Chrome UA，iPhone UA 会拿到另一套版面，
// 解析规则是按桌面版面写的。

enum DirectError: LocalizedError {
    case http(Int)
    case badURL
    case empty
    case allDomainsFailed

    var errorDescription: String? {
        switch self {
        case .http(let code): return "网络错误 (\(code))"
        case .badURL: return "地址错误"
        case .empty: return "数据为空，请重试"
        case .allDomainsFailed: return "源站暂时无法访问"
        }
    }
}

/// /api/update 的返回（App 目前没用到，补齐 7 个接口一一对应）
struct UpdateResponse: Decodable {
    var list: [BookCard]
    var page: Int
    var total_pages: Int
    var updated_count: Int

    enum CodingKeys: String, CodingKey {
        case list, page, total_pages, updated_count
    }

    init(list: [BookCard], page: Int, total_pages: Int, updated_count: Int) {
        self.list = list
        self.page = page
        self.total_pages = total_pages
        self.updated_count = updated_count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        list = try c.decodeIfPresent([BookCard].self, forKey: .list) ?? []
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        total_pages = try c.decodeIfPresent(Int.self, forKey: .total_pages) ?? 1
        updated_count = try c.decodeIfPresent(Int.self, forKey: .updated_count) ?? 0
    }
}

// 直连返回的模型要和 Worker 接口一致，模型在 API.swift 里只有
// init(from:)，这里补一个成员初始化器（不改 API.swift 的模型）。
extension HomeResponse {
    init(latest: [BookCard], popular: [BookCard], finished: [BookCard]) {
        self.latest = latest
        self.popular = popular
        self.finished = finished
    }
}

extension BookListResponse {
    init(list: [BookCard], page: Int, total_pages: Int) {
        self.list = list
        self.page = page
        self.total_pages = total_pages
    }
}

extension RankResponse {
    init(newBooks: [RankItem], total: [RankItem], monthly: [RankItem], finished: [RankItem], recommended: [RankItem]) {
        self.newBooks = newBooks
        self.total = total
        self.monthly = monthly
        self.finished = finished
        self.recommended = recommended
    }
}

extension SearchResponse {
    init(keyword: String, total: Int, list: [BookCard]) {
        self.keyword = keyword
        self.total = total
        self.list = list
    }
}

extension BookDetail {
    init(id: Int, title: String, alias: String, author: String, status: String, area: String, updated: String, views: Int, tags: [String], stars: Int, cover: String, description: String, chapters: [ChapterRef], first_chapter: Int) {
        self.id = id
        self.title = title
        self.alias = alias
        self.author = author
        self.status = status
        self.area = area
        self.updated = updated
        self.views = views
        self.tags = tags
        self.stars = stars
        self.cover = cover
        self.description = description
        self.chapters = chapters
        self.first_chapter = first_chapter
    }
}

extension ChapterDetail {
    init(id: Int, book_id: Int, book_title: String, title: String, images: [String], prev: ChapterRef?, next: ChapterRef?, chapters: [ChapterRef]) {
        self.id = id
        self.book_id = book_id
        self.book_title = book_title
        self.title = title
        self.images = images
        self.prev = prev
        self.next = next
        self.chapters = chapters
    }
}

// MARK: - 正则小工具

enum RX {
    /// 返回全部捕获组（[0] 是整个匹配，[1...] 是各分组），没匹配到返回 []
    static func first(_ pattern: String, in text: String) -> [String?] {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return [] }
        return groups(m, text)
    }

    static func all(_ pattern: String, in text: String) -> [[String?]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { groups($0, text) }
    }

    static func count(_ pattern: String, in text: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func groups(_ m: NSTextCheckingResult, _ text: String) -> [String?] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
            return String(text[range])
        }
    }
}

extension Array where Element == String? {
    /// 取第 i 个捕获组，没有返回 nil
    func g(_ i: Int) -> String? {
        guard i < count else { return nil }
        return self[i]
    }
}

extension String {
    /// 空串变 nil，方便 `clean(a) ?? clean(b) ?? ""` 这种链式回退
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - 站内 HTML 解析（从 worker.js 原样移植）

enum SiteParse {
    static let imgHost = "https://www.jjmhw12.top"

    static func coverUrl(_ id: Int) -> String {
        "\(imgHost)/static/upload/book/\(id)/cover.jpg"
    }

    static func decodeEntities(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "&hellip;", with: "…")
        r = r.replacingOccurrences(of: "&nbsp;", with: " ")
        r = r.replacingOccurrences(of: "&amp;", with: "&")
        r = r.replacingOccurrences(of: "&quot;", with: "\"")
        r = r.replacingOccurrences(of: "&#39;", with: "'")
        r = r.replacingOccurrences(of: "&apos;", with: "'")
        r = r.replacingOccurrences(of: "&lt;", with: "<")
        r = r.replacingOccurrences(of: "&gt;", with: ">")
        return r
    }

    static func stripTags(_ s: String) -> String {
        decodeEntities(RX.replace(#"<[^>]*>"#, in: s, with: ""))
    }

    /// 去标签、解实体、空白折叠成一个空格并去首尾空白
    static func clean(_ s: String?) -> String {
        stripTags(s ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // 站内卡片统一结构：
    // <div class="mh-item"><a href="/book/{id}" title="标题"><p class="mh-cover"
    //   style="background-image: url(封面)"></p></a><div class="mh-item-detali">
    //   <h2 class="title"><a href="/book/{id}">标题</a></h2>
    //   <p class="zl"><span>评分:</span><span class="mh-star-line star-N"></span></p>
    //   <p class="chapter">简介 / 更新时间:YYYY-MM-DD</p>
    static func parseCard(_ chunk: String) -> BookCard? {
        guard let idStr = RX.first(#"/book/(\d+)"#, in: chunk).g(1),
              let id = Int(idStr) else { return nil }
        let title = clean(RX.first(#"<a[^>]*href="/book/\d+"[^>]*title="([^"]+)""#, in: chunk).g(1)).nonEmpty
            ?? clean(RX.first(#"<h2 class="title">\s*<a[^>]*>([^<]+)</a>"#, in: chunk).g(1)).nonEmpty
            ?? clean(RX.first(#"<p class="title">\s*<a[^>]*>([^<]+)</a>"#, in: chunk).g(1)).nonEmpty
            ?? ""
        let cover = RX.first(#"background-image:\s*url\(([^)]+)\)"#, in: chunk).g(1) ?? coverUrl(id)
        var stars = Int(RX.first(#"mh-star-line star-(\d)"#, in: chunk).g(1) ?? "") ?? 0
        if stars == 0 {
            // 本月人气 swiper 用 <div class="star"><span class="active">…</span>
            if let inner = RX.first(#"<div class="star">([\s\S]*?)</div>"#, in: chunk).g(1) {
                stars = RX.count(#"class="active""#, in: inner)
            }
        }
        var intro = ""
        var updated = ""
        if let ch = RX.first(#"<p class="chapter"[^>]*>([\s\S]*?)</p>"#, in: chunk).g(1) {
            var txt = clean(ch)
            // 注意：列表页这里是 ASCII 冒号（worker.js 原样），详情页是全角冒号
            if txt.hasPrefix("更新时间:") {
                txt = clean(String(txt.dropFirst("更新时间:".count)))
            } else if txt.hasPrefix("更新") {
                txt = clean(String(txt.dropFirst("更新".count)))
            }
            if RX.first(#"^(\d{4}-\d{2}-\d{2})$"#, in: txt).g(1) != nil {
                updated = txt
            } else {
                intro = txt
            }
        }
        return BookCard(id: id, title: title, cover: cover, stars: stars, intro: intro, updated: updated)
    }

    static func parseList(_ html: String) -> [BookCard] {
        var out: [BookCard] = []
        var seen = Set<Int>()
        for chunk in html.components(separatedBy: #"<div class="mh-item">"#).dropFirst() {
            if let card = parseCard(String(chunk)), !seen.contains(card.id) {
                seen.insert(card.id)
                out.append(card)
            }
        }
        return out
    }

    static func maxPage(_ html: String, prefix: String) -> Int {
        let pattern = NSRegularExpression.escapedPattern(for: prefix) + #"\?page=(\d+)"#
        let pages = RX.all(pattern, in: html).compactMap { Int($0.g(1) ?? "") }
        return pages.max() ?? 1
    }

    static func segment(_ html: String, from start: String, to end: String?) -> String {
        guard let s = html.range(of: start) else { return "" }
        let from = s.lowerBound
        let to: String.Index
        if let end, let e = html.range(of: end, range: from..<html.endIndex) {
            to = e.lowerBound
        } else {
            to = html.endIndex
        }
        return String(html[from..<to])
    }

    static func parseHome(_ html: String) -> (latest: [BookCard], popular: [BookCard], finished: [BookCard]) {
        let latest = parseList(segment(html, from: ">最近更新<", to: ">本月人气<"))
        let finished = parseList(segment(html, from: ">完结优选<", to: nil))
        // 本月人气是 swiper：唯一的 <ul class="index-original-list">，6 条；
        // 同一段里还有新书榜/点击榜/推荐榜的 <li>（无星级/点击数），
        // 不能按整段切，必须只取这个 ul。
        var popular: [BookCard] = []
        if let u = html.range(of: "index-original-list") {
            let uEnd = html.range(of: "</ul>", range: u.upperBound..<html.endIndex)?.lowerBound ?? html.endIndex
            let popSeg = String(html[u.lowerBound..<uEnd])
            var seen = Set<Int>()
            for chunk in popSeg.components(separatedBy: "<li>").dropFirst() {
                let text = String(chunk)
                guard var card = parseCard(text), !seen.contains(card.id) else { continue }
                seen.insert(card.id)
                card.clicks = Int(RX.first(#"总点击[\s\S]*?<a[^>]*href="/book/\d+">\s*(\d+)\s*</a>"#, in: text).g(1) ?? "") ?? 0
                popular.append(card)
            }
        }
        return (latest, popular, finished)
    }

    // 每榜一段：<div class="title"> 新书榜</div>，首位是 mh-item horizontal，
    // 其余是 <div class="mh-itme-top"><a href="/book/{id}" title="标题">
    // <span class="num num-N">N</span>标题</a>（悬停提示里有重复链接，去重）
    static func parseRank(_ html: String) -> [String: [RankItem]] {
        let pattern = #"<div class="title">\s*(新书榜|总榜|月榜|完结榜|推荐)\s*</div>"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let matches = re.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var out: [String: [RankItem]] = [:]
        for (idx, m) in matches.enumerated() {
            guard let nameRange = Range(m.range(at: 1), in: html) else { continue }
            let name = String(html[nameRange])
            let segStart = Range(m.range, in: html)!.upperBound
            let segEnd = idx + 1 < matches.count
                ? Range(matches[idx + 1].range, in: html)!.lowerBound
                : html.endIndex
            out[name] = parseRankSegment(String(html[segStart..<segEnd]))
        }
        return out
    }

    static func parseRankSegment(_ seg: String) -> [RankItem] {
        let pattern = #"<a[^>]*href="/book/(\d+)"[^>]*title="([^"]*)"[^>]*>([\s\S]*?)</a>"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = re.matches(in: seg, range: NSRange(seg.startIndex..., in: seg))
        var items: [RankItem] = []
        var seen = Set<Int>()
        for m in matches {
            guard let idRange = Range(m.range(at: 1), in: seg),
                  let id = Int(seg[idRange]),
                  !seen.contains(id) else { continue }
            seen.insert(id)
            let title = clean(Range(m.range(at: 2), in: seg).map { String(seg[$0]) })
            let inner = Range(m.range(at: 3), in: seg).map { String(seg[$0]) } ?? ""
            let rank = Int(RX.first(#"num-(\d+)"#, in: inner).g(1) ?? "") ?? (items.count + 1)
            var cover = coverUrl(id)
            if items.isEmpty {
                // 首位：封面在链接之前的 background-image 里
                let beforeEnd = Range(m.range, in: seg)!.lowerBound
                let before = String(seg[seg.startIndex..<beforeEnd])
                if let c = RX.first(#"background-image:\s*url\(([^)]+)\)"#, in: before).g(1) {
                    cover = c
                }
            }
            items.append(RankItem(rank: rank, id: id, title: title, cover: cover))
        }
        return items
    }

    static func parseBook(_ html: String, id: Int) -> BookDetail {
        let title = clean(RX.first(#"<h1>([^<]+)</h1>"#, in: html).g(1))
        let alias = clean(RX.first(#"别名：([^<]*)</p>"#, in: html).g(1))
        let author = clean(RX.first(#"作者：([^<]*)</p>"#, in: html).g(1))
        let status = clean(RX.first(#"状态：<span>([^<]*)</span>"#, in: html).g(1))
        let areaGroups = RX.first(#"地区：<a href="/booklist/\?area=(\d+)"[^>]*>([^<]*)</a>"#, in: html)
        let area = clean(areaGroups.g(2))
        let updated = clean(RX.first(#"更新时间：([^<]*)</span>"#, in: html).g(1))
        let views = Int(RX.first(#"点击：(\d+)</span>"#, in: html).g(1) ?? "") ?? 0
        let tagSeg = RX.first(#"标签：([\s\S]*?)</span>"#, in: html).g(1) ?? ""
        let tags = RX.all(#">([^<]+)</a>"#, in: tagSeg).map { clean($0.g(1)) }
        let infoAt = html.range(of: #"<div class="info">"#)?.lowerBound ?? html.startIndex
        let stars = Int(RX.first(#"mh-star-line star-(\d)"#, in: String(html[infoAt...])).g(1) ?? "") ?? 0
        // 简介在 meta description 里："…漫画简介：「…」"
        var description = ""
        if let meta = RX.first(#"<meta name="description" content="([^"]*)""#, in: html).g(1) {
            let d = decodeEntities(meta)
            if let k = d.range(of: "漫画简介：") {
                description = String(d[k.upperBound...])
            } else {
                description = RX.replace(#"^提供.*?漫画，"#, in: d, with: "")
            }
            if description.hasPrefix("「") { description.removeFirst() }
            if description.hasSuffix("」") { description.removeLast() }
            description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let cover = RX.first(#"<img[^>]*src="(https://www\.jjmhw12\.top/static/upload/book/\d+/cover\.jpg)""#, in: html).g(1) ?? coverUrl(id)
        var chapters: [ChapterRef] = []
        var seen = Set<Int>()
        for groups in RX.all(#"<a href="/chapter/(\d+)" target="_blank" rel="nofollow">([^<]*)</a>"#, in: html) {
            guard let idStr = groups.g(1), let cid = Int(idStr), !seen.contains(cid) else { continue }
            seen.insert(cid)
            chapters.append(ChapterRef(id: cid, title: clean(groups.g(2))))
        }
        return BookDetail(
            id: id, title: title, alias: alias, author: author, status: status, area: area,
            updated: updated, views: views, tags: tags, stars: stars, cover: cover,
            description: description, chapters: chapters, first_chapter: chapters.first?.id ?? 0
        )
    }

    // 图片：<img class="lazy" data-original="https://www.jjmhw12.top/
    // static/upload/book/{book_id}/{chapter_id}/{seq}.jpg"> 按顺序排列
    static func parseChapter(_ html: String, id: Int) -> ChapterDetail {
        let title = clean(RX.first(#"<h1 class="title">([^<]*)</h1>"#, in: html).g(1))
        let bookGroups = RX.first(#"<a[^>]*href="/book/(\d+)"[^>]*>([^<]+)</a>"#, in: html)
        let bookId = Int(bookGroups.g(1) ?? "") ?? 0
        let bookTitle = clean(bookGroups.g(2))
        let chapterTitle: String
        if !bookTitle.isEmpty && title.hasPrefix(bookTitle) {
            chapterTitle = title.dropFirst(bookTitle.count).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            chapterTitle = title
        }
        let images = RX.all(#"data-original="([^"]+)""#, in: html).compactMap { $0.g(1) }
        let prevGroups = RX.first(#"<a[^>]*href="/chapter/(\d+)"[^>]*title="([^"]*)">上一章</a>"#, in: html)
        let nextGroups = RX.first(#"<a[^>]*href="/chapter/(\d+)"[^>]*title="([^"]*)">下一章</a>"#, in: html)
        let prev: ChapterRef? = {
            guard let idStr = prevGroups.g(1), let pid = Int(idStr) else { return nil }
            return ChapterRef(id: pid, title: prevGroups.g(2) ?? "")
        }()
        let next: ChapterRef? = {
            guard let idStr = nextGroups.g(1), let nid = Int(idStr) else { return nil }
            return ChapterRef(id: nid, title: nextGroups.g(2) ?? "")
        }()
        var chapters: [ChapterRef] = []
        var seen = Set<Int>()
        for groups in RX.all(#"<a[^>]*href="/chapter/(\d+)"[^>]*>\s*(第\d+話[^<]*?)\s*</a>"#, in: html) {
            guard let idStr = groups.g(1), let cid = Int(idStr), !seen.contains(cid) else { continue }
            seen.insert(cid)
            chapters.append(ChapterRef(id: cid, title: clean(groups.g(2))))
        }
        return ChapterDetail(
            id: id, book_id: bookId, book_title: bookTitle, title: chapterTitle,
            images: images, prev: prev, next: next, chapters: chapters
        )
    }
}

// MARK: - 直连客户端

actor DirectSiteClient {
    static let shared = DirectSiteClient()

    /// 桌面版 Chrome UA（worker.js 同款）。iPhone UA 会拿到另一套版面，解析会错。
    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    /// 同站域名只写一处，按顺序试（同站同库，书号一致）
    static let domains = [
        "https://www.ikanmh.xyz",
        "https://jjmhw.cc",
        "https://ikanmh.top",
        "https://wxzhm.top",
    ]

    /// 上次成功的域名下标，下次先试它
    private var domainIndex = 0

    // MARK: 抓取

    /// 单次请求，不重试；失败由调用方换域名
    private func download(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw DirectError.badURL }
        var request = URLRequest(url: url)
        request.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        // 直连是 Worker 挂了才走的兜底：手机出口被拦时连接会挂起，超时设 10 秒快速失败、
        // 换下一个域名，别让用户对着空白等半天
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw DirectError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        if let html = String(data: data, encoding: .utf8) { return html }
        return String(decoding: data, as: UTF8.self)
    }

    /// 按域名顺序抓一个 path，成功就记住这个域名
    private func fetchHTML(path: String) async throws -> String {
        var lastError: Error = DirectError.allDomainsFailed
        for attempt in 0..<Self.domains.count {
            let domain = Self.domains[(domainIndex + attempt) % Self.domains.count]
            do {
                let html = try await download(urlString: domain + path)
                domainIndex = (domainIndex + attempt) % Self.domains.count
                return html
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// 整个操作按域名重试：主请求、解析、空结果都算失败，换下一个域名重做
    private func withDomain<T>(_ work: (String) async throws -> T) async throws -> T {
        var lastError: Error = DirectError.allDomainsFailed
        for attempt in 0..<Self.domains.count {
            let domain = Self.domains[(domainIndex + attempt) % Self.domains.count]
            do {
                let result = try await work(domain)
                domainIndex = (domainIndex + attempt) % Self.domains.count
                return result
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// 列表页本身没有更新日期，只有详情页有「更新时间：YYYY-MM-DD」。
    /// 把列表里缺日期的书逐本去详情页抓回来补上，多个列表合起来去重
    /// （同一本书只抓一次）、每批 16 本并行、抓不到的留空。
    private func enrichUpdated(_ lists: inout [[BookCard]]) async {
        var order: [Int] = []
        var seen = Set<Int>()
        for list in lists {
            for b in list where b.updated.isEmpty && !seen.contains(b.id) {
                seen.insert(b.id)
                order.append(b.id)
            }
        }
        let need = Array(order.prefix(60))
        var dates: [Int: String] = [:]
        var start = 0
        while start < need.count {
            let chunk = Array(need[start..<min(start + 16, need.count)])
            let got = await withTaskGroup(of: (Int, String?).self) { group in
                for id in chunk {
                    group.addTask {
                        do {
                            let html = try await self.fetchHTML(path: "/book/\(id)")
                            if let m = RX.first(#"更新时间：([^<]*)<"#, in: html).g(1) {
                                return (id, SiteParse.clean(m))
                            }
                        } catch {
                            // 留空，下次刷新再试
                        }
                        return (id, nil)
                    }
                }
                var out: [Int: String] = [:]
                for await (id, d) in group {
                    if let d, !d.isEmpty { out[id] = d }
                }
                return out
            }
            dates.merge(got) { _, new in new }
            start += 16
        }
        for li in lists.indices {
            for bi in lists[li].indices where lists[li][bi].updated.isEmpty {
                if let d = dates[lists[li][bi].id] { lists[li][bi].updated = d }
            }
        }
    }

    // MARK: 7 个接口（和 IkanmhAPI 一一对应，返回相同模型）

    func home() async throws -> HomeResponse {
        try await withDomain { domain in
            let html = try await self.download(urlString: domain + "/")
            let parsed = SiteParse.parseHome(html)
            guard !parsed.latest.isEmpty || !parsed.popular.isEmpty || !parsed.finished.isEmpty else {
                throw DirectError.empty
            }
            var lists = [parsed.latest, parsed.popular, parsed.finished]
            await self.enrichUpdated(&lists)
            return HomeResponse(latest: lists[0], popular: lists[1], finished: lists[2])
        }
    }

    func booklist(tag: String?, area: Int?, end: Int?, page: Int) async throws -> BookListResponse {
        try await withDomain { domain in
            var items: [URLQueryItem] = []
            if let tag, !tag.isEmpty, tag != "全部" { items.append(URLQueryItem(name: "tag", value: tag)) }
            if let area, area >= 0 { items.append(URLQueryItem(name: "area", value: String(area))) }
            if let end, end >= 0 { items.append(URLQueryItem(name: "end", value: String(end))) }
            items.append(URLQueryItem(name: "page", value: String(page)))
            var comps = URLComponents(string: domain + "/booklist")!
            comps.queryItems = items
            guard let url = comps.url else { throw DirectError.badURL }
            let html = try await self.download(urlString: url.absoluteString)
            var lists = [SiteParse.parseList(html)]
            await self.enrichUpdated(&lists)
            guard !lists[0].isEmpty else { throw DirectError.empty }
            return BookListResponse(list: lists[0], page: page, total_pages: SiteParse.maxPage(html, prefix: "/booklist"))
        }
    }

    func update(page: Int) async throws -> UpdateResponse {
        try await withDomain { domain in
            let path = page > 1 ? "/update?page=\(page)" : "/update"
            let html = try await self.download(urlString: domain + path)
            var lists = [SiteParse.parseList(html)]
            await self.enrichUpdated(&lists)
            guard !lists[0].isEmpty else { throw DirectError.empty }
            let count = Int(RX.first(#"id="daykeyupdatecount">(\d+)<"#, in: html).g(1) ?? "") ?? 0
            return UpdateResponse(list: lists[0], page: page, total_pages: SiteParse.maxPage(html, prefix: "/update"), updated_count: count)
        }
    }

    func rank() async throws -> RankResponse {
        try await withDomain { domain in
            let html = try await self.download(urlString: domain + "/rank")
            let all = SiteParse.parseRank(html)
            return RankResponse(
                newBooks: all["新书榜"] ?? [],
                total: all["总榜"] ?? [],
                monthly: all["月榜"] ?? [],
                finished: all["完结榜"] ?? [],
                recommended: all["推荐"] ?? []
            )
        }
    }

    func search(keyword: String) async throws -> SearchResponse {
        try await withDomain { domain in
            var comps = URLComponents(string: domain + "/search")!
            comps.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
            guard let url = comps.url else { throw DirectError.badURL }
            let html = try await self.download(urlString: url.absoluteString)
            let total = Int(RX.first(#"id="counts">(\d+)<"#, in: html).g(1) ?? "") ?? 0
            var lists = [SiteParse.parseList(html)]
            await self.enrichUpdated(&lists)
            return SearchResponse(keyword: keyword, total: total, list: lists[0])
        }
    }

    func book(id: Int) async throws -> BookDetail {
        try await withDomain { domain in
            let html = try await self.download(urlString: domain + "/book/\(id)")
            let detail = SiteParse.parseBook(html, id: id)
            guard !detail.title.isEmpty else { throw DirectError.empty }
            return detail
        }
    }

    func chapter(id: Int) async throws -> ChapterDetail {
        try await withDomain { domain in
            let html = try await self.download(urlString: domain + "/chapter/\(id)")
            let detail = SiteParse.parseChapter(html, id: id)
            guard !detail.images.isEmpty else { throw DirectError.empty }
            return detail
        }
    }
}
