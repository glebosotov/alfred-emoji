import Foundation
import AppKit
import Darwin

let env = ProcessInfo.processInfo.environment
let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
let dataURL = URL(fileURLWithPath: env["EMOJI_DATA"] ?? root.appendingPathComponent("data").path)
let stateURL = URL(fileURLWithPath: env["alfred_workflow_data"] ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Alfred Emoji").path)
let cacheURL = URL(fileURLWithPath: env["alfred_workflow_cache"] ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Alfred Emoji").path)
let command = CommandLine.arguments.dropFirst().first ?? "search"
let argument = CommandLine.arguments.dropFirst(2).first ?? ""
let decoder = JSONDecoder(), encoder = JSONEncoder()
func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
    let url = stateURL.appendingPathComponent(name)
    guard fm.fileExists(atPath: url.path) else { return nil }
    return try decoder.decode(type, from: Data(contentsOf: url))
}
func save<T: Encodable>(_ value: T, _ name: String) throws {
    try fm.createDirectory(at: stateURL, withIntermediateDirectories: true)
    try encoder.encode(value).write(to: stateURL.appendingPathComponent(name), options: .atomic)
}
// Lock mutations across Alfred action processes; search reads atomic snapshots.
func mutate(_ body: () throws -> Void) throws {
    try fm.createDirectory(at: stateURL, withIntermediateDirectories: true)
    let fd = open(stateURL.appendingPathComponent("state.lock").path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { flock(fd, LOCK_UN) }
    try body()
}
func output(_ items: [[String: Any]]) throws {
    let data = try JSONSerialization.data(withJSONObject: ["items": items, "skipknowledge": true], options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
}
func icon(_ emoji: Emoji) throws -> String {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let folder = cacheURL.appendingPathComponent("icons-v3-\(env["icon_size"] ?? "120")-\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    let file = folder.appendingPathComponent(emoji.id + ".png")
    if fm.fileExists(atPath: file.path) { return file.path }
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw NSError(domain: "EmojiIcon", code: 1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 128, height: 128).fill()
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Apple Color Emoji", size: 96) ?? NSFont.systemFont(ofSize: 96)]
    let text = emoji.emoji as NSString
    let size = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (128 - size.width) / 2, y: (128 - size.height) / 2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    // Fit the visible glyph, rather than the font's padded line box, to the icon.
    var minX = 128, minY = 128, maxX = -1, maxY = -1
    for y in 0..<128 { for x in 0..<128 {
        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
        }
    } }
    let rendered = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let renderContext = NSGraphicsContext(bitmapImageRep: rendered)!.cgContext
    if maxX >= minX, let image = bitmap.cgImage?.cropping(to: CGRect(x: minX, y: minY, width: maxX-minX+1, height: maxY-minY+1)) {
        let extent = CGFloat(min(124, max(88, Int(env["icon_size"] ?? "120") ?? 120)))
        let ratio = extent / CGFloat(max(image.width, image.height))
        let width = CGFloat(image.width) * ratio, height = CGFloat(image.height) * ratio
        renderContext.clear(CGRect(x: 0, y: 0, width: 128, height: 128))
        renderContext.interpolationQuality = .high
        renderContext.draw(image, in: CGRect(x: (128-width)/2, y: (128-height)/2, width: width, height: height))
    }
    guard let png = rendered.representation(using: .png, properties: [:]) else { throw NSError(domain: "EmojiIcon", code: 2) }
    try png.write(to: file, options: .atomic)
    return file.path
}
func defaultSettings(_ catalog: Catalog) -> Settings {
    let available = Set(catalog.languages.map(\.code))
    var codes = ["en"]
    for locale in Locale.preferredLanguages {
        let normalized = locale.replacingOccurrences(of: "-", with: "_")
        let code = available.contains(normalized) ? normalized : String(normalized.split(separator: "_").first ?? "en")
        if available.contains(code), !codes.contains(code) { codes.append(code) }
    }
    return Settings(languages: codes, displayLanguage: "en")
}
do {
    let catalog = try Catalog(directory: dataURL)
    let settings = try load(Settings.self, "settings.json") ?? defaultSettings(catalog)
    switch command {
    case "search":
        struct CachedIndex: Codable { let key: String; let entries: [SearchEntry] }
        let key = "cldr48.2-emoji17-index1|" + settings.languages.sorted().joined(separator: ",") + "|" + settings.displayLanguage
        let indexURL = cacheURL.appendingPathComponent("search-index.json")
        let entries: [SearchEntry]
        if let bytes = try? Data(contentsOf: indexURL), let index = try? decoder.decode(CachedIndex.self, from: bytes), index.key == key {
            entries = index.entries
        } else {
            entries = try catalog.entries(settings: settings)
            try fm.createDirectory(at: cacheURL, withIntermediateDirectories: true)
            try encoder.encode(CachedIndex(key: key, entries: entries)).write(to: indexURL, options: .atomic)
        }
        let usage = try load([String: Usage].self, "usage.json") ?? [:]
        let results = search(entries, query: argument, usage: usage, limit: min(100, max(10, Int(env["result_limit"] ?? "40") ?? 40)))
        let items: [[String: Any]] = try results.map { entry in
            ["title": entry.title, "subtitle": env["subtitle_style"] == "english" && entry.title != entry.emoji.name ? entry.emoji.name : "", "arg": entry.emoji.emoji,
             "icon": ["path": try icon(entry.emoji)], "text": ["copy": entry.emoji.emoji, "largetype": entry.emoji.emoji],
             "mods": ["cmd": ["arg": entry.emoji.emoji]]]
        }
        try output(items.isEmpty ? [["title": "No matching emoji", "subtitle": "Use emojilang to enable more search languages", "valid": false]] : items)
    case "languages", "display-languages":
        let query = normalize(argument)
        let display = command == "display-languages"
        let languages = catalog.languages.filter {
            query.isEmpty || normalize("\($0.code) \($0.name) \($0.nativeName)").contains(query)
        }.sorted { a, b in
            let sa = display ? a.code == settings.displayLanguage : settings.languages.contains(a.code) || a.code == "en"
            let sb = display ? b.code == settings.displayLanguage : settings.languages.contains(b.code) || b.code == "en"
            if sa != sb { return sa }
            return a.name < b.name
        }
        try output(languages.map { lang in
            let on = display ? lang.code == settings.displayLanguage : settings.languages.contains(lang.code) || lang.code == "en"
            return ["title": "\(on ? "✓" : "○") \(lang.nativeName)",
                    "subtitle": "\(lang.name) · \(lang.code) · \(display ? "Set display language" : lang.code == "en" ? "English is always searchable" : on ? "Disable search language" : "Enable search language")",
                    "arg": lang.code, "valid": display || lang.code != "en"]
        })
    case "toggle-language", "set-display":
        guard catalog.languages.contains(where: { $0.code == argument }) else { throw NSError(domain: "Unknown language", code: 1) }
        try mutate {
            var current = try load(Settings.self, "settings.json") ?? defaultSettings(catalog)
            if command == "set-display" { current.displayLanguage = argument }
            else if argument != "en" {
                if current.languages.contains(argument) { current.languages.removeAll { $0 == argument } }
                else { current.languages.append(argument) }
            }
            try save(current, "settings.json")
        }
    case "render-icon":
        guard let emoji = catalog.emojis.first(where: { $0.emoji == argument }) else { throw NSError(domain: "Unknown emoji", code: 1) }
        FileHandle.standardOutput.write(try Data(contentsOf: URL(fileURLWithPath: icon(emoji))))
    case "record":
        guard catalog.emojis.contains(where: { $0.emoji == argument }) else { throw NSError(domain: "Unknown emoji", code: 1) }
        try mutate {
            var usage = try load([String: Usage].self, "usage.json") ?? [:]
            usage[argument] = Usage(count: (usage[argument]?.count ?? 0) + 1, last: Date().timeIntervalSince1970)
            try save(usage, "usage.json")
        }
        FileHandle.standardOutput.write(Data(argument.utf8))
    default: throw NSError(domain: "Unknown command: \(command)", code: 1)
    }
} catch {
    FileHandle.standardError.write(Data("Alfred Emoji: \(error)\n".utf8))
    if ["search", "languages", "display-languages"].contains(command) {
        try? output([["title": "Emoji could not load", "subtitle": "Open Alfred's workflow debugger for details", "valid": false]])
    }
    exit(1)
}
