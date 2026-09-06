import AppKit
import SwiftUI

@main
struct CameraFileSortSwiftApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Camera Media Importer", id: "importer") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, idealWidth: 1440, minHeight: 700, idealHeight: 840)
                .background(WindowOpeningFrameSetter())
        }
        .defaultSize(width: 1440, height: 840)
        .windowResizability(.contentSize)
    }
}

private struct WindowOpeningFrameSetter: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.configure(window: nsView.window)
        }
    }

    final class Coordinator {
        private var didConfigure = false

        func configure(window: NSWindow?) {
            guard !didConfigure, let window else { return }
            didConfigure = true

            window.isRestorable = false
            window.setFrameAutosaveName("")

            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            guard let visibleFrame else {
                window.setContentSize(NSSize(width: 1440, height: 840))
                window.center()
                return
            }

            let size = NSSize(
                width: min(1440, visibleFrame.width * 0.92),
                height: min(840, visibleFrame.height * 0.84)
            )
            let origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        }
    }
}
