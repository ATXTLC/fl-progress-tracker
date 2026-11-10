-- Run from repo root: lua tests/scrub_surname_test.lua
-- WoW Forever: UnitName("player") returns first name, surname. Error scrubbing must remove both.
local function run(first, surname)
  UnitName = function() return first, surname end
  GetRealmName = function() return "Lordaeron" end
  ForeverLedgerDB = {}
  local ns = {}
  pcall(assert(loadfile("fl-progress-tracker/Errors.lua")), "FL", ns)
  return ns.scrub("err by " .. first .. " " .. (surname or "") .. " on Lordaeron; " .. (surname or "x"))
end
local out = run("Arthas", "Menethil")
assert(not out:find("Menethil"), "surname leaked: " .. out)
assert(not out:find("Arthas"), "first name leaked: " .. out)
out = run("Arthas", nil)
assert(not out:find("Arthas"), "first name leaked (no surname): " .. out)
print("scrub_surname_test: OK")
