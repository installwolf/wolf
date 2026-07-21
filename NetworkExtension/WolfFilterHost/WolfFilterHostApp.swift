import SwiftUI

@main
struct WolfFilterHostApp: App {
    @StateObject private var model = FilterController()

    var body: some Scene {
        WindowGroup("Wolf Filter") {
            ContentView(model: model)
                .frame(width: 420, height: 300)
        }
        .windowResizability(.contentSize)
    }
}
