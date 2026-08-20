-- =========================================================================
-- RainonUI / TalentReminder (ЭКСПЕРИМЕНТАЛЬНЫЙ, тестовый модуль).
-- Идея заимствована из MythicPlusUtility: напоминаем игроку про важные
-- ПОЛЕЗНЫЕ таланты для подземелий. В коде — ТОЛЬКО паладин (другие классы
-- не заводим — так решили).
--
-- Окно в классическом стиле Blizzard (ButtonFrameTemplate). Показывает список
-- ключевых талантов паладина и статус «Изучен / Не изучен». Открывается:
--   • кнопкой из тестера («Подземелья → Напоминание о талантах»);
--   • слэшем /rstalent;
--   • автоматически при входе в подземелье, если модуль включён галкой
--     «Напоминание о талантах» (вкладка «Подземелья») и чего-то не хватает.
-- Галка по умолчанию ВЫКЛ (тестовая функция).
-- =========================================================================
local _, ns = ...

ns.TalentReminder = ns.TalentReminder or {}
local TR = ns.TalentReminder

-- Важные таланты паладина (класс-общие, полезные в M+). spellID.
-- Источник набора — MythicPlusUtility (utilityAbilities.PALADIN, без базовых
-- «Божественный щит»/«Молот правосудия», которые есть всегда).
local PALADIN_TALENTS = {
    1044,    -- Благословение свободы
    1022,    -- Благословение защиты
    10326,   -- Изгнание зла
    115750,  -- Ослепляющий свет
    469304,  -- Скакун свободы
    469321,  -- Праведная защита
}

-- -------------------------------------------------------------------------
-- Помощники API (12.1: спелл-функции в C_Spell)
-- -------------------------------------------------------------------------
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info and info.name then return info.name end
    end
    return "spell:" .. tostring(id)
end

-- Знает ли игрок этот талант/спелл. IsPlayerSpell учитывает таланты.
local function IsKnown(id)
    local known = false
    pcall(function()
        if IsPlayerSpell then known = IsPlayerSpell(id) and true or false end
    end)
    return known
end

local function IsPaladin()
    return select(2, UnitClass("player")) == "PALADIN"
end

-- Сколько важных талантов НЕ изучено.
local function MissingCount()
    local n = 0
    for _, id in ipairs(PALADIN_TALENTS) do
        if not IsKnown(id) then n = n + 1 end
    end
    return n
end

-- -------------------------------------------------------------------------
-- Окно (ButtonFrameTemplate — классические текстуры Blizzard)
-- -------------------------------------------------------------------------
local win
local rows = {}

local PAD    = 14      -- отступ от рамки инсета
local ROW_H  = 30      -- высота строки таланта
local ICON   = 24      -- размер иконки
local WIN_W  = 340

