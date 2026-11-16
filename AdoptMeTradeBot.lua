--!nocheck
--[[============================================================================
    AdoptMe Trade Bot  v1.0.0
    ------------------------------------------------------------------------
    AFK trade assistant for Adopt Me (Roblox).

      * auto-accepts incoming trade requests
      * reads both sides of the trade window (pets / pet wear / strollers / ...)
      * prices every item with https://amvgg.com/values
      * auto-fills your side from your inventory so the deal stays profitable
      * accepts / declines automatically
      * mirrors every offer to a Discord webhook

    Same conventions as the AdoptMe Farm loader: persistent settings table,
    feature toggles, safe pcall startup and a start_error.txt log.

    Load:
        loadstring(game:HttpGet("<raw url>"))()

    Everything lives in the "AdoptMeTradeBot" folder next to the executor
    workspace. Re-running the script keeps your settings.
============================================================================]]

local BOT = {
    Name    = "AdoptMeTradeBot",
    Version = "1.0.0",
    Folder  = "AdoptMeTradeBot",
}
BOT.SettingsFile = BOT.Folder .. "/settings.json"
BOT.ValuesFile   = BOT.Folder .. "/values.lua"
BOT.GuiDumpFile  = BOT.Folder .. "/gui_dump.txt"
BOT.LogFile      = BOT.Folder .. "/log.txt"
BOT.ErrorFile    = BOT.Folder .. "/start_error.txt"

--============================================================== 0. sandbox
local genv = _G
do
    local ok, fn = pcall(function() return getgenv end)
    if ok and type(fn) == "function" then
        local ok2, env = pcall(fn)
        if ok2 and type(env) == "table" then genv = env end
    end
end

local function G(name, fallback)
    local v = genv[name]
    if v == nil then v = _G[name] end
    if v == nil then return fallback end
    return v
end

local writefile = G("writefile")
local readfile  = G("readfile")
local isfile    = G("isfile")
local isfolder  = G("isfolder")
local makefolder= G("makefolder")
local getconnections = G("getconnections")
local firesignal = G("firesignal")

local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

--============================================================== 1. logging
local LogLines = {}

local function log(fmt, ...)
    local msg
    if select("#", ...) > 0 then
        local ok, res = pcall(string.format, fmt, ...)
        msg = ok and res or tostring(fmt)
    else
        msg = tostring(fmt)
    end
    local line = string.format("[%s] %s", os.date("%H:%M:%S"), msg)
    table.insert(LogLines, line)
    if #LogLines > 60 then table.remove(LogLines, 1) end
    if BOT.pushLog then pcall(BOT.pushLog, line) end
    if writefile and BOT.FolderReady then
        pcall(function()
            local body = table.concat(LogLines, "\n")
            writefile(BOT.LogFile, body)
        end)
    end
end

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 4,
        })
    end)
end

--============================================================== 2. http
local function httpRequest(opts)
    local fn
    local syn = G("syn")
    if syn and syn.request then fn = syn.request end
    if not fn then
        local h = G("http")
        if h and h.request then fn = h.request end
    end
    if not fn then fn = G("http_request") end
    if not fn then fn = G("request") end
    if not fn then return nil, "executor has no HTTP function (syn.request / http_request / request)" end

    local ok, res = pcall(fn, opts)
    if not ok then return nil, tostring(res) end
    if type(res) ~= "table" then return nil, "bad http response" end
    return res.Body or res.body, res.StatusCode or res.status or res.Status
end

local USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " ..
                   "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

local function httpGet(url)
    return httpRequest({
        Url = url,
        Method = "GET",
        Headers = {
            ["User-Agent"] = USER_AGENT,
            ["Accept"] = "text/html,application/xhtml+xml",
        },
    })
end

--============================================================== 3. settings
local DEFAULT_SETTINGS = {
    -- master
    Enabled = true,

    -- incoming trade requests
    AutoAcceptRequests = true,

    -- outgoing trade requests (best effort, UI driven)
    AutoRequestTrades  = false,
    TradeTargetsText   = "",
    RequestInterval    = 8,
    UseRemoteFallback  = false,

    -- offer handling
    AutoAcceptOffers  = true,
    MinAcceptRatio    = 1.05,   -- their value must be >= your value * this
    MaxAcceptRatio    = 4.00,   -- above this the offer looks like bait -> skip
    MinOfferValue     = 0.02,   -- ignore micro offers
    RequireKnownValue = true,   -- refuse to accept if an item has no price
    RequireWantedItem = false,  -- only accept if the offer contains a wanted item
    AutoDeclineBad    = true,   -- actually press Decline instead of just waiting
    ConfirmAccepts    = true,

    -- filling your side of the trade
    AutoFill       = true,
    FillMode       = "profit",  -- "profit" | "fair" | "manual"
    MaxItemsToGive = 4,
    NeverGiveLastPet = false,

    -- value modifiers (amvgg base values are normal / no fly-ride)
    FlyMult   = 1.03,
    RideMult  = 1.05,
    NeonMult  = 2.20,
    MegaMult  = 5.00,

    -- discord
    WebhookUrl       = "",
    WebhookMention   = "",
    NotifyAllOffers  = true,
    NotifyAccepted   = true,
    NotifyDeclined   = false,

    -- kiria persona (optional module: friendly lines + gifs on top of the cards)
    KiriaEnabled     = true,
    KiriaUrl         = "https://raw.githubusercontent.com/Amivictim/kiria/refs/heads/main/Kiria.lua",

    -- trading hub phone (best effort: labels are read from the real UI)
    PhoneEnabled        = false,
    PhoneDryRun         = true,    -- only log what it would click
    PhoneAutoOpen       = true,    -- try to use the phone toy
    PhoneAutoAcceptOffers = true,
    PhoneAutoDeclineBad = true,
    PhoneOfferSwap      = true,
    PhoneAutoList       = false,   -- posting costs 100 bucks each
    PhoneMinOfferValue  = 0,       -- absolute floor for an offer on a listing
    PhoneListedValue    = 0,       -- value of a listing posted by hand
    PhoneUpgradeMinPct  = 10,      -- smallest gain an ask listing should bring
    PhoneUpgradeMaxPct  = 60,      -- stay under the game's fairness guardrails
    PhoneBucksMax       = 300,     -- stop posting after this many bucks per session
    PhoneDuplicatesOnly = true,    -- only list pets you own two or more of
    PhoneGiveMinValue   = 0.05,    -- never list cheaper items than this
    PhoneScanInventory  = true,    -- read the real inventory before posting
    PhoneInvMaxAge      = 300,     -- rescan the inventory after this many seconds
    PhoneInvPasses      = 6,       -- how many scroll passes a full scan may take
    PhoneUpgradeSteps   = 4,       -- how deep the upgrade chain may go
    PhoneMaxListings    = 2,
    PhoneAutoLearn      = true,    -- dump the phone face and remember real button paths
    PhoneAutoOffer      = false,   -- search listings on the phone and send profitable offers
    PhoneOfferEvery     = 90,      -- seconds between listing searches
    PhoneAutoTravel     = true,    -- use TRAVEL TO HUB when Robo Todd is far away
    PhoneCreatePath     = "",
    PhoneNextPath       = "",
    PhonePostPath       = "",
    PhoneMaxOffers      = 20,
    PhoneRefreshMin     = 20,
    PhoneLoopDelay      = 1.5,

    -- behaviour
    OurSideIsLeft = true,       -- flip if the bot reads your offer as theirs
    Delay         = 0.45,
    Debug         = false,
    ClickRecorder = false,      -- log every click you make (for mapping the real UI)
    ToggleKey     = "RightControl",

    -- lists (newline separated)
    TradePoolText = "",         -- names you may give away ("" = everything except Keep)
    KeepListText  = "",         -- names that must never be given away
    WantedText    = "",         -- names you want to receive
    AliasText     = "",         -- "InGame Name = amvgg name" per line
}

local S = {}
for k, v in pairs(DEFAULT_SETTINGS) do S[k] = v end

local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == type(dst[k]) or dst[k] == nil then
            dst[k] = v
        end
    end
end

local function saveSettingsNow()
    if not writefile then return end
    local ok, body = pcall(function() return HttpService:JSONEncode(S) end)
    if ok then pcall(writefile, BOT.SettingsFile, body) end
end

local saveQueued = false
local function saveSettings()
    if saveQueued then return end
    saveQueued = true
    task.spawn(function()
        task.wait(0.6)
        saveQueued = false
        saveSettingsNow()
    end)
end

local function loadSettings()
    if not (readfile and isfile) then return end
    local ok, exists = pcall(isfile, BOT.SettingsFile)
    if not ok or not exists then return end
    local ok2, body = pcall(readfile, BOT.SettingsFile)
    if not ok2 or not body then return end
    local ok3, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok3 and type(data) == "table" then
        deepMerge(S, data)
    end
end

--============================================================== 4. runtime state
local E = {
    state = "idle",
    lastSignature = nil,
    lastActionAt = 0,
    acceptCooldown = 0,
    declineCooldown = 0,
    lastSummary = "",
    failed = {},
    lastFill = nil,
    requestIndex = 0,
    stats = { accepted = 0, declined = 0, offers = 0, giveV = 0, getV = 0 },
    lastPostAt = os.time(),
    phone = { listings = {}, cards = 0, nextAt = 0, openAt = 0, createAt = 0, bucks = 0, learnAt = 0, offerAt = 0, travelAt = 0 },
    inv = { items = {}, at = 0, total = 0, count = 0, busy = false },
}

