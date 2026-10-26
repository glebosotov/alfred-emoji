import Foundation

final class AnnotationParser: NSObject, XMLParserDelegate {
    var result: [String: Annotation] = [:]
    var cp: String?, kind: String?, content = ""
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if element == "annotation" { cp = attributes["cp"]; kind = attributes["type"]; content = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if cp != nil { content += string } }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        guard element == "annotation", let cp else { return }
        defer { self.cp = nil }
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "↑↑↑", value != "∅∅∅" else { return }
        let key = emojiKey(cp)
        var a = result[key] ?? Annotation(name: nil, tags: [])
        if kind == "tts" { a.name = value } else { a.tags = value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
        result[key] = a
    }
}
final class ParentParser: NSObject, XMLParserDelegate {
    var parents: [String: String] = [:]
    var component: String?
    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if e == "parentLocales" { component = a["component"] }
        if e == "parentLocale", component == nil, let parent = a["parent"], let locales = a["locales"] {
            for code in locales.split(separator: " ") { parents[String(code)] = parent }
        }
    }
}
final class LanguageNamesParser: NSObject, XMLParserDelegate {
    var names: [String: String] = [:]
    var code: String?, content = ""
    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if e == "language", a["alt"] == nil { code = a["type"]; content = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { if code != nil { content += s } }
    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        if e == "language", let code { if content != "↑↑↑" { names[code] = content }; self.code = nil }
    }
}

@main struct GenerateData {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { fatalError("Usage: generate-data CLDR_COMMON EMOJI_TEST OUTPUT") }
        let common = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[3])
        let fm = FileManager.default
        try fm.createDirectory(at: output.appendingPathComponent("locales"), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func write<T: Encodable>(_ value: T, _ file: String) throws { try encoder.encode(value).write(to: output.appendingPathComponent(file), options: .atomic) }
        let source = try String(contentsOfFile: args[2], encoding: .utf8)
        var group = "", emojis: [Emoji] = []
        for line in source.components(separatedBy: .newlines) {
            if line.hasPrefix("# group: ") { group = String(line.dropFirst(9)) }
            guard line.contains("; fully-qualified"), let hash = line.firstIndex(of: "#") else { continue }
            let fields = line[line.index(after: hash)...].split(separator: " ", maxSplits: 2)
            if fields.count == 3 { emojis.append(Emoji(emoji: String(fields[0]), name: String(fields[2]), group: group)) }
        }
        guard emojis.count > 3000 else { fatalError("Unexpected Unicode emoji data") }
        try write(emojis, "emoji.json")
        let valid = Set(emojis.map { emojiKey($0.emoji) })
        var raw: [String: [String: Annotation]] = [:]
        for folder in ["annotations", "annotationsDerived"] {
            for file in try fm.contentsOfDirectory(at: common.appendingPathComponent(folder), includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) where file.pathExtension == "xml" {
                let code = file.deletingPathExtension().lastPathComponent
                let delegate = AnnotationParser(), parser = XMLParser(contentsOf: file)!
                parser.delegate = delegate
                guard parser.parse() else { throw parser.parserError! }
                var existing = raw[code] ?? [:]
                for (key, a) in delegate.result where valid.contains(key) {
                    let old = existing[key]
                    existing[key] = Annotation(name: a.name ?? old?.name, tags: a.tags.isEmpty ? old?.tags ?? [] : a.tags)
                }
                raw[code] = existing
            }
        }
        let pd = ParentParser(), pp = XMLParser(contentsOf: common.appendingPathComponent("supplemental/supplementalData.xml"))!
        pp.delegate = pd
        guard pp.parse() else { throw pp.parserError! }
        var resolved: [String: [String: Annotation]] = [:]
        func resolve(_ code: String, seen: Set<String> = []) -> [String: Annotation] {
            if let cached = resolved[code] { return cached }
            if seen.contains(code) { return [:] }
            let parent = pd.parents[code] ?? (code.contains("_") ? code.split(separator: "_").dropLast().joined(separator: "_") : "root")
            var result = code == "root" ? [:] : resolve(parent, seen: seen.union([code]))
            for (key, a) in raw[code] ?? [:] {
                let old = result[key]
                result[key] = Annotation(name: a.name ?? old?.name, tags: a.tags.isEmpty ? old?.tags ?? [] : a.tags)
            }
            resolved[code] = result
            return result
        }
        func languageNames(_ code: String) -> [String: String] {
            let file = common.appendingPathComponent("main/\(code).xml")
            guard let parser = XMLParser(contentsOf: file) else { return [:] }
            let delegate = LanguageNamesParser(); parser.delegate = delegate
            guard parser.parse() else { return [:] }
            return delegate.names
        }
        let englishNames = languageNames("en")
        var languages: [Language] = []
        for code in raw.keys.sorted() where code != "root" {
            let annotations = resolve(code)
            guard !annotations.isEmpty else { continue }
            try write(annotations, "locales/\(code).json")
            let base = String(code.split(separator: "_")[0])
            let localNames = languageNames(code)
            let baseNames = code == base ? localNames : languageNames(base)
            let english = englishNames[code] ?? englishNames[base] ?? code
            let native = localNames[code] ?? localNames[base] ?? baseNames[base] ?? english
            let suffix = code == base ? "" : " (\(code))"
            languages.append(Language(code: code, name: english + suffix, nativeName: native + suffix))
        }
        try write(languages, "languages.json")
        print("Generated \(emojis.count) emoji and \(languages.count) locales")
    }
}
