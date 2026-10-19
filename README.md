# Pennyworth

A native macOS launcher inspired by Alfred — Swift + AppKit, no cross-platform framework.

Named after **Alfred Pennyworth**: every Batman needs a butler, every Mac deserves one too.

## Why native

Alfred's snappiness comes from being 100% AppKit: a `.nonactivatingPanel` for the
search window, a Carbon hotkey that needs no accessibility permission, and the
system Spotlight metadata index for files. Pennyworth follows the same path.

## Quick start

```bash
./build.sh
open Pennyworth.app
```

Press **⌥Space** to summon, **Esc** (or click away) to dismiss, **↑/↓** to move,
**⏎** to launch. If ⌥Space is already owned by another app (e.g. Alfred),
Pennyworth automatically falls back to **⌥⇧Space**.

## Development

```bash
swift build          # debug build
swift test           # run unit tests
./build.sh           # release build + .app bundle
```

## Roadmap

- [x] Global hotkey (⌥Space) via Carbon `RegisterEventHotKey`
- [x] Borderless vibrancy panel (`NSPanel` + `NSVisualEffectView`)
- [x] `/Applications` scanning and launching
- [ ] Fuzzy matching with frecency ranking — see `FuzzyMatcher.swift` TODO
- [ ] File search via `NSMetadataQuery` (Spotlight index)
- [ ] Clipboard history
- [ ] Calculator
- [ ] Workflow plugin system (subprocess + stdout + JSON, Alfred-style)

## License

MIT
