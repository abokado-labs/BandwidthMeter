import AppKit
import Foundation
import Security

extension Notification.Name {
    static let openAppDetail = Notification.Name("BandwidthMeterOpenAppDetail")
}

struct AppIdentity: Hashable {
    enum Confidence: Hashable {
        case knownSystemService
        case resolvedApp
        case unknown
    }

    let app: AppBandwidth
    let confidence: Confidence
    let summary: String
    let explanation: String
    let bundleIdentifier: String?
    let bundlePath: String?
    let signingIdentifier: String?
    let teamIdentifier: String?
    let signingName: String?
    let rawProcesses: [String]

    var title: String { app.displayName }
    var isUnknown: Bool { confidence == .unknown }

    var searchQuery: String {
        var parts = [app.displayName, app.processName]
        if let bundleIdentifier {
            parts.append(bundleIdentifier)
        }
        if let signingName {
            parts.append(signingName)
        }
        return parts.joined(separator: " ")
    }
}

enum AppIdentityResolver {
    static func resolve(_ app: AppBandwidth) -> AppIdentity {
        let rawProcesses = app.processName
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let known = knownProcessExplanation(for: app, rawProcesses: rawProcesses) {
            return known
        }

        let runningApp = runningApplication(for: app, rawProcesses: rawProcesses)
        let bundleURL = runningApp?.bundleURL ?? bundleURL(named: app.displayName)
        let signature = bundleURL.flatMap { signatureInfo(for: $0) }
        let bundle = bundleURL.flatMap(Bundle.init(url:))
        let bundleIdentifier = runningApp?.bundleIdentifier ?? bundle?.bundleIdentifier ?? signature?.identifier

        if let bundleURL {
            return AppIdentity(
                app: app,
                confidence: .resolvedApp,
                summary: "Recognized app bundle",
                explanation: "Bandwidth Meter matched this network activity to an installed or running app bundle on this Mac.",
                bundleIdentifier: bundleIdentifier,
                bundlePath: bundleURL.path,
                signingIdentifier: signature?.identifier,
                teamIdentifier: signature?.teamIdentifier,
                signingName: signature?.signingName,
                rawProcesses: rawProcesses
            )
        }

        return AppIdentity(
            app: app,
            confidence: .unknown,
            summary: "Unknown process",
            explanation: "Bandwidth Meter could not match this process to a known system service or app bundle. It may be a helper, command-line tool, background agent, or a process that has already exited.",
            bundleIdentifier: nil,
            bundlePath: nil,
            signingIdentifier: nil,
            teamIdentifier: nil,
            signingName: nil,
            rawProcesses: rawProcesses
        )
    }

    private static func knownProcessExplanation(for app: AppBandwidth, rawProcesses: [String]) -> AppIdentity? {
        let lowerProcesses = rawProcesses.map { $0.lowercased() }
        let contains: (String) -> Bool = { needle in
            lowerProcesses.contains { $0.contains(needle.lowercased()) }
        }

        let explanation: (String, String) -> AppIdentity = { summary, detail in
            AppIdentity(
                app: app,
                confidence: .knownSystemService,
                summary: summary,
                explanation: detail,
                bundleIdentifier: nil,
                bundlePath: nil,
                signingIdentifier: "Apple system process",
                teamIdentifier: "Apple",
                signingName: "Apple",
                rawProcesses: rawProcesses
            )
        }

        if app.displayName == "System Services" {
            if contains("mDNSResponder") {
                return explanation("Known system service", "mDNSResponder handles local network discovery and DNS lookups for macOS and apps.")
            }
            if contains("apsd") {
                return explanation("Known system service", "apsd is Apple's push notification daemon. It keeps notification connections open for apps and services.")
            }
            if contains("networkserviceproxy") {
                return explanation("Known system service", "networkserviceproxy is used by macOS networking features, including some Apple privacy and relay services.")
            }
            if contains("cfnetwork") {
                return explanation("Known system service", "CFNetwork is Apple's networking framework used by many apps for web requests and downloads.")
            }
            return explanation("Known system service", "This row groups Apple background networking processes that do work for macOS and other apps.")
        }

        if contains("webkit") {
            return explanation("WebKit networking helper", "This is a WebKit networking helper commonly used by Safari and apps that embed Apple's web view.")
        }
        if contains("nsurlsessiond") {
            return explanation("Background transfer service", "nsurlsessiond performs background downloads and uploads for apps, including when the original app is not frontmost.")
        }
        if contains("cloudd") || contains("bird") {
            return explanation("iCloud sync service", "This is part of iCloud Drive and iCloud document syncing.")
        }
        if contains("trustd") {
            return explanation("Certificate validation service", "trustd validates certificates and security trust decisions for macOS and apps.")
        }
        if contains("rapportd") {
            return explanation("Apple Continuity service", "rapportd supports Apple device discovery and Continuity features across nearby Apple devices.")
        }
        if contains("softwareupdated") {
            return explanation("Software Update service", "softwareupdated downloads and checks for macOS and Apple software updates.")
        }

        return nil
    }

    private static func runningApplication(for app: AppBandwidth, rawProcesses: [String]) -> NSRunningApplication? {
        if app.pid > 0, let running = NSRunningApplication(processIdentifier: app.pid) {
            return running
        }

        let displayName = app.displayName.lowercased()
        let processNames = Set(rawProcesses.map { $0.lowercased() })
        return NSWorkspace.shared.runningApplications.first { running in
            if running.localizedName?.lowercased() == displayName {
                return true
            }
            if let bundleName = running.bundleURL?.deletingPathExtension().lastPathComponent.lowercased(),
               processNames.contains(bundleName) || bundleName == displayName {
                return true
            }
            return false
        }
    }

    private static func bundleURL(named name: String) -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications").appendingPathComponent("\(name).app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(name).app")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func signatureInfo(for url: URL) -> (identifier: String?, teamIdentifier: String?, signingName: String?)? {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
        guard status == errSecSuccess, let staticCode else { return nil }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else {
            return nil
        }

        let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let signingName = certificates?.first.flatMap { certificate -> String? in
            var commonName: CFString?
            SecCertificateCopyCommonName(certificate, &commonName)
            return commonName as String?
        }

        return (
            dictionary[kSecCodeInfoIdentifier as String] as? String,
            dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
            signingName
        )
    }
}
