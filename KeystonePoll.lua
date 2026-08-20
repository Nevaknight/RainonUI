-- =========================================================================
-- RainonUI / KeystonePoll (ЭКСПЕРИМЕНТАЛЬНЫЙ, тестовый модуль).
-- Опросник по эпохальным ключам группы.
--
-- Как работает:
--   • Ключи группы берём через LibKeystone (её тянет BigWigs; свою копию тоже
--     кладём в Libs). Любой в группе с LibKeystone отвечает своим ключом.
--   • Кнопка «Опрос» — рассылаем список ключей-кандидатов группе НАШИМ каналом.
--     У всех с RainonUI окно авто-открывается, они кликают ключ (или «Пофиг»).
--     Голоса летят в PARTY — все видят живой подсчёт.
--   • Пока окно открыто — слушаем ключи и обновляем строки; закрыли —
--     LibKeystone отписываем, модуль спит. Крошечный слушатель на сигнал
--     «начался опрос» остаётся всегда (чтобы авто-открыть окно у получателя).
--
-- Окно и 5 строк создаём ОДИН раз (в группе максимум 5 ключей) — при обновлении
-- только меняем содержимое строк, геометрию/высоту не трогаем.
-- =========================================================================
local _, ns = ...

ns.KeystonePoll = ns.KeystonePoll or {}
local KP = ns.KeystonePoll

local POLL_PREFIX = "RainonUIKP"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(POLL_PREFIX)
end

local LKS = LibStub and LibStub("LibKeystone", true)

-- Состояние ---------------------------------------------------------------
local keys   = {}   -- [playerName] = { level, mapID, rating }
local votes  = {}   -- [playerName] = mapID (число) | "ANY"
local active = false -- окно открыто (живой режим)
local win

local MY_NAME = UnitName("player")

-- Помощники ---------------------------------------------------------------
local function DungeonName(mapID)
    local name, tex
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local n, _, _, t = C_ChallengeMode.GetMapUIInfo(mapID)
        name, tex = n, t
    end
    return name or ("Подземелье " .. tostring(mapID)), tex or 134400
end

