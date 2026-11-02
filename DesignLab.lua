-- =========================================================================
-- RainonUI / DesignLab (ЭКСПЕРИМЕНТАЛЬНЫЙ, ТЕСТОВЫЙ модуль — ТОЛЬКО ДИЗАЙН).
--
-- МАКЕТ всего окна аддона с навигацией «как на аукционе»: слева кнопки-разделы
-- с раскрывающимся списком под каждой (аккордеон), справа — панель настроек.
-- Функции НЕ подключены: галки/строки визуальные, чтобы отсмотреть весь дизайн.
-- Каркас окна = наш аддон (DefaultPanelFlatTemplate). Кнопки — РОДНЫЕ текстуры
-- аукциона (auctionhouse-nav-*): обычная / наведение / выбранная.
--
-- Вызов: /rsdes (+ кнопка тестера «Дизайн»).
-- =========================================================================
local _, ns = ...

ns.DesignLab = ns.DesignLab or {}
local DL = ns.DesignLab

local ACCENT = "FFD100"

-- Родные атласы аукциона: [обычная], [наведение], [выбранная].
local A_TOP,  A_TOP_HI,  A_TOP_SEL  = "auctionhouse-nav-button",           "auctionhouse-nav-button-highlight",           "auctionhouse-nav-button-select"
local A_SUB,  A_SUB_HI,  A_SUB_SEL  = "auctionhouse-nav-button-secondary", "auctionhouse-nav-button-secondary-highlight", "auctionhouse-nav-button-secondary-select"

-- Разделы = наши вкладки; дети = подсекции (демо систематизации). Без иконок.
local NAV = {
    { name = "Скрипты", children = {
        { "Полосы ресурсов классов", "скрывать индикаторы ресурса" },
        { "Полоса заклинаний",       "прятать полосу каста" },
        { "Рейдовые объявления",     "убирать текст рейд-варнингов" },
        { "Лут и названия зон",      "лут по центру, имя зоны" } } },
    { name = "Инструменты", children = {
        { "Стикеры готовности",  "экранные оповещения группы" },
        { "Тексты оповещений",   "ремонт, котёл, почта" },
        { "Иконки кулдаунов",    "зелья и инженерные штуки" },
        { "Валюта Moxie",        "счётчик валюты на экране" } } },
    { name = "Профессии", children = {
        { "Мастер профессий",         "общий выключатель модуля" },
        { "Флакон изобретательности", "клик по иконке = флакон" },
        { "Раскол сущности",          "частица для раскола" } } },
    { name = "Удобства", children = {
        { "Общее",       "муверы окон, тосты" },
        { "Метка танка", "авто-метка при проверке" },
        { "Воскрешение", "звук при воскрешении" },
        { "Изобилие",    "звук завершения события" } } },
    { name = "Паладин", children = {
        { "Освящение оружия", "иконка-напоминание" },
        { "Макро-строки",     "готовые макросы" } } },
    { name = "Подземелья", children = {
        { "Оповещение танка",     "анонс урона по BigWigs" },
        { "Напоминание талантов", "важные таланты на входе" },
        { "Опрос ключей",         "голосование по ключам" },
        { "Реролл ключей",        "нужно / не нужно" },
        { "Подсказки MDT",        "заметки по подземельям" } } },
    { name = "Звуки", children = {
        { "Приглушение звуков", "мьют отдельных звуков" },
        { "Трекер звуков",      "показывает id звука" } } },
    { name = "Тест", children = {
        { "Полоса «Резонанс»",  "таймер для танка-паладина" },
        { "Дизайн-лаборатория", "это окно" } } },
    { name = "Ссылки", children = {
        { "Полезные аддоны", "рекомендованные аддоны" } } },
}

local TOP_H, SUB_H = 32, 28   -- высота как у родного атласа (не искажать текстуру)
local SUB_IN       = 14
local NAV_W        = 210
local frame

