-- =========================================================================
-- RainonUI / Treatise: напоминание о недельном трактате.
--
--  (1) ПОДПИСЬ В ПОДСКАЗКЕ трактата (работает всегда): галочка/крестик
--      «использован / НЕ использован» для профессий текущего персонажа.
--  (2) ПИКСЕЛЬНОЕ СВЕЧЕНИЕ иконки трактата (если он ещё не использован):
--      * в Баганаторе — через его официальный API RegisterCornerWidget;
--      * в обычном банке Blizzard — своим сканом кнопок.
--
-- Диагностика: /rstreatise.
-- =========================================================================
local _, ns = ...

-- itemID трактата -> { base = линия профессии, quest = скрытый квест «изучен» }.
-- Midnight 12.0 (из WeeklyKnowledge Data\Objectives\Treatise.lua).
local TREATISE = {
    [245755] = { base = 171, quest = 95127 }, -- Алхимия
    [245763] = { base = 164, quest = 95128 }, -- Кузнечное дело
    [245759] = { base = 333, quest = 95129 }, -- Наложение чар
    [245809] = { base = 202, quest = 95138 }, -- Инженерное дело
    [245757] = { base = 773, quest = 95131 }, -- Начертание
    [245760] = { base = 755, quest = 95133 }, -- Ювелирное дело
    [245758] = { base = 165, quest = 95134 }, -- Кожевничество
    [245756] = { base = 197, quest = 95137 }, -- Портняжное дело
    [245761] = { base = 182, quest = 95130 }, -- Травничество
    [245762] = { base = 186, quest = 95135 }, -- Горное дело
    [245828] = { base = 393, quest = 95136 }, -- Снятие шкур
}

local READY_TEX    = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOTREADY_TEX = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function TooltipEnabled()
    return not (ns.db and ns.db.features and ns.db.features.treatiseTooltip == false)
end
local function GlowEnabled()
    return not (ns.db and ns.db.features and ns.db.features.treatiseGlow == false)
end

-- Профессии текущего персонажа (базовые ID). Кэш.
local myProfs = {}
local function RebuildProfs()
    wipe(myProfs)
    if not (GetProfessions and GetProfessionInfo) then return end
    local slots = { GetProfessions() }
    for i = 1, 2 do
        local idx = slots[i]
        if idx then
            local _, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
            if skillLine then myProfs[skillLine] = true end
        end
    end
end

local function IsDone(quest)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(quest) and true or false
    end
    if IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(quest) and true or false
    end
    return false
end

-- Трактат itemID, который НАДО подсветить: своя профессия + не использован.
local function ShouldGlowItem(itemID)
    local t = itemID and TREATISE[itemID]
    return t ~= nil and myProfs[t.base] and not IsDone(t.quest)
end

-- =========================================================================
-- (1) Подпись в подсказке предмета
-- =========================================================================
local function OnItemTooltip(tooltip, data)
    if not TooltipEnabled() then return end
    if not (tooltip and tooltip.AddLine) then return end
    local id = data and data.id
    local t = id and TREATISE[id]
    if not (t and myProfs[t.base]) then return end
    local done = IsDone(t.quest)
    local tex = done and READY_TEX or NOTREADY_TEX
    local line = "|T" .. tex .. ":14|t " ..
        (done and "Трактат уже использован на этой неделе"
              or "Трактат ещё НЕ использован")
    if done then tooltip:AddLine(line, 0.4, 1, 0.4)
    else tooltip:AddLine(line, 1, 0.35, 0.35) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
   and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

-- =========================================================================
-- Пиксельное свечение (бегущие пиксели по контуру иконки)
-- =========================================================================
local GLOW_COLOR = { 1, 0.85, 0.30 }   -- золотой «в стиле лого»

local GLOW_SPEED = 0.12   -- оборотов в секунду (меньше = медленнее)
local GLOW_N     = 10     -- число сегментов (меньше = длиннее промежутки)
local GLOW_LEN   = 10     -- длина сегмента-«полоски», px
local GLOW_TH    = 2      -- толщина сегмента, px

-- точка на периметре прямоугольника w×h по параметру t в [0,1);
-- edge: 1=низ, 2=право, 3=верх, 4=лево (для ориентации сегмента).
local function PerimeterPoint(t, w, h)
    local per = 2 * (w + h)
    local d = (t % 1) * per
    if d <= w then return d, 0, 1
    elseif d <= w + h then return w, d - w, 2
    elseif d <= 2 * w + h then return w - (d - w - h), h, 3
    else return 0, h - (d - 2 * w - h), 4 end
end

