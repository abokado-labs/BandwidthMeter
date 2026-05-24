import Foundation

enum SpeedTestError: LocalizedError {
    case missingTool
    case failed(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .missingTool:
            return "macOS networkQuality is not available on this Mac"
        case .failed(let message):
            return message.isEmpty ? "Speed test failed" : message
        case .invalidJSON:
            return "Speed test returned unreadable JSON"
        }
    }
}

struct SpeedTestRunner {
    func run() async throws -> SpeedTestResult {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/networkQuality") else {
            throw SpeedTestError.missingTool
        }

        let data = try await execute()
        guard let response = try? JSONDecoder().decode(NetworkQualityResponse.self, from: data) else {
            throw SpeedTestError.invalidJSON
        }

        return SpeedTestResult(
            id: UUID(),
            timestamp: Date(),
            downloadMbps: response.dlThroughputMbps,
            uploadMbps: response.ulThroughputMbps,
            latencyMs: response.baseRtt ?? 0,
            jitterMs: 0,
            packetLoss: nil,
            serverName: response.interfaceName.map { "macOS networkQuality on \($0)" } ?? "macOS networkQuality",
            isp: "Built-in macOS test",
            resultURL: nil
        )
    }

    private func execute() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
            process.arguments = ["-c"]
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { process in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: SpeedTestError.failed(String(data: errorData, encoding: .utf8) ?? ""))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: SpeedTestError.failed(error.localizedDescription))
            }
        }
    }
}

private struct NetworkQualityResponse: Decodable {
    let dlThroughput: Double?
    let ulThroughput: Double?
    let baseRtt: Double?
    let interfaceName: String?

    var dlThroughputMbps: Double {
        (dlThroughput ?? 0) / 1_000_000
    }

    var ulThroughputMbps: Double {
        (ulThroughput ?? 0) / 1_000_000
    }

    enum CodingKeys: String, CodingKey {
        case dlThroughput = "dl_throughput"
        case ulThroughput = "ul_throughput"
        case baseRtt = "base_rtt"
        case interfaceName = "interface_name"
    }
}
