-- ForeverLedger error capture (local only, readable, no network).
-- WoW add-ons cannot make network calls, so errors are only written to SavedVariables
-- (ForeverLedgerDB.errors). The player can view/copy them with /fl errors; the optional PC
-- watcher reads the SavedVariables file after the game flushes it (/reload, logout, char switch).
--
-- Sources captured:
--   "lua"       any Lua error reaching the global error handler (chained, never swallowed)
--   "bugGrabber" errors delivered by BugGrabber's callback when BugGrabber/BugSack is loaded
--   "blocked"   ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN (taint / protected call)
--   "warning"   LUA_WARNING
--   "leak"      Health.lua: memory growth, oversized SavedVariables, event runaways
--   "schema"    SavedVariables migration/corruption notes
--   "self"      ForeverLedger's own failures caught by ns.traced (xpcall wrapper)

local ADDON_NAME, ns = ...
ns = ns or {}

local MAX_ERRORS = 200      -- rollover: oldest entry is dropped beyond this
local MAX_MESSAGE = 1000
local MAX_STACK = 1500
local MAX_PER_SECOND = 10   -- stop recording during error storms (same idea as BugGrabber)

local function addonVersion()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return (get and get(ADDON_NAME or "fl-progress-tracker", "Version")) or "?"
end

local function buildInfo()
  if not GetBuildInfo then return {} end
  local version, build, date, toc = GetBuildInfo()
  return { version = version, build = build, date = date, toc = toc }
end

-- SavedVariables are only loaded at ADDON_LOADED; anything captured earlier goes to a
-- temporary table and is merged in once the real ForeverLedgerDB is available.
local svLoaded, pending = false, {}
local function db()
  if not svLoaded then
    pending.errors = pending.errors or {}
    pending.errorSeq = pending.errorSeq or 0
    return pending
  end
  ForeverLedgerDB = ForeverLedgerDB or {}
  ForeverLedgerDB.errors = ForeverLedgerDB.errors or {}
  ForeverLedgerDB.errorSeq = ForeverLedgerDB.errorSeq or 0
  return ForeverLedgerDB
end

local function trim(s, n)
  s = tostring(s or "")
  if #s > n then s = s:sub(1, n) .. "...(truncated)" end
  return s
end

-- Data minimization: remove anything that could identify the player or their PC.
local function scrub(s)
  s = tostring(s or "")
  s = s:gsub("[%w]:[\\/][^\n:]-[\\/][Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]", "<AddOns>/")
  s = s:gsub("[Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]", "<AddOns>/")
  s = s:gsub("([Uu]sers[\\/])[^\\/\n]+", "%1<user>")
  s = s:gsub("([Aa]ccount[\\/])[^\\/\n]+", "%1<account>")
  s = s:gsub("[%w%._%%%+%-]+@[%w%.%-]+%.%a%a+", "<email>")
  s = s:gsub("[%w\128-\255]+#%d%d%d%d%d?%f[%D]", "<battletag>")
  s = s:gsub("\\\\[^\n%s:]+", "<path>")            -- UNC \\server\share\...
  s = s:gsub("%f[%w]%a:[\\/][^\n%s:]*", "<path>")   -- any remaining drive path C:\...
  s = s:gsub("fl%-progress%-tracker", "\2FL\2"):gsub("ForeverLedger", "\1FL\1")   -- protect our own name from realm/player scrubbing
  local function drop(word, tag)
    if type(word) == "string" and #word > 1 then s = s:gsub("%f[%w\128-\255]" .. word:gsub("%p", "%%%0") .. "%f[^%w\128-\255]", tag) end
  end
  drop(UnitName and UnitName("player"), "<player>")
  drop(GetRealmName and GetRealmName(), "<realm>")
  -- every character this add-on has ever saved (keys are "Name-Realm")
  local chars = type(ForeverLedgerDB) == "table" and type(ForeverLedgerDB.characters) == "table" and ForeverLedgerDB.characters
  if chars then
    for key, c in pairs(chars) do
      local n, r = tostring(key):match("^([^%-]+)%-(.+)$")
      drop(type(c) == "table" and c.name or n, "<player>")
      drop(type(c) == "table" and c.realm or r, "<realm>")
    end
  end
  s = s:gsub("\1FL\1", "ForeverLedger"):gsub("\2FL\2", "fl-progress-tracker")
  return s
