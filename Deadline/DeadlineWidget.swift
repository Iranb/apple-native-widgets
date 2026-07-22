// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import WidgetKit

private enum DeadlineWidgetKind {
    static let stable = "AIDeadlineNativeWidget"
    static let transitional = "AIDeadlineWidget"
}

struct DeadlineSnapshot: Decodable {
    var version: Int?
    var writtenAt: String?
    var conferences: [ConferenceRecord]
    var error: String?
}

struct ConferenceRecord: Decodable, Identifiable {
    var name: String
    var deadlines: [DeadlineRecord]
    var papers: [PaperStatus]?
    var id: String { name }
}

struct DeadlineRecord: Decodable, Identifiable {
    var title: String
    var dueAt: String
    var id: String { "\(title)-\(dueAt)" }
}

struct PaperStatus: Decodable, Identifiable {
    var id: String
    var title: String
    var status: String
    var owner: String?
    var updatedAt: String?
}

struct DeadlineEntry: TimelineEntry {
    let date: Date
    let snapshot: DeadlineSnapshot
}

struct DeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeadlineEntry {
        DeadlineEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlineEntry) -> Void) {
        completion(DeadlineEntry(date: .now, snapshot: loadSnapshot() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineEntry>) -> Void) {
        let snapshot = loadSnapshot() ?? .preview
        completion(Timeline(entries: [DeadlineEntry(date: .now, snapshot: snapshot)], policy: .after(.now.addingTimeInterval(60))))
    }

    private func loadSnapshot() -> DeadlineSnapshot? {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIDeadlineNativeWidget/snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(DeadlineSnapshot.self, from: data)
    }
}

extension DeadlineSnapshot {
    static let preview = DeadlineSnapshot(
        version: 1,
        writtenAt: ISO8601DateFormatter().string(from: .now),
        conferences: [
            ConferenceRecord(
                name: "AAAI-27",
                deadlines: [
                    DeadlineRecord(title: "摘要", dueAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(5 * 86_400))),
                    DeadlineRecord(title: "全文", dueAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(12 * 86_400))),
                    DeadlineRecord(title: "补充材料 / 代码", dueAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(15 * 86_400)))
                ],
                papers: [
                    PaperStatus(id: "project-alpha", title: "Project Alpha", status: "实验中", owner: nil, updatedAt: nil),
                    PaperStatus(id: "project-beta", title: "Project Beta", status: "分析中", owner: nil, updatedAt: nil),
                    PaperStatus(id: "project-gamma", title: "Project Gamma", status: "待同步", owner: nil, updatedAt: nil)
                ]
            )
        ],
        error: nil
    )
}

private func parseISO8601(_ value: String) -> Date? {
    let standard = ISO8601DateFormatter()
    if let date = standard.date(from: value) { return date }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value)
}

private struct DatedDeadline: Identifiable {
    let record: DeadlineRecord
    let date: Date
    var id: String { record.id }
}

private extension ConferenceRecord {
    func datedDeadlines(after now: Date) -> [DatedDeadline] {
        deadlines.compactMap { record in
            parseISO8601(record.dueAt).map { DatedDeadline(record: record, date: $0) }
        }
        .filter { $0.date >= now }
        .sorted { $0.date < $1.date }
    }
}

private func dayCount(to date: Date, from now: Date) -> Int {
    max(0, Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0)
}

private func hourCount(to date: Date, from now: Date) -> Int {
    max(1, Int(ceil(date.timeIntervalSince(now) / 3_600)))
}

private func urgencyColor(days: Int) -> Color {
    if days <= 3 { return .red }
    if days <= 10 { return .orange }
    return .blue
}

private func statusColor(_ status: String) -> Color {
    if status.contains("完成") { return .green }
    if status.contains("暂停") || status.contains("决策") { return .red }
    if status.contains("待同步") { return .orange }
    if status.contains("实验") || status.contains("分析") { return .blue }
    if status.contains("调研") { return .teal }
    if status.contains("实现") { return .purple }
    if status.contains("写作") { return .indigo }
    return .secondary
}

private struct DeadlineHeader: View {
    let name: String
    let hasError: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hasError ? .red : .blue)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("截止日期")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
    }
}

private struct CountdownHero: View {
    let deadline: DatedDeadline
    let now: Date
    let compact: Bool

    private var days: Int { dayCount(to: deadline.date, from: now) }
    private var showsHours: Bool { days == 0 }
    private var remainingValue: Int { showsHours ? hourCount(to: deadline.date, from: now) : days }
    private var remainingUnit: String { showsHours ? "小时" : "天" }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(remainingValue)")
                    .font(.system(size: compact ? 42 : 48, weight: .bold, design: .rounded))
                    .tracking(-1.5)
                    .monospacedDigit()
                    .foregroundStyle(urgencyColor(days: days))
                Text(remainingUnit)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(deadline.record.title)
                .font(compact ? .caption.weight(.semibold) : .headline.weight(.semibold))
                .lineLimit(1)
            Text(deadline.date, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("距离 \(deadline.record.title) 还有 \(remainingValue) \(remainingUnit)")
    }
}

