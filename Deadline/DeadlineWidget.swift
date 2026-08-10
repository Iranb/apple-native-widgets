// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import AppIntents
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
    let selectedConferenceName: String?
    let isConferenceMenuOpen: Bool

    init(
        date: Date,
        snapshot: DeadlineSnapshot,
        selectedConferenceName: String? = nil,
        isConferenceMenuOpen: Bool = false
    ) {
        self.date = date
        self.snapshot = snapshot
        self.selectedConferenceName = selectedConferenceName
        self.isConferenceMenuOpen = isConferenceMenuOpen
    }
}

private enum ConferenceSelection {
    static let selectedNameKey = "AIDeadlineSelectedConferenceName"
    static let menuOpenKey = "AIDeadlineConferenceMenuOpen"

    static var selectedName: String? {
        let value = UserDefaults.standard.string(forKey: selectedNameKey)
        return value?.isEmpty == false ? value : nil
    }

    static var isMenuOpen: Bool {
        UserDefaults.standard.bool(forKey: menuOpenKey)
    }
}

struct ToggleConferenceMenuIntent: AppIntent {
    static let title: LocalizedStringResource = "展开会议列表"
    static let description = IntentDescription("展开或收起 AI Deadline 组件中的会议列表。")
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: ConferenceSelection.menuOpenKey), forKey: ConferenceSelection.menuOpenKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct SelectDeadlineConferenceIntent: AppIntent {
    static let title: LocalizedStringResource = "切换会议"
    static let description = IntentDescription("切换 AI Deadline 组件当前显示的会议。")
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "会议") var conferenceName: String

    init() {
        conferenceName = ""
    }

    init(conferenceName: String) {
        self.conferenceName = conferenceName
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults.standard
        defaults.set(conferenceName, forKey: ConferenceSelection.selectedNameKey)
        defaults.set(false, forKey: ConferenceSelection.menuOpenKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct DeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeadlineEntry {
        DeadlineEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlineEntry) -> Void) {
        completion(makeEntry(snapshot: loadSnapshot() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineEntry>) -> Void) {
        let snapshot = loadSnapshot() ?? .preview
        completion(Timeline(entries: [makeEntry(snapshot: snapshot)], policy: .after(.now.addingTimeInterval(60))))
    }

    private func makeEntry(snapshot: DeadlineSnapshot) -> DeadlineEntry {
        let availableNames = Set(snapshot.conferences.map(\.name))
        let selectedName = ConferenceSelection.selectedName.flatMap { availableNames.contains($0) ? $0 : nil }
        return DeadlineEntry(
            date: .now,
            snapshot: snapshot,
            selectedConferenceName: selectedName,
            isConferenceMenuOpen: ConferenceSelection.isMenuOpen
        )
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
            ),
            ConferenceRecord(
                name: "CVPR 2027",
                deadlines: [],
                papers: []
            ),
            ConferenceRecord(
                name: "ICLR 2027",
                deadlines: [
                    DeadlineRecord(title: "摘要", dueAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(32 * 86_400))),
                    DeadlineRecord(title: "全文", dueAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(37 * 86_400)))
                ],
                papers: []
            ),
            ConferenceRecord(
                name: "NeurIPS 2027",
                deadlines: [],
                papers: []
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
    let isMenuOpen: Bool
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            Button(intent: ToggleConferenceMenuIntent()) {
                HStack(spacing: 7) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hasError ? .red : .blue)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: isMenuOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMenuOpen ? "收起会议列表" : "切换会议，当前为 \(name)")
            Spacer()
            if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !compact {
                Text("截止日")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
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
        if let selectedName = entry.selectedConferenceName,
           let selected = entry.snapshot.conferences.first(where: { $0.name == selectedName }) {
            return selected
        }
        return entry.snapshot.conferences.first(where: { !$0.deadlines.isEmpty })
            ?? entry.snapshot.conferences.first
            ?? ConferenceRecord(name: "AI Deadline", deadlines: [], papers: [])
    }

    private var upcoming: [DatedDeadline] { conference.datedDeadlines(after: entry.date) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch previewFamily ?? family {
                case .systemSmall: smallView
                case .systemLarge: largeView
                default: mediumView
                }
            }
            if entry.isConferenceMenuOpen {
                conferenceMenu
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .modifier(DeadlineWidgetContainer(enabled: previewFamily == nil))
        .modifier(DeadlineWidgetLink(enabled: previewFamily == nil))
    }

    private var conferenceMenu: some View {
        let isSmall = (previewFamily ?? family) == .systemSmall
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(entry.snapshot.conferences) { candidate in
                Button(intent: SelectDeadlineConferenceIntent(conferenceName: candidate.name)) {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.blue)
                            .opacity(candidate.name == conference.name ? 1 : 0)
                            .frame(width: 11)
                        Text(candidate.name)
                            .font(isSmall ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Spacer(minLength: isSmall ? 3 : 6)
                        if let next = candidate.datedDeadlines(after: entry.date).first {
                            Text("\(dayCount(to: next.date, from: entry.date))天")
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("TBA")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: isSmall ? 23 : 25)
                    .background(candidate.name == conference.name ? Color.blue.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(width: isSmall ? 142 : 178)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.primary.opacity(0.12), lineWidth: 0.5)
        }
        .padding(.top, isSmall ? 36 : 39)
        .padding(.leading, isSmall ? 9 : 13)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("会议列表")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeadlineHeader(
                name: conference.name,
                hasError: entry.snapshot.error != nil,
                isMenuOpen: entry.isConferenceMenuOpen,
                compact: (previewFamily ?? family) == .systemSmall
            )
            Spacer(minLength: 0)
            ContentUnavailableView {
                Label("暂无截止日", systemImage: "calendar")
            } description: {
                Text("官网待公布或当前阶段已结束")
            }
            Spacer(minLength: 0)
        }
        .padding((previewFamily ?? family) == .systemSmall ? 12 : 17)
    }

    @ViewBuilder private var smallView: some View {
        if let next = upcoming.first {
            VStack(alignment: .leading, spacing: 8) {
                DeadlineHeader(
                    name: conference.name,
                    hasError: entry.snapshot.error != nil,
                    isMenuOpen: entry.isConferenceMenuOpen,
                    compact: true
                )
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
            emptyState
        }
    }

    @ViewBuilder private var mediumView: some View {
        if let next = upcoming.first {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    DeadlineHeader(
                        name: conference.name,
                        hasError: entry.snapshot.error != nil,
                        isMenuOpen: entry.isConferenceMenuOpen,
                        compact: true
                    )
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
            emptyState
        }
    }

    @ViewBuilder private var largeView: some View {
        if let next = upcoming.first {
            VStack(alignment: .leading, spacing: 14) {
                DeadlineHeader(
                    name: conference.name,
                    hasError: entry.snapshot.error != nil,
                    isMenuOpen: entry.isConferenceMenuOpen
                )
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
            emptyState
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
