import SwiftUI

struct SearchView: View {
    @State private var keyword = ""
    @State private var results: [BookCard] = []
    @State private var total = 0
    @State private var searched = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("请输入漫画名称、作者名", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { search() }
                    Button("搜索") { search() }
                        .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
                Group {
                    if loading {
                        LoadingView()
                    } else if let error {
                        ErrorView(message: error) { search() }
                    } else if searched {
                        if results.isEmpty {
                            Text("没有找到相关漫画")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("共找到 \(total) 部相关漫画")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                    LazyVGrid(
                                        columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                                        spacing: 12
                                    ) {
                                        ForEach(results) { book in
                                            NavigationLink(value: book) { BookGridCard(book: book) }
                                                .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .padding(.vertical)
                            }
                        }
                    } else {
                        Text("搜你想看的漫画")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationDestination(for: BookCard.self) { book in
                BookDetailView(bookId: book.id)
            }
        }
    }

    private func search() {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        loading = true
        searched = true
        Task {
            do {
                let res = try await IkanmhAPI.search(keyword: kw)
                results = res.list
                total = res.total
                error = nil
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            loading = false
        }
    }
}
