import Combine
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class BandwidthModel: ObservableObject {
    @Published var settings = AppSettings.load() {
        didSet {
            settings.save()
            if !isSyncingLaunchAtLoginSetting && oldValue.launchAtLogin != settings.launchAtLogin {
                configureLaunchAtLogin(settings.launchAtLogin)
            }
            startAutomaticSpeedTests()
            trimRateSamples()
            applySmoothedRates()
            onStatusChange?()
        }
    }
    @Published private(set) var apps: [AppBandwidth] = []
    @Published private(set) var totalDownloadBps: Double = 0
    @Published private(set) var totalUploadBps: Double = 0
    @Published private(set) var download24h: Int64 = 0
    @Published private(set) var upload24h: Int64 = 0
    @Published private(set) var activeInterface = "External"
    @Published private(set) var lastSampleStatus = "Starting"
    @Published private(set) var speedTests: [SpeedTestResult] = []
    @Published private(set) var isRunningSpeedTest = false
    @Published private(set) var speedTestMessage: String?
    @Published private(set) var isInternetAvailable = true
    @Published private(set) var internetStatusText = "Internet online"
    @Published private(set) var localIPAddress = "Checking"
    @Published private(set) var publicIPAddress = "Checking"
    @Published private(set) var publicIPLocation = "Checking"
    @Published private(set) var wifiNetworkName = "Checking"
    @Published private(set) var wifiSignal = "Checking"
    @Published private(set) var networkConnections: [NetworkIdentity.Connection] = []
    @Published private(set) var wiFiNamePermissionStatus = LocationPermissionManager.shared.statusText
    @Published private(set) var wiFiNamePermissionDiagnostic = LocationPermissionManager.shared.diagnosticsText
    @Published private(set) var launchAtLoginStatus = "Off"
    @Published private(set) var launchAtLoginMessage: String?

    var onStatusChange: (() -> Void)?

    private let sampler = NetTopSampler()
    private let store = PersistenceController.shared
    private var recentRateSamples: [(date: Date, downloadBps: Double, uploadBps: Double)] = []
    private var sampleTask: Task<Void, Never>?
    private var speedTestTask: Task<Void, Never>?
    private var connectivityTask: Task<Void, Never>?
    private var publicIPTask: Task<Void, Never>?
    private var isSyncingLaunchAtLoginSetting = false

    var menuBarLines: [String] {
        if !isInternetAvailable {
            return ["Internet Down"]
        }

        let down = ByteFormat.menuSpeed(totalDownloadBps, units: settings.units, scale: settings.unitScale, roundsScaledValues: settings.roundScaledMeasurements)
        let up = ByteFormat.menuSpeed(totalUploadBps, units: settings.units, scale: settings.unitScale, roundsScaledValues: settings.roundScaledMeasurements)
        let total = ByteFormat.menuSpeed(totalDownloadBps + totalUploadBps, units: settings.units, scale: settings.unitScale, roundsScaledValues: settings.roundScaledMeasurements)

        let icon = settings.showIcon ? "􀙇 " : ""
        let downPrefix = settings.showMenuArrows ? "↓ " : ""
        let upPrefix = settings.showMenuArrows ? "↑ " : ""
        let totalPrefix = settings.showMenuArrows ? "↕ " : ""
        switch settings.menuMetric {
        case .download:
            return ["\(icon)\(downPrefix)\(down)"]
        case .upload:
            return ["\(icon)\(upPrefix)\(up)"]
        case .both:
            if settings.menuLayout == .stacked {
                return ["\(icon)\(upPrefix)\(up)", "\(icon)\(downPrefix)\(down)"]
            }
            return ["\(icon)\(downPrefix)\(down)  \(upPrefix)\(up)"]
        case .total:
            return ["\(icon)\(totalPrefix)\(total)"]
        }
    }

    var bestCapableResult: SpeedTestResult? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return speedTests
            .filter { $0.timestamp >= cutoff }
            .max { lhs, rhs in
                (lhs.downloadMbps + lhs.uploadMbps) < (rhs.downloadMbps + rhs.uploadMbps)
            }
    }

    var averageRecentResult: (download: Double, upload: Double)? {
        let recent = Array(speedTests.prefix(10))
        guard !recent.isEmpty else { return nil }
        return (
            recent.map(\.downloadMbps).reduce(0, +) / Double(recent.count),
            recent.map(\.uploadMbps).reduce(0, +) / Double(recent.count)
        )
    }

    func start() {
        syncLaunchAtLoginStatus()
        speedTests = store.fetchSpeedTests()
        requestNotificationAuthorization()
        LocationPermissionManager.shared.onAuthorizationChanged = { [weak self] in
            guard let self else { return }
            self.wiFiNamePermissionStatus = LocationPermissionManager.shared.statusText
            self.wiFiNamePermissionDiagnostic = LocationPermissionManager.shared.diagnosticsText
            self.refreshLocalIPAddress()
        }
        LocationPermissionManager.shared.onDiagnosticsChanged = { [weak self] diagnostic in
            guard let self else { return }
            self.wiFiNamePermissionDiagnostic = diagnostic
            self.wiFiNamePermissionStatus = LocationPermissionManager.shared.statusText
        }
        refreshTotals()
        refreshLocalIPAddress()
        startPublicIPChecks()
        startAutomaticSpeedTests()
        startConnectivityChecks()
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.collectSample()
                try? await Task.sleep(for: .seconds(max(self.settings.samplingIntervalSeconds, 1)))
            }
        }
    }

    func stop() {
        sampleTask?.cancel()
        sampleTask = nil
        speedTestTask?.cancel()
        speedTestTask = nil
        connectivityTask?.cancel()
        connectivityTask = nil
        publicIPTask?.cancel()
        publicIPTask = nil
    }

    func refreshNow() {
        Task { await collectSample() }
    }

    func runSpeedTest() {
        guard !isRunningSpeedTest else { return }
        let runner = SpeedTestRunner()
        isRunningSpeedTest = true
        speedTestMessage = nil

        Task {
            do {
                let result = try await runner.run()
                store.insertSpeedTest(result)
                speedTests = store.fetchSpeedTests()
                speedTestMessage = "Completed with \(result.serverName)"
            } catch {
                speedTestMessage = error.localizedDescription
            }
            isRunningSpeedTest = false
        }
    }

    var latestSpeedTestSummary: String {
        guard let latest = speedTests.first else { return "No test yet" }
        let down = latest.downloadMbps.formatted(.number.precision(.fractionLength(settings.roundScaledMeasurements ? 0 : 1)))
        let up = latest.uploadMbps.formatted(.number.precision(.fractionLength(settings.roundScaledMeasurements ? 0 : 1)))
        return "↓ \(down) / ↑ \(up) Mbps"
    }

    func clearSpeedTestHistory() {
        store.clearSpeedTests()
        speedTests = []
    }

    func clearUsageHistory() {
        store.clearUsage()
        apps = apps.map { app in
            var app = app
            app.download24h = 0
            app.upload24h = 0
            return app
        }
        download24h = 0
        upload24h = 0
        refreshTotals()
    }

    func requestWiFiNamePermission() {
        LocationPermissionManager.shared.requestAuthorization()
        wiFiNamePermissionStatus = LocationPermissionManager.shared.statusText
        wiFiNamePermissionDiagnostic = LocationPermissionManager.shared.diagnosticsText
        refreshLocalIPAddress()
    }

    func appActivity(since date: Date) -> [AppBandwidth] {
        var historical = Dictionary(uniqueKeysWithValues: store.usageApps(since: date).map { ($0.id, $0) })

        for liveApp in apps {
            var merged = historical[liveApp.id] ?? liveApp
            merged.downloadBps = liveApp.downloadBps
            merged.uploadBps = liveApp.uploadBps
            merged.isActive = liveApp.downloadBps > 0 || liveApp.uploadBps > 0
            if historical[liveApp.id] == nil {
                merged.download24h = 0
                merged.upload24h = 0
            }
            historical[liveApp.id] = merged
        }

        return filterHiddenApps(Array(historical.values))
    }

    private func collectSample() async {
        do {
            let sample = try await sampler.sample()
            let rawDownloadBps = sample.apps.map(\.downloadBps).reduce(0, +)
            let rawUploadBps = sample.apps.map(\.uploadBps).reduce(0, +)
            recordRateSample(downloadBps: rawDownloadBps, uploadBps: rawUploadBps)
            applySmoothedRates()
            activeInterface = sample.interfaceName
            refreshLocalIPAddress()
            lastSampleStatus = sample.apps.isEmpty ? "No active network processes" : "Live"
            let visibleApps = filterHiddenApps(settings.groupApps ? AppGrouper.group(sample.apps) : sample.apps)
            apps = attachUsageTotals(to: visibleApps)
            store.insertUsage(apps)
            refreshTotals()
            pruneExpiredUsage()
            onStatusChange?()
        } catch {
            lastSampleStatus = error.localizedDescription
            apps = []
            recentRateSamples = []
            totalDownloadBps = 0
            totalUploadBps = 0
            onStatusChange?()
        }
    }

    private func recordRateSample(downloadBps: Double, uploadBps: Double) {
        recentRateSamples.append((Date(), downloadBps, uploadBps))
        trimRateSamples()
    }

    private func trimRateSamples() {
        let window = max(settings.rateSmoothingSeconds, settings.samplingIntervalSeconds)
        let cutoff = Date().addingTimeInterval(-Double(max(window, 1)))
        recentRateSamples.removeAll { $0.date < cutoff }
    }

    private func applySmoothedRates() {
        guard !recentRateSamples.isEmpty else { return }
        let smoothingWindow = settings.rateSmoothingSeconds
        let samples: [(date: Date, downloadBps: Double, uploadBps: Double)]
        if smoothingWindow <= 1 {
            samples = [recentRateSamples.last!]
        } else {
            let cutoff = Date().addingTimeInterval(-Double(smoothingWindow))
            samples = recentRateSamples.filter { $0.date >= cutoff }
        }
        guard !samples.isEmpty else { return }
        totalDownloadBps = samples.map(\.downloadBps).reduce(0, +) / Double(samples.count)
        totalUploadBps = samples.map(\.uploadBps).reduce(0, +) / Double(samples.count)
    }

    private func refreshTotals() {
        let totals = store.usageTotals(since: Date().addingTimeInterval(-24 * 60 * 60))
        download24h = totals.bytesIn
        upload24h = totals.bytesOut
    }

    private func attachUsageTotals(to apps: [AppBandwidth]) -> [AppBandwidth] {
        let totals = store.usageTotalsByApp(since: Date().addingTimeInterval(-24 * 60 * 60))
        return apps.map { app in
            var app = app
            let appTotals = totals[app.id] ?? (0, 0)
            app.download24h = appTotals.bytesIn
            app.upload24h = appTotals.bytesOut
            return app
        }
    }

    private func pruneExpiredUsage() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.retentionDays, to: Date()) ?? .distantPast
        store.pruneUsage(olderThan: cutoff)
    }

    private func filterHiddenApps(_ apps: [AppBandwidth]) -> [AppBandwidth] {
        guard settings.hideSystemServices else { return apps }
        return apps.filter { $0.displayName != "System Services" && $0.id != "System Services" }
    }

    private func startAutomaticSpeedTests() {
        speedTestTask?.cancel()
        guard settings.automaticSpeedTestsEnabled else { return }

        speedTestTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.shouldRunAutomaticSpeedTest {
                    self.runSpeedTest()
                }
                let seconds = max(self.settings.speedTestIntervalHours, 1) * 60 * 60
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    private var shouldRunAutomaticSpeedTest: Bool {
        guard !isRunningSpeedTest, isInternetAvailable else { return false }
        guard let latest = speedTests.first else { return true }
        return Date().timeIntervalSince(latest.timestamp) >= Double(settings.speedTestIntervalHours * 60 * 60)
    }

    private func startConnectivityChecks() {
        connectivityTask?.cancel()
        connectivityTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wasAvailable = self.isInternetAvailable
                let available = await Self.probeInternet()
                self.isInternetAvailable = available
                self.internetStatusText = available ? "Internet online" : "Internet down"
                if !wasAvailable && available {
                    self.refreshPublicIPAddress()
                    self.notifyInternetRestored()
                }
                if wasAvailable != available {
                    self.onStatusChange?()
                }
                try? await Task.sleep(for: .seconds(available ? 30 : 10))
            }
        }
    }

    private static func probeInternet() async -> Bool {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<400).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func refreshLocalIPAddress() {
        networkConnections = NetworkIdentity.activeConnections()
        localIPAddress = networkConnections.first?.localIP ?? "Unavailable"
        let wifiInfo = NetworkIdentity.wifiInfo()
        wifiNetworkName = wifiInfo.networkName
        wifiSignal = wifiInfo.signal
    }

    private func startPublicIPChecks() {
        publicIPTask?.cancel()
        publicIPTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isInternetAvailable {
                    let publicInfo = await NetworkIdentity.publicNetworkInfo()
                    self.publicIPAddress = publicInfo.ipAddress
                    self.publicIPLocation = publicInfo.location
                }
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    private func refreshPublicIPAddress() {
        Task { [weak self] in
            guard let self else { return }
            let publicInfo = await NetworkIdentity.publicNetworkInfo()
            self.publicIPAddress = publicInfo.ipAddress
            self.publicIPLocation = publicInfo.location
        }
    }

    private func notifyInternetRestored() {
        let content = UNMutableNotificationContent()
        content.title = "Internet is back"
        content.body = "Bandwidth Meter can reach the internet again."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func syncLaunchAtLoginStatus() {
        let isEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginStatus = isEnabled ? "On" : "Off"
        if settings.launchAtLogin != isEnabled {
            isSyncingLaunchAtLoginSetting = true
            var syncedSettings = settings
            syncedSettings.launchAtLogin = isEnabled
            settings = syncedSettings
            isSyncingLaunchAtLoginSetting = false
        }
    }

    private func configureLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginStatus = enabled ? "On" : "Off"
            launchAtLoginMessage = nil
        } catch {
            let isEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginStatus = isEnabled ? "On" : "Off"
            launchAtLoginMessage = error.localizedDescription
            if settings.launchAtLogin != isEnabled {
                isSyncingLaunchAtLoginSetting = true
                var revertedSettings = settings
                revertedSettings.launchAtLogin = isEnabled
                settings = revertedSettings
                isSyncingLaunchAtLoginSetting = false
            }
        }
    }
}