-- -------------------------------------------------------------------------
-- Кнопка навигации. level: "top" | "sub". Родные текстуры аукциона.
-- Наведение — highlight-атлас; выбранная — select-атлас (постоянно). Родитель
-- постоянной подсветки НЕ получает (только стрелка +/−) — чтобы «выбран» был
-- ровно один пункт.
-- -------------------------------------------------------------------------
-- Точная копия Blizzard AuctionCategoryButtonTemplate:
--   NormalTexture  atlas auctionhouse-nav-button        (заполняет кнопку)
--   SelectedTexture atlas auctionhouse-nav-button-select, alphaMode=ADD,
--                   растянут на всю кнопку → подсветка ЗАЛИВАЕТ кнопку целиком
--   HighlightTexture atlas auctionhouse-nav-button-highlight (наведение)
--   NormalFont GameFontNormalSmall, текст LEFT +4 / RIGHT -4, по центру Y.
local function MakeNavButton(parent, level)
    local top = (level == "top")
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp")

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetAtlas(top and A_TOP or A_SUB)

    b.sel = b:CreateTexture(nil, "ARTWORK")
    b.sel:SetAllPoints()                                  -- на всю кнопку
    b.sel:SetAtlas(top and A_TOP_SEL or A_SUB_SEL)
    b.sel:SetBlendMode("ADD")                             -- как в оригинале → полная заливка
    b.sel:Hide()

    b:SetHighlightAtlas(top and A_TOP_HI or A_SUB_HI)

    b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.Label:SetJustifyH("LEFT")
    b.Label:SetWordWrap(false)
    b.Label:SetTextColor(1, 0.82, 0)
    b.Label:SetPoint("LEFT", top and 10 or 14, 0)
    b.Label:SetPoint("RIGHT", -20, 0)                     -- запас под стрелку

    if top then
        b.Arrow = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.Arrow:SetPoint("RIGHT", -10, 0)
        b.Arrow:SetTextColor(1, 0.82, 0)
    end
    return b
end

