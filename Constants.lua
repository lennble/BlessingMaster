-- BlessingMaster: Constants.lua
-- Blessing definitions, class metadata, default priorities.

local BM = _G.BlessingMaster

-- Blessing keys are short internal IDs. "greater" is the raid/party-wide cast,
-- "single" is the single-target version. Both share one aura slot on a unit,
-- which is why exactly one blessing must "win" per player (see Assignment.lua).
--
-- Spells are identified by numeric spell ID rather than by (English) name,
-- so the addon works on any game client locale: GetSpellInfo(id) resolves
-- the name/icon in whatever language the local client is running, and
-- CastSpellByName/macro casts need that *resolved* localized name at cast
-- time (see BM:GetSpellName below and its use in CastBar.lua) rather than a
-- hardcoded English string. The exact numeric rank chosen for each ID
-- doesn't matter - it only anchors the spell family so we can look up its
-- current localized name/icon; /cast by name always casts the highest rank
-- the player actually knows.
BM.BLESSINGS = {
	MIGHT = {
		key = "MIGHT",
		label = "Might",
		greaterSpellId = 25782, -- Greater Blessing of Might
		singleSpellId = 19838,  -- Blessing of Might
		color = { r = 0.85, g = 0.25, b = 0.15 },
	},
	WISDOM = {
		key = "WISDOM",
		label = "Wisdom",
		greaterSpellId = 25894, -- Greater Blessing of Wisdom
		singleSpellId = 27142,  -- Blessing of Wisdom
		color = { r = 0.20, g = 0.55, b = 0.95 },
	},
	KINGS = {
		key = "KINGS",
		label = "Kings",
		greaterSpellId = 25898, -- Greater Blessing of Kings
		singleSpellId = 20217,  -- Blessing of Kings
		color = { r = 0.85, g = 0.75, b = 0.15 },
	},
	SALVATION = {
		key = "SALVATION",
		label = "Salvation",
		greaterSpellId = 25895, -- Greater Blessing of Salvation
		singleSpellId = 1038,   -- Blessing of Salvation
		color = { r = 0.55, g = 0.85, b = 0.55 },
	},
	SANCTUARY = {
		key = "SANCTUARY",
		label = "Sanctuary",
		greaterSpellId = 25899, -- Greater Blessing of Sanctuary
		singleSpellId = 20911,  -- Blessing of Sanctuary
		color = { r = 0.65, g = 0.45, b = 0.85 },
	},
}

-- Order used for UI / priority editing.
BM.BLESSING_ORDER = { "MIGHT", "WISDOM", "KINGS", "SALVATION", "SANCTUARY" }

-- Utility blessings: not part of auto-rotation (they don't compete for the
-- shared blessing slot the same way, or are highly situational), but exposed
-- as quick-cast buttons.
BM.UTILITY_BLESSINGS = {
	FREEDOM = { key = "FREEDOM", label = "Freedom", spellId = 1044 },       -- Blessing of Freedom
	PROTECTION = { key = "PROTECTION", label = "Protection", spellId = 10278 }, -- Blessing of Protection
	LIGHT = { key = "LIGHT", label = "Light", greaterSpellId = 27145, singleSpellId = 27144 },
}

-- Cache of resolved spell names/icons, filled lazily since GetSpellInfo
-- requires the spell to be in the local client's spell dictionary (works
-- even if the player doesn't personally know the spell, it's a game
-- constant lookup, not a "do I know this" check).
BM.nameCache = {}
BM.iconCache = {}

function BM:GetSpellName(spellId)
	local cached = self.nameCache[spellId]
	if cached then return cached end
	local name = GetSpellInfo(spellId)
	self.nameCache[spellId] = name
	return name
end

function BM:GetSpellIcon(spellId)
	local cached = self.iconCache[spellId]
	if cached then return cached end
	local _, _, icon = GetSpellInfo(spellId)
	icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
	self.iconCache[spellId] = icon
	return icon
end

function BM:GetBlessingIcon(blessingKey, greater)
	local def = self.BLESSINGS[blessingKey]
	if not def then return "Interface\\Icons\\INV_Misc_QuestionMark" end
	return self:GetSpellIcon(greater and def.greaterSpellId or def.singleSpellId)
end

-- Sanity check run once on login: if any configured spell ID fails to
-- resolve on this client (wrong ID, or removed/renamed spell), warn loudly
-- instead of silently failing to cast/detect that blessing later.
function BM:ValidateSpellIds()
	local problems = {}
	for _, key in ipairs(self.BLESSING_ORDER) do
		local def = self.BLESSINGS[key]
		if not self:GetSpellName(def.greaterSpellId) then
			table.insert(problems, ("Greater %s (id %d)"):format(def.label, def.greaterSpellId))
		end
		if not self:GetSpellName(def.singleSpellId) then
			table.insert(problems, ("%s (id %d)"):format(def.label, def.singleSpellId))
		end
	end
	for _, def in pairs(self.UTILITY_BLESSINGS) do
		if def.spellId and not self:GetSpellName(def.spellId) then
			table.insert(problems, ("%s (id %d)"):format(def.label, def.spellId))
		end
		if def.greaterSpellId and not self:GetSpellName(def.greaterSpellId) then
			table.insert(problems, ("Greater %s (id %d)"):format(def.label, def.greaterSpellId))
		end
		if def.singleSpellId and not self:GetSpellName(def.singleSpellId) then
			table.insert(problems, ("%s (id %d)"):format(def.label, def.singleSpellId))
		end
	end
	if #problems > 0 then
		self:Print("|cffff4444Warnung|r: Folgende Spell-IDs konnten nicht aufgelöst werden (evtl. falscher Client-Patch, bitte IDs in Constants.lua prüfen): " .. table.concat(problems, ", "))
	end
end

-- Role classification, used to pick sane default blessings per raid member.
-- "MELEE" -> Might, "CASTER" -> Wisdom (healers get Wisdom/Salvation weighting),
-- "TANK" -> Kings/Sanctuary, "HEALER" -> Wisdom.
BM.CLASS_DEFAULT_ROLE = {
	WARRIOR = "MELEE",
	ROGUE = "MELEE",
	HUNTER = "MELEE",
	SHAMAN = "CASTER",
	PALADIN = "MELEE",
	DRUID = "CASTER",
	PRIEST = "CASTER",
	MAGE = "CASTER",
	WARLOCK = "CASTER",
}

BM.CLASS_COLORS = RAID_CLASS_COLORS or CUSTOM_CLASS_COLORS

-- Default blessing preference per role. Used by Assignment.lua as the
-- starting point; fully overridable per profile/per player.
BM.DEFAULT_ROLE_BLESSING = {
	MELEE = "MIGHT",
	CASTER = "WISDOM",
	HEALER = "WISDOM",
	TANK = "KINGS",
}

-- Comm protocol
BM.COMM_PREFIX = "BlessingMstr"
BM.COMM_VERSION = 1

BM:On("PLAYER_LOGIN", function() BM:ValidateSpellIds() end)
