import Foundation
import AppKit

@main struct Integration {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath)
        let folder = root.appendingPathComponent(".build/integration-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        var env = ProcessInfo.processInfo.environment
        env["EMOJI_DATA"] = root.appendingPathComponent("data").path
        env["alfred_workflow_data"] = folder.appendingPathComponent("state").path
        env["alfred_workflow_cache"] = folder.appendingPathComponent("cache").path
        func run(_ command: String, _ argument: String) throws -> Data {
            let p = Process(), pipe = Pipe()
            p.executableURL = root.appendingPathComponent(".build/emoji")
            p.arguments = [command, argument]; p.environment = env; p.standardOutput = pipe
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            precondition(p.terminationStatus == 0, "CLI failed: \(command)")
            return data
        }
        func require(_ condition: Bool) { precondition(condition) }
        func items(_ data: Data) throws -> [[String: Any]] {
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            precondition(json["skipknowledge"] as? Bool == true)
            return json["items"] as! [[String: Any]]
        }
        _ = try run("set-display", "en")
        var langs = try items(run("languages", "ru"))
        if !(langs.first { $0["arg"] as? String == "ru" }!["title"] as! String).hasPrefix("✓") { _ = try run("toggle-language", "ru") }
        for query in ["eyes", "глаза", "eeys"] {
            let start = Date()
            let result = try items(run("search", query))
            precondition(result.first?["arg"] as? String == "👀", query)
            precondition(result.first?["subtitle"] as? String == "", "Clean subtitles by default")
            let icon = (result[0]["icon"] as! [String: String])["path"]!
            let png = try Data(contentsOf: URL(fileURLWithPath: icon))
            precondition(png.starts(with: [137,80,78,71]), "PNG icon")
            let bitmap = NSBitmapImageRep(data: png)!
            var visible = 0, minX = 128, maxX = 0
            for y in 0..<128 { for x in 0..<128 {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if alpha > 0.01 { visible += 1; minX = min(minX,x); maxX = max(maxX,x); precondition(x > 0 && y > 0 && x < 127 && y < 127, "Icon must not clip") }
            } }
            precondition(maxX - minX >= 118, "Emoji artwork fills the icon area")
            precondition(visible > 3000, "Large nonempty emoji artwork")
            print("CLI \(query): \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        }
        let warmStart = Date()
        for _ in 0..<5 { _ = try run("search", "eyes") }
        print("Warm CLI eyes average: \(Int(Date().timeIntervalSince(warmStart) * 200)) ms")
        _ = try run("record", "🤩")
        require(try items(run("search", "")).first?["arg"] as? String == "🤩")
        require(try items(run("search", "eyes")).first?["arg"] as? String == "👀")
        _ = try run("toggle-language", "ru")
        require(try items(run("search", "глаза")).first?["valid"] as? Bool == false)
        _ = try run("toggle-language", "de")
        require(try items(run("search", "Augen")).first?["arg"] as? String == "👀")
        _ = try run("set-display", "de")
        require(try items(run("search", "eyes")).first?["title"] as? String == "Augen")
        langs = try items(run("languages", "en"))
        precondition(langs.first { $0["arg"] as? String == "en" }?["valid"] as? Bool == false)
        let plistURL = root.appendingPathComponent("dist/Emoji.alfredworkflow.contents/info.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
        let objects = plist["objects"] as! [[String: Any]]
        let ids = Set(objects.map { $0["uid"] as! String })
        for (source, links) in plist["connections"] as! [String: [[String: Any]]] {
            precondition(ids.contains(source))
            for link in links { precondition(ids.contains(link["destinationuid"] as! String)) }
        }
        let config = plist["userconfigurationconfig"] as! [[String: Any]]
        precondition(config.count == 4)
        let links = plist["connections"] as! [String: [[String: Any]]]
        precondition(links["hotkey"]?.first?["destinationuid"] as? String == "search")
        precondition(links["record-paste"]?.first?["destinationuid"] as? String == "paste")
        let paste = objects.first { $0["uid"] as? String == "paste" }!["config"] as! [String: Any]
        precondition(paste["transient"] as? Bool == true)
        env["result_limit"] = "20"
        require(try items(run("search", "")).count == 20)
        env["subtitle_style"] = "english"
        require(try items(run("search", "eyes")).first?["subtitle"] as? String == "eyes")
        print("CLI state, icons, configuration, multilingual search, history and workflow graph passed")
    }
}
