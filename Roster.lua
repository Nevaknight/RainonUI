-- =========================================================================
-- RainonUI / Roster: мультиперсонажное хранилище для окна знаний/зарядов
-- и кнопка миникарты.
--
-- Игра отдаёт данные профессий/рецептов только когда открыто окно
-- профессии, поэтому пишем текущего персонажа в аккаунтные сохранёнки
-- (ns.db.roster[GUID]) при каждом открытии профессии / сдаче квеста, а окно
-- показывает из запомненного. Чужих альтов «на расстоянии» игра не отдаёт —
-- на каждого надо разок зайти и открыть профессию.
--
-- Заряды рецептов («Available Crafts X/Y») читаем через
-- C_TradeSkillUI.GetRecipeCooldown(recipeID) → charges, maxCharges.
-- =========================================================================
local _, ns = ...

local Roster = {}
ns.Roster = Roster

-- Рецепты алхимии с зарядами (ID выверены по Wowhead, Midnight 12.0)
Roster.HERBS_RECIPE    = 1230892 -- Bouquet of Herbs
Roster.WONDROUS_RECIPE = 1230856 -- Wondrous Synergist
local CHARGE_RECIPES = { Roster.HERBS_RECIPE, Roster.WONDROUS_RECIPE }

-- Валюта концентрации по базовому ID линии профессии (Midnight). ID выверены
-- по WeeklyKnowledge (Data\SkillLineVariants.lua). У собирателей (травы 182,
-- горное 186, шкуры 393) концентрации нет.
local CONC_CURRENCY = {
    [171] = 3161, [164] = 3162, [333] = 3163, [202] = 3164,
    [773] = 3165, [755] = 3166, [165] = 3167, [197] = 3168,
}

-- Период восстановления заряда определяется по МАКС. числу зарядов (оно
-- отражает прокачанные таланты): 4/4 → 9ч10м (талант снижения уже взят),
-- 1/1 → 18ч (без таланта). Прочее (2/2 и т.п.) — пока по умолчанию 18ч,
-- точное время подтвердим позже.
local function PeriodForMax(maxCharges)
    if maxCharges == 4 then return 9 * 3600 + 10 * 60 end  -- 9ч10м
    if maxCharges == 2 then return 12 * 3600 + 50 * 60 end -- 12ч50м
    if maxCharges == 1 then return 18 * 3600 end           -- 18ч
    return 18 * 3600                                        -- по умолчанию 18ч
end

local function ReadCharges(recipeID)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown) then return nil end
    -- Рецепт должен быть ИЗУЧЕН, иначе заряды не показываем
    if C_TradeSkillUI.GetRecipeInfo then
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if not (info and info.learned) then return nil end
    end
    local ok, cooldown, _, charges, maxCharges = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
    if not ok then return nil end
    if not maxCharges or maxCharges == 0 then return nil end
    return {
        cur = charges or 0,
        max = maxCharges,
        cd = cooldown, -- секунд до следующего заряда на момент скана
        ts = (GetServerTime and GetServerTime()) or 0,
        period = PeriodForMax(maxCharges),
    }
end

-- Записать текущего персонажа в ростер (не затираем то, что не готово).
function Roster.ScanCurrent()
    if not ns.db or not ns.db.roster then return end
    local guid = UnitGUID and UnitGUID("player")
    if not guid then return end

    local e = ns.db.roster[guid] or {}
    ns.db.roster[guid] = e
    e.name = UnitName("player") or e.name
    e.realm = (GetRealmName and GetRealmName()) or e.realm or ""
    e.classFile = select(2, UnitClass("player")) or e.classFile
    e.lastUpdate = (GetServerTime and GetServerTime()) or 0

    -- Профессии + недельный квест/трактат (name, icon, base, weeklyDone, treatiseDone)
    -- и концентрация по каждой профессии.
    if ns.Tools and ns.Tools.GetWeeklyKnowledge then
        local oldProfs = e.profs
        local profs = ns.Tools.GetWeeklyKnowledge()
        if profs and #profs > 0 then
            for _, p in ipairs(profs) do
                local cid = p.base and CONC_CURRENCY[p.base]
                if cid and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cid)
                    if ok and info and (info.maxQuantity or 0) > 0 then
                        p.conc = {
                            cur = info.quantity or 0,
                            max = info.maxQuantity or 0,
                            cycleMs = info.rechargingCycleDurationMS or 0,
                            perCycle = info.rechargingAmountPerCycle or 0,
                            ts = (GetServerTime and GetServerTime()) or 0,
                        }
                    end
                end
                -- если валюта не прочиталась — сохраняем прежнюю концентрацию
                if not p.conc and oldProfs then
                    for _, op in ipairs(oldProfs) do
                        if op.base == p.base and op.conc then p.conc = op.conc; break end
                    end
                end
            end
            e.profs = profs
        end
    end

    -- Abundant Offerings (общий объектив)
    if ns.Tools and ns.Tools.GetGlobalKnowledge then
        local g = ns.Tools.GetGlobalKnowledge()
        e.abundant = (g[1] and g[1].done) or false
    end

    -- Заряды рецептов алхимии — читаем только если у персонажа есть алхимия
    -- (база 171) и рецепт изучен. Иначе чистим — чтобы не висели чужие/старые
    -- заряды у персонажей без алхимии.
    e.charges = e.charges or {}
    local hasAlchemy = false
    if e.profs then
        for _, p in ipairs(e.profs) do
            if p.base == 171 then hasAlchemy = true; break end
        end
    end
    if not hasAlchemy then
        wipe(e.charges)
    else
        for _, rid in ipairs(CHARGE_RECIPES) do
            local c = ReadCharges(rid)
            if c then
                e.charges[rid] = c
            elseif C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
                -- рецепт есть в API, но не изучен → убираем старую запись
                local info = C_TradeSkillUI.GetRecipeInfo(rid)
                if info and info.learned == false then e.charges[rid] = nil end
            end
        end
    end
