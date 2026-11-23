import SwiftUI

struct MyView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("收藏") {
                    if store.favorites.isEmpty {
                        Text("还没有收藏").foregroundColor(.secondary)
                    } else {
                        ForEach(store.favorites) { fav in
                            NavigationLink(value: BookCard(id: fav.bookId, title: fav.title, cover: fav.cover)) {
                                HStack(spacing: 12) {
                                    BookCoverView(url: fav.cover).frame(width: 48)
                                    Text(fav.title).lineLimit(2)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                store.removeFavorite(bookId: store.favorites[i].bookId)
                            }
                        }
                    }
                }
                Section("阅读历史") {
                    if store.history.isEmpty {
                        Text("还没有阅读记录").foregroundColor(.secondary)
                    } else {
                        ForEach(store.history) { entry in
                            NavigationLink(value: BookCard(id: entry.bookId, title: entry.bookTitle, cover: entry.cover)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.bookTitle).lineLimit(1)
                                    Text("看到 \(entry.chapterTitle) · \(entry.date, style: .relative)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                store.removeHistory(bookId: store.history[i].bookId)
                            }
                        }
                    }
                }
                if !store.history.isEmpty {
                    Section {
                        Button("清空历史", role: .destructive) { showClearConfirm = true }
                    }
                }
            }
            .navigationTitle("我的")
            .navigationDestination(for: BookCard.self) { book in
                BookDetailView(bookId: book.id)
            }
            .alert("确定清空全部阅读历史？", isPresented: $showClearConfirm) {
                Button("清空", role: .destructive) { store.clearHistory() }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
