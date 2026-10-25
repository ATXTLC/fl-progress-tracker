# Changelog

All notable changes to the FL Progress Tracker add-on (formerly ForeverLedger). Format: Keep a Changelog; versions: SemVer.

## [1.2.0] - 2026-11-04

### Added
- Account linking: type /fl link CODE after logging in on the site with your BattleTag.
- Error reports are on by default for linked accounts and hold no personal data; opt out with /fl share off. Shown once at first login.
- Richer error capture: trigger, zone type, combat, after-patch, severity, OS major version, locale and loaded add-ons.
- Optional Linux-Wine marker for error reports (/fl share wine, opt-in).

### Changed
- Errors are grouped by a version-independent fingerprint.

### Fixed
- Only blocked actions caused by FL Progress Tracker itself are recorded as taint.

## [1.1.0] - unreleased (staged — not released; awaiting review)

### Added
- Local Lua error capture: errors are saved to SavedVariables (deduplicated, capped), and the previous error handler (e.g. BugSack) still runs.
- /fl errors shows recent errors in a copy window; /fl errors clear (or /fl clearerrors) empties the list.
- Health monitor (Health.lua): watches FL Progress Tracker's own memory for leaks, oversized SavedVariables and runaway events; /fl health shows the status.
- One-time What's new message in chat after an update (WhatsNew.lua).

### Changed
- The PC companion dashboard shows captured add-on errors in a local-only Errors view.

### Known issues
- Not yet run in a WoW Forever client.
- No public download yet.

## [1.0.0] - unreleased (initial version — release date not recorded)

### Added
- Read-only snapshots saved to SavedVariables: name, realm, race, class, faction, level, XP and rested XP, gold, zone.
- Equipped gear, professions/skills, quest log objectives and completed quest IDs.
- Guild name, rank, MOTD, info text and roster (with last online).

### Known issues
- Not yet run in a WoW Forever client; the Interface number (16001) is a guess until launch.
- Assumes an English client for some text.
- The _forever_ client folder name is unconfirmed until the Nov 4 launch.
- No automation: the add-on only reads and saves; it never clicks or plays for you.
