-- Run from repo root: lua tests/stale_empty_key_test.lua
-- Lesson from ElvUI PR #1903 (2026-11-27): after the 2026-11-20 Forever realm change, one character
-- can have several saved keys ("Name-Realm" before the hotfix, "Name-" from builds after it).
-- Only one live record may remain; the others are kept, not deleted.
local function load(realm, db)
  UnitName = function() return "Arthas" end
  UnitClass = function() return "Paladin", "PALADIN" end
  GetRealmName = function() return realm end
  CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
  SlashCmdList = {}
  ForeverLedgerDB = db
  local ns = { traced = function(fn) return fn end }
  assert(loadfile("fl-progress-tracker/ForeverLedger.lua"))("FL", ns)
  return ns
end
-- 1) only an empty-realm key: it becomes the live record
local ns = load("", { characters = { ["Arthas-"] = { classFile = "PALADIN", realm = "", level = 31 } } })
local c = ns.getChar()
assert(c.level == 31 and ForeverLedgerDB.characters["Arthas-Forever"] == c, "empty key not adopted")
assert(ForeverLedgerDB.characters["Arthas-"] == nil and c.realm == nil)
-- 2) both "Name-Realm" (older) and "Name-" (newer): newest is live, older kept in staleRecords
ns = load("", { characters = {
  ["Arthas-Lordaeron"] = { classFile = "PALADIN", realm = "Lordaeron", level = 20 },
  ["Arthas-"] = { classFile = "PALADIN", realm = "", level = 31 } } })
c = ns.getChar()
assert(c.level == 31, "newest record not live")
assert(c.staleRecords and c.staleRecords["Arthas-Lordaeron"].level == 20, "old record lost")
assert(c.legacyKey == "Arthas-Lordaeron")
local n = 0; for _ in pairs(ForeverLedgerDB.characters) do n = n + 1 end
assert(n == 1, "character listed more than once: " .. n)
-- 3) live key already exists and a stray "Name-" appears: folded in, not deleted
ns = load("", { characters = { ["Arthas-Forever"] = { classFile = "PALADIN", level = 40 },
  ["Arthas-"] = { classFile = "PALADIN", level = 31 } } })
c = ns.getChar()
assert(c.level == 40 and c.staleRecords["Arthas-"].level == 31 and ForeverLedgerDB.characters["Arthas-"] == nil)
-- 4) different class under "Name-": left alone
ns = load("", { characters = { ["Arthas-"] = { classFile = "MAGE", level = 5 } } })
c = ns.getChar()
assert(ForeverLedgerDB.characters["Arthas-"] and ForeverLedgerDB.characters["Arthas-"].classFile == "MAGE", "other class merged")
print("stale_empty_key_test: OK")
