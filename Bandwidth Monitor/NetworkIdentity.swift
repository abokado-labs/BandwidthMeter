import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

enum NetworkIdentity {
    struct Connection: Identifiable, Hashable {
        let id: String
        let type: String
        let name: String
        let localIP: String
        let signal: String
        let symbolName: String
    }

    struct WiFiInfo: Hashable {
        let interfaceName: String?
        let networkName: String
        let signal: String
    }

    struct PublicNetworkInfo: Hashable {
        let ipAddress: String
        let location: String
    }

    static func wifiInfo() -> WiFiInfo {
        guard let interface = CWWiFiClient.shared().interface() else {
            return WiFiInfo(interfaceName: nil, networkName: "Unavailable", signal: "Unavailable")
        }

        let ssid = interface.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rssi = interface.rssiValue()
        let signal = rssi == 0 ? "Unavailable" : "\(signalPercent(fromRSSI: rssi))% (\(rssi) dBm)"
        return WiFiInfo(
            interfaceName: interface.interfaceName,
            networkName: ssid?.isEmpty == false ? ssid! : "Unavailable",
            signal: signal
        )
    }

    static func activeConnections() -> [Connection] {
        let wifi = wifiInfo()
        let displayNames = interfaceDisplayNames()
        var connections: [Connection] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        var seen = Set<String>()
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }

            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            guard isUp, !isLoopback, let addr = interface.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let bsdName = String(cString: interface.ifa_name)
            guard bsdName.hasPrefix("en") || bsdName.hasPrefix("bridge") else { continue }
            guard !seen.contains(bsdName), let ip = ipAddress(from: addr) else { continue }
            seen.insert(bsdName)

            let displayName = displayNames[bsdName] ?? bsdName
            let isWiFi = bsdName == wifi.interfaceName || displayName.localizedCaseInsensitiveContains("wi-fi") || displayName.localizedCaseInsensitiveContains("airport")
            connections.append(Connection(
                id: bsdName,
                type: isWiFi ? "Wi-Fi" : displayName,
                name: isWiFi ? wifi.networkName : displayName,
                localIP: ip,
                signal: isWiFi ? wifi.signal : "N/A",
                symbolName: isWiFi ? "wifi" : "network"
            ))
        }

        return connections.sorted { lhs, rhs in
            if lhs.type == "Wi-Fi", rhs.type != "Wi-Fi" { return true }
            if lhs.type != "Wi-Fi", rhs.type == "Wi-Fi" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func localIPAddress() -> String {
        activeConnections().first?.localIP ?? "Unavailable"
    }

    static func publicNetworkInfo() async -> PublicNetworkInfo {
        guard let url = URL(string: "https://ipapi.co/json/") else {
            return PublicNetworkInfo(ipAddress: "Unavailable", location: "Unavailable")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return PublicNetworkInfo(ipAddress: "Unavailable", location: "Unavailable")
            }
            let payload = try JSONDecoder().decode(PublicNetworkPayload.self, from: data)
            return PublicNetworkInfo(
                ipAddress: payload.ip.trimmedOrUnavailable,
                location: payload.displayLocation
            )
        } catch {
            return PublicNetworkInfo(ipAddress: "Unavailable", location: "Unavailable")
        }
    }

    static func publicIPAddress() async -> String {
        await publicNetworkInfo().ipAddress
    }

    private static func signalPercent(fromRSSI rssi: Int) -> Int {
        let clamped = min(max(rssi, -100), -50)
        return Int(round(Double(clamped + 100) / 50 * 100))
    }

    private static func ipAddress(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            addr,
            socklen_t(addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: hostname)
    }

    private static func interfaceDisplayNames() -> [String: String] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: interfaces.compactMap { interface in
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
            let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsdName
            return (bsdName, displayName)
        })
    }
}

private struct PublicNetworkPayload: Decodable {
    let ip: String?
    let city: String?
    let region: String?
    let countryName: String?

    enum CodingKeys: String, CodingKey {
        case ip
        case city
        case region
        case countryName = "country_name"
    }

    var displayLocation: String {
        let parts = [city, region, countryName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Unavailable" : parts.joined(separator: ", ")
    }
}

private extension Optional where Wrapped == String {
    var trimmedOrUnavailable: String {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "Unavailable"
        }
        return value
    }
}
