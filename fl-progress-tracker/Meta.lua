-- ForeverLedger Meta: stamps ForeverLedgerDB.meta so the website's integration check can verify that an uploaded
-- SavedVariables file really came from ForeverLedger on a WoW Forever client. Read-only: GetBuildInfo + TOC metadata.
local ADDON_NAME, ns = ...
local SCHEMA = 2

local function stamp()
  ForeverLedgerDB = ForeverLedgerDB or {}
  local m = {}
  m.addon = "ForeverLedger"
  m.schema = SCHEMA
  local gm = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  m.addonVersion = gm and gm(ADDON_NAME or "fl-progress-tracker", "Version") or nil
  if GetBuildInfo then
    local version, build, _, toc = GetBuildInfo()
    m.gameVersion = version; m.build = tostring(build or ""); m.interface = tonumber(toc)
  end
  m.stamped = time and time() or nil
  ForeverLedgerDB.meta = m
  ForeverLedgerDB.schema = SCHEMA
  return m
end
if ns then ns.stampMeta = stamp; ns.SCHEMA = SCHEMA end

-- Error reports: recorded in game always; uploaded by the companion app for linked accounts. DEFAULT ON, opt out: /fl share off.
function ns.shareNotice()
  local st = type(ForeverLedgerDB) == "table" and type(ForeverLedgerDB.settings) == "table" and ForeverLedgerDB.settings or {}
  local on = st.shareErrors ~= false
  return ("FL Progress Tracker: error reports are %s. All FL Progress Tracker errors are recorded; for paired accounts the companion app uploads them to foreverledger.net with a hashed account id only. Reports hold no personal data: error text (scrubbed), add-on/game version, OS, locale, loaded add-on names, zone type. Opt out: /fl share off  (on again: /fl share on; Linux/Wine flag: /fl share wine, now %s). BattleTag on reports: %s (/fl share battletag to add it, only kept if your account is Battle.net-verified; /fl share battletag off to stop)"):format(
    on and "ON" or "OFF", st.linuxWine and "on" or "off", st.shareBattleTag == true and "ON" or "OFF")
end

if CreateFrame then
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LOGIN")
  f:RegisterEvent("PLAYER_LOGOUT")
  f:SetScript("OnEvent", function(_, event)
    stamp()
    local st = ForeverLedgerDB.settings or {}; ForeverLedgerDB.settings = st
    if event == "PLAYER_LOGIN" and not st.shareNoticeShown then   -- first-run notice, shown once
      st.shareNoticeShown = true
      print(ns.shareNotice())
    end
  end)
end

-- /fl link CODE : stores the one-time PAIRING code (made on foreverledger.net/account/ after Battle.net sign-in) in
-- SavedVariables. Nothing is sent anywhere by the add-on (it cannot network). After /reload the companion uploader reads
-- ForeverLedgerDB.link.code to pair this PC. The code proves nothing about identity (Battle.net sign-in does that);
-- it expires after 10 minutes. Never share the code: whoever uses it first pairs a device to your account. Your BattleTag is stored locally and only sent if you run /fl share battletag.
local CODE_CHARS = "^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]+$"
function ns.validLinkCode(code)
  return type(code) == "string" and #code == 8 and code:match(CODE_CHARS) ~= nil
end
function ns.link(arg)
  local code = strupper and strupper(strtrim and strtrim(arg or "") or (arg or "")) or tostring(arg or ""):upper()
  if not ns.validLinkCode(code) then
    print("FL Progress Tracker: usage /fl link CODE (8 letters/numbers from foreverledger.net/account/).")
    return false
  end
  local tag
  if BNGetInfo then local _, bt = BNGetInfo(); tag = bt end
  if type(tag) ~= "string" or not tag:find("#", 1, true) then
    print("FL Progress Tracker: could not read your BattleTag (Battle.net offline?). Try again in a minute.")
    return false
  end
  ForeverLedgerDB = ForeverLedgerDB or {}
  ForeverLedgerDB.link = { code = code, battletag = tag, at = time and time() or nil }
  stamp()
  print("FL Progress Tracker: pairing code saved. Type /reload now, then run the companion app (fl_companion pair).")
  return true
end
