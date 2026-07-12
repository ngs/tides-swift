import SwiftData
import SwiftUI
import TidesPlatform
import TidesUI

@main
struct TidesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedLocation.self)
    }
}
