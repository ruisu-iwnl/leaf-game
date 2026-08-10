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

## Notes

- Ids are matched case-insensitively; an unknown id prints the full list of valid ids for that
  catalog back to Output.
- Catalogs live in `src/shared/UpgradeConfig.luau`, `PerkConfig.luau`, `CosmeticConfig.luau`, and
  `BadgeConfig.luau` -- this table should be kept in sync whenever those change.
