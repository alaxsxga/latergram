import LatergramPrototype
import SwiftUI
import UIKit

@main
struct LatergramApp: App {
    init() {
        SentryBootstrap.start()
        UIWindow.appearance().backgroundColor = UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1)
    }

    var body: some Scene {
        WindowGroup {
            AppView()
        }
    }
}
