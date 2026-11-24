import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 竖屏章节阅读器：图片全部来自 API 返回的图片地址，逐张滚动加载；
/// 点按切换界面显隐；底部上一话 / 目录 / 下一话。黑色背景，无广告。
/// 图片走磁盘 + 内存缓存并预加载后面 3 张；打开时回到上次看到的位置；
/// 图片加载失败点一下重试。
struct ReaderView: View {
    var book: BookDetail
    var chapter: ChapterRef
    var startIndex: Int = 0

    @EnvironmentObject private var store: LibraryStore
    @State private var currentChapter: ChapterRef
    @State private var detail: ChapterDetail?
    @State private var error: String?
    @State private var loading = false
    @State private var chromeHidden = false
    @State private var showChapters = false
    @State private var currentIndex = 0
    @State private var lastSavedIndex = -1
    @State private var lastSavedAt = Date.distantPast
    @State private var restoreTarget: Int?
    @State private var didRestoreScroll = false

    init(book: BookDetail, chapter: ChapterRef, startIndex: Int = 0) {
        self.book = book
        self.chapter = chapter
        self.startIndex = startIndex
        _currentChapter = State(initialValue: chapter)
        _restoreTarget = State(initialValue: startIndex > 0 ? startIndex : nil)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if loading && detail == nil {
                    ProgressView().tint(.white)
                } else if let detail {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(detail.images.enumerated()), id: \.offset) { index, url in
                                    ReaderImage(
                                        url: url,
                                        prefetchURLs: Array(detail.images.dropFirst(index + 1).prefix(3))
                                    )
                                    .id(index)
                                    .onAppear { onPageAppear(index) }
                                }
                            }
                        }
                        .onTapGesture { chromeHidden.toggle() }
                        .onAppear { restoreScroll(proxy: proxy, imageCount: detail.images.count) }
                        .onChange(of: detail.id) { _ in
                            restoreScroll(proxy: proxy, imageCount: detail.images.count)
                        }
                    }
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
        .onDisappear { saveProgress(force: true) }
    }

    private func go(to chapter: ChapterRef?) {
        guard let chapter else { return }
        currentChapter = chapter
        detail = nil
        error = nil
        currentIndex = 0
        lastSavedIndex = -1
        lastSavedAt = .distantPast
        // 回到最初打开的那话时，回到上次保存的位置；其他话从头看。
        if chapter.id == self.chapter.id,
           let p = store.progress(for: book.id), p.chapterId == chapter.id {
            restoreTarget = p.pageIndex
        } else {
            restoreTarget = nil
        }
        didRestoreScroll = false
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

    // MARK: - 断点续看

    private func onPageAppear(_ index: Int) {
        currentIndex = index
        saveProgress(force: false)
    }

    /// index 变化且距上次保存超过 2 秒才写；退出阅读器时强制写一次。
    private func saveProgress(force: Bool) {
        guard currentIndex != lastSavedIndex else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSavedAt) > 2 else { return }
        lastSavedIndex = currentIndex
        lastSavedAt = now
        store.saveProgress(
            bookId: book.id,
            chapterId: currentChapter.id,
            chapterTitle: currentChapter.title,
            pageIndex: currentIndex
        )
    }

    /// 打开一话后滚到上次看到的那张（LazyVStack 布局需要一点时间，分两次尝试）。
    private func restoreScroll(proxy: ScrollViewProxy, imageCount: Int) {
        guard !didRestoreScroll, let target = restoreTarget, imageCount > 0 else { return }
        let clamped = min(max(target, 0), imageCount - 1)
        guard clamped > 0 else { return }
        didRestoreScroll = true
        restoreTarget = nil
        Task {
            for delay in [350_000_000, 900_000_000] {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay))
                } catch {
                    return
                }
                proxy.scrollTo(clamped, anchor: .top)
            }
        }
    }
}

struct ReaderImage: View {
    var url: String
    var prefetchURLs: [String] = []

    var body: some View {
        CachedImage(url: url, prefetchURLs: prefetchURLs) { phase, retry in
            switch phase {
            case .success(let image):
                Image(uiImage: image).resizable().scaledToFit()
            case .failure:
                Color(white: 0.12)
                    .frame(height: 400)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.gray)
                            Text("加载失败，点一下重试")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .onTapGesture { retry() }
            case .empty:
                Color(white: 0.08)
                    .frame(height: 400)
                    .overlay { ProgressView().tint(.gray) }
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