local function StartPixelGlow(button)
    if not button then return end
    local pg = button._rainonTreatiseGlow
    if not pg then
        local ok = pcall(function()
            pg = CreateFrame("Frame", nil, button)
            pg:SetPoint("TOPLEFT", -1, 1)
            pg:SetPoint("BOTTOMRIGHT", 1, -1)
            pg:SetFrameLevel((button:GetFrameLevel() or 1) + 8)
            pg.dots = {}
            for i = 1, GLOW_N do
                local d = pg:CreateTexture(nil, "OVERLAY", nil, 7)
                d:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], 1)
                pg.dots[i] = d
            end
            pg.phase = 0
            pg:SetScript("OnUpdate", function(self, elapsed)
                self.phase = (self.phase + elapsed * GLOW_SPEED) % 1
                local w, h = self:GetWidth(), self:GetHeight()
                if not w or w < 4 then return end
                for i = 1, GLOW_N do
                    local tt = (self.phase + (i - 1) / GLOW_N) % 1
                    local x, y, edge = PerimeterPoint(tt, w, h)
                    local dot = self.dots[i]
                    -- горизонтальные рёбра — длинная полоска по X, вертикальные — по Y
                    if edge == 1 or edge == 3 then dot:SetSize(GLOW_LEN, GLOW_TH)
                    else dot:SetSize(GLOW_TH, GLOW_LEN) end
                    dot:ClearAllPoints()
                    dot:SetPoint("CENTER", self, "BOTTOMLEFT", x, y)
                end
            end)
        end)
        if not ok or not pg then return end
        button._rainonTreatiseGlow = pg
    end
    pg:Show()
end

local function StopPixelGlow(button)
    local pg = button and button._rainonTreatiseGlow
    if pg then pg:Hide() end
end

-- =========================================================================
-- (2a) Баганатор — через официальный API RegisterCornerWidget
-- =========================================================================
local function ItemIDFromDetails(details)
    if not details then return nil end
    if details.itemID then return details.itemID end
    local link = details.itemLink
    if link then
        if C_Item and C_Item.GetItemInfoInstant then return (C_Item.GetItemInfoInstant(link)) end
        if GetItemInfoInstant then return (GetItemInfoInstant(link)) end
    end
    return nil
end

local baganatorReady = false
local function EnsureBaganator()
    if baganatorReady then return end
    if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then return end
    baganatorReady = true
    -- Виджет-«триггер»: невидимый фрейм в углу; когда Баганатор его показывает
    -- (предмет = наш трактат), запускаем пиксельное свечение на кнопке предмета.
    local ok = pcall(Baganator.API.RegisterCornerWidget,
        "Трактат (RainonUI)", "rainonui_treatise",
        function(widget, details)  -- onUpdate
            if not GlowEnabled() then return false end
            local id = ItemIDFromDetails(details)
            if not id then return false end
            return ShouldGlowItem(id) and true or false
        end,
        function(itemButton)       -- onInit
            local w = CreateFrame("Frame", nil, itemButton)
            w:SetSize(1, 1)
            w._btn = itemButton
            w:HookScript("OnShow", function(self) StartPixelGlow(self._btn) end)
            w:HookScript("OnHide", function(self) StopPixelGlow(self._btn) end)
            return w
        end,
        { corner = "top_left", priority = 1 },
        true) -- isFast: тултип не нужен
    if not ok then baganatorReady = false end
end

local function RequestBaganatorRefresh()
    if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh
       and Baganator.Constants and Baganator.Constants.RefreshReason then
        pcall(Baganator.API.RequestItemButtonsRefresh,
            { Baganator.Constants.RefreshReason.ItemWidgets })
    end
end

-- =========================================================================
-- (2b) Обычный банк/сумки Blizzard — свой скан (когда Баганатор НЕ используется)
-- =========================================================================
local litButtons = {}   -- кнопки, на которых сейчас наше свечение (для очистки)

local function ClearBankGlows()
    for b in pairs(litButtons) do StopPixelGlow(b) end
    wipe(litButtons)
end

local function ButtonItemID(b)
    if b.GetItemLocation then
        local ok, loc = pcall(b.GetItemLocation, b)
        if ok and loc and loc.IsValid and loc:IsValid() and C_Item and C_Item.GetItemID then
            local ok2, id = pcall(C_Item.GetItemID, loc)
            if ok2 and id then return id end
        end
    end
    local bag = b.bankTabID or (b.GetBankTabID and b:GetBankTabID())
    local slot = b.containerSlotID or (b.GetContainerSlotID and b:GetContainerSlotID())
    if not bag and b.GetBagID then local ok, v = pcall(b.GetBagID, b); if ok then bag = v end end
    if not slot and b.GetID then local ok, v = pcall(b.GetID, b); if ok then slot = v end end
    if bag and slot and C_Container and C_Container.GetContainerItemID then
        local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
        if ok and id then return id end
    end
    return nil
end

local function Walk(frame, fn, depth, seen)
    if not frame or depth > 6 or seen[frame] then return end
    seen[frame] = true
    if frame.GetObjectType then
        local ok, otype = pcall(frame.GetObjectType, frame)
        if ok and otype == "Button" then
            local id = ButtonItemID(frame)
            if id then fn(frame, id) end
        end
    end
    if frame.GetChildren then
        local ok, kids = pcall(function() return { frame:GetChildren() } end)
        if ok and kids then
            for _, c in ipairs(kids) do Walk(c, fn, depth + 1, seen) end
        end
    end
