# Setting up the 24 Badges

Like Game Passes, Roblox Badges can only be created through the website/Creator Dashboard -- there's
no API for it, so this is the one manual step. Everything else (awarding, the popup notification,
idempotency, retroactive awards for existing saves) is already fully wired -- see
`src/shared/BadgeConfig.luau` and `src/server/BadgeSystem.luau`.

## 1. Publish the game (if you haven't already)

Same requirement as Game Passes -- Badges belong to a published place.

## 2. Create each Badge

1. Go to your game's page on [create.roblox.com](https://create.roblox.com), open your experience,
   and go to **Engagement > Badges** (or **Monetization > Badges** depending on the current layout).
2. Click **Create a Badge**.
3. Upload the matching icon from `docs/badges/` (512x512, ready to upload as-is -- a tier-colored
   medal with a simple glyph and small leaf accents, consistent with the Game Pass icon's look).
4. Use the Name and Description below exactly, copy-pasted straight into the form's fields (the
   in-game popup shows this SAME text from `BadgeConfig.luau`, so keeping them matched avoids
   confusion). Tick each box off as you go -- you don't have to do all 22 in one sitting.

> **On hold:** stopped after Leaf Immortal -- Roblox rate-limits how many Badges/assets you can
> create within a 24-hour window. First Sweep through Leaf Immortal are created; everything below is
> paused until that window clears, then just pick back up in the same order.

### Leaves cleaned (lifetime)

- [x] **First Sweep**
  - Icon: `docs/badges/FirstSweep.png`
  - Name: `First Sweep`
  - Description: `Deliver your very first leaf.`
- [x] **Tidy Yard**
  - Icon: `docs/badges/TidyYard.png`
  - Name: `Tidy Yard`
  - Description: `Clean 100 leaves.`
- [x] **Leaf Wrangler**
  - Icon: `docs/badges/LeafWrangler.png`
  - Name: `Leaf Wrangler`
  - Description: `Clean 1,000 leaves.`
- [x] **Autumn Legend**
  - Icon: `docs/badges/AutumnLegend.png`
  - Name: `Autumn Legend`
  - Description: `Clean 10,000 leaves.`
- [x] **Leaf Master**
  - Icon: `docs/badges/LeafMaster.png`
  - Name: `Leaf Master`
  - Description: `Clean 40,000 leaves.`
- [x] **Leaf Tycoon**
  - Icon: `docs/badges/LeafTycoon.png`
  - Name: `Leaf Tycoon`
  - Description: `Clean 60,000 leaves.`
- [x] **Leaf Baron**
  - Icon: `docs/badges/LeafBaron.png`
  - Name: `Leaf Baron`
  - Description: `Clean 80,000 leaves.`
- [x] **Leaf Mogul**
  - Icon: `docs/badges/LeafMogul.png`
  - Name: `Leaf Mogul`
  - Description: `Clean 100,000 leaves.`
- [x] **Leaf Dynasty**
  - Icon: `docs/badges/LeafDynasty.png`
  - Name: `Leaf Dynasty`
  - Description: `Clean 500,000 leaves.`
- [x] **Leaf Immortal**
  - Icon: `docs/badges/LeafImmortal.png`
  - Name: `Leaf Immortal`
  - Description: `Clean 1,000,000 leaves.`

### Coins (current balance)

- [ ] **Pocket Change**
  - Icon: `docs/badges/PocketChange.png`
  - Name: `Pocket Change`
  - Description: `Reach 1,000 Coins.`
- [ ] **Coin Hoarder**
  - Icon: `docs/badges/CoinHoarder.png`
  - Name: `Coin Hoarder`
  - Description: `Reach 25,000 Coins.`
- [ ] **Coin Magnate**
  - Icon: `docs/badges/CoinMagnate.png`
  - Name: `Coin Magnate`
  - Description: `Reach 40,000 Coins.`
- [ ] **Coin Baron**
  - Icon: `docs/badges/CoinBaron.png`
  - Name: `Coin Baron`
  - Description: `Reach 60,000 Coins.`
