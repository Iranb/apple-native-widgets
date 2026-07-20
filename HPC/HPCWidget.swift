// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import Foundation
import SwiftUI
import WidgetKit

private enum HPCWidgetKind {
    static let stable = "BJTUHPCNativeWidget"
    static let transitional = "BJTUHPCWidget"
}
private let extensionBundleID = "com.example.bjtu-hpc-native-widget.widget"

struct HPCSnapshot: Decodable {
    var version: Int?
    var writtenAt: String?
    var payload: HPCPayload?
    var guardian: GuardianPayload?
    var guardianError: String?
    var error: String?
    var returncode: Int?
}

struct HPCPayload: Decodable {
    var checkedAtLocal: String?
    var accounts: [HPCAccount]?
    var clusterResources: ClusterResources?
}

struct HPCAccount: Decodable, Identifiable {
    var name: String?
    var error: String?
    var hasToken: Bool?
    var summary: AccountSummary?
    var jobs: [JobPayload]?
    var id: String { name ?? UUID().uuidString }
}

struct AccountSummary: Decodable {
    var running: Int?
    var pending: Int?
    var other: Int?
    var total: Int?
    var runSlotsOpen: Int?
    var capOpen: Int?
    var runningCpus: Int?
    var runningGpus: Int?
    var pendingReasons: [String: Int]?
}

struct JobPayload: Decodable, Identifiable {
    var jobId: String?
    var state: String?
    var reason: String?
    var name: String?
    var id: String { jobId ?? UUID().uuidString }
}

struct ClusterResources: Decodable {
    var error: String?
    var summary: ClusterSummary?
    var nodes: [ClusterNode]?
    var excludedReservedNodes: [String]?
}

struct ClusterSummary: Decodable {
    var nodes: Int?
    var gpuAlloc: Int?
    var gpuTotal: Int?
    var gpuFree: Int?
    var cpuAlloc: Int?
    var cpuTotal: Int?
    var cpuFree: Int?
    var reservedNodes: Int?
}

struct ClusterNode: Decodable, Identifiable {
    var name: String?
    var state: String?
    var cpuAlloc: Int?
    var cpuTotal: Int?
    var cpuFree: Int?
    var gpuAlloc: Int?
    var gpuTotal: Int?
    var gpuFree: Int?
    var id: String { name ?? UUID().uuidString }
}

struct GuardianPayload: Decodable {
    var accounts: [String: GuardianAccount]?
    var error: String?
}

struct GuardianAccount: Decodable {
    var status: String?
    var attentionRequired: Bool?
    var attentionReason: String?
    var ageWarning: Bool?
    var needsVisibleLogin: Bool?
}

struct HPCEntry: TimelineEntry {
    let date: Date
    let snapshot: HPCSnapshot
    let mediumAccountPage: Int
    let largeAccountPage: Int
}

private enum HPCAccountPaging {
    static func pageCount(accountCount: Int, pageSize: Int) -> Int {
        max(1, Int(ceil(Double(accountCount) / Double(pageSize))))
    }

    static func key(pageSize: Int) -> String {
        "HPCAccountPage.\(pageSize)"
    }

    static func currentPage(pageSize: Int, pageCount: Int) -> Int {
        UserDefaults.standard.integer(forKey: key(pageSize: pageSize)) % max(1, pageCount)
    }
}

struct ChangeHPCAccountPageIntent: AppIntent {
    static let title: LocalizedStringResource = "切换 HPC 账号页"
    static let description = IntentDescription("在 BJTU HPC 桌面组件中切换账号列表。")
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "方向") var direction: Int
    @Parameter(title: "每页账号数") var pageSize: Int
    @Parameter(title: "总页数") var pageCount: Int

    init() {
        direction = 1
        pageSize = 3
        pageCount = 1
    }

    init(direction: Int, pageSize: Int, pageCount: Int) {
        self.direction = direction
        self.pageSize = pageSize
        self.pageCount = pageCount
    }

    func perform() async throws -> some IntentResult {
        let count = max(1, pageCount)
        let defaults = UserDefaults.standard
        let current = defaults.integer(forKey: HPCAccountPaging.key(pageSize: pageSize)) % count
        defaults.set((current + direction + count) % count, forKey: HPCAccountPaging.key(pageSize: pageSize))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct HPCProvider: TimelineProvider {
    func placeholder(in context: Context) -> HPCEntry {
        makeEntry(snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (HPCEntry) -> Void) {
        completion(makeEntry(snapshot: loadSnapshot() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HPCEntry>) -> Void) {
        let entry = makeEntry(snapshot: loadSnapshot() ?? .preview)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60))))
    }

    private func makeEntry(snapshot: HPCSnapshot) -> HPCEntry {
        let accountCount = snapshot.payload?.accounts?.count ?? 0
        let mediumPageCount = HPCAccountPaging.pageCount(accountCount: accountCount, pageSize: 3)
        let largePageCount = HPCAccountPaging.pageCount(accountCount: accountCount, pageSize: 4)
        return HPCEntry(
            date: .now,
            snapshot: snapshot,
            mediumAccountPage: HPCAccountPaging.currentPage(pageSize: 3, pageCount: mediumPageCount),
            largeAccountPage: HPCAccountPaging.currentPage(pageSize: 4, pageCount: largePageCount)
        )
    }

    private func loadSnapshot() -> HPCSnapshot? {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BJTUHPCNativeWidget/snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(HPCSnapshot.self, from: data)
    }
}