-- Список кандидатов: по одному на подземелье (mapID). Если у нескольких игроков
-- один и тот же ключ-подземелье — берём наивысший уровень.
local function BuildCandidates()
    local byMap = {}
    for owner, k in pairs(keys) do
        local c = byMap[k.mapID]
        if not c or k.level > c.level then
            byMap[k.mapID] = { mapID = k.mapID, level = k.level, owner = owner, rating = k.rating }
        end
    end
    local list = {}
    for _, c in pairs(byMap) do list[#list + 1] = c end
    table.sort(list, function(a, b) return a.level > b.level end)
    return list
end

-- Сколько голосов у подземелья: явный выбор ИЛИ «Пофиг» (ANY).
local function CountFor(mapID)
    local n = 0
    for _, v in pairs(votes) do
        if v == mapID or v == "ANY" then n = n + 1 end
    end
    return n
end

-- Списки голосовавших за подземелье (для подсказки на цифре).
local function VotersFor(mapID)
    local direct, any = {}, {}
    for name, v in pairs(votes) do
        if v == mapID then direct[#direct + 1] = name
        elseif v == "ANY" then any[#any + 1] = name end
    end
    table.sort(direct); table.sort(any)
    return direct, any
end

-- Рассылка нашим каналом (в группе).
local function Send(msg)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, POLL_PREFIX, msg, channel)
    end
end

-- -------------------------------------------------------------------------
-- Окно (ButtonFrameTemplate — классические текстуры Blizzard).
-- Геометрия ФИКСИРОВАННАЯ: 5 строк, окно не пересчитывается.
-- -------------------------------------------------------------------------
local WIN_W  = 380
local PAD    = 14
local ROW_H  = 34
local ICON   = 28
local TITLEBAR   = 24
local BOTTOM_BAR = 40
local HINT_H     = 30    -- фикс. область под подсказку (2 строки)
local INSET_TOPPAD = 10
local MAX_ROWS   = 5     -- в группе максимум 5 человек → 5 ключей

local rows = {}          -- 5 статичных строк

local Rebuild  -- fwd

local function MakeRow(host, i)
    local r = CreateFrame("Button", nil, host)
    r:SetHeight(ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- галочка-отметка «мой выбор»
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(20, 20)
    r.check:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.check:SetAtlas("common-icon-checkmark")
    r.check:Hide()

    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 28, 0)
    r.label:SetJustifyH("LEFT")

    -- счётчик голосов справа
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.count:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    r.count:SetJustifyH("RIGHT")

    -- зона наведения на цифру → подсказка со списком голосовавших
    r.countHover = CreateFrame("Frame", nil, r)
    r.countHover:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.countHover:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.countHover:SetWidth(56)
    r.countHover:EnableMouse(true)
    r.countHover:SetScript("OnEnter", function(self)
        if not r.mapID then return end
        local direct, any = VotersFor(r.mapID)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine((select(1, DungeonName(r.mapID))))
        if #direct == 0 and #any == 0 then
            GameTooltip:AddLine("Никто не голосовал", 0.7, 0.7, 0.7)
        else
            if #direct > 0 then
                GameTooltip:AddLine("Голоса: " .. table.concat(direct, ", "), 1, 1, 1, true)
            end
            if #any > 0 then
                GameTooltip:AddLine("Пофиг: " .. table.concat(any, ", "), 0.7, 0.7, 0.7, true)
            end
        end
        GameTooltip:Show()
    end)
    r.countHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r:SetScript("OnClick", function(self)
        if self.mapID then KP.Vote(self.mapID) end
    end)
    r:Hide()
    return r
end

local function BuildWindow()
    if win then return win end
    win = CreateFrame("Frame", "RainonUIKeystonePoll", UIParent, "ButtonFrameTemplate")
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    table.insert(UISpecialFrames, "RainonUIKeystonePoll")

    -- Заголовок — центрируем по всей ширине рамки (иначе с портретом уезжает).
    if win.SetTitle then pcall(win.SetTitle, win, "Опрос ключей") end
    local titleFS = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
    if titleFS then
        titleFS:SetText("Опрос ключей")
        titleFS:ClearAllPoints()
        titleFS:SetPoint("TOP", win, "TOP", 0, -6)
        titleFS:SetJustifyH("CENTER")
    end

    -- Портрет — иконка эпохального ключа.
    pcall(function()
        local p = win.PortraitContainer and win.PortraitContainer.portrait or win.portrait
        if p then p:SetTexture(525134); p:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end)

    -- ФИКСИРОВАННАЯ геометрия (считаем один раз).
    local hintTop   = TITLEBAR + 6
    local insetTopY = -(hintTop + HINT_H + 6)
    win:SetSize(WIN_W, (hintTop + HINT_H + 6) + (INSET_TOPPAD + MAX_ROWS * ROW_H + 10) + BOTTOM_BAR)

    -- Подсказка (фикс. область над инсетом, левый край за портретом).
    win.Hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.Hint:SetPoint("TOPLEFT", win, "TOPLEFT", 64, -hintTop)
    win.Hint:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -hintTop)
    win.Hint:SetJustifyH("LEFT")

    -- Инсет держит строки (якоря один раз).
    local host = win.Inset or win
    if win.Inset then
        win.Inset:ClearAllPoints()
        win.Inset:SetPoint("TOPLEFT", win, "TOPLEFT", 4, insetTopY)
        win.Inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, BOTTOM_BAR)
    end

    -- 5 статичных строк.
    for i = 1, MAX_ROWS do
        local r = MakeRow(host, i)
        r:ClearAllPoints()
        local y = -INSET_TOPPAD - (i - 1) * ROW_H
        r:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, y)
        r:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, y)
        rows[i] = r
    end

    -- Кнопки нижней полосы: «Опрос» и «Пофиг» (две в ряд по центру).
    local by = (BOTTOM_BAR - 24) / 2
    local pollBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    pollBtn:SetSize(150, 24)
    pollBtn:SetPoint("BOTTOMLEFT", win, "BOTTOM", 4, by)
    pollBtn:SetText("Опрос")
    pollBtn:SetScript("OnClick", function() KP.StartPoll() end)
    win.PollBtn = pollBtn

    local anyBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    anyBtn:SetSize(150, 24)
    anyBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOM", -4, by)
    anyBtn:SetText("Пофиг")
    anyBtn:SetScript("OnClick", function() KP.Vote("ANY") end)
    win.AnyBtn = anyBtn

    win:SetScript("OnShow", function() KP.OnShow() end)
    win:SetScript("OnHide", function() KP.OnHide() end)

    win:Hide()
    return win
end

-- Обновить СОДЕРЖИМОЕ строк (геометрию не трогаем).
function Rebuild()
    if not win or not win:IsShown() then return end
    local cands = BuildCandidates()

    if #cands == 0 then
        win.Hint:SetText("Ключей в группе не видно. Жми " .. ns.C("FFD100", "«Опрос»") ..
            " — нужен BigWigs/RainonUI у игроков.")
    else
        win.Hint:SetText("Выбери ключ кликом. " .. ns.C("FFD100", "«Пофиг»") ..
            " — согласен на любой. Наведи на цифру — увидишь голосовавших.")
    end

    for i = 1, MAX_ROWS do
        local r = rows[i]
        local c = cands[i]
        if c then
            local name, tex = DungeonName(c.mapID)
            r.icon:SetTexture(tex)
            r.mapID = c.mapID
            r.label:SetText(name .. "  " .. ns.C("FFD100", "+" .. c.level))
            r.count:SetText(tostring(CountFor(c.mapID)))
            r.check:SetShown(votes[MY_NAME] == c.mapID or votes[MY_NAME] == "ANY")
            r:Show()
        else
            r.mapID = nil
            r:Hide()
        end
    end
