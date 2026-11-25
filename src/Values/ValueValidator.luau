--!strict
--[[
	ValueValidator.luau
	Validates and normalizes raw AMVGG pet records into a consistent internal schema.
	Never invents or fabricates missing/zero/invalid values.
]]

local ValueValidator = {}

export type PetRecord = {
	id: string,
	name: string,
	key: string,
	origin: string,
	category: number?,
	lastUpdatedAt: string?,
	values: {
		regular: number?,
		npRegular: number?,
		r: number?,
		f: number?,
		neon: number?,
		npNeon: number?,
		nr: number?,
		nf: number?,
		mega: number?,
		npMega: number?,
		mr: number?,
		mf: number?,
	},
	demands: {
		regular: string?,
		npRegular: string?,
		r: string?,
		f: string?,
		neon: string?,
		npNeon: string?,
		nr: string?,
		nf: string?,
		mega: string?,
		npMega: string?,
		mr: string?,
		mf: string?,
	},
	source: string,
	validatedAt: number,
}

export type ValidationSummary = {
	records: { [string]: PetRecord },
	ordered: { PetRecord },
	totalInput: number,
	validCount: number,
	rejectedCount: number,
	invalidFieldCount: number,
}

local VALUE_FIELDS = {
	regular = "regularValue",
	npRegular = "npRegularValue",
	r = "rValue",
	f = "fValue",
	neon = "neonValue",
	npNeon = "npNeonValue",
	nr = "nrValue",
	nf = "nfValue",
	mega = "megaValue",
	npMega = "npMegaValue",
	mr = "mrValue",
	mf = "mfValue",
}

local DEMAND_FIELDS = {
	regular = "regularDemand",
	npRegular = "npRegularDemand",
	r = "rDemand",
	f = "fDemand",
	neon = "neonDemand",
	npNeon = "npNeonDemand",
	nr = "nrDemand",
	nf = "nfDemand",
	mega = "megaDemand",
	npMega = "npMegaDemand",
	mr = "mrDemand",
	mf = "mfDemand",
}

function ValueValidator.normalizeKey(name: string): string
	local trimmed = tostring(name or ""):match("^%s*(.-)%s*$") or ""
	return string.lower(trimmed):gsub("%s+", " ")
end

local function parsePositiveNumber(raw: any): (number?, boolean)
	if raw == nil or raw == "" then
		return nil, false
	end
	local num = tonumber(raw)
	if num == nil or num ~= num or num == math.huge or num == -math.huge or num <= 0 then
		return nil, true -- invalid/zero value
	end
	return num, false
end

local function cleanTimestamp(raw: any): string?
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	-- Next.js RSC encodes dates as "$D2026-11-23T13:26:04.111Z"
	if string.sub(raw, 1, 2) == "$D" then
		return string.sub(raw, 3)
	end
	return raw
end

function ValueValidator.validateRecord(raw: any, nowTimestamp: number?): (PetRecord?, number)
	if type(raw) ~= "table" then
		return nil, 1
	end
	local name = type(raw.name) == "string" and (raw.name:match("^%s*(.-)%s*$") or "") or ""
	if name == "" then
		return nil, 1
	end

	local values: { [string]: number? } = {}
	local demands: { [string]: string? } = {}
	local invalidFields = 0
	local hasAnyValidValue = false

	-- Support both raw AMVGG fields (`regularValue`) and already-normalized cached records (`values.regular`)
	if type(raw.values) == "table" then
		for k in pairs(VALUE_FIELDS) do
			local num, isInvalid = parsePositiveNumber(raw.values[k])
			if isInvalid then
				invalidFields += 1
			elseif num then
				values[k] = num
				hasAnyValidValue = true
			end
		end
	else
		for k, srcKey in pairs(VALUE_FIELDS) do
			local num, isInvalid = parsePositiveNumber(raw[srcKey])
			if isInvalid then
				invalidFields += 1
			elseif num then
				values[k] = num
				hasAnyValidValue = true
			end
		end
	end

	if not hasAnyValidValue then
		return nil, math.max(1, invalidFields)
	end

	if type(raw.demands) == "table" then
		for k in pairs(DEMAND_FIELDS) do
			if type(raw.demands[k]) == "string" and raw.demands[k] ~= "" then
				demands[k] = raw.demands[k]
			end
		end
	else
		for k, srcKey in pairs(DEMAND_FIELDS) do
			if type(raw[srcKey]) == "string" and raw[srcKey] ~= "" then
				demands[k] = raw[srcKey]
			end
		end
	end

	local record: PetRecord = {
		id = tostring(raw.id or ValueValidator.normalizeKey(name)),
		name = name,
		key = ValueValidator.normalizeKey(name),
		origin = type(raw.origin) == "string" and raw.origin or "Unknown",
		category = tonumber(raw.category),
		lastUpdatedAt = cleanTimestamp(raw.lastUpdatedAt),
		values = values :: any,
		demands = demands :: any,
		source = "AMVGG",
		validatedAt = nowTimestamp or os.time(),
	}

	return record, invalidFields
end

function ValueValidator.validateDataset(rawList: { any }, nowTimestamp: number?): ValidationSummary
	local records: { [string]: PetRecord } = {}
	local ordered: { PetRecord } = {}
	local validCount = 0
	local rejectedCount = 0
	local invalidFieldCount = 0
	local ts = nowTimestamp or os.time()

	if type(rawList) ~= "table" then
		return {
			records = records,
			ordered = ordered,
			totalInput = 0,
			validCount = 0,
			rejectedCount = 0,
			invalidFieldCount = 0,
		}
	end

	for _, item in ipairs(rawList) do
		local rec, badFields = ValueValidator.validateRecord(item, ts)
		invalidFieldCount += badFields
		if rec then
			if not records[rec.key] then
				table.insert(ordered, rec)
				validCount += 1
			end
			records[rec.key] = rec
		else
			rejectedCount += 1
		end
	end

	table.sort(ordered, function(a, b)
		local va = a.values.regular or a.values.npRegular or a.values.neon or 0
		local vb = b.values.regular or b.values.npRegular or b.values.neon or 0
		if va ~= vb then
			return va > vb
		end
		return a.name < b.name
	end)

	return {
		records = records,
		ordered = ordered,
		totalInput = #rawList,
		validCount = validCount,
		rejectedCount = rejectedCount,
		invalidFieldCount = invalidFieldCount,
	}
end

return ValueValidator
