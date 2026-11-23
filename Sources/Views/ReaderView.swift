import SwiftUI

/// 竖屏章节阅读器：图片全部来自 API 返回的图片地址，逐张滚动加载；
/// 点按切换界面显隐；底部上一话 / 目录 / 下一话。黑色背景，无广告。
struct ReaderView: View {
    var book: BookDetail
    var chapter: ChapterRef

    @EnvironmentObject private var store: LibraryStore
    @State private var currentChapter: ChapterRef
    @State private var detail: ChapterDetail?
    @State private var error: String?
    @State private var loading = false
    @State private var chromeHidden = false
    @State private var showChapters = false

    init(book: BookDetail, chapter: ChapterRef) {
        self.book = book
        self.chapter = chapter
        _currentChapter = State(initialValue: chapter)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if loading && detail == nil {
                    ProgressView().tint(.white)
                } else if let detail {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(detail.images, id: \.self) { url in
                                ReaderImage(url: url)
                            }
                        }
                    }
                    .onTapGesture { chromeHidden.toggle() }
                } else if let error {
                    VStack(spacing: 12) {
                        Text(error).foregroundColor(.white)
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.bordered)
                            .tint(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle(detail?.title ?? currentChapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(chromeHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar(chromeHidden ? .hidden : .visible, for: .bottomBar)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("上一话") { go(to: detail?.prev) }
                    .disabled(detail?.prev == nil)
                Spacer()
                Button("目录") { showChapters = true }
                Spacer()
                Button("下一话") { go(to: detail?.next) }
                    .disabled(detail?.next == nil)
            }
        }
        .sheet(isPresented: $showChapters) {
            ChapterListSheet(
                book: book,
                chapters: detail?.chapters ?? book.chapters,
                currentId: currentChapter.id
            ) { selected in
                showChapters = false
                go(to: selected)
            }
        }
        .task(id: currentChapter.id) { await load() }
    }

    private func go(to chapter: ChapterRef?) {
        guard let chapter else { return }
        currentChapter = chapter
        detail = nil
        error = nil
    }

    private func load() async {
        if detail?.id == currentChapter.id { return }
        loading = true
        defer { loading = false }
        do {
            let d = try await IkanmhAPI.chapter(id: currentChapter.id)
            detail = d
            error = nil
            store.recordHistory(book: book, chapter: ChapterRef(id: d.id, title: d.title))
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ReaderImage: View {
    var url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Color(white: 0.12)
                    .frame(height: 400)
                    .overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.gray)
                    }
            case .empty:
                Color(white: 0.08)
                    .frame(height: 400)
                    .overlay { ProgressView().tint(.gray) }
            @unknown default:
                Color(white: 0.08).frame(height: 400)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ChapterListSheet: View {
    var book: BookDetail
    var chapters: [ChapterRef]
    var currentId: Int
    var onSelect: (ChapterRef) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(chapters) { ch in
                Button {
                    onSelect(ch)
                } label: {
                    HStack {
                        Text(ch.title)
                        Spacer()
                        if ch.id == currentId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("\(book.title) · 目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
