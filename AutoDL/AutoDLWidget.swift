// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import WidgetKit

private enum AutoDLWidgetKind {
    static let stable = "AutoDLNativeWidget"
}

struct AutoDLSnapshot: Decodable {
    var version: Int?
    var writtenAt: String?
    var instances: [AutoDLInstance]
    var summary: AutoDLSummary
    var error: String?
}

struct AutoDLInstance: Decodable, Identifiable {
    var id: String
    var label: String
    var status: String
    var mode: String
    var latencyMs: Int?
    var uptimeSeconds: Int?
    var errorCode: String?
    var gpus: [AutoDLGPU]
    var storage: [AutoDLStorage]
    var system: AutoDLSystem?
}

struct AutoDLGPU: Decodable, Identifiable {
    var index: Int
    var name: String
    var utilizationPct: Int
    var memoryUsedMib: Int
    var memoryTotalMib: Int
    var temperatureC: Int
    var powerW: Double?
    var powerLimitW: Double?
    var processCount: Int
    var busy: Bool
    var id: Int { index }
}

struct AutoDLStorage: Decodable, Identifiable {
    var kind: String
    var sizeBytes: Int64
    var usedBytes: Int64
    var availableBytes: Int64
    var usedPct: Double
    var id: String { kind }
}

struct AutoDLSystem: Decodable {
    var memoryUsedMib: Int?
    var memoryTotalMib: Int?
    var load1m: Double?
    var cpuCount: Int?
}

struct AutoDLSummary: Decodable {
    var totalInstances: Int
    var onlineInstances: Int
    var gpuInstances: Int
    var totalGpus: Int
    var busyGpus: Int
    var averageUtilizationPct: Int
    var memoryUsedMib: Int
    var memoryTotalMib: Int
    var activeProcesses: Int
    var maxTemperatureC: Int
}

struct AutoDLEntry: TimelineEntry {
    let date: Date
    let snapshot: AutoDLSnapshot
}

struct AutoDLProvider: TimelineProvider {
    func placeholder(in context: Context) -> AutoDLEntry {
        AutoDLEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (AutoDLEntry) -> Void) {
        completion(AutoDLEntry(date: .now, snapshot: loadSnapshot() ?? (context.isPreview ? .preview : .unconfigured)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AutoDLEntry>) -> Void) {
        let snapshot = loadSnapshot() ?? .unconfigured
        let entry = AutoDLEntry(date: .now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60))))
    }

    private func loadSnapshot() -> AutoDLSnapshot? {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoDLNativeWidget/snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(AutoDLSnapshot.self, from: data)
    }
}

extension AutoDLSnapshot {
    static let preview: AutoDLSnapshot = {
        let gpus = [
            AutoDLGPU(index: 0, name: "NVIDIA RTX 4090", utilizationPct: 92, memoryUsedMib: 19_860, memoryTotalMib: 24_564, temperatureC: 67, powerW: 392, powerLimitW: 450, processCount: 1, busy: true),
            AutoDLGPU(index: 1, name: "NVIDIA RTX 4090", utilizationPct: 71, memoryUsedMib: 14_320, memoryTotalMib: 24_564, temperatureC: 61, powerW: 318, powerLimitW: 450, processCount: 1, busy: true)
        ]
        let instance = AutoDLInstance(
            id: "primary",
            label: "AutoDL 主机",
            status: "online",
            mode: "gpu",
            latencyMs: 86,
            uptimeSeconds: 48_200,
            errorCode: nil,
            gpus: gpus,
            storage: [
                AutoDLStorage(kind: "local", sizeBytes: 536_870_912_000, usedBytes: 257_698_037_760, availableBytes: 279_172_874_240, usedPct: 48),
                AutoDLStorage(kind: "persistent", sizeBytes: 107_374_182_400, usedBytes: 62_770_257_920, availableBytes: 44_603_924_480, usedPct: 58.5)
            ],
            system: AutoDLSystem(memoryUsedMib: 21_820, memoryTotalMib: 65_536, load1m: 4.2, cpuCount: 16)
        )
        return AutoDLSnapshot(
            version: 1,
            writtenAt: ISO8601DateFormatter().string(from: .now),
            instances: [instance],
            summary: AutoDLSummary(totalInstances: 1, onlineInstances: 1, gpuInstances: 1, totalGpus: 2, busyGpus: 2, averageUtilizationPct: 82, memoryUsedMib: 34_180, memoryTotalMib: 49_128, activeProcesses: 2, maxTemperatureC: 67),
            error: nil
        )
    }()

    static let unconfigured = AutoDLSnapshot(
        version: 1,
        writtenAt: nil,
        instances: [],
        summary: AutoDLSummary(totalInstances: 0, onlineInstances: 0, gpuInstances: 0, totalGpus: 0, busyGpus: 0, averageUtilizationPct: 0, memoryUsedMib: 0, memoryTotalMib: 0, activeProcesses: 0, maxTemperatureC: 0),
        error: "not_configured"
    )
}

private struct GPUDisplay: Identifiable {
    let instanceID: String
    let instanceLabel: String
    let gpu: AutoDLGPU
    var id: String { "\(instanceID)-\(gpu.index)" }
}

