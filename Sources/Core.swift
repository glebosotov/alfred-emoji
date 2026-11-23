import Foundation

struct Emoji: Codable {
    let emoji: String
    let name: String
    let group: String
    var id: String { emoji.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-") }
}
struct Annotation: Codable {
    var name: String?
    var tags: [String]
}
struct Language: Codable {
    let code: String
    let name: String
    let nativeName: String
}
struct Settings: Codable {
    var languages: [String] = ["en"]
    var displayLanguage: String = "en"
}
struct Usage: Codable {
    var count: Int
    var last: Double
}
func normalize(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
func emojiKey(_ value: String) -> String { value.replacingOccurrences(of: "\u{FE0F}", with: "") }
func words(_ value: String) -> [String] {
    normalize(value).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
}
// Bounded Damerau-Levenshtein: one insertion, deletion, substitution or adjacent transposition.
func oneEdit(_ a: String, _ b: String) -> Bool {
    let a = Array(a), b = Array(b)
    guard abs(a.count - b.count) <= 1 else { return false }
    var i = 0, j = 0, edits = 0
    while i < a.count && j < b.count {
        if a[i] == b[j] { i += 1; j += 1; continue }
        edits += 1
        if edits > 1 { return false }
        if a.count == b.count {
            if i + 1 < a.count && a[i] == b[j + 1] && a[i + 1] == b[j] { i += 2; j += 2 }
            else { i += 1; j += 1 }
        } else if a.count > b.count { i += 1 } else { j += 1 }
    }
    return edits + (a.count - i) + (b.count - j) <= 1
}
struct SearchEntry: Codable {
    let emoji: Emoji
    let title: String
    let names: [String]
    let nameWords: Set<String>
    let keywords: Set<String>
    func score(_ query: String) -> Int {
        if query == emoji.emoji || emojiKey(query) == emojiKey(emoji.emoji) { return 1100 }
        if names.contains(query) { return 1000 }
        if names.contains(where: { $0.hasPrefix(query) }) { return 800 }
        let tokens = words(query)
        guard !tokens.isEmpty else { return 0 }
        if tokens.allSatisfy({ nameWords.contains($0) }) { return 700 }
        if tokens.allSatisfy({ keywords.contains($0) }) { return 600 }
        if tokens.allSatisfy({ token in keywords.contains { $0.hasPrefix(token) } }) { return 400 }
        // Substring matching supports scripts that do not separate words with spaces.
        if query.count >= 2 && names.contains(where: { $0.contains(query) }) { return 300 }
        if query.count >= 3 && names.contains(where: { oneEdit(query, $0) }) { return 250 }
        if tokens.allSatisfy({ token in
            keywords.contains(token) || (token.count >= 3 && keywords.contains { oneEdit(token, $0) })
        }) { return 200 }
        return 0
    }
}
struct Catalog {
    let emojis: [Emoji]
    let languages: [Language]
    let directory: URL
    init(directory: URL) throws {
        self.directory = directory
        emojis = try JSONDecoder().decode([Emoji].self, from: Data(contentsOf: directory.appendingPathComponent("emoji.json")))
        languages = try JSONDecoder().decode([Language].self, from: Data(contentsOf: directory.appendingPathComponent("languages.json")))
    }
    func entries(settings: Settings) throws -> [SearchEntry] {
        let available = Set(languages.map(\.code))
        let searchCodes = Set(settings.languages + ["en"]).intersection(available)
        let codes = searchCodes.union([settings.displayLanguage]).intersection(available)
        var annotations: [String: [String: Annotation]] = [:]
        for code in codes {
            annotations[code] = try JSONDecoder().decode([String: Annotation].self, from: Data(contentsOf: directory.appendingPathComponent("locales/\(code).json")))
        }
        return emojis.map { emoji in
            let key = emojiKey(emoji.emoji)
            var names = [emoji.name]
            var tags = [emoji.group]
            for code in searchCodes.sorted() {
                if let a = annotations[code]?[key] {
                    if let name = a.name { names.append(name) }
                    tags += a.tags
                }
            }
            let title = annotations[settings.displayLanguage]?[key]?.name ?? emoji.name
            if !names.contains(title) { names.append(title) }
            return SearchEntry(emoji: emoji, title: title, names: names.map(normalize),
                               nameWords: Set(names.flatMap(words)), keywords: Set((names + tags).flatMap(words)))
        }
    }
}
func search(_ entries: [SearchEntry], query: String, usage: [String: Usage], limit: Int = 40) -> [SearchEntry] {
    let query = normalize(query)
    return entries.enumerated().compactMap { index, entry -> (SearchEntry, Int, Int)? in
        let score = query.isEmpty ? 1 : entry.score(query)
        return score > 0 ? (entry, score, index) : nil
    }.sorted { a, b in
        if a.1 != b.1 { return a.1 > b.1 }
        let ua = usage[a.0.emoji.emoji], ub = usage[b.0.emoji.emoji]
        if (ua?.count ?? 0) != (ub?.count ?? 0) { return (ua?.count ?? 0) > (ub?.count ?? 0) }
        if (ua?.last ?? 0) != (ub?.last ?? 0) { return (ua?.last ?? 0) > (ub?.last ?? 0) }
        return a.2 < b.2
    }.prefix(limit).map { $0.0 }
}

// Keep match ranges in the original title so folded accents retain their spelling.
func highlightedCaption(_ title: String, query: String) -> String {
    let original = title as NSString
    var matches = IndexSet()
    for token in Set(query.split(whereSeparator: { $0.isWhitespace })) {
        var start = 0
        while start < original.length {
            let range = original.range(of: String(token), options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                       range: NSRange(location: start, length: original.length - start))
            guard range.location != NSNotFound, range.length > 0 else { break }
            let end = NSMaxRange(range)
            matches.insert(integersIn: range.location..<end)
            start = end
        }
    }
    let syntax = CharacterSet(charactersIn: "\\`*_{}[]<>()#+-.!|~>")
    func escaped(_ range: NSRange) -> String {
        original.substring(with: range).unicodeScalars.map { scalar in
            syntax.contains(scalar) ? "\\" + String(scalar) : String(scalar)
        }.joined()
    }
    var caption = ""
    var offset = 0
    for range in matches.rangeView {
        caption += escaped(NSRange(location: offset, length: range.lowerBound - offset))
        caption += "**" + escaped(NSRange(location: range.lowerBound, length: range.count)) + "**"
        offset = range.upperBound
    }
    return caption + escaped(NSRange(location: offset, length: original.length - offset))
}
