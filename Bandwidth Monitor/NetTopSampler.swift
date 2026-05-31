import Foundation
import SystemConfiguration

struct NetTopSample {
    let apps: [AppBandwidth]
    let interfaceName: String
}

enum SamplerError: LocalizedError {
    case launchFailed
    case noOutput(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            "Unable to launch /usr/bin/nettop"
        case .noOutput(let details):
            details.isEmpty ? "No nettop data available" : details
        }
    }
}

final class NetTopSampler {
    private var previousCounters: [String: (bytesIn: Int64, bytesOut: Int64, date: Date)] = [:]

    func sample() async throws -> NetTopSample {
        let output = try await runNetTop()
        let rows = parse(output)
        let now = Date()
        var apps: [AppBandwidth] = []

        for row in rows {
            let key = "\(row.processName)#\(row.pid)"
            let previous = previousCounters[key]
            previousCounters[key] = (row.bytesIn, row.bytesOut, now)

            guard let previous else { continue }
            let interval = max(now.timeIntervalSince(previous.date), 0.25)
            let inDelta = max(row.bytesIn - previous.bytesIn, 0)
            let outDelta = max(row.bytesOut - previous.bytesOut, 0)
            guard inDelta > 0 || outDelta > 0 else { continue }

            apps.append(AppBandwidth(
                id: key,
                displayName: row.displayName,
                processName: row.processName,
                pid: row.pid,
                downloadBps: Double(inDelta) / interval,
                uploadBps: Double(outDelta) / interval,
                download24h: 0,
                upload24h: 0,
                sampledDownloadBytes: inDelta,
                sampledUploadBytes: outDelta
            ))
        }

        return NetTopSample(
            apps: apps.sorted { ($0.downloadBps + $0.uploadBps) > ($1.downloadBps + $1.uploadBps) },
            interfaceName: primaryInterfaceName()
        )
    }

    private func runNetTop() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
            process.arguments = ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-x", "-n"]
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { process in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                if process.terminationStatus == 0, !output.isEmpty {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: SamplerError.noOutput(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: SamplerError.launchFailed)
            }
        }
    }

    private func parse(_ output: String) -> [(processName: String, displayName: String, pid: Int32, bytesIn: Int64, bytesOut: Int64)] {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerIndex = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("bytes_in") || $0.localizedCaseInsensitiveContains("bytes in") }) else {
            return []
        }

        let headers = csvFields(lines[headerIndex]).map { $0.lowercased().replacingOccurrences(of: " ", with: "_") }
        let nameIndex = headers.firstIndex(where: { $0 == "process" || $0 == "process_name" || $0 == "name" }) ?? 0
        let bytesInIndex = headers.firstIndex(where: { $0.contains("bytes_in") }) ?? max(headers.count - 2, 0)
        let bytesOutIndex = headers.firstIndex(where: { $0.contains("bytes_out") }) ?? max(headers.count - 1, 0)

        return lines.dropFirst(headerIndex + 1).compactMap { line in
            let fields = csvFields(line)
            guard fields.indices.contains(nameIndex),
                  fields.indices.contains(bytesInIndex),
                  fields.indices.contains(bytesOutIndex) else {
                return nil
            }

            let rawName = fields[nameIndex]
            let parsed = parseProcess(rawName)
            guard parsed.name != "nettop" else { return nil }
            return (
                parsed.name,
                AppGrouper.displayName(for: parsed.name),
                parsed.pid,
                Int64(fields[bytesInIndex].filter(\.isNumber)) ?? 0,
                Int64(fields[bytesOutIndex].filter(\.isNumber)) ?? 0
            )
        }
    }

    private func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for character in line {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return fields
    }

    private func parseProcess(_ value: String) -> (name: String, pid: Int32) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.lastIndex(of: "("), let end = trimmed.lastIndex(of: ")"), start < end {
            let pidText = trimmed[trimmed.index(after: start)..<end]
            let name = String(trimmed[..<start]).trimmingCharacters(in: .whitespaces)
            return (name, Int32(pidText) ?? 0)
        }
        if let dot = trimmed.lastIndex(of: "."), let pid = Int32(trimmed[trimmed.index(after: dot)...]) {
            return (String(trimmed[..<dot]), pid)
        }
        return (trimmed, 0)
    }

    private func primaryInterfaceName() -> String {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return "External"
        }
        if interfaces.contains(where: { SCNetworkInterfaceGetBSDName($0) as String? == "en0" }) {
            return "Wi-Fi"
        }
        return "External"
    }
}

enum AppGrouper {
    static func group(_ apps: [AppBandwidth]) -> [AppBandwidth] {
        let grouped = Dictionary(grouping: apps) { groupingKey(for: $0.processName) }
        return grouped.map { key, members in
            let first = members[0]
            return AppBandwidth(
                id: key,
                displayName: displayName(for: key),
                processName: members.map(\.processName).sorted().joined(separator: ", "),
                pid: first.pid,
                downloadBps: members.map(\.downloadBps).reduce(0, +),
                uploadBps: members.map(\.uploadBps).reduce(0, +),
                download24h: members.map(\.download24h).reduce(0, +),
                upload24h: members.map(\.upload24h).reduce(0, +),
                sampledDownloadBytes: members.map(\.sampledDownloadBytes).reduce(0, +),
                sampledUploadBytes: members.map(\.sampledUploadBytes).reduce(0, +)
            )
        }
        .sorted { ($0.downloadBps + $0.uploadBps) > ($1.downloadBps + $1.uploadBps) }
    }

    static func displayName(for processName: String) -> String {
        let key = groupingKey(for: processName)
        switch key.lowercased() {
        case "safari":
            return "Safari"
        case "system services":
            return "System Services"
        case "xcode":
            return "Xcode"
        default:
            return key.replacingOccurrences(of: " Helper", with: "")
        }
    }

    private static func groupingKey(for processName: String) -> String {
        let lower = processName.lowercased()
        if lower.contains("safari") || lower.contains("webkit") {
            return "Safari"
        }
        if lower.contains("xcode") || lower.contains("sourcekit") {
            return "Xcode"
        }
        if lower.contains("cfnetwork") || lower.contains("mDNSResponder".lowercased()) || lower.contains("apsd") || lower.contains("networkserviceproxy") {
            return "System Services"
        }
        if let range = processName.range(of: " Helper") {
            return String(processName[..<range.lowerBound])
        }
        return processName
    }
}
