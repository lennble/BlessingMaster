-- BlessingMaster: Profiles.lua
-- Per-encounter presets (priorities, roles, exclusions) + export/import strings.

local BM = _G.BlessingMaster
BM.Profiles = {}
local P = BM.Profiles

local function newProfile(name)
	return {
		name = name,
		-- class -> blessing key, used when a member has no explicit role/override
		classBlessing = {
			WARRIOR = "MIGHT", ROGUE = "MIGHT", HUNTER = "MIGHT", PALADIN = "MIGHT",
			SHAMAN = "WISDOM", DRUID = "WISDOM", PRIEST = "WISDOM", MAGE = "WISDOM", WARLOCK = "WISDOM",
		},
		-- role -> blessing key, takes priority over classBlessing when a role is set
		roleBlessing = {
			MELEE = "MIGHT",
			CASTER = "WISDOM",
			HEALER = "WISDOM",
			TANK = "KINGS",
		},
		kingsForEveryoneElse = true, -- once Might/Wisdom/Salvation needs are met, spread Kings
		roleOverrides = {},   -- [name] = "TANK"/"HEALER"/"MELEE"/"CASTER"
		forcedBlessing = {},    -- [name] = blessingKey, hard pin
		exclusions = {},         -- [name] = true
	}
end

function P:EnsureDefault()
	local db = BM.db
	if not db.profiles["Default"] then
		db.profiles["Default"] = newProfile("Default")
	end
	if not db.profiles[db.activeProfile] then
		db.activeProfile = "Default"
	end
end

function P:Get()
	self:EnsureDefault()
	return BM.db.profiles[BM.db.activeProfile]
end

function P:List()
	self:EnsureDefault()
	local names = {}
	for name in pairs(BM.db.profiles) do table.insert(names, name) end
	table.sort(names)
	return names
end

function P:Create(name)
	if not name or name == "" then return false, "invalid name" end
	if BM.db.profiles[name] then return false, "already exists" end
	BM.db.profiles[name] = newProfile(name)
	BM:Fire("PROFILE_LIST_CHANGED")
	return true
end

function P:CreateFromCurrent(name)
	if not name or name == "" then return false, "invalid name" end
	if BM.db.profiles[name] then return false, "already exists" end
	local cur = self:Get()
	local copy = newProfile(name)
	for k, v in pairs(cur) do
		if type(v) == "table" then
			copy[k] = CopyTable and CopyTable(v) or v
			-- fallback shallow-deep copy without relying on CopyTable existing
			local t = {}
			for kk, vv in pairs(v) do t[kk] = vv end
			copy[k] = t
		elseif k ~= "name" then
			copy[k] = v
		end
	end
	BM.db.profiles[name] = copy
	BM:Fire("PROFILE_LIST_CHANGED")
	return true
end

function P:Delete(name)
	if name == "Default" then return false, "cannot delete Default" end
	if not BM.db.profiles[name] then return false, "not found" end
	BM.db.profiles[name] = nil
	if BM.db.activeProfile == name then
		BM.db.activeProfile = "Default"
	end
	BM:Fire("PROFILE_LIST_CHANGED")
	return true
end

function P:SetActive(name)
	if not BM.db.profiles[name] then return false end
	BM.db.activeProfile = name
	BM:Fire("PROFILE_CHANGED", name)
	BM:Fire("REQUEST_RECALC")
	return true
end

function P:SetExcluded(name, excluded)
	local prof = self:Get()
	if excluded then
		prof.exclusions[name] = true
	else
		prof.exclusions[name] = nil
	end
	BM:Fire("REQUEST_RECALC")
end

function P:IsExcluded(name)
	return self:Get().exclusions[name] == true
end

function P:SetRole(name, role)
	local prof = self:Get()
	prof.roleOverrides[name] = role
	BM:Fire("REQUEST_RECALC")
end

function P:SetForcedBlessing(name, blessingKey)
	local prof = self:Get()
	prof.forcedBlessing[name] = blessingKey
	BM:Fire("REQUEST_RECALC")
end

