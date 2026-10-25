-- ForeverLedger progress capture: achievements (account) and PvP (per character). READ-ONLY, local only.
-- Memory-light by design: we store achievement IDs + earned date only, criteria numbers only for
-- INCOMPLETE achievements the player tracks, and a handful of PvP numbers. Never names or text
-- (the website has the reference text). Every API is feature-detected: if the WoW Forever client does
-- not expose it, nothing is written and the dashboard shows "not captured yet".
local ADDON_NAME, ns = ...
local MAX_TRACKED = 25   -- watched + in-game tracked achievements with criteria rows (memory cap)
ns.WATCH_CAP = 25

-- Battleground statistic IDs from the Forever beta client (wow-forever.gg game data, build 1.60.1.70532).
ns.BG_STATS = { played = 839, won = 840, av = 53, avWon = 49, ab = 55, abWon = 51, wsg = 52, wsgWon = 105, dsi = 64179, dsiWon = 64176 }

local function ymd(m, d, y) if not (m and d and y) then return nil end return string.format("%04d-%02d-%02d", 2000 + y, m, d) end

-- Earned achievements -> ForeverLedgerDB.account.achievements = { [id] = "YYYY-MM-DD" }
function ns.saveAchievements()
  if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then return false end
  local acct = ForeverLedgerDB.account or {}; ForeverLedgerDB.account = acct
  local earned = {}
  for _, cat in ipairs(GetCategoryList() or {}) do
    local n = GetCategoryNumAchievements(cat) or 0
    for i = 1, n do
      local id, _, _, done, m, d, y = GetAchievementInfo(cat, i)
      if id and done then earned[id] = ymd(m, d, y) or true end
    end
  end
  acct.achievements = earned
  -- Criteria progress only for tracked, incomplete achievements (bounded).
  local prog = {}
  if GetTrackedAchievements and GetAchievementNumCriteria and GetAchievementCriteriaInfo then
    -- the owner's watch list first (/fl watch), then in-game tracked ones, de-duplicated, capped at MAX_TRACKED
    local tracked, seen = {}, {}
    for _, aid in ipairs(acct.watch or {}) do if not seen[aid] then seen[aid] = true; tracked[#tracked + 1] = aid end end
    for _, aid in ipairs({ GetTrackedAchievements() }) do if not seen[aid] then seen[aid] = true; tracked[#tracked + 1] = aid end end
    for k = 1, math.min(#tracked, MAX_TRACKED) do
      local aid = tracked[k]
      if not earned[aid] then
        local row = {}
        for c = 1, (GetAchievementNumCriteria(aid) or 0) do
          local _, _, cdone, qty, req = GetAchievementCriteriaInfo(aid, c)
          row[c] = { cdone and 1 or 0, qty or 0, req or 0 }
        end
        prog[aid] = row
      end
    end
  end
  acct.achievementProgress = prog
  acct.achievementsUpdated = time()
  return true
end

-- PvP: rank, honor, BG battles/wins. Minimal numbers only.
function ns.savePvP(c)
  local p = {}
  if UnitPVPRank then local r = UnitPVPRank("player"); if r and r > 0 and GetPVPRankInfo then local name, num = GetPVPRankInfo(r); p.rank = num; p.rankName = name end end
  if GetPVPRankProgress then p.rankProgress = GetPVPRankProgress() end
  if GetPVPSessionStats then local hk, honor = GetPVPSessionStats(); p.todayHK = hk; p.todayHonor = honor end
  if GetPVPThisWeekStats then local hk, honor = GetPVPThisWeekStats(); p.weekHK = hk; p.weekHonor = honor end
  if GetPVPLifetimeStats then local hk, _, highest = GetPVPLifetimeStats(); p.lifetimeHK = hk; p.highestRank = highest end
  if GetHonorCurrency then p.honor = GetHonorCurrency() elseif C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, 1901); if ok and info then p.honor = info.quantity end end
  if GetStatistic then
    local bg = {}
    for k, id in pairs(ns.BG_STATS) do local v = tonumber(GetStatistic(id)); if v then bg[k] = v end end
    if next(bg) then p.bg = bg end
  end
  p.updated = time()
  c.pvp = p
end

-- Watch list: ForeverLedgerDB.account.watch = { id, ... } (numbers only, cap ns.WATCH_CAP)
function ns.watch(ids, on)
  local acct = ForeverLedgerDB.account or {}; ForeverLedgerDB.account = acct
  local w = acct.watch or {}; acct.watch = w
  local changed = 0
  for _, id in ipairs(ids) do
    local pos; for i, v in ipairs(w) do if v == id then pos = i end end
    if on and not pos and #w < ns.WATCH_CAP then w[#w + 1] = id; changed = changed + 1
    elseif not on and pos then table.remove(w, pos); changed = changed + 1 end
  end
  return changed, #w
end

-- Raid/dungeon lockouts per character (GetNumSavedInstances / GetSavedInstanceInfo). Unverified in the Forever client
-- until launch, so feature-detected: when missing we record c.lockoutApi = false and nothing else.
function ns.saveLockouts(c)
  if not (GetNumSavedInstances and GetSavedInstanceInfo) then c.lockoutApi = false; c.lockouts = nil; return false end
  local out, now = {}, time()
  for i = 1, math.min(GetNumSavedInstances() or 0, 40) do
    local name, id, reset, diff, locked, extended, _, isRaid, maxPlayers, _, numEnc, encProg = GetSavedInstanceInfo(i)
    if name and (locked or extended) and (reset or 0) > 0 then
      out[#out + 1] = { n = name, id = id, r = now + reset, d = diff, l = locked and 1 or 0, x = extended and 1 or nil,
        raid = isRaid and 1 or nil, m = maxPlayers, t = numEnc, p = encProg }
    end
  end
  c.lockoutApi = true; c.lockouts = out; c.lockoutsUpdated = now
  return true
end

-- Leaderboard opt-in: OFF by default, separate from search. Only this flag is stored; scores come from the data above.
function ns.setLeaderboard(on)
  local acct = ForeverLedgerDB.account or {}; ForeverLedgerDB.account = acct
  acct.leaderboard = on and true or false
  return acct.leaderboard
end

function ns.estimateProgressBytes()
  local a = ForeverLedgerDB.account or {}; local n, crit = 0, 0
  for _ in pairs(a.achievements or {}) do n = n + 1 end
  for _, row in pairs(a.achievementProgress or {}) do crit = crit + #row end
  crit = crit + #(a.watch or {}) / 4  -- ~10 bytes per watched id
  -- ~48 bytes per earned entry (key + date string) and ~40 per criteria row in Lua tables.
  return n, crit, n * 48 + crit * 40
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN"); f:RegisterEvent("PLAYER_LOGOUT"); f:RegisterEvent("ACHIEVEMENT_EARNED")
f:RegisterEvent("PLAYER_PVP_RANK_CHANGED"); f:RegisterEvent("PLAYER_PVP_KILLS_CHANGED"); f:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
f:RegisterEvent("UPDATE_INSTANCE_INFO")
local function onEvent(_, event)
  if ns.countEvent then ns.countEvent(event) end
  local c = ns.getChar and ns.getChar()
  if event == "PLAYER_LOGIN" or event == "PLAYER_LOGOUT" or event == "ACHIEVEMENT_EARNED" then ns.saveAchievements() end
  if c then ns.savePvP(c) end
  if c and (event == "PLAYER_LOGIN" or event == "PLAYER_LOGOUT" or event == "UPDATE_INSTANCE_INFO") then
    if event == "PLAYER_LOGIN" and RequestRaidInfo then RequestRaidInfo() end
    ns.saveLockouts(c)
  end
end
f:SetScript("OnEvent", ns.traced and ns.traced(onEvent) or onEvent)
