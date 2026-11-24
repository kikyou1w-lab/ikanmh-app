import SwiftUI

struct ReaderTarget: Hashable {
    var book: BookDetail
    var chapter: ChapterRef
    var startIndex: Int = 0
}

struct BookDetailView: View {
    var bookId: Int

    @EnvironmentObject private var store: LibraryStore
    @State private var detail: BookDetail?
    @State private var error: String?
    @State private var loading = false
    @State private var reversed = false

    var chapters: [ChapterRef] {
        guard let detail else { return [] }
        return reversed ? Array(detail.chapters.reversed()) : detail.chapters
    }

    /// 上次读到的那话（有断点续看进度时才有）。
    var resumeChapterId: Int? {
        guard let detail else { return nil }
        return store.progress(for: detail.id)?.chapterId
    }

    var body: some View {
        Group {
            if loading && detail == nil {
                LoadingView()
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            BookCoverView(url: detail.cover)
                                .frame(width: 120)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(detail.title)
                                    .font(.title3)
                                    .bold()
                                    .lineLimit(3)
                                if !detail.alias.isEmpty {
                                    Text("别名：\(detail.alias)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Text("作者：\(detail.author)").font(.subheadline)
                                Text("状态：\(detail.status) · \(detail.area)").font(.subheadline)
                                Text("更新：\(detail.updated)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("点击：\(detail.views)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                StarsView(stars: detail.stars)
                            }
                        }
                        if !detail.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(detail.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.secondary.opacity(0.15))
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }
                        if !detail.description.isEmpty {
                            Text(detail.description).font(.body)
                        }
                        if let p = store.progress(for: detail.id),
                           let resumeChapter = detail.chapters.first(where: { $0.id == p.chapterId }) {
                            NavigationLink(value: ReaderTarget(book: detail, chapter: resumeChapter, startIndex: p.pageIndex)) {
                                Label("继续阅读 · \(p.chapterTitle)（第 \(p.pageIndex + 1) 张）", systemImage: "bookmark.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        HStack(spacing: 12) {
                            if let first = detail.chapters.first {
                                NavigationLink(value: ReaderTarget(book: detail, chapter: first)) {
                                    Label("开始阅读", systemImage: "book.open")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            Button {
                                store.toggleFavorite(book: detail)
                            } label: {
                                Label(
                                    store.isFavorite(bookId: detail.id) ? "已收藏" : "收藏",
                                    systemImage: store.isFavorite(bookId: detail.id) ? "heart.fill" : "heart"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        HStack {
                            Text("章节（\(detail.chapters.count) 话）").font(.headline)
                            Spacer()
                            Button(reversed ? "正序" : "倒序") { reversed.toggle() }
                                .font(.subheadline)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                            ForEach(chapters) { ch in
                                NavigationLink(value: ReaderTarget(book: detail, chapter: ch)) {
                                    HStack(spacing: 4) {
                                        Text(ch.title)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        if ch.id == resumeChapterId {
                                            Image(systemName: "bookmark.fill")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            }
        }
        .navigationTitle(detail?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ReaderTarget.self) { target in
            ReaderView(book: target.book, chapter: target.chapter, startIndex: target.startIndex)
        }
        .task { await load() }
    }

    private func load() async {
        if detail != nil { return }
        loading = true
        defer { loading = false }
        do {
            detail = try await IkanmhAPI.book(id: bookId)
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