-- ---------------------------------------------------------------------------
-- Export / Import (WeakAuras-style copy/paste string)
-- ---------------------------------------------------------------------------

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64Encode(data)
	local out = {}
	local len = #data
	local i = 1
	while i <= len do
		local b1, b2, b3 = data:byte(i, i + 2)
		b2 = b2 or 0
		b3 = b3 or 0
		local n = b1 * 65536 + b2 * 256 + b3
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		local rem = len - i + 1
		out[#out + 1] = B64_CHARS:sub(c1 + 1, c1 + 1)
		out[#out + 1] = B64_CHARS:sub(c2 + 1, c2 + 1)
		out[#out + 1] = (rem >= 2) and B64_CHARS:sub(c3 + 1, c3 + 1) or "="
		out[#out + 1] = (rem >= 3) and B64_CHARS:sub(c4 + 1, c4 + 1) or "="
		i = i + 3
	end
	return table.concat(out)
end

local B64_REVERSE
local function base64Decode(str)
	if not B64_REVERSE then
		B64_REVERSE = {}
		for idx = 1, #B64_CHARS do
			B64_REVERSE[B64_CHARS:sub(idx, idx)] = idx - 1
		end
	end
	str = str:gsub("[^%a%d%+%/%=]", "")
	local out = {}
	local i = 1
	local len = #str
	while i <= len do
		local c1 = B64_REVERSE[str:sub(i, i)] or 0
		local c2 = B64_REVERSE[str:sub(i + 1, i + 1)] or 0
		local s3 = str:sub(i + 2, i + 2)
		local s4 = str:sub(i + 3, i + 3)
		local c3 = B64_REVERSE[s3]
		local c4 = B64_REVERSE[s4]
		local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
		local b1 = math.floor(n / 65536) % 256
		out[#out + 1] = string.char(b1)
		if s3 ~= "=" and s3 ~= "" then
			local b2 = math.floor(n / 256) % 256
			out[#out + 1] = string.char(b2)
		end
		if s4 ~= "=" and s4 ~= "" then
			local b3 = n % 256
			out[#out + 1] = string.char(b3)
		end
		i = i + 4
	end
	return table.concat(out)
end

-- Minimal deterministic Lua table serializer (numbers/strings/booleans/tables only).
local function serialize(value, buf)
	local t = type(value)
	if t == "table" then
		buf[#buf + 1] = "{"
		-- array part first, in order
		local n = #value
		for i = 1, n do
			serialize(value[i], buf)
			buf[#buf + 1] = ","
		end
		-- keyed part, sorted for determinism
		local keys = {}
		for k in pairs(value) do
			if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
				table.insert(keys, k)
			end
		end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			buf[#buf + 1] = "["
			serialize(k, buf)
			buf[#buf + 1] = "]="
			serialize(value[k], buf)
			buf[#buf + 1] = ","
		end
		buf[#buf + 1] = "}"
	elseif t == "string" then
		buf[#buf + 1] = string.format("%q", value)
	elseif t == "number" or t == "boolean" then
		buf[#buf + 1] = tostring(value)
	else
		buf[#buf + 1] = "nil"
	end
end

local function serializeTable(tbl)
	local buf = {}
	serialize(tbl, buf)
	return table.concat(buf)
end

local function deserializeTable(str)
	local chunk = "return " .. str
	local fn = loadstring and loadstring(chunk) or load(chunk)
	if not fn then return nil end
	-- Sandboxed environment: no globals needed for a pure data literal.
	if setfenv then setfenv(fn, {}) end
	local ok, result = pcall(fn)
	if not ok then return nil end
	return result
end

-- Exposed for reuse by Comm.lua (addon-message payload encode/decode).
BM.Serializer = {
	encode = function(tbl) return base64Encode(serializeTable(tbl)) end,
	decode = function(str)
		local ok, decoded = pcall(base64Decode, str)
		if not ok or not decoded then return nil end
		return deserializeTable(decoded)
	end,
}

local EXPORT_PREFIX = "BM1:"

function P:Export(name)
	local prof = BM.db.profiles[name or BM.db.activeProfile]
	if not prof then return nil end
	local serialized = serializeTable(prof)
	return EXPORT_PREFIX .. base64Encode(serialized)
end

function P:Import(str)
	if not str or not str:find(EXPORT_PREFIX, 1, true) then
		return false, "invalid string"
	end
	local payload = str:match(EXPORT_PREFIX .. "(.+)")
	if not payload then return false, "invalid string" end
	local ok, decoded = pcall(base64Decode, payload)
	if not ok or not decoded then return false, "decode failed" end
	local tbl = deserializeTable(decoded)
	if type(tbl) ~= "table" or not tbl.classBlessing then
		return false, "corrupt profile data"
	end
	local baseName = tbl.name or "Imported"
	local finalName = baseName
	local suffix = 2
	while BM.db.profiles[finalName] do
		finalName = baseName .. " " .. suffix
		suffix = suffix + 1
	end
	tbl.name = finalName
	BM.db.profiles[finalName] = tbl
	BM:Fire("PROFILE_LIST_CHANGED")
	return true, finalName
end

BM:On("DB_READY", function() P:EnsureDefault() end)