end

-- Видимые корни для скана: банк, сундук отряда И обычные сумки Blizzard.
local SCAN_ROOT_NAMES = {
    "AccountBankPanel", "BankPanel", "BankFrame",
    "ContainerFrameCombinedBags",
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
    "ContainerFrame5", "ContainerFrame6", "ContainerFrame7", "ContainerFrame8",
    "ContainerFrame9", "ContainerFrame10", "ContainerFrame11", "ContainerFrame12",
    "ContainerFrame13",
}
local function ScanRoots()
    local roots = {}
    for _, name in ipairs(SCAN_ROOT_NAMES) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then roots[#roots + 1] = f end
    end
    return roots
end

local function RefreshBank()
    ClearBankGlows()
    -- Если работает Баганатор — свечением рулит его corner-widget, свой скан не нужен.
    if baganatorReady then return end
    if not GlowEnabled() then return end
    local roots = ScanRoots()
    if #roots == 0 then return end
    local seen = {}
    for _, root in ipairs(roots) do
        Walk(root, function(button, id)
            if ShouldGlowItem(id) then
                StartPixelGlow(button)
                litButtons[button] = true
            end
        end, 0, seen)
    end
end

-- Тикер скана Blizzard-сумок/банка (только когда Баганатор НЕ используется).
local scanTicker
local function StartScanLoop()
    if baganatorReady then return end   -- Баганатор светит через corner-widget
    RefreshBank()
    if not scanTicker then
        scanTicker = C_Timer.NewTicker(1, function()
            if baganatorReady or #ScanRoots() == 0 then
                if scanTicker then scanTicker:Cancel(); scanTicker = nil end
                ClearBankGlows()
                return
            end
            RefreshBank()
        end)
    end
end

-- Хук на показ сумок Blizzard — чтобы ловить открытие сумок (без Баганатора).
local bagsHooked = false
local function HookBagFrames()
    if bagsHooked then return end
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
        local f = _G[name]
        if f and f.HookScript then
            f:HookScript("OnShow", function() C_Timer.After(0.05, StartScanLoop) end)
            bagsHooked = true
        end
    end
end

ns.RegisterEvent("BANKFRAME_OPENED", function()
    RebuildProfs()
    EnsureBaganator()
    C_Timer.After(0.1, StartScanLoop)
end)
ns.RegisterEvent("BANKFRAME_CLOSED", function()
    if scanTicker then scanTicker:Cancel(); scanTicker = nil end
    ClearBankGlows()
end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
    if not baganatorReady and #ScanRoots() > 0 then StartScanLoop() end
end)

-- =========================================================================
-- Общие триггеры
-- =========================================================================
local function OnProfChanged()
    RebuildProfs()
    RequestBaganatorRefresh()
end
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    RebuildProfs()
    EnsureBaganator()
    HookBagFrames()
end)
ns.RegisterEvent("SKILL_LINES_CHANGED", OnProfChanged)
ns.RegisterEvent("TRADE_SKILL_SHOW", OnProfChanged)
ns.RegisterEvent("QUEST_TURNED_IN", function()
    -- Использовал трактат → обновить свечение (перестанет светиться).
    RequestBaganatorRefresh()
    if not baganatorReady and #ScanRoots() > 0 then C_Timer.After(0.2, RefreshBank) end
end)
ns.RegisterMessage("RAINON_REAPPLY", function()
    EnsureBaganator()
    HookBagFrames()
end)

ns.Treatise = { RefreshBank = RefreshBank, RebuildProfs = RebuildProfs }

-- =========================================================================
-- Диагностика
-- =========================================================================
SLASH_RAINONTREATISE1 = "/rstreatise"
SlashCmdList.RAINONTREATISE = function()
    RebuildProfs()
    local want = {}
    for id, t in pairs(TREATISE) do
        if myProfs[t.base] and not IsDone(t.quest) then want[#want + 1] = tostring(id) end
    end
    ns.Print("трактаты к подсветке (itemID): " .. (#want > 0 and table.concat(want, ", ") or "нет"))
    ns.Print("Баганатор: " .. (baganatorReady and "подключён (свечение через его API)"
        or ((Baganator and Baganator.API) and "есть, но виджет не зарегистрирован" or "не найден")))
    local locs = {}
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = -5, 20 do
            local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
            if ok and slots and slots > 0 then
                for s = 1, slots do
                    local ok2, id = pcall(C_Container.GetContainerItemID, bag, s)
                    if ok2 and id and TREATISE[id] then
                        locs[#locs + 1] = ("bag %d/slot %d=%d"):format(bag, s, id)
                    end
                end
            end
        end
    end
    ns.Print("трактаты в контейнерах: " .. (#locs > 0 and table.concat(locs, "; ") or "нет"))
end