private extension AutoDLSnapshot {
    var flattenedGPUs: [GPUDisplay] {
        instances.flatMap { instance in
            instance.gpus.map { GPUDisplay(instanceID: instance.id, instanceLabel: instance.label, gpu: $0) }
        }
    }

    var isStale: Bool {
        guard let writtenAt, let date = ISO8601DateFormatter().date(from: writtenAt) else { return true }
        return Date().timeIntervalSince(date) > 180
    }

    var hasFailure: Bool {
        error != nil || instances.contains { $0.status != "online" }
    }
}

private func gpuTint(_ gpu: AutoDLGPU) -> Color {
    if gpu.busy { return .green }
    if gpu.utilizationPct > 0 { return .blue }
    return .orange
}

private func memoryText(used: Int, total: Int) -> String {
    guard total > 0 else { return "—" }
    let usedGiB = Double(used) / 1024
    let totalGiB = Double(total) / 1024
    return String(format: "%.1f / %.0fG", usedGiB, totalGiB)
}

private func storageText(_ bytes: Int64) -> String {
    let gib = Double(bytes) / 1_073_741_824
    if gib >= 1_000 { return String(format: "%.1fT", gib / 1024) }
    return String(format: "%.0fG", gib)
}

private struct AutoDLHeader: View {
    let snapshot: AutoDLSnapshot
    let compact: Bool

