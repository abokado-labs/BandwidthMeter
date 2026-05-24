import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: BandwidthModel
    @State private var isConfirmingClearUsage = false

    var body: some View {
        TabView {
            displayTab
                .tabItem { Label("Display", systemImage: "menubar.rectangle") }
            monitoringTab
                .tabItem { Label("Monitoring", systemImage: "dot.radiowaves.left.and.right") }
            speedTestTab
                .tabItem { Label("Speed Test", systemImage: "speedometer") }
            updatesPrivacyTab
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(18)
        .confirmationDialog(
            "Clear all locally stored usage history?",
            isPresented: $isConfirmingClearUsage
        ) {
            Button("Clear Usage History", role: .destructive) {
                model.clearUsageHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes observed app bandwidth history and 24-hour totals. Live measurements will continue.")
        }
    }

    private var displayTab: some View {
        Form {
            Picker("Menu Bar Metric", selection: binding(\.menuMetric)) {
                ForEach(MenuMetric.allCases) { metric in
                    Text(metric.label).tag(metric)
                }
            }
            Picker("Menu Bar Layout", selection: binding(\.menuLayout)) {
                ForEach(MenuLayout.allCases) { layout in
                    Text(layout.label).tag(layout)
                }
            }
            Picker("Units", selection: binding(\.units)) {
                ForEach(UnitPreference.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            Picker("Scale", selection: binding(\.unitScale)) {
                ForEach(UnitScale.allCases) { scale in
                    Text(scale.label).tag(scale)
                }
            }
            Toggle("Round KB/MB values", isOn: binding(\.roundScaledMeasurements))
            HStack {
                Text("Font Size")
                Slider(value: binding(\.menuFontSize), in: 4...16, step: 1)
                Text("\(Int(model.settings.menuFontSize))")
                    .frame(width: 24, alignment: .trailing)
            }
            Toggle("Show icon in menu bar", isOn: binding(\.showIcon))
        }
        .formStyle(.grouped)
    }

    private var monitoringTab: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: binding(\.launchAtLogin))
                LabeledContent("Status", value: model.launchAtLoginStatus)
                if let message = model.launchAtLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Sampling") {
                Picker("Sampling Interval", selection: binding(\.samplingIntervalSeconds)) {
                    ForEach(SamplingInterval.allCases) { interval in
                        Text(interval.label).tag(interval.rawValue)
                    }
                }
                Picker("Rate Smoothing", selection: binding(\.rateSmoothingSeconds)) {
                    ForEach(RateSmoothing.allCases) { smoothing in
                        Text(smoothing.label).tag(smoothing.rawValue)
                    }
                }
                Text("Smoothing averages the live menu bar and dashboard rates over the selected window. Stored usage totals still use observed samples.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("App List") {
                Toggle("Group helper processes into parent apps", isOn: binding(\.groupApps))
                Toggle("Hide System Services in app list", isOn: binding(\.hideSystemServices))
                Text("Hiding System Services only changes the dashboard list. Local totals are still retained so usage history remains accurate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Network Identity") {
                LabeledContent("Wi-Fi Name", value: model.wiFiNamePermissionStatus)
                Button {
                    model.requestWiFiNamePermission()
                } label: {
                    Label("Access Wi-Fi Name via Location Permission", systemImage: "location")
                }
                Text("macOS treats Wi-Fi network names as location-sensitive. Bandwidth Meter only uses this permission to show the current Wi-Fi name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Picker("Retain History", selection: binding(\.retentionDays)) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                Button(role: .destructive) {
                    isConfirmingClearUsage = true
                } label: {
                    Label("Clear Usage History", systemImage: "trash")
                }
                Text("24h usage is calculated from traffic observed while Bandwidth Meter is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var speedTestTab: some View {
        Form {
            LabeledContent("Provider", value: "Built-in macOS networkQuality")
            Toggle("Run speed tests automatically", isOn: binding(\.automaticSpeedTestsEnabled))
            Picker("Run Every", selection: binding(\.speedTestIntervalHours)) {
                Text("1 hour").tag(1)
                Text("3 hours").tag(3)
                Text("6 hours").tag(6)
                Text("12 hours").tag(12)
                Text("24 hours").tag(24)
            }
            .disabled(!model.settings.automaticSpeedTestsEnabled)
            HStack {
                Button {
                    model.runSpeedTest()
                } label: {
                    Label("Run Speed Test", systemImage: "play.fill")
                }
                .disabled(model.isRunningSpeedTest)

                Button(role: .destructive) {
                    model.clearSpeedTestHistory()
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
            }
            if model.isRunningSpeedTest {
                ProgressView("Running speed test...")
            }
            if let message = model.speedTestMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Speed tests transfer data over the internet. Bandwidth Meter uses Apple's built-in networkQuality command, so no separate CLI installation is required.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var updatesPrivacyTab: some View {
        Form {
            Section("Updates") {
                Button {
                    NSApp.sendAction(#selector(AppDelegate.checkForUpdates(_:)), to: nil, from: nil)
                } label: {
                    Label("Check for Updates", systemImage: "arrow.down.circle")
                }
                LabeledContent("Sparkle", value: AppDelegate.sparkleConfigurationStatus)
                Text("Bandwidth Meter uses Sparkle to check for signed updates from Abokado Labs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        Form {
            Section("Bandwidth Meter") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                Text("A small macOS menu bar app for understanding what your internet is actually doing. Live up/down rates, per-app traffic, Wi-Fi and public IP details, outage detection, and speed tests. Local-first, no telemetry.")
                    .foregroundStyle(.secondary)
            }

            Section("Abokado Labs") {
                Text("Abokado Labs is a small one-person dev shop building considered software for everyday problems. The apps are built for real daily use: quiet, practical, local-first where possible, and improved through customer feedback.")
                    .foregroundStyle(.secondary)
                Button {
                    NSWorkspace.shared.open(URL(string: "https://abokadolabs.com")!)
                } label: {
                    Label("Website and Support", systemImage: "safari")
                }
            }

            Section("Privacy") {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://abokadolabs.com/bandwidth-meter/privacy")!)
                } label: {
                    Label("Privacy Policy", systemImage: "lock.doc")
                }
                Text("No packet contents are read.")
                Text("No traffic is routed, filtered, decrypted, or uploaded.")
                Text("Usage and speed-test history are stored locally.")
                Text("Wi-Fi name access uses macOS Location Services because macOS treats network names as location-sensitive.")
                Text("Public IP location lookups contact ipapi.co, and speed tests use Apple's built-in networkQuality command.")
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                var settings = model.settings
                settings[keyPath: keyPath] = newValue
                model.settings = settings
            }
        )
    }
}