local function BuildWindow()
    if win then return win end

    win = CreateFrame("Frame", "RainonUITalentReminder", UIParent, "ButtonFrameTemplate")
    win:SetSize(WIN_W, 360)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    -- закрытие по Esc
    table.insert(UISpecialFrames, "RainonUITalentReminder")

    -- Заголовок. Сначала штатный SetTitle (чтобы не был пустым), затем
    -- насильно центрируем сам FontString по всей ширине рамки — иначе с
    -- портретом он уезжает вправо (у ButtonFrameTemplate текст цепляется за
    -- контейнер, а не за центр окна).
    if win.SetTitle then pcall(win.SetTitle, win, "Напоминание о талантах") end
    local titleFS = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
    if titleFS then
        titleFS:SetText("Напоминание о талантах")
        titleFS:ClearAllPoints()
        titleFS:SetPoint("TOP", win, "TOP", 0, -6)
        titleFS:SetJustifyH("CENTER")
    end

    -- Портрет: регион запоминаем, картинку ставим в Refresh (подземелье может
    -- смениться между показами).
    win.Portrait = win.PortraitContainer and win.PortraitContainer.portrait or win.portrait

    -- Тёмный бокс-инсет содержит ТОЛЬКО строки талантов. Пояснение — НАД ним
    -- (на фоне рамки), кнопка — в нижней полосе ПОД ним. Геометрию инсета и
    -- высоту окна пересчитываем в Refresh.
    local host = win.Inset or win

    -- Подзаголовок-пояснение (родитель — само окно, чтобы стоять НАД инсетом).
    local sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetJustifyH("LEFT")
    win.Sub = sub

    -- Строки талантов (иконка | название | статус) — внутри инсета.
    for i, id in ipairs(PALADIN_TALENTS) do
        local row = {}
        row.id = id

        row.icon = host:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon:SetTexture((ns.GetSpellTexture and ns.GetSpellTexture(id)) or 134400)

        row.name = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetJustifyH("LEFT")

        row.status = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.status:SetJustifyH("RIGHT")

        -- Прозрачная кнопка-ловушка на всю строку: наведение показывает ТУ ЖЕ
        -- подсказку, что и по линку способности в игре, через spellID —
        -- поэтому текст всегда на языке клиента, независимо от локали.
        row.hover = CreateFrame("Button", nil, host)
        row.hover:SetHeight(ICON)
        row.hover:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(function() GameTooltip:SetSpellByID(row.id) end)
            if not ok then GameTooltip:SetText(SpellName(row.id)) end
            GameTooltip:Show()
        end)
        row.hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

        rows[i] = row
    end

    -- Кнопка «Открыть окно талантов» — родитель окно (стоит в нижней полосе).
    local openBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    openBtn:SetSize(WIN_W - PAD * 2 - 16, 24)
    openBtn:SetText("Открыть окно талантов")
    openBtn:SetScript("OnClick", function()
        if InCombatLockdown() then
            ns.Print("окно талантов нельзя открыть в бою.")
            return
        end
        local ok = pcall(function()
            if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
                PlayerSpellsUtil.ToggleClassTalentFrame()
            elseif PlayerSpellsMicroButton then
                PlayerSpellsMicroButton:Click()
            end
        end)
        if not ok then ns.Print("не удалось открыть окно талантов.") end
    end)
    win.OpenBtn = openBtn

    win:Hide()
    return win
end

-- Портрет: иконка текущего подземелья (Журнал Приключений по карте игрока),
-- иначе — эмблема класса паладина. Всё в pcall — API может отсутствовать.
local function SetPortrait()
    local p = win and win.Portrait
    if not p then return end
    local done = false
    pcall(function()
        local inInstance, itype = IsInInstance()
        if inInstance and itype == "party"
            and C_Map and C_Map.GetBestMapForUnit and EJ_GetInstanceForMap then
            local mapID = C_Map.GetBestMapForUnit("player")
            local instID = mapID and EJ_GetInstanceForMap(mapID)
            if instID and instID > 0 then
                if EJ_SelectInstance then EJ_SelectInstance(instID) end
                local _, _, _, _, buttonImage = EJ_GetInstanceInfo(instID)
                if buttonImage then
                    p:SetTexture(buttonImage)
                    p:SetTexCoord(0, 1, 0, 1)
                    done = true
                end
            end
        end
    end)
    if not done then
        -- эмблема класса паладина (классический атлас кружков классов)
        pcall(function()
            p:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS["PALADIN"]
            if c then p:SetTexCoord(c[1], c[2], c[3], c[4])
            else p:SetTexCoord(0, 0.25, 0.75, 1) end
        end)
    end
end

-- Раскладка (в пикселях от верха рамки):
local TITLEBAR   = 24   -- высота плашки заголовка (портрет живёт тут же)
local PORTRAIT_CLEAR = 64  -- левый отступ пояснения, чтобы не лезло под портрет
local BOTTOM_BAR = 40   -- нижняя полоса рамки под инсетом (там кнопка)
local INSET_TOPPAD = 12 -- отступ первой строки от верха инсета
local INSET_BOTPAD = 10 -- отступ низа инсета под последней строкой