--============================================================== 4b. values
-- >>> VALUES_BEGIN
-- AUTO-GENERATED - do not edit by hand, run tools/update-values.ps1
local EMBEDDED_VALUES = {
    ["Rainbow Rattle"] = {11.75, 2, 7},
    ["Panda Cap"] = {7.25, 2, 3},
    ["Bat Dragon"] = {5.53, 3, 1},
    ["Shadow Dragon"] = {3.775, 3, 1},
    ["Giraffe"] = {2.59, 3, 1},
    ["Neon Black Scooter"] = {2.5, 2, 5},
    ["Frost Dragon"] = {1.76, 3, 1},
    ["Safari Egg"] = {1.5, 2, 2},
    ["Owl"] = {1.355, 3, 1},
    ["Candy Cannon"] = {1.3, 2, 7},
    ["Parrot"] = {1.085, 3, 1},
    ["Giant Panda"] = {1.05, 2, 1},
    ["Crow"] = {0.99, 3, 1},
    ["Strawberry Cupcake Shoes"] = {0.95, 2, 3},
    ["Balloon Unicorn"] = {0.945, 3, 1},
    ["African Wild Dog"] = {0.885, 3, 1},
    ["Blazing Lion"] = {0.87, 2, 1},
    ["Haetae"] = {0.83, 3, 1},
    ["SSBD Sunnies"] = {0.775, 2, 3},
    ["Amethyst Penguin"] = {0.76, 2, 1},
    ["Cryptid"] = {0.74, 2, 1},
    ["Buzzing Honeypot Hat"] = {0.7, 2, 3},
    ["Evil Unicorn"] = {0.665, 3, 1},
    ["Orchid Butterfly"] = {0.66, 2, 1},
    ["Hedgehog"] = {0.595, 3, 1},
    ["Strawberry Plushie Rider"] = {0.59, 2, 3},
    ["Flying Broomstick"] = {0.51, 2, 7},
    ["Dalmatian"] = {0.51, 3, 1},
    ["Jungle Egg"] = {0.5, 2, 2},
    ["Farm Egg"] = {0.47, 2, 2},
    ["Queen Bee Slippers"] = {0.44, 2, 3},
    ["Arctic Reindeer"] = {0.44, 3, 1},
    ["Strawberry Shortcake Bat Dragon"] = {0.4, 3, 1},
    ["Chocolate Chip Bat Dragon"] = {0.395, 3, 1},
    ["Rainbow Maker"] = {0.395, 3, 3},
    ["Giraffe Backpack"] = {0.38, 2, 3},
    ["Diamond Butterfly"] = {0.35, 2, 1},
    ["Hive Backpack"] = {0.34, 2, 3},
    ["Tombstone Ghostify"] = {0.26, 2, 7},
    ["Egg Stroller"] = {0.26, 2, 4},
    ["Mini Pig"] = {0.255, 3, 1},
    ["Giraffe Hat"] = {0.245, 2, 3},
    ["Blue Egg"] = {0.24, 2, 2},
    ["Water Walking Potion"] = {0.24, 2, 6},
    ["Hot Doggo"] = {0.235, 3, 1},
    ["Undead Jousting Horse"] = {0.235, 2, 1},
    ["Goose"] = {0.225, 3, 1},
    ["SSBD Beanie"] = {0.22, 2, 3},
    ["Halo"] = {0.22, 3, 3},
    ["Cow"] = {0.22, 3, 1},
    ["Peppermint Penguin"] = {0.215, 3, 1},
    ["Strawberry Tortle"] = {0.21, 2, 1},
    ["Jekyll Hydra"] = {0.21, 2, 1},
    ["Monkey King"] = {0.1975, 2, 1},
    ["Angel Wings"] = {0.195, 3, 3},
    ["Cherry-On-Top"] = {0.195, 2, 3},
    ["Ghost Vehicle"] = {0.19, 2, 5},
    ["Fairy Bat Dragon"] = {0.185, 3, 1},
    ["Pelican"] = {0.185, 2, 1},
    ["Cabbit"] = {0.1825, 3, 1},
    ["Pink Egg"] = {0.18, 2, 2},
    ["Bat Dragon Cuddle Animated Sticker"] = {0.175, 2, 9},
    ["Premium Monkey Box"] = {0.175, 2, 8},
    ["Sugar Glider"] = {0.1725, 3, 1},
    ["Cloud Car"] = {0.17, 2, 5},
    ["Frostbite Bear"] = {0.165, 2, 1},
    ["2022 Birthday Party Hat"] = {0.1625, 3, 3},
    ["Mermicorn"] = {0.16, 3, 1},
    ["Turtle"] = {0.1575, 3, 1},
    ["Grim Dragon"] = {0.155, 2, 1},
    ["Royal Mistletroll"] = {0.1525, 2, 1},
    ["2022 Birthday Cake"] = {0.145, 3, 3},
    ["Siamese Cat"] = {0.1425, 3, 1},
    ["Frost Unicorn"] = {0.14, 2, 1},
    ["Alpaca"] = {0.14, 3, 1},
    ["Rocket Sled"] = {0.14, 2, 5},
    ["Tio De Nadal"] = {0.14, 2, 1},
    ["Super Jetpack"] = {0.14, 2, 5},
    ["Unicorn Horn"] = {0.1325, 3, 3},
    ["Magic Girl Wings"] = {0.13, 2, 3},
    ["Werewolf"] = {0.13, 2, 1},
    ["Golden Leaf"] = {0.13, 2, 6},
    ["Flamingo"] = {0.1275, 3, 1},
    ["Candyfloss Chick"] = {0.1275, 3, 1},
    ["Golden Gift"] = {0.125, 2, 8},
    ["Kangaroo"] = {0.12, 3, 1},
    ["Spinning Cat Animated Sticker"] = {0.12, 2, 9},
    ["Candy Cane"] = {0.12, 2, 6},
    ["2022 Birthday Cupcake Shoes"] = {0.12, 3, 3},
    ["Candicorn"] = {0.115, 3, 1},
    ["Bush Elephant"] = {0.115, 2, 1},
    ["Haetyphoon"] = {0.105, 2, 1},
    ["Elephant"] = {0.105, 3, 1},
    ["Albino Monkey"] = {0.105, 3, 1},
    ["Christmas Egg"] = {0.105, 2, 2},
    ["Flash Weasel"] = {0.105, 2, 1},
    ["Rain Cloud Hat"] = {0.1, 3, 3},
    ["Seagull Yell Animated Sticker"] = {0.1, 2, 9},
    ["Border Collie"] = {0.0975, 3, 1},
    ["Winged Tiger"] = {0.0975, 3, 1},
    ["Tortoiseshell Guinea Pig"] = {0.0975, 2, 1},
    ["Lion"] = {0.0875, 3, 1},
    ["Crocodile"] = {0.0875, 3, 1},
    ["Caterpillar"] = {0.0825, 2, 1},
    ["Blue Dog"] = {0.0825, 2, 1},
    ["2022 Birthday Party Horn"] = {0.0825, 3, 3},
    ["2022 Birthday Confetti Cannon"] = {0.0825, 3, 3},
    ["Pumpkin"] = {0.075, 2, 7},
    ["Giant Cheetah Mount"] = {0.075, 2, 5},
    ["Shark Puppy"] = {0.075, 3, 1},
    ["Sea Slug"] = {0.0725, 2, 1},
    ["Munchkin Cat"] = {0.0725, 3, 1},
    ["Black-Chested Pheasant"] = {0.0725, 2, 1},
    ["Jellyfish"] = {0.07, 3, 1},
    ["Dragonfly Fairy Wings"] = {0.07, 2, 3},
    ["Emperor Gorilla"] = {0.0675, 2, 1},
    ["Toaster Hat"] = {0.0675, 3, 3},
    ["Moonbeam Peacock"] = {0.0675, 2, 1},
    ["Tiny Wings"] = {0.066, 3, 3},
    ["Christmas Gift"] = {0.065, 2, 8},
    ["Pig"] = {0.065, 3, 1},
    ["Mechapup"] = {0.0625, 2, 1},
    ["Pirate Ghost Capuchin Monkey"] = {0.06, 2, 1},
    ["Sugar Axolotl"] = {0.0575, 2, 1},
    ["Arctic Fox"] = {0.0575, 3, 1},
    ["Pink Cat"] = {0.056, 2, 1},
    ["Snow Snowboard"] = {0.055, 1, 5},
    ["Vampire Dragon"] = {0.055, 2, 1},
    ["Gold Snowboard"] = {0.055, 1, 5},
    ["Bunny Carriage"] = {0.055, 2, 5},
    ["Copycat"] = {0.0535, 3, 1},
    ["Irish Water Spaniel"] = {0.0525, 2, 1},
    ["Cupid Dragon"] = {0.0525, 3, 1},
    ["Sakura Spirit"] = {0.0525, 2, 1},
    ["Aurora Fox"] = {0.0505, 2, 1},
    ["Ice Snowboard"] = {0.05, 1, 5},
    ["Goldenrod Flower"] = {0.05, 2, 6},
    ["Matcha Cat"] = {0.05, 2, 1},
    ["Giant Anteater"] = {0.05, 2, 1},
    ["Chinese Lantern"] = {0.05, 2, 7},
    ["Roblox Snowboard"] = {0.05, 1, 5},
    ["Bald Eagle"] = {0.0485, 2, 1},
    ["Strawberry Penguin"] = {0.0485, 2, 1},
    ["Papa Moose"] = {0.0475, 2, 1},
    ["Lion Cub"] = {0.0475, 2, 1},
    ["Phantom Dragon"] = {0.0475, 2, 1},
    ["Midnight Dragon"] = {0.0455, 2, 1},
    ["Blue Neon Snowboard"] = {0.045, 2, 5},
    ["Pink Neon Snowboard"] = {0.045, 2, 5},
    ["White Neon Snowboard"] = {0.045, 2, 5},
    ["Quad Stroller"] = {0.045, 2, 4},
    ["Heart Stroller"] = {0.045, 2, 4},
    ["Cozy Cabin"] = {0.045, 2, 10},
    ["Ice Cream Cone Hat"] = {0.045, 2, 3},
    ["Rat Box"] = {0.045, 2, 8},
    ["Field Mouse"] = {0.045, 3, 1},
    ["Christmas Pudding Pup"] = {0.045, 2, 1},
    ["Caelum Cervi"] = {0.0435, 2, 1},
    ["Goat"] = {0.0435, 2, 1},
    ["Silverback Gorilla"] = {0.0435, 2, 1},
    ["Jester Dragon"] = {0.043, 2, 1},
    ["Zombie Buffalo"] = {0.0425, 2, 1},
    ["Glacier Kitsune"] = {0.041, 2, 1},
    ["Puffin"] = {0.041, 2, 1},
    ["Head Chef"] = {0.04, 2, 3},
    ["Strawberry Shortcake Bat Dragon Backpack"] = {0.04, 2, 3},
    ["Blazing Lion Animated Sticker"] = {0.04, 2, 9},
    ["Many Mackerel"] = {0.04, 2, 1},
    ["Bathtub"] = {0.04, 2, 5},
    ["Snowflake Potion"] = {0.04, 2, 6},
    ["Shrew"] = {0.04, 2, 1},
    ["GoKart"] = {0.04, 2, 5},
    ["Tortuga de la Isla"] = {0.04, 2, 1},
    ["Diamond Amazon"] = {0.04, 2, 1},
    ["Velocirooster"] = {0.0375, 2, 1},
    ["Christmas Pudding Pup Bait"] = {0.0375, 2, 6},
    ["Frost Fury"] = {0.0375, 3, 1},
    ["Arctic Dusk Dragon"] = {0.0375, 2, 1},
    ["Sheeeeep"] = {0.0375, 2, 1},
    ["Cherry Blossom Hang Glider"] = {0.036, 2, 7},
    ["Diamond Hummingbird"] = {0.036, 2, 1},
    ["Horse And Carriage"] = {0.035, 2, 5},
    ["Honey Badger"] = {0.035, 2, 1},
    ["Nessie"] = {0.0335, 2, 1},
    ["Ballet Swan"] = {0.0335, 2, 1},
    ["Glacier Moth"] = {0.033, 2, 1},
    ["Giant Gold Scarab"] = {0.0325, 2, 1},
    ["Meerkat"] = {0.0325, 2, 1},
    ["Aussie Egg"] = {0.0325, 3, 2},
    ["Shooting Star Board"] = {0.0325, 2, 5},
    ["Green Neon Snowboard"] = {0.0325, 2, 5},
    ["Tri-horned Treehopper"] = {0.031, 2, 1},
    ["Ring-Tailed Lemur"] = {0.031, 2, 1},
    ["Groundhog"] = {0.03, 2, 1},
    ["Spring Bunny Hood"] = {0.03, 2, 3},
    ["Eco Natural Earth House"] = {0.03, 2, 10},
    ["Ember Wings"] = {0.03, 2, 3},
    ["Owlbear"] = {0.03, 2, 1},
    ["Diamond Albatross"] = {0.029, 2, 1},
    ["Polar Bear"] = {0.028, 2, 1},
    ["Hero Gibbon"] = {0.028, 2, 1},
    ["Red Dutch Guinea Pig"] = {0.028, 2, 1},
    ["Glormy Leo"] = {0.028, 2, 1},
    ["Fallow Deer"] = {0.028, 2, 1},
    ["Brown Bear"] = {0.028, 2, 1},
    ["Space Fleet House"] = {0.0275, 2, 10},
    ["Toyshop House"] = {0.0275, 2, 10},
    ["Dim Sum"] = {0.0275, 2, 6},
    ["Unicorn Backpack"] = {0.0275, 2, 3},
    ["Happy Clam"] = {0.0265, 2, 1},
    ["Halloween White Ghost Dragon"] = {0.026, 2, 1},
    ["Jousting Horse"] = {0.0255, 2, 1},
    ["Millionaire Mansion"] = {0.025, 2, 10},
    ["Dragon Train"] = {0.025, 1, 5},
    ["Crescent Moon Car"] = {0.025, 2, 5},
    ["Glass Snowboard"] = {0.025, 1, 5},
    ["Neon Black Skateboard"] = {0.025, 2, 5},
    ["Expandable Dino House"] = {0.025, 2, 10},
    ["Tea Party Set"] = {0.025, 2, 7},
    ["Chocolate"] = {0.025, 2, 6},
    ["Gold Crown"] = {0.025, 2, 3},
    ["Teddy Skele"] = {0.025, 2, 7},
    ["Rose Dragon"] = {0.025, 2, 1},
    ["Jekyll Hydra Animated Sticker"] = {0.025, 2, 9},
    ["Hyena"] = {0.025, 2, 1},
    ["Latte Kitsune"] = {0.024, 2, 1},
    ["Dancing Dragon"] = {0.023, 2, 1},
    ["Naughty Mistletroll"] = {0.023, 2, 1},
    ["Ice Golem"] = {0.023, 2, 1},
    ["Platypus"] = {0.023, 2, 1},
    ["Lava Dragon"] = {0.0225, 2, 1},
    ["Hare"] = {0.0225, 2, 1},
    ["Goth Shoes"] = {0.0225, 2, 3},
    ["Mermaid Mansion"] = {0.0225, 2, 10},
    ["Moose Calf"] = {0.0215, 2, 1},
    ["Pineapple Owl"] = {0.0215, 2, 1},
    ["Ice Wolf"] = {0.0215, 2, 1},
    ["Purple Butterfly"] = {0.0215, 2, 1},
    ["Rainbow Dragon"] = {0.021, 2, 1},
    ["Scorching Kaijunior"] = {0.021, 2, 1},
    ["Alley Cat"] = {0.021, 2, 1},
    ["Vampire Stroller"] = {0.02, 1, 4},
    ["Celebrity Mansion"] = {0.02, 2, 10},
    ["Flower Truck"] = {0.02, 2, 5},
    ["Heart Potion"] = {0.02, 2, 6},
    ["Super Age-Up Potion"] = {0.02, 2, 6},
    ["Yule Log Dog"] = {0.02, 2, 1},
    ["Biodome Home"] = {0.02, 2, 10},
    ["Shadow Wings"] = {0.02, 2, 3},
    ["Golden Mistletoe"] = {0.02, 2, 8},
    ["Heart Rattle"] = {0.02, 2, 7},
    ["Unicorn Cycle"] = {0.02, 2, 5},
    ["Orange Neon Snowboard"] = {0.02, 2, 5},
    ["Mono-Moped"] = {0.02, 2, 5},
    ["Horse Cycle"] = {0.02, 2, 5},
    ["Pancake Stack"] = {0.019, 2, 3},
    ["Aestus"] = {0.019, 2, 1},
    ["Adopt Me Snowboard 2"] = {0.019, 1, 5},
    ["Adopt Me Snowboard 1"] = {0.019, 1, 5},
    ["Kookaburra"] = {0.0185, 2, 1},
    ["Dragonfruit Fox"] = {0.0185, 2, 1},
    ["Diamond King Penguin"] = {0.0185, 2, 1},
    ["Dango Penguins"] = {0.0185, 2, 1},
    ["Santa Hat"] = {0.0175, 2, 3},
    ["Race Car Stroller"] = {0.0175, 1, 4},
    ["Propeller Hat"] = {0.0175, 2, 3},
    ["Neon White Skateboard"] = {0.0175, 1, 5},
    ["Spring Bunny Nose"] = {0.0175, 2, 3},
    ["Expandable Luxury Mansion"] = {0.0175, 2, 10},
    ["Golden Lettuce"] = {0.0175, 2, 6},
    ["Neon White Scooter"] = {0.0175, 1, 5},
    ["Chocolate Egg"] = {0.0175, 2, 6},
    ["Snow Monkey"] = {0.0175, 2, 1},
    ["Solaris"] = {0.0175, 2, 1},
    ["Ruler's Castle"] = {0.0175, 2, 10},
    ["Ice Cream Hermit Crab"] = {0.0165, 2, 1},
    ["Majestic Pony"] = {0.0165, 2, 1},
    ["Frost Phoenix"] = {0.0165, 2, 1},
    ["Queen Bee"] = {0.0165, 2, 1},
    ["Leviathan"] = {0.0165, 2, 1},
    ["Albino Gorilla"] = {0.016, 2, 1},
    ["Flaming Fox"] = {0.016, 2, 1},
    ["Cheetah"] = {0.016, 2, 1},
    ["Husky"] = {0.0155, 2, 1},
    ["Wood Pigeon"] = {0.0155, 2, 1},
    ["Lavender Dragon"] = {0.0155, 2, 1},
    ["Llama"] = {0.0155, 2, 1},
    ["Tree Kangaroo"] = {0.0155, 2, 1},
    ["Glormy Hound"] = {0.015, 2, 1},
    ["Cradle Stroller"] = {0.015, 1, 4},
    ["Schoolhouse Home"] = {0.015, 2, 10},
    ["Diamond Hamster"] = {0.015, 2, 1},
    ["Unicorn Stroller"] = {0.015, 1, 4},
    ["Hugging Egg"] = {0.015, 1, 7},
    ["Airplane Stroller"] = {0.015, 1, 4},
    ["Wing Hang Glider"] = {0.015, 2, 7},
    ["Tea Party Chair"] = {0.015, 2, 7},
    ["Unicorn Plush"] = {0.015, 2, 7},
    ["Monkey Box"] = {0.015, 2, 8},
    ["Levitation Potion"] = {0.015, 1, 6},
    ["Chocolate Drop"] = {0.015, 2, 6},
    ["Sugar Skull Potion"] = {0.015, 2, 6},
    ["Violet Butterfly"] = {0.014, 2, 1},
    ["Candy Hare"] = {0.014, 2, 1},
    ["Baby Basket Stroller"] = {0.014, 1, 4},
    ["Turkey"] = {0.014, 2, 1},
    ["Golden Chow-Chow"] = {0.014, 2, 1},
    ["Gaelic Fae"] = {0.0135, 2, 1},
    ["Royal Corgi"] = {0.0135, 2, 1},
    ["Lava Wolf"] = {0.0135, 2, 1},
    ["Chocolate Dutch Guinea Pig"] = {0.013, 2, 1},
    ["Corn Doggo"] = {0.013, 2, 1},
    ["Teleportation Potion"] = {0.013, 1, 6},
    ["Broken Egg"] = {0.013, 1, 6},
    ["Glider"] = {0.013, 2, 7},
    ["Fly-A-Pet Potion"] = {0.013, 3, 6},
    ["Pet Handler Pro Certificate"] = {0.013, 3, 8},
    ["Neon Green Skateboard"] = {0.013, 1, 5},
    ["Bunny Stroller"] = {0.013, 1, 4},
    ["Neon Red Skateboard"] = {0.013, 1, 5},
    ["Neon Blue Skateboard"] = {0.013, 1, 5},
    ["Neon Pink Skateboard"] = {0.013, 1, 5},
    ["Slime"] = {0.013, 2, 1},
    ["Rain Boots"] = {0.013, 2, 3},
    ["Sailor Cap"] = {0.013, 2, 3},
    ["Swan"] = {0.013, 2, 1},
    ["Cerberus"] = {0.013, 2, 1},
    ["Moonbeam Butterfly"] = {0.013, 2, 1},
    ["Enchanted Broomstick"] = {0.013, 2, 5},
    ["Lamb"] = {0.013, 2, 1},
    ["Ninja Monkey"] = {0.013, 2, 1},
    ["Convertible"] = {0.013, 1, 5},
    ["Neon Orange Skateboard"] = {0.013, 1, 5},
    ["Panda Pal"] = {0.0125, 2, 7},
    ["Premium Gorilla Box"] = {0.0125, 2, 8},
    ["Skeleton Winged Glider"] = {0.0125, 2, 7},
    ["Duck Stroller"] = {0.0125, 1, 4},
    ["Neon Orange Scooter"] = {0.0125, 1, 5},
    ["Hot Tub Muscle Car"] = {0.0125, 2, 5},
    ["Hospital Home"] = {0.0125, 2, 10},
    ["Sunrise Hang Glider"] = {0.0125, 2, 7},
    ["Black Scooter"] = {0.0125, 2, 5},
    ["Gyrocopter"] = {0.0125, 1, 5},
    ["Floating Hand Stroller"] = {0.0125, 1, 4},
    ["Half Egg Stroller"] = {0.0125, 1, 4},
    ["Easter Egg Stroller"] = {0.0125, 1, 4},
    ["Leaf"] = {0.0125, 2, 6},
    ["Sandwich Hat"] = {0.0125, 2, 3},
    ["Golden Penguin"] = {0.0125, 2, 1},
    ["Wooly Rhino"] = {0.0125, 2, 1},
    ["Leopard Shark"] = {0.0125, 2, 1},
    ["Silly Duck"] = {0.0125, 2, 1},
    ["Eco Brown Hiking Backpack"] = {0.012, 2, 3},
    ["Neon Pink Scooter"] = {0.012, 1, 5},
    ["Astronaut Gorilla"] = {0.012, 2, 1},
    ["Prismatic Butterfly"] = {0.012, 2, 1},
    ["Mule"] = {0.012, 2, 1},
    ["Neon Blue Scooter"] = {0.012, 1, 5},
    ["Sushi Skateboard"] = {0.012, 2, 3},
    ["Rabbit Helicopter"] = {0.012, 1, 5},
    ["Halloween Black Axe Guitar Accessory"] = {0.012, 2, 3},
    ["Copter Hat"] = {0.012, 2, 3},
    ["Neon Green Scooter"] = {0.012, 1, 5},
    ["Ketchup and Mustard Jetpack"] = {0.012, 2, 5},
    ["Toy Rescue Helicopter"] = {0.012, 1, 5},
    ["Neon Red Scooter"] = {0.012, 1, 5},
    ["Harp Seal"] = {0.0115, 2, 1},
    ["Diamond Ladybug"] = {0.0115, 2, 1},
    ["Chef Gorilla"] = {0.0115, 2, 1},
    ["2D Doggy"] = {0.011, 1, 1},
    ["Dragon Breath Animated Sticker"] = {0.011, 2, 9},
    ["Moped"] = {0.011, 1, 5},
    ["Flying Cloud"] = {0.011, 2, 5},
    ["Dogmobile"] = {0.011, 2, 5},
    ["Clockwork Wings"] = {0.011, 2, 3},
    ["Shadow Aura"] = {0.011, 2, 3},
    ["Chocolate Twist"] = {0.011, 2, 6},
    ["Cloud Wings"] = {0.011, 2, 3},
    ["Zombie Wolf"] = {0.011, 2, 1},
    ["Unicorn"] = {0.011, 3, 1},
    ["Monkey King Crown"] = {0.011, 2, 3},
    ["Spring Bunny Feet"] = {0.011, 2, 3},
    ["Firefly"] = {0.0105, 2, 1},
    ["Chicken"] = {0.0105, 2, 1},
    ["Ram"] = {0.0105, 2, 1},
    ["Shark"] = {0.0105, 2, 1},
    ["Vanilla Penguin"] = {0.0105, 2, 1},
    ["Pupcicle"] = {0.0105, 3, 1},
    ["German Shepherd"] = {0.0105, 2, 1},
    ["Mini Schnauzer"] = {0.0105, 2, 1},
    ["French Bulldog"] = {0.0105, 2, 1},
    ["Golden Rat"] = {0.0105, 2, 1},
    ["Dodo"] = {0.0105, 2, 1},
    ["Phoenix"] = {0.0105, 2, 1},
    ["Green Butterfly"] = {0.0105, 2, 1},
    ["Soccer Stadium"] = {0.01, 2, 10},
    ["Capybara"] = {0.01, 2, 1},
    ["Modern Mansion"] = {0.01, 2, 10},
    ["Super Saru Animated Sticker"] = {0.01, 2, 9},
    ["Premium Capuchin Box"] = {0.01, 2, 8},
    ["Baked Alaska Bait"] = {0.01, 2, 6},
    ["Ice Tub"] = {0.01, 2, 6},
    ["Invisible Wings"] = {0.01, 2, 3},
    ["Magpie Wings"] = {0.01, 2, 3},
    ["Pink Cat Ear Headphones"] = {0.01, 2, 3},
    ["Skele-Rex"] = {0.01, 2, 1},
    ["Jeff's Nametag"] = {0.01, 2, 3},
    ["Banana Hat"] = {0.01, 2, 3},
    ["Royal Moon Egg"] = {0.01, 2, 2},
    ["Goldhorn"] = {0.01, 2, 1},
    ["Puffer Fish"] = {0.01, 2, 1},
    ["Adopt Me Girl Scooter"] = {0.01, 1, 5},
    ["Monocycle"] = {0.01, 1, 5},
    ["Doge Scooter"] = {0.01, 1, 5},
    ["Witches Wand"] = {0.01, 1, 7},
    ["Pumpkin Rattle"] = {0.01, 1, 7},
    ["Adopt Me Boy Scooter"] = {0.01, 1, 5},
    ["Eco Brown Earth-Wizard Hat"] = {0.01, 2, 3},
    ["Pink Heart Glasses"] = {0.01, 2, 3},
    ["Chef Hat"] = {0.01, 2, 3},
    ["Cupcake Scooter"] = {0.01, 1, 5},
    ["Eco Orange Pumpkin Pie Wings"] = {0.01, 2, 3},
    ["Toy Monkey"] = {0.01, 2, 1},
    ["Scarebear"] = {0.01, 2, 1},
    ["Pirate Hermit Crab"] = {0.01, 2, 1},
    ["Spinosaurus"] = {0.01, 2, 1},
    ["Black Widow"] = {0.0095, 2, 1},
    ["White Sand Dollar"] = {0.0095, 2, 1},
    ["T-Rex"] = {0.0095, 2, 1},
    ["Catte"] = {0.0095, 2, 1},
    ["Tuxedo Cat"] = {0.0095, 2, 1},
    ["Wild Boar"] = {0.0095, 2, 1},
    ["Volcanic Rhino"] = {0.0095, 2, 1},
    ["Ghost Bunny"] = {0.0095, 2, 1},
    ["Dire Stag"] = {0.0095, 2, 1},
    ["2D Kitty"] = {0.0095, 2, 1},
    ["Sushi Penguin"] = {0.0095, 2, 1},
    ["Capricorn"] = {0.0095, 2, 1},
    ["Kelp Captain"] = {0.0095, 1, 1},
    ["Gargoyle"] = {0.00925, 1, 1},
    ["Rhino"] = {0.00925, 2, 1},
    ["Black Panther"] = {0.00925, 2, 1},
    ["Octopus"] = {0.00925, 2, 1},
    ["Red Sand Dollar"] = {0.00925, 2, 1},
    ["Cactus Friend"] = {0.00925, 2, 1},
    ["Peacock"] = {0.00925, 2, 1},
    ["Golden Walrus"] = {0.00925, 2, 1},
    ["S'mores Raccoon"] = {0.00925, 2, 1},
    ["Drake"] = {0.00925, 2, 1},
    ["Peahen"] = {0.00925, 1, 1},
    ["Axolotl"] = {0.00925, 2, 1},
    ["Count Slothula"] = {0.009, 2, 1},
    ["Apple Owl"] = {0.009, 2, 1},
    ["Kitty Bat"] = {0.009, 2, 1},
    ["Premium Gibbon Box"] = {0.009, 2, 8},
    ["Shetland Pony Light Brown"] = {0.009, 1, 1},
    ["Peach Owl"] = {0.009, 2, 1},
    ["Donut Cycle"] = {0.009, 1, 5},
    ["Pumpkin Carriage"] = {0.009, 1, 5},
    ["Mermicorn Animated Sticker"] = {0.009, 2, 9},
    ["Easter 2020 Egg"] = {0.009, 2, 2},
    ["Frostclaw Animated Sticker"] = {0.009, 2, 9},
    ["Influencer Gibbon"] = {0.009, 1, 1},
    ["Strawberry Hat"] = {0.009, 2, 3},
    ["Naga Dragon"] = {0.009, 1, 1},
    ["Kiwi"] = {0.009, 2, 1},
    ["Panda"] = {0.009, 2, 1},
    ["Business Monkey"] = {0.009, 2, 1},
    ["Guardian Lion"] = {0.009, 2, 1},
    ["Black Springer Spaniel"] = {0.009, 2, 1},
    ["Brown Springer Spaniel"] = {0.009, 2, 1},
    ["Binturong"] = {0.0085, 2, 1},
    ["English Sheepdog"] = {0.0085, 2, 1},
    ["Yeti"] = {0.0085, 2, 1},
    ["Water Rabbit"] = {0.0085, 2, 1},
    ["Royal Capuchin Monkey"] = {0.0085, 1, 1},
    ["Winged Horse"] = {0.008, 2, 1},
    ["Golden Hummingbird"] = {0.008, 1, 1},
    ["White Amazon"] = {0.008, 2, 1},
    ["Mushroom Friend"] = {0.008, 1, 1},
    ["Super Saru"] = {0.008, 1, 1},
    ["Doge Skateboard"] = {0.008, 1, 5},
    ["Summer Spectacle"] = {0.008, 2, 5},
    ["Royal Desert Egg"] = {0.008, 2, 2},
    ["Hippogriff"] = {0.008, 1, 1},
    ["Evil Rock"] = {0.008, 2, 1},
    ["Orange Butterfly"] = {0.008, 2, 1},
    ["Snow Owl"] = {0.008, 2, 1},
    ["Princess Capuchin Monkey"] = {0.008, 1, 1},
    ["Pretty Pony"] = {0.008, 2, 1},
    ["Rainbow Stroller"] = {0.008, 1, 4},
    ["Ghost Dog"] = {0.008, 2, 1},
    ["Kiwi Kiwi"] = {0.008, 1, 1},
    ["Gilded Snake"] = {0.008, 1, 1},
    ["Lynx"] = {0.008, 2, 1},
    ["Cuddly Candle"] = {0.008, 1, 1},
    ["Reindeer"] = {0.008, 2, 1},
    ["Moon Rabbit"] = {0.008, 2, 1},
    ["Dimorphodon"] = {0.0075, 1, 1},
    ["Blue Betta Fish"] = {0.0075, 1, 1},
    ["Karate Gorilla"] = {0.0075, 2, 1},
    ["Golden Hamster"] = {0.0075, 1, 1},
    ["Seabed Creeper"] = {0.0075, 2, 1},
    ["Cake Friend"] = {0.0075, 2, 1},
    ["Great Pyrenees"] = {0.0075, 2, 1},
    ["Pets Plus Sticker Pack"] = {0.0075, 2, 9},
    ["Shadow Dragon Animated Sticker"] = {0.0075, 2, 9},
    ["Green-Chested Pheasant"] = {0.0075, 1, 1},
    ["Snowball Pet"] = {0.0075, 2, 1},
    ["Sunrise Duckling"] = {0.0075, 1, 1},
    ["Chocolate Chow-Chow"] = {0.0075, 1, 1},
    ["Golden King Penguin"] = {0.0075, 1, 1},
    ["Golden Ladybug"] = {0.0075, 1, 1},
    ["Black Chow-Chow"] = {0.0075, 1, 1},
    ["Robo Dog"] = {0.0075, 1, 1},
    ["Maneki-Neko"] = {0.0075, 1, 1},
    ["Pizza Stroller"] = {0.0075, 1, 4},
    ["Headless Horse"] = {0.007, 2, 1},
    ["King Bee"] = {0.007, 2, 1},
    ["Rose Petal Carriage"] = {0.007, 2, 5},
    ["Amami Rabbit"] = {0.007, 2, 1},
    ["Chimera"] = {0.007, 1, 1},
    ["Ride-A-Pet Potion"] = {0.007, 3, 6},
    ["Cobra"] = {0.007, 1, 1},
    ["Baku"] = {0.007, 1, 1},
    ["Ranger Beaver"] = {0.007, 2, 1},
    ["Burger Bear"] = {0.007, 2, 1},
    ["Red Squirrel"] = {0.007, 2, 1},
    ["Squid"] = {0.007, 1, 1},
    ["1000 Bucks Silk Bag"] = {0.007, 2, 8},
    ["Slimingo"] = {0.007, 1, 1},
    ["Golden Albatross"] = {0.007, 1, 1},
    ["Bat Box"] = {0.007, 2, 8},
    ["Mecha Meow"] = {0.007, 1, 1},
    ["Ice Cream Stroller"] = {0.007, 1, 4},
    ["Elf Hat"] = {0.007, 2, 3},
    ["Billy Goat"] = {0.007, 1, 1},
    ["Berry Cool Cube"] = {0.007, 1, 1},
    ["Criosphinx"] = {0.007, 1, 1},
    ["Frostbite Cub"] = {0.007, 2, 1},
    ["Hawk"] = {0.007, 1, 1},
    ["Emberlight"] = {0.007, 1, 1},
    ["Blue Ringed Octopus"] = {0.007, 2, 1},
    ["Castle Hermit Crab"] = {0.00675, 1, 1},
    ["Ash Zebra"] = {0.00675, 1, 1},
    ["Black Macaque"] = {0.00675, 2, 1},
    ["Winter Buck"] = {0.00675, 1, 1},
    ["Pupcake"] = {0.00675, 2, 1},
    ["Albino Bat"] = {0.00675, 1, 1},
    ["Shiver Wolf"] = {0.00675, 2, 1},
    ["Chameleon"] = {0.00675, 1, 1},
    ["Diamond Unicorn"] = {0.00675, 1, 1},
    ["Space Whale"] = {0.00675, 1, 1},
    ["Musk Ox"] = {0.00675, 1, 1},
    ["Golden Jaguar"] = {0.00675, 1, 1},
    ["Tasmanian Devil"] = {0.00675, 2, 1},
    ["Lunar Moon Bear"] = {0.00675, 1, 1},
    ["Flower Power Duckling"] = {0.00675, 1, 1},
    ["Scarecrow Crow"] = {0.00675, 1, 1},
    ["Pain au Chat"] = {0.00675, 2, 1},
    ["Griffin"] = {0.00675, 1, 1},
    ["Chihuahua"] = {0.00675, 2, 1},
    ["Bunny Swirl"] = {0.00675, 2, 1},
    ["Happy Duckling"] = {0.00675, 2, 1},
    ["Pumpkin Friend"] = {0.00675, 2, 1},
    ["Kitsune"] = {0.00675, 1, 1},
    ["Gecko"] = {0.0065, 1, 1},
    ["Rosy Maple Moth"] = {0.0065, 1, 1},
    ["Mr. Whiskerpips"] = {0.0065, 2, 1},
    ["Indian Flying Fox"] = {0.0065, 1, 1},
    ["Coconut Friend"] = {0.0065, 1, 1},
    ["Primal Kaijunior"] = {0.0065, 1, 1},
    ["Striped Eggy"] = {0.0065, 1, 1},
    ["Candy Cane Snail"] = {0.0065, 1, 1},
    ["Moonlight Moth"] = {0.0065, 1, 1},
    ["Pink Betta Fish"] = {0.0065, 1, 1},
    ["Horse"] = {0.0065, 2, 1},
    ["Regal Wing Chest"] = {0.0065, 2, 8},
    ["Wolf Box"] = {0.0065, 2, 8},
    ["Tarsier"] = {0.0065, 1, 1},
    ["Hermit Crab Box"] = {0.0065, 2, 8},
    ["Walrus Box"] = {0.0065, 2, 8},
    ["Duckling Box"] = {0.0065, 2, 8},
    ["Quokka"] = {0.0065, 1, 1},
    ["Mighty Haetyphoon Animated Sticker"] = {0.0065, 2, 9},
    ["Vol. 2 Pets Plus Sticker Pack"] = {0.0065, 2, 9},
    ["Mud Ball"] = {0.0065, 2, 6},
    ["Evil Chick"] = {0.0065, 1, 1},
    ["Highland Cow"] = {0.0065, 1, 1},
    ["Golden Goldfish"] = {0.0065, 2, 6},
    ["Frosty Glow Mega Neon Paint"] = {0.0065, 3, 7},
    ["Staff Ingredient"] = {0.0065, 1, 7},
    ["Zombie Buffalo Plush"] = {0.0065, 1, 7},
    ["Celebration Firework Launcher"] = {0.0065, 1, 7},
    ["Golden Goblet"] = {0.0065, 1, 7},
    ["Cat Plush"] = {0.0065, 1, 7},
    ["Hot Cocoa Stand"] = {0.0065, 2, 7},
    ["Koala"] = {0.0065, 1, 1},
    ["Canadian Goose"] = {0.0065, 1, 1},
    ["Hare Box"] = {0.0065, 2, 8},
    ["Glormy Dolphin"] = {0.0065, 1, 1},
    ["Merry Mistletroll"] = {0.0065, 1, 1},
    ["Irish Elk"] = {0.0065, 1, 1},
    ["Golden Clam"] = {0.0065, 2, 6},
    ["Eggnog Dog"] = {0.0065, 1, 1},
    ["Pudding Cat"] = {0.0065, 1, 1},
    ["Vermilion Butterfly"] = {0.0065, 1, 1},
    ["Hippo"] = {0.0065, 1, 1},
    ["Flaming Zebra"] = {0.0065, 1, 1},
    ["Shadow Dragon Ducky"] = {0.0065, 2, 1},
    ["Toasty Red Panda"] = {0.0065, 1, 1},
    ["Giant Blue Scarab"] = {0.0065, 1, 1},
    ["Halloween Evil Dachshund"] = {0.0065, 1, 1},
    ["Evil Basilisk"] = {0.0065, 1, 1},
    ["Leopard Cat"] = {0.0065, 1, 1},
    ["Pirate Ship House"] = {0.0065, 2, 10},
    ["Royal Aztec Egg"] = {0.0065, 2, 2},
    ["Golden Corn"] = {0.0065, 2, 6},
    ["Maple Leaf Treat"] = {0.0065, 2, 6},
    ["Golden Petunia"] = {0.0065, 2, 6},
    ["Golden Bone"] = {0.0065, 2, 6},
    ["Diamond Lavender"] = {0.0065, 2, 6},
    ["Golden Wheat"] = {0.0065, 2, 6},
    ["Golden Dandelion"] = {0.0065, 2, 6},
    ["Fleur De Ice"] = {0.0065, 1, 1},
    ["Evil Chickatrice"] = {0.0065, 1, 1},
    ["Halloween Golden Mummy Cat"] = {0.0065, 1, 1},
    ["Golden Seed Ball"] = {0.0065, 2, 6},
    ["Golden Plantain"] = {0.0065, 2, 6},
    ["Chipmunk"] = {0.0065, 1, 1},
    ["Golden Tortoise Beetle"] = {0.0065, 1, 1},
    ["Prehistoric Car"] = {0.0065, 1, 5},
    ["Gingerbread Sleigh"] = {0.0065, 2, 5},
    ["Festive Deliveries Present Truck"] = {0.0065, 1, 5},
    ["Emoji Scooter"] = {0.0065, 1, 5},
    ["Cupid's Coupe"] = {0.0065, 1, 5},
    ["Toxic Barrel"] = {0.0065, 1, 5},
    ["Alien Eyes Hat"] = {0.0065, 2, 3},
    ["Bat Wings"] = {0.0065, 2, 3},
    ["Respectful Mustache"] = {0.0065, 2, 3},
    ["Web Stroller"] = {0.0065, 1, 4},
    ["Cowboy Saddle"] = {0.0065, 2, 3},
    ["Icey Aura"] = {0.0065, 1, 3},
    ["Melon Skateboard"] = {0.0065, 1, 5},
    ["Glass Skateboard"] = {0.0065, 1, 5},
    ["Wood Skateboard"] = {0.0065, 1, 5},
    ["Glass Scooter"] = {0.0065, 1, 5},
    ["Fidget Skateboard"] = {0.0065, 1, 5},
    ["Gold Skateboard"] = {0.0065, 1, 5},
    ["Regal Roller"] = {0.0065, 1, 5},
    ["Bethink Skateboard"] = {0.0065, 1, 5},
    ["Gold Scooter"] = {0.0065, 1, 5},
    ["Ice Scooter"] = {0.0065, 1, 5},
    ["Street Drifter"] = {0.0065, 1, 5},
    ["Royal Crown Carriage"] = {0.0065, 1, 5},
    ["Fissy Skateboard"] = {0.0065, 1, 5},
    ["Dancing Tube Hat"] = {0.0065, 1, 3},
    ["General Sheepdog"] = {0.0065, 1, 1},
    ["Nautilus"] = {0.0065, 1, 1},
    ["Dimension Drifter"] = {0.0065, 1, 1},
    ["Aviator Hat"] = {0.0065, 2, 3},
    ["Cauldron Stroller"] = {0.0065, 1, 4},
    ["Blue Butterfly Wings"] = {0.0065, 2, 3},
    ["Fairy Wings"] = {0.0065, 1, 3},
    ["Priceless Shrimp"] = {0.0065, 1, 1},
    ["Frostclaw"] = {0.0065, 1, 1},
    ["Royal Palace Spaniel"] = {0.0065, 1, 1},
    ["Villain Gibbon"] = {0.0065, 1, 1},
    ["Cow Calf"] = {0.0065, 1, 1},
    ["Sunglider"] = {0.0065, 1, 1},
    ["Ice Moth Dragon"] = {0.0065, 1, 1},
    ["Kraken"] = {0.0065, 1, 1},
    ["Burger Boots"] = {0.0065, 2, 3},
    ["Eco Brown Branch Headphones"] = {0.0065, 1, 3},
    ["Jade Moth Wings"] = {0.0065, 1, 3},
    ["Demon Wings"] = {0.0065, 1, 3},
    ["2022 Birthday Confetti Drape"] = {0.0065, 2, 3},
    ["Black Designer Backpack"] = {0.0065, 1, 3},
    ["Chocolate Chip Bat Dragon Backpack"] = {0.0065, 1, 3},
    ["Bready Necklace"] = {0.0065, 2, 3},
    ["White Designer Backpack"] = {0.0065, 1, 3},
    ["Thinking Hat"] = {0.0065, 2, 3},
    ["Ostrich"] = {0.00625, 1, 1},
    ["Partridge"] = {0.00625, 1, 1},
    ["Wolf"] = {0.00625, 1, 1},
    ["Frog"] = {0.00625, 1, 1},
    ["Therapy Dog"] = {0.00625, 1, 1},
    ["Inmate Capuchin Monkey"] = {0.00625, 1, 1},
    ["Scarlet Butterfly"] = {0.00625, 1, 1},
    ["Punk Pony"] = {0.00625, 1, 1},
    ["Nightmare Owl"] = {0.00625, 1, 1},
    ["Preppy Capuchin Monkey"] = {0.00625, 1, 1},
    ["Rooster"] = {0.00625, 1, 1},
    ["Cassowary"] = {0.00625, 1, 1},
    ["Sloth"] = {0.00625, 1, 1},
    ["St Bernard"] = {0.00625, 1, 1},
    ["Glyptodon"] = {0.00625, 1, 1},
    ["Sprout Snail"] = {0.00625, 1, 1},
    ["Summer Walrus"] = {0.00625, 1, 1},
    ["Lunar Gold Tiger"] = {0.00625, 1, 1},
    ["Scarecrow Cat"] = {0.00625, 1, 1},
    ["Mirai Moth"] = {0.00625, 1, 1},
    ["Burning Bunny"] = {0.00625, 1, 1},
    ["Halloween White Skeleton Dog"] = {0.00625, 1, 1},
    ["Elasmosaurus"] = {0.00625, 1, 1},
    ["Feesh"] = {0.00625, 1, 1},
    ["Longhorn Cow"] = {0.00625, 1, 1},
    ["Koi Carp"] = {0.00625, 1, 1},
    ["Dumpling Friend Hat"] = {0.006, 2, 3},
    ["Butter Knife"] = {0.006, 2, 3},
    ["Rainbow Cloud Wings"] = {0.006, 2, 3},
    ["Steampunk Clock Hat"] = {0.006, 1, 3},
    ["Witch Hat"] = {0.006, 1, 3},
    ["Hero Mask"] = {0.006, 1, 3},
    ["Cotton Candy Hat"] = {0.006, 2, 3},
    ["2022 Birthday 5 Badge"] = {0.006, 1, 3},
    ["French Fries Stroller"] = {0.006, 1, 4},
    ["Creator Rattle (NewFissy)"] = {0.006, 1, 7},
    ["Homeing Rocket"] = {0.006, 1, 7},
    ["Danger Egg"] = {0.006, 2, 2},
    ["Ice Cream Heels"] = {0.006, 2, 3},
    ["Creator Rattle (Bethink)"] = {0.006, 1, 7},
    ["Chicken Hat"] = {0.006, 1, 3},
    ["Kitty Biscuit"] = {0.006, 2, 6},
    ["Pink Skateboard"] = {0.006, 1, 5},
    ["White Snowboard"] = {0.006, 1, 5},
    ["Cookie"] = {0.006, 2, 6},
    ["Blue Skateboard"] = {0.006, 1, 5},
    ["Halloween Black Ponycycle"] = {0.006, 1, 5},
    ["Duck Scooter"] = {0.006, 1, 5},
    ["Black Snowboard"] = {0.006, 1, 5},
    ["Snowmobile"] = {0.006, 1, 5},
    ["Crabby Cruiser"] = {0.006, 1, 5},
    ["Ice Plane"] = {0.006, 1, 5},
    ["Blue Scooter"] = {0.006, 1, 5},
    ["Black Skateboard"] = {0.006, 1, 5},
    ["Zodiac Minion Chick"] = {0.006, 1, 1},
    ["White Skateboard"] = {0.006, 1, 5},
    ["Toy Poodle"] = {0.006, 1, 1},
    ["Puptune"] = {0.006, 1, 1},
    ["Rice Cake Rabbit"] = {0.006, 1, 1},
    ["Kage Crow"] = {0.006, 1, 1},
    ["Tree Decorating Animated Sticker"] = {0.006, 2, 9},
    ["Skunk"] = {0.006, 1, 1},
    ["Clownfish"] = {0.006, 1, 1},
    ["Chick"] = {0.006, 1, 1},
    ["Tanuki"] = {0.006, 1, 1},
    ["Bauble Buddies"] = {0.006, 1, 1},
    ["Snowball Pug"] = {0.006, 1, 1},
    ["Fire Mare"] = {0.006, 1, 1},
    ["Love Bird"] = {0.006, 1, 1},
    ["Seafoam Butterfly"] = {0.006, 1, 1},
    ["Dracula Parrot"] = {0.006, 1, 1},
    ["Metal Ox"] = {0.006, 1, 1},
    ["Seagull"] = {0.006, 1, 1},
    ["Sweetheart Rat"] = {0.006, 1, 1},
    ["Angus Bull"] = {0.006, 1, 1},
    ["Clover Cow"] = {0.006, 1, 1},
    ["Komodo Dragon"] = {0.006, 1, 1},
    ["Strawberry Shortcake Ducky"] = {0.006, 1, 1},
    ["Deinonychus"] = {0.0055, 1, 1},
    ["Bubblegeist"] = {0.0055, 1, 1},
    ["Pink Scooter"] = {0.0055, 1, 5},
    ["Blue Boohoo Mega Neon Paint"] = {0.0055, 3, 7},
    ["White Scooter"] = {0.0055, 1, 5},
    ["Praying Mantis"] = {0.0055, 1, 1},
    ["Mochi Meow Tumble Animated Sticker"] = {0.0055, 2, 9},
    ["Solaris Animated Sticker"] = {0.0055, 2, 9},
    ["Sabertooth"] = {0.0055, 1, 1},
    ["Snow Leopard"] = {0.0055, 1, 1},
    ["Magma Snail"] = {0.0055, 1, 1},
    ["Hydra"] = {0.0055, 1, 1},
    ["Popsicle Stroller"] = {0.0055, 1, 4},
    ["Christmas Spirit"] = {0.0055, 1, 1},
    ["Kappakid"] = {0.0055, 1, 1},
    ["Goldfish"] = {0.0055, 1, 1},
    ["Shadow Rider"] = {0.0055, 1, 5},
    ["Blue Cat Ear Headphones"] = {0.0055, 2, 3},
    ["Blossom Snake"] = {0.0055, 1, 1},
    ["Sea Angel"] = {0.0055, 1, 1},
    ["Wood Scooter"] = {0.0055, 1, 5},
    ["Vulture"] = {0.0055, 1, 1},
    ["Ice Cream Truck"] = {0.0055, 2, 5},
    ["Urban Egg"] = {0.0055, 2, 2},
    ["Basilisk"] = {0.0055, 1, 1},
    ["Ghostly Cat"] = {0.0055, 1, 1},
    ["Kelp Hunter"] = {0.0055, 1, 1},
    ["Shetland Pony White"] = {0.0055, 1, 1},
    ["Hummingbird"] = {0.0055, 1, 1},
    ["2021 Uplift Butterfly"] = {0.0055, 1, 1},
    ["Malaysian Tapir"] = {0.0055, 1, 1},
    ["Spider Crab"] = {0.0055, 1, 1},
    ["Pine Marten"] = {0.0055, 1, 1},
    ["Ghost Chick"] = {0.0055, 1, 1},
    ["Wyvern"] = {0.0055, 1, 1},
    ["Deathstalker Scorpion"] = {0.0055, 1, 1},
    ["Subzero Scorpion"] = {0.0055, 1, 1},
    ["Nebula Snake"] = {0.0055, 1, 1},
    ["Steppe Lion"] = {0.0055, 1, 1},
    ["Trapdoor Snail"] = {0.0055, 1, 1},
    ["Wildfire Hawk"] = {0.0055, 1, 1},
    ["Grave Owl"] = {0.0055, 1, 1},
    ["Lobster"] = {0.0055, 1, 1},
    ["Singularity Pisces"] = {0.0055, 1, 1},
    ["Fanghorn Tortoise"] = {0.0055, 1, 1},
    ["Water Moon Bear"] = {0.0055, 1, 1},
    ["Roadrunner"] = {0.0055, 1, 1},
    ["Magma Moose"] = {0.0055, 1, 1},
    ["Starhopper"] = {0.0055, 1, 1},
    ["Gingerbread Reindeer"] = {0.0055, 1, 1},
    ["Ornate Horned Frog"] = {0.0055, 1, 1},
    ["Gingerbread Hare"] = {0.0055, 1, 1},
    ["Bird of Paradise"] = {0.0055, 1, 1},
    ["Peregrine Falcon"] = {0.0055, 1, 1},
    ["Raccoon"] = {0.0055, 1, 1},
    ["Prism Snake"] = {0.0055, 1, 1},
    ["Coyote"] = {0.0055, 1, 1},
    ["Salamander"] = {0.0055, 1, 1},
    ["Narwhal"] = {0.005, 1, 1},
    ["Ermine"] = {0.005, 1, 1},
    ["Eggnog Hare"] = {0.005, 1, 1},
    ["2022 Uplift Butterfly"] = {0.005, 1, 1},
    ["Dilophosaurus"] = {0.005, 1, 1},
    ["Rock Pigeon"] = {0.005, 1, 1},
    ["Lammergeier"] = {0.005, 1, 1},
    ["Temple Friend"] = {0.005, 1, 1},
    ["Albatross"] = {0.005, 1, 1},
    ["Pterodactyl"] = {0.005, 1, 1},
    ["Officer Gibbon"] = {0.005, 1, 1},
    ["Giant Black Scarab"] = {0.005, 1, 1},
    ["Mecha R4BBIT"] = {0.005, 1, 1},
    ["Green Amazon"] = {0.005, 1, 1},
    ["Ringmaster Gibbon"] = {0.005, 1, 1},
    ["Singularity Beetle"] = {0.005, 1, 1},
    ["Gingerbread Mouse"] = {0.005, 1, 1},
    ["Momma Moose"] = {0.005, 1, 1},
    ["King Penguin"] = {0.005, 1, 1},
    ["Seahorse"] = {0.005, 1, 1},
    ["Pirate Hat"] = {0.005, 1, 3},
    ["Bat Backpack"] = {0.005, 1, 3},
    ["Pirate Hat & Friend"] = {0.005, 1, 3},
    ["Flower Wings"] = {0.005, 1, 3},
    ["Fishbowl Hat"] = {0.005, 1, 3},
    ["Clam Wings"] = {0.005, 1, 3},
    ["Cupcake Sprinkle Wings"] = {0.005, 2, 3},
    ["Pterodactyl Wings"] = {0.005, 1, 3},
    ["Eyepatch"] = {0.005, 1, 3},
    ["Music Box Hat"] = {0.005, 1, 3},
    ["Daisymobile"] = {0.005, 1, 5},
    ["Headless Horseman's Biplane"] = {0.005, 1, 5},
    ["Fossil Paw Helicopter"] = {0.005, 1, 5},
    ["Penguin"] = {0.005, 1, 1},
    ["Rock"] = {0.005, 1, 1},
    ["Brain Jar"] = {0.005, 1, 3},
    ["Lunar New Year Shoes"] = {0.005, 1, 3},
    ["Lava Lamp Hat"] = {0.005, 1, 3},
    ["Blue Snowboard"] = {0.005, 1, 5},
    ["Husky Sled"] = {0.005, 1, 5},
    ["Bloodhound"] = {0.005, 1, 1},
    ["Tan Chow-Chow"] = {0.005, 1, 1},
    ["Yellow Butterfly"] = {0.005, 1, 1},
    ["Diamond Dragon"] = {0.005, 1, 1},
    ["Woolly Mammoth"] = {0.005, 1, 1},
    ["Cold Cube"] = {0.005, 1, 1},
    ["Lunar White Tiger"] = {0.005, 1, 1},
    ["Mongoose"] = {0.005, 1, 1},
    ["Undead Elk"] = {0.005, 1, 1},
    ["Ibex"] = {0.005, 1, 1},
    ["Cute-A-Cabra"] = {0.005, 1, 1},
    ["Magic House Door"] = {0.005, 2, 7},
    ["Banjo"] = {0.005, 1, 7},
    ["Jackhammer"] = {0.005, 1, 7},
    ["Peachick"] = {0.005, 1, 1},
    ["Santa Throne"] = {0.005, 1, 7},
    ["Dance Arcade Stand"] = {0.005, 1, 7},
    ["Fossil Egg"] = {0.005, 2, 2},
    ["Wrapped Doll"] = {0.005, 1, 2},
    ["Fool Egg"] = {0.005, 2, 2},
    ["Candyfloss Mega Neon Paint"] = {0.005, 3, 7},
    ["Halloween Slime Mega Neon Paint"] = {0.005, 3, 7},
    ["Firefighter Gibbon"] = {0.005, 1, 1},
    ["Nutcracker Squirrel"] = {0.005, 1, 1},
    ["Winter Doe"] = {0.005, 1, 1},
    ["Quetzalcoatl"] = {0.005, 1, 1},
    ["Snowman"] = {0.005, 1, 1},
    ["Indian Leopard"] = {0.005, 1, 1},
    ["Zombie Chick"] = {0.005, 1, 1},
    ["Warthog"] = {0.005, 1, 1},
    ["Brown-Chested Pheasant"] = {0.005, 1, 1},
    ["Red Fox"] = {0.005, 1, 1},
    ["Emu"] = {0.005, 1, 1},
    ["Ladybug"] = {0.005, 1, 1},
    ["Red Crowned Crane"] = {0.005, 1, 1},
    ["Hamster"] = {0.005, 1, 1},
    ["Sasquatch"] = {0.005, 1, 1},
    ["Australian Kelpie"] = {0.005, 1, 1},
    ["Clementine Owl"] = {0.005, 1, 1},
    ["Maine Coon"] = {0.005, 1, 1},
    ["Choco Penguin"] = {0.005, 1, 1},
    ["Ankylosaurus"] = {0.005, 1, 1},
    ["Cozy Mistletroll"] = {0.005, 1, 1},
    ["Black Kite"] = {0.005, 1, 1},
    ["Electric Hornet"] = {0.00475, 1, 1},
    ["Diamond Griffin"] = {0.00475, 1, 1},
    ["Golden Unicorn"] = {0.00475, 1, 1},
    ["Manta Ray"] = {0.00475, 1, 1},
    ["Skelicorn"] = {0.00475, 1, 1},
    ["Glormy Crab"] = {0.00475, 1, 1},
    ["Merhorse"] = {0.00475, 1, 1},
    ["Halloween White Mummy Cat"] = {0.00475, 1, 1},
    ["Possum"] = {0.0045, 1, 1},
    ["Birthday Butterfly 2023"] = {0.0045, 1, 1},
    ["Oryx"] = {0.0045, 1, 1},
    ["DJ Snooze"] = {0.0045, 1, 1},
    ["Snowblower Toboggan"] = {0.0045, 1, 5},
    ["Firework Cycle"] = {0.0045, 1, 5},
    ["Bewitched Hat"] = {0.0045, 1, 3},
    ["Emperor's Chariot"] = {0.0045, 1, 5},
    ["Cannon Stroller"] = {0.0045, 1, 4},
    ["Trike Stroller"] = {0.0045, 1, 4},
    ["Lavender Teapot Carriage"] = {0.0045, 1, 5},
    ["Flower Wagon"] = {0.0045, 1, 5},
    ["Satellite Spinner"] = {0.0045, 1, 3},
    ["Venus Flytrap Hat"] = {0.0045, 1, 3},
    ["Headband"] = {0.0045, 1, 3},
    ["Waterfall Hat"] = {0.0045, 1, 3},
    ["Leprechaun Hat"] = {0.0045, 1, 3},
    ["Flower Monocle"] = {0.0045, 1, 3},
    ["Lightbulb Hat"] = {0.0045, 1, 3},
    ["Golden Walrus Crown"] = {0.0045, 1, 3},
    ["Discosplosion"] = {0.0045, 2, 7},
    ["Ice Saber"] = {0.0045, 1, 7},
    ["Anna Rattle"] = {0.0045, 1, 7},
    ["Triceratops"] = {0.0045, 1, 1},
    ["Marabou Stork"] = {0.0045, 1, 1},
    ["Chickatrice"] = {0.0045, 1, 1},
    ["Mochi Meow"] = {0.0045, 1, 1},
    ["Mistletroll"] = {0.0045, 1, 1},
    ["Floral Eggy"] = {0.0045, 1, 1},
    ["Dugong"] = {0.0045, 1, 1},
    ["Fire Stallion"] = {0.0045, 1, 1},
    ["Sea Turtle"] = {0.0045, 1, 1},
    ["Tealwood Monster"] = {0.0045, 1, 1},
    ["Easter Bunny"] = {0.0045, 1, 1},
    ["Old King Coal"] = {0.0045, 1, 1},
    ["Starmite"] = {0.0045, 1, 1},
    ["Monster Mansion"] = {0.0045, 1, 10},
    ["Premium Sticker Pack"] = {0.0045, 2, 9},
    ["Honey"] = {0.0045, 2, 6},
    ["Ice Cube"] = {0.0045, 1, 1},
    ["Woodpecker"] = {0.0045, 1, 1},
    ["Kelp Raider"] = {0.0045, 1, 1},
    ["Dirty Ducky"] = {0.0045, 1, 1},
    ["Bee"] = {0.0045, 1, 1},
    ["Toxic Kaijunior"] = {0.0045, 1, 1},
    ["Black Dog"] = {0.0045, 1, 1},
    ["Poison Dart Frog"] = {0.0045, 1, 1},
    ["Ibis"] = {0.0045, 1, 1},
    ["Skelebat"] = {0.0045, 1, 1},
    ["Frogspawn"] = {0.0045, 1, 1},
    ["Eel"] = {0.0045, 1, 1},
    ["Slug"] = {0.0045, 1, 1},
    ["Thorny Devil"] = {0.0045, 1, 1},
    ["Chilling Spider"] = {0.0045, 1, 1},
    ["Liger"] = {0.0045, 1, 1},
    ["Cattuccino"] = {0.0045, 2, 1},
    ["Three Blind Mice"] = {0.0045, 1, 1},
    ["Arctic Tern"] = {0.0045, 1, 1},
    ["Alicorn"] = {0.0045, 1, 1},
    ["Dolphin"] = {0.0045, 1, 1},
    ["Lionfish"] = {0.0045, 1, 1},
    ["Stray Cat Dragon"] = {0.0045, 1, 1},
    ["Golden Dragon"] = {0.0045, 1, 1},
    ["Scarecrow Horse"] = {0.0045, 1, 1},
    ["Monkey"] = {0.0045, 1, 1},
    ["Stegosaurus"] = {0.0045, 1, 1},
    ["Blue Jay"] = {0.0045, 1, 1},
    ["Flower Stroller"] = {0.0045, 1, 4},
    ["Robin"] = {0.0045, 1, 1},
    ["Lunar Ox"] = {0.0045, 1, 1},
    ["Huntsman Robin"] = {0.0043, 1, 1},
    ["Oakee Wizard"] = {0.0043, 1, 1},
    ["Dark Choccybunny"] = {0.0043, 1, 1},
    ["Weevil"] = {0.00425, 1, 1},
    ["Diamond Mahi Mahi"] = {0.00425, 1, 1},
    ["Walrus"] = {0.00425, 1, 1},
    ["Ancient Dragon"] = {0.00425, 1, 1},
    ["Cockroach"] = {0.00425, 1, 1},
    ["Golden Griffin"] = {0.00425, 1, 1},
    ["Blue Whale"] = {0.00425, 1, 1},
    ["Dragonfly"] = {0.00425, 1, 1},
    ["Purrowl"] = {0.00425, 1, 1},
    ["Dragon"] = {0.00425, 1, 1},
    ["Arctic Hare"] = {0.00425, 1, 1},
    ["Ash Zebra Bait"] = {0.004, 2, 6},
    ["Flaming Zebra Bait"] = {0.004, 2, 6},
    ["Scarecrow Box"] = {0.004, 2, 8},
    ["Velvet Fuchsia Mega Neon Paint"] = {0.004, 3, 7},
    ["Strawberry Shortcake Bat Dragon Sticker"] = {0.004, 2, 9},
    ["Tropical Surge Mega Neon Paint"] = {0.004, 3, 7},
    ["Bunny Plush"] = {0.004, 1, 7},
    ["Zeopod"] = {0.004, 1, 1},
    ["Emperor Shrimp"] = {0.004, 1, 1},
    ["Red Cardinal"] = {0.004, 1, 1},
    ["Hammerhead Shark"] = {0.004, 1, 1},
    ["Urchin"] = {0.004, 1, 1},
    ["Hermit Crab"] = {0.004, 1, 1},
    ["Crab"] = {0.004, 1, 1},
    ["Dylan"] = {0.004, 1, 2},
    ["Christmas Future Egg"] = {0.004, 2, 2},
    ["Orange Betta Fish"] = {0.004, 1, 1},
    ["Pistachio"] = {0.004, 1, 2},
    ["Birthday Butterfly 2024"] = {0.004, 1, 1},
    ["Gemstone Egg"] = {0.004, 2, 2},
    ["River"] = {0.004, 1, 2},
    ["Puppy Plush"] = {0.004, 1, 7},
    ["Elephant Plush"] = {0.004, 1, 7},
    ["Crossbow Grappling Hook"] = {0.004, 1, 7},
    ["Croc Plush"] = {0.004, 1, 7},
    ["Rose Quartz Glow Mega Neon Paint"] = {0.004, 3, 7},
    ["Campfire Stories Mega Neon Paint"] = {0.004, 3, 7},
    ["Phoenix Plush"] = {0.004, 1, 7},
    ["Llama Plush"] = {0.004, 1, 7},
    ["Compass"] = {0.004, 1, 7},
    ["Chick Plush"] = {0.004, 1, 7},
    ["Whoopee Cushion"] = {0.004, 1, 7},
    ["Special Lunar New Year Gift Box"] = {0.004, 1, 8},
    ["Kangaroo Stroller"] = {0.004, 1, 4},
    ["Halloween Mummy Cat Box"] = {0.004, 1, 8},
    ["Pony Box"] = {0.004, 2, 8},
    ["Easter Eggy Box"] = {0.004, 1, 8},
    ["Electric Tide Mega Neon Paint"] = {0.004, 3, 7},
    ["Candy Flare Mega Neon Paint"] = {0.004, 3, 7},
    ["Amethyst Skies Mega Neon Paint"] = {0.004, 3, 7},
    ["Easter Bunny Plush"] = {0.004, 1, 7},
    ["Fancy Umbrella"] = {0.004, 1, 7},
    ["Halloween Blue Scorpion"] = {0.004, 1, 1},
    ["Winter Fawn"] = {0.004, 1, 1},
    ["Kelp Crewmate"] = {0.004, 1, 1},
    ["Rattlesnake"] = {0.004, 1, 1},
    ["Wing Trunk Car"] = {0.004, 1, 5},
    ["Hoverboard"] = {0.004, 1, 5},
    ["Classic Teapot"] = {0.004, 1, 1},
    ["Magical Girl Car"] = {0.004, 1, 5},
    ["Tarantula"] = {0.004, 1, 1},
    ["Dotted Eggy"] = {0.004, 1, 1},
    ["Dire Wolf"] = {0.004, 1, 1},
    ["Rhino Beetle"] = {0.004, 1, 1},
    ["Sea Skeleton Panda"] = {0.004, 1, 1},
    ["Gila Monster"] = {0.004, 1, 1},
    ["Rodeo Bull"] = {0.004, 1, 1},
    ["Puddleducks Hood"] = {0.004, 1, 3},
    ["Bubble Car"] = {0.004, 1, 5},
    ["Money Hat"] = {0.004, 1, 3},
    ["Ruff"] = {0.004, 1, 3},
    ["Strawberry Clip"] = {0.004, 2, 3},
    ["Cutlass"] = {0.004, 1, 3},
    ["Sakura Wings"] = {0.004, 2, 3},
    ["Energy Aura Feet"] = {0.004, 2, 3},
    ["Chimney Hat"] = {0.004, 1, 3},
    ["Midnight Wings"] = {0.004, 2, 3},
    ["Tutu"] = {0.004, 2, 3},
    ["Ferris Wheel Hat"] = {0.004, 1, 3},
    ["Lava Racer"] = {0.004, 1, 5},
    ["Santa Copter"] = {0.004, 1, 5},
    ["Strawberry Shortcake Bow"] = {0.004, 2, 3},
    ["Jetpack"] = {0.004, 1, 3},
    ["Mandarin's Hat"] = {0.004, 1, 3},
    ["Golden Hair"] = {0.004, 1, 3},
    ["Bat"] = {0.004, 1, 1},
    ["Ghost"] = {0.004, 1, 1},
    ["Persian Cat"] = {0.004, 1, 1},
    ["Yellow-Lipped Sea Krait"] = {0.004, 1, 1},
    ["Kaijunior"] = {0.004, 1, 1},
    ["Banded Palm Civet"] = {0.004, 1, 1},
    ["Kirin"] = {0.004, 1, 1},
    ["Mrs. Whiskerpips"] = {0.004, 1, 1},
    ["Rat"] = {0.004, 1, 1},
    ["Scarecrow"] = {0.004, 1, 1},
    ["Gorilla"] = {0.004, 1, 1},
    ["Dracula Fish"] = {0.004, 1, 1},
    ["Fossa"] = {0.004, 1, 1},
    ["Moonpine"] = {0.004, 1, 1},
    ["Waffle Wyrm"] = {0.00375, 1, 1},
    ["Velociraptor"] = {0.00375, 1, 1},
    ["Black Moon Bear"] = {0.00375, 1, 1},
    ["Tawny Frogmouth"] = {0.00375, 1, 1},
    ["Ground Sloth"] = {0.00375, 1, 1},
    ["Dingo"] = {0.00375, 1, 1},
    ["Black Marlin"] = {0.00375, 1, 1},
    ["Ghost Wolf"] = {0.00375, 1, 1},
    ["Brachiosaurus"] = {0.00375, 1, 1},
    ["Angelfish"] = {0.00375, 1, 1},
    ["Shetland Pony Dark Brown"] = {0.00375, 1, 1},
    ["Tasmanian Tiger"] = {0.00375, 1, 1},
    ["Royal Carriage"] = {0.0035, 1, 5},
    ["Princess Carriage"] = {0.0035, 1, 5},
    ["Egg Delivery Machine"] = {0.0035, 1, 5},
    ["Prince Carriage"] = {0.0035, 1, 5},
    ["Festive Deliveries Sleigh"] = {0.0035, 1, 5},
    ["Burnt Bites Bait"] = {0.0035, 1, 6},
    ["Bat Dragon Sticker"] = {0.0035, 2, 9},
    ["Donut Throw Toy"] = {0.0035, 1, 7},
    ["Ferris Wheel Propeller"] = {0.0035, 1, 7},
    ["Moon Bear Box"] = {0.0035, 1, 8},
    ["Pretty Please Snowball Sticker"] = {0.0035, 2, 9},
    ["Well, Actually Walrus Sticker"] = {0.0035, 2, 9},
    ["Halloween Chick Box"] = {0.0035, 1, 8},
    ["Frostbite Bear and Cub Animated Sticker"] = {0.0035, 1, 9},
    ["Netzooka"] = {0.0035, 1, 7},
    ["Balloon Stroller"] = {0.0035, 1, 4},
    ["Pumpkin Stroller"] = {0.0035, 1, 4},
    ["Rainbow Wand"] = {0.0035, 1, 7},
    ["Strawberry Stroller"] = {0.0035, 1, 4},
    ["Elephant Stroller"] = {0.0035, 1, 4},
    ["Unicorn Leash"] = {0.0035, 1, 7},
    ["Football Throw Toy"] = {0.0035, 1, 7},
    ["Cotton Candy Stand"] = {0.0035, 1, 7},
    ["Starpower Wand"] = {0.0035, 1, 7},
    ["Borhyaena Gigantica"] = {0.0035, 1, 1},
    ["Frozen Penguin"] = {0.0035, 1, 1},
    ["Snorgle"] = {0.0035, 1, 1},
    ["Capuchin Monkey"] = {0.0035, 1, 1},
    ["Armadillo"] = {0.0035, 1, 1},
    ["Summer Straw Hat"] = {0.0035, 1, 3},
    ["Watery Wings"] = {0.0035, 1, 3},
    ["Flower Beret"] = {0.0035, 1, 3},
    ["Ponytail"] = {0.0035, 1, 3},
    ["2025 Birthday Butterfly"] = {0.0035, 1, 1},
    ["Ginger Cat"] = {0.0035, 1, 1},
    ["Angus Calf"] = {0.0035, 1, 1},
    ["Wolpertinger"] = {0.0035, 1, 1},
    ["Onza"] = {0.0035, 1, 1},
    ["Kid Goat"] = {0.0035, 1, 1},
    ["Samoyed"] = {0.0035, 1, 1},
    ["Hopbop"] = {0.0035, 1, 1},
    ["Jumping Spider"] = {0.0035, 1, 1},
    ["Firey Aura"] = {0.0035, 1, 3},
    ["Nest of Eggs"] = {0.0035, 1, 3},
    ["Ratatoskr"] = {0.0035, 1, 1},
    ["Maleo Bird"] = {0.0035, 1, 1},
    ["Wren"] = {0.0035, 1, 1},
    ["Snowy Mammoth"] = {0.0035, 1, 1},
    ["Ghost Kitty Backpack"] = {0.0035, 1, 3},
    ["Science Hat"] = {0.0035, 1, 3},
    ["Pandaguin Glooptodog"] = {0.0035, 1, 1},
    ["Nature's Crown"] = {0.0035, 1, 3},
    ["Rubber Ducks"] = {0.0035, 1, 3},
    ["Duck Floatie"] = {0.0035, 1, 3},
    ["Back Taco"] = {0.0035, 2, 3},
    ["Summer Walrus Sunhat"] = {0.0035, 1, 3},
    ["Easter Egg Friends"] = {0.0035, 1, 3},
    ["Ox"] = {0.0035, 1, 1},
    ["Garden Snake"] = {0.0035, 1, 1},
    ["Bandicoot"] = {0.0035, 1, 1},
    ["Amber Butterfly"] = {0.0035, 1, 1},
    ["Icy Porcupine"] = {0.0035, 1, 1},
    ["Ehecatl"] = {0.0035, 1, 1},
    ["Southeast Asia Egg"] = {0.0035, 2, 2},
    ["Halloween Black Mummy Cat"] = {0.0035, 1, 1},
    ["Frankenfeline"] = {0.0035, 1, 1},
    ["Boohoo"] = {0.0035, 1, 1},
    ["Orca"] = {0.0035, 1, 1},
    ["Toucan"] = {0.0035, 1, 1},
    ["Stitches"] = {0.0035, 1, 1},
    ["Gumball Caterpillar"] = {0.0035, 1, 1},
    ["Gibbon"] = {0.0035, 1, 1},
    ["Stingray"] = {0.0035, 1, 1},
    ["Thunderfisher"] = {0.0035, 1, 1},
    ["Starfish"] = {0.0035, 1, 1},
    ["Bakeneko"] = {0.0035, 1, 1},
    ["Woodland Egg"] = {0.0035, 2, 2},
    ["Sandfish"] = {0.0035, 1, 1},
    ["Show Pony"] = {0.0035, 1, 1},
    ["Bali Starling"] = {0.0035, 1, 1},
    ["Piranha"] = {0.0035, 1, 1},
    ["Turtle Doves"] = {0.0035, 1, 1},
    ["Island Tarsier"] = {0.0035, 1, 1},
    ["Angler Fish"] = {0.0035, 1, 1},
    ["Mythic Egg"] = {0.0035, 2, 2},
    ["Diamond Egg"] = {0.0035, 1, 2},
    ["Mosquito"] = {0.0035, 1, 1},
    ["Ocean Egg"] = {0.0035, 2, 2},
    ["Jumpscare"] = {0.0035, 1, 1},
    ["Pomeranian"] = {0.0035, 1, 1},
    ["Bluebottle Fly"] = {0.0035, 1, 1},
    ["Beluga Whale"] = {0.0035, 1, 1},
    ["Lunar Tiger"] = {0.0035, 1, 1},
    ["Mole"] = {0.0035, 1, 1},
    ["Bullfrog"] = {0.0035, 1, 1},
    ["Bobageist"] = {0.0035, 1, 1},
    ["Sado Mole"] = {0.0035, 1, 1},
    ["Shoebill"] = {0.00325, 1, 1},
    ["Water Opossum"] = {0.00325, 1, 1},
    ["Jester Hat"] = {0.00325, 1, 3},
    ["Mummy Spider"] = {0.00325, 1, 1},
    ["Blue Cat"] = {0.00325, 1, 1},
    ["Red Panda"] = {0.00325, 1, 1},
    ["Corgi"] = {0.00325, 1, 1},
    ["Patchy Bear"] = {0.00325, 1, 1},
    ["Blue Butterfly"] = {0.00325, 1, 1},
    ["Pangolin"] = {0.00325, 1, 1},
    ["Caramelgeist"] = {0.00325, 1, 1},
    ["Bolt"] = {0.00325, 1, 1},
    ["Black-Footed Ferret"] = {0.00325, 1, 1},
    ["Flying Fish"] = {0.00325, 1, 1},
    ["Little Lamb"] = {0.00325, 1, 1},
    ["Pink Dog"] = {0.00325, 1, 1},
    ["Tree Sasquatch"] = {0.00325, 1, 1},
    ["Shiba Inu"] = {0.00325, 1, 1},
    ["Chanekeh"] = {0.00325, 1, 1},
    ["Crimson Cape"] = {0.00325, 1, 1},
    ["Swordfish"] = {0.00325, 1, 1},
    ["Yellow Taxi Cab"] = {0.00325, 1, 5},
    ["Santa's Sleigh"] = {0.00325, 1, 5},
    ["Robot"] = {0.00325, 1, 1},
    ["Black Cab"] = {0.00325, 1, 5},
    ["Badger"] = {0.00325, 1, 1},
    ["Oakee"] = {0.0031, 1, 1},
    ["Muskrat"] = {0.0031, 1, 1},
    ["Sneak Weasel"] = {0.0031, 1, 1},
    ["Gummy Guana"] = {0.0031, 1, 1},
    ["Fire Foal"] = {0.0031, 1, 1},
    ["California Condor"] = {0.0031, 1, 1},
    ["Kakapo"] = {0.0031, 1, 1},
    ["Magpie"] = {0.0031, 1, 1},
    ["Cherub Chipmunk"] = {0.0031, 1, 1},
    ["Japanese Snow Fairy"] = {0.0031, 1, 1},
    ["Aye Aye"] = {0.0031, 1, 1},
    ["Beaver"] = {0.0031, 1, 1},
    ["Cocoadile"] = {0.0031, 1, 1},
    ["Ocelot"] = {0.0031, 1, 1},
    ["Black Rhino"] = {0.0031, 1, 1},
    ["Mexican Wolf"] = {0.0031, 1, 1},
    ["Ribbon Seal"] = {0.0031, 1, 1},
    ["Glyptodon Ducky"] = {0.0031, 1, 1},
    ["Bison"] = {0.0031, 1, 1},
    ["Rubber Ducky"] = {0.0031, 1, 1},
    ["Grinmoire"] = {0.0031, 1, 1},
    ["Galapagos Sea Lion"] = {0.0031, 1, 1},
    ["Unicorn Ducky"] = {0.0031, 1, 1},
    ["Donkey"] = {0.0031, 1, 1},
    ["Red Panda Ducky"] = {0.0031, 1, 1},
    ["River Otter"] = {0.0031, 1, 1},
    ["Clubtail Dragonfly"] = {0.0031, 1, 1},
    ["Stygian Owl"] = {0.0031, 1, 1},
    ["Irish Setter"] = {0.0031, 1, 1},
    ["Gecko Ducky"] = {0.0031, 1, 1},
    ["Nurse Shark"] = {0.0031, 1, 1},
    ["Sheepdog Ducky"] = {0.0031, 1, 1},
    ["Pilot Gull"] = {0.0031, 1, 1},
    ["Oakee Knight"] = {0.0031, 1, 1},
    ["Rainbow Trout"] = {0.0031, 1, 1},
    ["Storm Condor"] = {0.0031, 1, 1},
    ["Sunflower Friend"] = {0.0031, 1, 1},
    ["Ms. Muffet"] = {0.0031, 1, 1},
    ["Gold Mahi Mahi"] = {0.0031, 1, 1},
    ["Violet Friend"] = {0.0031, 1, 1},
    ["Abyssinian Cat"] = {0.0031, 1, 1},
    ["Chestnut Glyptodon"] = {0.0031, 1, 1},
    ["Tegu"] = {0.0031, 1, 1},
    ["Ruddy Duck"] = {0.0031, 1, 1},
    ["Zebra"] = {0.0031, 1, 1},
    ["Forest Sprite"] = {0.0031, 1, 1},
    ["2026 Birthday Butterfly"] = {0.0031, 1, 1},
    ["Chocolate Labrador"] = {0.0031, 1, 1},
    ["Pinkypillar"] = {0.0031, 1, 1},
    ["White Choccybunny"] = {0.0031, 1, 1},
    ["Humbug"] = {0.0031, 1, 1},
    ["Shih Tzu"] = {0.0031, 1, 1},
    ["Milk Choccybunny"] = {0.0031, 1, 1},
    ["Angus Cow"] = {0.0031, 1, 1},
    ["Bunny"] = {0.0031, 1, 1},
    ["Jiggly Jerboa"] = {0.0031, 1, 1},
    ["Tree Frog"] = {0.0031, 1, 1},
    ["Orangutan"] = {0.0031, 1, 1},
    ["Princess Mare"] = {0.0031, 1, 1},
    ["Budgie Witch"] = {0.0031, 1, 1},
    ["Clumpty"] = {0.0031, 1, 1},
    ["Black Tiger"] = {0.0031, 1, 1},
    ["Jacobin Pigeon"] = {0.0031, 1, 1},
    ["Granny Wolf"] = {0.0031, 1, 1},
    ["Fennec Fox"] = {0.003, 1, 1},
    ["Snow Puma"] = {0.003, 1, 1},
    ["Dog"] = {0.003, 1, 1},
    ["Snow Cat"] = {0.003, 1, 1},
    ["Poodle"] = {0.003, 1, 1},
    ["Cat"] = {0.003, 1, 1},
    ["Otter"] = {0.003, 1, 1},
    ["Mouse"] = {0.003, 1, 1},
    ["Rabbit"] = {0.003, 1, 1},
    ["Ant"] = {0.003, 1, 1},
    ["Buffalo"] = {0.003, 1, 1},
    ["Mahi Mahi"] = {0.003, 1, 1},
    ["Puma"] = {0.003, 1, 1},
    ["Parakeet"] = {0.003, 1, 1},
    ["Hamster Selfie Sticker"] = {0.003, 2, 9},
    ["Cow Loves This Sticker"] = {0.003, 1, 9},
    ["Winter Deer Family Sticker"] = {0.003, 1, 9},
    ["Parrot Sticker"] = {0.003, 1, 9},
    ["Dinner Discourse Cat Sticker"] = {0.003, 2, 9},
    ["Wet Owl Sticker"] = {0.003, 2, 9},
    ["Wailing Mr. Whiskerpips Sticker"] = {0.003, 1, 9},
    ["Ox Box"] = {0.003, 1, 8},
    ["Standard Capuchin Box"] = {0.003, 1, 8},
    ["Lunar Tiger Box"] = {0.003, 1, 8},
    ["Long Ermine Sticker"] = {0.003, 1, 9},
    ["Round Fallow Deer Sticker"] = {0.003, 1, 9},
    ["Balloon Unicorn Sticker"] = {0.003, 2, 9},
    ["Camel"] = {0.003, 1, 1},
    ["Noob Balloon"] = {0.003, 1, 7},
    ["Scarab Crossbow Grappling Hook"] = {0.003, 1, 7},
    ["Pro Ghost Blaster"] = {0.003, 2, 7},
    ["Polar Bear Plush"] = {0.003, 1, 7},
    ["Marshmallow Stand"] = {0.003, 1, 7},
    ["Rib Guitar"] = {0.003, 1, 7},
    ["Wooden Pogo"] = {0.003, 1, 7},
    ["Fancy Balloon"] = {0.003, 1, 7},
    ["Horse Plush"] = {0.003, 1, 7},
    ["Chocolate Bunny Balloon"] = {0.003, 1, 7},
    ["Skeleton Pogo Stick"] = {0.003, 1, 7},
    ["Inflatable Sword"] = {0.003, 1, 7},
    ["Balloons"] = {0.003, 1, 7},
    ["Ukulele"] = {0.003, 1, 7},
    ["Marsh Plush"] = {0.003, 1, 7},
    ["Snow Cone Stand"] = {0.003, 1, 7},
    ["Axe Rattle"] = {0.003, 1, 7},
    ["Octopus Plush"] = {0.003, 1, 7},
    ["Egg Rattle"] = {0.003, 1, 7},
    ["Classic Trade Stand"] = {0.003, 2, 7},
    ["Christmas Cat Rattle"] = {0.003, 1, 7},
    ["Stars Egg"] = {0.003, 1, 6},
    ["Caticorn Rattle"] = {0.003, 1, 7},
    ["Skull Drum"] = {0.003, 1, 7},
    ["Christmas Doge Rattle"] = {0.003, 1, 7},
    ["Patterns Egg"] = {0.003, 1, 6},
    ["Stripes Egg"] = {0.003, 1, 6},
    ["Gold Fairy Crown"] = {0.003, 1, 3},
    ["Glamicorn Purse Pet"] = {0.003, 1, 3},
    ["Pink Designer Backpack"] = {0.003, 1, 3},
    ["Watermelon Backpack"] = {0.003, 1, 3},
    ["City Hat"] = {0.003, 1, 3},
    ["Personal Controller"] = {0.003, 1, 3},
    ["Lunar New Year Collar"] = {0.003, 1, 3},
    ["Kraken Hat"] = {0.003, 1, 3},
    ["Pink Instant Camera"] = {0.003, 2, 3},
    ["Picnic Basket"] = {0.003, 1, 3},
    ["Heart Bow"] = {0.003, 2, 3},
    ["White Chef Hat"] = {0.003, 1, 3},
    ["Halloween White Skull Hat"] = {0.003, 2, 3},
    ["Shark Swimcap"] = {0.003, 1, 3},
    ["Corndog Mustache"] = {0.003, 1, 3},
    ["Volcanic Boots"] = {0.003, 1, 3},
    ["Volcano Hat"] = {0.003, 1, 3},
    ["Tiffany"] = {0.003, 1, 5},
    ["Axel"] = {0.003, 1, 5},
    ["Ribcage Carriage"] = {0.003, 1, 5},
    ["Unicorn Zombie Ponycycle"] = {0.003, 1, 5},
    ["Ice Queen Sleigh"] = {0.003, 1, 5},
    ["Douglas"] = {0.003, 1, 5},
    ["Choo Choo Train"] = {0.003, 1, 5},
    ["Shadow Dragon Skateboard"] = {0.003, 1, 5},
    ["Giant Snowball"] = {0.003, 1, 5},
    ["Paint Roller Truck"] = {0.003, 1, 5},
    ["Postie Van"] = {0.003, 1, 5},
    ["Luxury Apartments"] = {0.003, 1, 10},
    ["Fairytale Castle"] = {0.003, 1, 10},
    ["Traveling House"] = {0.003, 1, 5},
    ["Dragonster"] = {0.003, 1, 5},
    ["Hovertible"] = {0.003, 1, 5},
    ["Banana Car"] = {0.003, 1, 5},
    ["Yellow Instant Camera"] = {0.003, 2, 3},
    ["Festive Beard"] = {0.003, 1, 3},
    ["Rain Hat"] = {0.003, 2, 3},
    ["Llamalush Purse Pet"] = {0.003, 1, 3},
    ["Reindeer Stroller"] = {0.003, 1, 4},
    ["Grinder Hat"] = {0.003, 1, 3},
    ["Top Hat"] = {0.003, 1, 3},
    ["Balloon Dog"] = {0.003, 1, 3},
    ["Fishbone Badge"] = {0.003, 2, 3},
    ["Sack of Cash"] = {0.003, 1, 3},
    ["Police Cap"] = {0.003, 1, 3},
    ["Ice Grapple"] = {0.00275, 1, 7},
    ["Vampire Teeth Grappling Hook"] = {0.0025, 1, 7},
    ["Creepy Balloon"] = {0.0025, 1, 7},
    ["Slimingo Feather Teleporter"] = {0.0025, 2, 7},
    ["Throwing Pumpkin"] = {0.0025, 1, 7},
    ["Money Rattle"] = {0.0025, 1, 7},
    ["Balloon"] = {0.0025, 1, 7},
    ["Rocket Pogo"] = {0.0025, 1, 7},
    ["Chick Backpack"] = {0.0025, 1, 3},
    ["Dandelion Propeller"] = {0.0025, 1, 7},
    ["Premium Camping Tent"] = {0.0025, 1, 7},
    ["Banana Pogo"] = {0.0025, 1, 7},
    ["Aztec Crown"] = {0.0025, 1, 3},
    ["Burger Bun Hat"] = {0.0025, 1, 3},
    ["Halloween Evil Barrel Backpack"] = {0.0025, 1, 3},
    ["Puppeteer Hand"] = {0.0025, 1, 3},
    ["Buttoned Ushanka"] = {0.0025, 1, 3},
    ["Purple Heart Glasses"] = {0.0025, 1, 3},
    ["Three Egg Basket"] = {0.0025, 1, 3},
    ["Bunny Ear Tiara"] = {0.0025, 1, 3},
    ["Star Sunglasses"] = {0.0025, 1, 3},
    ["Flower Aura"] = {0.0025, 1, 3},
    ["Festive Light Crown"] = {0.0025, 1, 3},
    ["Halloween Orange Pumpkin Friend Hat"] = {0.0025, 1, 3},
    ["Squid Plush"] = {0.0025, 1, 7},
    ["Unstable Triangle Car"] = {0.0025, 1, 5},
    ["Festive Wagon"] = {0.0025, 1, 5},
    ["Imagination Box"] = {0.0025, 1, 5},
    ["Royal Fairytale Egg"] = {0.0025, 1, 2},
    ["Slothula Transformation Animated Sticker"] = {0.0025, 1, 9},
    ["Mansion"] = {0.0025, 2, 10},
    ["Halloween Hotel"] = {0.0025, 1, 10},
    ["Dapper Friend Carrier"] = {0.0025, 1, 5},
    ["Dino Truck"] = {0.0025, 1, 5},
    ["Candy Snowmobile"] = {0.0025, 1, 5},
    ["Wizard Caravan"] = {0.0025, 1, 5},
    ["Celestial Carrier"] = {0.0025, 1, 5},
    ["Hovercar"] = {0.0025, 1, 5},
    ["Bee Shuttle"] = {0.0025, 1, 5},
    ["Energy Wings"] = {0.002, 1, 3},
    ["Viking Helmet"] = {0.002, 1, 3},
    ["Modern Jetpack"] = {0.002, 1, 3},
    ["Sakura Scythe"] = {0.002, 1, 3},
    ["Winter Bow Wings"] = {0.002, 1, 3},
    ["Fantastical Wings"] = {0.002, 1, 3},
    ["Red Wagon Stroller"] = {0.002, 1, 4},
    ["Candy Cane Wings"] = {0.002, 1, 3},
    ["Winged Horse Sticker"] = {0.002, 1, 9},
    ["Telescope Pogo"] = {0.002, 1, 7},
    ["Palanquin Stroller"] = {0.002, 1, 4},
    ["Kitsune Sticker"] = {0.002, 1, 9},
    ["Heart Ribbon"] = {0.002, 1, 3},
    ["Galaxy Explorer Helmet"] = {0.002, 1, 3},
    ["Cheese Hat"] = {0.002, 1, 3},
    ["Elf Shoes"] = {0.002, 1, 3},
    ["Macaw Wings"] = {0.002, 1, 3},
    ["Elf Bandana"] = {0.002, 1, 3},
    ["Orbweaver Glider"] = {0.002, 1, 7},
    ["Stygian Hang Glider"] = {0.002, 1, 7},
    ["Festive Bells Balloon"] = {0.002, 1, 7},
    ["Glormy Backpack"] = {0.002, 1, 3},
    ["Unfortunate Eyelashes"] = {0.002, 1, 3},
    ["Heart Plushie"] = {0.002, 1, 7},
    ["Hotdog Stand"] = {0.002, 1, 7},
    ["Cookie Dough Plush"] = {0.002, 1, 7},
    ["Turkey Plush"] = {0.002, 1, 7},
    ["Fall Corn Grappling Hook"] = {0.002, 1, 7},
    ["Santa's Bow"] = {0.002, 1, 3},
    ["Bear Hood"] = {0.002, 1, 3},
    ["Chick Hat"] = {0.002, 1, 3},
    ["Mule Baskets"] = {0.002, 1, 3},
    ["Bee Hive"] = {0.002, 1, 3},
    ["Pink Butterfly Wings"] = {0.002, 1, 3},
    ["Eaten Donut"] = {0.002, 1, 3},
    ["Heart Lock Necklace"] = {0.002, 1, 3},
    ["Heart Hat"] = {0.002, 1, 3},
    ["Candy Cane (Pet Wear)"] = {0.002, 1, 3},
    ["Banana Stroller"] = {0.002, 1, 4},
    ["Golden Egg"] = {0.002, 1, 2},
    ["Desert Egg"] = {0.002, 2, 2},
    ["Micro Car"] = {0.002, 1, 5},
    ["Canine Cruiser"] = {0.002, 1, 5},
    ["Snow Plow"] = {0.002, 1, 5},
    ["Motorized Sofa"] = {0.002, 1, 5},
    ["Japan Egg"] = {0.002, 2, 2},
    ["Space Whale Sticker"] = {0.002, 1, 9},
    ["Clown Car"] = {0.002, 1, 5},
    ["Chairlift"] = {0.002, 1, 5},
    ["Camper Van"] = {0.002, 1, 5},
    ["Charon's Boat"] = {0.002, 1, 5},
    ["Sunshine Chariot"] = {0.002, 1, 5},
    ["Lunar Muscle Car"] = {0.002, 1, 5},
    ["Gingerbread Stunt Plane"] = {0.002, 1, 5},
    ["Zamboni"] = {0.002, 1, 5},
    ["Standard Gorilla Box"] = {0.002, 1, 8},
    ["Carrot Rattle"] = {0.002, 1, 7},
    ["Inspector Sherbet Bus"] = {0.002, 1, 5},
    ["Squished Red Pandorama Sticker"] = {0.002, 1, 9},
    ["Phoenix Sticker"] = {0.002, 1, 9},
    ["Sour Glider"] = {0.002, 1, 7},
    ["Reindeer Plush"] = {0.002, 1, 7},
    ["Squirrel Car"] = {0.002, 1, 5},
    ["SUV"] = {0.002, 1, 5},
    ["Gummy Biplane"] = {0.002, 1, 5},
    ["Hot Rod Sleigh"] = {0.002, 1, 5},
    ["Heart Hoverboard"] = {0.002, 1, 5},
    ["Zodiac Minion Egg"] = {0.00175, 1, 2},
    ["Dalmatian Sticker"] = {0.0015, 1, 9},
    ["Hot Doggo Sticker"] = {0.0015, 1, 9},
    ["Flamingo Sticker"] = {0.0015, 1, 9},
    ["Fairy Bat Dragon Sticker"] = {0.0015, 1, 9},
    ["Cow Sticker"] = {0.0015, 1, 9},
    ["Turtle Sticker"] = {0.0015, 1, 9},
    ["Elephant Sticker"] = {0.0015, 1, 9},
    ["African Painted Dog Sticker"] = {0.0015, 1, 9},
    ["Shark Puppy Sticker"] = {0.0015, 1, 9},
    ["Pelican Sticker"] = {0.0015, 1, 9},
    ["Hollywood House"] = {0.0015, 1, 10},
    ["Premium Fire Pit"] = {0.0015, 1, 7},
    ["Wheelbarrow Stroller"] = {0.0015, 1, 4},
    ["Standard Gibbon Box"] = {0.0015, 1, 8},
    ["Dragon Balloon"] = {0.0015, 1, 7},
    ["Banana Plush"] = {0.0015, 1, 7},
    ["Lemonade Stand"] = {0.0015, 1, 7},
    ["Marsh Balloon"] = {0.0015, 1, 7},
    ["Moon Viewing Bench"] = {0.0015, 1, 7},
    ["Triple Stroller"] = {0.0015, 1, 4},
    ["Ornament Throw Toy"] = {0.0015, 1, 7},
    ["Candle"] = {0.0015, 1, 7},
    ["Heart Balloon"] = {0.0015, 1, 7},
    ["Elf Plush"] = {0.0015, 1, 7},
    ["Throne Stroller"] = {0.0015, 1, 4},
    ["Hatched Egg Stroller"] = {0.0015, 1, 4},
    ["Egg Basket Stroller"] = {0.0015, 1, 4},
    ["Donut Stroller"] = {0.0015, 1, 4},
    ["Dog House Stroller"] = {0.0015, 1, 4},
    ["Hot Air Balloon"] = {0.0015, 1, 5},
    ["Speedboat"] = {0.0015, 1, 5},
    ["Taco"] = {0.0015, 1, 6},
    ["Spinning Teacup Vehicle"] = {0.0015, 1, 5},
    ["Gingerbread Wings"] = {0.0015, 1, 3},
    ["RB Battles Trophy Hat"] = {0.0015, 1, 3},
    ["Snow Globetrotter"] = {0.0015, 1, 5},
    ["Eco Orange Maple Cape"] = {0.0015, 1, 3},
    ["Bumper Car"] = {0.0015, 1, 5},
    ["Beach Buggy"] = {0.0015, 1, 5},
    ["RGB Monster Truck"] = {0.0015, 1, 5},
    ["Personal Cannon Launcher"] = {0.0015, 1, 5},
    ["Classic American Car"] = {0.0015, 1, 5},
    ["Latte Motorcycle"] = {0.0015, 1, 5},
    ["Dolphin Cruiser"] = {0.0015, 1, 5},
    ["Powerbike"] = {0.0015, 1, 5},
    ["RGB UFO"] = {0.0015, 1, 5},
    ["Bone Wings"] = {0.0015, 1, 3},
    ["Waffle Wagon"] = {0.0015, 1, 5},
    ["Mystic Wing Crown"] = {0.0015, 1, 3},
    ["Beachgoer"] = {0.0015, 1, 5},
    ["Ghoul Mobile"] = {0.0015, 1, 5},
    ["Pink Hightops"] = {0.0015, 1, 3},
    ["Flying Fairy"] = {0.0015, 1, 3},
    ["Festive Antlers"] = {0.0015, 1, 3},
    ["Cheesecake Hat"] = {0.0015, 1, 3},
    ["Growing Flower Hat"] = {0.0015, 1, 3},
    ["Candy Corn Hat"] = {0.0015, 1, 3},
    ["Crescent Moon Head Ornament"] = {0.0015, 1, 3},
    ["Leaf Hat"] = {0.0015, 1, 3},
    ["Halloween Green Zombie Bat Wings"] = {0.0015, 1, 3},
    ["Love Letter"] = {0.0015, 1, 3},
    ["Culinary Wizard Hat"] = {0.0015, 1, 3},
    ["Gold Tiara"] = {0.00125, 1, 3},
    ["Party House"] = {0.00125, 1, 10},
    ["Briefcase Ingredient"] = {0.00125, 1, 7},
    ["Cymbal Ingredient"] = {0.00125, 1, 7},
    ["Tundra Exploration Machine"] = {0.001, 1, 5},
    ["Mini Pig Sticker"] = {0.001, 1, 9},
    ["Peppermint Penguin Sticker"] = {0.001, 1, 9},
    ["Kaijunior Box"] = {0.001, 1, 8},
    ["Ice Tray"] = {0.001, 1, 8},
    ["2D Box"] = {0.001, 1, 8},
    ["Kelp Raider Box"] = {0.001, 1, 8},
    ["Tractor"] = {0.001, 1, 5},
    ["Harvest Truck"] = {0.001, 1, 5},
    ["Trireme"] = {0.001, 1, 5},
    ["High Heel Stroller"] = {0.001, 1, 4},
    ["Halloween Black Witch Hat Stroller"] = {0.001, 1, 4},
    ["Droplet Stroller"] = {0.001, 1, 4},
    ["Witch's Caravan"] = {0.001, 1, 5},
    ["Soccer Car"] = {0.001, 1, 5},
    ["Rift Rider"] = {0.001, 1, 5},
    ["Landsailer"] = {0.001, 1, 5},
    ["Galleon"] = {0.001, 1, 5},
    ["Corsair Cruiser"] = {0.001, 1, 5},
    ["Candy Camper"] = {0.001, 1, 5},
    ["Lunar Stroller"] = {0.001, 1, 4},
    ["Claw Machine Stroller"] = {0.001, 1, 4},
    ["Founder's Crown"] = {0.001, 1, 3},
    ["Snow Cloud Wings"] = {0.001, 1, 3},
    ["Marshmallow Friend"] = {0.001, 1, 3},
    ["Lunar New Year Rickshaw Stroller"] = {0.001, 1, 4},
    ["Swan Stroller"] = {0.001, 1, 4},
    ["Drone Stroller"] = {0.001, 1, 4},
    ["Tractor Stroller"] = {0.001, 1, 4},
    ["Tulip Stroller"] = {0.001, 1, 4},
    ["Scarebear Stroller"] = {0.001, 1, 4},
    ["Orange Butterfly Sticker"] = {0.001, 1, 9},
    ["Donut Rattle"] = {0.001, 1, 7},
    ["Elf Rattle"] = {0.001, 1, 7},
    ["Ice Cream Plush"] = {0.001, 1, 7},
    ["Gift Throw Toy"] = {0.001, 1, 7},
    ["Strawberry Toast Flying Disc"] = {0.001, 1, 7},
    ["Santa Rattle"] = {0.001, 1, 7},
    ["Purple & Green Beads"] = {0.001, 1, 3},
    ["Aestus Mane"] = {0.001, 1, 3},
    ["Sock Chew Toy"] = {0.001, 1, 7},
    ["Duck Balloon"] = {0.001, 1, 7},
    ["Kangaroo Pogo"] = {0.001, 1, 7},
    ["Solar System Necklace"] = {0.001, 1, 3},
    ["Red & Yellow Beads"] = {0.001, 1, 3},
    ["Dog Backpack"] = {0.001, 1, 3},
    ["Rainbow Dragon Hat"] = {0.001, 1, 3},
    ["Silly Duck Hat"] = {0.001, 1, 3},
    ["Strawberry Shortcake"] = {0.001, 1, 6},
    ["Winter Deer Bait"] = {0.001, 1, 6},
    ["Sleigh Bells Rattle"] = {0.001, 1, 7},
    ["Subzero Popsicle Bait"] = {0.001, 1, 6},
    ["Shiver Cone Bait"] = {0.001, 1, 6},
    ["Snapdragon Flower"] = {0.001, 1, 6},
    ["Gold Circle Glasses"] = {0.001, 2, 3},
    ["Galactic Hoverboard"] = {0.001, 1, 5},
    ["Soulfire Animated Sticker"] = {0.001, 1, 9},
    ["Knitted Pumpkin Hat"] = {0.001, 1, 3},
    ["Black Hightops"] = {0.001, 1, 3},
    ["Ghost Hat"] = {0.001, 1, 3},
    ["Mountain House"] = {0.001, 1, 10},
    ["Panda Sticker"] = {0.001, 1, 9},
    ["Igloo Home"] = {0.001, 1, 10},
    ["Dragon's Castle"] = {0.001, 1, 10},
    ["Scary House"] = {0.001, 1, 10},
    ["Human Feet Shoes"] = {0.001, 1, 3},
    ["Festive Stocking Shoes"] = {0.001, 1, 3},
    ["Swamp Mist Wings"] = {0.001, 1, 3},
    ["Cat Backpack"] = {0.001, 1, 3},
    ["Security Spotlight"] = {0.001, 1, 3},
    ["Festive Scarf"] = {0.001, 1, 3},
    ["Rotating Periscope"] = {0.001, 1, 3},
    ["Royal Palace"] = {0.0009, 1, 10},
    ["Winter 2024 Sticker Pack"] = {0.0009, 1, 9},
    ["Halloween 2024 Sticker Pack"] = {0.0009, 1, 9},
    ["Camping Van"] = {0.0009, 1, 5},
    ["Stocked Santa Sleigh"] = {0.0009, 1, 5},
    ["Sasquatch Sticker"] = {0.0008, 1, 9},
    ["Pet Rock Sticker"] = {0.0008, 1, 9},
    ["Poodle Sticker"] = {0.0008, 1, 9},
    ["Pig Sticker"] = {0.0008, 1, 9},
    ["Beehive House"] = {0.0008, 1, 10},
    ["Christmas Pudding House"] = {0.0008, 1, 10},
    ["Spider Gift"] = {0.0008, 1, 8},
    ["Koala Sticker"] = {0.0008, 1, 9},
    ["Snowball Launcher"] = {0.0008, 1, 7},
    ["Camping Tent"] = {0.0008, 1, 7},
    ["Futuristic House"] = {0.0008, 1, 10},
    ["Medieval Wagon"] = {0.0008, 1, 5},
    ["Fox Sticker"] = {0.0008, 1, 9},
    ["Rocket Ship Stroller"] = {0.0008, 1, 4},
    ["Car Stroller"] = {0.0008, 1, 4},
    ["Ginger Cat Sticker"] = {0.0008, 1, 9},
    ["Woodland Cradle Stroller"] = {0.00075, 1, 4},
    ["Pea Pod Stroller"] = {0.00075, 1, 4},
    ["S'mores Stroller"] = {0.00075, 1, 4},
    ["UFO Stroller"] = {0.00075, 1, 4},
    ["Toilet Stroller"] = {0.00075, 1, 4},
    ["Catapult Stroller"] = {0.00075, 1, 4},
    ["Hover Stroller"] = {0.00075, 1, 4},
    ["Sandbox Island"] = {0.0007, 1, 10},
    ["Candyfloss Chick Sticker"] = {0.0007, 1, 9},
    ["Jimothy"] = {0.0007, 1, 9},
    ["Safari Home"] = {0.0007, 1, 10},
    ["Moon Egg"] = {0.00065, 1, 2},
    ["Garden Egg"] = {0.00065, 1, 2},
    ["Walrus Sticker"] = {0.0006, 1, 9},
    ["Racetrack House"] = {0.0006, 1, 10},
    ["Shiba Inu Sticker"] = {0.0006, 1, 9},
    ["Frog Sticker"] = {0.0006, 1, 9},
    ["Crooked House"] = {0.0006, 1, 10},
    ["Lunar House"] = {0.0006, 1, 10},
    ["Otter Sticker"] = {0.0006, 1, 9},
    ["Rat Sticker"] = {0.0006, 1, 9},
    ["Flower Cart Stroller"] = {0.0006, 1, 4},
    ["Ruddy Duck Waddler"] = {0.0006, 1, 5},
    ["Haunted House"] = {0.0006, 1, 10},
    ["Paint Sealer"] = {0.00055, 2, 7},
    ["Snowman Stroller"] = {0.0005, 1, 4},
    ["Glyptodon Van"] = {0.0005, 1, 5},
    ["Pirate Captain Stroller"] = {0.0005, 1, 4},
    ["Santa's Helper Stroller"] = {0.0005, 1, 4},
    ["Apple Barrel Stroller"] = {0.0005, 1, 4},
    ["Aestus Kite"] = {0.0005, 1, 7},
    ["Teddy Bear"] = {0.0005, 1, 7},
    ["S'mores Pogo Stick"] = {0.0005, 1, 7},
    ["Froggy Stroller"] = {0.0005, 1, 4},
    ["Double Stroller"] = {0.0005, 1, 4},
    ["Crystal Ball Stroller"] = {0.0005, 1, 4},
    ["Egyptian Chariot Stroller"] = {0.0005, 1, 4},
    ["Box of Jokes"] = {0.0005, 1, 8},
    ["Snow Globe Stroller"] = {0.0005, 1, 4},
    ["Fall Wheelbarrow Stroller"] = {0.0005, 1, 4},
    ["Bunch Of Balloons"] = {0.0005, 1, 3},
    ["Snow Mobile Stroller"] = {0.0005, 1, 4},
    ["State Fair Sticker Pack"] = {0.0005, 1, 9},
    ["Takoyaki Stroller"] = {0.0005, 1, 4},
    ["Carrot Friend Plushie"] = {0.0005, 1, 7},
    ["Stocking Stroller"] = {0.0005, 1, 4},
    ["Candicorn Sticker"] = {0.0004, 1, 9},
    ["Majestic Pony Sticker"] = {0.0004, 1, 9},
    ["Blue Betta Fish Sticker"] = {0.0004, 1, 9},
    ["Coconut Friend Sticker"] = {0.0004, 1, 9},
    ["Leviathan Sticker"] = {0.0004, 1, 9},
    ["Nautilus Sticker"] = {0.0004, 1, 9},
    ["Scorching Kaijunior Sticker"] = {0.0004, 1, 9},
    ["Crate Stroller"] = {0.0004, 1, 4},
    ["Crystal Egg"] = {0.0004, 2, 2},
    ["Kappakid Sticker"] = {0.0004, 1, 9},
    ["Admin Abuse Egg"] = {0.0004, 2, 2},
    ["Pelican Stroller"] = {0.0004, 1, 4},
    ["Priceless Shrimp Sticker"] = {0.0004, 1, 9},
    ["Scarebear Sticker"] = {0.0004, 1, 9},
    ["Lava Dragon Sticker"] = {0.0004, 1, 9},
    ["Phantom Dragon Sticker"] = {0.0004, 1, 9},
    ["Jousting Horse Sticker"] = {0.0004, 1, 9},
    ["Aurora Fox Sticker"] = {0.0004, 1, 9},
    ["Evil Unicorn Sticker"] = {0.0004, 1, 9},
    ["Grim Dragon Sticker"] = {0.0004, 1, 9},
    ["Skele-Rex Sticker"] = {0.0004, 1, 9},
    ["Cocoadile Sticker"] = {0.0004, 1, 9},
    ["Octopus Sticker"] = {0.0004, 1, 9},
    ["Shark Sticker"] = {0.0004, 1, 9},
    ["Kraken Sticker"] = {0.0004, 1, 9},
    ["Flaming Fox Sticker"] = {0.0004, 1, 9},
    ["Toasty Red Panda Sticker"] = {0.0004, 1, 9},
    ["Volcanic Rhino Sticker"] = {0.0004, 1, 9},
    ["T-Rex Sticker"] = {0.0004, 1, 9},
    ["Santa Pet Rock Sticker"] = {0.0004, 1, 9},
    ["Christmas Dog Sticker"] = {0.0004, 1, 9},
    ["Sakura Spirit Sticker"] = {0.0004, 1, 9},
    ["Sledding Penguin Sticker"] = {0.0004, 1, 9},
    ["Pirate Dog Sticker"] = {0.0004, 1, 9},
    ["Kelp Captain Sticker"] = {0.0004, 1, 9},
    ["Arctic Dusk Dragon Sticker"] = {0.0004, 1, 9},
    ["Naughty Mistletroll Sticker"] = {0.0004, 1, 9},
    ["Dimorphodon Sticker"] = {0.0004, 1, 9},
    ["Dodo Sticker"] = {0.0004, 1, 9},
    ["Sunrise Duckling Sticker"] = {0.0004, 1, 9},
    ["Fire Dimension Sticker Pack"] = {0.00035, 1, 9},
    ["Aztec Egg"] = {0.00035, 1, 2},
    ["Fossil Sticker Pack"] = {0.0003, 1, 9},
    ["Royal Egg"] = {0.0003, 1, 2},
    ["Admin Abuse Box"] = {0.0003, 1, 8},
    ["Aberdeen Angus Box"] = {0.00025, 1, 8},
    ["Cherry Blossom Tree Sticker"] = {0.00025, 1, 9},
    ["Cherry Blossom Flower Sticker"] = {0.00025, 1, 9},
    ["Fire Horse Apple"] = {0.0002, 1, 6},
    ["Fairytale Egg"] = {0.0002, 1, 2},
    ["Poltergeist Box"] = {0.0002, 1, 8},
    ["Yellow Designer Backpack"] = {0.0002, 1, 3},
    ["Retired Egg"] = {0.0002, 1, 2},
    ["Endangered Egg"] = {0.0002, 1, 2},
    ["Rubber Ducky Box"] = {0.00015, 1, 8},
    ["Pet Egg"] = {0.00015, 1, 2},
    ["Throwback Egg"] = {0.00013, 1, 2},
    ["Basic Egg"] = {0.00012, 1, 2},
    ["Choccybunny Box"] = {0.0001, 1, 8},
    ["Oakee Box"] = {0.0001, 1, 8},
    ["Cracked Egg"] = {0.0001, 1, 2},
    ["Wallet Chew Toy"] = {0.0001, 1, 7},
}
-- <<< VALUES_END

