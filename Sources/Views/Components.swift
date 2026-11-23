import SwiftUI

/// 漫画封面（3:4），只加载 API 返回的封面图地址。
struct BookCoverView: View {
    var url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Color.gray.opacity(0.3)
                    .overlay {
                        Image(systemName: "book.closed").foregroundColor(.secondary)
                    }
            case .empty:
                Color.gray.opacity(0.15).overlay { ProgressView() }
            @unknown default:
                Color.gray.opacity(0.15)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipped()
        .cornerRadius(8)
    }
}

struct StarsView: View {
    var stars: Int

    var body: some View {
        if stars > 0 {
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < stars ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

struct BookGridCard: View {
    var book: BookCard

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            BookCoverView(url: book.cover)
            Text(book.title)
                .font(.subheadline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            StarsView(stars: book.stars)
            if !book.updated.isEmpty {
                Text(book.updated)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
