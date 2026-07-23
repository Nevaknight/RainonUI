-- =========================================================================
-- RainonUI / HideUI: скрытие элементов стандартного интерфейса.
-- Портировано из WeakAuras «Rainon Scripts UI» и выверено по исходникам
-- Blizzard UI 12.0.7 (сборка 68453):
--   * ComboPointPlayerFrame → RogueComboPointBarFrame
--   * ComboPointDruidPlayerFrame → DruidComboPointBarFrame
--   * TargetFrameSpellBar → TargetFrame.spellbar (глобальное имя убрано)
--   * ObjectiveTrackerBonusBannerFrame → ObjectiveTrackerTopBannerFrame
--   * Индикатор личного ресурса — новый PersonalResourceDisplayFrame
--     (Edit Mode): классовый фрейм в нём создаётся БЕЗ имени, поэтому
--     скрываем его контейнер ClassFrameContainer для своего класса.
-- Применение отложенное и с повторами (как WA_DELAYED_PLAYER_ENTERING_WORLD
-- у WeakAuras): часть фреймов создаётся позже входа в мир.
-- =========================================================================

local _, ns = ...

-- key -> список путей к фреймам (поддерживаются точки: "TargetFrame.spellbar")
local FRAMES = {
    -- Рамка игрока
    holypower       = { "PaladinPowerBarFrame" },
    essence         = { "EssencePlayerFrame" },
    runeframe       = { "RuneFrame" },
    warlockpower    = { "WarlockPowerFrame" },
    stagger         = { "MonkStaggerBar" },
    monkbar         = { "MonkHarmonyBarFrame" },
    rogcombo        = { "RogueComboPointBarFrame" },
    drucombo        = { "DruidComboPointBarFrame" },
    arcanemage      = { "MageArcaneChargesFrame" },
    totempanel      = { "TotemFrame" },
    castbar         = { "PlayerCastingBarFrame" },
    -- Индикатор личного ресурса: старые нейплейт-бары + новый PRD
    holypowerbar    = { "ClassNameplateBarPaladinFrame" },
    essencebar      = { "ClassNameplateBarDracthyrFrame" },
    runeframebar    = { "DeathKnightResourceOverlayFrame" },
    warlockpowerbar = { "ClassNameplateBarWarlockFrame" },
    monkpersonalbar = { "ClassNameplateBarWindwalkerMonkFrame" },
    rogcombobar     = { "ClassNameplateBarRogueFrame" },
    drucombobar     = { "ClassNameplateBarFeralDruidFrame" },
    arcanemagebar   = { "ClassNameplateBarMageFrame" },
    -- Разное
    targetspellbar  = { "TargetFrame.spellbar" },
    talkinghead     = { "TalkingHeadFrame" },
    actionbutton    = { "ExtraActionButton1.style" },
    zonebutton      = { "ZoneAbilityFrame.Style" },
    expbar          = { "StatusTrackingBarManager" },
    bags            = { "MainMenuBarBackpackButton", "BagBarExpandToggle",
                        "CharacterReagentBag0Slot" },
    raidmanager     = { "CompactRaidFrameManager" },
    expansionbutton = { "ExpansionLandingPageMinimapButton" },
    durability      = { "DurabilityFrame" },
    vehicle         = { "VehicleSeatIndicator" },
    -- Особые
    event           = { "EventToastManagerFrame" },
    dailyquest      = { "ObjectiveTrackerTopBannerFrame" },
    ZoneHide        = { "ZoneTextFrame", "SubZoneTextFrame" },
    -- Баннер «X повержен / Подземелье пройдено» (BossBanner, BossBannerToast.xml)
    bossbanner      = { "BossBanner" },
}

-- Классовая часть нового Personal Resource Display: скрываем контейнер
-- классового ресурса, если игрок соответствующего класса.
local PRD_CLASS = {
    holypowerbar = "PALADIN",  essencebar      = "EVOKER",
    runeframebar = "DEATHKNIGHT", warlockpowerbar = "WARLOCK",
    monkpersonalbar = "MONK",  rogcombobar     = "ROGUE",
    drucombobar  = "DRUID",    arcanemagebar   = "MAGE",
}

local hooked = {}          -- [frame] = true
local specialApplied = {}  -- [key] = true
local combatQueue = {}     -- защищённые фреймы, ждущие конца боя
local pendingPaths = {}    -- [key] = { path, ... } — фреймы, ещё не созданные