struct AppBandwidth: Identifiable, Hashable {
    let id: String
    let displayName: String
    let processName: String
    let pid: Int32
    var downloadBps: Double
    var uploadBps: Double
    var download24h: Int64
    var upload24h: Int64
    var isActive = true
}

struct SpeedTestResult: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let downloadMbps: Double
    let uploadMbps: Double
    let latencyMs: Double
    let jitterMs: Double
    let packetLoss: Double?
    let serverName: String
    let isp: String
    let resultURL: String?
}

enum MenuMetric: String, CaseIterable, Identifiable {
    case both
    case download
    case upload
    case total

    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: "Download and Upload"
        case .download: "Download Only"
        case .upload: "Upload Only"
        case .total: "Total"
        }
    }
}

enum UnitPreference: String, CaseIterable, Identifiable {
    case bytes
    case bits

    var id: String { rawValue }
    var label: String { self == .bytes ? "Bytes/s" : "Bits/s" }
}

enum UnitScale: String, CaseIterable, Identifiable {
    case automatic
    case kilo
    case mega
    case giga

    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic:
            return "Auto"
        case .kilo:
            return "Kilo"
        case .mega:
            return "Mega"
        case .giga:
            return "Giga"
        }
    }
}

enum MenuLayout: String, CaseIterable, Identifiable {
    case inline
    case stacked