private struct DeadlineRow: View {
    let deadline: DatedDeadline
    let now: Date

    private var days: Int { dayCount(to: deadline.date, from: now) }
    private var shortTitle: String {
        let first = deadline.record.title.split(separator: "/", maxSplits: 1).first
        let title = first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? deadline.record.title
        if title.hasPrefix("补充") { return "补充" }
        if title.hasPrefix("Phase") { return "P1 结果" }
        return title
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(urgencyColor(days: days))
                .frame(width: 7, height: 7)
            Text(shortTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(deadline.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Text("\(days)天")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(urgencyColor(days: days))
                .frame(width: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PaperRow: View {
    let paper: PaperStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(paper.status))
                .frame(width: 7, height: 7)
            Text(paper.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(paper.status)
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusColor(paper.status))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DeadlineWidgetContainer: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.containerBackground(for: .widget) {
                Rectangle().fill(.regularMaterial)
            }
        } else {
            content
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

private struct GlassInset: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

private extension View {
    func glassInset(padding: CGFloat = 11) -> some View {
        modifier(GlassInset(padding: padding))
    }
}

private struct DeadlineWidgetLink: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.widgetURL(URL(string: "ai-deadline-widget://reload"))
        } else {
            content
        }
    }
}

struct DeadlineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeadlineEntry
    var previewFamily: WidgetFamily? = nil

    private var conference: ConferenceRecord {
        entry.snapshot.conferences.first(where: { !$0.deadlines.isEmpty })
            ?? entry.snapshot.conferences.first
            ?? ConferenceRecord(name: "AI Deadline", deadlines: [], papers: [])
    }

    private var upcoming: [DatedDeadline] { conference.datedDeadlines(after: entry.date) }

    var body: some View {
        Group {
            switch previewFamily ?? family {
            case .systemSmall: smallView
            case .systemLarge: largeView
            default: mediumView
            }
        }
        .modifier(DeadlineWidgetContainer(enabled: previewFamily == nil))
        .modifier(DeadlineWidgetLink(enabled: previewFamily == nil))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无截止日", systemImage: "calendar")
        } description: {
            Text("同步状态后会显示在这里")
        }
    }

    @ViewBuilder private var smallView: some View {
        if let next = upcoming.first {
            VStack(alignment: .leading, spacing: 8) {
                DeadlineHeader(name: conference.name, hasError: entry.snapshot.error != nil)
                Spacer(minLength: 0)
                CountdownHero(deadline: next, now: entry.date, compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassInset(padding: 9)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.fill")
                    Text("\(conference.papers?.count ?? 0) 篇论文")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(14)
        } else {
            emptyState.padding(12)
        }
    }

    @ViewBuilder private var mediumView: some View {
        if let next = upcoming.first {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    DeadlineHeader(name: conference.name, hasError: entry.snapshot.error != nil)
                    Spacer(minLength: 0)
                    CountdownHero(deadline: next, now: entry.date, compact: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassInset(padding: 11)
                VStack(alignment: .leading, spacing: 9) {
                    Text("接下来")
                        .font(.caption.weight(.semibold))
                    ForEach(Array(upcoming.dropFirst().prefix(3))) { deadline in
                        DeadlineRow(deadline: deadline, now: entry.date)
                    }
                    if upcoming.count <= 1 {
                        Text("这是当前最后一个截止日")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        } else {
            emptyState.padding(12)
        }
    }

    @ViewBuilder private var largeView: some View {
        if let next = upcoming.first {
            VStack(alignment: .leading, spacing: 14) {
                DeadlineHeader(name: conference.name, hasError: entry.snapshot.error != nil)
                HStack(alignment: .center, spacing: 14) {
                    CountdownHero(deadline: next, now: entry.date, compact: false)
                        .frame(width: 108, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(upcoming.dropFirst().prefix(3))) { deadline in
                            DeadlineRow(deadline: deadline, now: entry.date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .glassInset(padding: 12)
                Divider().opacity(0.45)
                HStack {
                    Label("论文进度", systemImage: "doc.text.fill")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(conference.papers?.count ?? 0) 个项目")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 9) {
                    ForEach(Array((conference.papers ?? []).prefix(5))) { paper in
                        PaperRow(paper: paper)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(17)
        } else {
            emptyState.padding(12)
        }
    }
}

#if WIDGET_EXTENSION
struct AIDeadlineWidget: Widget {
    let kind: String
    let displayName: String

    init() {
        kind = DeadlineWidgetKind.stable
        displayName = "AI Deadline"
    }

    init(kind: String, displayName: String) {
        self.kind = kind
        self.displayName = displayName
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeadlineProvider()) { entry in
            DeadlineWidgetView(entry: entry)
        }
        .configurationDisplayName(displayName)
        .description("查看最近的投稿截止日与论文进度。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct AIDeadlineWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIDeadlineWidget(kind: DeadlineWidgetKind.stable, displayName: "AI Deadline")
        AIDeadlineWidget(kind: DeadlineWidgetKind.transitional, displayName: "AI Deadline（兼容）")
    }
}
#endif
