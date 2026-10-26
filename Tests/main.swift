import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); failures += 1 }
}
let catalog = try Catalog(directory: URL(fileURLWithPath: "data"))
let entries = try catalog.entries(settings: Settings(languages: ["en", "ru"], displayLanguage: "en"))
let noisyHistory = ["🤩": Usage(count: 100000, last: Date().timeIntervalSince1970)]
for query in ["eyes", "глаза", "EYES", "  eyes  ", "eeys", "eyse", "eyss", "глза", "👀"] {
    check(search(entries, query: query, usage: noisyHistory).first?.emoji.emoji == "👀", "Exact/fuzzy eyes: \(query)")
}
check(search(entries, query: "zzzzzzzzzzzz", usage: [:]).isEmpty, "Unrelated query must not match")
check(search(entries, query: "", usage: noisyHistory).first?.emoji.emoji == "🤩", "History on empty query")
let onlyEnglish = try catalog.entries(settings: Settings(languages: ["en"], displayLanguage: "en"))
check(search(onlyEnglish, query: "глаза", usage: [:]).isEmpty, "Disabled languages excluded")
let russian = try catalog.entries(settings: Settings(languages: ["ru"], displayLanguage: "ru"))
check(search(russian, query: "eyes", usage: [:]).first?.title == "глаза", "English fallback and Russian display")
check(oneEdit("eyes", "eeys"), "Transposition")
check(!oneEdit("eyes", "eeee"), "Reject two edits")
check(oneEdit("глаза", "глза"), "Unicode deletion")
check(catalog.languages.count > 100, "All CLDR annotation locales bundled")
for language in catalog.languages {
    let file = catalog.directory.appendingPathComponent("locales/\(language.code).json")
    let annotations = try JSONDecoder().decode([String: Annotation].self, from: Data(contentsOf: file))
    check(!annotations.isEmpty, "Nonempty locale \(language.code)")
}
let start = Date()
for _ in 0..<10 { _ = search(entries, query: "eyes", usage: noisyHistory) }
print("Search average: \(Date().timeIntervalSince(start) * 100) ms")
print("\(catalog.emojis.count) emoji, \(catalog.languages.count) locales; \(failures) failures")
exit(failures == 0 ? 0 : 1)
