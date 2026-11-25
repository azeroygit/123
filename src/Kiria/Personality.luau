--!strict
--[[
	Personality.luau
	Kiria's voice, rank ladder, moods, and template formatter.
	Honest, calm, and never fabricates trade results.
]]

local Personality = {}

Personality.Name = "Kiria"
Personality.Title = "Kirito's Lost Fragment"

Personality.Ranks = {
	{ xp = 0, title = "Intern" },
	{ xp = 100, title = "Junior Analyst" },
	{ xp = 300, title = "Analyst" },
	{ xp = 700, title = "Trader" },
	{ xp = 1500, title = "Senior Trader" },
	{ xp = 3000, title = "Head of Trading" },
	{ xp = 6000, title = "Chief Trading Officer" },
	{ xp = 12000, title = "Kirito-Tier" },
}

Personality.Lines = {
	hello = {
		night = {
			"It's late. I'll watch the AMVGG values quietly while you review.",
			"Night shift! Fewer traders are online, so we can be extra picky.",
		},
		morning = {
			"Good morning! I'm at the Trade Hub terminal and ready to start.",
			"Morning! Let's check AMVGG values and see what opportunities appear.",
		},
		day = {
			"Hi! I'm ready at the Trade Hub terminal.",
			"Hello again! I'm watching AMVGG values and waiting for solid deals.",
		},
		evening = {
			"Good evening! Many traders are online now, so let's watch for good deals.",
			"Evening! Let's review listings carefully before the day ends.",
		},
	},
	returning = {
		"Session #{sessions}. Together we've confirmed {trades} {trades:trade|trades} so far.",
		"Day {days} together. {trades} confirmed {trades:trade|trades}, and I never invent results.",
	},
	intro = {
		"I'm Kiria, Kirito's lost fragment. I'll evaluate AMVGG values and guide your trades — you always have final confirmation.",
	},
	amvgg_refresh = {
		"AMVGG values refreshed: {petCount} pets verified from amvgg.com.",
	},
	amvgg_error = {
		"AMVGG refresh hit an issue ({error}). I preserved our last valid cache so nothing breaks.",
		"Couldn't reach live AMVGG ({error}). No live values will be faked.",
	},
	good_deal = {
		"Spotted a good deal on {items}: +{pct}% (+{gain} AMVGG). Worth a look.",
		"Nice opportunity: {items} is +{pct}% on AMVGG. Review it when you're ready.",
	},
	bad_offer = {
		"Careful: that offer is {pct}% behind ({gain} AMVGG). I'd pass on this one.",
	},
	trade_confirmed = {
		"Confirmed trade: gave {give} for {get} (+{pct}%, +{gain} AMVGG). Realized profit updated!",
		"Nice! {give} became {get} (+{pct}%). Confirmed profit is now tracked.",
	},
	loss_trade = {
		"That confirmed trade came out behind ({gain} AMVGG). I've logged it honestly.",
	},
	offer_queued = {
		"Offer queued for review (+{pct}% AMVGG). Nothing is finalized until you confirm.",
	},
	offer_declined = {
		"An offer was declined. That's normal at the Trade Hub — one good yes beats many no's.",
	},
	offer_expired = {
		"An offer expired with no response, freeing those pets for new candidates.",
	},
	listing_published = {
		"Listing published ({offeredValue} AMVGG). I'll watch its age and alert you if it goes stale.",
	},
	listing_stale = {
		"A listing went stale after {age}s without a match. You can refresh or cancel it when ready.",
	},
	incomplete_data = {
		"Some items are missing verified AMVGG values, so I marked them INCOMPLETE instead of guessing.",
	},
	warning = {
		"Heads up: {message}",
	},
	promotion = {
		"I reached {rank}! Thank you for trading carefully with me.",
	},
}

local MONEY_KEYS = { gain = true, total = true, offeredValue = true, receivedValue = true }
local PCT_KEYS = { pct = true, rate = true }

function Personality.getRank(xp: number): string
	local current = Personality.Ranks[1].title
	for _, r in ipairs(Personality.Ranks) do
		if xp >= r.xp then
			current = r.title
		end
	end
	return current
end

function Personality.formatLine(template: string, ctx: { [string]: any }): string?
	if type(template) ~= "string" then
		return nil
	end
	local missing = false

	local out = string.gsub(template, "{(%w+):([^|}]*)|([^}]*)}", function(k, one, many)
		local v = tonumber(ctx[k])
		if v == nil then
			missing = true
			return ""
		end
		return if v == 1 then one else many
	end)

	out = string.gsub(out, "{(%w+)}", function(k)
		local v = ctx[k]
		if v == nil or v == "" then
			missing = true
			return ""
		end
		if PCT_KEYS[k] and tonumber(v) then
			local a = math.abs(tonumber(v) :: number)
			return string.format(if a < 10 then "%.1f" else "%.0f", a)
		end
		if MONEY_KEYS[k] and tonumber(v) then
			return string.format("%.2f", tonumber(v) :: number)
		end
		return tostring(v)
	end)

	if missing then
		return nil
	end
	return out
end

function Personality.pickLine(list: { string }?, ctx: { [string]: any }): string?
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local valid = {}
	for _, tpl in ipairs(list) do
		local formatted = Personality.formatLine(tpl, ctx)
		if formatted then
			table.insert(valid, formatted)
		end
	end
	if #valid == 0 then
		return nil
	end
	return valid[math.random(1, #valid)]
end

return Personality
