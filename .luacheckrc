-- luacheck for the Isaac mods here: `luacheck <mod folder>` from this directory.
-- The game's globals come from .luarc.json, the list the editor's language
-- server already uses, so there is one list to keep: a game global missing
-- from it shows up in both tools. A global a mod itself sets (its own handle,
-- kept across luamod so the old copy can be detected; a polyfilled enum; a flag
-- that must outlive a reload; Options, which one mod writes) goes in `writable`
-- below, since a name in read_globals is read-only whatever else says.
std = "lua53"

local writable = { gt = true, tmmc = true, Controller = true, DevReproPending = true, Options = true }

local names
for _, path in ipairs({ ".luarc.json", "../.luarc.json", "../../.luarc.json" }) do
  local f = io.open(path)
  if f then
    names = f:read("a")
    f:close()
    break
  end
end
assert(names, ".luacheckrc: .luarc.json not found; run luacheck from the workspace root")
local block = assert(names:match('"diagnostics%.globals"%s*:%s*%[(.-)%]'), ".luacheckrc: no diagnostics.globals in .luarc.json")

read_globals = {}
globals = {}
for name in block:gmatch('"([%w_]+)"') do
  if writable[name] then
    globals[#globals + 1] = name
  else
    read_globals[#read_globals + 1] = name
  end
end

-- style the mods are full of and nobody is fixing: long lines, mixed
-- indentation, callback arguments the game passes and the mod ignores
max_line_length = false
unused_args = false
ignore = { "621" }
