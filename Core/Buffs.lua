local ADDON = "MultiTool"
local NS = _G[ADDON] or {}
_G[ADDON] = NS

NS.ClassBuffs = {
    PALADIN = {
        { key = "BlessingOfKings", spellIDs = {20217}, labelKey = "BLESSING_OF_KINGS", groupKey = "blessing", default = true },
        { key = "BlessingOfMight", spellIDs = {19740,19834,19835,19836,19837,19838,25291}, labelKey = "BLESSING_OF_MIGHT", groupKey = "blessing", default = true },
        { key = "BlessingOfWisdom", spellIDs = {19742,19850,19852,19853,19854,25290}, labelKey = "BLESSING_OF_WISDOM", groupKey = "blessing", default = true },
        { key = "BlessingOfLight", spellIDs = {19977,19978,19979,25890}, labelKey = "BLESSING_OF_LIGHT", groupKey = "blessing", default = true },
        { key = "BlessingOfSalvation", spellIDs = {1038,25895}, labelKey = "BLESSING_OF_SALVATION", groupKey = "blessing", default = true },
        { key = "BlessingOfSanctuary", spellIDs = {20911,25899}, labelKey = "BLESSING_OF_SANCTUARY", groupKey = "blessing", default = true },
        { key = "RighteousFury", spellIDs = {25780}, labelKey = "RIGHTEOUS_FURY", requiresShield = true, default = true },
        { key = "SealOfRighteousness", spellIDs = {20154,21084}, labelKey = "SEAL_OF_RIGHTEOUSNESS", default = true, isSeal = true },
        { key = "SealOfCommand", spellIDs = {20375}, labelKey = "SEAL_OF_COMMAND", default = true, isSeal = true },
        { key = "SealOfJustice", spellIDs = {20164}, labelKey = "SEAL_OF_JUSTICE", default = true, isSeal = true },
        { key = "SealOfLight", spellIDs = {20165}, labelKey = "SEAL_OF_LIGHT", default = true, isSeal = true },
        { key = "SealOfWisdom", spellIDs = {20166}, labelKey = "SEAL_OF_WISDOM", default = true, isSeal = true },
        { key = "SealOfVengeance", spellIDs = {31801}, labelKey = "SEAL_OF_VENGEANCE", default = true, isSeal = true },
        { key = "SealOfBlood", spellIDs = {31892}, labelKey = "SEAL_OF_BLOOD", default = true, isSeal = true },
        { key = "SealOfFury", spellIDs = {20451,20452,20453,20454}, labelKey = "SEAL_OF_FURY", default = true, isSeal = true },
    },
    PRIEST = {
        { key = "PowerWordFortitude", spellIDs = {1243,1244,1245,2791,10937,10938}, labelKey = "POWER_WORD_FORTITUDE", default = true },
        { key = "DivineSpirit", spellIDs = {14752,14818,14819}, labelKey = "DIVINE_SPIRIT", default = true },
        { key = "InnerFire", spellIDs = {588,7128,602,1006}, labelKey = "INNER_FIRE", default = true },
        { key = "ShadowProtection", spellIDs = {976,10957,10958}, labelKey = "SHADOW_PROTECTION", default = true },
    },
    SHAMAN = {
        { key = "StoneskinTotem", spellIDs = {8071,8154,8155,10406,10407,10408}, labelKey = "STONE_SKIN_TOTEM", default = true },
        { key = "GraceOfAirTotem", spellIDs = {8835,10627,25359}, labelKey = "GRACE_OF_AIR_TOTEM", default = true },
        { key = "ManaSpringTotem", spellIDs = {5675,10495,10496,10497}, labelKey = "MANA_SPRING_TOTEM", default = true },
        { key = "WindfuryTotem", spellIDs = {8512,10613,10614,25587}, labelKey = "WINDFURY_TOTEM", default = true },
    },
    DRUID = {
        { key = "MarkOfTheWild", spellIDs = {1126,5232,6756,8907,9866,9896}, labelKey = "MARK_OF_THE_WILD", default = true },
        { key = "Thorns", spellIDs = {467,782,1075,8914,9756,9910}, labelKey = "THORNS", default = true },
        { key = "GiftOfTheWild", spellIDs = {21849,21850}, labelKey = "GIFT_OF_THE_WILD", default = true },
        { key = "Innervate", spellIDs = {29166,29167}, labelKey = "INNERVATE", default = true },
    },
    MAGE = {
        { key = "ArcaneIntellect", spellIDs = {1459,1460,1461,10156,10157}, labelKey = "ARCANE_INTELLECT", default = true },
        { key = "FrostArmor", spellIDs = {168,7302,7303,7304}, labelKey = "FROST_ARMOR", default = true },
        { key = "IceArmor", spellIDs = {10219,10220,10221}, labelKey = "ICE_ARMOR", default = true },
        { key = "MageArmor", spellIDs = {6117,22782,22783}, labelKey = "MAGE_ARMOR", default = true },
    },
    WARLOCK = {
        { key = "DemonArmor", spellIDs = {706,1086,11733,11734,11735}, labelKey = "DEMON_ARMOR", default = true },
        { key = "FelArmor", spellIDs = {28176,28179,28180}, labelKey = "FEL_ARMOR", default = true },
        { key = "ShadowWard", spellIDs = {6229,11739,11740,11741,28610}, labelKey = "SHADOW_WARD", default = true },
        { key = "SoulLink", spellIDs = {19028,19029,19030}, labelKey = "SOUL_LINK", default = true },
    },
    HUNTER = {
        { key = "AspectOfTheMonkey", spellIDs = {13163}, labelKey = "ASPECT_OF_THE_MONKEY", default = true },
        { key = "AspectOfTheHawk", spellIDs = {13165,14318,14319,14320,14321}, labelKey = "ASPECT_OF_THE_HAWK", default = true },
        { key = "AspectOfTheBeast", spellIDs = {13161}, labelKey = "ASPECT_OF_THE_BEAST", default = true },
        { key = "TrueshotAura", spellIDs = {19506,20905,20906,20907}, labelKey = "TRUESHOT_AURA", default = true },
    },
    ROGUE = {
        { key = "Sprint", spellIDs = {11305,2983}, labelKey = "SPRINT", default = true },
        { key = "Evasion", spellIDs = {5277,26669,26679}, labelKey = "EVASION", default = true },
        { key = "Shadowstep", spellIDs = {36554,36563}, labelKey = "SHADOWSTEP", default = true },
        { key = "BladeFlurry", spellIDs = {13877,13878,13879}, labelKey = "BLADE_FLURRY", default = true },
    },
    WARRIOR = {
        { key = "BattleShout", spellIDs = {6673,5242,6192,11549,11550,11551}, labelKey = "BATTLE_SHOUT", default = true },
        { key = "CommandingShout", spellIDs = {469,1160,6192,6193,6194}, labelKey = "COMMANDING_SHOUT", default = true },
        { key = "DefensiveStance", spellIDs = {71}, labelKey = "DEFENSIVE_STANCE", default = true },
        { key = "BerserkerStance", spellIDs = {2458}, labelKey = "BERSERKER_STANCE", default = true },
    },
}

NS.PaladinAuras = {
    { spellIDs = {
        465,10290,643,10291,1032,10292,10293,
        7294,10298,10299,10300,10301,27150,
        19746,
        19891,19899,19900,27153,
        19888,19897,19898,27152,
        19876,19895,19896,27151,
    } },
}