local function ResolvePath(path)
    local obj = _G
    for part in string.gmatch(path, "[^%.]+") do
        obj = obj[part]
        if obj == nil then return nil end
    end
    return obj
end

local function SafeHide(frame)
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        combatQueue[frame] = true
    else
        frame:Hide()
    end
end

local function KeepHidden(frame)
    if not frame or hooked[frame] then return frame and true end
    if type(frame) ~= "table" or not frame.HookScript or not frame.Hide then
        return false
    end
    hooked[frame] = true
    frame:HookScript("OnShow", SafeHide)
    SafeHide(frame)
    return true
end

-- Одноразовые действия, не сводящиеся к скрытию фрейма
local SPECIAL = {
    combattext = function()
        -- Текст боя на рамке игрока (setglobal устарел — пишем в _G)
        _G.COMBATFEEDBACK_FADEINTIME  = 0
        _G.COMBATFEEDBACK_HOLDTIME    = 0
        _G.COMBATFEEDBACK_FADEOUTTIME = 0
    end,
    blizzdbm = function()
        if RaidBossEmoteFrame then
            RaidBossEmoteFrame:UnregisterEvent("RAID_BOSS_EMOTE")
        end
    end,
    lootHide = function()
        if AlertFrame then
            AlertFrame:UnregisterEvent("SHOW_LOOT_TOAST")
        end
    end,
    bossbanner = function()
        -- Баннер боссов/подземелий срабатывает по событиям — глушим их,
        -- а сам фрейм дополнительно прячем через KeepHidden (FRAMES).
        if _G.BossBanner then
            _G.BossBanner:UnregisterAllEvents()
        end
    end,
}

local playerClass = nil

local function ApplyKey(key)
    local db = ns.db and ns.db.hide
    if not db or not db[key] then return end

    if SPECIAL[key] and not specialApplied[key] then
        specialApplied[key] = true
        pcall(SPECIAL[key])
    end

    local missing
    local list = FRAMES[key]
    if list then
        for _, path in ipairs(list) do
            if not KeepHidden(ResolvePath(path)) then
                missing = missing or {}
                table.insert(missing, path)
            end
        end
    end

    -- Новый Personal Resource Display (12.0)
    local classToken = PRD_CLASS[key]
    if classToken then
        playerClass = playerClass or select(2, UnitClass("player"))
        if playerClass == classToken then
            local prd = _G.PersonalResourceDisplayFrame
            local container = prd and prd.ClassFrameContainer
            if container then
                KeepHidden(container)
            else
                missing = missing or {}
                table.insert(missing, "PersonalResourceDisplayFrame.ClassFrameContainer")
            end
        end
    end

    pendingPaths[key] = missing
end

local function ApplyAll()
    for key in pairs(ns.defaults.hide) do
        ApplyKey(key)
    end
end

-- Повторы для фреймов, создающихся позже (аналог задержки WeakAuras)
local RETRY_DELAYS = { 1, 3, 8, 20 }
local retryScheduled = false

local function RetryPending(step)
    local anyMissing = false
    for key, list in pairs(pendingPaths) do
        if list and #list > 0 then
            ApplyKey(key)
            if pendingPaths[key] and #pendingPaths[key] > 0 then
                anyMissing = true
            end
        end
    end
    local nextDelay = RETRY_DELAYS[step + 1]
    if anyMissing and nextDelay then
        C_Timer.After(nextDelay, function() RetryPending(step + 1) end)
    else
        retryScheduled = false
    end
end

local function ApplyWithRetries()
    ApplyAll()
    if not retryScheduled then
        retryScheduled = true
        C_Timer.After(RETRY_DELAYS[1], function() RetryPending(1) end)
    end
end

ns.HideUI = {
    ApplyKey = ApplyKey,
    ApplyAll = ApplyWithRetries,
}

ns.RegisterMessage("RAINON_REAPPLY", ApplyWithRetries)

-- Edit Mode может заново показать управляемые фреймы при смене макета,
-- смена специализации пересоздаёт классовые ресурсы.
ns.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", ApplyWithRetries)
ns.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(unit)
    if unit == "player" or unit == nil then ApplyWithRetries() end
end)

-- Конец боя — скрываем то, что нельзя было трогать в бою
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    for frame in pairs(combatQueue) do
        pcall(frame.Hide, frame)
    end
    wipe(combatQueue)
end)