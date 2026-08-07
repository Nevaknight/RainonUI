-- =========================================================================
-- RainonUI / SoundTracker: ловля воспроизводимых звуков в стилизованное окно.
--
-- Этап 1 — просто ловить: перехватываем Lua-функции PlaySound / PlaySoundFile
-- (hooksecurefunc — taint-безопасно, внутри только чтение + своё окно) и
-- показываем пойманные звуки списком: имя | ID | сколько раз. Клик по строке —
-- переиграть звук (проверить, тот ли).
--
-- ЧЕСТНО о границе: ловятся только звуки, запущенные ЧЕРЕЗ Lua (интерфейс,
-- оповещения, часть событий). Звуки, которые движок играет сам (многие звуки
-- способностей/боя/озвучки), в Lua НЕ проходят — их не поймает ни один аддон,
-- ID таких звуков берут на wago.tools/sounds. Приглушение (этап 2) — позже,
-- через MuteSoundFile(fileDataID).
-- =========================================================================
local _, ns = ...
local _issecret = issecretvalue or function() return false end

local Sound = {}
ns.SoundTracker = Sound

local active = false
local captured, order = {}, {}   -- captured[key]={id,kind,name,count}; order=ключи (новые сверху)

-- Обратный поиск имени по SOUNDKIT (id → имя константы, напр. IG_MAINMENU_OPEN)
local kitName, kitBuilt = {}, false
local function KitName(id)
    if not kitBuilt then
        kitBuilt = true
        if type(SOUNDKIT) == "table" then
            for n, v in pairs(SOUNDKIT) do kitName[v] = n end
        end
    end
    return kitName[id]
end

-- -------------------------------------------------------------------------
-- Окно
-- -------------------------------------------------------------------------
local panel, content, rows
local ROW_H = 20

local function EntryLabel(e)
    if e.kind == "kit" then
        return e.name or "SoundKit", "kit " .. tostring(e.id)
    elseif e.kind == "path" then
        return "файл-путь", tostring(e.id)
    else
        return "звук-файл", tostring(e.id)   -- FileDataID (его глушим MuteSoundFile)
    end
end

local function BuildRow(i)
    local r = CreateFrame("Button", nil, content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ROW_H)

    r.Bg = r:CreateTexture(nil, "BACKGROUND")
    r.Bg:SetAllPoints()
    r.Bg:SetColorTexture(1, 1, 1, 0.05)

    r.Hi = r:CreateTexture(nil, "HIGHLIGHT")
    r.Hi:SetAllPoints()
    r.Hi:SetColorTexture(1, 0.82, 0, 0.12)

    r.Id = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.Id:SetPoint("RIGHT", -8, 0)

    r.Cnt = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.Cnt:SetPoint("RIGHT", r.Id, "LEFT", -8, 0)

    r.Name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.Name:SetPoint("LEFT", 8, 0)
    r.Name:SetPoint("RIGHT", r.Cnt, "LEFT", -6, 0)
    r.Name:SetJustifyH("LEFT")
    r.Name:SetWordWrap(false)

    r:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.kind == "kit" then pcall(PlaySound, e.id)
        else pcall(PlaySoundFile, e.id, "Master") end
    end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Клик — переиграть звук", 1, 1, 1)
        if self.entry then
            GameTooltip:AddLine("ID: " .. tostring(self.entry.id), 0.8, 0.8, 0.8)
            if self.entry.kind == "file" then
                GameTooltip:AddLine("Это FileDataID — его можно будет заглушить.", 0.6, 0.8, 1, true)
            end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function Refresh()
    if not (panel and panel:IsShown()) then return end
    rows = rows or {}
    if content and content:GetParent() then
        local w = content:GetParent():GetWidth()
        if w and w > 0 then content:SetWidth(w) end
    end
    local n = 0
    for i = 1, #order do
        local e = captured[order[i]]
        if e then
            n = n + 1
            local r = rows[n] or BuildRow(n)
            rows[n] = r
            r.entry = e
            local nm, idText = EntryLabel(e)
            r.Name:SetText(nm)
            r.Id:SetText(idText)
            r.Cnt:SetText(e.count > 1 and ("×" .. e.count) or "")
            r.Bg:SetShown((n % 2) == 0)
            r:Show()
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(n * ROW_H, 1))
end

