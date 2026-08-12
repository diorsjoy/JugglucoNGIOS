import SwiftUI

@main
struct AiDexApp: App {
    init() {
        setvbuf(stdout, nil, _IONBF, 0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
