// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import WidgetKit

final class AutoDLAppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/AutoDLNativeWidget/run_autodl_monitor.sh")
            .path
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == "autodl-widget" }) else { return }
        if url.host == "refresh" {
            refreshSnapshot()
        } else {
            WidgetCenter.shared.reloadAllTimelines()
            Self.terminateSoon()
        }
    }

    private func refreshSnapshot() {
        guard FileManager.default.isExecutableFile(atPath: monitor) else {
            WidgetCenter.shared.reloadAllTimelines()
            Self.terminateSoon()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: monitor)
        process.arguments = ["once", "--no-reload"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
                Self.terminateSoon()
            }
        }
        do {
            try process.run()
        } catch {
            WidgetCenter.shared.reloadAllTimelines()
            Self.terminateSoon()
        }
    }

    private static func terminateSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }
}

@main
struct AutoDLNativeWidgetApp: App {
    @NSApplicationDelegateAdaptor(AutoDLAppDelegate.self) private var appDelegate

    var body: some Scene { Settings { EmptyView() } }
}
