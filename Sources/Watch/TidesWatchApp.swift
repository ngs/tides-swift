import SwiftUI

@main
struct TidesWatchApp: App {
    @State private var store = WatchTideStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(store)
        }
    }
}
