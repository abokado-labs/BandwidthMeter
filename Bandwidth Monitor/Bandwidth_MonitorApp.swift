import AppKit
import Sparkle
import SwiftUI

@main
struct Bandwidth_MonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
                .frame(width: 620, height: 460)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = BandwidthModel()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var updaterController: SPUStandardUpdaterController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var appDetailWindow: NSWindow?
    private var keyMonitor: Any?
    private var appDetailObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        configureUpdater()
        configureKeyboardShortcuts()
        configureAppDetailObserver()
        model.start()
        showOnboardingIfNeeded()
    }

    static var sparkleConfigurationStatus: String {
        "Configured"
    }

    private func configureUpdater() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let appDetailObserver {
            NotificationCenter.default.removeObserver(appDetailObserver)
        }
        model.stop()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateMenuTitle()

        model.onStatusChange = { [weak self] in
            DispatchQueue.main.async {
                self?.updateMenuTitle()
            }
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 430, height: 560)
        popover.contentViewController = NSHostingController(rootView: DashboardView(model: model))
    }

    private func updateMenuTitle() {
        guard let button = statusItem.button else { return }

        if !model.isInternetAvailable {
            let lines = model.menuBarLines
            let fontSize = CGFloat(model.settings.menuFontSize)
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(
                string: lines.joined(separator: "\n"),
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.labelColor
                ]
            )
            let width = (lines.joined(separator: "\n") as NSString).size(withAttributes: [.font: font]).width
            statusItem.length = ceil(width + 16)
            return
        }

        let stacked = model.settings.menuLayout == .stacked && model.settings.menuMetric == .both
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.image = menuBarImage(stacked: stacked)
        button.imagePosition = .imageOnly
        statusItem.length = reservedMenuBarLength(stacked: stacked)
    }

    private struct MenuBarEntry {
        let arrow: String
        let number: String
        let unit: String
    }

    private func menuBarEntries(stacked: Bool) -> [MenuBarEntry] {
        let down = ByteFormat.menuSpeedParts(model.totalDownloadBps, units: model.settings.units, scale: model.settings.unitScale, roundsScaledValues: model.settings.roundScaledMeasurements)
        let up = ByteFormat.menuSpeedParts(model.totalUploadBps, units: model.settings.units, scale: model.settings.unitScale, roundsScaledValues: model.settings.roundScaledMeasurements)
        let total = ByteFormat.menuSpeedParts(model.totalDownloadBps + model.totalUploadBps, units: model.settings.units, scale: model.settings.unitScale, roundsScaledValues: model.settings.roundScaledMeasurements)

        switch model.settings.menuMetric {
        case .download:
            return [MenuBarEntry(arrow: "↓", number: down.number, unit: down.unit)]
        case .upload:
            return [MenuBarEntry(arrow: "↑", number: up.number, unit: up.unit)]
        case .both:
            let downEntry = MenuBarEntry(arrow: "↓", number: down.number, unit: down.unit)
            let upEntry = MenuBarEntry(arrow: "↑", number: up.number, unit: up.unit)
            return stacked ? [upEntry, downEntry] : [downEntry, upEntry]
        case .total:
            return [MenuBarEntry(arrow: "↕", number: total.number, unit: total.unit)]
        }
    }

    private func menuBarImage(stacked: Bool) -> NSImage {
        let entries = menuBarEntries(stacked: stacked)
        let visibleEntries = stacked ? entries : entries.prefix(model.settings.menuMetric == .both ? 2 : 1).map { $0 }
        let fontSize = stacked
            ? CGFloat(min(max(model.settings.menuFontSize * 0.66, 4), 10.5))
            : CGFloat(model.settings.menuFontSize)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let width = reservedMenuBarLength(stacked: stacked) - 6
        let height = max(NSStatusBar.system.thickness, 22)
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        if stacked {
            let lineHeight = ceil(fontSize + 1)
            let blockHeight = lineHeight * CGFloat(visibleEntries.count)
            let firstBaselineTop = floor((height + blockHeight) / 2) - lineHeight + 1
            for (index, entry) in visibleEntries.enumerated() {
                drawMenuBarEntry(entry, includesIcon: index == 0 && model.settings.showIcon, at: NSPoint(x: 3, y: firstBaselineTop - (CGFloat(index) * lineHeight)), attributes: attributes)
            }
        } else {
            let y = floor((height - fontSize) / 2)
            var x: CGFloat = 3
            for (index, entry) in visibleEntries.enumerated() {
                let usedWidth = drawMenuBarEntry(entry, includesIcon: index == 0 && model.settings.showIcon, at: NSPoint(x: x, y: y), attributes: attributes)
                x += usedWidth + 10
            }
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    @discardableResult
    private func drawMenuBarEntry(_ entry: MenuBarEntry, includesIcon: Bool, at origin: NSPoint, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        var x = origin.x
        if includesIcon {
            drawMenuIcon(at: NSPoint(x: x, y: origin.y), attributes: attributes)
            x += menuIconWidth(attributes: attributes)
        }

        if model.settings.showMenuArrows {
            (entry.arrow as NSString).draw(at: NSPoint(x: x, y: origin.y), withAttributes: attributes)
            x += menuArrowWidth(attributes: attributes)
        }

        let numberWidth = menuNumberColumnWidth(attributes: attributes)
        let actualNumberWidth = (entry.number as NSString).size(withAttributes: attributes).width
        (entry.number as NSString).draw(at: NSPoint(x: x + numberWidth - actualNumberWidth, y: origin.y), withAttributes: attributes)
        x += numberWidth + 3

        let unitWidth = menuUnitColumnWidth(attributes: attributes)
        let actualUnitWidth = (entry.unit as NSString).size(withAttributes: attributes).width
        (entry.unit as NSString).draw(at: NSPoint(x: x + unitWidth - actualUnitWidth, y: origin.y), withAttributes: attributes)
        x += unitWidth
        return x - origin.x
    }

    private func menuIconWidth(attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        guard model.settings.showIcon else { return 0 }
        return menuIconSize(attributes: attributes) + 3
    }

    private func menuIconSize(attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let font = attributes[.font] as? NSFont
        return ceil(font?.pointSize ?? 10)
    }

    private func drawMenuIcon(at origin: NSPoint, attributes: [NSAttributedString.Key: Any]) {
        guard let symbol = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: nil) else {
            return
        }
        let size = menuIconSize(attributes: attributes)
        let font = attributes[.font] as? NSFont
        let yOffset = max(((font?.pointSize ?? size) - size) / 2, 0)
        let rect = NSRect(x: origin.x, y: origin.y + yOffset, width: size, height: size)
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func menuArrowWidth(attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil(("↕ " as NSString).size(withAttributes: attributes).width)
    }

    private func menuNumberColumnWidth(attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ["888", "88.8", "8.88"]
            .map { ($0 as NSString).size(withAttributes: attributes).width }
            .max()
            .map { ceil($0) } ?? 0
    }

    private func menuUnitColumnWidth(attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let labels: [String]
        switch model.settings.units {
        case .bytes:
            labels = ["B/s", "KB/s", "MB/s", "GB/s"]
        case .bits:
            labels = ["bps", "Kbps", "Mbps", "Gbps"]
        }
        return ceil(labels.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0)
    }

    private func menuBarEntryWidth(attributes: [NSAttributedString.Key: Any], includesIcon: Bool) -> CGFloat {
        (includesIcon ? menuIconWidth(attributes: attributes) : 0)
            + (model.settings.showMenuArrows ? menuArrowWidth(attributes: attributes) : 0)
            + menuNumberColumnWidth(attributes: attributes)
            + 3
            + menuUnitColumnWidth(attributes: attributes)
    }

    private func reservedMenuBarLength(stacked: Bool) -> CGFloat {
        let fontSize = stacked
            ? CGFloat(min(max(model.settings.menuFontSize * 0.66, 4), 10.5))
            : CGFloat(model.settings.menuFontSize)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let entryCount = model.settings.menuMetric == .both ? 2 : 1
        let first = menuBarEntryWidth(attributes: attributes, includesIcon: model.settings.showIcon)
        let width: CGFloat
        if stacked {
            let subsequent = menuBarEntryWidth(attributes: attributes, includesIcon: false)
            width = max(first, entryCount > 1 ? subsequent : 0) + 12
        } else {
            let subsequent = menuBarEntryWidth(attributes: attributes, includesIcon: false)
            width = first + (entryCount > 1 ? subsequent + 10 : 0) + 14
        }
        return min(max(ceil(width), stacked ? 44 : 30), stacked ? 110 : 220)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Bandwidth Meter", action: #selector(openPopoverFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Run Speed Test", action: #selector(runSpeedTestFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings(_:)), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Bandwidth Meter", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPopoverFromMenu() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func runSpeedTestFromMenu() {
        model.runSpeedTest()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard let updaterController else {
            let alert = NSAlert()
            alert.messageText = "Updates could not start"
            alert.informativeText = "Bandwidth Meter could not start Sparkle's updater. Please quit and reopen the app, then try again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        updaterController.checkForUpdates(sender)
    }

    private func configureKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else { return event }
            guard event.charactersIgnoringModifiers == "," || event.charactersIgnoringModifiers == "." else { return event }
            self.openSettings(event)
            return nil
        }
    }

    private func configureAppDetailObserver() {
        appDetailObserver = NotificationCenter.default.addObserver(
            forName: .openAppDetail,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.object as? AppBandwidth else { return }
            self?.openAppDetail(for: app)
        }
    }

    private func openAppDetail(for app: AppBandwidth) {
        let identity = AppIdentityResolver.resolve(app)
        let controller = NSHostingController(
            rootView: AppDetailView(identity: identity, settings: model.settings)
                .frame(width: 460, height: 520)
        )

        if let appDetailWindow {
            appDetailWindow.contentViewController = controller
            appDetailWindow.title = "\(identity.title) Details"
            appDetailWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 460, height: 520))
        window.minSize = NSSize(width: 420, height: 420)
        window.title = "\(identity.title) Details"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        appDetailWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }

        let controller = NSHostingController(
            rootView: OnboardingView(
                model: model,
                onOpenPrivacy: {
                    NSWorkspace.shared.open(URL(string: "https://abokadolabs.com/bandwidth-meter/privacy")!)
                },
                onComplete: { [weak self] in
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    self?.onboardingWindow?.close()
                    self?.onboardingWindow = nil
                }
            )
            .frame(width: 520, height: 500)
        )
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 520, height: 500))
        window.minSize = NSSize(width: 500, height: 460)
        window.title = "Welcome to Bandwidth Meter"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func openSettings(_ sender: Any?) {
        popover.performClose(sender)
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(
            rootView: SettingsView(model: model)
                .frame(width: 620, height: 460)
        )
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 620, height: 460))
        window.minSize = NSSize(width: 560, height: 420)
        window.title = "Bandwidth Meter Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
