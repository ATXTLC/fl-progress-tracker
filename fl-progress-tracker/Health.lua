-- ForeverLedger health monitor: watches ONLY ForeverLedger's own resource use. Local only, no network.
-- Findings are stored through the shared error store with source = "leak".
--   * memory: sampled every 60 s out of combat; a steady climb (no drop) across WINDOW samples
--     totalling more than LEAK_KB is recorded as a possible leak.
--   * SavedVariables size: tables over the thresholds below are recorded.
--   * event runaways: one of our event handlers firing more than RUNAWAY_PER_SEC times in a second.
--   * CPU: only read if the player already enabled the scriptProfile CVar (we never enable it).

local ADDON_NAME, ns = ...
local INTERVAL = 60          -- seconds between samples
local WINDOW = 10            -- samples in the rolling window (10 min)
local LEAK_KB = 1024         -- growth over the window that counts as a leak
local RUNAWAY_PER_SEC = 50
local LIMITS = { completedQuests = 10000, questLog = 100, roster = 2000, guilds = 50, characters = 100, errors = 200 }

local samples = {}           -- rolling memory samples in KB
local status = { memoryKB = nil, cpuMS = nil, leak = false, warnings = 0 }
ns.health = status

local function warn(message)
  status.warnings = status.warnings + 1
  if ns.recordError then ns.recordError({ source = "leak", message = message, stack = "" }) end
end

local function count(t) local n = 0; if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end; return n end

-- Pure check, exposed for tests: true when every sample >= the previous one and total growth > limitKB.
function ns.isSteadyGrowth(list, limitKB)
  if #list < WINDOW then return false end
  for i = 2, #list do if list[i] < list[i - 1] then return false end end
  return (list[#list] - list[1]) > limitKB
end

function ns.checkSavedVariablesSize()
  local d = ForeverLedgerDB
  if type(d) ~= "table" then return end
  local function check(label, n)
    if n > (LIMITS[label] or math.huge) then
      warn(("SavedVariables table '%s' is large (over %d entries)"):format(label, LIMITS[label]))
    end
  end
  check("characters", count(d.characters)); check("guilds", count(d.guilds)); check("errors", count(d.errors))
  for _, c in pairs(d.characters or {}) do
    if type(c) == "table" then
      check("completedQuests", count(c.completedQuests)); check("questLog", count(c.questLog))
      if type(c.guild) == "table" then check("roster", count(c.guild.roster)) end
    end
  end
end

function ns.sampleHealth()
  if InCombatLockdown and InCombatLockdown() then return end     -- never sample in combat
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    UpdateAddOnMemoryUsage()
    local kb = GetAddOnMemoryUsage(ADDON_NAME)
    status.memoryKB = kb
    samples[#samples + 1] = kb
    while #samples > WINDOW do table.remove(samples, 1) end
    if ns.isSteadyGrowth(samples, LEAK_KB) then
      status.leak = true
      warn(("Memory grew steadily by more than %d KB over %d minutes"):format(LEAK_KB, WINDOW * INTERVAL / 60))
      samples = { kb }   -- start a fresh window so we don't re-flag every minute
    end
  end
  if GetCVar and GetCVar("scriptProfile") == "1" and UpdateAddOnCPUUsage and GetAddOnCPUUsage then
    UpdateAddOnCPUUsage()
    status.cpuMS = GetAddOnCPUUsage(ADDON_NAME)
  end
  ns.checkSavedVariablesSize()
end

-- Called by ForeverLedger.lua's OnEvent; counts per event per second.
local evSecond, evCounts, flagged = 0, {}, {}
function ns.countEvent(event)
  local now = time()
  if now ~= evSecond then evSecond, evCounts = now, {} end
  local n = (evCounts[event] or 0) + 1
  evCounts[event] = n
  if n > RUNAWAY_PER_SEC and not flagged[event] then
    flagged[event] = true   -- once per session per event
    warn(("Event handler runaway: %s fired more than %d times in one second"):format(event, RUNAWAY_PER_SEC))
  end
end

function ns.printHealth()
  local mem = status.memoryKB
  if not mem and UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    UpdateAddOnMemoryUsage(); mem = GetAddOnMemoryUsage(ADDON_NAME)
  end
  print(("FL Progress Tracker health: memory %s KB, CPU %s, %d sample(s), leak suspected: %s, warnings this session: %d"):format(
    mem and ("%.0f"):format(mem) or "?", status.cpuMS and ("%.0f ms"):format(status.cpuMS) or "n/a (scriptProfile off)",
    #samples, status.leak and "yes" or "no", status.warnings))
  if ns.estimateProgressBytes then
    local n, crit, bytes = ns.estimateProgressBytes()
    print(("FL Progress Tracker achievements: %d earned + %d criteria rows stored, about %.1f KB"):format(n, crit, bytes / 1024))
  end
end

-- Tiny timer: C_Timer when available, else a throttled OnUpdate.
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(INTERVAL, function() pcall(ns.sampleHealth) end)
else
  local acc, t = 0, CreateFrame("Frame")
  t:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc >= INTERVAL then acc = 0; pcall(ns.sampleHealth) end
  end)
end
