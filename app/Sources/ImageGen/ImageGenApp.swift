import AppKit
import SwiftUI

@main
struct ImageGenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("ImageGen", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    delegate.model = model
                    model.start()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Generate") { model.generate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canGenerate || model.showModelPicker)
                Button("Switch Model…") { model.showModelPicker = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(systemName: model.activeJobs.isEmpty ? "photo.stack" : "photo.badge.arrow.down")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    // Keep running with the window closed so MCP clients stay connected.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.shutdown() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Development aid: IMAGEGEN_SNAPSHOT=/path/prefix writes the main window to PNG every few seconds.
        guard let prefix = ProcessInfo.processInfo.environment["IMAGEGEN_SNAPSHOT"] else { return }
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let view = NSApp.windows.first(where: { $0.isVisible && $0.title == "ImageGen" })?.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: prefix + ".png"))
            }
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.engine.message)
        if let job = model.activeJobs.first {
            Text("\(job.stage) (\(model.activeJobs.count) in queue)")
        }
        Divider()
        Button("Open ImageGen") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Copy MCP URL") { Clipboard.copy(model.mcpURL) }
            .disabled(model.mcpURL.isEmpty)
        Button("Copy Claude Code Command") { Clipboard.copy(model.claudeCommand) }
            .disabled(model.mcpURL.isEmpty)
        Divider()
        Button("Quit ImageGen") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
