# CurseForge listing draft — FL Progress Tracker

**Project name:** FL Progress Tracker
**Slug (requested):** fl-progress-tracker
**Game / flavor:** World of Warcraft → WoW Forever (Interface 16001, client 1.60.1)
**License:** MIT
**Icon:** listing/icon_400.png (400×400)

## Summary (one sentence, ≤ 100 chars)
Read-only tracker that saves your characters' quests, gear, professions and guild for an offline dashboard.

## Description

**FL Progress Tracker** is a free, read-only add-on that keeps a local record of your own characters' progress so you can review it outside the game.

### What it does
- Records what your client already shows you: level, XP, zone, equipped gear, quest log and completed quests, professions, guild, achievements and Legacy points.
- Saves everything to the add-on's SavedVariables file when you `/reload`, log out or exit — nothing is sent anywhere from inside the game.
- Watch list for specific quests (`/fl watch <id>`), built-in error log (`/fl errors`) and a health monitor (`/fl health`) that checks the add-on's own memory use.
- **No automation.** It never clicks, casts, loots, trades or plays for you.

### Your data stays local
The add-on makes no network calls. Your data stays in your `WTF` folder on your PC until **you** choose to upload it — either by dragging the file onto the Account page at https://www.foreverledger.net/ or with the optional companion uploader. The dashboard then shows quests by zone/class/status, maps, gear and guild progress.

### Free, no ads, no donation prompts
FL Progress Tracker is completely free. In line with Blizzard's UI Add-On Development Policy, the add-on contains no advertisements, no paywalled features and no in-game donation requests.

### Slash commands
- `/fl` — summary + help
- `/fl errors [count]`, `/fl clearerrors` — view / clear recorded Lua errors
- `/fl health` — memory / leak status
- `/fl watch <id>`, `/fl unwatch <id>`, `/fl watchlist` — quest watch list
- `/fl leaderboard on|off` — opt in/out of the public leaderboard (off by default)
- `/fl link CODE` — pair with your foreverledger.net account
- `/fl share on|off|battletag|battletag off` — sharing options

### Install
**With the CurseForge app or WowUp:** search for "FL Progress Tracker", choose the WoW Forever install, click Install.

**Manually:**
1. Close the game and download the zip.
2. Extract it into `World of Warcraft\_forever_\Interface\AddOns\` so you get `Interface\AddOns\fl-progress-tracker\fl-progress-tracker.toc` (not a doubled folder).
3. Start the game, open **AddOns** on character select and tick **FL Progress Tracker**.
4. Log in, then `/reload` (or log out) to write your first snapshot.

**Upgrading from the old "ForeverLedger" folder:** delete `Interface\AddOns\ForeverLedger`, install this one, and (to keep history) rename `WTF\Account\<ACCOUNT>\SavedVariables\ForeverLedger.lua` to `fl-progress-tracker.lua` while the game is closed.

### Links
- Dashboard & help: https://www.foreverledger.net/
- Source & issues: GitHub (link added once the repo is public)

*Fan-made. Not affiliated with or endorsed by Blizzard Entertainment.*

## Categories / tags (suggested)
- Primary: **Quests & Leveling**
- Additional: **Data Export**, **Achievements**, **Professions**, **Guild**
- Tags/keywords: progress tracker, quest tracker, character tracker, quest log, completed quests, gear, professions, guild, achievements, dashboard, WoW Forever