-- Перерисовать содержимое под текущие таланты.
local function Refresh()
    if not win then return end
    local host = win.Inset or win

    SetPortrait()

    local paladin = IsPaladin()
    if paladin then
        win.Sub:SetText("Проверь ключевые таланты паладина перед подземельем:")
    else
        win.Sub:SetText(ns.C("FFD100", "Этот модуль рассчитан на паладина.") ..
            " Ниже — список для примера.")
    end

    -- Пояснение НАД инсетом (на фоне рамки). Слева отступаем на ширину портрета
    -- (PORTRAIT_CLEAR), чтобы текст не заходил под круглую иконку в шапке.
    local subTop = TITLEBAR + 6
    win.Sub:ClearAllPoints()
    win.Sub:SetPoint("TOPLEFT", win, "TOPLEFT", PORTRAIT_CLEAR, -subTop)
    win.Sub:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -subTop)
    local subH = math.ceil(win.Sub:GetStringHeight())

    -- Инсет: верх — сразу под пояснением, низ — оставляем нижнюю полосу.
    local insetTopY = -(subTop + subH + 8)
    if win.Inset then
        win.Inset:ClearAllPoints()
        win.Inset:SetPoint("TOPLEFT", win, "TOPLEFT", 4, insetTopY)
        win.Inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, BOTTOM_BAR)
    end

    -- Строки талантов — от ВЕРХА инсета вниз.
    local y = -INSET_TOPPAD
    for _, row in ipairs(rows) do
        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, y)
        row.name:SetText(SpellName(row.id))

        row.hover:ClearAllPoints()
        row.hover:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, y)
        row.hover:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, y)

        row.status:ClearAllPoints()
        row.status:SetPoint("RIGHT", host, "RIGHT", -PAD, 0)
        row.status:SetPoint("TOP", row.icon, "TOP", 0, -4)
        if paladin and IsKnown(row.id) then
            row.status:SetText(ns.C("40D040", "Изучен"))
            row.name:SetTextColor(1, 1, 1)
        else
            row.status:SetText(ns.C("FF5555", "Не изучен"))
            row.name:SetTextColor(0.7, 0.7, 0.7)
        end
        y = y - ROW_H
    end

    -- Кнопка — по центру нижней полосы (гориз. центр рамки + центр по высоте
    -- полосы BOTTOM_BAR). Родитель — окно, поэтому цепляемся за его низ.
    win.OpenBtn:ClearAllPoints()
    win.OpenBtn:SetPoint("BOTTOM", win, "BOTTOM", 0, (BOTTOM_BAR - 24) / 2)

    -- Высота окна: пояснение + инсет (строки) + нижняя полоса.
    local insetInnerH = INSET_TOPPAD + #rows * ROW_H + INSET_BOTPAD
    win:SetHeight((subTop + subH + 8) + insetInnerH + BOTTOM_BAR)
end
TR.Refresh = Refresh

-- -------------------------------------------------------------------------
-- Публичный показ
-- -------------------------------------------------------------------------
function TR.Show()
    BuildWindow()
    Refresh()
    win:Show()
    win:Raise()
end

-- Тест из панели «Тестер»: всегда показываем окно (даже если всё изучено).
function TR.Test()
    TR.Show()
end

function TR.Toggle()
    BuildWindow()
    if win:IsShown() then win:Hide() else TR.Show() end
end

-- -------------------------------------------------------------------------
-- Автопоказ при входе в подземелье (если модуль включён галкой)
-- -------------------------------------------------------------------------
local lastInstanceID
local function MaybeAutoShow()
    if not (ns.db and ns.db.features and ns.db.features.talentReminder) then return end
    if not IsPaladin() then return end
    if InCombatLockdown() then return end

    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then return end

    -- один показ на вход в конкретный экземпляр подземелья
    local id = select(8, GetInstanceInfo())
    if id and id == lastInstanceID then return end
    lastInstanceID = id

    if MissingCount() > 0 then
        TR.Show()
    end
end
ns.RegisterEvent("PLAYER_ENTERING_WORLD", MaybeAutoShow)
ns.RegisterEvent("CHALLENGE_MODE_START", function()
    lastInstanceID = nil
    MaybeAutoShow()
end)

-- -------------------------------------------------------------------------
-- Слэш + кнопка тестера
-- -------------------------------------------------------------------------
SLASH_RAINONTALENT1 = "/rstalent"
SlashCmdList.RAINONTALENT = function() TR.Toggle() end

-- Кнопка в панели «Тестер» (вызвать ДО первого открытия панели — она ленивая).
if ns.Tester and ns.Tester.Add then
    ns.Tester.Add("Подземелья", "Напоминание о талантах", TR.Test)
end
