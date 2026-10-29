# Changelog

All notable changes to Windr are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

- **PATCH** (1.1.**1**): bug fixes, no behavior change
- **MINOR** (1.**2**.0): new features, existing configs keep working
- **MAJOR** (**2**.0.0): changes that require updating your `init.lua` or your profiles

Your version: hammer icon → `Console` → `spoon.Windr.version`, or hover the Windr icon in the menu bar.

## [Unreleased]

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

[Unreleased]: https://github.com/jcsuzanne/windr/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/jcsuzanne/windr/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jcsuzanne/windr/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jcsuzanne/windr/releases/tag/v1.0.0
