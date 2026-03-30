import SwiftUI

@main
struct CameraFileSortSwiftApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1080, idealWidth: 1080, minHeight: 500, idealHeight: 500)
        }
        .windowResizability(.contentSize)
    }
}
