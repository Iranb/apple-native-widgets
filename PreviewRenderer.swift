// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import WidgetKit

private enum PreviewError: Error {
    case renderFailed
}

@MainActor
private func pngData<V: View>(for content: V, size: CGSize, scheme: ColorScheme) throws -> Data {
    let base = scheme == .dark
        ? Color(red: 0.07, green: 0.09, blue: 0.14)
        : Color(red: 0.72, green: 0.82, blue: 0.93)
    let accent = scheme == .dark
        ? Color(red: 0.18, green: 0.42, blue: 0.70)
        : Color(red: 0.95, green: 0.60, blue: 0.47)
    let card = ZStack {
        LinearGradient(colors: [base, accent.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
        Circle()
            .fill(Color.cyan.opacity(scheme == .dark ? 0.26 : 0.34))
            .frame(width: size.width * 0.72)
            .blur(radius: 34)
            .offset(x: size.width * 0.30, y: -size.height * 0.28)
        Circle()
            .fill(Color.purple.opacity(scheme == .dark ? 0.24 : 0.20))
            .frame(width: size.width * 0.58)
            .blur(radius: 30)
            .offset(x: -size.width * 0.32, y: size.height * 0.34)
        content
            .environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height)
    }
    .frame(width: size.width, height: size.height)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

    let renderer = ImageRenderer(content: card)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw PreviewError.renderFailed
    }
    return data
}

private func loadJSON<T: Decodable>(_ type: T.Type, path: String?) -> T? {
    guard let path, let data = FileManager.default.contents(atPath: path) else { return nil }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(T.self, from: data)
}

@main
@MainActor
struct PreviewRenderer {
    static func main() throws {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        guard args.count >= 2 else { return }
        let output = URL(fileURLWithPath: args[1], isDirectory: true)
        let snapshotPath = args.count > 2 ? args[2] : nil
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

#if HPC_PREVIEW
        let snapshot = loadJSON(HPCSnapshot.self, path: snapshotPath) ?? .preview
        let entry = HPCEntry(date: .now, snapshot: snapshot, mediumAccountPage: 0, largeAccountPage: 0)
        let secondPageEntry = HPCEntry(date: .now, snapshot: snapshot, mediumAccountPage: 1, largeAccountPage: 1)
        try render(HPCWidgetView(entry: entry, previewFamily: .systemSmall), size: CGSize(width: 158, height: 158), name: "hpc-small", output: output)
        try render(HPCWidgetView(entry: entry, previewFamily: .systemMedium), size: CGSize(width: 338, height: 158), name: "hpc-medium", output: output)
        try render(HPCWidgetView(entry: entry, previewFamily: .systemLarge), size: CGSize(width: 338, height: 354), name: "hpc-large", output: output)
        try render(HPCWidgetView(entry: secondPageEntry, previewFamily: .systemMedium), size: CGSize(width: 338, height: 158), name: "hpc-medium-page2", output: output)
        try render(HPCWidgetView(entry: secondPageEntry, previewFamily: .systemLarge), size: CGSize(width: 338, height: 354), name: "hpc-large-page2", output: output)
#elseif AUTODL_PREVIEW
        let snapshot = loadJSON(AutoDLSnapshot.self, path: snapshotPath) ?? .preview
        let entry = AutoDLEntry(date: .now, snapshot: snapshot)
        try render(AutoDLWidgetView(entry: entry, previewFamily: .systemSmall), size: CGSize(width: 158, height: 158), name: "autodl-small", output: output)
        try render(AutoDLWidgetView(entry: entry, previewFamily: .systemMedium), size: CGSize(width: 338, height: 158), name: "autodl-medium", output: output)
        try render(AutoDLWidgetView(entry: entry, previewFamily: .systemLarge), size: CGSize(width: 338, height: 354), name: "autodl-large", output: output)
#else
        let snapshot = loadJSON(DeadlineSnapshot.self, path: snapshotPath) ?? .preview
        let entry = DeadlineEntry(date: .now, snapshot: snapshot)
        let menuEntry = DeadlineEntry(date: .now, snapshot: snapshot, isConferenceMenuOpen: true)
        let selectedConferenceEntry = DeadlineEntry(date: .now, snapshot: snapshot, selectedConferenceName: "ICLR 2027")
        try render(DeadlineWidgetView(entry: entry, previewFamily: .systemSmall), size: CGSize(width: 158, height: 158), name: "deadline-small", output: output)
        try render(DeadlineWidgetView(entry: entry, previewFamily: .systemMedium), size: CGSize(width: 338, height: 158), name: "deadline-medium", output: output)
        try render(DeadlineWidgetView(entry: entry, previewFamily: .systemLarge), size: CGSize(width: 338, height: 354), name: "deadline-large", output: output)
        try render(DeadlineWidgetView(entry: menuEntry, previewFamily: .systemSmall), size: CGSize(width: 158, height: 158), name: "deadline-menu-small", output: output)
        try render(DeadlineWidgetView(entry: menuEntry, previewFamily: .systemMedium), size: CGSize(width: 338, height: 158), name: "deadline-menu-medium", output: output)
        try render(DeadlineWidgetView(entry: menuEntry, previewFamily: .systemLarge), size: CGSize(width: 338, height: 354), name: "deadline-menu-large", output: output)
        try render(DeadlineWidgetView(entry: selectedConferenceEntry, previewFamily: .systemMedium), size: CGSize(width: 338, height: 158), name: "deadline-selected-medium", output: output)
        try render(DeadlineWidgetView(entry: selectedConferenceEntry, previewFamily: .systemLarge), size: CGSize(width: 338, height: 354), name: "deadline-selected-large", output: output)
#endif
    }

    private static func render<V: View>(_ view: V, size: CGSize, name: String, output: URL) throws {
        for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            _ = try pngData(for: view, size: size, scheme: scheme)
            let data = try pngData(for: view, size: size, scheme: scheme)
            try data.write(to: output.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }
}
