import Foundation

/// Default filtering for the model picker: hides providers/models the user never wants
/// to see, categorically-excluded capabilities, redundant dated snapshots, and — for
/// providers whose naming convention we've mapped — all but the two most recent
/// generations of each model family. Bypassed entirely when the user enables
/// `AppState.showAllModels`.
enum ModelFiltering {
    static let alwaysHiddenProviderIDs: Set<String> = ["opencode"]
    static let reasoningFilterExemptProviderIDs: Set<String> = ["inception"]
    static let hardExcludedIDSubstrings = ["codex-spark", "customtools", "mini-fast"]
    static let hardExcludedModelIDs: Set<String> = ["gemma-4-26b-a4b-it"]

    private static let datedSnapshotSuffix = try! NSRegularExpression(pattern: "-\\d{8}$")

    static func isProviderHidden(_ provider: ModelProvider) -> Bool {
        alwaysHiddenProviderIDs.contains(provider.id)
    }

    /// Applies every default filter to one provider's models, returning bare model names
    /// (not provider-prefixed).
    static func slimmedModelNames(for provider: ModelProvider) -> [String] {
        var names = provider.models.filter { $0 != "No configured model" }

        names = names.filter { name in
            !hardExcludedModelIDs.contains(name)
                && !hardExcludedIDSubstrings.contains { name.contains($0) }
        }

        names = names.filter { name in
            guard let capability = provider.modelCapabilities[name] else { return true }
            if !capability.outputText { return false }
            if capability.outputImage { return false }
            if !capability.reasoning && !reasoningFilterExemptProviderIDs.contains(provider.id) { return false }
            return true
        }

        names = hidingRedundantDatedSnapshots(names)
        names = keepingLatestGenerations(names, provider: provider.id)
        return names
    }

    /// Providers list both a floating alias (e.g. "claude-opus-4-5") and a pinned dated
    /// snapshot of the same release (e.g. "claude-opus-4-5-20251101"). The alias always
    /// resolves to that snapshot, so the dated duplicate is pure clutter — hide it, but
    /// only when the alias is actually present, so a provider with only dated IDs still
    /// shows all of them.
    private static func hidingRedundantDatedSnapshots(_ names: [String]) -> [String] {
        func isDatedSnapshot(_ name: String) -> Bool {
            datedSnapshotSuffix.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }
        guard names.contains(where: { !isDatedSnapshot($0) }) else { return names }
        return names.filter { !isDatedSnapshot($0) }
    }

    private struct ParsedModel {
        let family: String
        /// nil marks a floating alias (e.g. "-latest") — always kept, exempt from the
        /// top-N generation cutoff since it doesn't represent a discrete generation.
        let generation: [Int]?
    }

    /// Splits a bare model name into (family, generation) using the naming convention
    /// for the given provider. Returns nil if the provider's convention isn't mapped,
    /// or a specific name doesn't parse — those names skip generation-based trimming.
    private static func parse(_ name: String, provider: String) -> ParsedModel? {
        switch provider {
        case "anthropic":
            var base = name
            let isFast = base.hasSuffix("-fast")
            if isFast { base.removeLast(5) }
            var generation: [Int] = []
            while let range = base.range(of: "-", options: .backwards) {
                let tail = base[base.index(after: range.lowerBound)...]
                guard let n = Int(tail) else { break }
                generation.insert(n, at: 0)
                base = String(base[..<range.lowerBound])
            }
            guard !generation.isEmpty else { return nil }
            return ParsedModel(family: isFast ? "\(base)-fast" : base, generation: generation)

        case "openai":
            var base = name
            for suffix in ["-fast", "-mini"] where base.hasSuffix(suffix) {
                base.removeLast(suffix.count)
            }
            guard let range = base.range(of: "-", options: .backwards) else { return nil }
            let tail = base[base.index(after: range.lowerBound)...]
            let components = tail.split(separator: ".").compactMap { Int($0) }
            guard !components.isEmpty else { return nil }
            return ParsedModel(family: String(base[..<range.lowerBound]), generation: components)

        case "google":
            if name.hasSuffix("-latest") {
                return ParsedModel(family: String(name.dropLast("-latest".count)), generation: nil)
            }
            var base = name
            if base.hasSuffix("-preview") { base.removeLast("-preview".count) }
            base = base.replacingOccurrences(of: "-lite", with: "")
            guard base.hasPrefix("gemini-") else { return nil }
            let rest = base.dropFirst("gemini-".count)
            guard let dashIndex = rest.firstIndex(of: "-") else { return nil }
            let versionPart = rest[rest.startIndex..<dashIndex]
            let corePart = rest[rest.index(after: dashIndex)...]
            let components = versionPart.split(separator: ".").compactMap { Int($0) }
            guard !components.isEmpty else { return nil }
            return ParsedModel(family: "gemini-\(corePart)", generation: components)

        default:
            return nil
        }
    }

    /// Keeps every alias/unrecognized name as-is, and within each recognized family keeps
    /// only the `keep` most recent generations (comparing generation number components
    /// lexicographically, so "4.10" ranks above "4.8").
    private static func keepingLatestGenerations(_ names: [String], provider: String, keep: Int = 2) -> [String] {
        var alwaysKept: [String] = []
        var unparsed: [String] = []
        var byFamily: [String: [(name: String, generation: [Int])]] = [:]

        for name in names {
            guard let parsed = parse(name, provider: provider) else {
                unparsed.append(name)
                continue
            }
            guard let generation = parsed.generation else {
                alwaysKept.append(name)
                continue
            }
            byFamily[parsed.family, default: []].append((name, generation))
        }

        guard !byFamily.isEmpty else { return names }

        var kept = alwaysKept + unparsed
        for members in byFamily.values {
            let generations = Set(members.map(\.generation)).sorted { lhs, rhs in
                for (a, b) in zip(lhs, rhs) where a != b { return a < b }
                return lhs.count < rhs.count
            }
            let keptGenerations = Set(generations.suffix(keep))
            kept.append(contentsOf: members.filter { keptGenerations.contains($0.generation) }.map(\.name))
        }
        return kept
    }
}
