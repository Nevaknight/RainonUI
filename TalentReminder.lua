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

-- ТЕСТОВЫЕ данные «против кого использовать талант» (клик по таланту → окно
-- мобов с 3D-моделью). Позже вынесем в DATA-таблицу по подземельям (теги).
-- COUNTERS[talentSpellID] = { { npc=npcID, ability="имя", note="что делать" }, ... }
-- npc/name/g — из MDT (KingsRest); spell — для игровой ссылки/тултипа; icon —
-- иконка способности. Позже вынесем в DATA-таблицу по подземельям.
local COUNTERS = {
    [1022] = { -- Blessing of Protection
        { npc = 269811, dungeon = 1762, name = "Kula the Butcher", g = "13, 20, 27",
          spell = 266231, icon = 132215, ability = "Увечащий топор",
          note = "Снимаем с союзника" },
        { npc = 135167, dungeon = 1762, name = "Royal Berserker", g = "22, 24, 25, 26, 30",
          icon = 132215, ability = "Кровожадный топор",
          note = "Снимаем с себя и сразу скидываем БоП" },
    },
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

-- Локализованное имя НПЦ по npcID (из клиента игры). Строим unit-ссылку с
-- фиктивным GUID и читаем тултип — имя приходит на языке клиента. Кэшируем.
-- Фолбэк — англ. имя из MDT (передаём), если API недоступен.
local npcNameCache = {}
local function NpcName(id, fallback)
    if npcNameCache[id] then return npcNameCache[id] end
    local nm
    pcall(function()
        if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            local data = C_TooltipInfo.GetHyperlink(("unit:Creature-0-0-0-0-%d-0000000000"):format(id))
            if data and data.lines and data.lines[1] then nm = data.lines[1].leftText end
        end
    end)
    if not nm or nm == "" then nm = fallback or ("НПЦ " .. tostring(id)) end
    npcNameCache[id] = nm
    return nm
end

local function DungeonTex(mapID)
    if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local _, _, _, tex = C_ChallengeMode.GetMapUIInfo(mapID)
        if tex then return tex end
    end
    return 525134
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
        -- у талантов с данными «против кого» строка кликабельна (подсветка)
        if COUNTERS[id] then
            row.hover:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        end
        row.hover:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(function() GameTooltip:SetSpellByID(row.id) end)
            if not ok then GameTooltip:SetText(SpellName(row.id)) end
            if COUNTERS[row.id] then
                GameTooltip:AddLine("Клик — против кого использовать", 0.4, 0.8, 1)
            end
            GameTooltip:Show()
        end)
        row.hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.hover:SetScript("OnClick", function()
            if COUNTERS[row.id] then TR.ShowCounters(row.id) end
        end)

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
-- Окно «против кого использовать талант» (клик по таланту).
-- Строка = 3D-модель моба (SetCreature, как MDT) | способность | что делать.
-- -------------------------------------------------------------------------
local cwin, crows = nil, {}
local curCounters   -- текущий список (для агрегации по НПЦ в большом окне)
local C_ROW_H, C_MODEL, C_PAD, C_TITLE, C_BOT = 76, 60, 12, 26, 12

