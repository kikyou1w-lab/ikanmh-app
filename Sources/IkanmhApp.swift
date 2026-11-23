import SwiftUI

@main
struct IkanmhApp: App {
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
            LibraryView()
                .tabItem { Label("书库", systemImage: "books.vertical") }
            RankView()
                .tabItem { Label("排行", systemImage: "chart.bar") }
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            MyView()
                .tabItem { Label("我的", systemImage: "person") }
        }
    }
}