local CATEGORY = { [1] = "pet", [2] = "egg", [3] = "petwear", [4] = "stroller",
                   [5] = "vehicle", [6] = "food", [7] = "toy", [8] = "gift",
                   [9] = "sticker", [10] = "house" }

local VALUES = {}         -- normalized name -> { name, value, demand, cat }
local VALUES_UPDATED = "bundled"

local function htmlDecode(s)
    if not s then return "" end
    s = s:gsub("&#x27;", "'"):gsub("&#39;", "'"):gsub("&quot;", '"')
    s = s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
    s = s:gsub("&#(%d+);", function(n)
        local code = tonumber(n)
        if code and code < 256 then return string.char(code) end
        return ""
    end)
    return s
end

local function normalize(s)
    s = htmlDecode(tostring(s or ""))
    s = s:lower()
    s = s:gsub("&", "and")
    s = s:gsub("[^%w]", "")
    return s
end

local function indexValues(flat)
    VALUES = {}
    for name, data in pairs(flat) do
        local value, demand, cat = data[1], data[2], data[3]
        local key = normalize(name)
        if key ~= "" and VALUES[key] == nil then
            VALUES[key] = {
                name = name,
                value = tonumber(value) or 0,
                demand = tonumber(demand) or 0,
                cat = CATEGORY[tonumber(cat) or 1] or "pet",
            }
        end
    end
