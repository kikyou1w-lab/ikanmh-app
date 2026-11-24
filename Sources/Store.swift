import Foundation

/// 本地收藏与阅读历史，存在 UserDefaults，不联网。
struct HistoryEntry: Identifiable, Codable, Hashable {
    var bookId: Int
    var bookTitle: String
    var cover: String
    var chapterId: Int
    var chapterTitle: String
    var date: Date
    var id: Int { bookId }
}

struct FavoriteEntry: Identifiable, Codable, Hashable {
    var bookId: Int
    var title: String
    var cover: String
    var id: Int { bookId }
}

/// 断点续看：一本书只留最新一条（最后一次读到的那话、那张）。
struct ReadingProgress: Codable, Hashable {
    var bookId: Int
    var chapterId: Int
    var chapterTitle: String
    var pageIndex: Int
    var date: Date
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var favorites: [FavoriteEntry] = []
    @Published private(set) var progress: [ReadingProgress] = []

    private let historyKey = "ikanmh.history.v1"
    private let favoritesKey = "ikanmh.favorites.v1"
    private let progressKey = "ikanmh.progress.v1"

    init() {
        history = load(key: historyKey) ?? []
        favorites = load(key: favoritesKey) ?? []
        progress = load(key: progressKey) ?? []
    }

    private func load<T: Decodable>(key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func progress(for bookId: Int) -> ReadingProgress? {
        progress.first { $0.bookId == bookId }
    }

    func saveProgress(bookId: Int, chapterId: Int, chapterTitle: String, pageIndex: Int) {
        let entry = ReadingProgress(
            bookId: bookId, chapterId: chapterId, chapterTitle: chapterTitle,
            pageIndex: pageIndex, date: Date()
        )
        progress.removeAll { $0.bookId == bookId }
        progress.insert(entry, at: 0)
        if progress.count > 100 { progress = Array(progress.prefix(100)) }
        save(progress, key: progressKey)
    }

    func recordHistory(book: BookDetail, chapter: ChapterRef) {
        let entry = HistoryEntry(
            bookId: book.id, bookTitle: book.title, cover: book.cover,
            chapterId: chapter.id, chapterTitle: chapter.title, date: Date()
        )
        history.removeAll { $0.bookId == book.id }
        history.insert(entry, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        save(history, key: historyKey)
    }

    func isFavorite(bookId: Int) -> Bool {
        favorites.contains { $0.bookId == bookId }
    }

    func toggleFavorite(book: BookDetail) {
        if let i = favorites.firstIndex(where: { $0.bookId == book.id }) {
            favorites.remove(at: i)
        } else {
            favorites.append(FavoriteEntry(bookId: book.id, title: book.title, cover: book.cover))
        }
        save(favorites, key: favoritesKey)
    }

    func removeFavorite(bookId: Int) {
        favorites.removeAll { $0.bookId == bookId }
        save(favorites, key: favoritesKey)
    }

    func removeHistory(bookId: Int) {
        history.removeAll { $0.bookId == bookId }
        save(history, key: historyKey)
    }

    func clearHistory() {
        history = []
        save(history, key: historyKey)
    }
}
