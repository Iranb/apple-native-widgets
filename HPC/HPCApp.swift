// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dashboardURL = URL(string: "http://127.0.0.1:8765/")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "bjtu-hpc-widget" else { return }
        switch url.host {
        case "reload":
            WidgetCenter.shared.reloadAllTimelines()
            Self.terminateSoon()
        case "token":
            let account = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "account" })?.value
            requestVisibleTokenLogin(account: account)
        default:
            NSWorkspace.shared.open(dashboardURL)
            Self.terminateSoon()
        }
    }

    private func requestVisibleTokenLogin(account: String?) {
        var request = URLRequest(url: dashboardURL.appendingPathComponent("api/token-guardian/visible-refresh"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: account.map { ["account": $0] } ?? [:])
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
                Self.terminateSoon()
            }
        }.resume()
    }

    private static func terminateSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }
}

@main
struct BJTUHPCNativeWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
