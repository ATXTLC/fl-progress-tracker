-- ForeverLedger: read-only snapshot addon for WoW Forever (Interface 16001).
-- It only READS game state and writes it to SavedVariables (ForeverLedgerDB).
-- It never casts, moves, clicks, sends chat, or automates anything.

local ADDON_NAME, ns = ...
ForeverLedgerDB = ForeverLedgerDB or {}

local SLOTS = {
  "HeadSlot", "NeckSlot", "ShoulderSlot", "ShirtSlot", "ChestSlot", "WaistSlot", "LegsSlot",
  "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot",
  "Trinket1Slot", "BackSlot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "TabardSlot",
}

local function charKey()
  local name = UnitName("player") or "Unknown"
  local realm = GetRealmName and GetRealmName() or "Unknown"
  return name .. "-" .. realm
end

local function getChar()
  ForeverLedgerDB.version = 1
  ForeverLedgerDB.characters = ForeverLedgerDB.characters or {}
  local key = charKey()
  ForeverLedgerDB.characters[key] = ForeverLedgerDB.characters[key] or {}
  return ForeverLedgerDB.characters[key]
end

ns.getChar = function() return getChar() end

local function saveBasics(c)
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  c.name = UnitName("player")
  c.realm = GetRealmName and GetRealmName() or nil
  c.faction = UnitFactionGroup("player")
  c.race = select(1, UnitRace("player")); c.raceFile = race
  c.class = select(1, UnitClass("player")); c.classFile = class
  c.level = UnitLevel("player")
  c.xp = UnitXP("player"); c.xpMax = UnitXPMax("player")
  c.restedXP = GetXPExhaustion and GetXPExhaustion() or nil
  c.zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
  c.subzone = GetSubZoneText and GetSubZoneText() or nil
  c.money = GetMoney()
  c.updated = time()
end

