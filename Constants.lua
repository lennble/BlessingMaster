-- BlessingMaster: Constants.lua
-- Blessing definitions, class metadata, default priorities.

local BM = _G.BlessingMaster

-- Blessing keys are short internal IDs. "greater" is the raid/party-wide cast,
-- "single" is the single-target version. Both share one aura slot on a unit,
-- which is why exactly one blessing must "win" per player (see Assignment.lua).
BM.BLESSINGS = {
	MIGHT = {
		key = "MIGHT",
		label = "Might",
		greaterSpell = "Greater Blessing of Might",
		singleSpell = "Blessing of Might",
		color = { r = 0.85, g = 0.25, b = 0.15 },
	},
	WISDOM = {
		key = "WISDOM",
		label = "Wisdom",
		greaterSpell = "Greater Blessing of Wisdom",
		singleSpell = "Blessing of Wisdom",
		color = { r = 0.20, g = 0.55, b = 0.95 },
	},
	KINGS = {
		key = "KINGS",
		label = "Kings",
		greaterSpell = "Greater Blessing of Kings",
		singleSpell = "Blessing of Kings",
		color = { r = 0.85, g = 0.75, b = 0.15 },
	},
	SALVATION = {
		key = "SALVATION",
		label = "Salvation",
		greaterSpell = "Greater Blessing of Salvation",
		singleSpell = "Blessing of Salvation",
		color = { r = 0.55, g = 0.85, b = 0.55 },
	},
	SANCTUARY = {
		key = "SANCTUARY",
		label = "Sanctuary",
		greaterSpell = "Greater Blessing of Sanctuary",
		singleSpell = "Blessing of Sanctuary",
		color = { r = 0.65, g = 0.45, b = 0.85 },
	},
}

-- Order used for UI / priority editing.
BM.BLESSING_ORDER = { "MIGHT", "WISDOM", "KINGS", "SALVATION", "SANCTUARY" }

-- Utility blessings: not part of auto-rotation (they don't compete for the
-- shared blessing slot the same way, or are highly situational), but exposed
-- as quick-cast buttons.
BM.UTILITY_BLESSINGS = {
	FREEDOM = { key = "FREEDOM", label = "Freedom", spell = "Blessing of Freedom" },
	PROTECTION = { key = "PROTECTION", label = "Protection", spell = "Blessing of Protection" },
	LIGHT = { key = "LIGHT", label = "Light", greaterSpell = "Greater Blessing of Light", singleSpell = "Blessing of Light" },
}

-- Cache of resolved spell icons, filled lazily since GetSpellInfo requires
-- the spell to be in the local client's spell dictionary (works client-side
-- even if the player doesn't know the spell yet, since it's a game constant).
BM.iconCache = {}
function BM:GetSpellIcon(spellName)
	local cached = self.iconCache[spellName]
	if cached then return cached end
	local _, _, icon = GetSpellInfo(spellName)
	icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
	self.iconCache[spellName] = icon
	return icon
end

function BM:GetBlessingIcon(blessingKey, greater)
	local def = self.BLESSINGS[blessingKey]
	if not def then return "Interface\\Icons\\INV_Misc_QuestionMark" end
	return self:GetSpellIcon(greater and def.greaterSpell or def.singleSpell)
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
