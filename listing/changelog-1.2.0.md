# FL Progress Tracker 1.2.0

**Target release date:** 2026-11-04 (WoW Forever launch day).

First release under the name **FL Progress Tracker** (previously distributed by hand as "ForeverLedger").

### Changed
- Renamed: add-on folder and TOC are now `fl-progress-tracker`; in-game title "FL Progress Tracker". `/fl` commands are unchanged.
- Errors are grouped by a version-independent fingerprint.

### Added
- Account linking: `/fl link CODE` after signing in at foreverledger.net with Battle.net.
- Error reports for linked accounts (no personal data); opt out with `/fl share off`. Shown once at first login.
- Richer error capture: trigger, zone type, combat, after-patch, severity, OS major version, locale and loaded add-ons.
- Optional Linux/Wine marker for error reports (`/fl share wine`, opt-in).

### Fixed
- Only blocked actions caused by FL Progress Tracker itself are recorded as taint.

### Upgrading from ForeverLedger
Delete `Interface\AddOns\ForeverLedger`. To keep recorded history, with the game closed rename
`WTF\Account\<ACCOUNT>\SavedVariables\ForeverLedger.lua` → `fl-progress-tracker.lua`.