local function saveGear(c)
  local gear = {}
  for _, slot in ipairs(SLOTS) do
    local id = GetInventorySlotInfo(slot)
    local itemID = GetInventoryItemID("player", id)
    if itemID then
      gear[#gear + 1] = { slot = slot, itemID = itemID, link = GetInventoryItemLink("player", id) }
    end
  end
  c.gear = gear
end

local function saveProfessions(c)
  local profs = {}
  if GetNumSkillLines then
    local header
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if isHeader then
        header = name
      elseif name then
        profs[#profs + 1] = { name = name, category = header, rank = rank, max = maxRank }
      end
    end
  end
  c.skills = profs
end

local function saveCompleted(c)
  local ids = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    ids = C_QuestLog.GetAllCompletedQuestIDs() or {}
  elseif GetQuestsCompleted then
    local t = {}
    GetQuestsCompleted(t) -- fills t[questID] = true
    for id in pairs(t) do ids[#ids + 1] = id end
  end
  table.sort(ids)
  c.completedQuests = ids
end

local function saveQuestLog(c)
  local log = {}
  local num = GetNumQuestLogEntries()
  for i = 1, num do
    local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
    if title and not isHeader then
      local objectives = {}
      for o = 1, (GetNumQuestLeaderBoards(i) or 0) do
        local text, kind, done = GetQuestLogLeaderBoard(o, i)
        objectives[#objectives + 1] = { text = text, type = kind, done = done and true or false }
      end
      log[#log + 1] = { id = questID, title = title, level = level,
        complete = (isComplete == 1), failed = (isComplete == -1), objectives = objectives }
    end
  end
  c.questLog = log
end

local function saveGuild(c)
  if not IsInGuild() then c.guild = nil; return end
  local gname, rankName, rankIndex = GetGuildInfo("player")
  if not gname then return end -- not loaded yet; GUILD_ROSTER_UPDATE will retry
  local g = { name = gname, rank = rankName, rankIndex = rankIndex,
    motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or nil,
    info = GetGuildInfoText and GetGuildInfoText() or nil, roster = {}, updated = time() }
  local total = GetNumGuildMembers() or 0
  for i = 1, total do
    local name, rank, rIdx, level, class, zone, note, _, online = GetGuildRosterInfo(i)
    if name then
      local y, m, d, h = GetGuildRosterLastOnline(i)
      g.roster[#g.roster + 1] = { name = name, rank = rank, rankIndex = rIdx, level = level,
        class = class, zone = zone, online = online and true or false, note = note,
        lastOnline = (not online and y) and { years = y, months = m, days = d, hours = h } or nil }
    end
  end
  c.guild = g
  ForeverLedgerDB.guilds = ForeverLedgerDB.guilds or {}
  ForeverLedgerDB.guilds[gname .. "-" .. (c.realm or "")] = g
end

local function snapshot(full)
  local c = getChar()
  saveBasics(c)
  saveGear(c)
  saveProfessions(c)
  saveQuestLog(c)
  if full then saveCompleted(c) end
  c.lastEvent = full or "update"
end

local traced = ns.traced -- from Errors.lua

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("TIME_PLAYED_MSG")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_GUILD_UPDATE")

local function onEvent(_, event, ...)
  if ns.countEvent then ns.countEvent(event) end
  if event == "TIME_PLAYED_MSG" then
    local total, thisLevel = ...
    local c = getChar(); c.playedTotal = total; c.playedLevel = thisLevel
    return
  end
  if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
    saveGuild(getChar())
    return
  end
  if event == "QUEST_TURNED_IN" then
    -- The completed list may not include the quest yet; record it directly too.
    local questID = ...
    snapshot(event)
    local c = getChar()
    local seen = false
    for _, id in ipairs(c.completedQuests or {}) do if id == questID then seen = true break end end
    if questID and not seen then table.insert(c.completedQuests, questID) end
    return
  end
  snapshot(event)
  if event == "PLAYER_LOGIN" then
    if RequestTimePlayed then RequestTimePlayed() end -- prints /played once; read-only
    if IsInGuild() then
      if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
      elseif GuildRoster then GuildRoster() end
    end
  end
end
f:SetScript("OnEvent", traced(onEvent))

-- /fl errors [n]  -> copy window with the latest n errors;  /fl clearerrors -> empty the list
SLASH_FOREVERLEDGER1 = "/fl"
SlashCmdList["FOREVERLEDGER"] = traced(function(input)
  local cmd, arg = strtrim(input or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "errors" and arg == "clear" or cmd == "clearerrors" then
    ns.clearErrors()
  elseif cmd == "health" then
    ns.printHealth()
  elseif cmd == "errors" then
    ns.showErrors(arg)
  elseif cmd == "watch" or cmd == "unwatch" then
    local ids = {}; for n in arg:gmatch("%d+") do ids[#ids + 1] = tonumber(n) end
    if #ids == 0 then print("Usage: /fl " .. cmd .. " <achievement id> [more ids]"); return end
    local ch, total = ns.watch(ids, cmd == "watch")
    print(string.format("FL Progress Tracker: %d changed, watching %d/%d. Progress saves on /reload or logout.", ch, total, ns.WATCH_CAP))
  elseif cmd == "watchlist" then
    local w = (ForeverLedgerDB.account or {}).watch or {}
    print("FL Progress Tracker watch list (" .. #w .. "/" .. ns.WATCH_CAP .. "): " .. (#w > 0 and table.concat(w, " ") or "empty"))
  elseif cmd == "leaderboard" then
    if arg == "on" or arg == "off" then
      local on = ns.setLeaderboard(arg == "on")
      print("FL Progress Tracker leaderboard: " .. (on and "ON - your character-realm and scores can appear on the public leaderboard after the next upload." or "OFF - you are not listed."))
    else
      print("FL Progress Tracker leaderboard is " .. (((ForeverLedgerDB.account or {}).leaderboard) and "ON" or "OFF") .. ". Use /fl leaderboard on|off.")
    end
  elseif cmd == "share" then   -- error reports via the companion app: DEFAULT ON for linked accounts; /fl share off to opt out
    ForeverLedgerDB.settings = ForeverLedgerDB.settings or {}
    local st = ForeverLedgerDB.settings
    if arg == "on" or arg == "off" then st.shareErrors = (arg == "on") end
    if arg == "wine" then st.linuxWine = not st.linuxWine end   -- opt-in: mark Windows client as Linux/Wine
    if arg == "battletag" then st.shareBattleTag = true end      -- opt-in: BattleTag on error reports (server keeps it only if Battle.net-verified)
    if arg == "battletag off" then st.shareBattleTag = false end
    print(ns.shareNotice())
  elseif cmd == "link" and ns.link then
    ns.link(arg)
  else
    print("FL Progress Tracker commands: /fl errors [count], /fl clearerrors, /fl health, /fl watch <id>, /fl unwatch <id>, /fl watchlist, /fl leaderboard on|off, /fl link CODE, /fl share on|off|wine|battletag|battletag off")
  end
end, "slash")