    private var tint: Color {
        if snapshot.hasFailure { return .red }
        if snapshot.isStale { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(tint)
            Text("AutoDL")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            Spacer(minLength: 4)
            if snapshot.isStale && !snapshot.instances.isEmpty {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("状态可能已过期")
            } else {
                HStack(spacing: 3) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Text("\(snapshot.summary.onlineInstances)/\(snapshot.summary.totalInstances)")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct UtilizationRing: View {
    let utilization: Int
    let compact: Bool

    private var tint: Color {
        utilization >= 10 ? .green : .orange
    }

    var body: some View {
        ZStack {
            Circle().stroke(.tertiary, lineWidth: compact ? 6 : 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, utilization))) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: compact ? 6 : 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(utilization)%")
                    .font(.system(size: compact ? 25 : 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("GPU 使用")
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("平均 GPU 使用率 \(utilization)%")
    }
}

private struct AutoDLMetric: View {
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
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MemoryBar: View {
    let used: Int
    let total: Int

    private var fraction: CGFloat {
        total > 0 ? CGFloat(min(used, total)) / CGFloat(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("显存", systemImage: "memorychip.fill")
                Spacer()
                Text(memoryText(used: used, total: total)).monospacedDigit()
            }
            .font(.caption2)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.tertiary)
                    Capsule().fill(Color.blue).frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct GPURow: View {
    let item: GPUDisplay
    let compact: Bool

    private var gpu: AutoDLGPU { item.gpu }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Circle().fill(gpuTint(gpu)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text("GPU \(gpu.index)")
                    .font(.caption.weight(.medium))
                if !compact {
                    Text(gpu.name.replacingOccurrences(of: "NVIDIA ", with: ""))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 3)
            Text("\(gpu.utilizationPct)%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(gpuTint(gpu))
                .frame(width: 32, alignment: .trailing)
            Text(memoryText(used: gpu.memoryUsedMib, total: gpu.memoryTotalMib))
                .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: compact ? 58 : 68, alignment: .trailing)
            if !compact {
                Text("\(gpu.temperatureC)°")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(gpu.temperatureC >= 80 ? .red : .secondary)
                    .frame(width: 26, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.instanceLabel) GPU \(gpu.index)，使用率 \(gpu.utilizationPct)%，显存 \(memoryText(used: gpu.memoryUsedMib, total: gpu.memoryTotalMib))")
    }
}

private struct InstanceRow: View {
    let instance: AutoDLInstance
    var compact: Bool = false

    private var state: (String, Color, String) {
        if instance.status != "online" { return ("连接失败", .red, "wifi.exclamationmark") }
        if instance.mode == "cpu_only" { return ("无卡模式", .indigo, "cpu") }
        if instance.gpus.contains(where: \.busy) { return ("运行中", .green, "play.circle.fill") }
        return ("GPU 空闲", .orange, "pause.circle.fill")
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: state.2).foregroundStyle(state.1).frame(width: 14)
            Text(instance.label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if !compact {
                Text("\(instance.gpus.filter(\.busy).count)/\(instance.gpus.count) GPU")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(state.0)
                .font(.caption2.weight(.medium))
                .foregroundStyle(state.1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StorageRow: View {
    let disk: AutoDLStorage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: disk.kind == "persistent" ? "externaldrive.fill" : "internaldrive.fill")
                .foregroundStyle(.secondary)
            Text(disk.kind == "persistent" ? "文件存储" : "实例磁盘")
            Spacer()
            Text("\(Int(disk.usedPct.rounded()))%")
                .monospacedDigit()
                .foregroundStyle(disk.usedPct >= 90 ? .red : (disk.usedPct >= 75 ? .orange : .secondary))
            Text("余 \(storageText(disk.availableBytes))")
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
    }
}

private struct AutoDLWidgetContainer: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.containerBackground(for: .widget) { Rectangle().fill(.regularMaterial) }
        } else {
            content
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

private struct AutoDLGlassInset: ViewModifier {
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
    func autoDLGlassInset(padding: CGFloat = 11) -> some View {
        modifier(AutoDLGlassInset(padding: padding))
    }
}

struct AutoDLWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AutoDLEntry
    var previewFamily: WidgetFamily? = nil

    private var snapshot: AutoDLSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if snapshot.instances.isEmpty {
                emptyView
            } else {
                switch previewFamily ?? family {
                case .systemSmall: smallView
                case .systemLarge: largeView
                default: mediumView
                }
            }
        }
        .modifier(AutoDLWidgetContainer(enabled: previewFamily == nil))
        .widgetURL(previewFamily == nil ? URL(string: "autodl-widget://refresh") : nil)
    }

    private var emptyView: some View {
        VStack(spacing: 9) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            Text("等待 SSH 配置").font(.headline)
            Text("配置连接后显示 AutoDL GPU 状态")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
    }

    private var smallView: some View {
        VStack(spacing: 8) {
            AutoDLHeader(snapshot: snapshot, compact: true)
            UtilizationRing(utilization: snapshot.summary.averageUtilizationPct, compact: true)
                .padding(8)
                .background(.thinMaterial, in: Circle())
                .overlay { Circle().stroke(.primary.opacity(0.08), lineWidth: 0.5) }
            HStack {
                Label("\(snapshot.summary.busyGpus)/\(snapshot.summary.totalGpus)", systemImage: "memorychip.fill")
                Spacer()
                Text(memoryText(used: snapshot.summary.memoryUsedMib, total: snapshot.summary.memoryTotalMib))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var mediumView: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 8) {
                AutoDLHeader(snapshot: snapshot, compact: false)
                UtilizationRing(utilization: snapshot.summary.averageUtilizationPct, compact: true)
                    .frame(width: 72, height: 72)
                MemoryBar(used: snapshot.summary.memoryUsedMib, total: snapshot.summary.memoryTotalMib)
            }
            .frame(width: 126, alignment: .leading)
            .autoDLGlassInset(padding: 10)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("GPU 状态").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(snapshot.summary.busyGpus)/\(snapshot.summary.totalGpus) 运行")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if snapshot.flattenedGPUs.isEmpty {
                    Text("实例在线 · 当前为无卡模式")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                } else {
                    ForEach(Array(snapshot.flattenedGPUs.prefix(3))) { item in
                        GPURow(item: item, compact: true)
                    }
                }
                Spacer(minLength: 0)
                if let instance = snapshot.instances.first {
                    InstanceRow(instance: instance, compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            AutoDLHeader(snapshot: snapshot, compact: false)
            HStack(spacing: 16) {
                UtilizationRing(utilization: snapshot.summary.averageUtilizationPct, compact: false)
                    .frame(width: 94, height: 94)
                VStack(alignment: .leading, spacing: 10) {
                    AutoDLMetric(icon: "memorychip.fill", value: "\(snapshot.summary.busyGpus) / \(snapshot.summary.totalGpus)", label: "忙碌 GPU", tint: .green)
                    AutoDLMetric(icon: "square.stack.3d.up.fill", value: memoryText(used: snapshot.summary.memoryUsedMib, total: snapshot.summary.memoryTotalMib), label: "GPU 显存", tint: .blue)
                    AutoDLMetric(icon: "thermometer.medium", value: "\(snapshot.summary.maxTemperatureC)°C", label: "最高温度", tint: snapshot.summary.maxTemperatureC >= 80 ? .red : .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .autoDLGlassInset(padding: 11)
            Divider().opacity(0.45)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("GPU 状态").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(snapshot.summary.activeProcesses) 个计算进程")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if snapshot.flattenedGPUs.isEmpty {
                    Text("当前实例在线，但没有可见 GPU").font(.caption).foregroundStyle(.indigo)
                } else {
                    ForEach(Array(snapshot.flattenedGPUs.prefix(4))) { item in
                        GPURow(item: item, compact: false)
                    }
                }
            }
            Divider().opacity(0.35)
            VStack(spacing: 6) {
                ForEach(Array(snapshot.instances.prefix(3))) { instance in
                    InstanceRow(instance: instance)
                }
                if let disk = snapshot.instances.first?.storage.first(where: { $0.kind == "persistent" })
                    ?? snapshot.instances.first?.storage.first {
                    StorageRow(disk: disk)
                }
            }
        }
        .padding(17)
    }
}

#if WIDGET_EXTENSION
struct AutoDLWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AutoDLWidgetKind.stable, provider: AutoDLProvider()) { entry in
            AutoDLWidgetView(entry: entry)
        }
        .configurationDisplayName("AutoDL GPU")
        .description("查看 AutoDL 实例、GPU 使用率、显存、温度与存储状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct AutoDLWidgetBundle: WidgetBundle {
    var body: some Widget { AutoDLWidget() }
}
#endif
