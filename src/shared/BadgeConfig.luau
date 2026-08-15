-- Catalog of Roblox Badges this game awards, same shape/reasoning as UpgradeConfig/PerkConfig/
-- CosmeticConfig -- purely data, kept separate from the check logic in BadgeSystem.luau (server)
-- so the criteria for each one lives in one obvious, readable place instead of scattered.
--
-- BadgeId starts at 0 (an id no real Roblox Badge can ever have) for every entry -- same "not set
-- up yet" placeholder pattern as PerkConfig.luau's GamePassId. BadgeSystem.luau treats 0 as "skip
-- silently" so nothing breaks before you've created the real Badges -- see docs/BADGES_SETUP.md.
--
-- Tier is purely cosmetic -- it picks which color the in-game popup's medal renders in
-- (BadgeNotificationUI.luau), no gameplay effect.
return {
	FirstSweep = {
		Id = "FirstSweep",
		Name = "First Sweep",
		Description = "Deliver your very first leaf.",
		Tier = "Bronze",
		BadgeId = 2943244015256403,
	},
	TidyYard = {
		Id = "TidyYard",
		Name = "Tidy Yard",
		Description = "Clean 100 leaves.",
		Tier = "Silver",
		BadgeId = 2326932281683595,
	},
	LeafWrangler = {
		Id = "LeafWrangler",
		Name = "Leaf Wrangler",
		Description = "Clean 1,000 leaves.",
		Tier = "Silver",
		BadgeId = 4084450635833854,
	},
	AutumnLegend = {
		Id = "AutumnLegend",
		Name = "Autumn Legend",
		Description = "Clean 10,000 leaves.",
		Tier = "Gold",
		BadgeId = 1628422551304118,
	},
	-- 10,000 turned out to be reachable pretty quickly -- these extend the same ladder further
	-- into genuine long-term/endgame territory, same spirit as the Coins ladder below.
	LeafMaster = {
		Id = "LeafMaster",
		Name = "Leaf Master",
		Description = "Clean 40,000 leaves.",
		Tier = "Silver",
		BadgeId = 1256862772626789,
	},
	LeafTycoon = {
		Id = "LeafTycoon",
		Name = "Leaf Tycoon",
		Description = "Clean 60,000 leaves.",
		Tier = "Silver",
		BadgeId = 2002025779415692,
	},
	LeafBaron = {
		Id = "LeafBaron",
		Name = "Leaf Baron",
		Description = "Clean 80,000 leaves.",
		Tier = "Gold",
		BadgeId = 1417822934033750,
	},
	LeafMogul = {
		Id = "LeafMogul",
		Name = "Leaf Mogul",
		Description = "Clean 100,000 leaves.",
		Tier = "Gold",
		BadgeId = 4249301079020422,
	},
	LeafDynasty = {
		Id = "LeafDynasty",
		Name = "Leaf Dynasty",
		Description = "Clean 500,000 leaves.",
		Tier = "Platinum",
		BadgeId = 2946057053969600,
	},
	LeafImmortal = {
		Id = "LeafImmortal",
		Name = "Leaf Immortal",
		Description = "Clean 1,000,000 leaves.",
		Tier = "Platinum",
		BadgeId = 4264426220716000,
	},

	PocketChange = {
		Id = "PocketChange",
		Name = "Pocket Change",
		Description = "Reach 1,000 Coins.",
		Tier = "Bronze",
		BadgeId = 4149068188970633,
	},
	CoinHoarder = {
		Id = "CoinHoarder",
		Name = "Coin Hoarder",
		Description = "Reach 25,000 Coins.",
		Tier = "Gold",
		BadgeId = 484854671302075,
	},
	-- Same reasoning/ladder shape as the Leaf* extensions above -- CoinsPerLeaf is 1 (see
	-- MoneyConfig.luau), so these line up on roughly the same scale as the Leaf ladder by default.
	CoinMagnate = {
		Id = "CoinMagnate",
		Name = "Coin Magnate",
		Description = "Reach 40,000 Coins.",
		Tier = "Silver",
		BadgeId = 4365311111144099,
	},
	CoinBaron = {
		Id = "CoinBaron",
		Name = "Coin Baron",
		Description = "Reach 60,000 Coins.",
		Tier = "Silver",
		BadgeId = 802982505066428,
	},
	CoinTycoon = {
		Id = "CoinTycoon",
		Name = "Coin Tycoon",
		Description = "Reach 80,000 Coins.",
		Tier = "Gold",
		BadgeId = 3359724448435698,
	},
	CoinMogul = {
		Id = "CoinMogul",
		Name = "Coin Mogul",
		Description = "Reach 100,000 Coins.",
		Tier = "Gold",
		BadgeId = 370934028919633,
	},
	CoinDynasty = {
		Id = "CoinDynasty",
		Name = "Coin Dynasty",
		Description = "Reach 500,000 Coins.",
		Tier = "Platinum",
		BadgeId = 2885993920452880,
	},
	CoinImmortal = {
		Id = "CoinImmortal",
		Name = "Coin Immortal",
		Description = "Reach 1,000,000 Coins.",
		Tier = "Platinum",
		BadgeId = 1955848720128050,
	},

	Upgraded = {
		Id = "Upgraded",
		Name = "Upgraded",
		Description = "Buy your first upgrade.",
		Tier = "Bronze",
		BadgeId = 3657817993636453,
	},
	FullyLoaded = {
		Id = "FullyLoaded",
		Name = "Fully Loaded",
		Description = "Own every upgrade.",
		Tier = "Silver",
		BadgeId = 2147202474230529,
	},

	Fashionista = {
		Id = "Fashionista",
		Name = "Fashionista",
		Description = "Own your first cosmetic skin.",
		Tier = "Bronze",
		BadgeId = 0,
	},

	TwoXGrabber = {
		Id = "TwoXGrabber",
		Name = "2X Grabber",
		Description = "Own the 2X Grab perk.",
		Tier = "Silver",
		BadgeId = 0,
	},
	LuckyLeafOwner = {
		Id = "LuckyLeafOwner",
		Name = "Lucky Leaf",
		Description = "Own the Lucky Leaf perk.",
		Tier = "Silver",
		BadgeId = 0,
	},
	LeafPatronOwner = {
		Id = "LeafPatronOwner",
		Name = "Leaf Patron",
		Description = "Own the Leaf Patron VIP perk.",
		Tier = "Gold",
		BadgeId = 0,
	},
}
