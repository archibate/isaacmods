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
- Agents can't see the running game. For runtime bugs: add a `print()` probe, have the
  user reproduce and read it back, fix from the data, then remove the probe.
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

Reproduction guides hand the user an exact console sequence in a fenced code block,
one command per line, copy-paste ready:

```
luamod goodtripfixed
restart 28
stage 7
giveitem c561
lua print(Isaac.GetPlayer(0).TearRange)
```

- Start with `luamod <modname>` (bare folder name, no `_workshopid` suffix) whenever the
  mod's Lua was just edited — it hot-reloads without a game restart.
- `restart <PlayerType>` picks the character; `giveitem cNNN` gives items (`tNNN` for
  trinkets); `stage N[a-d]` jumps floors; `lua print(Isaac.GetXX())` reads game state back.
- **Never quote an ID from memory** — models hallucinate them. Grep the ground truth
  first: `rg "ALMOND_MILK" isaac-lua-api/vanilla/enums.lua` (CollectibleType, PlayerType,
  EntityType, TrinketType...). Mind naming quirks: Tech X is `COLLECTIBLE_TECH_X`, not
  `TECHNOLOGY_X`.

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