extension HPCSnapshot {
    static let preview = HPCSnapshot(
        version: 1,
        writtenAt: ISO8601DateFormatter().string(from: .now),
        payload: HPCPayload(
            checkedAtLocal: nil,
            accounts: [
                HPCAccount(name: "acct-a", error: nil, hasToken: true, summary: AccountSummary(running: 1, pending: 0, other: 0, total: 1, runSlotsOpen: 1, capOpen: 3, runningCpus: 6, runningGpus: 1, pendingReasons: [:]), jobs: []),
                HPCAccount(name: "acct-b", error: nil, hasToken: true, summary: AccountSummary(running: 1, pending: 1, other: 0, total: 2, runSlotsOpen: 1, capOpen: 2, runningCpus: 6, runningGpus: 1, pendingReasons: ["Resources": 1]), jobs: []),
                HPCAccount(name: "acct-c", error: nil, hasToken: false, summary: AccountSummary(running: 0, pending: 0, other: 0, total: 0, runSlotsOpen: 2, capOpen: 4, runningCpus: 0, runningGpus: 0, pendingReasons: [:]), jobs: []),
                HPCAccount(name: "acct-d", error: nil, hasToken: true, summary: AccountSummary(running: 1, pending: 0, other: 0, total: 1, runSlotsOpen: 1, capOpen: 3, runningCpus: 6, runningGpus: 1, pendingReasons: [:]), jobs: []),
                HPCAccount(name: "acct-e", error: nil, hasToken: true, summary: AccountSummary(running: 0, pending: 0, other: 0, total: 0, runSlotsOpen: 2, capOpen: 4, runningCpus: 0, runningGpus: 0, pendingReasons: [:]), jobs: []),
                HPCAccount(name: "acct-f", error: nil, hasToken: true, summary: AccountSummary(running: 1, pending: 0, other: 0, total: 1, runSlotsOpen: 1, capOpen: 3, runningCpus: 6, runningGpus: 1, pendingReasons: [:]), jobs: [])
            ],
            clusterResources: ClusterResources(
                error: nil,
                summary: ClusterSummary(nodes: 4, gpuAlloc: 20, gpuTotal: 32, gpuFree: 12, cpuAlloc: 84, cpuTotal: 192, cpuFree: 108, reservedNodes: 1),
                nodes: [
                    ClusterNode(name: "gpu01", state: "MIXED", cpuAlloc: 16, cpuTotal: 48, cpuFree: 32, gpuAlloc: 8, gpuTotal: 8, gpuFree: 0),
                    ClusterNode(name: "gpu02", state: "MIXED", cpuAlloc: 43, cpuTotal: 48, cpuFree: 5, gpuAlloc: 8, gpuTotal: 8, gpuFree: 0),
                    ClusterNode(name: "gpu03", state: "IDLE", cpuAlloc: 0, cpuTotal: 48, cpuFree: 48, gpuAlloc: 0, gpuTotal: 8, gpuFree: 8),
                    ClusterNode(name: "gpu04", state: "MIXED", cpuAlloc: 25, cpuTotal: 48, cpuFree: 23, gpuAlloc: 4, gpuTotal: 8, gpuFree: 4)
                ],
                excludedReservedNodes: ["gpu05"]
            )
        ),
        guardian: GuardianPayload(
            accounts: [
                "acct-c": GuardianAccount(
                    status: "expired",
                    attentionRequired: true,
                    attentionReason: "Authentication required",
                    ageWarning: false,
                    needsVisibleLogin: true
                )
            ],
            error: nil
        ),
        guardianError: nil,
        error: nil,
        returncode: 0
    )
}

private extension Optional where Wrapped == Int {
    var value: Int { self ?? 0 }
}

