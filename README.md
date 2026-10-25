# FL Progress Tracker

Free, read-only add-on for WoW Forever (Interface 16001) that records your own characters' quests, gear, professions, guild and achievements into SavedVariables (`ForeverLedgerDB`) for the dashboard at https://www.foreverledger.net/. No automation, no in-game network calls, no ads or donation prompts.

### Install
- **Add-on managers:** CurseForge app, Wago app, or WowUp (CurseForge/Wago/GitHub sources) — search "FL Progress Tracker".
- **Manual:** download `fl-progress-tracker-<version>.zip` from [Releases](../../releases) and extract into `_forever_\Interface\AddOns\` → `AddOns\fl-progress-tracker\fl-progress-tracker.toc`.

Data file: `_forever_\WTF\Account\<ACCOUNT>\SavedVariables\fl-progress-tracker.lua` (older installs: `ForeverLedger.lua`; both are read by the dashboard and companion).

### Commands
`/fl`, `/fl errors [n]`, `/fl clearerrors`, `/fl health`, `/fl watch <id>`, `/fl unwatch <id>`, `/fl watchlist`, `/fl leaderboard on|off`, `/fl link CODE`, `/fl share …`

### Releasing
Tag `X.Y.Z` (matching `## Version` in the TOC and the top of `fl-progress-tracker/CHANGELOG.md`) and push the tag; `.github/workflows/release.yml` runs BigWigsMods/packager, uploads to CurseForge/Wago and creates a GitHub release with `release.json` (WowUp, flavor `forever`). 1.2.0 targets 2026-11-04 (WoW Forever launch day): do **not** push the `1.2.0` tag before Nov 4, 2026.

License: MIT. Fan-made; not affiliated with Blizzard Entertainment.
