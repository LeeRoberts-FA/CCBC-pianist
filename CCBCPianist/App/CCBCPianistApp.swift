import SwiftUI

@main
struct CCBCPianistApp: App {
    @StateObject private var model = PianistViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 960, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
