import SwiftUI

struct HomeView: View {
    @State private var home: HomeResponse?
    @State private var error: String?
    @State private var loading = false
    @State private var refreshed = false

    // 首页本地缓存：上次成功拉到的数据存一份，打开先显示旧内容、后台静默刷新，
    // 接口再慢也不会白屏转圈；只有第一次打开（无缓存）才显示加载页。
    private let homeCacheKey = "ikanmh.home.cache.v1"

    private func loadCached() -> HomeResponse? {
        guard let data = UserDefaults.standard.data(forKey: homeCacheKey),
              let cached = try? JSONDecoder().decode(HomeResponse.self, from: data) else { return nil }
        // 空缓存是 11-26 下午源站回 200 空页时存进去的脏数据：三个列表全空，
        // 显示出来就是白屏。直接丢弃并清掉，下次重新拉。
        guard !cached.isEmpty else {
            UserDefaults.standard.removeObject(forKey: homeCacheKey)
            return nil
        }
        return cached
    }

    private func saveCached(_ home: HomeResponse) {
        // 全空不存，免得下次打开又白屏
        guard !home.isEmpty else { return }
        if let data = try? JSONEncoder().encode(home) {
            UserDefaults.standard.set(data, forKey: homeCacheKey)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading && home == nil {
                    LoadingView()
                } else if let home, !home.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !home.popular.isEmpty {
                                section(title: "本月人气") {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(alignment: .top, spacing: 12) {
                                            ForEach(home.popular) { book in
                                                NavigationLink(value: book) {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        BookCoverView(url: book.cover)
                                                            .frame(width: 120)
                                                        Text(book.title)
                                                            .font(.subheadline)
                                                            .lineLimit(1)
                                                            .frame(width: 120, alignment: .leading)
                                                        Text("\(book.clicks) 点击")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            if !home.latest.isEmpty {
                                section(title: "最近更新") {
                                    bookGrid(books: home.latest)
                                }
                            }
                            if !home.finished.isEmpty {
                                section(title: "完结优选") {
                                    bookGrid(books: home.finished)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .refreshable { await load(force: true) }
                } else if let error {
                    ErrorView(message: error) { Task { await load(force: true) } }
                } else {
                    // 兜底：任何状态都没命中时也别留白屏，显示加载中
                    LoadingView()
                }
            }
            .navigationTitle("漫小肆")
            .navigationDestination(for: BookCard.self) { book in
                BookDetailView(bookId: book.id)
            }
            .task { await load() }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.horizontal)
            content()
        }
    }

    private func bookGrid(books: [BookCard]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach(books) { book in
                NavigationLink(value: book) { BookGridCard(book: book) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private func load(force: Bool = false) async {
        if home == nil, let cached = loadCached() {
            home = cached
        }
        if home != nil && !force && refreshed { return }
        if loading { return }
        loading = true
        defer { loading = false }
        do {
            let fresh = try await IkanmhAPI.home()
            // 全空等于没拿到数据：不显示、不缓存，走错误页让用户点重试
            guard !fresh.isEmpty else {
                if home == nil { self.error = "没有拿到数据，请点重试" }
                return
            }
            home = fresh
            refreshed = true
            error = nil
            saveCached(fresh)
        } catch {
            // 有缓存内容在显示时静默失败，不弹错误页；无缓存才显示错误。
            if home == nil {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