func resolvedAvailableCount(reported: Int?, allocated: Int?, total: Int?) -> Int {
    guard let total, total > 0 else {
        return max(0, reported ?? 0)
    }

    let reportedValue = min(max(0, reported ?? 0), total)
    guard let allocated else {
        return reportedValue
    }

    let derivedValue = total - min(max(0, allocated), total)
    guard let reported, (0...total).contains(reported) else {
        return derivedValue
    }

    // Missing free-counts decode as nil, while some older snapshots emitted a
    // contradictory zero. Prefer the allocation-derived value in either case.
    return reported == 0 && derivedValue > 0 ? derivedValue : reportedValue
}

private extension ClusterSummary {
    var availableGPUCount: Int {
        resolvedAvailableCount(reported: gpuFree, allocated: gpuAlloc, total: gpuTotal)
    }

    var availableCPUCount: Int {
        resolvedAvailableCount(reported: cpuFree, allocated: cpuAlloc, total: cpuTotal)
    }
}

private extension ClusterNode {
    var availableGPUCount: Int {
        resolvedAvailableCount(reported: gpuFree, allocated: gpuAlloc, total: gpuTotal)
    }
}

private extension HPCSnapshot {
    var accounts: [HPCAccount] { payload?.accounts ?? [] }
    var nodes: [ClusterNode] { payload?.clusterResources?.nodes ?? [] }
    var summary: ClusterSummary { payload?.clusterResources?.summary ?? ClusterSummary() }
    var attentionCount: Int {
        guardian?.accounts?.values.filter { $0.attentionRequired == true || $0.needsVisibleLogin == true }.count ?? 0
    }
    var hasFailure: Bool {
        error != nil || payload?.clusterResources?.error != nil || accounts.contains { $0.error != nil }
    }
}