end

local function countValues()
    local n = 0
    for _ in pairs(VALUES) do n += 1 end
    return n
end

-- Runtime scraper: same HTML layout as tools/update-values.ps1.
local function parseValuesHtml(html, catCode)
    local out = {}
    local pos = 1
    local marker = 'aria-label="View '
    while true do
        local s = html:find(marker, pos, true)
        if not s then break end
        local nextS = html:find(marker, s + #marker, true)
        local block = html:sub(s, (nextS or (#html + 1)) - 1)
        pos = nextS or (#html + 1)

        local title = block:match('title="([^"]+)">')
        local value = block:match("Value</span><span[^>]*>([0-9%.]+)</span>")
        if title and value then
            local demand = 0
            local stars = block:match("Demand</span><span[^>]*><span[^>]*>([\226\152\133\226\152\134]+)")
            if stars then demand = select(2, stars:gsub("\226\152\133", "")) end
            out[htmlDecode(title)] = { tonumber(value) or 0, demand, catCode }
        end
    end
    return out
end

local VALUE_PAGES = {
    { page = "pets",      cat = 1 },
    { page = "eggs",      cat = 2 },
    { page = "petwear",   cat = 3 },
    { page = "strollers", cat = 4 },
    { page = "vehicles",  cat = 5 },
    { page = "food",      cat = 6 },
    { page = "toys",      cat = 7 },
    { page = "gifts",     cat = 8 },
    { page = "stickers",  cat = 9 },
    { page = "houses",    cat = 10 },
}

local function updateValuesFromWeb(silent)
    if not silent then log("updating values from amvgg.com ...") end
    local flat = {}
    local total, pages = 0, 0

    for _, spec in ipairs(VALUE_PAGES) do
        local body, status = httpGet("https://amvgg.com/values/" .. spec.page)
        if body and #body > 1000 then
            local parsed = parseValuesHtml(body, spec.cat)
            local n = 0
            for name, data in pairs(parsed) do
                if flat[name] == nil then
                    flat[name] = data
                    n += 1
                end
            end
            total += n
            pages += 1
        else
            log("value page '%s' failed (%s)", spec.page, tostring(status))
        end
        task.wait(0.15)
    end

    if total < 100 then
        log("value update aborted: only %d items", total)
        return false
    end

    indexValues(flat)
    VALUES_UPDATED = os.date("%Y-%m-%d %H:%M")

    if writefile then
        local parts = { "-- cached amvgg values, " .. VALUES_UPDATED, "return {" }
        for _, e in pairs(VALUES) do
            local catId = 1
            for id, cat in pairs(CATEGORY) do
                if cat == e.cat then catId = id; break end
            end
            parts[#parts + 1] = string.format('  ["%s"] = {%s, %d, %d},',
                e.name:gsub("\\", "\\\\"):gsub('"', '\\"'),
                tostring(e.value), e.demand, catId)
        end
        parts[#parts + 1] = "}"
        local ok = pcall(writefile, BOT.ValuesFile, table.concat(parts, "\n"))
        if ok then log("cached values written to %s", BOT.ValuesFile) end
    end

    log("values updated: %d items from %d/%d pages", countValues(), pages, #VALUE_PAGES)
    if not silent then notify("Values updated", string.format("%d items", countValues())) end
    return true
end

local function loadValues()
    -- 1. cached file (written by a previous web update) wins
    if readfile and isfile then
        local ok, exists = pcall(isfile, BOT.ValuesFile)
        if ok and exists then
            local ok2, body = pcall(readfile, BOT.ValuesFile)
            if ok2 and body then
                local chunk = loadstring(body)
                if chunk then
                    local ok3, flat = pcall(chunk)
                    if ok3 and type(flat) == "table" and next(flat) then
                        indexValues(flat)
                        VALUES_UPDATED = "cache"
                        log("loaded %d cached values", countValues())
                        return
                    end
                end
            end
        end
    end
    -- 2. bundled table
    indexValues(EMBEDDED_VALUES)
    log("loaded %d bundled values", countValues())
end

--============================================================== 5. name utils
local AGE_WORDS = { "newborn", "junior", "preteen", "pre teen", "teen",
                    "postteen", "post teen", "fullgrown", "full grown" }

local function stripAges(s)
    local lower = s:lower()
    for _, w in ipairs(AGE_WORDS) do
        local pat = w:gsub("(%a)", function(c) return c end):gsub(" ", "%%s+")
        lower = lower:gsub(pat, " ")
    end
    return lower
end

-- Returns cleanName, inlineFlags
local function cleanItemName(text)
    local s = tostring(text or "")
    if s == "" then return "", nil end
    s = s:gsub("<[^>]->", "")
    s = s:gsub("[\r\n\t]+", " ")
    s = s:gsub("%s+", " ")
    s = s:match("^%s*(.-)%s*$") or s

    local flags = { fly = false, ride = false, neon = false, mega = false }
    local lower = s:lower()

    if lower:find("mega%s+neon") then
        flags.mega, flags.neon, flags.fly, flags.ride = true, true, true, true
        s = s:gsub("[Mm][Ee][Gg][Aa]%s+[Nn][Ee][Oo][Nn]%s*", "")
    elseif lower:find("^neon%s") then
        flags.neon, flags.fly, flags.ride = true, true, true
        s = s:gsub("^[Nn][Ee][Oo][Nn]%s*", "")
    elseif lower:find("^mega%s") then
        flags.mega, flags.neon, flags.fly, flags.ride = true, true, true, true
        s = s:gsub("^[Mm][Ee][Gg][Aa]%s*", "")
    end

    s = stripAges(s)
    s = s:gsub("%s+", " ")
    s = s:match("^%s*(.-)%s*$") or s
    return s, flags
end

local ALIASES = {}   -- normalized ingame -> normalized amvgg

local function rebuildAliases()
    ALIASES = {}
    for line in (S.AliasText or ""):gmatch("[^\r\n]+") do
        local a, b = line:match("^(.-)%s*=%s*(.+)$")
        if a and b then
            ALIASES[normalize(a)] = normalize(b)
        end
    end
end

local function lookupValue(name)
    local key = normalize(name)
    if key == "" then return nil end
    local alias = ALIASES[key]
    if alias then
        local e = VALUES[alias]
        if e then return e end
    end
    return VALUES[key]
end

local function parseList(text)
    local out = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local s = line:match("^%s*(.-)%s*$")
        if s ~= "" and s:sub(1, 1) ~= "#" then
            out[normalize(s)] = s
        end
    end
    return out
end

--============================================================== 6. gui utils
local function getPlayerGui()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then
        pg = LocalPlayer:WaitForChild("PlayerGui", 10)
    end
    return pg
end

local function isVisible(obj)
    local o = obj
    local guard = 0
    while o and o ~= game and guard < 40 do
        if o:IsA("GuiObject") and o.Visible == false then return false end
        o = o.Parent
        guard += 1
    end
    return true
end

local function textMatches(text, words)
    local t = tostring(text or ""):lower()
    if t == "" then return false end
    for _, w in ipairs(words) do
        if t:find(w, 1, true) then return true end
    end
    return false
end

local ACCEPT_WORDS  = { "accept", "confirm", "ready", "yes" }
local DECLINE_WORDS = { "decline", "cancel", "refuse", "no thanks" }

-- ImageButton has no Text property at all and indexing it raises an error, while
-- the game uses ImageButtons for most of the HUD. Every read goes through these.
local function guiText(obj)
    if not obj then return "" end
    local ok, t = pcall(function() return obj.Text end)
    if ok and type(t) == "string" then return t end
    return ""
end

local function guiLabel(obj)
    local text = guiText(obj)
    if text ~= "" then return text end
    local ok, n = pcall(function() return obj.Name end)
    if ok and n ~= nil then return tostring(n) end
    return "?"
end

-- buttons in game UIs are not always labelled with Text, so fall back to Name
local function buttonMatches(btn, words)
    return textMatches(guiText(btn), words) or textMatches(btn.Name, words)
end

local lastClickAt = {}
local function clickButton(btn)
    if not btn then return false end
    local now = os.clock()
    if lastClickAt[btn] and (now - lastClickAt[btn]) < 0.35 then return false end
    lastClickAt[btn] = now

    local fired = false
    if getconnections then
        local ok, conns = pcall(getconnections, btn.MouseButton1Click)
        if ok and type(conns) == "table" then
            for _, c in ipairs(conns) do
                if c.Enabled ~= false and type(c.Function) == "function" then
                    pcall(c.Function)
                    fired = true
                end
            end
        end
    end

    if not fired then
        local signal = btn.MouseButton1Click
        if firesignal then
            pcall(firesignal, signal)
        elseif type(signal) == "userdata" or type(signal) == "table" then
            pcall(function() signal:Fire() end)
        end
    end

    -- some UIs listen on down/up instead of click
    if not fired then
        pcall(function() btn.MouseButton1Down:Fire() end)
        task.wait(0.03)
        pcall(function() btn.MouseButton1Up:Fire() end)
    end

    return true
end

local function collectButtons(root)
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiButton") and isVisible(d) then
            out[#out + 1] = d
        end
    end
    return out
end

local function ancestorsUntil(obj, stop, maxDepth)
    local list = {}
    local p = obj
    local depth = 0
    while p and p ~= stop and depth < (maxDepth or 8) do
        list[#list + 1] = p
        p = p.Parent
        depth += 1
    end
    return list
end

-- Find the smallest visible container with an accept button and a decline button.
local function findTradeWindow()
    local pg = getPlayerGui()
    if not pg then return nil end

    local buttons = collectButtons(pg)
    if #buttons == 0 then return nil end

    local marks = {}
    local function mark(btn, field)
        for _, anc in ipairs(ancestorsUntil(btn, pg, 10)) do
            if anc:IsA("GuiObject") then
                local m = marks[anc]
                if not m then m = {}; marks[anc] = m end
                m[field] = true
            end
        end
    end

    for _, b in ipairs(buttons) do
        if buttonMatches(b, ACCEPT_WORDS) then mark(b, "accept") end
        if buttonMatches(b, DECLINE_WORDS) then mark(b, "decline") end
    end

    local best, bestArea = nil, 0
    for obj, m in pairs(marks) do
        if m.accept and m.decline then
            local size = obj.AbsoluteSize
            local area = size.X * size.Y
            if area > bestArea then
                best, bestArea = obj, area
            end
        end
    end
    return best, bestArea
end

local function findButtonIn(win, words, avoidWords)
    if not win then return nil end
    for _, d in ipairs(win:GetDescendants()) do
        if d:IsA("GuiButton") and isVisible(d) then
            if buttonMatches(d, words) and not (avoidWords and buttonMatches(d, avoidWords)) then
                return d
            end
        end
    end
    return nil
end

-- True when the label belongs to the inventory strip rather than the offer panels.
-- The inventory is either below the offer area or inside a scroller that starts low.
local function isInventoryLabel(obj, win, thresholdY, offerBottomY)
    if obj.AbsolutePosition.Y > offerBottomY then return true end
    local p = obj.Parent
    local guard = 0
    while p and p ~= win and guard < 20 do
        if p:IsA("ScrollingFrame") then
            return p.AbsolutePosition.Y > thresholdY
        end
        p = p.Parent
        guard += 1
    end
    return false
end

-- A trade slot is a small square-ish container that holds the item picture.
local function slotLooksLikeSlot(obj)
    if not obj or not obj:IsA("GuiObject") then return false end
    local sz = obj.AbsoluteSize
    if sz.X < 26 or sz.Y < 26 or sz.X > 280 or sz.Y > 280 then return false end
    for _, c in ipairs(obj:GetDescendants()) do
        if c:IsA("ViewportFrame") or c:IsA("ImageLabel") or c:IsA("ImageButton") then
            return true
        end
    end
    return false
end

local function findSlot(obj, root)
    local p = obj.Parent
    local depth = 0
    while p and p ~= root and depth < 6 do
        if slotLooksLikeSlot(p) or p:IsA("GuiButton") then return p end
        p = p.Parent
        depth += 1
    end
    return nil
end

local function hasPricedSlotItem(win)
    for _, d in ipairs(win:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" and isVisible(d) then
            local name = cleanItemName(d.Text)
            if name ~= "" and lookupValue(name) and findSlot(d, win) then
                return true
            end
        end
    end
    return false
end

local function classifyWindow(win)
    if not win then return "none" end
    local size = win.AbsoluteSize
    local area = size.X * size.Y

    -- the Trading Hub phone also has accept/decline buttons; never treat it as a trade
    local hasHistory, hasListing = false, false
    for _, d in ipairs(win:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= "" then
            local t = d.Text:lower()
            if t:find("post a listing", 1, true) or t:find("view my listings", 1, true)
                or t:find("trading hub", 1, true) or t:find("post listing", 1, true) then
                return "phone"
            end
            if t:find("history", 1, true) then hasHistory = true
            elseif t:find("listing", 1, true) then hasListing = true end
            if hasHistory and hasListing then return "phone" end
        end
    end

    for _, d in ipairs(win:GetDescendants()) do
        if d:IsA("ScrollingFrame") and isVisible(d) then
            return "trade"
        end
    end
    if area >= 120000 then return "trade" end
    -- a small popup that already shows real items is a trade, not a request
    if hasPricedSlotItem(win) then return "trade" end
    return "request"
end

local function readFlags(slot)
    local f = { fly = false, ride = false, neon = false, mega = false }
    if not slot or not slot.Parent then return f end

    local limit = 0
    for _, d in ipairs(slot:GetDescendants()) do
        limit += 1
        if limit > 60 then break end
        if d:IsA("ImageLabel") or d:IsA("ImageButton") then
            local hay = ((d.Image or "") .. " " .. d.Name):lower()
            if hay:find("fly", 1, true) then f.fly = true end
            if hay:find("ride", 1, true) then f.ride = true end
            if hay:find("neon", 1, true) then f.neon = true end
            if hay:find("mega", 1, true) then f.mega = true end
        elseif d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = (d.Text or ""):upper():gsub("[^%u]", "")
            if t == "MFR" then f.mega, f.neon, f.fly, f.ride = true, true, true, true
            elseif t == "NFR" then f.neon, f.fly, f.ride = true, true, true
            elseif t == "FR" then f.fly, f.ride = true, true
            elseif t == "M" then f.mega = true
            elseif t == "N" then f.neon = true
            elseif t == "F" then f.fly = true
            elseif t == "R" then f.ride = true end
        end
    end
    if f.mega then f.neon, f.fly, f.ride = true, true, true end
    if f.neon then f.fly, f.ride = true, true end
    return f
end

--============================================================== 7. valuation
local function itemValue(entry, flags)
    if not entry then return nil end
    local v = entry.value
    if flags then
        if flags.fly then v *= S.FlyMult end
        if flags.ride then v *= S.RideMult end
        if flags.neon then v *= S.NeonMult end
        if flags.mega then v *= S.MegaMult end
    end
    return v
end

local function flagString(flags)
    if not flags then return "" end
    if flags.mega then return "MFR" end
    if flags.neon then return "NFR" end
    if flags.fly and flags.ride then return "FR" end
    if flags.fly then return "F" end
    if flags.ride then return "R" end
    return ""
end

-- Reads offer panels. Returns table { ours = {...}, theirs = {...}, unknown = {...} }
local function readOffers(win)
    local result = { ours = {}, theirs = {}, unknown = {}, ourValue = 0, theirValue = 0 }
    if not win then return result end

    local pos = win.AbsolutePosition
    local size = win.AbsoluteSize
    local centerX = pos.X + size.X / 2
    local topY = pos.Y
    local offerBottom = pos.Y + size.Y * 0.72
    local inventoryTop = pos.Y + size.Y * 0.55

    local leftIsOurs = S.OurSideIsLeft ~= false
    local seen = {}

    for _, d in ipairs(win:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" and isVisible(d) then
            local labelPos = d.AbsolutePosition
            local insideOfferArea = labelPos.Y >= (topY - 8) and labelPos.Y <= offerBottom
            if insideOfferArea and not isInventoryLabel(d, win, inventoryTop, offerBottom) then
                local slot = findSlot(d, win)
                local dedupeKey = slot or d
                if not seen[dedupeKey] then
                    local name, inlineFlags = cleanItemName(d.Text)
                    local entry = lookupValue(name)
                    if entry then
                        seen[dedupeKey] = true
                        local flags = readFlags(slot or d)
                        if inlineFlags then
                            for k, v in pairs(inlineFlags) do
                                if v then flags[k] = true end
                            end
                        end

                        local item = {
                            name = entry.name,
                            entry = entry,
                            flags = flags,
                            value = itemValue(entry, flags),
                            slot = slot or d,
                        }

                        local isLeft = labelPos.X < centerX
                        local mine = (isLeft == leftIsOurs)
                        if mine then
                            result.ours[#result.ours + 1] = item
                            result.ourValue += item.value
                        else
                            result.theirs[#result.theirs + 1] = item
                            result.theirValue += item.value
                        end
                    elseif slot and #name >= 3 and #name <= 40 then
                        -- only slot-like text can be an unpriced item; this keeps
                        -- player names and UI labels out of the "unknown" list
                        if not textMatches(name, {
                            "value", "demand", "trade", "offer", "inventory", "search",
                            "accept", "decline", "cancel", "confirm", "pets", "wear",
                            "stroller", "vehicle", "food", "toy", "egg", "gift", "friend",
                        }) then
                            seen[dedupeKey] = true
                            result.unknown[#result.unknown + 1] = name
                        end
                    end
                end
            end
        end
    end

    return result
end

-- Inventory slots available to give away (inside scrolling frames, or whatever
-- sits below the offer panels when the inventory is not a ScrollingFrame).
local function scanInventory(win)
    local items = {}
    if not win then return items end

    local keep = parseList(S.KeepListText)
    local pool = parseList(S.TradePoolText)
    local hasPool = next(pool) ~= nil
    local seen = {}

    local winPos = win.AbsolutePosition
    local winSize = win.AbsoluteSize
    local offerBottomY = winPos.Y + winSize.Y * 0.72
    local inventoryTop = winPos.Y + winSize.Y * 0.55

    for _, d in ipairs(win:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" and isVisible(d) then
            local isInventory = isInventoryLabel(d, win, inventoryTop, offerBottomY)
            if isInventory then
                local name, inlineFlags = cleanItemName(d.Text)
                local entry = lookupValue(name)
                if entry then
                    local key = normalize(entry.name)
                    local allowed = not keep[key] and (not hasPool or pool[key] ~= nil)
                    if allowed then
                        local slot = findSlot(d, win) or d
                        if not seen[slot] then
                            seen[slot] = true
                            local flags = readFlags(slot)
                            if inlineFlags then
                                for k, v in pairs(inlineFlags) do
                                    if v then flags[k] = true end
                                end
                            end
                            items[#items + 1] = {
                                name = entry.name,
                                key = key,
                                entry = entry,
                                flags = flags,
                                value = itemValue(entry, flags),
                                slot = slot,
                            }
                        end
                    end
                end
            end
        end
    end

    -- safety: do not hand away the only copy of a pet
    if S.NeverGiveLastPet then
        local counts = {}
        for _, it in ipairs(items) do
            counts[it.key] = (counts[it.key] or 0) + 1
        end
        local filtered = {}
        for _, it in ipairs(items) do
            if (counts[it.key] or 0) > 1 then
                filtered[#filtered + 1] = it
            end
        end
        items = filtered
    end

    -- drop slots the game ignored before (double clicks, locked items, ...)
    if E.failed and next(E.failed) then
        local usable = {}
        for _, it in ipairs(items) do
            if not E.failed[it.key] then usable[#usable + 1] = it end
        end
        items = usable
    end

    return items
end

-- Scrolls the inventory search forward so virtualised grids reveal more pets.
local function sweepInventory(win)
    if not win then return false end
    for _, d in ipairs(win:GetDescendants()) do
        if d:IsA("ScrollingFrame") and isVisible(d) then
            local ok = pcall(function()
                local window = d.AbsoluteWindowSize
                local canvas = d.AbsoluteCanvasSize
                if window.Y <= 0 then window = d.AbsoluteSize end
                local maxY = math.max(0, canvas.Y - window.Y)
                local nextY = d.CanvasPosition.Y + window.Y * 0.85
                if nextY > maxY + 1 then nextY = 0 end
                d.CanvasPosition = Vector2.new(d.CanvasPosition.X, nextY)
            end)
            if ok then return true end
        end
    end
    return false
end

--============================================================== 7b. kiria persona
-- Optional module (Kiria.lua from the same author) that turns trade events into a
-- few friendly lines + a gif and keeps its own memory in TradeBot/Kiria_memory.json.
-- If it cannot be loaded, the bot simply posts plain cards.
local Kiria = nil
local kiriaRetryAt = 0
local kiriaWarnAt = 0

local function loadKiria()
    if Kiria then return Kiria end
    if not S.KiriaEnabled then return nil end
    if os.clock() < kiriaRetryAt then return nil end

    local url = (S.KiriaUrl or ""):gsub("%s", "")
    if url == "" then return nil end

    local body
    local okGet, res = pcall(function() return game:HttpGet(url, true) end)
    if okGet and type(res) == "string" and #res > 200 then
        body = res
    else
        local okHttp, text = httpGet(url)
        if okHttp and type(text) == "string" and #text > 200 then body = text end
    end
    if not body then
        kiriaRetryAt = os.clock() + 180
        log("kiria: download failed (%s)", tostring(res))
        return nil
    end

    local compile = G("loadstring")
    if type(compile) ~= "function" then compile = loadstring end
    if type(compile) ~= "function" then
        kiriaRetryAt = os.clock() + 600
        log("kiria: executor has no loadstring")
        return nil
    end

    local chunk, compileErr = compile(body)
    if not chunk then
        kiriaRetryAt = os.clock() + 600
        log("kiria: compile error: %s", tostring(compileErr))
        return nil
    end

    local okRun, module = pcall(chunk)
    if not okRun or type(module) ~= "table" or type(module.react) ~= "function" then
        kiriaRetryAt = os.clock() + 600
        log("kiria: bad module: %s", tostring(module))
        return nil
    end

    Kiria = module
    log("kiria v%s loaded | %s", tostring(module.Version), tostring(module.Title))
    return Kiria
end

-- returns line, gif, mood, meta (all nil when the module is off or failed)
local function kiriaReact(event, ctx)
    if not S.KiriaEnabled then return nil end
    local K = loadKiria()
    if not K then return nil end
    local ok, line, gif, mood, meta = pcall(K.react, event, ctx or {})
    if not ok then
        log("kiria react error: %s", tostring(line))
        return nil
    end
    return line, gif, mood, meta
end

--============================================================== 8. webhook
local WebhookQueue = {}
local function enqueueWebhook(payload)
    WebhookQueue[#WebhookQueue + 1] = payload
    E.lastPostAt = os.time()
end

local function postWebhook(payload)
    local url = (S.WebhookUrl or ""):gsub("%s", "")
    if url == "" or url:sub(1, 8) ~= "https://" then
        return false, "webhook url is empty"
    end
    local ok, body = pcall(function() return HttpService:JSONEncode(payload) end)
    if not ok then return false, "json encode failed" end

    local res, status = httpRequest({
        Url = url,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "AdoptMeTradeBot/" .. BOT.Version,
        },
        Body = body,
    })

    if type(status) == "number" then
        if status >= 200 and status < 300 then return true end
        return false, "HTTP " .. tostring(status)
    end
    if res ~= nil then return true end
    return false, tostring(status) .. " " .. tostring(res)
end

task.spawn(function()
    while true do
        if #WebhookQueue > 0 then
            local payload = table.remove(WebhookQueue, 1)
            local ok, err = postWebhook(payload)
            if not ok then log("webhook error: %s", tostring(err)) end
            task.wait(1.4)
        else
            task.wait(0.4)
        end
    end
end)

local function describeItems(items, limit)
    if not items or #items == 0 then return "*(nothing)*" end
    local parts = {}
    for i, it in ipairs(items) do
        if limit and i > limit then
            parts[#parts + 1] = string.format("... +%d more", #items - limit)
            break
        end
        local fl = flagString(it.flags)
        parts[#parts + 1] = string.format("%s%s - `%.3f`",
            fl ~= "" and (fl .. " ") or "", it.name, it.value or 0)
    end
    return table.concat(parts, "\n")
end

local function isoNow()
    local ok, dt = pcall(function() return DateTime.now():ToIsoDate() end)
    if ok and dt then return dt end
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function webhookReady()
    local url = (S.WebhookUrl or ""):gsub("%s", "")
    return url:sub(1, 8) == "https://"
end

local function shortList(items, limit)
    local t = {}
    for i, it in ipairs(items or {}) do
        if limit and i > limit then
            t[#t + 1] = "+" .. tostring(#items - limit) .. " more"
            break
        end
        t[#t + 1] = tostring(it.name)
    end
    if #t == 0 then return "nothing" end
    return table.concat(t, " + ")
end

-- one Discord card written by Kiria (start / warning / test, ...)
local function sendKiriaCard(event, ctx, title)
    if not S.KiriaEnabled then return false end
    if not webhookReady() then return false end
    local line, gif = kiriaReact(event, ctx)
    if not line and not gif then return false end

    local embed = {
        title = title or "Kiria",
        description = line or "",
        color = (Kiria and Kiria.Color) or 0x9B59B6,
        timestamp = isoNow(),
    }
    if gif then embed.image = { url = gif } end

    local payload = { embeds = { embed } }
    if Kiria then
        payload.username = tostring(Kiria.Name) .. " | " .. tostring(Kiria.Title)
        payload.avatar_url = Kiria.Avatar
        embed.footer = { text = "Kiria v" .. tostring(Kiria.Version) }
    end
    enqueueWebhook(payload)
    return true
end

local function sessionProfit()
    local give = E.stats.giveV or 0
    local get = E.stats.getV or 0
    local gain = get - give
    local pct = give > 0 and (gain / give * 100) or 0
    return gain, pct, give, get
end

-- Kiria's progress card: real session numbers only
local function sendSessionCard(title)
    local gain, pct = sessionProfit()
    local wins = E.stats.accepted or 0
    local decisions = wins + (E.stats.declined or 0)
    return sendKiriaCard("progress", {
        pct = pct,
        gain = gain,
        wins = wins,
        offers = decisions,
        rate = decisions > 0 and (wins / decisions * 100) or nil,
    }, title or "Session progress")
end

local function maybeSessionCard()
    if not S.KiriaEnabled or not webhookReady() then return end
    local wins = E.stats.accepted or 0
    if wins > 0 and wins % 10 == 0 then
        task.spawn(function() sendSessionCard() end)
    end
end

-- "still working" heartbeat: one progress card every 30 quiet minutes
task.spawn(function()
    while true do
        task.wait(60)
        if S.Enabled and S.KiriaEnabled and webhookReady() then
            local idle = os.time() - (E.lastPostAt or os.time())
            if idle >= 1800 then
                E.lastPostAt = os.time()
                sendSessionCard("Still working")
            end
        end
    end
end)

local function sendOfferWebhook(offer, decision, extra)
    if decision == "new" and not S.NotifyAllOffers then return end
    if decision == "accepted" and not S.NotifyAccepted then return end
    if decision == "declined" and not S.NotifyDeclined then return end

    local color = 0xE67E22
    local title = "New trade offer"
    if decision == "accepted" then
        color, title = 0x2ECC71, "Trade accepted"
    elseif decision == "declined" then
        color, title = 0xE74C3C, "Trade declined"
    end

    local ratio = 0
    if offer.ourValue > 0 then
        ratio = offer.theirValue / offer.ourValue
    elseif offer.theirValue > 0 then
        ratio = math.huge
    end

    local ratioText
    if ratio == math.huge then
        ratioText = "inf (you give nothing)"
    else
        ratioText = string.format("x%.2f", ratio)
    end

    local fields = {
        { name = "You receive", value = describeItems(offer.theirs, 12), inline = false },
        { name = "You give",    value = describeItems(offer.ours, 12),   inline = false },
        {
            name = "Value",
            value = string.format("**%.3f** <- theirs | yours -> **%.3f**  (%s)",
                offer.theirValue or 0, offer.ourValue or 0, ratioText),
            inline = false,
        },
    }

    if offer.unknown and #offer.unknown > 0 then
        fields[#fields + 1] = {
            name = "Unpriced items",
            value = table.concat(offer.unknown, ", "):sub(1, 1000),
            inline = false,
        }
    end
    if decision == "accepted" then
        local gain, pct, give, get = sessionProfit()
        fields[#fields + 1] = {
            name = "Session",
            value = string.format("net %+.2f (%+.1f%%) | given %.2f | received %.2f", gain, pct, give, get),
            inline = false,
        }
    end
    if extra then
        fields[#fields + 1] = { name = "Note", value = tostring(extra):sub(1, 1000), inline = false }
    end

    local payload = {
        username = "Adopt Me Trade Bot",
        embeds = {
            {
                title = title,
                color = color,
                fields = fields,
                footer = { text = string.format("amvgg values | %s | v%s", VALUES_UPDATED, BOT.Version) },
                timestamp = isoNow(),
            },
        },
    }
    if (S.WebhookMention or "") ~= "" then
        payload.content = "<@" .. tostring(S.WebhookMention):gsub("[^%d]", "") .. ">"
    end

    -- Kiria explains the finished trade in her own words and adds a gif
    if decision == "accepted" and S.KiriaEnabled then
        local giveV = offer.ourValue or 0
        local getV = offer.theirValue or 0
        if giveV > 0 then
            local gain = getV - giveV
            local line, gif = kiriaReact("win", {
                pct = gain / giveV * 100,
                gain = gain,
                give = shortList(offer.ours),
                get = shortList(offer.theirs),
                giveV = giveV,
                getV = getV,
                source = "incoming",
                n = #(offer.ours or {}) + #(offer.theirs or {}),
                dry = not S.Enabled,
            })
            if line then payload.description = line end
            if gif then payload.embeds[1].image = { url = gif } end
            if Kiria then
                payload.username = tostring(Kiria.Name) .. " | " .. tostring(Kiria.Title)
                payload.avatar_url = Kiria.Avatar
            end
        end
    end

    enqueueWebhook(payload)
end

--============================================================== 9. engine
BOT.Engine = E

local function signatureOf(list)
    local t = {}
    for _, it in ipairs(list or {}) do
        t[#t + 1] = it.name .. "|" .. flagString(it.flags)
    end
    table.sort(t)
    return table.concat(t, ",")
end

local function decide(offer)
    local theirValue = offer.theirValue or 0
    local ourValue = offer.ourValue or 0

    if #offer.theirs == 0 then
        return "waiting", "their side is empty"
    end
    if theirValue < (S.MinOfferValue or 0) then
        return "waiting", "offer too small"
    end
    if S.RequireKnownValue and #offer.unknown > 0 then
        return "decline", "unpriced items in offer"
    end
    if ourValue <= 0 then
        -- we have not added anything yet: the fill logic will handle it
        return "fill", "nothing on our side yet"
    end

    local ratio = theirValue / ourValue

    if ratio < (S.MinAcceptRatio or 1.05) then
        return "decline", string.format("low ratio x%.2f", ratio)
    end
    local maxRatio = S.MaxAcceptRatio or 0
    if maxRatio > 0 and ratio > maxRatio then
        return "decline", string.format("ratio too high x%.2f (possible bait)", ratio)
    end

    if S.RequireWantedItem then
        local wanted = parseList(S.WantedText)
        if next(wanted) then
            local found = false
            for _, it in ipairs(offer.theirs) do
                if wanted[normalize(it.name)] then found = true; break end
            end
            if not found then return "decline", "no wanted item" end
        end
    end

    return "accept", string.format("ratio x%.2f", ratio)
end

-- picks the next inventory item to add to our side
local function pickNextItem(inventory, offer)
    if #inventory == 0 then return nil end

    local theirValue = offer.theirValue or 0
    local ourValue = offer.ourValue or 0
    if #offer.ours >= (S.MaxItemsToGive or 4) then return nil end

    local target
    if S.FillMode == "fair" then
        target = theirValue * 0.98
    else
        target = theirValue / math.max(S.MinAcceptRatio or 1.05, 1.0001) * 0.98
    end

    local remaining = target - ourValue
    if remaining <= 0 then return nil end

    local sorted = {}
    for _, it in ipairs(inventory) do sorted[#sorted + 1] = it end
    table.sort(sorted, function(a, b) return (a.value or 0) < (b.value or 0) end)

    -- prefer the most expensive item that still fits, so we need fewer slots
    local best
    for _, it in ipairs(sorted) do
        local v = it.value or 0
        if v <= remaining then best = it end
    end
    -- nothing fits: adding the cheapest would push the ratio under MinAcceptRatio,
    -- so leave the decision to the caller
    return best
end

local function clickInventoryItem(item)
    if not item or not item.slot then return false end
    local slot = item.slot
    if slot:IsA("GuiButton") then
        return clickButton(slot)
    end
    for _, d in ipairs(slot:GetDescendants()) do
        if d:IsA("GuiButton") and isVisible(d) then
            return clickButton(d)
        end
    end
    return clickButton(slot.Parent)
end

local function doAccept(win)
    local btn = findButtonIn(win, ACCEPT_WORDS, DECLINE_WORDS)
    if not btn then return false end
    clickButton(btn)

    if S.ConfirmAccepts then
        task.wait(0.7)
        local win2 = findTradeWindow()
        if win2 then
            local confirm = findButtonIn(win2, { "confirm", "yes" },
                { "decline", "cancel", "no" })
            if confirm and confirm ~= btn then
                clickButton(confirm)
            end
        end
    end
    return true
end

local function doDecline(win)
    local btn = findButtonIn(win, DECLINE_WORDS, nil)
    if not btn then return false end
    return clickButton(btn)
end

local function stepTradeWindow(win)
    if classifyWindow(win) == "phone" then return end
    local offer = readOffers(win)
    -- only the other player's side triggers a "new offer" notification,
    -- otherwise every item we add would spam the webhook
    local sig = signatureOf(offer.theirs)

    if sig ~= E.lastSignature then
        E.lastSignature = sig
        E.lastSummary = string.format("theirs %.3f / ours %.3f  %d vs %d items",
            offer.theirValue, offer.ourValue, #offer.theirs, #offer.ours)
        if #offer.theirs > 0 then
            E.stats.offers += 1
            sendOfferWebhook(offer, "new")
            log("offer: %s", E.lastSummary)
        end
    end

    if #offer.theirs == 0 then
        E.state = "waiting"
        return
    end

    local action, reason = decide(offer)

    if S.Debug and #offer.unknown > 0 then
        log("unpriced items: %s", table.concat(offer.unknown, ", "))
    end

    if action == "fill" or (action == "accept" and S.AutoFill and offer.ourValue <
            (offer.theirValue / math.max(S.MinAcceptRatio or 1.05)) * 0.9) then
        if S.AutoFill then
            local inventory = scanInventory(win)
            local nextItem = pickNextItem(inventory, offer)
            if nextItem then
                -- if the same click did nothing three times, stop trying it
                if E.lastFill and E.lastFill.key == nextItem.key
                    and E.lastFill.ourValue == offer.ourValue then
                    E.lastFill.tries = (E.lastFill.tries or 1) + 1
                else
                    E.lastFill = { key = nextItem.key, ourValue = offer.ourValue, tries = 1 }
                end

                if E.lastFill.tries > 3 then
                    E.failed[nextItem.key] = true
                    E.lastFill = nil
                    log("cannot add %s, marking as unusable", nextItem.name)
                    return
                end

                E.state = "filling (" .. nextItem.name .. ")"
                if clickInventoryItem(nextItem) then
                    log("adding to offer: %s (%.3f)", nextItem.name, nextItem.value)
                    task.wait(0.35)
                end
                return
            end
            -- nothing suitable on screen: page through the inventory grid
            if sweepInventory(win) then
                E.state = "searching inventory"
                task.wait(0.2)
                return
            end
        end
        if action == "fill" then
            E.state = "waiting for our side"
            return
        end
    end

    if action == "accept" and S.AutoAcceptOffers then
        if os.clock() < E.acceptCooldown then return end
        E.state = "accepting (" .. reason .. ")"
        log("accepting trade: %s", reason)
        E.stats.giveV = (E.stats.giveV or 0) + (offer.ourValue or 0)
        E.stats.getV = (E.stats.getV or 0) + (offer.theirValue or 0)
        sendOfferWebhook(offer, "accepted", reason)
        E.stats.accepted += 1
        E.acceptCooldown = os.clock() + 2.5
        doAccept(win)
        notify("Trade accepted", reason, 3)
        maybeSessionCard()
        return
    end

    if action == "decline" and S.AutoDeclineBad then
        if os.clock() < E.declineCooldown then return end
        E.state = "declining (" .. reason .. ")"
        log("declining trade: %s", reason)
        if S.NotifyDeclined then sendOfferWebhook(offer, "declined", reason) end
        E.stats.declined += 1
        E.declineCooldown = os.clock() + 2.0
        doDecline(win)
    end
end

local function stepRequestPopup(win)
    if not S.AutoAcceptRequests then return end
    if os.clock() < E.acceptCooldown then return end

    local btn = findButtonIn(win, ACCEPT_WORDS, DECLINE_WORDS)
    if btn then
        E.state = "accepting trade request"
        log("accepting incoming trade request")
        clickButton(btn)
        E.acceptCooldown = os.clock() + 2.0
    end
end

--============================================================== 9b. outgoing requests
local function tryRequestTrade(target)
    local pg = getPlayerGui()
    if not pg or not target or target == "" then return false end
    local needle = target:lower()

    -- find the player's name somewhere in the UI (player list, trade tab, ...)
    local anchor
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text and d.Text ~= "" then
            if d.Text:lower():find(needle, 1, true) then
                anchor = d
                break
            end
        end
    end
    if not anchor then return false end

    -- look for a "Trade" button in the surrounding card
    local node = anchor
    for _ = 1, 4 do
        node = node.Parent
        if not node then break end
        for _, d in ipairs(node:GetDescendants()) do
            if d:IsA("GuiButton") and isVisible(d) then
                local t = (guiText(d) .. " " .. (d.Name or "")):lower()
                if t:find("trade", 1, true) and not t:find("request", 1, true) then
                    clickButton(d)
                    return true
                end
            end
        end
    end
    return false
end

local function remoteRequestTrade(target)
    if not S.UseRemoteFallback then return false end
    local player = Players:FindFirstChild(target)
    if not player then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Name:lower() == tostring(target):lower()
                or p.DisplayName:lower() == tostring(target):lower() then
                player = p
                break
            end
        end
    end
    if not player then return false end

    local rs = game:GetService("ReplicatedStorage")
    for _, d in ipairs(rs:GetDescendants()) do
        local n = d.Name:lower()
        if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction"))
            and n:find("trade", 1, true)
            and (n:find("request", 1, true) or n:find("send", 1, true) or n:find("invite", 1, true)) then
            local ok = pcall(function()
                if d:IsA("RemoteEvent") then
                    d:FireServer(player)
                else
                    d:InvokeServer(player)
                end
            end)
            if ok then return true end
        end
    end
    return false
end

--============================================================== 9c. trading hub phone
-- The Trading Hub Phone (a toy) opens Listings / Offers / History. Posting a
-- listing works only inside the Trading Hub, at Robo Todd, costs 100 bucks and
-- is capped at two listings. Only the outside of that UI is public knowledge,
-- so every step here is driven by visible labels and logged. PhoneDryRun is ON
-- by default: the bot writes what it would click and clicks nothing.
local PHONE_CREATE = { "create", "post", "new listing", "add listing", "list pet" }
local PHONE_NEXT   = { "next", "continue", "select", "done", "confirm" }
local PHONE_REMOVE = { "take down", "remove", "delete", "cancel listing", "unlist" }
local PHONE_NOISE  = {
    "value", "demand", "offers", "offer", "listings", "listing", "history", "bucks",
    "accept", "decline", "cancel", "confirm", "create", "search", "filter", "sort",
    "you give", "you get", "you receive", "wants", "want", "trade", "claim", "expired",
    "pending", "sold", "trading hub", "phone", "back", "close", "locked", "remove",
    "next", "post", "delete", "modify", "history", "trades",
}

local function uiRoot(obj)
    local pg = getPlayerGui()
    local p = obj
    while p and p.Parent and p.Parent ~= pg do p = p.Parent end
    return p or obj
end

-- smallest container that holds the labels of the trade phone / Robo Todd window
local function findPhoneWindow()
    local pg = getPlayerGui()
    if not pg then return nil end
    local marks = {}
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= "" then
            local t = d.Text:lower()
            local key
            if t:find("post a listing", 1, true) or t:find("view my listings", 1, true)
                or t:find("trading hub", 1, true) then
                key = "hub"
            elseif t:find("post listing", 1, true) then
                key = "post"
            elseif t:find("for listing", 1, true) then
                key = "offers"
            elseif t:find("history", 1, true) then
                key = "history"
            elseif t:find("listing", 1, true) then
                key = "listings"
            elseif t:find("offer", 1, true) then
                key = "offers"
            end
            if key then
                local p, depth = d, 0
                while p and p ~= pg and depth < 10 do
                    if p:IsA("GuiObject") then
                        local m = marks[p]
                        if not m then m = {}; marks[p] = m end
                        m[key] = true
                    end
                    p = p.Parent
                    depth += 1
                end
            end
        end
    end
    local best, bestArea = nil, math.huge
    for obj, m in pairs(marks) do
        local count = 0
        for _ in pairs(m) do count += 1 end
        if (count >= 2) or m.hub or m.post then
            local sz = obj.AbsoluteSize
            local area = math.max(sz.X, 1) * math.max(sz.Y, 1)
            if area > 15000 and area < bestArea then best, bestArea = obj, area end
        end
    end
    return best
end

local function phoneNoise(name)
    return textMatches(name, PHONE_NOISE)
end

-- every click goes through here: dry run only logs
local function phoneClick(btn, what)
    if not btn then
        log("phone: %s - no button found", tostring(what))
        return false
    end
    local label = guiLabel(btn)
    if S.PhoneDryRun then
        log("phone (dry): would click \"%s\" for %s", label, tostring(what))
        return false
    end
    clickButton(btn)
    log("phone: clicked \"%s\" for %s", label, tostring(what))
    return true
end

-- the phone is a Tool, so it can be used straight from the backpack
local function findPhoneTool()
    local function isPhone(name)
        local n = tostring(name or ""):lower()
        return n:find("phone", 1, true) ~= nil
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and isPhone(t.Name) then return t, false end
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and isPhone(t.Name) then return t, true end
        end
    end
    return nil
end

local function phoneClickToy()
    local pg = getPlayerGui()
    if not pg then return false end

    -- 1. the toy itself: equip it and activate, no clicking needed
    local tool, equipped = findPhoneTool()
    if tool then
        if equipped then
            log("phone: the phone toy is already in hand")
        elseif S.PhoneDryRun then
            log("phone (dry): would equip and use the tool \"%s\"", tostring(tool.Name))
            return false
        else
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                if pcall(function() hum:EquipTool(tool) end) then
                    log("phone: equipped \"%s\"", tostring(tool.Name))
                    task.wait(0.5)
                end
            end
        end
        if not S.PhoneDryRun then
            pcall(function() tool:Activate() end)
            task.wait(0.9)
            if findPhoneWindow() then return true end
        end
    end

    -- 2. fall back to a button that looks like the phone
    local function scan()
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("GuiButton") and isVisible(d) then
                local t = (guiText(d) .. " " .. tostring(d.Name or "")):lower()
                if t:find("phone", 1, true) then return d end
            end
        end
        return nil
    end
    local btn = scan()
    if not btn then
        local bag = findButtonIn(pg, { "backpack", "inventory" })
        if bag then
            clickButton(bag)
            task.wait(0.5)
            btn = scan()
        end
    end
    if not btn then return false end
    if S.PhoneDryRun then
        log("phone (dry): would click the phone toy \"%s\"", guiLabel(btn))
        return false
    end
    clickButton(btn)
    log("phone: used the phone toy")
    task.wait(0.8)
    return true
end

-- offer cards = smallest container around an accept button that holds item names
local function phoneCards(win)
    local cards, seen = {}, {}
    if not win then return cards end
    for _, b in ipairs(collectButtons(win)) do
        if buttonMatches(b, ACCEPT_WORDS) then
            local card
            local p, depth = b, 0
            while p and p ~= win and depth < 5 do
                if p:IsA("GuiObject") then
                    local sz = p.AbsoluteSize
                    if sz.X >= 120 and sz.Y >= 60 then
                        for _, c in ipairs(p:GetDescendants()) do
                            if c:IsA("TextLabel") and isVisible(c) and c.Text ~= "" then
                                local name = cleanItemName(c.Text)
                                if name ~= "" and not phoneNoise(name) and lookupValue(name) then
                                    card = p
                                    break
                                end
                            end
                        end
                    end
                    if card then break end
                end
                p = p.Parent
                depth += 1
            end
            if card and not seen[card] then
                seen[card] = true
                cards[#cards + 1] = {
                    card = card,
                    accept = b,
                    decline = findButtonIn(card, DECLINE_WORDS, ACCEPT_WORDS),
                }
            end
        end
    end
    return cards
end

local function readPhoneCard(card)
    local result = { ours = {}, theirs = {}, unknown = {}, ourValue = 0, theirValue = 0 }
    if not card then return result end

    local split = readOffers(card)
    if #split.theirs > 0 then return split end

    -- fallback: an offer card usually holds only what the other side gives
    local seen = {}
    for _, d in ipairs(card:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" and isVisible(d) then
            local name = cleanItemName(d.Text)
            local entry = (name ~= "" and not phoneNoise(name)) and lookupValue(name) or nil
            local slot = findSlot(d, card) or d
            if entry and not seen[slot] then
                seen[slot] = true
                local flags = readFlags(slot)
                local item = {
                    name = entry.name, entry = entry, flags = flags,
                    value = itemValue(entry, flags), slot = slot,
                }
                result.theirs[#result.theirs + 1] = item
                result.theirValue += item.value
            end
        end
    end
    return result
end

-- what an offer must be worth: the dearest listing we know about, plus a manual floor
local function phoneFloor()
    local minRatio = S.MinAcceptRatio or 1.05
    local floor = tonumber(S.PhoneMinOfferValue) or 0
    local listed = tonumber(S.PhoneListedValue) or 0
    if listed > 0 then floor = math.max(floor, listed * minRatio) end
    for _, rec in ipairs(E.phone.listings or {}) do
        local v = tonumber(rec.askV) or ((tonumber(rec.value) or 0) * minRatio)
        if v > floor then floor = v end
    end
    return floor
end

local function phoneDecision(offer, floor)
    local getV = offer.theirValue or 0
    if #offer.theirs == 0 then return "waiting", getV, "no priced items" end
    if getV < (S.MinOfferValue or 0) then return "waiting", getV, "too small" end
    if floor <= 0 then return "waiting", getV, "no reference value (set PhoneListedValue)" end
    if getV < floor then return "decline", getV, string.format("%.3f < %.3f", getV, floor) end
    return "accept", getV, string.format("%.3f >= %.3f", getV, floor)
end

local function sendPhoneWebhook(title, color, fields, kiriaEvent, kiriaCtx)
    if not webhookReady() then return false end
    local embed = { title = title, color = color or 0x3498DB, fields = fields, timestamp = isoNow() }
    if kiriaEvent then
        local line, gif = kiriaReact(kiriaEvent, kiriaCtx or {})
        if line then embed.description = line end
        if gif then embed.image = { url = gif } end
    end
    local payload = { embeds = { embed } }
    if Kiria and S.KiriaEnabled then
        payload.username = tostring(Kiria.Name) .. " | " .. tostring(Kiria.Title)
        payload.avatar_url = Kiria.Avatar
    end
    enqueueWebhook(payload)
    return true
end

--============================================================== 9d. inventory brain
-- Reads the real inventory (backpack grid, every scroll page), then plans an
-- upgrade chain out of it: give the cheapest duplicate, ask for something worth
-- more, and feed the result of each step into the next one. Everything is based
-- on items that were actually seen, so a plan can never name a pet you do not own.
local function invBanned(d, banned)
    local p = d
    local guard = 0
    while p and guard < 40 do
        if banned[p] then return true end
        p = p.Parent
        guard += 1
    end
    return false
end

-- the phone lists other people's offers and the trade window lists the other
-- player's pets; neither of those is mine
local function invBannedRoots()
    local banned = {}
    local phoneWin = findPhoneWindow()
    if phoneWin then banned[phoneWin] = true end
    local tradeWin = findTradeWindow()
    if tradeWin then banned[tradeWin] = true end
    -- my own window prints item names in the log, they are not inventory
    local pg = getPlayerGui()
    local ownGui = pg and pg:FindFirstChild("AdoptMeTradeBotUI")
    if ownGui then banned[ownGui] = true end
    return banned
end

-- one pass over whatever is on screen right now
local function invPass(root, banned)
    local map, order, seen = {}, {}, {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= "" and not invBanned(d, banned) then
            local name = cleanItemName(d.Text)
            if name ~= "" and not textMatches(name, PHONE_NOISE) then
                local entry = lookupValue(name)
                if entry then
                    local slot = findSlot(d, root) or d
                    local key = normalize(entry.name)
                    local rec = map[key]
                    if not rec then
                        local flags = readFlags(slot)
                        rec = {
                            key = key, name = entry.name, entry = entry,
                            flags = flags, value = itemValue(entry, flags),
                            copies = 0, slots = {},
                        }
                        map[key] = rec
                        order[#order + 1] = rec
                    end
                    if not seen[slot] then
                        seen[slot] = true
                        rec.copies += 1
                        rec.slots[#rec.slots + 1] = slot
                    end
                end
            end
        end
    end
    return order
end

-- scroll every grid on the screen by one page; false when nothing moved
local function invSweep(root)
    local moved = false
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ScrollingFrame") and isVisible(d) then
            pcall(function()
                local window = d.AbsoluteWindowSize
                if window.Y <= 0 then window = d.AbsoluteSize end
                local canvas = d.AbsoluteCanvasSize
                local maxY = math.max(0, canvas.Y - window.Y)
                if maxY >= 1 then
                    local step = math.max(window.Y * 0.8, 60)
                    local y = d.CanvasPosition.Y + step
                    if y > maxY + 1 then
                        y = 0
                    else
                        moved = true
                    end
                    d.CanvasPosition = Vector2.new(d.CanvasPosition.X, y)
                end
            end)
        end
    end
    return moved
end

-- toys (the phone itself, strollers, ...) live in the Roblox backpack
local function invTools(best, order)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") then
            local entry = lookupValue(cleanItemName(t.Name))
            if entry then
                local key = normalize(entry.name)
                local rec = best[key]
                if not rec then
                    rec = { key = key, name = entry.name, entry = entry, value = itemValue(entry, nil), copies = 0 }
                    best[key] = rec
                    order[#order + 1] = rec
                end
                rec.copies += 1
            end
        end
    end
end

local function inventoryTotal(items)
    local total, count = 0, 0
    for _, it in ipairs(items or {}) do
        total += (it.value or 0) * (it.copies or 1)
        count += it.copies or 1
    end
    return total, count
end

-- full scan: several scroll passes, keep the highest copy count ever seen
local function scanInventoryBrain(maxPasses)
    local pg = getPlayerGui()
    if not pg then return false, "no player GUI" end
    maxPasses = tonumber(maxPasses) or tonumber(S.PhoneInvPasses) or 6
    local banned = invBannedRoots()
    local best, order = {}, {}
    local openedBag = false

    for pass = 1, maxPasses do
        local found = invPass(pg, banned)
        if #found == 0 and not openedBag then
            openedBag = true
            local bag = findButtonIn(pg, { "backpack", "inventory", "pets" })
            if bag and not S.PhoneDryRun then
                clickButton(bag)
                task.wait(0.7)
                found = invPass(pg, banned)
            end
        end
        for _, rec in ipairs(found) do
            local cur = best[rec.key]
            if not cur then
                cur = {
                    key = rec.key, name = rec.name, entry = rec.entry,
                    value = rec.value, flags = rec.flags, copies = rec.copies,
                }
                best[rec.key] = cur
                order[#order + 1] = cur
            elseif rec.copies > cur.copies then
                cur.copies = rec.copies
                cur.value = rec.value
                cur.flags = rec.flags
            end
        end
        if #found == 0 or not invSweep(pg) then break end
        task.wait(0.25)
    end

    invTools(best, order)
    table.sort(order, function(a, b)
        local av = (a.value or 0) * (a.copies or 1)
        local bv = (b.value or 0) * (b.copies or 1)
        if av == bv then return a.name < b.name end
        return av > bv
    end)

    E.inv.items = order
    E.inv.total, E.inv.count = inventoryTotal(order)
    E.inv.at = os.time()
    E.inv.busy = false
    return true, nil
end

local function inventorySnapshot()
    local inv = E.inv
    if not inv or not inv.items or #inv.items == 0 then return nil end
    return inv
end

-- hand back the last snapshot and start a fresh one in the background when it
-- is too old; never blocks the trade loop
local function ensureInventory()
    if S.PhoneScanInventory == false then return inventorySnapshot() end
    local inv = inventorySnapshot()
    local maxAge = tonumber(S.PhoneInvMaxAge) or 300
    if inv and (os.time() - (inv.at or 0)) <= maxAge then return inv end
    if E.inv.busy then return inv end
    E.inv.busy = true
    task.spawn(function()
        local ok, err = scanInventoryBrain()
        if ok then
            log("inventory: %d stacks, %d items, total %.3f", #E.inv.items, E.inv.count or 0, E.inv.total or 0)
        else
            E.inv.busy = false
            log("inventory: scan failed (%s)", tostring(err))
        end
    end)
    return inv
end

-- one greedy chain: cheapest duplicate -> best item inside the gain window,
-- then the item you just got becomes the next thing you give away
local function planUpgrades(items, steps)
    steps = tonumber(steps) or tonumber(S.PhoneUpgradeSteps) or 4
    local keep = parseList(S.KeepListText)
    local pool = parseList(S.TradePoolText)
    local wanted = parseList(S.WantedText)
    local hasPool = next(pool) ~= nil
    local minPct = tonumber(S.PhoneUpgradeMinPct) or 10
    local maxPct = tonumber(S.PhoneUpgradeMaxPct) or 60
    local giveFloor = tonumber(S.PhoneGiveMinValue) or 0.05

    local owned = {}
    for _, it in ipairs(items or {}) do
        owned[it.key] = { key = it.key, name = it.name, value = it.value or 0, copies = it.copies or 1 }
    end

    local plan = {}
    local startTotal = inventoryTotal(items)
    local total = startTotal

    for _ = 1, steps do
        local give
        for _, rec in pairs(owned) do
            local allowed = not keep[rec.key] and (not hasPool or pool[rec.key] ~= nil)
            if allowed and rec.value >= giveFloor then
                local enough = (rec.copies >= 2) or (S.PhoneDuplicatesOnly == false)
                if enough and (not give or rec.value < give.value) then give = rec end
            end
        end
        if not give then break end

        local lo = give.value * (1 + minPct / 100)
        local hi = give.value * (1 + maxPct / 100)
        local want, wantValue, source, bestScore
        for key, entry in pairs(VALUES) do
            local v = entry.value or 0
            if key ~= give.key and v >= lo and v <= hi and not keep[key] then
                local score = v
                if wanted[key] then score += 10000 end
                local mine = owned[key]
                if mine and (mine.copies or 0) > 0 then score -= 5000 end
                if entry.cat == "pet" then score += 300 end
                if not bestScore or score > bestScore then
                    want, wantValue, bestScore = entry.name, v, score
                    if wanted[key] then
                        source = "wanted list"
                    elseif mine and (mine.copies or 0) > 0 then
                        source = "already owned, another copy"
                    else
                        source = "value table"
                    end
                end
            end
        end
        if not want then break end

        local key = normalize(want)
        local rec = owned[key]
        if not rec then
            rec = { key = key, name = want, value = wantValue, copies = 0 }
            owned[key] = rec
        end
        rec.copies += 1
        if (rec.value or 0) < wantValue then rec.value = wantValue end

        give.copies -= 1
        if give.copies <= 0 then owned[give.key] = nil end

        local gain = wantValue - give.value
        total += gain
        plan[#plan + 1] = {
            give = give.name, giveValue = give.value,
            want = want, wantValue = wantValue,
            gain = gain, pct = (gain / give.value) * 100,
            source = source or "value table",
        }
    end

    local planned = 0
    for _, s in ipairs(plan) do planned += s.gain end
    return plan, startTotal, planned
end

local function describePlan(plan, startTotal, planned)
    if not plan or #plan == 0 then return "no safe upgrade found" end
    local lines = {}
    for i, s in ipairs(plan) do
        lines[#lines + 1] = string.format("%d) %s (%.3f) -> %s (%.3f) %+.0f%% [%s]",
            i, s.give, s.giveValue, s.want, s.wantValue, s.pct, s.source)
    end
    lines[#lines + 1] = string.format("chain: %.3f -> %.3f (%+.3f)", startTotal, startTotal + planned, planned)
    return table.concat(lines, "\n")
end

local function writeInventoryDump()
    local inv = E.inv or {}
    local items = inv.items or {}
    local lines = { "Inventory scan " .. os.date("%Y-%m-%d %H:%M:%S") }
    lines[#lines + 1] = string.format("stacks: %d | items: %d | value: %.3f", #items, inv.count or 0, inv.total or 0)
    for _, it in ipairs(items) do
        lines[#lines + 1] = string.format("  %s x%d | %.3f each | %.3f total%s",
            it.name, it.copies or 1, it.value or 0, (it.value or 0) * (it.copies or 1),
            (it.flags and flagString(it.flags) ~= "") and (" | " .. flagString(it.flags)) or "")
    end
    if #items == 0 then
        lines[#lines + 1] = "  nothing found: open the backpack (or a trade) and scan again"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "upgrade plan:"
    local plan, startTotal, planned = planUpgrades(items)
    lines[#lines + 1] = describePlan(plan, startTotal, planned)
    local body = table.concat(lines, "\n")
    if writefile then pcall(writefile, BOT.Folder .. "/inventory_dump.txt", body) end
    return body
end

local function sendInventoryCard()
    local inv = inventorySnapshot()
    if not inv then return false end
    local plan, startTotal, planned = planUpgrades(inv.items)
    local top = {}
    for i = 1, math.min(5, #inv.items) do
        local it = inv.items[i]
        top[#top + 1] = string.format("%s x%d (%.3f)", it.name, it.copies or 1,
            (it.value or 0) * (it.copies or 1))
    end
    return sendPhoneWebhook("Inventory scan", 0x9B59B6, {
        { name = "Inventory", value = string.format("%d stacks / %d items / **%.3f** total",
            #inv.items, inv.count or 0, inv.total or 0), inline = false },
        { name = "Most valuable", value = #top > 0 and table.concat(top, "\n") or "-", inline = false },
        { name = "Upgrade chain", value = describePlan(plan, startTotal, planned), inline = false },
    })
end

-- the pickers (give / want) share one search field
local function pickerSearch(root, text)
    local box
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextBox") and isVisible(d) then box = d; break end
    end
    if not box then return false end
    if S.PhoneDryRun then
        log("phone (dry): would type \"%s\" into the search field", text)
        return true
    end
    pcall(function()
        box.Text = text
        box:CaptureFocus()
        task.wait(0.15)
        box:ReleaseFocus()
    end)
    log("phone: searched the picker for %s", text)
    task.wait(0.7)
    return true
end

local function clickPickerItem(root, name)
    local key = normalize(name or "")
    if key == "" then return nil end
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= "" then
            local entry = lookupValue(cleanItemName(d.Text))
            if entry and normalize(entry.name) == key then
                return findSlot(d, root) or d.Parent
            end
        end
    end
    return nil
end

local function selectItemInPicker(root, name)
    local slot = clickPickerItem(root, name)
    if slot then return slot end
    if pickerSearch(root, name) then return clickPickerItem(root, name) end
    return nil
end

-- every priced item that is visible right now (the picker only shows what we own)
local function visibleItems(root)
    local map, order = {}, {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= "" then
            local name = cleanItemName(d.Text)
            if name ~= "" and not phoneNoise(name) then
                local entry = lookupValue(name)
                if entry then
                    local slot = findSlot(d, root) or d
                    local rec = map[entry.name]
                    if not rec then
                        rec = {
                            name = entry.name, entry = entry, label = d, slot = slot,
                            value = itemValue(entry, readFlags(slot)),
                            copies = 0, seen = {},
                        }
                        map[entry.name] = rec
                        order[#order + 1] = rec
                    end
                    if not rec.seen[slot] then
                        rec.seen[slot] = true
                        rec.copies += 1
                    end
                end
            end
        end
    end
    return order
end

--============================================================== 9e. self-learning ui map
-- The bot writes down what it sees and remembers the path of every control it
-- found, so the next run clicks the exact same object instead of guessing.
local function objPath(obj, root)
    if not obj or not root then return "" end
    local parts = {}
    local p, guard = obj, 0
    while p and p ~= root and guard < 14 do
        local seg = tostring(p.Name)
        local ok, cls = pcall(function() return p.ClassName end)
        if ok and cls then seg = seg .. "#" .. tostring(cls) end
        table.insert(parts, 1, seg)
        p = p.Parent
        guard += 1
    end
    return table.concat(parts, "/")
end

local function findByPath(root, path)
    if not root or type(path) ~= "string" or path == "" then return nil end
    local node = root
    for seg in string.gmatch(path, "[^/]+") do
        local name, cls = seg:match("^(.-)#([^#]+)$")
        if not name then name, cls = seg, nil end
        local found
        for _, c in ipairs(node:GetChildren()) do
            if tostring(c.Name) == name then
                if not cls then found = c; break end
                local ok, got = pcall(function() return c.ClassName end)
                if ok and tostring(got) == cls then found = c; break end
            end
        end
        if not found then return nil end
        node = found
    end
    return node
end

local function listButtons(root)
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiButton") and isVisible(d) then
            local sz = d.AbsoluteSize
            if sz.X >= 18 and sz.Y >= 14 then
                out[#out + 1] = {
                    btn = d, label = guiLabel(d),
                    path = objPath(d, getPlayerGui()),
                    w = math.floor(sz.X), h = math.floor(sz.Y),
                }
            end
        end
    end
    return out
end

-- writes everything clickable + every label on the current face of the UI
local function learnDump(tag, root)
    if not root or not writefile then return nil end
    local lines = { "face " .. tostring(tag) .. "  " .. os.date("%Y-%m-%d %H:%M:%S") }
    local buttons = listButtons(root)
    table.sort(buttons, function(a, b) return a.label < b.label end)
    for _, b in ipairs(buttons) do
        lines[#lines + 1] = string.format("%-30s %4dx%-4d %s",
            b.label:sub(1, 30), b.w, b.h, b.path)
    end
    local seenText = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= "" then
            local t = d.Text:gsub("[\r\n]", " ")
            if #t <= 44 and not seenText[t] then
                seenText[t] = true
                lines[#lines + 1] = "text: " .. t
            end
        end
    end
    local file = BOT.Folder .. "/auto_face_" .. tostring(tag) .. ".txt"
    pcall(writefile, file, table.concat(lines, "\n"))
    log("auto: face \"%s\" saved (%d buttons)", tostring(tag), #buttons)
    return buttons
end

-- remember the exact object behind a role, so guessing happens once
local function savePath(key, obj)
    local pg = getPlayerGui()
    if not pg or not obj then return end
    local path = objPath(obj, pg)
    if path == "" or (S[key] or "") == path then return end
    S[key] = path
    saveSettings()
    log("auto: learned %s = %s", key, path)
end

local function findLearnedBtn(root, key, words, avoid)
    local pg = getPlayerGui()
    local saved = S[key]
    if pg and type(saved) == "string" and saved ~= "" then
        local obj = findByPath(pg, saved)
        if obj and obj.Parent and obj:IsA("GuiButton") and isVisible(obj) then
            return obj
        end
    end
    local btn = findButtonIn(root, words, avoid)
    if btn then savePath(key, btn) end
    return btn
end

--============================================================== 9f. real listing flow
-- Verified against the live Trading Hub UI:
--   Robo Todd window: "POST A LISTING" / "VIEW MY LISTINGS"
--   -> POST LISTING screen: panels "You" and "Them", green + buttons
--   -> backpack (input "Enter Search...") or journal -> pick the pet
--   -> "POST LISTING" -> "Successfully posted listing!" -> "Okay"
local function commonAncestor(a, b)
    if not a or not b then return nil end
    local set = {}
    local p, guard = a, 0
    while p and guard < 24 do set[p] = true; p = p.Parent; guard += 1 end
    p, guard = b, 0
    while p and guard < 24 do
        if set[p] then return p end
        p = p.Parent
        guard += 1
    end
    return nil
end

local function labelExact(root, text)
    local want = text:lower()
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= "" then
            local t = d.Text:gsub("^%s+", ""):gsub("%s+$", ""):lower()
            if t == want then return d end
        end
    end
    return nil
end

local function visibleLabels(root, words)
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= "" and textMatches(d.Text, words) then
            out[#out + 1] = d
        end
    end
    return out
end

local function clickableForLabel(label)
    local p, guard = label.Parent, 0
    while p and guard < 6 do
        if p:IsA("GuiButton") and isVisible(p) then return p end
        p = p.Parent
        guard += 1
    end
    local parent = label.Parent
    if parent then
        for _, c in ipairs(parent:GetChildren()) do
            if c:IsA("GuiButton") and isVisible(c) then return c end
        end
    end
    return nil
end

-- the button behind a text; bottom = pick the lowest one (header and footer
-- share the same words on the POST LISTING screen)
local function clickLabel(root, words, bottom)
    local pick, pickY
    for _, d in ipairs(visibleLabels(root, words)) do
        local btn = clickableForLabel(d)
        local obj = btn or d
        local y = obj.AbsolutePosition.Y
        if not pick or (bottom and y > pickY) or (not bottom and y < pickY) then
            pick, pickY = obj, y
        end
    end
    return pick
end

local function isGreenish(btn)
    local ok, c = pcall(function() return btn.BackgroundColor3 end)
    if not ok or c == nil then return false end
    local ok2, r, g, b = pcall(function() return c.R, c.G, c.B end)
    if not ok2 or not r then return false end
    return g > 0.4 and g > r * 1.1 and g > b * 1.1
end

-- the green "+" slots of the two panels, left to right
local function plusButtons(root, minY, maxY)
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiButton") and isVisible(d) then
            local sz = d.AbsoluteSize
            local y = d.AbsolutePosition.Y
            if sz.X >= 34 and sz.Y >= 34 and sz.X <= 170 and sz.Y <= 170
                and y >= (minY or 0) and y <= (maxY or 1e6) then
                local img = ""
                pcall(function() img = tostring(d.Image or "") end)
                if guiText(d) == "" and (isGreenish(d) or textMatches(img, { "plus", "add", "green" })) then
                    out[#out + 1] = d
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if math.abs(a.AbsolutePosition.X - b.AbsolutePosition.X) < 10 then
            return a.AbsolutePosition.Y < b.AbsolutePosition.Y
        end
        return a.AbsolutePosition.X < b.AbsolutePosition.X
    end)
    return out
end

local function searchBoxIn(root)
    local first
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextBox") and isVisible(d) then
            local ph = ""
            pcall(function() ph = tostring(d.PlaceholderText or "") end)
            if ph:lower():find("search", 1, true) then return d end
            first = first or d
        end
    end
    return first
end

-- the backpack window = smallest container that holds its title and its search box
local function backpackRoot(pg)
    local label, box
    for _, d in ipairs(pg:GetDescendants()) do
        if not label and d:IsA("TextLabel") and isVisible(d) and d.Text ~= ""
            and d.Text:lower():find("backpack", 1, true) then
            label = d
        end
        if not box and d:IsA("TextBox") and isVisible(d) then
            local ph = ""
            pcall(function() ph = tostring(d.PlaceholderText or "") end)
            if ph:lower():find("search", 1, true) then box = d end
        end
    end
    if label and box then
        return commonAncestor(label, box) or box.Parent, box
    end
    if box then return box.Parent, box end
    return nil, nil
end

local function gridOf(root)
    local best, bestArea
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ScrollingFrame") and isVisible(d) then
            local sz = d.AbsoluteSize
            local area = sz.X * sz.Y
            if area > 3000 and (not bestArea or area > bestArea) then best, bestArea = d, area end
        end
    end
    return best
end

local function tilesOf(grid)
    local out = {}
    if not grid then return out end
    for _, d in ipairs(grid:GetDescendants()) do
        if (d:IsA("ImageButton") or d:IsA("TextButton")) and isVisible(d) then
            local sz = d.AbsoluteSize
            if sz.X >= 26 and sz.X <= 170 and sz.Y >= 26 and sz.Y <= 170 then
                out[#out + 1] = d
            end
        end
    end
    table.sort(out, function(a, b)
        local ay, by = a.AbsolutePosition.Y, b.AbsolutePosition.Y
        if math.abs(ay - by) < 12 then return a.AbsolutePosition.X < b.AbsolutePosition.X end
        return ay < by
    end)
    return out
end

local function typeSearch(box, text)
    if S.PhoneDryRun then
        log("phone (dry): would type \"%s\" into the backpack search", text)
        return false
    end
    pcall(function()
        box:CaptureFocus()
        task.wait(0.1)
        box.Text = ""
        task.wait(0.05)
        box.Text = text
        task.wait(0.25)
        box:ReleaseFocus()
    end)
    log("phone: typed \"%s\" into the backpack search", text)
    task.wait(0.9)
    return true
end

-- search the backpack and click the first tile (the search narrows it to one)
local function pickFromBackpack(pg, name, tag)
    local root, box = backpackRoot(pg)
    if not root then
        if S.PhoneAutoLearn then learnDump("no_backpack_" .. tag, pg) end
        return false, "the backpack did not open"
    end
    if not box then
        if S.PhoneAutoLearn then learnDump("no_search_" .. tag, root) end
        return false, "no search field in the backpack"
    end
    local grid = gridOf(root)
    local before = #tilesOf(grid)
    if not typeSearch(box, name) then return false, "dry run" end
    local tiles = tilesOf(gridOf(root) or grid)
    if #tiles == 0 then
        log("phone: \"%s\" is not in the backpack", name)
        if S.PhoneAutoLearn then learnDump("empty_" .. tag, root) end
        return false, "no search results"
    end
    if #tiles > 4 and before > 0 and #tiles >= before - 1 then
        log("phone: the search did not filter (%d -> %d tiles), not guessing", before, #tiles)
        if S.PhoneAutoLearn then learnDump("nofilter_" .. tag, root) end
        return false, "the search did not filter"
    end
    clickButton(tiles[1])
    log("phone: picked \"%s\" from the backpack (%d result(s))", name, #tiles)
    task.wait(1)
    return true
end

-- the "Them" side may open the journal instead of the backpack
local function pickFromJournal(pg, name, tag)
    local petsTab = labelExact(pg, "pets")
    if petsTab then
        local btn = clickableForLabel(petsTab)
        if btn and not S.PhoneDryRun then
            clickButton(btn)
            log("phone: opened the Pets tab of the journal")
            task.wait(0.8)
        end
    end
    local label = labelExact(pg, name)
    if label then
        local btn = clickableForLabel(label) or label.Parent
        if btn then
            if S.PhoneDryRun then
                log("phone (dry): would pick \"%s\" in the journal", name)
                return false, "dry run"
            end
            clickButton(btn)
            log("phone: picked \"%s\" in the journal", name)
            task.wait(1)
            return true
        end
    end
    for _ = 1, 4 do
        if not invSweep(pg) then break end
        task.wait(0.4)
        label = labelExact(pg, name)
        if label then
            local btn = clickableForLabel(label) or label.Parent
            if btn and not S.PhoneDryRun then
                clickButton(btn)
                log("phone: picked \"%s\" in the journal after scrolling", name)
                task.wait(1)
                return true
            end
        end
    end
    if S.PhoneAutoLearn then learnDump("journal_" .. tag, uiRoot(pg) or pg) end
    return false, "\"" .. tostring(name) .. "\" is not in the journal"
end

-- Robo Todd himself, so the bot can post without the player walking up to him
local function openRoboTodd()
    local fire = G("fireproximityprompt")
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local hay = ((d.ActionText or "") .. " " .. (d.ObjectText or "") .. " " .. d.Parent.Name):lower()
            if hay:find("robo", 1, true) or hay:find("todd", 1, true) or hay:find("listing", 1, true) then
                if type(fire) == "function" then
                    local ok = pcall(fire, d)
                    if ok then return true end
                end
                pcall(function()
                    d:InputHoldBegin()
                    task.wait(0.1)
                    d:InputHoldEnd()
                end)
                return true
            end
        end
    end
    return false
end

-- the whole "POST A LISTING" flow; returns true only when the game confirmed it
-- fills the You / Them slots on any two-sided screen (post listing, search)
local function fillTwoSides(pg, giveName, wantName)
    local you, them
    for _ = 1, 12 do
        you = labelExact(pg, "you")
        them = labelExact(pg, "them")
        if you and them then break end
        task.wait(0.25)
    end
    if not (you and them) then
        if S.PhoneAutoLearn then learnDump("no_sides", pg) end
        return false, "the You / Them panels did not show up"
    end

    local top = math.min(you.AbsolutePosition.Y, them.AbsolutePosition.Y) - 12
    local submit = clickLabel(pg, { "search", "post listing" }, true)
    local bottom = (submit and submit.AbsolutePosition.Y) or (top + 460)

    local plus = plusButtons(pg, top, bottom)
    if #plus < 2 then
        if S.PhoneAutoLearn then learnDump("no_plus", pg) end
        return false, string.format("expected two + slots, found %d", #plus)
    end
    local leftPlus, rightPlus = plus[1], plus[#plus]

    if not phoneClick(leftPlus, "put " .. giveName .. " on the You side") then return false, "dry run" end
    task.wait(1.2)
    local ok, why = pickFromBackpack(pg, giveName, "give")
    if not ok then
        log("phone: could not pick %s (%s)", giveName, tostring(why))
        return false, why
    end
    task.wait(1)

    if not (rightPlus and rightPlus.Parent and isVisible(rightPlus)) then
        local again = plusButtons(pg, top, bottom)
        rightPlus = again[#again]
    end
    if not rightPlus then
        if S.PhoneAutoLearn then learnDump("no_want_slot", pg) end
        return false, "no + slot for the Them side"
    end
    if not phoneClick(rightPlus, "put " .. wantName .. " on the Them side") then return false, "dry run" end
    task.wait(1.2)

    ok, why = pickFromBackpack(pg, wantName, "want")
    if not ok then
        log("phone: backpack did not have %s (%s), trying the journal", wantName, tostring(why))
        ok, why = pickFromJournal(pg, wantName, "want")
    end
    if not ok then
        log("phone: could not pick %s (%s)", wantName, tostring(why))
        return false, why
    end
    task.wait(1)
    return true
end

-- Robo Todd: POST A LISTING -> You / Them -> POST LISTING -> "Okay"
local function postListingFlow(win, giveName, wantName)
    local pg = getPlayerGui()
    if not pg then return false, "no player GUI" end

    local hub = clickLabel(pg, { "post a listing" })
    if not hub then
        log("phone: Robo Todd window is not open, trying his prompt")
        if openRoboTodd() then
            task.wait(1.5)
            hub = clickLabel(pg, { "post a listing" })
        end
    end
    if not hub then
        if S.PhoneAutoLearn then learnDump("no_hub", uiRoot(win) or pg) end
        return false, "no POST A LISTING button (use TRAVEL TO HUB first)"
    end
    if not phoneClick(hub, "open POST A LISTING") then return false, "dry run" end
    task.wait(1.2)

    local ok, why = fillTwoSides(pg, giveName, wantName)
    if not ok then return false, why end

    local post = clickLabel(pg, { "post listing" }, true)
    if not post then
        if S.PhoneAutoLearn then learnDump("no_post_btn", pg) end
        return false, "no POST LISTING button"
    end
    if not phoneClick(post, "publish the listing") then return false, "dry run" end

    -- wait for "Successfully posted listing!" and press Okay
    local confirmed = false
    for _ = 1, 16 do
        task.wait(0.25)
        if #visibleLabels(pg, { "successfully", "posted" }) > 0 then confirmed = true end
        local okay = clickLabel(pg, { "okay" })
        if okay and confirmed then
            phoneClick(okay, "dismiss the success popup")
            break
        end
    end
    if not confirmed then
        if S.PhoneAutoLearn then learnDump("no_confirm", pg) end
        return false, "the game did not confirm the listing"
    end
    log("phone: posted %s for %s", giveName, wantName)
    return true
end

-- phone app menu: TRADE LISTINGS / TRADE OFFERS / TRADE HISTORY / TRAVEL TO HUB
local function phoneMenuOpen()
    local pg = getPlayerGui()
    if not pg then return nil end
    if labelExact(pg, "trade listings") and labelExact(pg, "trade offers") then return pg end
    if clickLabel(pg, { "travel to hub" }) then return pg end
    return nil
end

local function openPhoneApp(words, headerWords, tag)
    local pg = getPlayerGui()
    if not pg then return false, "no player GUI" end
    if #visibleLabels(pg, headerWords) > 0 then return true end
    local tile = clickLabel(pg, words)
    if not tile then
        if S.PhoneAutoLearn then learnDump("no_app_" .. tag, uiRoot(pg) or pg) end
        return false, "the phone has no " .. tostring(words[1]) .. " tile"
    end
    if not phoneClick(tile, "open " .. tostring(words[1])) then return false, "dry run" end
    task.wait(1.2)
    return true
end

local function travelToHub()
    local pg = getPlayerGui()
    if not pg then return false end
    local tile = clickLabel(pg, { "travel to hub" })
    if not tile then return false end
    if not phoneClick(tile, "travel to the Trading Hub") then return false end
    task.wait(4)
    return true
end

-- the search flow: phone -> TRADE LISTINGS -> SEARCH LISTINGS -> You/Them -> SEARCH
-- -> a listing row with SEND OFFER. The counterpart fixes the terms, so the value
-- is exactly the planned one: we only send offers that are already profitable.
local function searchAndOffer(giveName, wantName)
    local pg = getPlayerGui()
    if not pg then return false, "no player GUI" end

    local open, why = openPhoneApp({ "trade listings" }, { "search listings", "offers i sent" }, "listings")
    if not open then return false, why end
    task.wait(0.8)

    local ok, why2 = openPhoneApp({ "search listings" }, { "you", "them" }, "search")
    if not ok then return false, why2 end
    task.wait(0.8)

    local filled, why3 = fillTwoSides(pg, giveName, wantName)
    if not filled then return false, why3 end

    local searchBtn = clickLabel(pg, { "search" }, true)
    if not searchBtn then
        if S.PhoneAutoLearn then learnDump("no_search_btn", pg) end
        return false, "no SEARCH button"
    end
    if not phoneClick(searchBtn, "look for matching listings") then return false, "dry run" end
    task.wait(2)

    -- results: rows "Listing #1", "Listing #2", plus a SEND OFFER button
    local rows = {}
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= ""
            and d.Text:lower():find("listing", 1, true) then
            local p, depth = d, 0
            while p and p ~= pg and depth < 7 do
                if p:IsA("GuiObject") and p.AbsoluteSize.Y > 90 then
                    local btn = clickLabel(p, { "send offer" })
                    if btn then
                        rows[#rows + 1] = { label = d.Text, card = p, send = btn }
                        break
                    end
                end
                p = p.Parent
                depth += 1
            end
        end
    end
    if #rows == 0 then
        log("phone: no listing matches %s -> %s right now", giveName, wantName)
        if S.PhoneAutoLearn then learnDump("no_results", pg) end
        return false, "no matching listing"
    end
    table.sort(rows, function(a, b) return a.card.AbsolutePosition.Y < b.card.AbsolutePosition.Y end)
    local row = rows[1]
    log("phone: %d listing(s) match, sending an offer on \"%s\"", #rows, tostring(row.label))
    if not phoneClick(row.send, string.format("send the offer: %s for %s", giveName, wantName)) then
        return false, "dry run"
    end
    task.wait(1.5)
    local okay = clickLabel(pg, { "okay", "ok", "confirm" })
    if okay then
        phoneClick(okay, "dismiss the offer popup")
        task.wait(0.4)
    end
    log("phone: offer sent (%s for %s)", giveName, wantName)
    return true
end

-- what to give away: cheap and duplicated first, so the upgrade is safe

-- what to give away: cheap and duplicated first, so the upgrade is safe
local function pickGiveItem(items, keep, pool)
    local hasPool = next(pool) ~= nil
    local floorV = tonumber(S.PhoneGiveMinValue) or 0.05
    local best, bestScore
    for _, it in ipairs(items) do
        local key = normalize(it.entry.name)
        local allowed = not keep[key] and (not hasPool or pool[key] ~= nil)
        if allowed and it.value >= floorV then
            if (not S.PhoneDuplicatesOnly) or it.copies >= 2 then
                -- any duplicate beats any single copy, then the cheapest wins
                local score = it.value + (it.copies >= 2 and 0 or 1000)
                if not bestScore or score < bestScore then best, bestScore = it, score end
            end
        end
    end
    return best
end

-- what to ask for: a wanted item inside the window, else the best pet inside it
local function pickWantItem(giveValue, keep)
    local minPct = tonumber(S.PhoneUpgradeMinPct) or 10
    local maxPct = tonumber(S.PhoneUpgradeMaxPct) or 60
    local lo = giveValue * (1 + minPct / 100)
    local hi = giveValue * (1 + maxPct / 100)

    local wanted = parseList(S.WantedText)
    local bestName, bestValue = nil, 0
    for key, entry in pairs(VALUES) do
        local v = entry.value or 0
        if wanted[key] and v >= lo and v <= hi and not keep[key] and v > bestValue then
            bestName, bestValue = entry.name, v
        end
    end
    if bestName then return bestName, bestValue, "wanted list" end

    for key, entry in pairs(VALUES) do
        local v = entry.value or 0
        if entry.cat == "pet" and v >= lo and v <= hi and not keep[key] and v > bestValue then
            bestName, bestValue = entry.name, v
        end
    end
    if bestName then return bestName, bestValue, "value table" end

    for key, entry in pairs(VALUES) do
        local v = entry.value or 0
        if v >= lo and v <= hi and not keep[key] and v > bestValue then
            bestName, bestValue = entry.name, v
        end
    end
    return bestName, bestValue, bestName and "any category" or nil
end

-- the want picker: search for the name if there is a field, then click it
local function selectWantItem(root, wantName)
    return selectItemInPicker(root, wantName)
end

local function findListingCard(win, itemName)
    local key = normalize(itemName or "")
    if key == "" then return nil end
    for _, d in ipairs(win:GetDescendants()) do
        if d:IsA("TextLabel") and isVisible(d) and d.Text ~= "" then
            local name = cleanItemName(d.Text)
            if name ~= "" and normalize(name) == key then
                local p, depth = d, 0
                while p and p ~= win and depth < 6 do
                    if p:IsA("GuiObject") and p.AbsoluteSize.Y >= 80
                        and findButtonIn(p, PHONE_REMOVE, ACCEPT_WORDS) then
                        return p
                    end
                    p = p.Parent
                    depth += 1
                end
            end
        end
    end
    return nil
end

-- create/post flow: give a cheap duplicate, ask for something worth more.
-- Every step aborts cleanly when its control is missing.
local function createPhoneListing(win)
    if not S.PhoneAutoList then return false end
    if os.clock() < (E.phone.createAt or 0) then return false end
    E.phone.createAt = os.clock() + 120
    if #(E.phone.listings or {}) >= (tonumber(S.PhoneMaxListings) or 2) then return false end

    local budget = tonumber(S.PhoneBucksMax) or 0
    if budget > 0 and (E.phone.bucks or 0) + 100 > budget then
        log("phone: bucks budget reached (%d), not posting", E.phone.bucks or 0)
        return false
    end

    local hubBtn = clickLabel(getPlayerGui() or win, { "post a listing" })
    if not hubBtn then
        log("phone: Robo Todd is not open right now (posting works only in the Trading Hub)")
        if S.PhoneAutoLearn then learnDump("no_hub_menu", uiRoot(win)) end
        return false
    end

    local root = uiRoot(win)
    local keep = parseList(S.KeepListText)
    local pool = parseList(S.TradePoolText)

    -- the plan comes from the real inventory; the visible picker is only a fallback
    local giveName, giveValue, giveCopies, wantName, wantValue, gainPct, wantSource
    local inv = ensureInventory()
    local plan = inv and planUpgrades(inv.items, 1) or nil
    if plan and plan[1] then
        local step = plan[1]
        giveName, giveValue = step.give, step.giveValue
        wantName, wantValue, gainPct, wantSource = step.want, step.wantValue, step.pct, step.source
        for _, it in ipairs(inv.items) do
            if normalize(it.name) == normalize(step.give) then giveCopies = it.copies end
        end
        log("phone: inventory plan %s (%.3f, %s copies) -> %s (%.3f, +%.0f%%, from %s)",
            giveName, giveValue, tostring(giveCopies), wantName, wantValue, gainPct, tostring(wantSource))
    else
        if S.PhoneScanInventory ~= false and not inventorySnapshot() then
            log("phone: scanning the inventory first, posting on the next pass")
            return false
        end
        local give = pickGiveItem(visibleItems(root), keep, pool)
        if not give then
            log("phone: nothing to give (duplicates only: %s, min value %.2f)",
                tostring(S.PhoneDuplicatesOnly), tonumber(S.PhoneGiveMinValue) or 0.05)
            return false
        end
        giveName, giveValue, giveCopies = give.name, give.value, give.copies
        wantName, wantValue, wantSource = pickWantItem(give.value, keep)
        if not wantName then
            log("phone: no target for %.3f inside the +%d..+%d%% window",
                give.value, tonumber(S.PhoneUpgradeMinPct) or 10, tonumber(S.PhoneUpgradeMaxPct) or 60)
            return false
        end
        gainPct = (wantValue / give.value - 1) * 100
        log("phone: picker plan %s (%.3f, %d copies) -> %s (%.3f, +%.0f%%, from %s)",
            giveName, giveValue, giveCopies, wantName, wantValue, gainPct, tostring(wantSource))
    end

    if giveValue and wantValue and giveValue > 0 then
        gainPct = (wantValue / giveValue - 1) * 100
    end

    local okFlow, flowWhy = postListingFlow(win, giveName, wantName)
    if not okFlow then
        log("phone: listing flow stopped: %s", tostring(flowWhy))
        return false
    end

    E.phone.bucks = (E.phone.bucks or 0) + 100
    E.phone.listings[#E.phone.listings + 1] = {
        item = giveName,
        value = giveValue,
        want = wantName,
        askV = wantValue,
        at = os.time(),
    }
    sendPhoneWebhook("Listing posted", 0x3498DB, {
        { name = "I offer", value = string.format("%s (%.3f)", tostring(giveName), giveValue or 0), inline = true },
        { name = "I want", value = string.format("%s (%.3f)", tostring(wantName), wantValue or 0), inline = true },
        { name = "If it sells", value = string.format("+%.0f%% | bucks spent: %d", gainPct or 0, E.phone.bucks or 0), inline = false },
    }, "listing", {
        slot = "ask",
        items = tostring(giveName),
        n = 1,
        ask = tostring(wantName),
        askV = wantValue,
        askPct = gainPct,
    })
    return true
end

-- what the bot would post right now (for the Tools button)
local function planNextListing()
    local inv = inventorySnapshot()
    if inv then
        local plan, startTotal, planned = planUpgrades(inv.items)
        if #plan == 0 then
            return string.format("inventory %.3f: nothing safe to upgrade (duplicates only: %s, min %.2f)",
                inv.total or 0, tostring(S.PhoneDuplicatesOnly), tonumber(S.PhoneGiveMinValue) or 0.05)
        end
        return describePlan(plan, startTotal, planned)
    end

    local win = findPhoneWindow()
    local root = (win and uiRoot(win)) or getPlayerGui()
    if not root then return "no player GUI" end
    local keep = parseList(S.KeepListText)
    local pool = parseList(S.TradePoolText)
    local give = pickGiveItem(visibleItems(root), keep, pool)
    if not give then
        return "no inventory snapshot yet: press \"Scan inventory\", then check Duplicates only / Allowed to give"
    end
    local wantName, wantValue, wantSource = pickWantItem(give.value, keep)
    if not wantName then
        return string.format("no target for %s (%.3f): widen the +%d..+%d%% window",
            give.name, give.value, tonumber(S.PhoneUpgradeMinPct) or 10, tonumber(S.PhoneUpgradeMaxPct) or 60)
    end
    return string.format("%s (%.3f, %d copies) -> %s (%.3f, +%.0f%%, from %s)",
        give.name, give.value, give.copies, wantName, wantValue,
        (wantValue / give.value - 1) * 100, tostring(wantSource))
end

-- Tools button: read the inventory right now, save it and show the plan
local function scanInventoryNow()
    E.inv.busy = true
    local ok, err = scanInventoryBrain()
    if not ok then
        E.inv.busy = false
        log("inventory: scan failed (%s)", tostring(err))
        notify("Inventory", "scan failed: " .. tostring(err), 5)
        return false
    end
    local body = writeInventoryDump()
    log("inventory scan:\n%s", body)
    sendInventoryCard()
    notify("Inventory", string.format("%d items, %.3f total", E.inv.count or 0, E.inv.total or 0), 6)
    return true
end

local function stepPhone()
    if not S.PhoneEnabled then return end
    if os.clock() < (E.phone.nextAt or 0) then return end
    E.phone.nextAt = os.clock() + math.max(0.7, tonumber(S.PhoneLoopDelay) or 1.5)

    local win = findPhoneWindow()
    if not win then
        if S.PhoneAutoOpen and os.clock() >= (E.phone.openAt or 0) then
            E.phone.openAt = os.clock() + 20
            if not phoneClickToy() then log("phone: window not open and no phone toy found") end
        end
        return
    end

    local cards = phoneCards(win)
    E.phone.cards = #cards
    local floor = phoneFloor()

    -- the bot photographs the window it sees, once a minute, so the real UI can
    -- be mapped from files instead of guessing
    if S.PhoneAutoLearn and os.clock() >= (E.phone.learnAt or 0) then
        E.phone.learnAt = os.clock() + 60
        learnDump("phone", uiRoot(win))
    end

    -- 1. the best offer on our listings
    if S.PhoneAutoAcceptOffers and #cards > 0 then
        local best, bestV = nil, 0
        for _, ci in ipairs(cards) do
            ci.offer = ci.offer or readPhoneCard(ci.card)
            if (ci.offer.theirValue or 0) > bestV then
                best, bestV = ci, ci.offer.theirValue or 0
            end
        end
        if best then
            local action, getV, reason = phoneDecision(best.offer, floor)
            if action == "accept" then
                if S.PhoneDryRun then
                    log("phone (dry): would accept an offer worth %.3f (%s)", getV, reason)
                    return
                end
                E.state = "phone: accepting a listing offer"
                if phoneClick(best.accept, string.format("accept an offer worth %.3f", getV)) then
                    E.stats.getV = (E.stats.getV or 0) + getV
                    E.stats.accepted += 1
                    sendPhoneWebhook("Listing offer accepted", 0x2ECC71, {
                        { name = "You receive", value = describeItems(best.offer.theirs, 12), inline = false },
                        { name = "Value", value = string.format("**%.3f** (%.3f needed, %s)", getV, floor, reason), inline = false },
                    })
                    notify("Listing offer", string.format("accepted %s", reason), 3)
                    maybeSessionCard()
                end
                return
            elseif action == "decline" and S.PhoneAutoDeclineBad and best.decline then
                if S.PhoneDryRun then
                    log("phone (dry): would decline an offer worth %.3f (%s)", getV, reason)
                    return
                end
                if phoneClick(best.decline, "decline a weak listing offer") then
                    E.stats.declined += 1
                    log("phone: declined an offer worth %.3f (%s)", getV, reason)
                end
                return
            end
        end
    end

    -- 2. over the cap: drop the weakest waiting offer
    local cap = tonumber(S.PhoneMaxOffers) or 20
    if S.PhoneOfferSwap and #cards > cap then
        local worst, worstV
        for _, ci in ipairs(cards) do
            ci.offer = ci.offer or readPhoneCard(ci.card)
            local v = ci.offer.theirValue or 0
            if not worstV or v < worstV then worst, worstV = ci, v end
        end
        if worst and worst.decline and not S.PhoneDryRun then
            if phoneClick(worst.decline, "drop the weakest offer") then
                sendPhoneWebhook("Offer swapped", 0xE67E22, {
                    { name = "Dropped", value = describeItems(worst.offer.theirs, 8), inline = false },
                    { name = "Why", value = string.format("%d offers waiting, the cap is %d", #cards, cap), inline = false },
                }, "round", { declined = 1, sent = 0 })
                log("phone: dropped the weakest offer (%.3f)", worstV)
            end
            return
        end
    end

    -- 3. take down a listing that nobody good offered on
    if S.PhoneAutoList then
        local now = os.time()
        for i = #E.phone.listings, 1, -1 do
            local rec = E.phone.listings[i]
            local age = now - (rec.at or now)
            local retryIn = now - (rec.triedAt or 0)
            if age >= (tonumber(S.PhoneRefreshMin) or 20) * 60 and retryIn > 300 then
                local card = findListingCard(win, rec.item)
                local btn = card and findButtonIn(card, PHONE_REMOVE, ACCEPT_WORDS)
                if btn then
                    rec.triedAt = now
                    if phoneClick(btn, "take down a stale listing") then
                        table.remove(E.phone.listings, i)
                        sendPhoneWebhook("Listing taken down", 0x95A5A6, {
                            { name = "Item", value = rec.item, inline = true },
                            { name = "After", value = tostring(S.PhoneRefreshMin) .. " min", inline = true },
                        }, "refresh", { items = rec.item, min = tostring(S.PhoneRefreshMin) })
                    end
                end
                break
            end
        end
    end

    -- 4. look for profitable listings on the phone and send an offer
    if S.PhoneAutoOffer and os.clock() >= (E.phone.offerAt or 0) then
        E.phone.offerAt = os.clock() + math.max(30, tonumber(S.PhoneOfferEvery) or 90)
        local inv = inventorySnapshot()
        local plan = inv and planUpgrades(inv.items, 1) or nil
        if plan and plan[1] then
            local step = plan[1]
            local ok, why = searchAndOffer(step.give, step.want)
            if ok then
                sendPhoneWebhook("Offer sent", 0x1ABC9C, {
                    { name = "I offer", value = string.format("%s (%.3f)", step.give, step.giveValue), inline = true },
                    { name = "I want", value = string.format("%s (%.3f)", step.want, step.wantValue), inline = true },
                    { name = "Gain", value = string.format("+%.0f%% (%+.3f)", step.pct, step.gain), inline = false },
                }, "listing", {
                    slot = "ask",
                    items = step.give,
                    n = 1,
                    ask = step.want,
                    askV = step.wantValue,
                    askPct = step.pct,
                })
            else
                log("phone: search & offer skipped (%s)", tostring(why))
            end
        else
            log("phone: no upgrade plan yet (open the backpack and press Scan inventory)")
        end
    end

    -- 5. post a new listing when a slot is free
    if S.PhoneAutoList then
        local pg = getPlayerGui()
        local hubOpen = pg and clickLabel(pg, { "post a listing" })
        if not hubOpen and S.PhoneAutoTravel and os.clock() >= (E.phone.travelAt or 0) then
            E.phone.travelAt = os.clock() + 90
            log("phone: travelling to the Trading Hub to post")
            travelToHub()
        end
        createPhoneListing(win)
    end
end

-- structured report for the log and for phone_dump.txt
local function scanPhone()
    local win = findPhoneWindow()
    local lines = { "Trade phone scan " .. os.date("%Y-%m-%d %H:%M:%S") }
    if not win then
        lines[#lines + 1] = "phone window not found (open the toy first)"
    else
        lines[#lines + 1] = "window: " .. win:GetFullName()
        local labels = {}
        for _, b in ipairs(collectButtons(win)) do
            labels[#labels + 1] = guiLabel(b)
        end
        table.sort(labels)
        lines[#lines + 1] = "buttons: " .. table.concat(labels, " | ")
        local cards = phoneCards(win)
        lines[#lines + 1] = string.format("offer cards: %d | floor %.3f", #cards, phoneFloor())
        for i, ci in ipairs(cards) do
            local o = readPhoneCard(ci.card)
            lines[#lines + 1] = string.format("  #%d %.3f | decline=%s | %s",
                i, o.theirValue or 0, ci.decline and "yes" or "no", shortList(o.theirs, 6))
        end
        lines[#lines + 1] = string.format("listings known: %d", #E.phone.listings)        for i, rec in ipairs(E.phone.listings) do
            lines[#lines + 1] = string.format("  #%d %s value %.3f ask %.3f", i, tostring(rec.item), rec.value or 0, rec.askV or 0)
        end
        lines[#lines + 1] = "next plan: " .. planNextListing()
        lines[#lines + 1] = string.format("learned: create=%s | next=%s | post=%s",
            (S.PhoneCreatePath ~= "" and S.PhoneCreatePath or "-"),
            (S.PhoneNextPath ~= "" and S.PhoneNextPath or "-"),
            (S.PhonePostPath ~= "" and S.PhonePostPath or "-"))
        local inv = inventorySnapshot()
        if inv then
            lines[#lines + 1] = string.format("inventory snapshot: %d stacks / %d items / %.3f (age %ds)",
                #inv.items, inv.count or 0, inv.total or 0, os.time() - (inv.at or 0))
        else
            lines[#lines + 1] = "inventory snapshot: none (press \"Scan inventory\")"
        end
    end
    local body = table.concat(lines, "\n")
    if writefile then pcall(writefile, BOT.Folder .. "/phone_dump.txt", body) end
    log("phone scan:\n%s", body)
    return body
end

--============================================================== 10. main loop
local cachedWindow = nil
local lastScan = 0

local function findWindowCached()
    local now = os.clock()
    if cachedWindow and not cachedWindow.Parent then
        cachedWindow = nil
    end
    if cachedWindow and isVisible(cachedWindow) then
        return cachedWindow
    end
    if now - lastScan < 1.0 then
        return cachedWindow
    end
    lastScan = now
    local win = findTradeWindow()
    cachedWindow = win
    return win
end

-- outgoing trade request loop (needs findWindowCached, so it lives here)
task.spawn(function()
    task.wait(5)
    while true do
        task.wait(2)
        local ok = pcall(function()
            if not S.Enabled or not S.AutoRequestTrades then return end
            if findWindowCached() then return end

            local targets = {}
            for line in (S.TradeTargetsText or ""):gmatch("[^\r\n]+") do
                local t = line:match("^%s*(.-)%s*$")
                if t ~= "" and t:sub(1, 1) ~= "#" then targets[#targets + 1] = t end
            end
            if #targets == 0 then return end

            E.requestIndex = ((E.requestIndex or 0) % #targets) + 1
            local name = targets[E.requestIndex]
            local sent = tryRequestTrade(name) or remoteRequestTrade(name)
            if sent then
                log("sent trade request to %s", name)
                E.state = "requested " .. name
                task.wait(S.RequestInterval or 8)
            end
        end)
        if not ok then log("request loop error") end
    end
end)

task.spawn(function()
    task.wait(2)
    while true do
        local ok, err = pcall(function()
            if not S.Enabled then
                E.state = "disabled"
                task.wait(0.5)
                return
            end

            local win = findWindowCached()
            if not win then
                if E.state ~= "idle" and not tostring(E.state):find("phone", 1, true) then
                    E.state = "idle"
                    E.lastSignature = nil
                    E.failed = {}
                    E.lastFill = nil
                end
                if S.PhoneEnabled then stepPhone() end
                task.wait(0.3)
                return
            end

            local kind = classifyWindow(win)
            if kind == "trade" then
                stepTradeWindow(win)
            elseif kind == "request" then
                stepRequestPopup(win)
            elseif kind == "phone" then
                if S.PhoneEnabled then stepPhone() end
            end
        end)
        if not ok then
            log("loop error: %s", tostring(err))
            if S.KiriaEnabled and webhookReady() and os.time() - kiriaWarnAt > 900 then
                kiriaWarnAt = os.time()
                task.spawn(function() sendKiriaCard("warning", {}, "Kiria needs help") end)
            end
        end
        task.wait(S.Delay or 0.45)
    end
end)

--============================================================== 11. debug tools
local function copyToClipboard(text)
    if type(text) ~= "string" or text == "" then return false end
    local fn = G("setclipboard") or G("toclipboard")
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn, text)
    return ok
end

local function copyFile(relPath)
    if not readfile then return false end
    local ok, body = pcall(readfile, BOT.Folder .. "/" .. relPath)
    if not ok or type(body) ~= "string" or body == "" then return false end
    if not copyToClipboard(body) then return false end
    notify("Clipboard", relPath .. " copied (" .. #body .. " bytes)", 4)
    return true
end

local function dumpGuiTree()
    local pg = getPlayerGui()
    if not pg or not writefile then return false end

    local lines = { "AdoptMe Trade Bot GUI dump " .. os.date("%Y-%m-%d %H:%M:%S") }
    local function walk(obj, depth)
        if depth > 9 then return end
        local label = obj.ClassName .. "  " .. obj.Name
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            local t = (obj.Text or ""):gsub("[\r\n]", " ")
            if t ~= "" then label = label .. '  text="' .. t:sub(1, 60) .. '"' end
        elseif obj:IsA("GuiObject") then
            label = label .. string.format("  [%dx%d] vis=%s",
                math.floor(obj.AbsoluteSize.X), math.floor(obj.AbsoluteSize.Y), tostring(obj.Visible))
        end
        lines[#lines + 1] = string.rep("  ", depth) .. label
        for _, child in ipairs(obj:GetChildren()) do
            walk(child, depth + 1)
        end
    end
    walk(pg, 0)

    local ok = pcall(writefile, BOT.GuiDumpFile, table.concat(lines, "\n"))
    if ok then
        log("gui dump written to %s (%d lines)", BOT.GuiDumpFile, #lines)
        notify("GUI dump", "Saved to " .. BOT.GuiDumpFile, 5)
    end
    return ok
end

-- every remote that could be trade/listing related, so we can stop guessing the UI
local function dumpRemotes()
    if not writefile then return false end
    local rs = game:GetService("ReplicatedStorage")
    local lines = { "Remote dump " .. os.date("%Y-%m-%d %H:%M:%S") }
    local function walk(obj, depth)
        if depth > 4 then return end
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("BindableEvent") then
            lines[#lines + 1] = string.rep("  ", depth) .. obj.ClassName .. "  " .. obj:GetFullName()
        end
        for _, c in ipairs(obj:GetChildren()) do walk(c, depth + 1) end
    end
    walk(rs, 0)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "all top-level ReplicatedStorage children:"
    for _, c in ipairs(rs:GetChildren()) do
        lines[#lines + 1] = "  " .. c.ClassName .. "  " .. c.Name
    end
    local body = table.concat(lines, "\n")
    local ok = pcall(writefile, BOT.Folder .. "/remotes.txt", body)
    if ok then
        log("remotes written to %s (%d lines)", BOT.Folder .. "/remotes.txt", #lines)
        notify("Remotes", "Saved to remotes.txt", 5)
    end
    return ok
end

-- records what YOU click, so the real listing flow can be mapped exactly
local clickLog = {}

local function describeClickObject(obj)
    local parts = {}
    local p, guard = obj, 0
    while p and p ~= game and guard < 8 do
        local label = p.Name
        local okText, text = pcall(function() return p.Text end)
        if okText and type(text) == "string" and text ~= "" then
            label = label .. '["' .. text:gsub("[\r\n]", " "):sub(1, 40) .. '"]'
        end
        table.insert(parts, 1, label)
        p = p.Parent
        guard += 1
    end
    return table.concat(parts, " > ")
end

local function recordClick(x, y)
    local pg = getPlayerGui()
    if not pg then return end
    local objs
    local ok = pcall(function() objs = pg:GetGuiObjectsAtPosition(x, y) end)
    if not ok or type(objs) ~= "table" or #objs == 0 then return end
    local names = {}
    for i = 1, math.min(#objs, 5) do
        local o = objs[i]
        if o:IsA("GuiObject") and isVisible(o) then
            names[#names + 1] = describeClickObject(o)
        end
    end
    if #names == 0 then return end
    local line = string.format("%s  (%d,%d)  %s", os.date("%H:%M:%S"),
        math.floor(x), math.floor(y), table.concat(names, " ;; "))
    clickLog[#clickLog + 1] = line
    if #clickLog > 300 then table.remove(clickLog, 1) end
    log("click: %s", line)
    if writefile then pcall(writefile, BOT.Folder .. "/clicks.txt", table.concat(clickLog, "\n")) end
end

local function startClickRecorder()
    local UIS = game:GetService("UserInputService")
    UIS.InputBegan:Connect(function(input)
        if not S.ClickRecorder then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            task.spawn(function() recordClick(input.Position.X, input.Position.Y) end)
        end
    end)
end

local function scanNow()
    local win = findTradeWindow()
    cachedWindow = win
    lastScan = os.clock()
    if not win then
        log("scan: no trade / request window found")
        notify("Scan", "No trade window found", 3)
        return
    end
    local kind = classifyWindow(win)
    local offer = readOffers(win)
    log("scan: %s window, theirs=%.3f ours=%.3f, %d unpriced",
        kind, offer.theirValue, offer.ourValue, #offer.unknown)
    notify("Scan", string.format("%s window | %.3f / %.3f", kind, offer.theirValue, offer.ourValue), 5)
end

--============================================================== 12. ui
local COLOR = {
    bg      = Color3.fromRGB(22, 22, 26),
    panel   = Color3.fromRGB(30, 30, 36),
    row     = Color3.fromRGB(38, 38, 46),
    text    = Color3.fromRGB(235, 235, 240),
    dim     = Color3.fromRGB(150, 150, 160),
    accent  = Color3.fromRGB(88, 166, 255),
    good    = Color3.fromRGB(70, 190, 120),
    off     = Color3.fromRGB(70, 70, 80),
}

local function new(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do obj[k] = v end
    if parent then obj.Parent = parent end
    return obj
end

local UI = {}

local function buildUI()
    local pg = getPlayerGui()
    if not pg then return end
    if UI.gui then UI.gui:Destroy() end

    local gui = new("ScreenGui", {
        Name = "AdoptMeTradeBotUI",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 999,
    }, pg)
    UI.gui = gui

    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.new(0, 330, 0, 470),
        Position = UDim2.new(0, 24, 0, 90),
        BackgroundColor3 = COLOR.bg,
        BorderSizePixel = 0,
        Active = true,
    }, gui)
    new("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
    new("UIStroke", { Color = Color3.fromRGB(60, 60, 70), Thickness = 1 }, main)

    local header = new("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COLOR.panel,
        BorderSizePixel = 0,
        Active = true,
    }, main)
    new("UICorner", { CornerRadius = UDim.new(0, 10) }, header)

    new("TextLabel", {
        Size = UDim2.new(1, -80, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = "AdoptMe Trade Bot  v" .. BOT.Version,
        TextColor3 = COLOR.text,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)

    local minimize = new("TextButton", {
        Size = UDim2.new(0, 26, 0, 26),
        Position = UDim2.new(1, -66, 0, 5),
        BackgroundColor3 = COLOR.row,
        Text = "",
        TextColor3 = COLOR.text,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        BorderSizePixel = 0,
        AutoButtonColor = true,
    }, header)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, minimize)

    local close = new("TextButton", {
        Size = UDim2.new(0, 26, 0, 26),
        Position = UDim2.new(1, -34, 0, 5),
        BackgroundColor3 = COLOR.row,
        Text = "x",
        TextColor3 = COLOR.text,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        BorderSizePixel = 0,
    }, header)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, close)
    close.MouseButton1Click:Connect(function() gui.Enabled = false end)

    local body = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -36),
        Position = UDim2.new(0, 0, 0, 36),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, main)

    local layout = new("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, body)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, body)

    local order = 0
    local function nextOrder() order += 1; return order end

    local function section(text)
        local lbl = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Text = text:upper(),
            TextColor3 = COLOR.dim,
            TextSize = 11,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = nextOrder(),
        }, body)
        return lbl
    end

    local function toggle(key, label)
        local row = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = COLOR.row,
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            LayoutOrder = nextOrder(),
        }, body)
        new("UICorner", { CornerRadius = UDim.new(0, 6) }, row)

        new("TextLabel", {
            Size = UDim2.new(1, -56, 1, 0),
            Position = UDim2.new(0, 8, 0, 0),
            BackgroundTransparency = 1,
            Text = label,
            TextColor3 = COLOR.text,
            TextSize = 12,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        local track = new("Frame", {
            Size = UDim2.new(0, 32, 0, 16),
            Position = UDim2.new(1, -40, 0.5, -8),
            BackgroundColor3 = COLOR.off,
            BorderSizePixel = 0,
        }, row)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

        local knob = new("Frame", {
            Size = UDim2.new(0, 12, 0, 12),
            Position = UDim2.new(0, 2, 0.5, -6),
            BackgroundColor3 = COLOR.text,
            BorderSizePixel = 0,
        }, track)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

        local function render()
            local on = S[key] and true or false
            track.BackgroundColor3 = on and COLOR.good or COLOR.off
            knob.Position = UDim2.new(0, on and 18 or 2, 0.5, -6)
        end
        row.MouseButton1Click:Connect(function()
            S[key] = not S[key]
            render()
            saveSettings()
        end)
        render()
        return row
    end

    local function input(key, label, numeric)
        local holder = new("Frame", {
            Size = UDim2.new(1, 0, 0, 48),
            BackgroundColor3 = COLOR.row,
            BorderSizePixel = 0,
            LayoutOrder = nextOrder(),
        }, body)
        new("UICorner", { CornerRadius = UDim.new(0, 6) }, holder)

        new("TextLabel", {
            Size = UDim2.new(1, -16, 0, 18),
            Position = UDim2.new(0, 8, 0, 2),
            BackgroundTransparency = 1,
            Text = label,
            TextColor3 = COLOR.dim,
            TextSize = 11,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, holder)

        local box = new("TextBox", {
            Size = UDim2.new(1, -16, 0, 22),
            Position = UDim2.new(0, 8, 0, 21),
            BackgroundColor3 = COLOR.bg,
            Text = tostring(S[key] or ""),
            TextColor3 = COLOR.text,
            TextSize = 12,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
            BorderSizePixel = 0,
        }, holder)
        new("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
        new("UIPadding", { PaddingLeft = UDim.new(0, 6) }, box)

        box.FocusLost:Connect(function()
            if numeric then
                S[key] = tonumber(box.Text) or DEFAULT_SETTINGS[key]
                box.Text = tostring(S[key])
            else
                S[key] = box.Text
            end
            saveSettings()
        end)
        return holder
    end

    local function multiline(key, label, height)
        local holder = new("Frame", {
            Size = UDim2.new(1, 0, 0, height or 84),
            BackgroundColor3 = COLOR.row,
            BorderSizePixel = 0,
            LayoutOrder = nextOrder(),
        }, body)
        new("UICorner", { CornerRadius = UDim.new(0, 6) }, holder)

        new("TextLabel", {
            Size = UDim2.new(1, -16, 0, 18),
            Position = UDim2.new(0, 8, 0, 2),
            BackgroundTransparency = 1,
            Text = label,
            TextColor3 = COLOR.dim,
            TextSize = 11,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, holder)

        local box = new("TextBox", {
            Size = UDim2.new(1, -16, 0, (height or 84) - 24),
            Position = UDim2.new(0, 8, 0, 20),
            BackgroundColor3 = COLOR.bg,
            Text = tostring(S[key] or ""),
            TextColor3 = COLOR.text,
            TextSize = 11,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            MultiLine = true,
            ClearTextOnFocus = false,
            BorderSizePixel = 0,
        }, holder)
        new("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
        new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 4) }, box)

        box.FocusLost:Connect(function()
            S[key] = box.Text
            rebuildAliases()
            saveSettings()
        end)
        return holder
    end

    local function button(text, callback)
        local btn = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = COLOR.accent,
            Text = text,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 12,
            Font = Enum.Font.GothamBold,
            BorderSizePixel = 0,
            LayoutOrder = nextOrder(),
        }, body)
        new("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
        btn.MouseButton1Click:Connect(function()
            local ok, err = pcall(callback)
            if not ok then log("ui error: %s", tostring(err)) end
        end)
        return btn
    end

    -- ===================== content
    section("Core")
    toggle("Enabled", "Bot enabled")
    toggle("AutoAcceptRequests", "Auto-accept trade requests")
    toggle("AutoAcceptOffers", "Auto-accept good offers")
    toggle("AutoRequestTrades", "Send trade requests to targets")
    input("RequestInterval", "Seconds between outgoing requests", true)
    toggle("UseRemoteFallback", "Remote fallback for requests (risky)")

    section("Offer rules")
    input("MinAcceptRatio", "Min ratio (accept when theirs >= yours * X)", true)
    input("MaxAcceptRatio", "Max ratio (bait guard)", true)
    input("MinOfferValue", "Min offer value", true)
    toggle("RequireKnownValue", "Skip offers with unpriced items")
    toggle("RequireWantedItem", "Only accept wanted items")
    toggle("AutoDeclineBad", "Auto-decline bad offers")
    toggle("ConfirmAccepts", "Click the confirm step")

    section("Your side")
    toggle("AutoFill", "Auto-add items from inventory")
    input("FillMode", "Fill mode: profit / fair / manual", false)
    input("MaxItemsToGive", "Max items to give", true)
    toggle("NeverGiveLastPet", "Never give your only copy of a pet")
    input("FlyMult", "Fly multiplier", true)
    input("RideMult", "Ride multiplier", true)
    input("NeonMult", "Neon multiplier", true)
    input("MegaMult", "Mega multiplier", true)

    section("Discord")
    input("WebhookUrl", "Webhook URL", false)
    input("WebhookMention", "Mention user id (optional)", false)
    toggle("NotifyAllOffers", "Post every offer")
    toggle("NotifyAccepted", "Post accepted trades")
    toggle("NotifyDeclined", "Post declined trades")
    toggle("KiriaEnabled", "Kiria persona in messages")
    input("KiriaUrl", "Kiria module URL", false)

    section("Trading Hub phone")
    toggle("PhoneEnabled", "Use the trade phone (listings + offers)")
    toggle("PhoneDryRun", "Dry run (only log, never click)")
    toggle("PhoneAutoOpen", "Open the phone toy myself")
    toggle("PhoneAutoAcceptOffers", "Accept good offers on my listings")
    toggle("PhoneAutoDeclineBad", "Decline weak offers")
    toggle("PhoneOfferSwap", "Drop the weakest offer over the cap")
    toggle("PhoneAutoList", "Post listings (100 bucks each)")
    toggle("PhoneScanInventory", "Read my inventory before posting")
    toggle("PhoneAutoLearn", "Auto-dump the phone UI (self-learning)")
    toggle("PhoneAutoOffer", "Search listings and send offers")
    input("PhoneOfferEvery", "Search listings every N seconds", true)
    toggle("PhoneAutoTravel", "Travel to the Hub myself")
    input("PhoneInvMaxAge", "Rescan inventory after N seconds", true)
    input("PhoneInvPasses", "Inventory scan passes (scroll pages)", true)
    input("PhoneUpgradeSteps", "Upgrade chain depth", true)
    input("PhoneListedValue", "Value of a listing I posted by hand (0 = off)", true)
    input("PhoneMinOfferValue", "Or accept offers worth at least (0 = off)", true)
    input("PhoneUpgradeMinPct", "Ask listing: min gain %", true)
    input("PhoneUpgradeMaxPct", "Ask listing: max gain % (guardrails)", true)
    input("PhoneBucksMax", "Bucks budget per session (0 = no limit)", true)
    input("PhoneGiveMinValue", "Never list anything cheaper than", true)
    toggle("PhoneDuplicatesOnly", "Only list pets I own 2+ of")
    input("PhoneMaxListings", "Max listings", true)
    input("PhoneMaxOffers", "Max waiting offers", true)
    input("PhoneRefreshMin", "Take a listing down after N minutes", true)

    section("Lists")
    multiline("TradeTargetsText", "Trade request targets (usernames, one per line)", 62)
    multiline("TradePoolText", "Allowed to give (one per line, empty = all)", 78)
    multiline("KeepListText", "Never give (one per line)", 62)
    multiline("WantedText", "Wanted items (one per line)", 62)
    multiline("AliasText", "Aliases: in-game name = amvgg name", 62)

    section("Advanced")
    toggle("OurSideIsLeft", "Your offer is on the left")
    input("Delay", "Loop delay (seconds)", true)
    input("ToggleKey", "Toggle key (e.g. RightControl)", false)
    toggle("Debug", "Verbose log")
    toggle("ClickRecorder", "Record my clicks (map the real UI)")

    section("Tools")
    button("Test webhook", function()
        sendOfferWebhook({
            theirs = { { name = "Bat Dragon", value = 5.53, flags = { fly = true, ride = true } } },
            ours = { { name = "Frost Dragon", value = 1.76, flags = {} } },
            theirValue = 5.53,
            ourValue = 1.76,
            unknown = {},
        }, "new", "test message")
        notify("Webhook", "Test message queued", 3)
    end)

    button("Test Kiria card", function()
        task.spawn(function()
            if not loadKiria() then
                notify("Kiria", "Module not loaded - see the log", 4)
                return
            end
            local ok = sendKiriaCard("win", {
                dry = true,
                pct = 35,
                gain = 1.2,
                give = "Owl",
                get = "Shadow Dragon",
                n = 1,
            }, "Kiria (test)")
            notify("Kiria", ok and "Card queued" or "Set the webhook URL first", 3)
        end)
    end)

    button("Session progress card", function()
        task.spawn(function()
            local ok = sendSessionCard("Session progress")
            notify("Kiria", ok and "Progress card queued" or "Set the webhook URL first", 3)
        end)
    end)

    button("Scan inventory", function()
        task.spawn(function()
            if scanInventoryNow() then notify("Inventory", "Saved to inventory_dump.txt", 4) end
        end)
    end)
    button("Plan upgrade chain", function()
        task.spawn(function()
            if not inventorySnapshot() then scanInventoryNow() end
            local plan = planNextListing()
            log("upgrade chain: %s", plan)
            notify("Upgrade chain", plan:sub(1, 120), 8)
        end)
    end)

    button("Search & offer now", function()
        task.spawn(function()
            local inv = inventorySnapshot()
            if not inv then scanInventoryNow() end
            local plan = planUpgrades(E.inv.items, 1)
            if not plan[1] then
                notify("Offer", "no upgrade plan (check duplicates only / min value)", 6)
                return
            end
            local step = plan[1]
            local ok, why = searchAndOffer(step.give, step.want)
            notify("Offer", ok and string.format("sent: %s -> %s", step.give, step.want) or tostring(why), 6)
        end)
    end)

    button("Plan next listing", function()
        local plan = planNextListing()
        log("phone plan: %s", plan)
        notify("Next listing", plan:sub(1, 120), 6)
    end)

    button("Scan trade window", scanNow)
    button("Scan trade phone", function()
        local body = scanPhone()
        notify("Trade phone", #body > 0 and "Saved to phone_dump.txt" or "Nothing found", 3)
    end)
    button("Open trade phone", function()
        task.spawn(function()
            if phoneClickToy() then notify("Trade phone", "Phone used", 3)
            else notify("Trade phone", "Toy not found or dry run", 3) end
        end)
    end)
    button("Dump GUI tree to file", dumpGuiTree)
    button("Learn phone UI now", function()
        local win = findPhoneWindow()
        local root = (win and uiRoot(win)) or getPlayerGui()
        if not root then notify("Learn", "no player GUI", 4) return end
        local buttons = learnDump("manual", root)
        notify("Learn", string.format("%d buttons saved to auto_face_manual.txt", buttons and #buttons or 0), 5)
    end)
    button("Copy clicks.txt", function()
        if not copyFile("clicks.txt") then
            notify("Clipboard", "clicks.txt is empty: turn on Record my clicks first", 5)
        end
    end)
    button("Copy log.txt", function()
        if not copyFile("log.txt") then notify("Clipboard", "log.txt is empty", 4) end
    end)
    button("Dump remotes to file", function()
        if dumpRemotes() then notify("Remotes", "Saved to remotes.txt", 4) end
    end)
    button("Copy remotes.txt", function()
        if not copyFile("remotes.txt") then notify("Clipboard", "press Dump remotes first", 4) end
    end)
    button("Copy inventory_dump.txt", function()
        if not copyFile("inventory_dump.txt") then notify("Clipboard", "press Scan inventory first", 4) end
    end)
    button("Update values from amvgg.com", function()
        task.spawn(function() updateValuesFromWeb(false) end)
    end)

    section("Status")
    local status = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 74),
        BackgroundColor3 = COLOR.row,
        Text = "",
        TextColor3 = COLOR.text,
        TextSize = 11,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, body)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, status)
    new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 4) }, status)
    UI.status = status

    task.spawn(function()
        while UI.status and UI.status.Parent do
            UI.status.Text = string.format(
                "state: %s\n%s\naccepted %d | declined %d | offers %d\nnet %+.2f (%+.1f%%) | %d values",
                tostring(E.state), tostring(E.lastSummary),
                E.stats.accepted, E.stats.declined, E.stats.offers,
                sessionProfit(), select(2, sessionProfit()), countValues())
            task.wait(0.6)
        end
    end)

    -- dragging
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = inp.Position
            startPos = main.Position
        end
    end)
    header.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch) then
            local delta = inp.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    local minimized = false
    minimize.MouseButton1Click:Connect(function()
        minimized = not minimized
        body.Visible = not minimized
        main.Size = minimized and UDim2.new(0, 330, 0, 36) or UDim2.new(0, 330, 0, 470)
        minimize.Text = minimized and "+" or "-"
    end)

    return gui
end

--============================================================== 13. keybind
local function bindKey()
    local name = tostring(S.ToggleKey or "")
    if name == "" then return end

    local keyCode = Enum.KeyCode[name]
    if not keyCode then
        local compact = name:gsub("[%s_%-]", ""):lower()
        for _, kc in ipairs(Enum.KeyCode:GetEnumItems()) do
            if kc.Name:lower() == compact then
                keyCode = kc
                break
            end
        end
    end
    if not keyCode or keyCode == Enum.KeyCode.Unknown then return end

    UserInputService.InputBegan:Connect(function(inp, processed)
        if processed then return end
        if inp.KeyCode == keyCode then
            S.Enabled = not S.Enabled
            saveSettings()
            notify("AdoptMe Trade Bot", S.Enabled and "Enabled" or "Disabled", 2)
            if UI.gui then
                UI.gui.Enabled = true
            end
        end
    end)
end

--============================================================== 14. startup
local function ensureFolder()
    if not (isfolder and makefolder) then
        BOT.FolderReady = false
        return
    end
    local ok, exists = pcall(isfolder, BOT.Folder)
    if not ok or not exists then
        pcall(makefolder, BOT.Folder)
    end
    BOT.FolderReady = true
end

local function fail(err)
    local text = string.format("AdoptMe Trade Bot v%s startup error\n%s\n\n%s",
        BOT.Version, tostring(err), debug.traceback())
    if writefile and BOT.FolderReady then
        pcall(writefile, BOT.ErrorFile, text)
    end
    pcall(function() warn("[AdoptMeTradeBot] " .. tostring(err)) end)
end

local ok, err = pcall(function()
    ensureFolder()
    loadSettings()
    rebuildAliases()
    loadValues()

    if writefile then
        pcall(writefile, BOT.ErrorFile, "started " .. os.date("%Y-%m-%d %H:%M:%S"))
    end

    getgenv().AdoptMeTradeBot = BOT
    BOT.settings = S
    BOT.save = saveSettings
    BOT.updateValues = updateValuesFromWeb
    BOT.scanNow = scanNow
    BOT.dumpGui = dumpGuiTree
    BOT.loadKiria = loadKiria
    BOT.kiriaReact = kiriaReact
    BOT.sendSessionCard = sendSessionCard
    BOT.sessionProfit = sessionProfit
    BOT.scanPhone = scanPhone
    BOT.stepPhone = stepPhone
    BOT.planNextListing = planNextListing
    BOT.scanInventory = scanInventoryNow
    BOT.planUpgrades = planUpgrades
    BOT.inventory = E.inv
    BOT.dumpRemotes = dumpRemotes
    BOT.learnDump = learnDump
    BOT.searchAndOffer = searchAndOffer
    BOT.travelToHub = travelToHub
    BOT.phone = E.phone
    BOT.api = {
        getSettings = function() return S end,
        setSetting = function(key, value) S[key] = value; saveSettings() end,
        evaluate = function()
            local win = findTradeWindow()
            if not win then return nil end
            local offer = readOffers(win)
            return offer, decide(offer)
        end,
        valueOf = function(name)
            local e = lookupValue(name)
            if not e then return nil end
            return itemValue(e, {})
        end,
    }

    buildUI()
    bindKey()
    startClickRecorder()

    log("AdoptMe Trade Bot v%s loaded | %d values", BOT.Version, countValues())
    notify("Adopt Me Trade Bot", "Loaded - " .. countValues() .. " prices", 4)

    -- Kiria says hello once per session (needs the webhook; loads in the background)
    task.spawn(function()
        if not loadKiria() then return end
        sendKiriaCard("start", {
            dry = not S.Enabled,
            minPct = math.max(0, math.floor(((S.MinAcceptRatio or 1) - 1) * 100 + 0.5)),
        }, "Kiria online")
    end)
end)

if not ok then fail(err) end
