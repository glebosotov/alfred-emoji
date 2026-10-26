# Alfred Emoji

Offline emoji search for Alfred 5 Powerpack on macOS 13 or newer.
Search multiple languages simultaneously, tolerate single-character typos and
adjacent transpositions, and keep exact names above keyword matches.

## Install and use

Download [Emoji.alfredworkflow from the latest release](https://github.com/glebosotov/alfred-emoji/releases/latest/download/Emoji.alfredworkflow)
and open it in Alfred. The portable build contains both
Apple Silicon and Intel code; users need no Nix, Homebrew, Python or Pillow.

- `em <query>` searches the enabled languages. Enter uses Alfred’s native paste action; Command-Enter only copies.
- Assign a shortcut to the Hotkey trigger on the workflow canvas.
- Configure Workflow controls the keyword, emoji size, subtitles and result limit.
- `emojilang` toggles search languages individually. A checkmark means enabled.
  English always remains searchable. Initial selection follows macOS preferred
  languages where available.
- `emojidisplay` chooses the result-label language, with English fallback.
- An empty query shows most-used emoji first. Usage breaks ties within a search
  rank; it cannot outrank an exact name.

Names and keywords come from Unicode CLDR, not machine translation. Coverage
varies by locale. The bundled catalog contains 3,944 fully qualified Unicode 17
emoji and 164 nonempty CLDR 48.2 annotation locales, including regional variants.
Emoji appearance and glyph availability depend on the installed macOS font.

Search and settings work offline. AppKit renders only visible result icons and
caches them per macOS version. Settings and usage live in Alfred's workflow data
directory; disposable icons and the selected-language index live in its cache.
The workflow performs no network requests and has no persistent background process.

## Develop

This is an independent project. Its flake pins tooling; it has no dependency on
any personal machine configuration or external deployment infrastructure.

```sh
nix develop --command scripts/test.sh
nix develop --command scripts/build.sh
nix develop --command scripts/integration-test.sh
```

These commands require Apple's installed Xcode/Command Line Tools. The portable
build explicitly selects Apple's compiler and matching SDK, builds both
architectures for macOS 13+, and ad-hoc signs the result. It is not notarized.
The output is `dist/Emoji.alfredworkflow`; building never installs it.

```sh
nix build
```

The pure Nix build uses pinned Swift and SDK packages and produces a workflow
for the build machine's architecture under `result/`. Both build paths use only
system libraries at runtime. Architecture coverage and deployment targets are
not a substitute for testing on an Intel Mac or the oldest supported macOS.

`Tests/main.swift` tests ranking, typo handling, language selection, translation
fallback and catalog integrity. Integration tests use temporary state, exercise
the packaged CLI and validate the workflow graph, then remove that state. Actual
Alfred insertion, modifier routing and focus restoration require a manual check.
Native insertion also places the emoji on the clipboard. Pasted items are marked
transient to avoid adding them to clipboard history; this does not preserve the
previous clipboard contents. No clipboard snapshots or restoration timers are used.

## Data maintenance

```sh
nix develop --command scripts/update-data.sh
```

The generator verifies fixed input SHA-256 hashes and merges annotation files
with CLDR parent-locale inheritance. Generated locale files are committed so
normal builds need no Unicode download. Locale display names also come from the pinned CLDR release.
When updating the catalog or index schema, bump the cache key in `Sources/main.swift`.
Unicode data is covered by [Unicode License v3](data/UNICODE-LICENSE.txt).

Before a release, run the checks above, inspect `otool -L` for unexpected runtime
paths, and test paste/copy and language switching inside Alfred. Publishing a
release and replacing another workflow are separate actions.
