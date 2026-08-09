# Isaac Mod Authorship Workspace

archibate (小彭老师) develops *Binding of Isaac* mods here — each subdirectory is one
mod's source. Open this directory as the editor root so the shared `.luarc.json`
(Isaac API globals + stubs) covers every mod.

## What to know

- **Repentance+ is Windows-only.** On Linux, Steam defaults to the Linux build, which
  lacks the Repentance DLC — mods that need it won't run. The game must be forced to
  run under Proton to get Rep+.
- **Mods dir:** `~/.local/share/Steam/steamapps/common/The Binding of Isaac Rebirth/mods/`.
  Each mod is a folder; its real name/version lives in `metadata.xml`, not the folder name.
- **Workshop sync:** subscribed items are folders named `<name>_<workshopid>`, and Steam
  overwrites them on sync. To develop safely, symlink your source into the mods dir under
  the **bare** name (no `_id`) — Steam ignores unnumbered folders, so your edits survive.
- **`disable.it`:** an empty file named `disable.it` inside a mod folder toggles that mod
  off. Use it to disable the workshop copy so it doesn't shadow your dev symlink. (One
  accidentally left in your dev folder silently breaks the mod.)
- **`luamod <name>`** in the in-game console hot-reloads a mod's Lua (enable the console
  via `options.ini`). No restart needed.
- **Version check:** `REPENTANCE_PLUS` is `true` on Rep+, `nil` on old Rep; `REPENTANCE`
  is `true` on both. Gate version-specific behavior on `REPENTANCE_PLUS`.

## Working here

- Runtime is **Lua 5.3**; `luac -p main.lua` catches syntax errors, not logic bugs.
- `luac -o /tmp/x.out -l -l main.lua | rg -o '_ENV "\w+"' | sort -u` lists every global
  the file touches. Anything there that is not an Isaac or Lua global is a typo or a
  function used above where it is defined — a crash `luac -p` cannot see. Run it after
  every edit, before asking anyone to play.
- Agents can't see the running game. For runtime bugs: instrument with
  `Isaac.DebugString`, have the user run the reproduction, read `log.txt` yourself, fix
  from the data, then remove the instrument. See the Console Repro Contract below.
- Map/teleport code carries hand-tuned pixel offsets that differ across game versions and
  in mirror world — measure in-game, don't guess.
- Verify game mechanics against WebSearch before matching them in code.

## Testing Contract

When provided with Steam community comments on mods, extract bug reports and feature
requests into bullet points for the user to review. Not every request deserves a fix:
non-bugs get a "won't fix" (just explain why in a reply); niche requests go behind
MCM-gated if-paths, default off — the majority keeps the familiar behavior while the
minority still gets served.

Do bug fixes one by one, never several fixes in parallel. The workflow for each fix:

1. Leave the mod unfixed. Write a reproduction guide based on the comment.
2. The user reproduces the phenomenon successfully.
3. Implement your fix.
4. The user tries to reproduce again — confirm the bug is gone and nothing else broke.
5. Append one changelog line describing the bug fixed or feature implemented.

Fix not converging? Probe loop: form hypotheses, add instrument logs, debug together
with the user.

## Console Repro Contract

Reproductions run through `devrepro/`, not through copy-paste. Write the command list
into the `STEPS` table of `devrepro/main.lua`, put anything the user must do by hand
into `HINT`, and ask them to press **F1**. The driver reloads itself first, so the list
that runs is always the one just written.

```lua
local STEPS = {
    "luamod goodtripfixed",
    "restart 0", 10,
    "debug 3",
    "stage 7", 10,
    "giveitem c561",
}

local HINT = "walk into the boss room and fire once"
```

- A string is a console command; a number is that many frames to wait. `restart` and
  `stage` only take effect on a later frame, so each needs a wait behind it.
- One press is one whole run. Never ask for a command to be typed by hand partway
  through — everything the run needs belongs in the list. Comparing two characters, or
  two active items, is two runs: rewrite the list and ask for a second press.
- Start with `luamod <modname>` (bare folder name, no `_workshopid` suffix) so the mod
  under test picks up its latest Lua.
- `restart <PlayerType>` picks the character; `giveitem cNNN` gives items (`tNNN` for
  trinkets, `kNN` for cards); `stage N[a-d]` jumps floors.
- `debug <N>`: enable testing cheats accordingly to help user reproduce easy — `3` invincibility (prevent player death during test), `4` +40 damage (kills faster), `8` active always charged (to allow test active items repeatitively), `6` draws each entity's damage hitbox as a circle (see what a shot actually covers), `9` very high luck (luck-gated tear effects fire more often), `10` quick kill enemies (useful when need to walk through rooms). Run again to toggle off. Flags clear on restart.
- `lua print(...)`: run lua expression.
- `spawn <Type>.<Variant>.<Subtype>`: spawn entity by type.
- Bombs, keys or coins needed? `giveitem c190` (Pyro) fills bombs, `c17` (Skeleton Key)
  keys, `c18` (A Dollar) coins — each fills the counter, so nobody scrounges mid-test.
- Target dummy: `spawn 408.0.0` (Hush, skinless) by default — a cut enemy that stands
  still and has no attack beyond contact. `spawn 36.0.1` (Gurdy) when the test wants a
  crowd, since it keeps spawning flies — chaining and group-hitting weapons need one.
  `spawn 20.0.2` (Monstro) when it wants a target that moves and jumps.
- **Never quote an ID from memory** — models hallucinate them. Grep the ground truth
  first: `rg "ALMOND_MILK" isaac-lua-api/vanilla/enums.lua` (CollectibleType, PlayerType,
  EntityType, CardType, TrinketType...).
- `restart` and `stage` takes time to take effect, so a `10` frame delay is required.
- To read something out of the game instead — an enum, the item table, any state — rewrite
  the driver's `dump()` and ask for **F2**.

Read the outcome yourself instead of asking the user to describe it. Instrument the mod
under test with `Isaac.DebugString("[TAG] ...")` — state it prints, the board it draws,
whichever branch is in question — and once the user says the reproduction is done, read
`~/.local/share/Steam/steamapps/compatdata/250900/pfx/drive_c/users/steamuser/Documents/My Games/Binding of Isaac Repentance+/log.txt`
and grep the tag. A dedup guard is worth it on anything that fires per frame. Strip the
instruments before the fix is called done.

## API references

- **Local stubs** (EmmyLua, greppable, power the Lua language server): `isaac-lua-api/`,
  cloned from `filloax/isaac-api-autocomplete-lua`. `.luarc.json` loads `vanilla/` +
  `no_repentogon_only/` (the `repentogon_*` folders are for the separate REPENTOGON
  loader — don't enable unless the mod uses it). Update with `git -C isaac-lua-api pull`.
- **IsaacDocs** (prose + examples, greppable): https://wofsauge.github.io/IsaacDocs/rep/
  Mirrored locally at `isaac-docs/` (markdown source, `docs/` tree — `images/` and
  `customData/` hidden via sparse-checkout to keep it lean). `rg isaac-docs/docs` for
  callback signatures, entity/boss tables, XML refs, and code examples offline.
  Update with `git -C isaac-docs pull`.
- **Gameplay wiki** (game mechanics explained, human-readable): https://bindingofisaacrebirth.wiki.gg

## Also here

- `isaac-spinfix/` — patch for Rep+'s render thread pinning a CPU core under Wine.
- `steamcomments` — fetch a mod's workshop comments from CLI (folder name or workshop id), no login needed.
- `moduploader` — launch Isaac's ModUploader to publish a mod release to the workshop (requires user GUI clicks).
