import AppKit
import CoreLocation
import Foundation
import Security

@MainActor
final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionManager()

    private let manager = CLLocationManager()
    private var previousActivationPolicy: NSApplication.ActivationPolicy?
    private var isRequestingAuthorization = false
    private var requestGeneration = 0
    var onAuthorizationChanged: (() -> Void)?
    var onDiagnosticsChanged: ((String) -> Void)?
    private(set) var diagnosticsText = "No permission request yet"

    var statusText: String {
        guard CLLocationManager.locationServicesEnabled() else { return "Location Services off" }

        switch manager.authorizationStatus {
        case .notDetermined:
            return "Permission not requested"
        case .restricted:
            return "Permission restricted"
        case .denied:
            return "Permission denied"
        case .authorizedAlways:
            return "Permission granted"
        @unknown default:
            return "Permission unknown"
        }
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        recordDiagnostic("Initialized. \(stateSummary)")
    }

    func requestAuthorizationIfNeeded() {
        recordDiagnostic("Automatic request check. \(stateSummary)")
        guard CLLocationManager.locationServicesEnabled() else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            requestForegroundAuthorization()
        case .restricted, .denied, .authorizedAlways:
            break
        @unknown default:
            break
        }
    }

    func requestAuthorization() {
        recordDiagnostic("Manual Wi-Fi name access request. \(stateSummary)")
        guard CLLocationManager.locationServicesEnabled() else {
            openLocationServicesSettings()
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            requestForegroundAuthorization()
        case .denied, .restricted:
            openLocationServicesSettings()
        case .authorizedAlways:
            manager.requestLocation()
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        recordDiagnostic("Authorization changed. \(stateSummary)")
        if manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
        if manager.authorizationStatus != .notDetermined {
            restoreActivationPolicyAfterPrompt()
        }
        onAuthorizationChanged?()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        recordDiagnostic("Location update received. \(stateSummary)")
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        recordDiagnostic("Location request failed: \(error.localizedDescription). \(stateSummary)")
        manager.stopUpdatingLocation()
    }

    private func openLocationServicesSettings() {
        recordDiagnostic("Opening Location Services settings. \(stateSummary)")
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func requestForegroundAuthorization() {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        requestGeneration += 1
        let generation = requestGeneration

        if NSApp.activationPolicy() != .regular {
            previousActivationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
        recordDiagnostic("Requesting macOS Location permission. \(stateSummary)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.manager.requestWhenInUseAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self,
                  self.isRequestingAuthorization,
                  self.requestGeneration == generation else {
                return
            }

            self.recordDiagnostic("Location permission dialog did not complete. \(self.stateSummary)")
            self.restoreActivationPolicyAfterPrompt()
            self.onAuthorizationChanged?()
        }
    }

    private func restoreActivationPolicyAfterPrompt() {
        guard isRequestingAuthorization else { return }
        isRequestingAuthorization = false

        guard let previousActivationPolicy else { return }
        self.previousActivationPolicy = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.setActivationPolicy(previousActivationPolicy)
        }
    }

    private var stateSummary: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown-bundle"
        let hasWhenInUse = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil
        let hasGeneric = Bundle.main.object(forInfoDictionaryKey: "NSLocationUsageDescription") != nil
        let hasLocationEntitlement = Self.entitlementBool("com.apple.security.personal-information.location")
        return "servicesEnabled=\(CLLocationManager.locationServicesEnabled()), status=\(statusText), bundleID=\(bundleID), hasWhenInUseUsage=\(hasWhenInUse), hasLocationUsage=\(hasGeneric), hasLocationEntitlement=\(hasLocationEntitlement)"
    }

    private func recordDiagnostic(_ message: String) {
        diagnosticsText = message
        onDiagnosticsChanged?(message)
    }

    private static func entitlementBool(_ key: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else {
            return false
        }
        return (value as? Bool) == true
    }
}
