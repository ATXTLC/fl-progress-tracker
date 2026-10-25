-- ForeverLedger "What's new": prints a short chat-frame note once per new add-on version, on login.
-- Chat text only (no popups, no network). Remembers the last version shown in ForeverLedgerDB.whatsNewSeen.
-- Keep NOTES in sync with server/static/changelog.json (tests check the top version matches the .toc).
local ADDON_NAME = ...
local NOTES = {
  ["1.2.0"] = {
    "Link your account: log in on foreverledger.net with your BattleTag, then /fl link CODE.",
    "Error reports are ON by default for linked accounts (no personal data). Opt out: /fl share off.",
  },
  ["1.1.0"] = {
    "Records Lua errors locally: type /fl errors to view and copy them into an Error/bug report.",
    "Health monitor: /fl health shows memory/leak status for FL Progress Tracker.",
    "Shows this one-time What's new note after an update.",
  },
  ["1.0.0"] = {
    "First release: read-only snapshots of level, XP, zone, gear, professions, quests and guild roster.",
  },
}
local function version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return (get and get(ADDON_NAME or "fl-progress-tracker", "Version")) or "?"
end
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  local ok = pcall(function()
    ForeverLedgerDB = ForeverLedgerDB or {}
    local v = version()
    if ForeverLedgerDB.whatsNewSeen == v then return end
    local notes = NOTES[v]
    if notes then
      print("|cffe0b84aFL Progress Tracker " .. v .. " — what's new:|r")
      for _, line in ipairs(notes) do print("  • " .. line) end
      print("  Full changelog: Add-on tab on foreverledger.net.")
    end
    ForeverLedgerDB.whatsNewSeen = v
  end)
  f:UnregisterEvent("PLAYER_LOGIN")
  return ok
end)
