import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
func filter(_ id: String, _ keyword: String, _ title: String, _ command: String) -> [String: Any] {
    ["uid": id, "type": "alfred.workflow.input.scriptfilter", "version": 3,
     "config": ["keyword": keyword, "title": title, "subtext": "Offline multilingual emoji search", "runningsubtext": "",
                "withspace": true, "argumenttype": 2, "argumenttrimmode": 0, "argumenttreatemptyqueryasnil": false,
                "alfredfiltersresults": false, "script": "./emoji \(command) \"$1\"", "scriptfile": "", "type": 0,
                "scriptargtype": 1, "escaping": 0, "queuemode": 1, "queuedelaymode": 0,
                "queuedelaycustom": 0.1, "queuedelayimmediatelyinitially": true]]
}
func script(_ id: String, _ command: String) -> [String: Any] {
    ["uid": id, "type": "alfred.workflow.action.script", "version": 2,
     "config": ["script": "./emoji \(command) \"$1\"", "scriptfile": "", "type": 0, "scriptargtype": 1, "escaping": 0]]
}
func clipboard(_ id: String, _ paste: Bool) -> [String: Any] {
    ["uid": id, "type": "alfred.workflow.output.clipboard", "version": 3,
     "config": ["autopaste": paste, "clipboardtext": "{query}", "ignoredynamicplaceholders": true, "transient": paste]]
}
func reopen(_ id: String, _ query: String) -> [String: Any] {
    ["uid": id, "type": "alfred.workflow.action.script", "version": 2,
     "config": ["script": "/usr/bin/osascript -e 'tell application id \"com.runningwithcrayons.Alfred\" to search \"\(query)\"'", "type": 0, "scriptargtype": 1, "escaping": 0, "scriptfile": ""]]
}
func link(_ id: String, modifiers: Int = 0) -> [String: Any] {
    ["destinationuid": id, "modifiers": modifiers, "modifiersubtext": "", "vitoclose": false]
}
let hotkey: [String: Any] = ["uid": "hotkey", "type": "alfred.workflow.trigger.hotkey", "version": 2,
    "config": ["action": 0, "argument": 0, "focusedappvariable": false, "focusedappvariablename": "",
               "leftcursor": false, "modsmode": 0, "relatedAppsMode": 0]]
func setting(_ variable: String, _ label: String, _ description: String, _ type: String, _ config: [String: Any]) -> [String: Any] {
    ["variable": variable, "label": label, "description": description, "type": type, "config": config]
}
let configuration = [
    setting("keyword", "Search keyword", "Open emoji search. A hotkey can also be assigned on the workflow canvas.", "textfield", ["default": "em", "required": true, "trim": true]),
    setting("subtitle_style", "Result subtitles", "Keep results clean, or show English names below translated labels.", "popupbutton", ["default": "none", "pairs": [["Hidden", "none"], ["English translation", "english"]]]),
    setting("icon_size", "Emoji size", "Artwork size within Alfred's icon area. Row size is controlled by your Alfred theme.", "popupbutton", ["default": "120", "pairs": [["Large", "120"], ["Medium", "108"], ["Small", "96"]]]),
    setting("result_limit", "Maximum results", "Limit the number of search results.", "popupbutton", ["default": "40", "pairs": [["20", "20"], ["40", "40"], ["80", "80"]]])
]
let objects = [hotkey, filter("search", "{var:keyword}", "Search Emoji", "search"),
               filter("languages", "emojilang", "Emoji Search Languages", "languages"),
               filter("display", "emojidisplay", "Emoji Display Language", "display-languages"),
               script("record-paste", "record"), script("record-copy", "record"),
               clipboard("paste", true), clipboard("copy", false),
               script("toggle", "toggle-language"), script("set-display", "set-display"),
               reopen("reopen-languages", "emojilang "), reopen("reopen-display", "emojidisplay ")]
let plist: [String: Any] = [
    "bundleid": "com.glebosotov.alfred-emoji", "name": "Emoji", "version": "0.2.1",
    "createdby": "Gleb Osotov", "webaddress": "https://github.com/glebosotov/alfred-emoji", "description": "Fast offline emoji search in 164 languages, with typo tolerance and native macOS artwork.", "disabled": false,
    "category": "Productivity", "userconfigurationconfig": configuration,
    "readme": """
    # Emoji

    Search 3,944 emoji offline in multiple languages, with exact-name priority and typo tolerance.

    ## Start
    Type your search keyword (default `em`), or assign a shortcut to the Hotkey trigger on the canvas.
    Return uses Alfred’s native paste action, which also places the emoji on the clipboard. Command-Return only copies.
    Pasted emoji are marked transient to keep them out of clipboard history; the current clipboard still changes.

    ## Languages
    `emojilang` toggles multiple search languages; English is always available.
    `emojidisplay` selects the label language. Search languages initially follow macOS preferences.

    ## Appearance
    Configure emoji size, optional English subtitles, result count and the search keyword below.
    Alfred's theme controls row height and the overall icon area.

    ## Requirements and privacy
    Alfred 5 Powerpack and macOS 13+. Apple Silicon and Intel are included in the portable package.
    No Python, Pillow, Homebrew or Nix runtime required. No network requests.
    Language settings and usage stay locally in Alfred's workflow data; indexes and icons are disposable caches.
    Unicode 17.0 / CLDR 48.2 data is included under Unicode License v3.
    """,
    "objects": objects,
    "connections": ["hotkey": [link("search")], "search": [link("record-paste"), link("record-copy", modifiers: 1048576)],
                    "record-paste": [link("paste")], "record-copy": [link("copy")],
                    "languages": [link("toggle")], "toggle": [link("reopen-languages")],
                    "display": [link("set-display")], "set-display": [link("reopen-display")]],
    "uidata": Dictionary(uniqueKeysWithValues: objects.enumerated().map { i, o in
        (o["uid"] as! String, ["xpos": 60 + (i % 4) * 220, "ypos": 60 + (i / 4) * 160])
    })
]
try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: destination.appendingPathComponent("info.plist"))