end
KP.Rebuild = Rebuild

-- -------------------------------------------------------------------------
-- Сбор ключей (LibKeystone) — только пока окно открыто
-- -------------------------------------------------------------------------
local lksToken = {}   -- объект-токен для LibKeystone.Register
local function OnKeystone(level, mapID, rating, name, channel)
    if not active then return end
    if type(level) ~= "number" or type(mapID) ~= "number" then return end
    if level > 0 and mapID > 0 then
        keys[name] = { level = level, mapID = mapID, rating = rating }
        Rebuild()
    end
end

local function GatherKeys()
    keys = {}
    -- свой ключ на всякий случай (если LibKeystone нет)
    if C_MythicPlus then
        local lvl = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        local map = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        if type(lvl) == "number" and type(map) == "number" and lvl > 0 and map > 0 then
            keys[MY_NAME] = { level = lvl, mapID = map, rating = 0 }
        end
    end
    if LKS and LKS.Request then pcall(LKS.Request, "PARTY") end
end

-- -------------------------------------------------------------------------
-- Показ / скрытие
-- -------------------------------------------------------------------------
function KP.OnShow()
    active = true
    if LKS and LKS.Register then pcall(LKS.Register, lksToken, OnKeystone) end
    GatherKeys()
    Rebuild()
end

function KP.OnHide()
    active = false
    if LKS and LKS.Unregister then pcall(LKS.Unregister, lksToken) end
end

function KP.Show()
    BuildWindow()
    win:Show()
    win:Raise()
end

function KP.Toggle()
    BuildWindow()
    if win:IsShown() then win:Hide() else KP.Show() end
end

-- -------------------------------------------------------------------------
-- Голосование
-- -------------------------------------------------------------------------
function KP.Vote(choice)
    votes[MY_NAME] = choice
    Send("V:" .. tostring(choice))
    Rebuild()
end

-- Старт/пересбор опроса ведущим: чистим голоса, собираем ключи, зовём группу.
function KP.StartPoll()
    votes = {}
    if not win or not win:IsShown() then KP.Show() end
    GatherKeys()
    -- дать LibKeystone мгновение на ответы, затем разослать список кандидатов
    C_Timer.After(1.0, function()
        local cands = BuildCandidates()
        local ids = {}
        for _, c in ipairs(cands) do ids[#ids + 1] = tostring(c.mapID) .. "." .. tostring(c.level) end
        Send("S:" .. table.concat(ids, ","))
        Rebuild()
    end)
end

-- -------------------------------------------------------------------------
-- Приём наших сообщений (слушатель ВСЕГДА активен — чтобы авто-открыть окно)
-- -------------------------------------------------------------------------
ns.RegisterEvent("CHAT_MSG_ADDON", function(prefix, msg, _, sender)
    if prefix ~= POLL_PREFIX then return end
    local short = sender and Ambiguate(sender, "short") or sender
    local isMine = short == MY_NAME

    local kind, payload = msg:match("^(%a):(.*)$")
    if kind == "S" then
        -- начался опрос: авто-открываем окно (если модуль включён галкой),
        -- подсеваем кандидатов из payload
        local enabled = ns.db and ns.db.features and ns.db.features.keystonePoll
        if not isMine and enabled then
            votes = {}
            for pair in payload:gmatch("[^,]+") do
                local m, l = pair:match("^(%d+)%.(%d+)$")
                m, l = tonumber(m), tonumber(l)
                if m and l and not keys[m] then
                    -- владельца не знаем — кладём как «кандидат от группы»
                    keys["#" .. m] = { level = l, mapID = m, rating = 0 }
                end
            end
            KP.Show()
        end
    elseif kind == "V" then
        -- чужой голос: учитываем (рисуем только если окно открыто)
        if not isMine then
            local m = tonumber(payload)
            votes[short] = m or (payload == "ANY" and "ANY" or nil)
            Rebuild()
        end
    end
end)

-- -------------------------------------------------------------------------
-- Слэш + кнопка тестера
-- -------------------------------------------------------------------------
SLASH_RAINONPOLL1 = "/rspoll"
SlashCmdList.RAINONPOLL = function() KP.Toggle() end

if ns.Tester and ns.Tester.Add then
    ns.Tester.Add("Подземелья", "Опрос ключей", KP.Show)
end
