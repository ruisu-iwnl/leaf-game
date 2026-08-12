# Admin Commands

Dev/testing commands for Leaf Blower. Not player-facing -- feedback goes to the server Output
window, not any in-game UI.

## Access

- Press **`` ` `` (backtick)** in-game to open the command bar (bottom-center), type a command, hit
  **Enter**.
- Allowed for: the game's owner (`game.CreatorId`), any username listed in
  `src/shared/AdminConfig.luau`'s `ExtraAdmins`, and **anyone testing inside Studio** (so you're
  never locked out of your own unpublished place).
- `<player|me>` accepts `me` (always resolves to whoever ran the command), an exact username, or a
  case-insensitive partial match (e.g. `lu` for `Luis123`) -- ambiguous partial matches are
  rejected rather than guessed.

Source: `src/server/AdminCommands.luau`.

## Money

| Command | Effect |
|---|---|
| `:addmoney <player\|me> <amount>` | Gives Coins. |
| `:wipemoney <player\|me>` | Resets Coins to 0. |

## Sacks

| Command | Effect |
|---|---|
| `:fixsacks <player\|me>` | Resyncs `ActiveSackCount` to match the sacks the player actually has -- fixes a "counter says 2/3 but nothing's in the hotbar" desync without needing a rejoin. |

## Upgrades

`:addupgrade <player|me> <id>` / `:removeupgrade <player|me> <id>`

| Id | Name | Price | Effect |
|---|---|---|---|
| `RakeCooldown` | Fast Rake | 1000 | Rake cooldown drops to 1s. |
| `BlowerOverheat` | Bigger Tank | 1000 | Overheat cap 100 -> 150 (~50% more time before overheating). |
| `SackCapacity` | Extra Sack | 1000 | Max active sacks 3 -> 4. |

## Perks

`:addperk <player|me> <id>` / `:removeperk <player|me> <id>`

| Id | Name | Price | Effect |
|---|---|---|---|
| `DoubleGrab` | 2X Grab | Robux (Game Pass -- see `docs/GAMEPASS_SETUP.md`) | Every leaf delivered is worth double Coins. |

`:addperk`/`:removeperk` still work on `DoubleGrab` for quick testing (they just set/clear the same
`Perk_DoubleGrab` attribute a real Game Pass purchase would) -- they bypass Robux entirely, same as
they'd bypass Coins for any other perk.

## Cosmetics

`:addcosmetic <player|me> <id>` / `:removecosmetic <player|me> <id>`

These only grant **ownership** -- they don't equip the skin. Use the store panel (talk to Ruisu) to
actually wear an owned skin, or call the `EquipCosmetic` remote directly for automated testing.

| Id | Name | Tool | Price |
|---|---|---|---|
| `BlowerCrimson` | Crimson Blower | Blower | 5000 |
| `BlowerEvergreen` | Evergreen Blower | Blower | 10000 |
| `RakeGolden` | Golden Rake | Rake | 10000 |
| `RakeCharcoal` | Charcoal Rake | Rake | 5000 |
| `SackHarvest` | Harvest Sack | Sack | 5000 |
| `SackFrost` | Frost Sack | Sack | 10000 |

`Default` is always owned/equippable for every tool and isn't a catalog id -- nothing to add/remove.

## Badges

`:addbadge <player|me> <id>` / `:testbadge <player|me> <id>` -- see `docs/BADGES_SETUP.md` for the
full list of 10 badges, their criteria, and how to create the real Roblox Badges.

- `:addbadge` awards the REAL badge via BadgeService, bypassing its normal criteria. Permanent --
  Roblox has no revoke API, so there's no `:removebadge`.
- `:testbadge` only fires the client-side popup notification, no BadgeService call at all -- safe to
  run repeatedly to preview the animation, even before the real Badge has been created.

## Quests

`:resetquest <player|me> <id|all>`

Clears a player's quest state (both "started" and "completed", plus any chain quest's per-objective
progress -- see `QuestObjectives.luau`) and immediately restarts it -- not just a silent flag reset.
If the quest announces a "Quest Started" toast (`QuestConfig.<id>.AnnounceStart` isn't `false`), that
toast fires again too, so this reproduces the full live flow a real fresh start would give, not just
next-rejoin behavior. Resetting a chain quest whose prerequisite isn't ALSO complete just clears it
(stays hidden in Quest Log, per that system's "don't reveal follow-ups early" design) instead of
force-starting it out of order. `all` uses a genuinely different two-pass reset (`QuestSystem.
ResetAllQuests`) rather than looping the single-id reset, specifically so a chain's ordering can never
leave a stale "started" flag behind on a downstream quest.

| Id | Name | Notes |
|---|---|---|
| `Tutorial` | Getting Started | Given by the Lobby's "Ruisu" guide rig. Resetting brings back `QuestPathUI`'s guiding path live, in the same session. Its own "Quest Started" toast is suppressed by design (`AnnounceStart = false`) -- only "Quest Completed" (+200 Coins) ever shows for this one. |
| `GettingStarted2` | Getting Started II | Unlocks only once `Tutorial` is completed (`RequiresQuest`) -- hidden from Quest Log until then. 3 objectives (deliver 100 leaves, use the Rake 5 times, handpick 50 leaves into a sack), all must complete for the quest itself to auto-complete -- no client "Show me!" step. |
| `GettingStarted3` | Getting Started III | Unlocks only once `GettingStarted2` is completed. 1 objective: buy any upgrade from the Store. |

`all` resets every quest in `QuestConfig` at once (today that's just `Tutorial`, but stays useful as
more get added). See `CLAUDE.md`'s Quest System section for the full Started/Completed/reward
lifecycle this routes through (`QuestSystem.ResetQuest`, not `PlayerQuests.ResetQuest` directly).

## Rounds

`:finishround`

Force-ends the current round immediately, as if the timer had just expired (counts as a Timer end,
not a Goal one), skipping straight to Results -- for testing the Active -> Results -> Intermission
tail of the round loop without sitting through a full round. No target player (affects the whole
server's round). Only works during an `Active` round; warns and no-ops otherwise.

## Leaves

`:goldenleaf <percent|reset>`

Overrides the Golden Leaf spawn chance (`LeafConfig.luau`'s `GoldenLeafChance`, normally ~1.5%) for
every Yard leaf spawned from that point on, without editing `LeafConfig.luau` itself. `percent` is
0-100 (e.g. `:goldenleaf 100` makes every newly-spawned leaf golden); `:goldenleaf reset` (or
`default`) goes back to the normal rare chance. No target player -- global, since there's only one
server-side spawn loop. Running it with no argument prints the current chance to Output instead of
changing anything. Already-spawned leaves are unaffected either way (the roll only happens at spawn
time); only leaves the spawn loops create AFTER the command runs are affected.

:goldenleaf 100
:goldenleaf reset

## Notes

- Ids are matched case-insensitively; an unknown id prints the full list of valid ids for that
  catalog back to Output.
- Catalogs live in `src/shared/UpgradeConfig.luau`, `PerkConfig.luau`, `CosmeticConfig.luau`,
  `BadgeConfig.luau`, and `QuestConfig.luau` -- this table should be kept in sync whenever those
  change.
