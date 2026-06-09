import LatergramPrototype
import SwiftUI

@main
struct LatergramApp: App {
    init() {
        SentryBootstrap.start()
    }

    var body: some Scene {
        WindowGroup {
            AppView()
        }
    }
}