private struct MetricLabel: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AvailabilityRing: View {
    let free: Int
    let total: Int
    let compact: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: compact ? 6 : 8)
            Circle()
                .trim(from: 0, to: total > 0 ? CGFloat(free) / CGFloat(total) : 0)
                .stroke(Color.green, style: StrokeStyle(lineWidth: compact ? 6 : 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: compact ? -2 : 0) {
                Text("\(free)")
                    .font(.system(size: compact ? 28 : 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("GPU 可用")
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("可用 GPU")
        .accessibilityValue("\(free) / \(total)")
    }
}

private struct HPCHeader: View {
    let snapshot: HPCSnapshot
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(snapshot.hasFailure ? .red : .green)
            Text("BJTU HPC")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            Spacer(minLength: 4)
            if snapshot.attentionCount > 0 {
                Label("\(snapshot.attentionCount)", systemImage: "key.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.purple)
                    .accessibilityLabel("\(snapshot.attentionCount) 个账号需要登录")
            } else {
                Image(systemName: snapshot.hasFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(snapshot.hasFailure ? .red : .green)
                    .accessibilityLabel(snapshot.hasFailure ? "状态异常" : "状态正常")
            }
        }
    }
}

private struct NodeRow: View {
    let node: ClusterNode

    private var free: Int { node.availableGPUCount }
    private var total: Int { node.gpuTotal.value }
    private var tint: Color { free >= 4 ? .green : (free > 0 ? .orange : .secondary) }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(node.name ?? "GPU")
                .font(.caption.weight(.medium))
            Spacer()
            Text("\(free) / \(total)")
                .font(.caption.monospacedDigit().weight(.semibold))
            Text("GPU")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AccountRow: View {
    let account: HPCAccount
    let guardian: GuardianAccount?

    private var accountName: String { account.name ?? "account" }
    private var running: Int { account.summary?.running.value ?? 0 }
    private var pending: Int { account.summary?.pending.value ?? 0 }
    private var needsLogin: Bool {
        guardian?.needsVisibleLogin == true || account.hasToken == false
    }
    private var hasFailure: Bool {
        if account.error != nil { return true }
        let status = guardian?.status?.lowercased() ?? ""
        return ["error", "expired", "invalid", "missing"].contains(status)
    }
    private var needsAttention: Bool {
        guardian?.attentionRequired == true || guardian?.ageWarning == true
    }
    private var statusLabel: String {
        if needsLogin { return "需登录" }
        if hasFailure { return "异常" }
        if guardian?.ageWarning == true { return "将过期" }
        if needsAttention { return "需关注" }
        if account.hasToken == true || guardian?.status?.lowercased() == "valid" { return "已登录" }
        return "未知"
    }
    private var statusTint: Color {
        if needsLogin { return .purple }
        if hasFailure { return .red }
        if needsAttention { return .orange }
        if statusLabel == "已登录" { return .green }
        return .secondary
    }
    private var statusIcon: String {
        if needsLogin { return "key.fill" }
        if hasFailure { return "exclamationmark.triangle.fill" }
        if needsAttention { return "clock.badge.exclamationmark.fill" }
        if statusLabel == "已登录" { return "checkmark.circle.fill" }
        return "questionmark.circle.fill"
    }
    private var loginURL: URL? {
        guard needsLogin else { return nil }
        var components = URLComponents()
        components.scheme = "bjtu-hpc-widget"
        components.host = "token"
        components.queryItems = [URLQueryItem(name: "account", value: accountName)]
        return components.url
    }

    private var identityLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundStyle(statusTint)
            Text(accountName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .underline(needsLogin, color: statusTint)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accountName)，\(statusLabel)")
    }

    @ViewBuilder
    private var accountIdentity: some View {
        if let loginURL {
            Link(destination: loginURL) {
                identityLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("登录 HPC 账号 \(accountName)")
        } else {
            identityLabel
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            accountIdentity
            Spacer(minLength: 4)
            if running == 0 && pending == 0 {
                Text("空闲")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 3) {
                    Text("\(running)")
                        .foregroundStyle(running > 0 ? .green : .secondary)
                    Text("运行")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2.monospacedDigit())
            }
            if pending > 0 {
                HStack(spacing: 3) {
                    Text("\(pending)").foregroundStyle(.orange)
                    Text("等待").foregroundStyle(.secondary)
                }
                .font(.caption2.monospacedDigit())
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct AccountStatusLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            item("OK", color: .green)
            item("LOGIN", color: .purple)
            item("WARN", color: .orange)
            item("ERR", color: .red)
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("账号状态：绿色正常，紫色需登录，橙色需关注，红色异常")
    }

    private func item(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
        }
    }
}

private struct AccountPagerHeader: View {
    let accountCount: Int
    let page: Int
    let pageSize: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 5) {
            Text("账号队列")
                .font(.caption.weight(.semibold))
            Text("\(accountCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 3)
            if pageCount > 1 {
                Text("\(page + 1)/\(pageCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(intent: ChangeHPCAccountPageIntent(direction: -1, pageSize: pageSize, pageCount: pageCount)) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("上一页账号")
                Button(intent: ChangeHPCAccountPageIntent(direction: 1, pageSize: pageSize, pageCount: pageCount)) {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("下一页账号")
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CompactNodeStrip: View {
    let nodes: [ClusterNode]

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(.secondary)
            ForEach(Array(nodes.prefix(4))) { node in
                HStack(spacing: 2) {
                    Circle()
                        .fill(node.availableGPUCount >= 4 ? Color.green : (node.availableGPUCount > 0 ? Color.orange : Color.secondary))
                        .frame(width: 5, height: 5)
                    Text("\(node.availableGPUCount)")
                        .monospacedDigit()
                }
                .accessibilityLabel("\(node.name ?? "GPU") 可用 \(node.availableGPUCount)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct HPCWidgetContainer: ViewModifier {
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

private struct HPCWidgetLink: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.widgetURL(URL(string: "bjtu-hpc-widget://dashboard"))
        } else {
            content
        }
    }
}

struct HPCWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HPCEntry
    var previewFamily: WidgetFamily? = nil

    private var snapshot: HPCSnapshot { entry.snapshot }
    private var freeGPU: Int { snapshot.summary.availableGPUCount }
    private var totalGPU: Int { snapshot.summary.gpuTotal.value }
    private var freeCPU: Int { snapshot.summary.availableCPUCount }
    private var totalCPU: Int { snapshot.summary.cpuTotal.value }
    private var runningTaskCount: Int {
        snapshot.accounts.reduce(0) { $0 + ($1.summary?.running.value ?? 0) }
    }
    private var maxRunningTaskCount: Int {
        snapshot.accounts.reduce(0) { total, account in
            let running = account.summary?.running.value ?? 0
            let openSlots = account.summary?.runSlotsOpen.value ?? 0
            return total + running + openSlots
        }
    }

    private var prioritizedAccounts: [HPCAccount] {
        snapshot.accounts.enumerated().sorted { lhs, rhs in
            let left = accountPriority(lhs.element)
            let right = accountPriority(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    private func accountPriority(_ account: HPCAccount) -> Int {
        let guardian = snapshot.guardian?.accounts?[account.name ?? ""]
        if guardian?.attentionRequired == true || guardian?.needsVisibleLogin == true || account.hasToken == false { return 0 }
        if account.summary?.pending.value ?? 0 > 0 { return 1 }
        if account.summary?.running.value ?? 0 > 0 { return 2 }
        return 3
    }

    private func accountPage(pageSize: Int, requestedPage: Int) -> (page: Int, pageCount: Int, accounts: [HPCAccount]) {
        let pageCount = HPCAccountPaging.pageCount(accountCount: prioritizedAccounts.count, pageSize: pageSize)
        let page = requestedPage % pageCount
        let start = min(page * pageSize, prioritizedAccounts.count)
        let end = min(start + pageSize, prioritizedAccounts.count)
        return (page, pageCount, Array(prioritizedAccounts[start..<end]))
    }

    var body: some View {
        Group {
            switch previewFamily ?? family {
            case .systemSmall: smallView
            case .systemLarge: largeView
            default: mediumView
            }
        }
        .modifier(HPCWidgetContainer(enabled: previewFamily == nil))
        .modifier(HPCWidgetLink(enabled: previewFamily == nil))
    }

    private var smallView: some View {
        VStack(spacing: 8) {
            HPCHeader(snapshot: snapshot, compact: true)
            AvailabilityRing(free: freeGPU, total: totalGPU, compact: true)
                .padding(8)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.primary.opacity(0.08), lineWidth: 0.5)
                }
            HStack {
                Label("\(freeCPU) / \(totalCPU)", systemImage: "cpu")
                Spacer()
                Label("\(snapshot.accounts.count)", systemImage: "person.2.fill")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var mediumView: some View {
        let accounts = accountPage(pageSize: 3, requestedPage: entry.mediumAccountPage)
        return HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HPCHeader(snapshot: snapshot, compact: false)
                AvailabilityRing(free: freeGPU, total: totalGPU, compact: true)
                    .frame(width: 76, height: 76)
            }
            .glassInset(padding: 10)
            VStack(alignment: .leading, spacing: 6) {
                AccountPagerHeader(
                    accountCount: prioritizedAccounts.count,
                    page: accounts.page,
                    pageSize: 3,
                    pageCount: accounts.pageCount
                )
                ForEach(accounts.accounts) { account in
                    AccountRow(account: account, guardian: snapshot.guardian?.accounts?[account.name ?? ""])
                }
                Spacer(minLength: 0)
                CompactNodeStrip(nodes: snapshot.nodes)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    private var largeView: some View {
        let accounts = accountPage(pageSize: 4, requestedPage: entry.largeAccountPage)
        return VStack(alignment: .leading, spacing: 14) {
            HPCHeader(snapshot: snapshot, compact: false)
            HStack(spacing: 16) {
                AvailabilityRing(free: freeGPU, total: totalGPU, compact: false)
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 12) {
                    MetricLabel(icon: "play.fill", value: "\(runningTaskCount) / \(maxRunningTaskCount)", label: "运行任务", tint: .blue)
                    MetricLabel(icon: "person.2.fill", value: "\(snapshot.accounts.count)", label: "已连接账号", tint: .indigo)
                    MetricLabel(icon: "clock.fill", value: "\(snapshot.accounts.reduce(0) { $0 + ($1.summary?.pending.value ?? 0) })", label: "等待任务", tint: .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassInset(padding: 11)
            Divider().opacity(0.45)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("节点可用性")
                        .font(.caption.weight(.semibold))
                    ForEach(Array(snapshot.nodes.prefix(4))) { node in
                        NodeRow(node: node)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    AccountPagerHeader(
                        accountCount: prioritizedAccounts.count,
                        page: accounts.page,
                        pageSize: 4,
                        pageCount: accounts.pageCount
                    )
                    ForEach(accounts.accounts) { account in
                        AccountRow(account: account, guardian: snapshot.guardian?.accounts?[account.name ?? ""])
                    }
                    AccountStatusLegend()
                        .padding(.top, 2)
                }
            }
        }
        .padding(17)
    }
}

#if WIDGET_EXTENSION
struct BJTUHPCWidget: Widget {
    let kind: String
    let displayName: String

    init() {
        kind = HPCWidgetKind.stable
        displayName = "BJTU HPC"
    }

    init(kind: String, displayName: String) {
        self.kind = kind
        self.displayName = displayName
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HPCProvider()) { entry in
            HPCWidgetView(entry: entry)
        }
        .configurationDisplayName(displayName)
        .description("查看 GPU、CPU、节点与账号队列的实时状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct BJTUHPCWidgetBundle: WidgetBundle {
    var body: some Widget {
        BJTUHPCWidget(kind: HPCWidgetKind.stable, displayName: "BJTU HPC")
        BJTUHPCWidget(kind: HPCWidgetKind.transitional, displayName: "BJTU HPC（兼容）")
    }
}
#endif
