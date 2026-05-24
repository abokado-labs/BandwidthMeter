import AppKit
import CoreLocation
import Foundation
import Security

@MainActor
final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionManager()

    private let manager = CLLocationManager()
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
        case .authorizedAlways, .authorizedWhenInUse:
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
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied, .authorizedAlways, .authorizedWhenInUse:
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
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()
        case .denied, .restricted:
            openLocationServicesSettings()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        recordDiagnostic("Authorization changed. \(stateSummary)")
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
