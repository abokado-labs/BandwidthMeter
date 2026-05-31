import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: BandwidthModel
    @State private var appSortColumn: AppSortColumn = .app
    @State private var appSortAscending = true
    @State private var activityWindow: AppActivityWindow = .oneHour
    @State private var displayedApps: [AppBandwidth] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    summary
                    appList
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .frame(width: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: refreshDisplayedApps)
        .onChange(of: activityWindow) { _, _ in refreshDisplayedApps() }
        .onChange(of: model.apps) { _, _ in refreshDisplayedApps() }
        .onChange(of: model.download24h) { _, _ in refreshDisplayedApps() }
        .onChange(of: model.upload24h) { _, _ in refreshDisplayedApps() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "speedometer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bandwidth Meter")
                    .font(.headline)
                Text(model.lastSampleStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isInternetAvailable ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(model.lastSampleStatus)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSApp.sendAction(#selector(AppDelegate.openSettings(_:)), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Live Measurements")
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    CompactMetric(title: "Down", value: ByteFormat.speed(model.totalDownloadBps, units: model.settings.units, scale: model.settings.unitScale, roundsScaledValues: model.settings.roundScaledMeasurements), icon: "arrow.down", color: .blue)
                    CompactMetric(title: "Up", value: ByteFormat.speed(model.totalUploadBps, units: model.settings.units, scale: model.settings.unitScale, roundsScaledValues: model.settings.roundScaledMeasurements), icon: "arrow.up", color: .green)
                }
                GridRow {
                    CompactMetric(title: "24h Down", value: ByteFormat.bytes(model.download24h, roundsScaledValues: model.settings.roundScaledMeasurements), icon: "clock.arrow.circlepath", color: .orange)
                    CompactMetric(title: "24h Up", value: ByteFormat.bytes(model.upload24h, roundsScaledValues: model.settings.roundScaledMeasurements), icon: "clock", color: .purple)
                }
                ForEach(model.networkConnections.isEmpty ? [NetworkIdentity.Connection(id: "unavailable", type: model.activeInterface, name: model.activeInterface, localIP: model.localIPAddress, signal: "N/A", symbolName: "network")] : model.networkConnections) { connection in
                    GridRow {
                        InterfaceMetric(connection: connection, publicIP: model.publicIPAddress, publicLocation: model.publicIPLocation)
                            .gridCellColumns(2)
                    }
                }
                GridRow {
                    CompactMetric(title: "Connection", value: model.internetStatusText, icon: model.isInternetAvailable ? "checkmark.circle" : "exclamationmark.triangle", color: model.isInternetAvailable ? .green : .red)
                    CompactMetric(title: "Last Speed Test", value: model.latestSpeedTestSummary, icon: "speedometer", color: .indigo)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                SectionTitle(title: "Apps")
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                Picker("Window", selection: $activityWindow) {
                    ForEach(AppActivityWindow.allCases) { window in
                        Text(window.label).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 118)
            }
            .padding(.trailing, 10)
            if sortedApps.isEmpty {
                ContentUnavailableView("No active bandwidth", systemImage: "antenna.radiowaves.left.and.right", description: Text("Traffic appears here after two samples."))
                    .frame(height: 100)
            } else {
                VStack(spacing: 0) {
                    AppTableHeader(activityWindow: activityWindow, sortColumn: $appSortColumn, sortAscending: $appSortAscending)
                    ForEach(sortedApps) { app in
                        AppBandwidthRow(app: app, units: model.settings.units, scale: model.settings.unitScale, roundsScaledValues: model.settings.roundScaledMeasurements)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var sortedApps: [AppBandwidth] {
        let sorted = displayedApps.sorted { lhs, rhs in
            switch appSortColumn {
            case .app:
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            case .download:
                lhs.downloadBps < rhs.downloadBps
            case .upload:
                lhs.uploadBps < rhs.uploadBps
            case .download24h:
                lhs.download24h < rhs.download24h
            case .upload24h:
                lhs.upload24h < rhs.upload24h
            }
        }
        return appSortAscending ? sorted : sorted.reversed()
    }

    private func refreshDisplayedApps() {
        displayedApps = model.appActivity(since: Date().addingTimeInterval(-activityWindow.interval))
    }

    private var speedTestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Speed Test")
                    .font(.headline)
                Spacer()
                Button {
                    model.runSpeedTest()
                } label: {
                    if model.isRunningSpeedTest {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Run", systemImage: "play.fill")
                    }
                }
                .disabled(model.isRunningSpeedTest)
            }

            if let last = model.speedTests.first {
                SpeedResultLine(title: "Last", detail: "\(last.downloadMbps.formatted(.number.precision(.fractionLength(1)))) down / \(last.uploadMbps.formatted(.number.precision(.fractionLength(1)))) up Mbps")
                SpeedResultLine(title: "Latency", detail: "\(last.latencyMs.formatted(.number.precision(.fractionLength(1)))) ms, jitter \(last.jitterMs.formatted(.number.precision(.fractionLength(1)))) ms")
            } else {
                SpeedResultLine(title: "Last", detail: model.speedTestMessage ?? "No completed tests")
            }

            if let best = model.bestCapableResult {
                SpeedResultLine(title: "Capable", detail: "\(best.downloadMbps.formatted(.number.precision(.fractionLength(1)))) down / \(best.uploadMbps.formatted(.number.precision(.fractionLength(1)))) up Mbps")
            }
            if let average = model.averageRecentResult {
                SpeedResultLine(title: "Average", detail: "\(average.download.formatted(.number.precision(.fractionLength(1)))) down / \(average.upload.formatted(.number.precision(.fractionLength(1)))) up Mbps")
            }
            if let message = model.speedTestMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private enum AppSortColumn: String, CaseIterable {
    case app
    case download
    case upload
    case download24h
    case upload24h
}

private enum AppActivityWindow: String, CaseIterable, Identifiable {
    case oneHour
    case twelveHours
    case twentyFourHours

    var id: String { rawValue }
    var interval: TimeInterval {
        switch self {
        case .oneHour:
            return 60 * 60
        case .twelveHours:
            return 12 * 60 * 60
        case .twentyFourHours:
            return 24 * 60 * 60
        }
    }
    var label: String {
        switch self {
        case .oneHour:
            return "1h"
        case .twelveHours:
            return "12h"
        case .twentyFourHours:
            return "24h"
        }
    }
    var columnPrefix: String {
        switch self {
        case .oneHour:
            return "1h"
        case .twelveHours:
            return "12h"
        case .twentyFourHours:
            return "24h"
        }
    }
}

private struct SectionTitle: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, 10)
    }
}

private struct CompactMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(color.opacity(0.95))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct InterfaceMetric: View {
    let connection: NetworkIdentity.Connection
    let publicIP: String
    let publicLocation: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: connection.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(Color.cyan.opacity(0.95))
            VStack(alignment: .leading, spacing: 4) {
                InfoChip(title: connection.type == "Wi-Fi" ? "Wi-Fi" : "Network", value: connection.name)
                InfoChip(title: "Signal", value: connection.signal)
            }
            .frame(width: 150, alignment: .leading)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                InfoChip(title: "Local", value: connection.localIP, alignment: .trailing, frameAlignment: .trailing)
                InfoChip(title: "Public", value: publicIP, secondaryValue: publicLocation, alignment: .trailing, frameAlignment: .trailing)
            }
            .frame(width: 190, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(Color.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.cyan.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct InfoChip: View {
    let title: String
    let value: String
    var secondaryValue: String?
    var alignment: HorizontalAlignment = .leading
    var frameAlignment: Alignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.65)
            if let secondaryValue {
                Text(secondaryValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}

private struct AppTableHeader: View {
    let activityWindow: AppActivityWindow
    @Binding var sortColumn: AppSortColumn
    @Binding var sortAscending: Bool

    var body: some View {
        HStack(spacing: 6) {
            header("App Name", .app, alignment: .leading)
                .frame(width: 112, alignment: .leading)
            header("Down", .download)
                .frame(width: 56, alignment: .trailing)
            header("Up", .upload)
                .frame(width: 56, alignment: .trailing)
            header("\(activityWindow.columnPrefix) Down", .download24h)
                .frame(width: 64, alignment: .trailing)
            header("\(activityWindow.columnPrefix) Up", .upload24h)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.bottom, 5)
    }

    private func header(_ title: String, _ column: AppSortColumn, alignment: Alignment = .trailing) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = column == .app
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(sortColumn == column ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .buttonStyle(.plain)
    }
}

private struct AppBandwidthRow: View {
    let app: AppBandwidth
    let units: UnitPreference
    let scale: UnitScale
    let roundsScaledValues: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openAppDetail, object: app)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(app.isActive ? .primary : Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if app.processName != app.displayName {
                        Text(app.processName)
                            .font(.caption2)
                            .foregroundStyle(app.isActive ? .secondary : Color(nsColor: .tertiaryLabelColor))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(width: 112, alignment: .leading)
                tableValue(ByteFormat.speed(app.downloadBps, units: units, scale: scale, roundsScaledValues: roundsScaledValues), color: .blue)
                    .frame(width: 56, alignment: .trailing)
                tableValue(ByteFormat.speed(app.uploadBps, units: units, scale: scale, roundsScaledValues: roundsScaledValues), color: .green)
                    .frame(width: 56, alignment: .trailing)
                tableValue(ByteFormat.bytes(app.download24h, roundsScaledValues: roundsScaledValues), color: .orange)
                    .frame(width: 64, alignment: .trailing)
                tableValue(ByteFormat.bytes(app.upload24h, roundsScaledValues: roundsScaledValues), color: .purple)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, app.processName == app.displayName ? 4 : 5)
            .contentShape(Rectangle())
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Show app details")
    }

    private var rowBackground: Color {
        if isHovered {
            return Color(nsColor: .controlAccentColor).opacity(0.13)
        }
        if app.isActive {
            return Color.white.opacity(0.02)
        }
        return Color.clear
    }

    private func tableValue(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(app.isActive ? color : Color(nsColor: .tertiaryLabelColor))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }
}

private struct SpeedResultLine: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}
