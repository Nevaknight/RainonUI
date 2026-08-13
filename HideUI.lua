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
    -- Плашка открытия основной фракции (Blizzard_MajorFactions, грузится лениво —
    -- pendingPaths дождётся создания фрейма).
    factiontoast    = { "MajorFactionUnlockToast" },
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

local hooked = {}          -- [frame] = true (хук OnShow уже повешен)
local frameKey = {}        -- [frame] = key (для проверки актуальности скрытия)
local keyFrames = {}       -- [key] = { frame, ... } (чтобы вернуть при снятии галки)
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

local function IsHideOn(key)
    return ns.db and ns.db.hide and ns.db.hide[key] and true or false
end

local function SafeHide(frame)
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        combatQueue[frame] = true
    else
        frame:Hide()
    end
end

local function Remember(key, frame)
    keyFrames[key] = keyFrames[key] or {}
    for _, f in ipairs(keyFrames[key]) do if f == frame then return end end
    table.insert(keyFrames[key], frame)
end

-- Скрываем фрейм и вешаем ОДИН хук OnShow, который прячет фрейм ТОЛЬКО пока
-- галка скрытия включена. Так снятие галки (Unhide) сразу возвращает окно —
-- хук перестаёт его прятать, а мы показываем его вручную.
local function KeepHidden(frame, key)
    if not frame then return false end
    if type(frame) ~= "table" or not frame.HookScript or not frame.Hide then
        return false
    end
    frameKey[frame] = key
    Remember(key, frame)
    if not hooked[frame] then
        hooked[frame] = true
        frame:HookScript("OnShow", function(f)
            if IsHideOn(frameKey[f]) then SafeHide(f) end
        end)
    end
    if IsHideOn(key) then SafeHide(frame) end
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
    raidwarning = function()
        -- Скрываем крупный текст рейдового объявления по центру: снимаем событие
        -- с RaidWarningFrame. Звук на 12.0 играет отдельная система (C_Sound),
        -- MuteSoundFile его не берёт — поэтому убираем только текст, это работает.
        -- RaidWarningFrame не защищён — тэйнта нет.
        if _G.RaidWarningFrame then
            _G.RaidWarningFrame:UnregisterEvent("CHAT_MSG_RAID_WARNING")
        end
    end,
}

