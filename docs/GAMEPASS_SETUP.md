# Setting up the "2X Grab" Game Pass

The 2X Grab perk is now Robux-only, sold as a real Roblox Game Pass instead of a Coins purchase
(see `src/shared/PerkConfig.luau` and `src/server/GamePassPerks.luau`). Game Passes can only be
created through Roblox's own website/Creator Dashboard -- there's no way to script this part, so
this is the one piece you have to do by hand.

## 1. Publish the game (if you haven't already)

Game Passes belong to a published place. File > Publish to Roblox in Studio, even just privately/
unlisted -- it doesn't need to be public yet.

## 2. Create the Pass

1. Go to your game's page on [create.roblox.com](https://create.roblox.com) (or the Creator
   Dashboard), open your experience, and go to **Monetization > Passes**.
2. Click **Create a Pass**.
3. Upload an icon. A simple one is already generated for you at
   `docs/gamepass-2x-grab-icon.png` (512x512, ready to upload as-is) -- a gold "2X" coin badge with
   small leaf accents, matching the game's autumn palette. Feel free to swap it for your own later.
4. Name it something like **"2X Grab"**. The description is public-facing marketing copy shown on
   the Pass's own Roblox store page (seen even by people not currently in your game), so it's worth
   being a little more descriptive than the terse in-game tooltip -- something like:
   *"Double your Coins from every leaf you clean up -- forever! A permanent 2x multiplier on all
   Coins earned from delivering leaves."* Purely cosmetic text either way -- nothing in the code
   reads it.
5. Set the **price in Robux** -- this is entirely controlled here, not by any file in this project.
6. Save/create the pass.

## 3. Copy the Game Pass Id

After creating it, its page URL looks like `.../game-pass/123456789/2X-Grab` -- that number
(`123456789`) is the `GamePassId`.

## 4. Paste it into the config

Open `src/shared/PerkConfig.luau` and replace the placeholder:

```lua
GamePassId = 0, -- TODO: replace with the real Game Pass id
```

with the real number:

```lua
GamePassId = 123456789,
```

That's it -- no other file needs to change. `GamePassPerks.luau` (server) checks real ownership on
join and grants the perk, and reacts immediately if someone buys it mid-session.
`StorePanelUI.luau` (client) already shows a green "R$ Buy" row for it and opens Roblox's own
purchase prompt when clicked, instead of a Coins confirm.

## 5. Test it

- **In Studio**: Play/Start, talk to Ruisu, open the shop, click 2X Grab's row. Studio treats Game
  Pass purchases as free test purchases while playtesting -- you won't be charged real Robux.
  (Roblox has a known quirk where `UserOwnsGamePassAsync` can occasionally lag behind a just-made
  test purchase inside the same Studio session -- if the row doesn't flip to "Owned" immediately,
  stop and restart Play mode once and it'll pick it up correctly on the next join-check.)
- **Live**: once published for real, buying it spends real Robux and grants the perk immediately
  via `PromptGamePassPurchaseFinished` -- no rejoin needed.
- Either way, confirm the "2X" badge shows up in the Inventory panel's Active Perks row afterward
  (that part needed zero changes -- it already reads whatever `Perk_DoubleGrab` ends up set to,
  regardless of how it was earned).

## Notes

- `GamePassId = 0` is a safe "not set up yet" placeholder everywhere in the code -- clicking the row
  before you've done the steps above just shows a friendly "not set up yet" message instead of
  erroring.
- If you ever want a SECOND Robux-only perk later, the pattern's fully generic: add
  `Currency = "Robux"` and a `GamePassId` to any entry in `PerkConfig.luau`, create its Pass the
  same way, and everything else (store UI, grant-on-join, grant-on-purchase) already handles it --
  no code changes needed.
