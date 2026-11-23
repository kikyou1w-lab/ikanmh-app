import SwiftUI

struct RankView: View {
    @State private var rank: RankResponse?
    @State private var selected: RankKey = .newBooks
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if loading && rank == nil {
                    LoadingView()
                } else if let rank {
                    VStack(spacing: 0) {
                        Picker("榜单", selection: $selected) {
                            ForEach(RankKey.allCases) { key in
                                Text(key.rawValue).tag(key)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        List(rank.list(for: selected)) { item in
                            NavigationLink(value: BookCard(id: item.id, title: item.title, cover: item.cover)) {
                                HStack(spacing: 12) {
                                    Text("\(item.rank)")
                                        .font(.headline)
                                        .foregroundColor(item.rank <= 3 ? .red : .secondary)
                                        .frame(width: 24)
                                    BookCoverView(url: item.cover)
                                        .frame(width: 48)
                                    Text(item.title)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                } else if let error {
                    ErrorView(message: error) { Task { await load() } }
                }
            }
            .navigationTitle("排行")
            .navigationDestination(for: BookCard.self) { book in
                BookDetailView(bookId: book.id)
            }
            .task { await load() }
        }
    }

    private func load() async {
        if rank != nil { return }
        loading = true
        defer { loading = false }
        do {
            rank = try await IkanmhAPI.rank()
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