-- Обратные действия для «особых» ключей — чтобы снятие галки возвращало всё
-- как было, без /reload (где это возможно).
local SPECIAL_UNDO = {
    combattext = function()
        -- Стандартные тайминги текста боя Blizzard.
        _G.COMBATFEEDBACK_FADEINTIME  = 0.2
        _G.COMBATFEEDBACK_HOLDTIME    = 2.0
        _G.COMBATFEEDBACK_FADEOUTTIME = 0.3
    end,
    blizzdbm = function()
        if RaidBossEmoteFrame then
            RaidBossEmoteFrame:RegisterEvent("RAID_BOSS_EMOTE")
        end
    end,
    lootHide = function()
        if AlertFrame then
            AlertFrame:RegisterEvent("SHOW_LOOT_TOAST")
        end
    end,
    raidwarning = function()
        if _G.RaidWarningFrame then
            _G.RaidWarningFrame:RegisterEvent("CHAT_MSG_RAID_WARNING")
        end
    end,
    -- bossbanner: у баннера много событий — надёжнее вернуть через /reload.
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
            if not KeepHidden(ResolvePath(path), key) then
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
                KeepHidden(container, key)
            else
                missing = missing or {}
                table.insert(missing, "PersonalResourceDisplayFrame.ClassFrameContainer")
            end
        end
    end

    pendingPaths[key] = missing
end

-- Снятие галки: возвращаем скрытые элементы обратно (без /reload, где можно).
-- Хук OnShow больше не прячет их (проверяет ns.db.hide[key], уже false), а мы
-- дополнительно показываем те, что сейчас скрыты.
local function Unhide(key)
    specialApplied[key] = nil
    if SPECIAL_UNDO[key] then pcall(SPECIAL_UNDO[key]) end
    local frames = keyFrames[key]
    if frames then
        for _, f in ipairs(frames) do
            combatQueue[f] = nil
            if f.Show then pcall(f.Show, f) end
        end
    end
    -- Для «особых» ключей без обратного действия (баннер боссов) нужен /reload.
    if SPECIAL[key] and not SPECIAL_UNDO[key] then
        ns.Print("часть изменений вернётся после перезагрузки интерфейса (" ..
            ns.C("FFFF00", "/reload") .. ").")
    end
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

-- =========================================================================
-- Режим настройки: крестики скрытия прямо на элементах интерфейса.
-- Когда режим включён, на каждом ещё НЕ скрытом элементе (из FRAMES),
-- который сейчас виден на экране, появляется красный крестик. Клик по нему
-- включает галку скрытия этого элемента и прячет его — наглядно и удобно.
-- =========================================================================
local setupOverlays = {}   -- [key] = кнопка-крестик
local setupTicker

local function FirstFrameForKey(key)
    local list = FRAMES[key]
    if not list then return nil end
    for _, path in ipairs(list) do
        local f = ResolvePath(path)
        if type(f) == "table" and f.IsShown then return f end
    end
    return nil
end

-- Человеческое название элемента — как в меню аддона (ns.HideNames заполняет
-- Options.lua из того же списка). Фолбэк — сам ключ.
local function HideLabel(key)
    return (ns.HideNames and ns.HideNames[key]) or key
end

local function MakeSetupCross(key)
    local x = setupOverlays[key]
    if x then return x end
    x = CreateFrame("Button", nil, UIParent)
    x:SetSize(24, 24)
    x:SetFrameStrata("FULLSCREEN_DIALOG")
    x:SetFrameLevel(500)
    -- Игровая красная кнопка-«X» (та же, что «отказаться» в розыгрыше добычи).
    x:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    x:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    local hl = x:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    -- Мягкая тёмная подложка, чтобы крестик читался на любом фоне.
    local bg = x:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -2, 2)
    bg:SetPoint("BOTTOMRIGHT", 2, -2)
    bg:SetColorTexture(0, 0, 0, 0.5)
    x:SetScript("OnClick", function()
        if ns.db and ns.db.hide then ns.db.hide[key] = true end
        ApplyKey(key)
        x:Hide()
    end)
    x:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Скрывать: " .. HideLabel(key), 1, 1, 1)
        GameTooltip:AddLine("Клик — включить скрытие этого элемента в RainonUI.",
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    x:SetScript("OnLeave", function() GameTooltip:Hide() end)
    setupOverlays[key] = x
    return x
end

local function RefreshSetup()
    local on = ns.db and ns.db.features and ns.db.features.hideSetupMode
    for key in pairs(FRAMES) do
        local want = on and ns.db.hide and not ns.db.hide[key]
        local f = want and FirstFrameForKey(key) or nil
        if f and f:IsShown() then
            local x = MakeSetupCross(key)
            x:ClearAllPoints()
            -- Крестик — по центру самого элемента (у некоторых фреймов, напр.
            -- полосы опыта, угол far от видимой части — центр надёжнее).
            x:SetPoint("CENTER", f, "CENTER", 0, 0)
            x:Show()
        elseif setupOverlays[key] then
            setupOverlays[key]:Hide()
        end
    end
end

local function SetSetupMode(on)
    if on then
        RefreshSetup()
        if not setupTicker then setupTicker = C_Timer.NewTicker(1, RefreshSetup) end
    else
        if setupTicker then setupTicker:Cancel(); setupTicker = nil end
        for _, x in pairs(setupOverlays) do x:Hide() end
    end
end

ns.HideUI = {
    ApplyKey = ApplyKey,
    ApplyAll = ApplyWithRetries,
    SetSetupMode = SetSetupMode,
    Unhide = Unhide,
}

-- Восстанавливаем режим настройки после входа в мир, если он был включён.
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if ns.db and ns.db.features and ns.db.features.hideSetupMode then
        C_Timer.After(2, function() SetSetupMode(true) end)
    end
end)

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