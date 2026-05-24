import Foundation

enum ByteFormat {
    struct SpeedParts {
        let number: String
        let unit: String
    }

    static func speed(_ bytesPerSecond: Double, units: UnitPreference, scale: UnitScale, roundsScaledValues: Bool = false) -> String {
        switch units {
        case .bytes:
            return "\(scaled(bytesPerSecond, labels: ["B", "KB", "MB", "GB", "TB"], scale: scale, roundsScaledValues: roundsScaledValues))/s"
        case .bits:
            return scaled(bytesPerSecond * 8, labels: ["bps", "Kbps", "Mbps", "Gbps", "Tbps"], scale: scale, roundsScaledValues: roundsScaledValues)
        }
    }

    static func menuSpeed(_ bytesPerSecond: Double, units: UnitPreference, scale: UnitScale, roundsScaledValues: Bool = false) -> String {
        let parts = menuSpeedParts(bytesPerSecond, units: units, scale: scale, roundsScaledValues: roundsScaledValues)
        return "\(parts.number) \(parts.unit)"
    }

    static func menuSpeedParts(_ bytesPerSecond: Double, units: UnitPreference, scale: UnitScale, roundsScaledValues: Bool = false) -> SpeedParts {
        switch units {
        case .bytes:
            let component = scaledComponent(bytesPerSecond, labels: ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"], scale: scale)
            return SpeedParts(number: menuNumber(component.amount, index: component.index, roundsScaledValues: roundsScaledValues), unit: component.label)
        case .bits:
            let component = scaledComponent(bytesPerSecond * 8, labels: ["bps", "Kbps", "Mbps", "Gbps", "Tbps"], scale: scale)
            return SpeedParts(number: menuNumber(component.amount, index: component.index, roundsScaledValues: roundsScaledValues), unit: component.label)
        }
    }

    static func bytes(_ bytes: Int64, roundsScaledValues: Bool = false) -> String {
        scaled(Double(bytes), labels: ["B", "KB", "MB", "GB", "TB"], scale: .automatic, roundsScaledValues: roundsScaledValues)
    }

    private static func scaled(_ value: Double, labels: [String], scale: UnitScale, roundsScaledValues: Bool) -> String {
        let component = scaledComponent(value, labels: labels, scale: scale)

        if roundsScaledValues || component.amount >= 100 || component.index == 0 {
            return "\(Int(component.amount.rounded())) \(component.label)"
        }
        if component.amount >= 10 {
            return String(format: "%.1f %@", component.amount, component.label)
        }
        return String(format: "%.2f %@", component.amount, component.label)
    }

    private static func scaledComponent(_ value: Double, labels: [String], scale: UnitScale) -> (amount: Double, index: Int, label: String) {
        var amount = max(value, 0)
        var index = fixedIndex(for: scale)
        if scale == .automatic {
            index = 0
            while amount >= 1000, index < labels.count - 1 {
                amount /= 1000
                index += 1
            }
        } else {
            for _ in 0..<min(index, labels.count - 1) {
                amount /= 1000
            }
            index = min(index, labels.count - 1)
        }

        return (amount, index, labels[index])
    }

    private static func menuNumber(_ amount: Double, index: Int, roundsScaledValues: Bool) -> String {
        if roundsScaledValues || amount >= 100 || index == 0 {
            return "\(Int(amount.rounded()))"
        }
        if amount >= 10 {
            return String(format: "%.1f", amount)
        }
        return String(format: "%.2f", amount)
    }

    private static func fixedIndex(for scale: UnitScale) -> Int {
        switch scale {
        case .automatic:
            return 0
        case .kilo:
            return 1
        case .mega:
            return 2
        case .giga:
            return 3
        }
    }
}

extension Date {
    var shortTimeAndDate: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
