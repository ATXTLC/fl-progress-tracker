-- Run from repo root: lua tests/empty_realm_test.lua
-- WoW Forever hotfix 2026-11-20: GetRealmName() returns "". Keys must stay stable and old data must carry over.
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
-- 1) old save under "Arthas-Lordaeron" is moved to "Arthas-Forever"
local ns = load("", { characters = { ["Arthas-Lordaeron"] = { classFile = "PALADIN", realm = "Lordaeron", level = 20 } } })
local c = ns.getChar()
assert(c.level == 20, "legacy data not adopted")
assert(ForeverLedgerDB.characters["Arthas-Forever"] == c and ForeverLedgerDB.characters["Arthas-Lordaeron"] == nil)
assert(ForeverLedgerDB.characters["Arthas-"] == nil, "empty-realm key created")
assert(ns.realmName() == nil)
-- 2) two old saves with the same name: nothing merged
ns = load("", { characters = { ["Arthas-A"] = { classFile = "PALADIN" }, ["Arthas-B"] = { classFile = "PALADIN" } } })
c = ns.getChar()
assert(c.level == nil and ForeverLedgerDB.characters["Arthas-A"] and ForeverLedgerDB.characters["Arthas-B"], "ambiguous merge")
-- 3) realm still returned (other flavors): old behavior
ns = load("Lordaeron", { characters = {} })
ns.getChar()
assert(ForeverLedgerDB.characters["Arthas-Lordaeron"], "normal realm key broken")
print("empty_realm_test: OK")
-- 4) error scrub must not eat the word "Forever" from the no-realm key label
UnitName = function() return "Arthas" end
GetRealmName = function() return "" end
ForeverLedgerDB = { characters = { ["Arthas-Forever"] = { name = "Arthas" } } }
local ens = {}
pcall(assert(loadfile("fl-progress-tracker/Errors.lua")), "FL", ens)
local out = ens.scrub("Arthas hit an error in WoW Forever")
assert(out:find("WoW Forever", 1, true) and not out:find("Arthas"), "scrub wrong: " .. out)
print("empty_realm_test (scrub): OK")