end
ns.scrub = scrub

-- Keep only stack frames inside ForeverLedger; if none, keep the top 2 frames for context.
local function minimalStack(stack)
  local keep, all = {}, {}
  for line in scrub(stack):gmatch("[^\n]+") do
    all[#all + 1] = line
    if line:find("ForeverLedger", 1, true) or line:find("fl-progress-tracker", 1, true) then keep[#keep + 1] = line end
  end
  if #keep == 0 then keep = { all[1], all[2] } end
  return trim(table.concat(keep, "\n"), MAX_STACK)
end
ns.minimalStack = minimalStack

local SCHEMA = 2   -- 2 = minimized records (no locals/character/realm/zone)
local KEEP = { id = 1, seq = 1, source = 1, message = 1, stack = 1, count = 1, first = 1, last = 1,
  session = 1, addonVersion = 1, gameBuild = 1, interface = 1, gameVersion = 1, os = 1, locale = 1, where = 1,
  trigger = 1, zoneType = 1, inCombat = 1, afterPatch = 1, severity = 1, addons = 1 }

-- Upgrade/validate SavedVariables safely. Corrupt parts are reset, never allowed to break loading.
function ns.migrate()
  local notes = {}
  if type(ForeverLedgerDB) ~= "table" then ForeverLedgerDB = {}; notes[#notes + 1] = "ForeverLedgerDB was not a table; reset" end
  local d = ForeverLedgerDB
  local ok, err = pcall(function()
    if d.errors ~= nil and type(d.errors) ~= "table" then d.errors = {}; notes[#notes + 1] = "errors list corrupt; reset" end
    if type(d.errorSeq) ~= "number" then d.errorSeq = 0 end
    local old = tonumber(d.errorSchema) or 1
    if old > SCHEMA then
      notes[#notes + 1] = ("SavedVariables schema %d is newer than this add-on (%d); downgrade?"):format(old, SCHEMA)
    end
    local clean = {}
    for _, e in ipairs(d.errors or {}) do
      if type(e) == "table" then
        local m = {}
        for k in pairs(KEEP) do m[k] = e[k] end
        m.first = m.first or e.serverTime or e.time; m.last = m.last or e.lastServer
        m.session = m.session or e.lastSession
        m.message, m.stack = scrub(m.message), minimalStack(m.stack)
        clean[#clean + 1] = m
      end
    end
    d.errors = clean
    if old < SCHEMA then d.errorSchema = SCHEMA end
  end)
  if not ok then d.errors = {}; notes[#notes + 1] = "migration failed (" .. tostring(err) .. "); errors reset" end
  for _, n in ipairs(notes) do ns.pendingNotes = ns.pendingNotes or {}; table.insert(ns.pendingNotes, n) end
end

-- ---- Capture context (docs/error-capture-fields.md). Public/technical facts only: no names, paths, coords, chat.
ns.trigger = nil                     -- event / slash command being handled (set by ns.withTrigger)
function ns.withTrigger(name, fn, ...)
  local prev = ns.trigger; ns.trigger = name
  local r = { pcall(fn, ...) }
  ns.trigger = prev
  if not r[1] then error(r[2], 0) end
  return unpack(r, 2)
end
local function clientOS()
  if IsMacClient and IsMacClient() then return "macOS" end
  if IsLinuxClient and IsLinuxClient() then return "Linux" end
  if IsWindowsClient and IsWindowsClient() then
    local st = type(ForeverLedgerDB) == "table" and ForeverLedgerDB.settings
    return (type(st) == "table" and st.linuxWine) and "Linux-Wine" or "Windows"   -- Wine reports Windows
  end
  return nil
end
local addonListCache
local function loadedAddons()   -- names + versions only, cap 60, once per session
  if addonListCache then return addonListCache end
  local C = C_AddOns or {}
  local num = C.GetNumAddOns or GetNumAddOns
  local info = C.GetAddOnInfo or GetAddOnInfo
  local loaded = C.IsAddOnLoaded or IsAddOnLoaded
  local meta = C.GetAddOnMetadata or GetAddOnMetadata
  local out = {}
  if num and info and loaded then
    for i = 1, num() do
      local name = info(i)
      if name and name ~= ADDON_NAME and loaded(i) and #out < 60 then
        local v = meta and meta(i, "Version")
        out[#out + 1] = tostring(name) .. (v and (" " .. tostring(v):sub(1, 16)) or "")
      end
    end
  end
  addonListCache = out
  return out
end
ns.loadedAddons = loadedAddons
local function zoneType()
  if not IsInInstance then return "none" end
  local _, t = IsInInstance()
  return t or "none"
end
local function whereFrom(msg)   -- "File.lua:123" of the first ForeverLedger frame (scrubbed path)
  return tostring(msg or ""):match("fl%-progress%-tracker[\\/]([%w_%-%.]+%.lua:%d+)") or tostring(msg or ""):match("ForeverLedger[\\/]([%w_%-%.]+%.lua:%d+)") or tostring(msg or ""):match("([%w_%-]+%.lua:%d+)")
end
local SEVERE_SOURCE = { blocked = "Taint", schema = "Data loss", leak = "Leak" }
local function severity(info, trigger)
  if SEVERE_SOURCE[info.source] then return SEVERE_SOURCE[info.source] end
  if trigger == "ADDON_LOADED" or trigger == "PLAYER_LOGIN" then return "Crash" end   -- load path: add-on may be disabled
  local m = tostring(info.message or ""):lower()
  if m:find("frame") or m:find("texture") or m:find("fontstring") or m:find("setpoint") then return "Cosmetic" end
  return "Functional"
end
ns.errorSeverity = severity

local recording = false        -- re-entrancy guard: never record an error raised while recording
local windowStart, windowCount = 0, 0

-- Store one error. info = { message, source, stack }. ONLY the fields below are stored.
local function record(info)
  if recording then return end
  recording = true
  pcall(function()
    local now = time()
    if now ~= windowStart then windowStart, windowCount = now, 0 end
    windowCount = windowCount + 1
    if windowCount > MAX_PER_SECOND then return end

    local d = db()
    local list = d.errors
    local msg = trim(scrub(info.message or "?"), MAX_MESSAGE)
    local server = GetServerTime and GetServerTime() or now
    d.errorSeq = d.errorSeq + 1

    for _, e in ipairs(list) do
      if e.message == msg and e.source == info.source then   -- dedupe: bump the counter
        e.count = (e.count or 1) + 1
        e.last, e.seq, e.session = server, d.errorSeq, d.errorSession
        return
      end
    end

    local b = buildInfo()
    local trig = info.trigger or ns.trigger
    while #list >= MAX_ERRORS do table.remove(list, 1) end
    list[#list + 1] = {
      id = d.errorSeq, seq = d.errorSeq,
      source = info.source or "lua",
      message = msg,
      stack = minimalStack(info.stack),
      count = 1,
      first = server, last = server,
      session = d.errorSession,
      addonVersion = addonVersion(),
      gameBuild = b.build, gameVersion = b.version, interface = b.toc,
      os = clientOS(), locale = GetLocale and GetLocale() or nil,
      where = whereFrom(info.stack) or whereFrom(msg),
      trigger = trig and tostring(trig):sub(1, 40) or nil,
      zoneType = zoneType(), inCombat = (InCombatLockdown and InCombatLockdown()) and true or false,
      afterPatch = ns.afterPatch and true or false,
      severity = severity(info, trig),
      addons = loadedAddons(),
    }
  end)
  recording = false
end
ns.recordError = record

-- ForeverLedger's own code paths: wrap a function so failures are recorded, not thrown.
-- Also sets the trigger context: OnEvent handlers -> the event name; kind "slash" -> "/fl <command>".
function ns.traced(fn, kind)
  return function(...)
    local n, args = select("#", ...), { ... }
    local trig
    if kind == "slash" then trig = "/fl " .. (tostring(args[1] or ""):match("^%s*(%a+)") or ""):lower():sub(1, 12)
    elseif type(args[2]) == "string" and args[2]:match("^[A-Z][A-Z0-9_]+$") then trig = args[2] end
    local prev = ns.trigger; ns.trigger = trig and trig:gsub("%s+$", "") or prev
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, function(e)
      return { msg = e, stack = debugstack and debugstack(2) or "" }
    end)
    if not ok then
      record({ source = "self", message = err.msg, stack = err.stack })
    end
    ns.trigger = prev
  end
end

-- ---- Global Lua errors -------------------------------------------------------------------
local usingBugGrabber = false

local function hookBugGrabber()
  local BG = _G.BugGrabber
  if type(BG) ~= "table" then return false end
  local function fromObject(obj)
    if type(obj) ~= "table" then return end
    record({ source = "bugGrabber", message = obj.message, stack = obj.stack })
  end
  -- Current BugGrabber: EventRegistry "BugGrabber.BugGrabbed" passes a table id string.
  if EventRegistry and EventRegistry.RegisterCallback and BG.GetErrorByID then
    EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, tableID)
      fromObject(BG:GetErrorByID(tableID))
    end, ns)
    return true
  end
  -- Older BugGrabber: CallbackHandler "BugGrabber_BugGrabbed" passes the error object.
  if BG.RegisterCallback then
    BG.RegisterCallback(ns, "BugGrabber_BugGrabbed", function(_, obj) fromObject(obj) end)
    return true
  end
  return false
end

usingBugGrabber = hookBugGrabber()

if not usingBugGrabber and geterrorhandler and seterrorhandler then
  -- Chain: record, then ALWAYS hand the error to the previous handler (default error frame,
  -- other capture add-ons). We never suppress or replace anyone's handling.
  local previous = geterrorhandler()
  seterrorhandler(function(msg, ...)
    record({ source = "lua", message = msg, stack = debugstack and debugstack(3) or "" })
    if previous then return previous(msg, ...) end
  end)
end

-- ---- Blocked / forbidden actions and Lua warnings ------------------------------------------
-- BugGrabber already turns these into errors (and they reach us through its callback), so only
-- listen ourselves when it is absent to avoid double counting. We only observe; we do not
-- unregister Blizzard's own handlers.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
if not usingBugGrabber then
  events:RegisterEvent("ADDON_ACTION_BLOCKED")
  events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
  events:RegisterEvent("LUA_WARNING")
end
events:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "ADDON_LOADED" then
    if a1 == ADDON_NAME then
      svLoaded = true
      ns.migrate()
      local d = db()
      d.errorSession = (d.errorSession or 0) + 1      -- one session per UI load
      local bi = buildInfo()                           -- after_patch: build changed since last session
      ns.afterPatch = d.lastBuild ~= nil and bi.build ~= nil and tostring(d.lastBuild) ~= tostring(bi.build)
      d.lastBuild = bi.build
      for _, e in ipairs(pending.errors or {}) do      -- merge errors from before SV load
        while #d.errors >= MAX_ERRORS do table.remove(d.errors, 1) end
        d.errorSeq = d.errorSeq + 1
        e.id, e.seq, e.session, e.lastSession = d.errorSeq, d.errorSeq, d.errorSession, d.errorSession
        d.errors[#d.errors + 1] = e
      end
      pending = {}
      for _, n in ipairs(ns.pendingNotes or {}) do record({ source = "schema", message = n }) end
      ns.pendingNotes = nil
      -- Late check: BugGrabber may load after us in rare setups.
      if not usingBugGrabber then usingBugGrabber = hookBugGrabber() end
    end
    return
  end
  if event == "LUA_WARNING" then
    record({ source = "warning", message = "LUA_WARNING: " .. tostring(a2 or a1 or "") })
  elseif a1 == ADDON_NAME then          -- taint blamed on ForeverLedger only
    record({ source = "blocked",
             message = ("[%s] AddOn '%s' tried to call the protected function '%s'."):format(event, tostring(a1 or "?"), tostring(a2 or "?")),
             stack = debugstack and debugstack(2) or "" })
  end
end)

-- ---- Viewing / copying --------------------------------------------------------------------
local function reportText(limit)
  local d, b = db(), buildInfo()
  local lines = {
    ("FL Progress Tracker %s | WoW %s build %s (%s) interface %s"):format(addonVersion(),
      tostring(b.version), tostring(b.build), tostring(b.date), tostring(b.toc)),
    ("Session %s | BugGrabber %s | %d stored error(s)"):format(tostring(d.errorSession),
      usingBugGrabber and "yes" or "no", #d.errors), "",
  }
  local list, first = d.errors, math.max(1, #d.errors - (limit or 20) + 1)
  for i = #list, first, -1 do
    local e = list[i]
    lines[#lines + 1] = ("#%d [%s] x%d  first %s last %s  session %s"):format(e.id or i, e.source or "?",
      e.count or 1, date("%Y-%m-%d %H:%M:%S", e.first or 0), date("%Y-%m-%d %H:%M:%S", e.last or 0), tostring(e.session))
    lines[#lines + 1] = e.message or ""
    if e.stack and e.stack ~= "" then lines[#lines + 1] = "Stack:\n" .. e.stack end
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end
ns.errorReportText = reportText

local copyFrame
local function showCopyWindow(text)
  if not copyFrame then
    copyFrame = CreateFrame("Frame", "ForeverLedgerErrorFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    copyFrame:SetSize(640, 420)
    copyFrame:SetPoint("CENTER")
    copyFrame:SetFrameStrata("DIALOG")
    copyFrame:EnableMouse(true)
    copyFrame:SetMovable(true)
    copyFrame:RegisterForDrag("LeftButton")
    copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
    copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
    if copyFrame.SetBackdrop then
      copyFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    end
    local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("FL Progress Tracker errors - Ctrl+A then Ctrl+C to copy")
    local close = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local scroll = CreateFrame("ScrollFrame", "ForeverLedgerErrorScroll", copyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -36)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(580)
    edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    scroll:SetScrollChild(edit)
    copyFrame.edit = edit
    tinsert(UISpecialFrames, "ForeverLedgerErrorFrame")   -- Escape closes it
  end
  copyFrame.edit:SetText(text)
  copyFrame:Show()
  copyFrame.edit:SetFocus()
  copyFrame.edit:HighlightText()
end

function ns.showErrors(arg)
  local d = db()
  if #d.errors == 0 then print("FL Progress Tracker: no errors recorded."); return end
  local n = tonumber(arg) or 20
  print(("FL Progress Tracker: %d stored error(s); showing the latest %d in a copy window."):format(#d.errors, math.min(n, #d.errors)))
  for i = #d.errors, math.max(1, #d.errors - 4), -1 do
    local e = d.errors[i]
    print(("  #%d [%s] x%d %s"):format(e.id or i, e.source or "?", e.count or 1, (e.message or ""):sub(1, 120)))
  end
  showCopyWindow(reportText(n))
end

function ns.clearErrors()
  db().errors = {}   -- errorSeq keeps counting so the PC watcher never re-sends old ids
  print("FL Progress Tracker: error list cleared.")
end
