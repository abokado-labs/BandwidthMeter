import AppKit
import SwiftUI

struct AppDetailView: View {
    let identity: AppIdentity
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    explanationCard
                    usageCard
                    identityCard
                    processCard
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: headerIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(headerColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(identity.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if identity.isUnknown {
                Button {
                    openGoogleSearch()
                } label: {
                    Label("Search", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .help("Search Google in Safari")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitle(title: "What Is It?")
            Text(identity.explanation)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if identity.isUnknown {
                Text("Use Search to open a pre-filled Google search in Safari for the process name and app name.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitle(title: "Bandwidth")
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    DetailMetric(title: "Down", value: ByteFormat.speed(identity.app.downloadBps, units: settings.units, scale: settings.unitScale, roundsScaledValues: settings.roundScaledMeasurements), color: .blue)
                    DetailMetric(title: "Up", value: ByteFormat.speed(identity.app.uploadBps, units: settings.units, scale: settings.unitScale, roundsScaledValues: settings.roundScaledMeasurements), color: .green)
                }
                GridRow {
                    DetailMetric(title: "24h Down", value: ByteFormat.bytes(identity.app.download24h, roundsScaledValues: settings.roundScaledMeasurements), color: .orange)
                    DetailMetric(title: "24h Up", value: ByteFormat.bytes(identity.app.upload24h, roundsScaledValues: settings.roundScaledMeasurements), color: .purple)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitle(title: "Identity")
            InfoLine(title: "Bundle ID", value: identity.bundleIdentifier ?? "Not found")
            InfoLine(title: "Signed By", value: identity.signingName ?? identity.signingIdentifier ?? "Not found")
            InfoLine(title: "Team", value: identity.teamIdentifier ?? "Not found")
            InfoLine(title: "Path", value: identity.bundlePath ?? "No app bundle matched")
            if let bundlePath = identity.bundlePath {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bundlePath)])
                } label: {
                    Label("Reveal in Finder", systemImage: "finder")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitle(title: "Processes")
            InfoLine(title: "PID", value: identity.app.pid > 0 ? String(identity.app.pid) : "Not available")
            ForEach(identity.rawProcesses, id: \.self) { process in
                Text(process)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var headerIcon: String {
        switch identity.confidence {
        case .knownSystemService:
            return "gearshape.2"
        case .resolvedApp:
            return "app.badge"
        case .unknown:
            return "questionmark.app"
        }
    }

    private var headerColor: Color {
        switch identity.confidence {
        case .knownSystemService:
            return .blue
        case .resolvedApp:
            return .green
        case .unknown:
            return .orange
        }
    }

    private func openGoogleSearch() {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: identity.searchQuery)]
        guard let url = components?.url else { return }

        let safariURL = URL(fileURLWithPath: "/Applications/Safari.app")
        if FileManager.default.fileExists(atPath: safariURL.path) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: configuration)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct DetailSectionTitle: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct InfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
