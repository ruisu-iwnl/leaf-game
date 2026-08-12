# Setting up the "2X Grab", "Lucky Leaf", and "Leaf Patron" Game Passes

All three are Robux-only perks, sold as real Roblox Game Passes instead of a Coins purchase (see
`src/shared/PerkConfig.luau` and `src/server/GamePassPerks.luau`, which is fully generic across any
number of Robux-currency perks -- adding Lucky Leaf and Leaf Patron both needed zero changes there).
Game Passes can only be created through Roblox's own website/Creator Dashboard -- there's no way to
script this part, so this is the one piece you have to do by hand, once per Pass.

Leaf Patron is the premium VIP tier -- unlike the other two (a single numeric gameplay effect each),
it bundles four purely-cosmetic perks: an animated rainbow overhead nametag, a gold/purple-tinted
row design in the Results leaderboard, a neon footstep trail while moving, and three VIP-exclusive
tool skins (Patron Blower/Rake/Sack -- auto-granted the instant the perk itself is granted, nothing
extra to buy, see `CosmeticConfig.luau`'s `RequiresPerk` field and `PlayerUpgrades.GrantPerk`).

## 1. Publish the game (if you haven't already)

Game Passes belong to a published place. File > Publish to Roblox in Studio, even just privately/
unlisted -- it doesn't need to be public yet.

## 2. Create each Pass

Repeat these steps once per Pass (2X Grab, Lucky Leaf, Leaf Patron) -- do one at a time if you
want, no need to do all three in the same sitting.

1. Go to your game's page on [create.roblox.com](https://create.roblox.com) (or the Creator
   Dashboard), open your experience, and go to **Monetization > Passes**.
2. Click **Create a Pass**.
3. Upload the matching icon (all three already generated, 512x512, ready to upload as-is):
   - **2X Grab**: `docs/gamepass-2x-grab-icon.png` -- a gold "2X" coin badge with small leaf
     accents, matching the game's autumn palette.
   - **Lucky Leaf**: `docs/gamepass-lucky-leaf-icon.png` -- a green coin badge with a leprechaun
     hat glyph (rendered from `docs/gamepass-lucky-leaf-icon.svg`, same source-file workflow as the
     Badge icons in `docs/badges/`) and the same leaf-accent shape recolored clover-green, fitting
     the "every leaf could be a lucky one" theme.
   - **Leaf Patron**: `docs/gamepass-leaf-patron-icon.png` -- a royal purple coin badge with a gold
     crown glyph (rendered from `docs/gamepass-leaf-patron-icon.svg`, same workflow) and the same
     leaf-accent shape recolored gold, matching the perk's purple+gold VIP theme (same palette as
     the Patron tool skins, the nametag, and the footstep trail).
   Feel free to swap any of these for your own later.
4. Name it **"2X Grab"**, **"Lucky Leaf"**, or **"Leaf Patron"** to match. The description is
   public-facing marketing copy shown on the Pass's own Roblox store page (seen even by people not
   currently in your game), so it's worth being a little more descriptive than the terse in-game
   tooltip -- something like:
   - 2X Grab: *"Double your Coins from every leaf you clean up -- forever! A permanent 2x
     multiplier on all Coins earned from delivering leaves."*
   - Lucky Leaf: *"Every leaf you deliver has a 1-in-20 chance to pay out 3-5x Coins instead of the
     normal rate -- pure luck of the leaf!"*
   - Leaf Patron: *"Become a true Leaf Patron -- the ultimate VIP status! Get an animated rainbow
     name, a gold VIP look in the round results, a glowing neon footstep trail as you walk, and
     three exclusive Patron-only skins for your Blower, Rake, and Sack. Wear your support with
     pride!"*
   Purely cosmetic text either way -- nothing in the code reads it.
5. Set the **price in Robux** -- this is entirely controlled here, not by any file in this project.
6. Save/create the pass.

## 3. Copy each Game Pass Id

After creating one, its page URL looks like `.../game-pass/123456789/2X-Grab` (or `.../Lucky-Leaf`)
-- that number (`123456789`) is the `GamePassId`.

## 4. Paste them into the config

Open `src/shared/PerkConfig.luau` and replace each entry's placeholder:

```lua
GamePassId = 0, -- TODO: replace with the real Game Pass id
```

with the real number, e.g.:

```lua
GamePassId = 123456789,
```

`DoubleGrab`, `LuckyLeaf`, and `LeafPatron` each have their own `GamePassId` field -- you don't have
to do all three at once, any entry still at `0` is silently skipped everywhere (`GamePassPerks.luau`
treats 0 as "not set up yet", same convention as `BadgeConfig.luau`'s `BadgeId`). That's it either
way -- no other file needs to change. `GamePassPerks.luau` (server) checks real ownership on join
and grants the perk, and reacts immediately if someone buys it mid-session. `StorePanelUI.luau`
(client) already shows a green "R$ Buy" row for each and opens Roblox's own purchase prompt when
clicked, instead of a Coins confirm.

## 5. Test it

- **In Studio**: Play/Start, talk to Ruisu, open the shop, click the Pass's row in Perks. Studio
  treats Game Pass purchases as free test purchases while playtesting -- you won't be charged real
  Robux. (Roblox has a known quirk where `UserOwnsGamePassAsync` can occasionally lag behind a
  just-made test purchase inside the same Studio session -- if the row doesn't flip to "Owned"
  immediately, stop and restart Play mode once and it'll pick it up correctly on the next
  join-check.)
- **Live**: once published for real, buying it spends real Robux and grants the perk immediately
  via `PromptGamePassPurchaseFinished` -- no rejoin needed.
- Either way, confirm the right badge shows up in the Inventory panel's Active Perks row afterward:
  "2X" text for 2X Grab, the four-leaf-clover icon for Lucky Leaf, or the crown icon for Leaf Patron
  (`PerkIcons.luau`'s `BuildLuckyLeafIcon`/`BuildLeafPatronIcon`) -- that part needed zero changes to
  wire up per-perk, it already reads whatever `Perk_DoubleGrab`/`Perk_LuckyLeaf`/`Perk_LeafPatron`
  ends up set to, regardless of how it was earned.
- For Leaf Patron specifically, confirm all four effects: your name renders in an animated rainbow
  above your head (and everyone else's client sees it too -- it's not local-only), the three Patron
  skins show up already-owned (not for sale) in the Blower/Rake/Sack skin sections, a neon
  purple-to-blue trail follows your feet while walking (and fades out over ~8s after you stop), and
  your row in the post-round Results panel gets the purple/gold VIP treatment (plus a small crown
  next to your name) even if you didn't place top 3.
- For Lucky Leaf specifically, since the payout itself is random: deliver a large batch of leaves
  at once (a full sack works well) rather than one at a time, so you actually see a 5%-chance roll
  land within a reasonable number of tries.

## Notes

- `GamePassId = 0` is a safe "not set up yet" placeholder everywhere in the code -- clicking the row
  before you've done the steps above just shows a friendly "not set up yet" message instead of
  erroring.
- If you ever want a FOURTH Robux-only perk later, the pattern's fully generic: add
  `Currency = "Robux"` and a `GamePassId` to any entry in `PerkConfig.luau`, create its Pass the
  same way, and everything else (store UI, grant-on-join, grant-on-purchase) already handles it --
  no code changes needed. A perk can also bundle its own exclusive cosmetics the way Leaf Patron
  does -- add `RequiresPerk = "YourPerkId"` to a `CosmeticConfig.luau` entry and
  `PlayerUpgrades.GrantPerk`/`RemovePerk` will auto-grant/revoke it, no extra code needed there
  either.