end

-- Список всех записанных персонажей, свежие сверху.
function Roster.GetAll()
    local list = {}
    if not ns.db or not ns.db.roster then return list end
    for guid, e in pairs(ns.db.roster) do
        e.guid = guid
        list[#list + 1] = e
    end
    table.sort(list, function(a, b)
        return (a.lastUpdate or 0) > (b.lastUpdate or 0)
    end)
    return list
end

-- Удалить персонажа из ростера (для контекстного меню окна).
function Roster.Delete(guid)
    if ns.db and ns.db.roster then ns.db.roster[guid] = nil end
end

-- -------------------------------------------------------------------------
-- Кнопка миникарты
-- -------------------------------------------------------------------------
local minimapButton

local function UpdatePosition()
    if not minimapButton or not ns.db or not Minimap then return end
    local angle = math.rad(ns.db.knowledge.minimapAngle or 205)
    -- радиус от текущего размера миникарты — чтобы кнопка липла к границе
    -- при любом её размере (а не висела в стороне при фиксированных 80)
    local r = (Minimap:GetWidth() / 2) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        r * math.cos(angle), r * math.sin(angle))
end

local function CreateMinimapButton()
    if minimapButton then return minimapButton end
    if not Minimap then return nil end

    local b = CreateFrame("Button", "RainonUIMinimapButton", Minimap)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetSize(31, 31)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\AddOns\\RainonUI\\Media\\logo")
    icon:SetPoint("TOPLEFT", 7, -6)
    b.icon = icon

    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            -- ПКМ — окно знаний и зарядов
            if ns.Knowledge and ns.Knowledge.Toggle then ns.Knowledge:Toggle() end
        else
            -- ЛКМ — главное меню настроек аддона (/rs)
            if SlashCmdList and SlashCmdList.RAINONUI then SlashCmdList.RAINONUI("") end
        end
    end)
    b:SetScript("OnDragStart", function()
        b:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            if not (mx and px and scale and scale > 0) then return end
            px, py = px / scale, py / scale
            ns.db.knowledge.minimapAngle = math.deg(math.atan2(py - my, px - mx))
            UpdatePosition()
        end)
    end)
    b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("RainonUI", 1, 1, 1)
        GameTooltip:AddLine("ЛКМ — меню настроек аддона.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("ПКМ — окно знаний и зарядов.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Перетаскивание — двигать кнопку.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    minimapButton = b
    UpdatePosition()
    return b
end

-- Показать/скрыть кнопку миникарты по мастер-флагу и настройке.
function Roster.UpdateMinimap()
    if not ns.db then return end
    local want = ns.ProfEnabled() and not ns.db.knowledge.hideMinimap
    if want then
        if CreateMinimapButton() then
            UpdatePosition()
            minimapButton:Show()
        end
    elseif minimapButton then
        minimapButton:Hide()
    end
end

-- -------------------------------------------------------------------------
-- События: скан при открытии профессии / обновлении рецептов / квестах
-- -------------------------------------------------------------------------
local function scanAndRefresh()
    Roster.ScanCurrent()
    if ns.Knowledge and ns.Knowledge.Refresh then ns.Knowledge:Refresh() end
end

ns.RegisterEvent("TRADE_SKILL_SHOW", scanAndRefresh)
ns.RegisterEvent("TRADE_SKILL_LIST_UPDATE", scanAndRefresh)
ns.RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", scanAndRefresh)
ns.RegisterEvent("QUEST_TURNED_IN", scanAndRefresh)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(2, function()
        Roster.ScanCurrent()
        Roster.UpdateMinimap()
    end)
end)
ns.RegisterMessage("RAINON_REAPPLY", function()
    Roster.ScanCurrent()
    Roster.UpdateMinimap()
end)