# Changelog

All notable changes to Windr are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

- **PATCH** (1.1.**1**): bug fixes, no behavior change
- **MINOR** (1.**2**.0): new features, existing configs keep working
- **MAJOR** (**2**.0.0): changes that require updating your `init.lua` or your profiles

Your version: hammer icon → `Console` → `spoon.Windr.version`, or hover the Windr icon in the menu bar.

## [Unreleased]

### Added
- **Help** screen in the panel (**?** button or `?` key): what each button and icon does, drawn as in the panel.
- **Auto** switch in the panel header: re-applies a profile when screens change (display plugged or unplugged). New `autoApply` option: a profile name, `true` (the active profile, default) or `false` (off, no switch). Also `spoon.Windr:setAutoApply(on)`.

### Fixed
- Windows were resized with a seemingly random layout after waking from sleep, when a screen watcher applied a profile on every screen event. Windr's watcher ignores events while asleep, waits for displays to settle and only applies a profile when the set of screens actually changed.

## [1.2.0] - 2026-11-09

### Added
- Profiles are grouped by screen: the panel shows one tab per screen resolution, plus **All screens**. It opens on the current screen's tab; `Tab` / `⇧Tab` switches tabs. A profile appears on the screens it has a variant for; a profile with only a `default` variant appears on every screen.
- **Remove from this screen** button on a card (in a screen tab): drops only that screen's variant and keeps the profile on its other screens. Also available as `spoon.Windr:removeFromScreen(name, width)`.
- Profile shortcuts (`profileHotkeys`) and the `1`–`9` keys follow the order of the current screen's profiles.

### Changed
- Downloads now come from [GitHub Releases](https://github.com/jcsuzanne/windr/releases); the zip is no longer stored in the repo.

## [1.1.1] - 2026-10-29

### Fixed
- The panel showed its rounded corners inside a dark rectangle. The window is now fully transparent and the shadow follows the rounded panel.
- Clicking the transparent margin around the panel closes it, like any click outside.

### Added
- The menu bar icon tooltip shows the installed version.
- Docs: how to update an existing install (terminal command, by hand, or git).
- MIT license.

## [1.1.0] - 2026-10-29

### Added
- The interface follows the macOS language (English or French). The new `language` option (`"auto"`, `"en"`, `"fr"`) forces one.
- English README, with the French version moved to `README.fr.md`.
- Stable download link: `dist/Windr.zip`.

### Changed
- Code comments and documentation are in English.

## [1.0.0] - 2026-10-29

### Added
- Menu bar icon and panel listing every profile with a preview of its layout (`⌘⌥⌃Space`).
- Apply a profile with a click, keys `1`–`9`, or arrows + Enter.
- Capture the current window layout as a new profile, with a click on an app to exclude it.
- Edit a profile (remove apps from every variant, rename), replace it with the current layout, delete it after a second click to confirm.
- Reorder profiles with drag and drop.
- Per-screen variants: a profile is saved for the screen width and used as the default elsewhere.
- `profileHotkeys` option to apply profiles 1–9 with a global shortcut.
- Finder and System Settings are never captured. Apps placed in the same spot share one tile in previews.

[Unreleased]: https://github.com/jcsuzanne/windr/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/jcsuzanne/windr/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/jcsuzanne/windr/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jcsuzanne/windr/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jcsuzanne/windr/releases/tag/v1.0.0