local refreshPending = false
local function ScheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.2, function() refreshPending = false; Refresh() end)
end

local MAX_ENTRIES = 300
local function Record(kind, id)
    if not active or id == nil or _issecret(id) then return end
    local key = kind .. ":" .. tostring(id)
    local e = captured[key]
    if e then
        e.count = e.count + 1
    else
        e = { id = id, kind = kind, count = 1 }
        if kind == "kit" then e.name = KitName(id) end
        captured[key] = e
        table.insert(order, 1, key)
        if #order > MAX_ENTRIES then
            local drop = table.remove(order)        -- убираем самый старый
            if drop then captured[drop] = nil end
        end
    end
    ScheduleRefresh()
end

local function ClearAll()
    wipe(captured); wipe(order)
    Refresh()
end

-- -------------------------------------------------------------------------
-- Хуки (ставим один раз при первом включении; при выключении Record молчит)
-- -------------------------------------------------------------------------
local hooked = false
local function InstallHooks()
    if hooked then return end
    hooked = true
    if type(PlaySound) == "function" then
        hooksecurefunc("PlaySound", function(kit) Record("kit", kit) end)
    end
    if type(PlaySoundFile) == "function" then
        hooksecurefunc("PlaySoundFile", function(file)
            Record(type(file) == "number" and "file" or "path", file)
        end)
    end
end

-- -------------------------------------------------------------------------
-- Панель — в стиле главного окна RainonUI: DefaultPanelFlatTemplate (прямоугольник
-- без портрета) + тёмный инсет для списка + ScrollFrameTemplate (современная
-- тонкая полоса MinimalScrollBar). Размер вдвое меньше прежнего.
-- -------------------------------------------------------------------------
local function BuildPanel()
    if panel then return panel end
    panel = CreateFrame("Frame", "RainonUISoundTracker", UIParent, "DefaultPanelFlatTemplate")
    panel:SetSize(360, 300)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    if panel.SetTitle then panel:SetTitle("Трекер звуков") end
    table.insert(UISpecialFrames, "RainonUISoundTracker")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)

    -- Состояние + подсказка в одну строку: «Ловлю… Клик по строке — …»
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -30)
    hint:SetPoint("TOPRIGHT", -12, -30)
    hint:SetJustifyH("LEFT")
    local function UpdateState()
        hint:SetText((active and "|cff55ff55Ловлю…|r  " or "|cff888888Пауза|r  ")
            .. "Клик по строке — проиграть звук.")
    end

    -- Тёмный инсет: список живёт ВНУТРИ него, текст не заходит на рамку окна.
    local inset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 10, -46)
    inset:SetPoint("BOTTOMRIGHT", -10, 42)

    local scroll = CreateFrame("ScrollFrame", nil, inset, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)   -- место справа под тонкую полосу
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(scroll:GetWidth() or 180, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

    local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clear:SetSize(70, 22)
    clear:SetPoint("BOTTOMLEFT", 10, 12)
    clear:SetText("Очистить")
    clear:SetScript("OnClick", ClearAll)

    local toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    toggle:SetSize(90, 22)
    toggle:SetPoint("BOTTOMRIGHT", -10, 12)
    toggle:SetText("Старт/Пауза")
    toggle:SetScript("OnClick", function()
        active = not active
        if active then InstallHooks() end
        UpdateState()
        Refresh()
    end)

    panel:SetScript("OnShow", function() UpdateState(); Refresh() end)
    -- Закрыли окно (X / Esc / Toggle) — сразу выключаем ловлю.
    panel:SetScript("OnHide", function() active = false end)
    panel:Hide()
    return panel
end

-- Открыть окно и начать ловить (или просто переключить видимость окна).
function Sound.Toggle()
    BuildPanel()
    if panel:IsShown() then
        panel:Hide()
        active = false
    else
        InstallHooks()
        active = true
        panel:Show()
        Refresh()
    end
end

-- Кнопка в тест-панели (Tester грузится раньше — регистрируем после входа в мир)
local added = false
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if added or not (ns.Tester and ns.Tester.Add) then return end
    added = true
    ns.Tester.Add("Диагностика", "Трекер звуков", function() Sound.Toggle() end)
end)

SLASH_RAINONSOUNDTRACK1 = "/rstrack"
SlashCmdList.RAINONSOUNDTRACK = function() Sound.Toggle() end