    var id: String { rawValue }
    var label: String {
        switch self {
        case .inline:
            return "Next to Each Other"
        case .stacked:
            return "Stacked"
        }
    }
}

enum SamplingInterval: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .one:
            return "1 second"
        case .two:
            return "2 seconds"
        case .three:
            return "3 seconds"
        }
    }
}

enum RateSmoothing: Int, CaseIterable, Identifiable {
    case off = 1
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .off:
            return "Off"
        case .three:
            return "3 seconds"
        case .five:
            return "5 seconds"
        case .ten:
            return "10 seconds"
        }
    }
}

struct AppSettings {
    var menuMetric: MenuMetric = .both
    var menuLayout: MenuLayout = .inline
    var units: UnitPreference = .bytes
    var unitScale: UnitScale = .automatic
    var roundScaledMeasurements = false
    var menuFontSize: Double = 15
    var showIcon = false
    var showMenuArrows = true
    var groupApps = true
    var hideSystemServices = false
    var samplingIntervalSeconds = 1
    var rateSmoothingSeconds = 3
    var retentionDays = 30
    var automaticSpeedTestsEnabled = false
    var speedTestIntervalHours = 6
    var launchAtLogin = false

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        var settings = AppSettings()
        if let value = defaults.string(forKey: "menuMetric"), let metric = MenuMetric(rawValue: value) {
            settings.menuMetric = metric
        }
        if let value = defaults.string(forKey: "menuLayout"), let layout = MenuLayout(rawValue: value) {
            settings.menuLayout = layout
        }
        if let value = defaults.string(forKey: "units"), let units = UnitPreference(rawValue: value) {
            settings.units = units
        }
        if let value = defaults.string(forKey: "unitScale"), let scale = UnitScale(rawValue: value) {
            settings.unitScale = scale
        }
        settings.roundScaledMeasurements = defaults.bool(forKey: "roundScaledMeasurements")
        let fontSize = defaults.double(forKey: "menuFontSize")
        if fontSize > 0 { settings.menuFontSize = fontSize }
        settings.showIcon = defaults.bool(forKey: "showIcon")
        if defaults.object(forKey: "showMenuArrows") != nil {
            settings.showMenuArrows = defaults.bool(forKey: "showMenuArrows")
        }
        if defaults.object(forKey: "groupApps") != nil {
            settings.groupApps = defaults.bool(forKey: "groupApps")
        }
        settings.hideSystemServices = defaults.bool(forKey: "hideSystemServices")
        let samplingIntervalSeconds = defaults.integer(forKey: "samplingIntervalSeconds")
        if SamplingInterval(rawValue: samplingIntervalSeconds) != nil {
            settings.samplingIntervalSeconds = samplingIntervalSeconds
        }
        let rateSmoothingSeconds = defaults.integer(forKey: "rateSmoothingSeconds")
        if RateSmoothing(rawValue: rateSmoothingSeconds) != nil {
            settings.rateSmoothingSeconds = rateSmoothingSeconds
        }
        let retention = defaults.integer(forKey: "retentionDays")
        if retention > 0 { settings.retentionDays = retention }
        settings.automaticSpeedTestsEnabled = defaults.bool(forKey: "automaticSpeedTestsEnabled")
        let speedTestIntervalHours = defaults.integer(forKey: "speedTestIntervalHours")
        if speedTestIntervalHours > 0 { settings.speedTestIntervalHours = speedTestIntervalHours }
        settings.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        return settings
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(menuMetric.rawValue, forKey: "menuMetric")
        defaults.set(menuLayout.rawValue, forKey: "menuLayout")
        defaults.set(units.rawValue, forKey: "units")
        defaults.set(unitScale.rawValue, forKey: "unitScale")
        defaults.set(roundScaledMeasurements, forKey: "roundScaledMeasurements")
        defaults.set(menuFontSize, forKey: "menuFontSize")
        defaults.set(showIcon, forKey: "showIcon")
        defaults.set(showMenuArrows, forKey: "showMenuArrows")
        defaults.set(groupApps, forKey: "groupApps")
        defaults.set(hideSystemServices, forKey: "hideSystemServices")
        defaults.set(samplingIntervalSeconds, forKey: "samplingIntervalSeconds")
        defaults.set(rateSmoothingSeconds, forKey: "rateSmoothingSeconds")
        defaults.set(retentionDays, forKey: "retentionDays")
        defaults.set(automaticSpeedTestsEnabled, forKey: "automaticSpeedTestsEnabled")
        defaults.set(speedTestIntervalHours, forKey: "speedTestIntervalHours")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
    }
}
