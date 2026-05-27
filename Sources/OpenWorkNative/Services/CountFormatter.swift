import Foundation

enum CountFormatter {
    static func abbreviated(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K"),
        ]
        for unit in units where Double(absValue) >= unit.threshold {
            let scaled = Double(absValue) / unit.threshold
            let formatted: String
            if scaled >= 100 {
                formatted = String(Int(scaled.rounded()))
            } else {
                let rounded = (scaled * 10).rounded() / 10
                formatted = rounded.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(rounded))
                    : String(format: "%.1f", rounded)
            }
            return "\(sign)\(formatted)\(unit.suffix)"
        }
        return "\(value)"
    }

    static func usd(_ value: Double) -> String {
        if value == 0 { return "$0.00" }
        let fractionDigits = abs(value) < 0.01 ? 4 : 2
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.\(fractionDigits)f", value)
    }

    static func latency(_ seconds: TimeInterval) -> String {
        if seconds < 0.1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return String(format: "%.1fs", seconds)
    }
}
