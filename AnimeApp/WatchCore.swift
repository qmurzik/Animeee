import Foundation

enum EpisodeNumber {
    static func canonical(_ number: String?) -> String {
        let value = (number ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let numeric = Double(value.replacingOccurrences(of: ",", with: ".")), numeric.isFinite, numeric >= 0 { return String(numeric) }
        return value.lowercased()
    }
    static func isBefore(_ lhs: String?, _ rhs: String?) -> Bool {
        let a = canonical(lhs), b = canonical(rhs)
        if let x = Double(a), let y = Double(b) { return x < y }
        return a.localizedStandardCompare(b) == .orderedAscending
    }
}
func episodeIdentity(_ number: String?) -> String { EpisodeNumber.canonical(number) }

enum PlaybackMath {
    static func seekTarget(_ proposed: Double, duration: Double) -> Double {
        guard proposed.isFinite else { return 0 }
        return max(0, min(proposed, duration.isFinite && duration > 0 ? min(duration, 2_000_000) : 2_000_000))
    }
    static func resumeID(_ ids: [Int], remembered: Int?, numbers: [String?] = [], episode: String? = nil) -> Int? {
        if let remembered, ids.contains(remembered) { return remembered }
        if let episode, !EpisodeNumber.canonical(episode).isEmpty,
           let index = numbers.firstIndex(where: { EpisodeNumber.canonical($0) == EpisodeNumber.canonical(episode) }), ids.indices.contains(index) { return ids[index] }
        return ids.first
    }
}