function TR.ShowCounters(talentID)
    local data = COUNTERS[talentID]
    if not data then return end
    curCounters = data

    if not cwin then
        cwin = CreateFrame("Frame", "RainonUITalentCounters", UIParent, "ButtonFrameTemplate")
        cwin:SetFrameStrata("DIALOG"); cwin:SetToplevel(true)
        cwin:SetMovable(true); cwin:EnableMouse(true); cwin:RegisterForDrag("LeftButton")
        cwin:SetScript("OnDragStart", cwin.StartMoving)
        cwin:SetScript("OnDragStop", cwin.StopMovingOrSizing)
        table.insert(UISpecialFrames, "RainonUITalentCounters")
        cwin.host = cwin.Inset or cwin
    end

    -- заголовок = имя таланта, по центру рамки
    if cwin.SetTitle then pcall(cwin.SetTitle, cwin, SpellName(talentID)) end
    local titleFS = (cwin.TitleContainer and cwin.TitleContainer.TitleText) or cwin.TitleText
    if titleFS then
        titleFS:SetText(SpellName(talentID))
        titleFS:ClearAllPoints(); titleFS:SetPoint("TOP", cwin, "TOP", 0, -6); titleFS:SetJustifyH("CENTER")
    end
    -- портрет = иконка таланта
    pcall(function()
        local p = cwin.PortraitContainer and cwin.PortraitContainer.portrait or cwin.portrait
        if p then p:SetTexture((ns.GetSpellTexture and ns.GetSpellTexture(talentID)) or 134400)
            p:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end)

    local host = cwin.host
    cwin:ClearAllPoints(); cwin:SetPoint("CENTER")
    cwin:SetSize(380, (C_TITLE + 8) + (10 + #data * C_ROW_H + 10) + C_BOT)
    if cwin.Inset then
        cwin.Inset:ClearAllPoints()
        cwin.Inset:SetPoint("TOPLEFT", cwin, "TOPLEFT", 4, -(C_TITLE + 8))
        cwin.Inset:SetPoint("BOTTOMRIGHT", cwin, "BOTTOMRIGHT", -6, C_BOT)
    end

    for _, r in ipairs(crows) do r:Hide() end
    local y = -8
    for i, e in ipairs(data) do
        local r = crows[i]
        if not r then
            r = CreateFrame("Frame", nil, host)
            r.model = CreateFrame("PlayerModel", nil, r)
            r.model:SetSize(C_MODEL, C_MODEL)
            r.model:SetPoint("LEFT", r, "LEFT", 6, 0)
            r.model:EnableMouse(true)
            r.model:SetScript("OnMouseUp", function()
                if r._entry then TR.ShowNpc(r._entry) end
            end)
            r.model:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(r._entry and r._entry.name or "")
                GameTooltip:AddLine("Клик — крупно", 0.4, 0.8, 1)
                GameTooltip:Show()
            end)
            r.model:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Три строки: имя НПЦ | иконка+способность | текст.
            r.npcName = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.npcName:SetPoint("TOPLEFT", r.model, "TOPRIGHT", 12, -8)
            r.npcName:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.npcName:SetJustifyH("LEFT")
            r.ability = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.ability:SetPoint("TOPLEFT", r.npcName, "BOTTOMLEFT", 0, -5)
            r.ability:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.ability:SetJustifyH("LEFT")
            r.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.note:SetPoint("TOPLEFT", r.ability, "BOTTOMLEFT", 0, -5)
            r.note:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.note:SetJustifyH("LEFT"); r.note:SetWordWrap(true)
            crows[i] = r
        end
        r._entry = e
        r:SetHeight(C_ROW_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", host, "TOPLEFT", C_PAD, y)
        r:SetPoint("TOPRIGHT", host, "TOPRIGHT", -C_PAD, y)
        pcall(function()
            r.model:SetCreature(e.npc)
            r.model:SetCamDistanceScale(1.4)
            r.model:SetPortraitZoom(0.35)
        end)
        r.npcName:SetText(NpcName(e.npc, e.name))
        local ic = e.icon and ("|T" .. e.icon .. ":16:16:0:0:64:64:5:59:5:59|t ") or ""
        r.ability:SetText(ic .. ns.C("71D5FF", e.ability))
        r.note:SetText(e.note)
        r:Show()
        y = y - C_ROW_H
    end

    cwin:Show(); cwin:Raise()
end

-- -------------------------------------------------------------------------
-- Окно-деталь одного моба (клик по 3D-модели). Ширина как «Напоминание о
-- талантах», но выше — крупная модель. Заголовок = имя НПЦ, ниже «G …»,
-- потом способность (игровой тултип) и текст.
-- -------------------------------------------------------------------------
local nwin, nabs = nil, {}
local N_W, N_TITLE, N_BOT, N_MODEL, N_AB = 340, 26, 12, 260, 52

function TR.ShowNpc(e)
    if not e then return end
    -- собрать ВСЕ способности этого НПЦ из текущего списка (может быть несколько)
    local list = {}
    if curCounters then
        for _, x in ipairs(curCounters) do if x.npc == e.npc then list[#list + 1] = x end end
    end
    if #list == 0 then list = { e } end

    if not nwin then
        nwin = CreateFrame("Frame", "RainonUITalentNpc", UIParent, "ButtonFrameTemplate")
        nwin:SetFrameStrata("FULLSCREEN_DIALOG"); nwin:SetToplevel(true)
        nwin:SetMovable(true); nwin:EnableMouse(true); nwin:RegisterForDrag("LeftButton")
        nwin:SetScript("OnDragStart", nwin.StartMoving)
        nwin:SetScript("OnDragStop", nwin.StopMovingOrSizing)
        table.insert(UISpecialFrames, "RainonUITalentNpc")
        nwin.host = nwin.Inset or nwin
        -- строка «G …» под заголовком (на фоне рамки)
        nwin.GLine = nwin:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nwin.GLine:SetPoint("TOP", nwin, "TOP", 0, -(N_TITLE + 2))
        nwin.GLine:SetJustifyH("CENTER")
        -- крупная модель сверху инсета
        nwin.model = CreateFrame("PlayerModel", nil, nwin.host)
        nwin.model:SetPoint("TOPLEFT", nwin.host, "TOPLEFT", 10, -10)
        nwin.model:SetPoint("TOPRIGHT", nwin.host, "TOPRIGHT", -10, -10)
        nwin.model:SetHeight(N_MODEL)
    end
    local host = nwin.host

    -- заголовок = имя НПЦ (локализованное из клиента)
    local title = NpcName(e.npc, e.name)
    if nwin.SetTitle then pcall(nwin.SetTitle, nwin, title) end
    local titleFS = (nwin.TitleContainer and nwin.TitleContainer.TitleText) or nwin.TitleText
    if titleFS then
        titleFS:SetText(title)
        titleFS:ClearAllPoints(); titleFS:SetPoint("TOP", nwin, "TOP", 0, -6); titleFS:SetJustifyH("CENTER")
    end
    -- портрет рамки = иконка ПОДЗЕМЕЛЬЯ (способностей может быть несколько)
    pcall(function()
        local p = nwin.PortraitContainer and nwin.PortraitContainer.portrait or nwin.portrait
        if p then p:SetTexture(DungeonTex(e.dungeon)); p:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end)

    nwin.GLine:SetText(ns.C("FFD100", "G ") .. (e.g or "?"))
    pcall(function()
        nwin.model:SetCreature(e.npc)
        nwin.model:SetCamDistanceScale(1.0)
        nwin.model:SetPortraitZoom(0)
    end)

    -- список способностей под моделью (иконка+способность c игровым тултипом + текст)
    for _, ab in ipairs(nabs) do ab.frame:Hide() end
    local ay = -10
    for i, x in ipairs(list) do
        local ab = nabs[i]
        if not ab then
            ab = {}
            ab.frame = CreateFrame("Button", nil, host)
            ab.frame:SetHeight(N_AB)
            ab.text = ab.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            ab.text:SetPoint("TOPLEFT", 0, 0); ab.text:SetJustifyH("LEFT")
            ab.note = ab.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            ab.note:SetPoint("TOPLEFT", ab.text, "BOTTOMLEFT", 0, -5)
            ab.note:SetPoint("RIGHT", ab.frame, "RIGHT", 0, 0)
            ab.note:SetJustifyH("LEFT"); ab.note:SetWordWrap(true)
            ab.frame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if ab._spell then
                    local ok = pcall(function() GameTooltip:SetSpellByID(ab._spell) end)
                    if not ok then GameTooltip:SetText(ab._name or "") end
                else GameTooltip:SetText(ab._name or "") end
                GameTooltip:Show()
            end)
            ab.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
            nabs[i] = ab
        end
        ab.frame:ClearAllPoints()
        ab.frame:SetPoint("TOPLEFT", nwin.model, "BOTTOMLEFT", 0, ay)
        ab.frame:SetPoint("RIGHT", host, "RIGHT", -10, 0)
        local ic = x.icon and ("|T" .. x.icon .. ":18:18:0:0:64:64:5:59:5:59|t ") or ""
        ab.text:SetText(ic .. ns.C("71D5FF", x.ability or ""))
        ab.note:SetText(x.note or "")
        ab._spell = x.spell; ab._name = x.ability
        ab.frame:Show()
        ay = ay - N_AB
    end

    -- размер окна + инсет под контент
    local h = (N_TITLE + 22) + (10 + N_MODEL + #list * N_AB + 10) + N_BOT
    nwin:SetSize(N_W, h)
    nwin:ClearAllPoints(); nwin:SetPoint("CENTER")
    if nwin.Inset then
        nwin.Inset:ClearAllPoints()
        nwin.Inset:SetPoint("TOPLEFT", nwin, "TOPLEFT", 4, -(N_TITLE + 22))
        nwin.Inset:SetPoint("BOTTOMRIGHT", nwin, "BOTTOMRIGHT", -6, N_BOT)
    end
    nwin:Show(); nwin:Raise()
end

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
    ns.Tester.Add("Подземелья", "Против кого: Благословение защиты",
        function() TR.ShowCounters(1022) end)
end
