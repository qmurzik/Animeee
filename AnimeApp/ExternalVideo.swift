import Foundation

// Catalog clips are deliberately separate from complete playable episodes.
struct ExternalVideo: Decodable, Identifiable {
    let id: Int
    let url: String
    let name: String?
    let kind: String
    let hosting: String
    var destination: URL? {
        guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "https", parsed.host != nil else { return nil }
        return parsed
    }
    var kindTitle: String {
        switch kind {
        case "op": return "Опенинг"
        case "ed": return "Эндинг"
        case "pv", "character_trailer": return "Трейлер"
        case "cm": return "Проморолик"
        case "op_ed_clip", "clip": return "Клип"
        default: return "Видео"
        }
    }
}