-- -------------------------------------------------------------------------
-- Правая панель: статичный макет настроек раздела (галки-пустышки).
-- -------------------------------------------------------------------------
local function BuildDetail(i)
    local d = frame.detail
    for _, w in ipairs(d.rows) do w:Hide() end
    wipe(d.rows)

    local sec = NAV[i]; if not sec then return end
    d.Title:SetText(ns.C(ACCENT, sec.name))
    d.Sub:SetText("|cFFF48CBAРаздел настроек — предпросмотр дизайна|r")

    local y = -74
    for k, ch in ipairs(sec.children) do
        local cb = d.pool[k]
        if not cb then
            cb = ns.MakeCheckButton(d)
            cb.desc = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            cb.desc:SetPoint("LEFT", cb.Text, "RIGHT", 8, 0)
            cb.desc:SetPoint("RIGHT", d, "RIGHT", -6, 0)
            cb.desc:SetJustifyH("LEFT")
            d.pool[k] = cb
        end
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", d, "TOPLEFT", 4, y)
        cb.Text:SetText(ch[1])
        cb.desc:SetText("— " .. (ch[2] or ""))
        cb:SetChecked(k % 3 ~= 0)   -- статичный вид, без логики
        cb:Show()
        d.rows[#d.rows + 1] = cb
        y = y - 30
    end
end

-- -------------------------------------------------------------------------
-- Перекладка левого столбца (аккордеон): раскрытый раздел показывает детей.
-- -------------------------------------------------------------------------
local function Relayout()
    if not frame then return end
    local host = frame.navHost
    local y = 0
    for i in ipairs(NAV) do
        local tb = frame.topBtn[i]
        tb:ClearAllPoints()
        tb:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
        tb:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        tb:SetHeight(TOP_H)
        tb.Arrow:SetText(frame.expanded == i and "–" or "+")
        tb.sel:Hide()   -- родитель постоянно не выделяем
        y = y + TOP_H + 2

        local kids = frame.subBtn[i]
        if frame.expanded == i then
            for j, cb in ipairs(kids) do
                cb:ClearAllPoints()
                cb:SetPoint("TOPLEFT", host, "TOPLEFT", SUB_IN, -y)
                cb:SetPoint("RIGHT", host, "RIGHT", -2, 0)
                cb:SetHeight(SUB_H)
                cb.sel:SetShown(frame.selSection == i and frame.selChild == j)
                cb:Show()
                y = y + SUB_H + 1
            end
            y = y + 3
        else
            for _, cb in ipairs(kids) do cb:Hide() end
        end
    end
    host:SetHeight(math.max(y, 10))
end

-- Клик по разделу: раскрыть, а если уже раскрыт — свернуть.
function DL.ToggleSection(i)
    if frame.expanded == i then
        frame.expanded = nil
    else
        frame.expanded = i
    end
    Relayout()
end

function DL.SelectChild(i, j)
    frame.selSection, frame.selChild = i, j
    if frame.expanded ~= i then frame.expanded = i end
    Relayout()
    BuildDetail(i)
end

-- Масштаб окна (+/- у крестика).
local function DB() ns.db = ns.db or {}; ns.db.designlab = ns.db.designlab or {}; return ns.db.designlab end
local function ApplyScale() if frame then frame:SetScale(DB().scale or 1) end end
local function ChangeScale(delta)
    DB().scale = math.max(0.6, math.min(1.6, (DB().scale or 1) + delta)); ApplyScale()
end

-- Память позиции. Экран не ограничиваем — окно уходит за край, как основное меню.
local function SavePos()
    if not (frame and ns.db) then return end
    ns.db.positions = ns.db.positions or {}
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.db.positions.designlab = { point = point, relPoint = relPoint, x = x, y = y }
end
local function RestorePos()
    if not frame then return end
    frame:ClearAllPoints()
    local p = ns.db and ns.db.positions and ns.db.positions.designlab
    if p and p.point then
        frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-- -------------------------------------------------------------------------
-- Постройка окна. Каркас = наш аддон, ГОРИЗОНТАЛЬНЫЙ прямоугольник.
-- -------------------------------------------------------------------------
local function Build()
    if frame then return frame end

    frame = CreateFrame("Frame", "RainonUIDesignLab", UIParent, "DefaultPanelFlatTemplate")
    frame:SetSize(760, 520)   -- горизонтальный (шире, чем выше)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)      -- без клампа → уходит за экран
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    if frame.SetTitle then frame:SetTitle("RainonUI — Дизайн-лаборатория") end
    table.insert(UISpecialFrames, "RainonUIDesignLab")

    -- Свой крестик + кнопки масштаба слева от него.
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    local plus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    plus:SetSize(22, 20); plus:SetText("+")
    plus:SetPoint("RIGHT", close, "LEFT", 0, 0)
    plus:SetScript("OnClick", function() ChangeScale(0.1) end)
    local minus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minus:SetSize(22, 20); minus:SetText("-")
    minus:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    minus:SetScript("OnClick", function() ChangeScale(-0.1) end)

    -- Левый столбец навигации (без скролла — весь список виден).
    local navHost = CreateFrame("Frame", nil, frame)
    navHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -40)
    navHost:SetWidth(NAV_W); navHost:SetHeight(10)
    frame.navHost = navHost

    -- Вертикальный разделитель.
    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.10); sep:SetWidth(1)
    sep:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + NAV_W + 12, -40)
    sep:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12 + NAV_W + 12, 14)

    -- Правая панель.
    local d = CreateFrame("Frame", nil, frame)
    d:SetPoint("TOPLEFT", sep, "TOPRIGHT", 14, 0)
    d:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    d.rows, d.pool = {}, {}
    frame.detail = d
    d.Title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.Title:SetPoint("TOPLEFT", 0, -2)
    d.Sub = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.Sub:SetPoint("TOPLEFT", d.Title, "BOTTOMLEFT", 0, -8)

    -- Кнопки разделов и детей.
    frame.topBtn, frame.subBtn = {}, {}
    for i, sec in ipairs(NAV) do
        local tb = MakeNavButton(navHost, "top")
        tb.Label:SetText(sec.name)
        tb:SetScript("OnClick", function() DL.ToggleSection(i) end)
        frame.topBtn[i] = tb
        local kids = {}
        for j, ch in ipairs(sec.children) do
            local cb = MakeNavButton(navHost, "sub")
            cb.Label:SetText(ch[1])
            cb:SetScript("OnClick", function() DL.SelectChild(i, j) end)
            kids[j] = cb
        end
        frame.subBtn[i] = kids
    end

    frame.expanded = 1
    frame.selSection, frame.selChild = 1, 1
    Relayout()
    BuildDetail(1)
    ApplyScale()
    RestorePos()
    frame:Hide()
    return frame
end

function DL.Toggle()
    Build()
    if frame:IsShown() then frame:Hide() else RestorePos(); frame:Show() end
end
function DL.Show() Build(); RestorePos(); frame:Show() end

SLASH_RAINONDESIGN1 = "/rsdes"
SlashCmdList.RAINONDESIGN = function() DL.Toggle() end

if ns.Tester and ns.Tester.Add then
    ns.Tester.Add("Дизайн", "Прототип навигации аукциона", function() DL.Show() end)
end
