import SwiftUI

struct LibraryView: View {
    static let tags = ["全部", "青春", "性感", "长腿", "多人", "御姐", "巨乳", "新婚", "媳妇",
                       "暧昧", "清纯", "调教", "少妇", "风骚", "同居", "淫乱", "好友", "女神",
                       "诱惑", "偷情", "出轨", "正妹", "家教"]
    static let areas = [("全部", -1), ("韩国", 1), ("日本", 2), ("台湾", 3)]
    static let ends = [("全部", -1), ("连载", 0), ("完结", 1)]

    @State private var tag = "全部"
    @State private var area = -1
    @State private var end = -1
    @State private var books: [BookCard] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var loading = false
    @State private var loadingMore = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.tags, id: \.self) { t in
                            Button(t) { selectTag(t) }
                                .buttonStyle(.bordered)
                                .tint(tag == t ? .accentColor : .gray)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                HStack(spacing: 16) {
                    Picker("地区", selection: $area) {
                        ForEach(Self.areas, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    .pickerStyle(.segmented)
                    Picker("进度", selection: $end) {
                        ForEach(Self.ends, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
                .onChange(of: area) { _ in reload() }
                .onChange(of: end) { _ in reload() }

                Group {
                    if loading && books.isEmpty {
                        LoadingView()
                    } else if let error, books.isEmpty {
                        ErrorView(message: error) { reload() }
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                                spacing: 10
                            ) {
                                ForEach(books) { book in
                                    NavigationLink(value: book) { BookGridCard(book: book) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding()
                            if page < totalPages {
                                Button(loadingMore ? "加载中…" : "加载更多") { Task { await loadMore() } }
                                    .disabled(loadingMore)
                                    .padding()
                            }
                        }
                    }
                }
            }
            .navigationTitle("书库")
            .navigationDestination(for: BookCard.self) { book in
                BookDetailView(bookId: book.id)
            }
            .task { reload() }
        }
    }

    private func selectTag(_ t: String) {
        tag = t
        reload()
    }

    private func reload() {
        page = 1
        totalPages = 1
        books = []
        Task { await loadPage(1, replace: true) }
    }

    private func loadMore() async {
        guard page < totalPages, !loadingMore else { return }
        await loadPage(page + 1, replace: false)
    }

    private func loadPage(_ p: Int, replace: Bool) async {
        if replace { loading = true } else { loadingMore = true }
        defer { loading = false; loadingMore = false }
        do {
            let res = try await IkanmhAPI.booklist(tag: tag, area: area, end: end, page: p)
            if replace { books = res.list } else { books += res.list }
            page = res.page
            totalPages = res.total_pages
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