- [ ] **Coin Tycoon**
  - Icon: `docs/badges/CoinTycoon.png`
  - Name: `Coin Tycoon`
  - Description: `Reach 80,000 Coins.`
- [ ] **Coin Mogul**
  - Icon: `docs/badges/CoinMogul.png`
  - Name: `Coin Mogul`
  - Description: `Reach 100,000 Coins.`
- [ ] **Coin Dynasty**
  - Icon: `docs/badges/CoinDynasty.png`
  - Name: `Coin Dynasty`
  - Description: `Reach 500,000 Coins.`
- [ ] **Coin Immortal**
  - Icon: `docs/badges/CoinImmortal.png`
  - Name: `Coin Immortal`
  - Description: `Reach 1,000,000 Coins.`

### Store ownership

- [ ] **Upgraded**
  - Icon: `docs/badges/Upgraded.png`
  - Name: `Upgraded`
  - Description: `Buy your first upgrade.`
- [ ] **Fully Loaded**
  - Icon: `docs/badges/FullyLoaded.png`
  - Name: `Fully Loaded`
  - Description: `Own every upgrade.`
- [ ] **Fashionista**
  - Icon: `docs/badges/Fashionista.png`
  - Name: `Fashionista`
  - Description: `Own your first cosmetic skin.`
- [ ] **2X Grabber**
  - Icon: `docs/badges/TwoXGrabber.png`
  - Name: `2X Grabber`
  - Description: `Own the 2X Grab perk.`
- [ ] **Lucky Leaf**
  - Icon: `docs/badges/LuckyLeaf.png`
  - Name: `Lucky Leaf`
  - Description: `Own the Lucky Leaf perk.`
- [ ] **Leaf Patron**
  - Icon: `docs/badges/LeafPatronOwner.png`
  - Name: `Leaf Patron`
  - Description: `Own the Leaf Patron VIP perk.`

## 3. Copy each Badge Id

Same as Game Passes -- after creating a Badge, its page URL looks like
`.../badge/987654321/First-Sweep`. That number is the `BadgeId`.

## 4. Paste them into the config

Open `src/shared/BadgeConfig.luau` and replace each entry's placeholder:

```lua
BadgeId = 0,
```

with the real id, e.g.:

```lua
BadgeId = 987654321,
```

You don't have to do all 22 at once -- any entry still at `0` is silently skipped everywhere
(`BadgeSystem.luau` treats 0 as "not set up yet", same convention as `PerkConfig.luau`'s
`GamePassId`), so you can create and wire them up one at a time.

## 5. Test it

- `:testbadge me <id>` (e.g. `:testbadge me FirstSweep`) previews the popup notification instantly,
  with no BadgeService call at all -- safe to run as many times as you want, even before the real
  Badge exists, to check how it looks/animates.
- `:addbadge me <id>` awards the REAL badge directly (bypassing its normal criteria) -- useful for
  confirming the actual BadgeService award works end-to-end, but note Roblox has no "revoke" API
  (same limitation as Game Passes), so this is permanent once the id is real. Use `:testbadge`
  instead for repeated visual checks.
- Playing normally (cleaning leaves, earning Coins, buying upgrades/perks/cosmetics) triggers the
  real checks automatically -- see `BadgeSystem.CheckDeliveryMilestones`/`CheckOwnershipMilestones`
  in `src/server/BadgeSystem.luau` for exactly which action checks which badge.
- A returning player's already-saved progress is re-checked once on load, so anyone who already
  passed a threshold before you finished this setup gets it retroactively the next time they join
  -- no need to manually backfill existing players.

## Notes

- `docs/badges/*.svg` are the source files the PNGs were rendered from, if you want to tweak a
  design later (recolor, swap the glyph, etc.) rather than starting from scratch.
- If you want to add an 11th badge later: add an entry to `BadgeConfig.luau`, add whatever
  `award(player, "YourNewId")` check makes sense in `BadgeSystem.luau` (or reuse an existing
  Check* function if it fits one of the two categories already there), create the Badge on Roblox,
  and fill in its id -- no changes needed anywhere else (the popup, queueing, and admin commands
  are all already generic across every entry in the catalog).
