-- =========================================================================
-- RainonUI / Options: окно настроек в новом стиле Midnight
-- (DefaultPanelFlatTemplate + боковые вкладки LargeSideTabButtonTemplate,
-- как у панели жилья / журнала заданий в 12.0).
-- Вкладка 1 — «Скрипты» (скрытие интерфейса), вкладка 2 — «Инструменты».
-- =========================================================================

local _, ns = ...

local COLOR = {
    PALADIN = "F48CBA", EVOKER = "33937F", DEATHKNIGHT = "C41E3A",
    WARLOCK = "8788EE", MONK = "00FF98", ROGUE = "FFF468",
    DRUID = "FF7C0A", MAGE = "3FC7EB", SHAMAN = "0070DD",
}
local C = ns.C

-- Подтверждение для кнопки «вернуть весь скрытый интерфейс» (защита от дурака).
StaticPopupDialogs["RAINONUI_RESET_HIDE"] = {
    text = "Вернуть весь скрытый интерфейс: снять ВСЕ галочки скрытия в RainonUI" ..
        " и перезагрузить интерфейс?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if ns.db and ns.db.hide then
            for k in pairs(ns.db.hide) do ns.db.hide[k] = false end
        end
        ReloadUI()
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
}

local HIDE_OPTIONS = {
    { header = "Рамка игрока", spoiler = true, collapsed = true },
    { key = "holypower",   name = C(COLOR.PALADIN, "Сила света"),          desc = C(COLOR.PALADIN, "Паладин") },
    { key = "essence",     name = C(COLOR.EVOKER, "Заряды сущности"),      desc = C(COLOR.EVOKER, "Пробудитель") },
    { key = "runeframe",   name = C(COLOR.DEATHKNIGHT, "Сила Рун"),        desc = C(COLOR.DEATHKNIGHT, "Рыцарь Смерти") },
    { key = "warlockpower", name = C(COLOR.WARLOCK, "Осколки душ"),        desc = C(COLOR.WARLOCK, "Чернокнижник") },
    { key = "stagger",     name = C(COLOR.MONK, "Пошатывание"),            desc = C(COLOR.MONK, "Монах") },
    { key = "monkbar",     name = C(COLOR.MONK, "Энергия ци"),             desc = C(COLOR.MONK, "Монах") },
    { key = "rogcombo",    name = C(COLOR.ROGUE, "Серия приёмов"),         desc = C(COLOR.ROGUE, "Разбойник") },
    { key = "drucombo",    name = C(COLOR.DRUID, "Серия приёмов"),         desc = C(COLOR.DRUID, "Друид") },
    { key = "arcanemage",  name = C(COLOR.MAGE, "Чародейские заряды"),     desc = C(COLOR.MAGE, "Маг") },
    { key = "combattext",  name = "Текст боя",
      desc = "Исцеление, урон, блокирование и прочие события на личном фрейме." },
    { key = "totempanel",  name = "Панель тотемов",
      desc = "Панель находится под рамкой игрока. " .. C(COLOR.PALADIN, "Паладин") ..
             " - Освящение, " .. C(COLOR.DRUID, "Друид") .. " - Период цветения, " ..
             C(COLOR.SHAMAN, "Шаман") .. " - Тотемы, " .. C(COLOR.MONK, "Монах") ..
             " - Призыв Сюэня, Белого Тигра." },
    { key = "castbar",     name = "Полоса заклинаний",
      desc = "Личная полоса заклинаний игрока." },

    { header = "Индикатор личного ресурса", spoiler = true, collapsed = true },
    { key = "holypowerbar",    name = C(COLOR.PALADIN, "Сила света"),      desc = C(COLOR.PALADIN, "Паладин") },
    { key = "essencebar",      name = C(COLOR.EVOKER, "Заряды сущности"),  desc = C(COLOR.EVOKER, "Пробудитель") },
    { key = "runeframebar",    name = C(COLOR.DEATHKNIGHT, "Сила Рун"),    desc = C(COLOR.DEATHKNIGHT, "Рыцарь Смерти") },
    { key = "warlockpowerbar", name = C(COLOR.WARLOCK, "Осколки душ"),     desc = C(COLOR.WARLOCK, "Чернокнижник") },
    { key = "monkpersonalbar", name = C(COLOR.MONK, "Энергия ци"),         desc = C(COLOR.MONK, "Монах") },
    { key = "rogcombobar",     name = C(COLOR.ROGUE, "Серия приёмов"),     desc = C(COLOR.ROGUE, "Разбойник") },
    { key = "drucombobar",     name = C(COLOR.DRUID, "Серия приёмов"),     desc = C(COLOR.DRUID, "Друид") },
    { key = "arcanemagebar",   name = C(COLOR.MAGE, "Чародейские заряды"), desc = C(COLOR.MAGE, "Маг") },

    { header = "Разное" },
    { key = "targetspellbar",  name = "Полоса заклинаний цели",
      desc = "Полоса заклинаний цели." },
    { key = "blizzdbm",        name = "Босс сообщения на экране",
      desc = "Blizzard оповещения о способностях босса." },
    { key = "talkinghead",     name = "Говорящая голова",
      desc = "Окно с говорящим персонажем и репликами." },
    { key = "actionbutton",    name = "Обводка кнопки действия",
      desc = "Кнопка, которая появляется на боссах." },
    { key = "zonebutton",      name = "Обводка кнопки зоны",
      desc = "Кнопка гарнизона и т.д." },
    { key = "expbar",          name = "Полоса опыта, репутации и т.д.",
      desc = "Отключает полосу опыта, репутации и чести." },
    { key = "bags",            name = "Сумки",
      desc = "Панель сумок рядом с микроменю." },
    { key = "raidmanager",     name = "Управление рейдом",
      desc = "Полоска с выпадающим окошком меток слева на экране, появляется в группе или рейде." },
    { key = "expansionbutton", name = "Кнопка у миникарты",
      desc = "Кнопка ковенанта, гарнизона и т.д. на миникарте." },
    { key = "durability",      name = "Состояние брони",
      desc = "Иконка, напоминающая о ремонте." },
    { key = "vehicle",         name = "Панель транспорта",
      desc = "Иконка транспорта, на котором есть дополнительные места для пассажиров." },
    { key = "__alwaysCompare", name = "Не сравнивать предметы в подсказках",
      desc = "Отключает авто-сравнение предметов в подсказках " ..
             "(/console alwaysCompareItems 0). Снятие галки возвращает сравнение." },

    { header = "Особые" },
    { key = "event",      name = "События",
      desc = "Виджет событий по центру экрана: «Название подземелья» на старте ключа, фазы сценариев и аналогичные события." },
    { key = "dailyquest", name = "Задачи",
      desc = "Виджет по центру экрана, когда вы получаете «Локальное задание» и аналогичные события." },
    { key = "lootHide",   name = "Лут по центру",
      desc = "Персональный список добычи по центру экрана." },
    { key = "ZoneHide",   name = "Название зоны",
      desc = "Текст с названием зоны по центру экрана." },
    { key = "bossbanner", name = "Баннер боссов",
      desc = "Баннер «X повержен» и «Подземелье пройдено» (BossBanner). Скрытие требует /reload после включения." },
}

-- Карта ключ -> человеческое название (для крестиков режима настройки в
-- HideUI, чтобы подпись совпадала с названием в меню).
ns.HideNames = {}
for _, o in ipairs(HIDE_OPTIONS) do
    if o.key and o.key ~= "__setup" and o.name then
        ns.HideNames[o.key] = o.name
    end
end

local TOOLS_OPTIONS = {
    { header = "Стикеры (сбор рейда)" },
    { key = "breaktimer", name = "Перерыв",
      desc = "Большой стикер с таймером перерыва из DBM или BigWigs." },
    { key = "allready",   name = "Все готовы",
      desc = "Стикер «Все готовы» по завершении проверки готовности." },
    { key = "feast",      name = "Сытная еда",
      desc = "Стикер, когда в группе поставили пиршество." },
    { key = "food",       name = "Обычная еда",
      desc = "Стикер, когда в группе поставили обычную еду." },
    { key = "racechange", name = "Смена расы",
      desc = "Стикер, когда кто-то использует смену расы." },

    { header = "Оповещения — тексты" },
    { key = "repair",       name = "Ремонт",       desc = "Поставили ремонтного бота." },
    { key = "cauldron",     name = "Котёл",        desc = "Поставили котёл с зельями." },
    { key = "mail",         name = "Почта",        desc = "Вызвали почтовый ящик." },
    { key = "healthstones", name = "Камни здоровья", desc = "Чернокнижник создал круг камней здоровья." },
    { key = "magetable",    name = "Стол мага",    desc = "Маг поставил стол с едой." },
    { key = "summon",       name = "Шкаф сумона",  desc = "Чернокнижник начал ритуал призыва." },
    { key = "mageeat",      name = "Кушай еду мага",
      desc = "Напоминание поесть еду мага, если здоровье ниже 60% в рейде." },

    { header = "Напоминания" },
    { key = "consumables", name = "Памятка расходников",
      desc = "На отдыхе показывает, каких расходников не хватает: зелья, барабаны, вантийская руна, авто-молоток." },
    { key = "delvemap",    name = "Карта вылазок",
      desc = "В вылазках напоминает использовать карту, если бафф не активен." },

    { header = "Оповещения" },
    { key = "leader",     name = "Лидер группы",   desc = "Крупный текст, когда тебе передали лидерство." },
    { key = "readybar",   name = "Полоса готовности", desc = "Полоса-таймер во время проверки готовности." },
    { key = "combatdrop", name = "Выход из боя",   desc = "Текст «Бой спал» при выходе из боя в группе." },

    { header = "Иконки" },
    { key = "invispotion", name = "Зелье невидимости",
      desc = "Иконка активного зелья невидимости с таймером." },
    { key = "engcloak", name = "Инженерный плащ", desc = "Кулдаун инженерного плаща." },

    { header = "Прочее" },
    { key = "combattimer", name = "Таймер боя",
      desc = "Таймер текущего боя. Позицию можно менять в режиме редактирования Blizzard (Esc → Настройка интерфейса)." },
    { key = "bonusroll", name = "Бонусная добыча",
      desc = "Перемещает окна бонусной добычи: бросок, выигранный предмет и выигранное золото (BonusRollFrame, BonusRollLootWonFrame, BonusRollMoneyWonFrame) — один общий бокс. Двигается и масштабируется в режиме редактирования; выключение вернёт стандартную позицию после /reload." },
    { key = "keystone", name = "Окно эпохального ключа",
      desc = "Перемещает окно «Вставьте эпохальный ключ» (ChallengesKeystoneFrame). Двигается и масштабируется в режиме редактирования; выключение вернёт стандартную позицию после /reload." },
}

local PROF_OPTIONS = {
    { key = "professions_enabled", name = "Профессии — включить всё",
      desc = "Главный выключатель всего по профессиям: напоминания о баффах" ..
             " крафта, кнопка миникарты и окно недельных знаний/зарядов." },
    { header = "Баффы крафта" },
}

-- Текст-справка по Moxie (перенесён из бывшей вкладки «Валюта»).
local MOXIE_INFO = "Учитываются все профессии:\n"
    .. "• Алхимия — Пыл искусного алхимика\n"
    .. "• Кузнечное дело — Пыл искусного кузнеца\n"
    .. "• Наложение чар — Пыл искусного зачаровывателя\n"
    .. "• Инженерное дело — Пыл искусного инженера\n"
    .. "• Травничество — Пыл искусного травника\n"
    .. "• Начертание — Пыл искусного начертателя\n"
    .. "• Ювелирное дело — Пыл искусного ювелира\n"
    .. "• Кожевничество — Пыл искусного кожевника\n"
    .. "• Горное дело — Пыл искусного горняка\n"
    .. "• Снятие шкур — Пыл искусного скорняка\n"
    .. "• Портняжное дело — Пыл искусного портного"

local FEATURES_OPTIONS = {
    { key = "teleportPrompt", name = "Телепорты",
      desc = "Окно телепорта в подземелье при вступлении в группу Поиска групп:" ..
             " кнопка телепорта в один клик, если он изучен." },
    { key = "reloadMenuButton", name = "Кнопка перезагрузки",
      desc = "Добавляет кнопку «Перезагрузить UI» сверху игрового меню (Esc)." },
    { key = "tankMark", name = "Метка танка",
      desc = "Если ты танк, при проверке готовности по центру появляется иконка" ..
             " выбранного значка с подписью «Задать танку метку?». Клик ставит" ..
             " значок на себя. Когда проверка готовности заканчивается — окно" ..
             " скрывается. Иконку можно двигать в режиме редактирования." },

    { header = "CraftSim (нужны CraftSim и Auctionator)" },
    { key = "craftAHButton", name = "Кнопка списка покупок на аукционе",
      desc = "На окне аукциона добавляет кнопку, которая просит CraftSim собрать" ..
             " список покупок для его ОЧЕРЕДИ крафта в Auctionator — не нужно" ..
             " открывать сам CraftSim (сначала добавь рецепты в очередь CraftSim)." },
}

-- -------------------------------------------------------------------------
-- Макросы паладина (вкладка «Макросы»). Игра до сих пор не даёт задавать ID
-- спеллов в макросах, поэтому нужны отдельные РУ/ЕУ версии с локализованными
-- именами. Префикс 1.x_RainonUI держит их в начале списка.
-- -------------------------------------------------------------------------
-- «?» (fileID 134400): с #showtooltip макрос сам подтянет иконку заклинания,
-- поэтому фиксированную иконку не задаём.
local MACRO_ICON = 134400
-- Иконка строки «Создать всё» — как у вкладки (класс-крест паладина)
local MACRO_ALL_ICON = "Interface\\Icons\\ClassIcon_Paladin"

-- Пары РУ/ЕУ по способностям. icon — fileID иконки; desc — подсказка (что
-- делает макрос) для инфо-кнопки справа.
local MACRO_ROWS = {
    {
        icon = 133192, -- Торжество
        desc = "Лечит цель под курсором (наведение на рамку или модель игрока)," ..
               " если она жива и союзник; иначе — по обычным правилам (текущая цель).",
        ru = { name = "1.1_RainonUI", label = "Торжество",
               body = "#showtooltip \n/cast [@mouseover, exists, nodead, noharm][] Торжество" },
        eu = { name = "1.2_RainonUI", label = "Word of Glory",
               body = "#showtooltip \n/cast [@mouseover, exists, nodead, noharm][] Word of Glory" },
    },
    {
        icon = 135966, -- Жертвенное благословение / Blessing of Sacrifice
        desc = "Накладывает защитное благословение на игрока, чьё имя вписано" ..
               " в макрос. Замени НИК_ИГРОКА на нужное имя.",
        ru = { name = "1.3_RainonUI", label = "Жертв. благословение",
               body = "#showtooltip\n/cast [target=НИК_ИГРОКА] Жертвенное благословение" },
        eu = { name = "1.4_RainonUI", label = "Blessing of Sacrifice",
               body = "#showtooltip\n/cast [target=НИК_ИГРОКА] Blessing of Sacrifice" },
    },
}

-- Создаёт/обновляет набор макросов в ОБЩИХ (аккаунтных) макросах. Только вне
-- боя (CreateMacro/EditMacro в бою заблокированы).
local function CreateMacroSet(list)
    if InCombatLockdown() then
        ns.Print("нельзя создавать макросы в бою — выйди из боя и нажми снова.")
        return
    end
    local created, updated, failed = 0, 0, 0
    for _, mac in ipairs(list) do
        local idx = GetMacroIndexByName and GetMacroIndexByName(mac.name) or 0
        if idx and idx > 0 then
            local ok = pcall(EditMacro, idx, mac.name, MACRO_ICON, mac.body)
            if ok then updated = updated + 1 else failed = failed + 1 end
        else
            local numAcc = (GetNumMacros and GetNumMacros()) or 0
            if numAcc >= 120 then
                failed = failed + 1  -- нет места в общих макросах
            else
                local ok = pcall(CreateMacro, mac.name, MACRO_ICON, mac.body, false)
                if ok then created = created + 1 else failed = failed + 1 end
            end
        end
    end
    if failed > 0 then
        ns.Print(string.format("макросы: создано %d, обновлено %d, не удалось %d — " ..
            "проверь, что в ОБЩИХ макросах есть свободные слоты (лимит 120).", created, updated, failed))
    else
        ns.Print(string.format("макросы готовы: создано %d, обновлено %d. Открой " ..
            ns.C("FFFF00", "/macro") .. ", перетащи на панель и замени НИК_ИГРОКА.", created, updated))
    end
end

-- -------------------------------------------------------------------------
-- Построение списка чекбоксов на прокручиваемой панели
-- -------------------------------------------------------------------------
local function BuildChecklist(scrollParent, options, getValue, onToggle)
    local content = CreateFrame("Frame", nil, scrollParent)
    content:SetSize(520, 10)

    local COL_X = { 10, 270 }
    local ROW_H = 26

    local rows = {}   -- виджеты с метаданными для перерасчёта раскладки
    local checks = {} -- [key] = чекбокс (для программного обновления галки)
    local Relayout   -- forward

    -- Создаём все виджеты (позиции проставит Relayout).
    for _, opt in ipairs(options) do
        if opt.header then
            -- Заголовок. Спойлер (opt.spoiler) — кликабельный, со стрелкой
            -- +/−; сворачивает свою секцию до следующего заголовка.
            local hb = CreateFrame("Button", nil, content)
            hb:SetHeight(20)
            local tex
            if opt.spoiler then
                tex = hb:CreateTexture(nil, "ARTWORK")
                tex:SetSize(16, 16)
                tex:SetPoint("LEFT", hb, "LEFT", 0, 0)
            end
            local ht = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            ht:SetPoint("LEFT", hb, "LEFT", opt.spoiler and 20 or 0, 0)
            ht:SetText(C("FFD100", opt.header))
            hb:SetWidth(ht:GetStringWidth() + (opt.spoiler and 22 or 0) + 4)
            local row = { kind = "header", opt = opt, frame = hb, tex = tex,
                          spoiler = opt.spoiler, collapsed = opt.collapsed or false }
            local function UpdateArrow()
                if not tex then return end
                tex:SetTexture(row.collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                    or "Interface\\Buttons\\UI-MinusButton-Up")
            end
            UpdateArrow()
            if opt.spoiler then
                hb:SetScript("OnClick", function()
                    row.collapsed = not row.collapsed
                    UpdateArrow()
                    Relayout()
                end)
            end
            rows[#rows + 1] = row
        elseif opt.text then
            local t = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            t:SetWidth(496)
            t:SetJustifyH("LEFT")
            t:SetText(opt.text)
            rows[#rows + 1] = { kind = "text", opt = opt, fs = t }
        else
            local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            cb:SetSize(26, 26)
            cb.Text:SetText(opt.name)
            cb.Text:SetFontObject("GameFontHighlight")
            cb:SetChecked(getValue(opt.key))
            cb:SetScript("OnEnter", function(self)
                if opt.desc and opt.desc ~= "" then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(opt.name, 1, 1, 1)
                    GameTooltip:AddLine(opt.desc, nil, nil, nil, true)
                    GameTooltip:Show()
                end
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cb:SetScript("OnClick", function(self)
                onToggle(opt, self:GetChecked() and true or false)
            end)
            rows[#rows + 1] = { kind = "check", opt = opt, cb = cb }
            checks[opt.key] = cb
        end
    end

    -- Программно выставить галку по ключу (например, когда выбор звука
    -- автоматически включает функцию).
    content.SetKeyChecked = function(_, key, state)
        if checks[key] then checks[key]:SetChecked(state) end
    end

    Relayout = function()
        local y = -4
        local col = 0
        local curCollapsed = false
        for _, r in ipairs(rows) do
            if r.kind == "header" then
                if col == 1 then col = 0; y = y - ROW_H end
                y = y - 10
                r.frame:ClearAllPoints()
                r.frame:SetPoint("TOPLEFT", 10, y)
                r.frame:Show()
                curCollapsed = r.spoiler and r.collapsed
                y = y - 26
            elseif r.kind == "text" then
                if curCollapsed then
                    r.fs:Hide()
                else
                    if col == 1 then col = 0; y = y - ROW_H end
                    y = y - 6
                    r.fs:ClearAllPoints()
                    r.fs:SetPoint("TOPLEFT", 12, y)
                    r.fs:Show()
                    y = y - r.fs:GetStringHeight() - 10
                end
            else -- check
                if curCollapsed then
                    r.cb:Hide()
                else
                    r.cb:ClearAllPoints()
                    r.cb:SetPoint("TOPLEFT", COL_X[col + 1], y)
                    r.cb:Show()
                    if col == 0 then col = 1 else col = 0; y = y - ROW_H end
                end
            end
        end
        if col == 1 then y = y - ROW_H end
        content:SetHeight(-y + 20)
        if content.OnRelayout then content.OnRelayout() end
    end

    content.Relayout = Relayout
    Relayout()
    return content
end

-- -------------------------------------------------------------------------
-- Окно
-- -------------------------------------------------------------------------
local optionsFrame

-- Выпадающий список на MenuUtil: кнопка показывает текущий выбор, клик
-- открывает меню с радио-опциями. options = { {text=, value=}, ... }.
local function MakeDropdown(parent, width, get, set, options)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    local function CurrentText()
        local v = get()
        for _, o in ipairs(options) do
            if o.value == v then return o.text end
        end
        return options[1] and options[1].text or "—"
    end
    btn:SetText(CurrentText())
    btn:SetScript("OnClick", function()
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(btn, function(_, root)
            for _, o in ipairs(options) do
                root:CreateRadio(o.text,
                    function() return get() == o.value end,
                    function()
                        set(o.value)
                        btn:SetText(CurrentText())
                        return MenuResponse and MenuResponse.Close
                    end)
            end
        end)
    end)
    return btn
end

-- Селектор со стрелками ◀ [текст] ▶ (как в «Параметры → Звук»): стрелки
-- листают список, клик по центру — предпросмотр. options = { {text=,value=}, ... }
local function MakeArrowSelector(parent, width, get, set, options, onPreview, height)
    local H = height or 24
    local AR = H - 2 -- размер стрелок и высота центральной кнопки
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, H)

    local left = CreateFrame("Button", nil, holder)
    left:SetSize(AR, AR)
    left:SetPoint("LEFT", holder, "LEFT", 0, 0)
    left:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    left:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    left:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")

    local right = CreateFrame("Button", nil, holder)
    right:SetSize(AR, AR)
    right:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    right:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    right:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    right:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")

    local center = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    center:SetPoint("LEFT", left, "RIGHT", 2, 0)
    center:SetPoint("RIGHT", right, "LEFT", -2, 0)
    center:SetHeight(AR)

    local function CurIndex()
        local v = get()
        for i, o in ipairs(options) do if o.value == v then return i end end
        return 1
    end
    local function Refresh()
        local o = options[CurIndex()]
        center:SetText(o and o.text or "—")
    end
    local function Step(delta)
        local i = CurIndex() + delta
        if i < 1 then i = #options elseif i > #options then i = 1 end
        set(options[i].value)
        Refresh()
        if onPreview then onPreview(options[i].value) end
    end
    left:SetScript("OnClick", function() Step(-1) end)
    right:SetScript("OnClick", function() Step(1) end)
    -- Клик по центру — выпадающий список всех вариантов (радио); выбор
    -- применяется и проигрывается. Стрелки при этом продолжают листать.
    center:SetScript("OnClick", function()
        if not (MenuUtil and MenuUtil.CreateContextMenu) then
            if onPreview then onPreview(options[CurIndex()].value) end
            return
        end
        MenuUtil.CreateContextMenu(center, function(_, root)
            -- Ограничиваем высоту меню и включаем прокрутку — иначе длинный
            -- список звуков (сотни от чужих аддонов) растягивается на весь экран.
            if root.SetScrollMode then
                root:SetScrollMode(GetScreenHeight() * 0.5)
            end
            for _, o in ipairs(options) do
                root:CreateRadio(o.text,
                    function() return get() == o.value end,
                    function()
                        set(o.value)
                        Refresh()
                        if onPreview then onPreview(o.value) end
                        return MenuResponse and MenuResponse.Close
                    end)
            end
        end)
    end)
    Refresh()
    holder.Refresh = Refresh
    return holder
end

local function CreateOptionsWindow()
    local f = CreateFrame("Frame", "RainonUIOptions", UIParent, "DefaultPanelFlatTemplate")
    f:SetSize(620, 590)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetTitle("RainonUI")
    table.insert(UISpecialFrames, "RainonUIOptions")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)

    -- Пояснение
    local intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", 16, -34)
    intro:SetPoint("TOPRIGHT", -16, -34)
    intro:SetJustifyH("LEFT")
    f.Intro = intro

    -- Верхние кнопки панели «Скрипты» (две на всю ширину): слева режим
    -- «крестики скрытия», справа «вернуть весь скрытый интерфейс». Показываются
    -- только на вкладке «Скрипты» (см. SelectTab).
    local setupBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    setupBtn:SetSize(288, 24)
    setupBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -32)
    local function UpdateSetupBtn()
        local on = ns.db.features and ns.db.features.hideSetupMode
        setupBtn:SetText(on and "Настройка скрытия: ВКЛ" or "Настройка скрытия: ВЫКЛ")
    end
    UpdateSetupBtn()
    setupBtn:SetScript("OnClick", function()
        local on = not (ns.db.features and ns.db.features.hideSetupMode)
        if ns.db.features then ns.db.features.hideSetupMode = on end
        if ns.HideUI and ns.HideUI.SetSetupMode then ns.HideUI.SetSetupMode(on) end
        UpdateSetupBtn()
    end)
    setupBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Настройка скрытия (крестики)", 1, 1, 1)
        GameTooltip:AddLine("Показывает красные крестики на скрываемых элементах" ..
            " интерфейса. Клик по крестику скрывает элемент — удобно выбрать всё" ..
            " наглядно, потом выключить режим.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    setupBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    setupBtn:Hide()

    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(288, 24)
    resetBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -32)
    resetBtn:SetText("Вернуть весь скрытый интерфейс")
    resetBtn:SetScript("OnClick", function() StaticPopup_Show("RAINONUI_RESET_HIDE") end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Вернуть весь скрытый интерфейс", 1, 1, 1)
        GameTooltip:AddLine("Снимает ВСЕ галочки скрытия в аддоне и перезагружает" ..
            " интерфейс, чтобы всё вернулось на место.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    resetBtn:Hide()

    -- Прокрутка: один scroll child, внутри — все панели (видима одна).
    -- ScrollFrame обрезает только свой scroll child, поэтому панели
    -- обязаны жить внутри контейнера, а не подменяться местами.
    -- ScrollFrameTemplate (12.0) сам создаёт современную тонкую полосу
    -- прокрутки MinimalScrollBar с новыми стрелочками.
    local scroll = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -78)
    scroll:SetPoint("BOTTOMRIGHT", -28, 16)
    f.Scroll = scroll

    local container = CreateFrame("Frame", nil, scroll)
    container:SetSize(540, 10)
    scroll:SetScrollChild(container)

    -- Панель «Скрипты» (скрытие UI)
    local hidePanel = BuildChecklist(container,
        HIDE_OPTIONS,
        function(key)
            if key == "__alwaysCompare" then
                local v = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("alwaysCompareItems"))
                    or (GetCVar and GetCVar("alwaysCompareItems"))
                return v == "0"
            end
            return ns.db.hide[key]
        end,
        function(opt, state)
            if opt.key == "__alwaysCompare" then
                -- галка = сравнение ВЫКЛ; снятие возвращает (1).
                local val = state and "0" or "1"
                if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar("alwaysCompareItems", val)
                elseif SetCVar then SetCVar("alwaysCompareItems", val) end
                return
            end
            ns.db.hide[opt.key] = state
            if state then
                ns.HideUI.ApplyKey(opt.key)
            elseif ns.HideUI.Unhide then
                ns.HideUI.Unhide(opt.key)
            end
        end)
    hidePanel:SetPoint("TOPLEFT")
    -- При сворачивании спойлеров пересчитываем высоту прокрутки (панель «Скрипты»).
    hidePanel.OnRelayout = function() container:SetHeight(hidePanel:GetHeight()) end

    -- Панель «Инструменты»
    local onToolToggle = function(opt, state)
        ns.db.tools[opt.key] = state
        ns.Tools.OnToggle(opt.key, state)
    end
    local toolsPanel = BuildChecklist(container,
        TOOLS_OPTIONS,
        function(key) return ns.db.tools[key] end,
        onToolToggle)
    toolsPanel:SetPoint("TOPLEFT")

    -- Панель «Профессии»
    local profPanel = BuildChecklist(container,
        PROF_OPTIONS,
        function(key) return ns.db.tools[key] end,
        onToolToggle)
    profPanel:SetPoint("TOPLEFT")

    -- Строки «Баффы крафта»: галочка + название + выпадающий список выбора,
    -- и кнопка открытия окна «Недельные знания» (Knowledge.lua).
    do
        local y = -profPanel:GetHeight() + 6

        -- строка: [галочка трекера] [название] [дропдаун выбора]
        local function ProfRow(toolKey, label, dropWidth, cfgKey, options)
            local cb = CreateFrame("CheckButton", nil, profPanel, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("TOPLEFT", 10, y)
            cb:SetChecked(ns.db.tools[toolKey] ~= false)
            cb:SetScript("OnClick", function(self)
                onToolToggle({ key = toolKey }, self:GetChecked() and true or false)
            end)
            local lbl = profPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            lbl:SetText(label)
            local dd = MakeDropdown(profPanel, dropWidth,
                function() return ns.db.tools[cfgKey] end,
                function(v) ns.db.tools[cfgKey] = v end,
                options)
            dd:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            y = y - 32
        end

        ProfRow("prof_phial", "Харанирский флакон изобретательности", 120, "phialQuality", {
            { text = "Качество 1", value = 241313 },
            { text = "Качество 2", value = 241312 },
        })
        ProfRow("prof_essence", "Раскалывание сущности", 210, "shatterEssence", {
            { text = "Частица чистой Бездны",       value = 236952 },
            { text = "Частица дикой магии",         value = 236951 },
            { text = "Частица изначальной энергии", value = 236950 },
            { text = "Частица света",               value = 236949 },
        })

        local knowBtn = CreateFrame("Button", nil, profPanel, "UIPanelButtonTemplate")
        knowBtn:SetSize(230, 26)
        knowBtn:SetPoint("TOPLEFT", 10, y - 6)
        knowBtn:SetText("Недельные знания…")
        knowBtn:SetScript("OnClick", function()
            if ns.Knowledge and ns.Knowledge.Toggle then ns.Knowledge:Toggle() end
        end)
        knowBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Недельные знания", 1, 1, 1)
            GameTooltip:AddLine("Открывает отдельное окно: недельный квест профессии" ..
                " и трактат по каждой профессии. Команда " .. C("FFFF00", "/rsk") .. ".",
                nil, nil, nil, true)
            GameTooltip:Show()
        end)
        knowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - 6 - 26 - 12   -- ниже кнопки «Недельные знания…»

        -- Трактат: две галки (подпись в подсказке + пиксельное свечение).
        local function ProfFeatureCB(featureKey, label, tip, onChange)
            local cb = CreateFrame("CheckButton", nil, profPanel, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("TOPLEFT", 10, y)
            cb:SetChecked(ns.db.features[featureKey] ~= false)
            cb:SetScript("OnClick", function(self)
                ns.db.features[featureKey] = self:GetChecked() and true or false
                if onChange then onChange() end
            end)
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label, 1, 1, 1)
                GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            local l = profPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            l:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            l:SetText(label)
            y = y - 28
        end
        ProfFeatureCB("treatiseTooltip", "Подпись трактата в подсказке",
            "В подсказке предмета-трактата: использован ли он на этой неделе" ..
            " (галочка/крестик), для профессий текущего персонажа.")
        ProfFeatureCB("treatiseGlow", "Свечение неиспользованного трактата",
            "Иконка трактата (в сумках и сундуке отряда, в т.ч. в Баганаторе)" ..
            " светится пиксельным свечением, пока трактат не использован.",
            function() if ns.Treatise and ns.Treatise.RefreshBank then ns.Treatise.RefreshBank() end end)
        y = y - 8

        -- Разделительная линия
        local div = profPanel:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.15)
        div:SetSize(500, 1)
        div:SetPoint("TOPLEFT", 10, y)
        y = y - 14

        -- «Купи сумку» + справка (перенесено из бывшей вкладки «Валюта»)
        local moxieCB = CreateFrame("CheckButton", nil, profPanel, "UICheckButtonTemplate")
        moxieCB:SetSize(24, 24)
        moxieCB:SetPoint("TOPLEFT", 10, y)
        moxieCB:SetChecked(ns.db.tools.curr_moxie ~= false)
        moxieCB:SetScript("OnClick", function(self)
            onToolToggle({ key = "curr_moxie" }, self:GetChecked() and true or false)
        end)
        moxieCB:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Купи сумку!", 1, 1, 1)
            GameTooltip:AddLine("Если «Пыла искусного мастера» 600 и больше — иконка" ..
                " с подсветкой «Купи сумку!» (сумка стоит 600). Двигается в режиме" ..
                " редактирования.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        moxieCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local moxieLbl = profPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        moxieLbl:SetPoint("LEFT", moxieCB, "RIGHT", 4, 0)
        moxieLbl:SetText("Купи сумку!")
        y = y - 30

        local moxieText = profPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        moxieText:SetPoint("TOPLEFT", 12, y)
        moxieText:SetWidth(496)
        moxieText:SetJustifyH("LEFT")
        moxieText:SetText(MOXIE_INFO)
        y = y - moxieText:GetStringHeight() - 12

        profPanel:SetHeight(-y + 20)
    end

    -- Панель «Удобства»: телепорт, кнопка перезагрузки, метка танка
    local featuresPanel = BuildChecklist(container,
        FEATURES_OPTIONS,
        function(key) return ns.db.features[key] end,
        function(opt, state)
            ns.db.features[opt.key] = state
            if opt.key == "teleportPrompt" and not state and ns.Teleport then
                ns.Teleport.Hide()
            elseif opt.key == "tankMark" and ns.Tools and ns.Tools.RefreshTankMark then
                ns.Tools.RefreshTankMark()
            elseif opt.key == "craftAHButton" and ns.Integrations then
                ns.Integrations.RefreshAH()
            end
        end)
    featuresPanel:SetPoint("TOPLEFT")

    -- Выбор значка для «Метки танка» (дропдаун под списком «Удобства»).
    -- Значки — стандартные метки цели с инлайн-иконкой в тексте.
    do
        local y = -featuresPanel:GetHeight() + 4
        local lbl = featuresPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", 12, y)
        lbl:SetText("Значок метки танка:")
        local MARK = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:16|t "
        local markOptions = {
            { text = MARK:format(8) .. "Череп",       value = 8 },
            { text = MARK:format(7) .. "Крест",       value = 7 },
            { text = MARK:format(6) .. "Квадрат",     value = 6 },
            { text = MARK:format(5) .. "Полумесяц",   value = 5 },
            { text = MARK:format(4) .. "Треугольник", value = 4 },
            { text = MARK:format(3) .. "Ромб",        value = 3 },
            { text = MARK:format(2) .. "Круг",        value = 2 },
            { text = MARK:format(1) .. "Звезда",      value = 1 },
        }
        local dd = MakeDropdown(featuresPanel, 150,
            function() return ns.db.features.tankMarkIcon or 8 end,
            function(v)
                ns.db.features.tankMarkIcon = v
                if ns.Tools and ns.Tools.RefreshTankMark then ns.Tools.RefreshTankMark() end
            end,
            markOptions)
        dd:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
        featuresPanel:SetHeight(featuresPanel:GetHeight() + 40)
    end

    -- === Секция «Воскрешение» (заголовок как у CraftSim) ===
    -- Две функции: звук когда воскрешают ТЕБЯ, и звук когда кто-то в группе/рейде
    -- КАСТУЕТ воскрешение. У каждой — своя галка и свой селектор звука (крупный,
    -- по центру). Выбор звука сам включает соответствующую галку.
    do
        local PANEL_W = 520
        local y = -featuresPanel:GetHeight() - 4

        local hdr = featuresPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        hdr:SetPoint("TOPLEFT", 10, y)
        hdr:SetText(C("FFD100", "Воскрешение"))
        y = y - 28

        -- Галка с подписью и тултипом; возвращает чекбокс.
        local function MakeCheck(featureKey, label, tip, onChange)
            local cb = CreateFrame("CheckButton", nil, featuresPanel, "UICheckButtonTemplate")
            cb:SetSize(26, 26)
            cb:SetPoint("TOPLEFT", 10, y)
            cb.Text:SetText(label)
            cb.Text:SetFontObject("GameFontHighlight")
            cb:SetChecked(ns.db.features[featureKey] and true or false)
            cb:SetScript("OnClick", function(self)
                ns.db.features[featureKey] = self:GetChecked() and true or false
                if onChange then onChange(ns.db.features[featureKey]) end
            end)
            if tip then
                cb:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(label, 1, 1, 1)
                    GameTooltip:AddLine(tip, nil, nil, nil, true)
                    GameTooltip:Show()
                end)
                cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            y = y - 28
            return cb
        end

        -- Крупный (1.5x) селектор звука по центру панели. applyFn получает имя.
        local function MakeSoundSelector(getName, applyFn, previewFn)
            local names = (ns.Tools and ns.Tools.GetSoundNames and ns.Tools.GetSoundNames()) or {}
            local opts = {}
            for i, n in ipairs(names) do opts[i] = { text = n, value = n } end
            if #opts == 0 then opts[1] = { text = "—", value = "None" } end
            local sel = MakeArrowSelector(featuresPanel, 390, getName, applyFn, opts,
                function(v) applyFn(v); if previewFn then previewFn() end end, 34)
            sel:SetPoint("TOP", featuresPanel, "TOPLEFT", PANEL_W / 2, y)
            y = y - 42
            return sel
        end

        -- 1) Звук, когда воскрешают ТЕБЯ.
        local cb1
        cb1 = MakeCheck("resurrectSoundOn", "Звук воскрешения",
            "Играет, когда на тебя применили воскрешение (окно «Воскреснуть»).")
        MakeSoundSelector(
            function() return (ns.Tools and ns.Tools.CurrentSoundName and ns.Tools.CurrentSoundName()) or "None" end,
            function(v)
                ns.db.features.resurrectSound = v
                ns.db.features.resurrectSoundOn = true
                cb1:SetChecked(true)
            end,
            function() if ns.Tools and ns.Tools.PlayResurrectPreview then ns.Tools.PlayResurrectPreview() end end)

        -- 2) Звук, когда кто-то в группе/рейде КАСТУЕТ воскрешение.
        local cb2
        cb2 = MakeCheck("resCastSoundOn", "Звук воскрешения союзника",
            "Играет, когда кто-то в группе/рейде применяет заклинание воскрешения" ..
            " (одиночное или массовое, напр. Искупление/Отпущение паладина).")
        MakeSoundSelector(
            function() return (ns.Tools and ns.Tools.CurrentResCastSoundName and ns.Tools.CurrentResCastSoundName()) or "None" end,
            function(v)
                ns.db.features.resCastSound = v
                ns.db.features.resCastSoundOn = true
                cb2:SetChecked(true)
            end,
            function() if ns.Tools and ns.Tools.PlayResCastPreview then ns.Tools.PlayResCastPreview() end end)

        featuresPanel:SetHeight(featuresPanel:GetHeight() + 28 + 28 + 42 + 28 + 42 + 12)
    end

    -- Панель «Макросы»: «Создать ВСЕ» по центру + матрица [иконка | РУ | ЕУ]
    local macroPanel = CreateFrame("Frame", nil, container)
    macroPanel:SetSize(520, 260)
    macroPanel:SetPoint("TOPLEFT")
    do
        local info = macroPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        info:SetPoint("TOPLEFT", 12, -10)
        info:SetPoint("TOPRIGHT", -12, -10)
        info:SetJustifyH("CENTER")
        info:SetText("Создают готовые макросы паладина в " .. C("FFD100", "ОБЩИХ") .. " макросах (префикс " ..
            C("FFD100", "1.x_RainonUI") .. "). " .. C("FFD100", "РУ") .. "/" .. C("FFD100", "ЕУ") ..
            " — одна способность на нужном языке клиента.\nПосле — " .. C("FFFF00", "/macro") ..
            ", перетащи на панель и замени " .. C("FFD100", "НИК_ИГРОКА") .. ".")

        -- «Баф паладина» (перенесено из «Удобств») — освятить оружие.
        local palCB = CreateFrame("CheckButton", nil, macroPanel, "UICheckButtonTemplate")
        palCB:SetSize(26, 26)
        palCB:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 2, -8)
        palCB:SetChecked(ns.db.features.paladinWeapon ~= false)
        palCB:SetScript("OnClick", function(self)
            ns.db.features.paladinWeapon = self:GetChecked() and true or false
            if ns.PaladinBuff and ns.PaladinBuff.Apply then ns.PaladinBuff.Apply() end
        end)
        palCB:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Баф паладина", 1, 1, 1)
            GameTooltip:AddLine("Кликабельная иконка (только паладин): по клику" ..
                " накладывает обряд освящения (усиленное оружие). Появляется, когда" ..
                " на оружии нет временного зачарования.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        palCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local palLbl = macroPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        palLbl:SetPoint("LEFT", palCB, "RIGHT", 4, 0)
        palLbl:SetText("Баф паладина (освятить оружие)")

        -- Невидимый якорь на всю ширину под чекбоксом — чтобы строки макросов
        -- центрировались по панели, а не по узкому чекбоксу (иначе разъезжались).
        local rowAnchor = CreateFrame("Frame", nil, macroPanel)
        rowAnchor:SetHeight(1)
        rowAnchor:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -40)
        rowAnchor:SetPoint("TOPRIGHT", info, "BOTTOMRIGHT", 0, -40)

        -- одна строка матрицы: [иконка] [кнопка РУ] [кнопка ЕУ] [инфо-?]
        -- ширина фиксированная (со слотом под инфо) — чтобы столбцы РУ/ЕУ
        -- совпадали во всех строках, даже без инфо-кнопки.
        local ROW_W = 26 + 8 + 210 + 8 + 210 + 8 + 36
        local function MakeRow(prev, icon, ruText, ruFn, euText, euFn, desc)
            local rowF = CreateFrame("Frame", nil, macroPanel)
            rowF:SetSize(ROW_W, 26)
            rowF:SetPoint("TOP", prev, "BOTTOM", 0, -10)

            local ic = rowF:CreateTexture(nil, "ARTWORK")
            ic:SetSize(26, 26)
            ic:SetPoint("LEFT", rowF, "LEFT", 0, 0)
            ic:SetTexture(icon)
            ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local ruB = CreateFrame("Button", nil, rowF, "UIPanelButtonTemplate")
            ruB:SetSize(210, 24)
            ruB:SetPoint("LEFT", ic, "RIGHT", 8, 0)
            ruB:SetText(ruText)
            ruB:SetScript("OnClick", ruFn)

            local euB = CreateFrame("Button", nil, rowF, "UIPanelButtonTemplate")
            euB:SetSize(210, 24)
            euB:SetPoint("LEFT", ruB, "RIGHT", 8, 0)
            euB:SetText(euText)
            euB:SetScript("OnClick", euFn)

            -- инфо-кнопка «i» справа (только для строк способностей)
            if desc then
                local infoBtn = CreateFrame("Button", nil, rowF)
                infoBtn:SetSize(36, 36)  -- в 2 раза крупнее прежней иконки
                infoBtn:SetPoint("LEFT", euB, "RIGHT", 8, 0)
                local itex = infoBtn:CreateTexture(nil, "ARTWORK")
                itex:SetAllPoints()
                -- Иконка «i» как в Spellbook игрока: текстура кнопки
                -- MainHelpPlateButton (Interface\Common\help-i) — крупная и
                -- без пикселей, вместо старой FriendsFrame\InformationIcon.
                itex:SetTexture("Interface\\Common\\help-i")
                infoBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Что делает макрос", 1, 1, 1)
                    GameTooltip:AddLine(desc, 0.85, 0.85, 0.85, true)
                    GameTooltip:Show()
                end)
                infoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end

            return rowF
        end

        local function CollectSet(langKey)
            local t = {}
            for _, row in ipairs(MACRO_ROWS) do t[#t + 1] = row[langKey] end
            return t
        end

        -- Верхняя строка: [логотип] [Создать ВСЕ РУ] [Создать ВСЕ ЕУ] (без инфо)
        local prev = MakeRow(rowAnchor, MACRO_ALL_ICON,
            "Создать ВСЕ РУ", function() CreateMacroSet(CollectSet("ru")) end,
            "Создать ВСЕ ЕУ", function() CreateMacroSet(CollectSet("eu")) end)

        -- Строки по способностям: [иконка спелла] [РУ] [ЕУ] [инфо]
        for _, row in ipairs(MACRO_ROWS) do
            prev = MakeRow(prev, row.icon,
                row.ru.label, function() CreateMacroSet({ row.ru }) end,
                row.eu.label, function() CreateMacroSet({ row.eu }) end,
                row.desc)
        end
    end

    -- Панель «Ссылки»: кнопка выделяет ссылку, копировать Ctrl+C
    local linksPanel = CreateFrame("Frame", nil, container)
    linksPanel:SetSize(520, 230)
    linksPanel:SetPoint("TOPLEFT")
    do
        local LINKS = {
            { name = "Obsidian",
              url = "https://publish.obsidian.md/sanctumoflight/Библиотеки/Игра/Аддоны" },
            { name = "Boosty",
              url = "https://boosty.to/rainon" },
            { name = "Discord",
              url = "https://discord.com/invite/yAhvHbM" },
        }
        local y = -20
        for _, link in ipairs(LINKS) do
            local btn = CreateFrame("Button", nil, linksPanel, "UIPanelButtonTemplate")
            btn:SetSize(120, 26)
            btn:SetPoint("TOPLEFT", 10, y)
            btn:SetText(link.name)

            local box = CreateFrame("EditBox", nil, linksPanel, "InputBoxTemplate")
            box:SetSize(350, 24)
            box:SetPoint("LEFT", btn, "RIGHT", 16, 0)
            box:SetAutoFocus(false)
            box:SetText(link.url)
            box:SetCursorPosition(0)
            box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            box:SetScript("OnTextChanged", function(self, userInput)
                -- ссылку нельзя испортить: любой ввод возвращает текст
                if userInput then self:SetText(link.url); self:HighlightText() end
            end)
            box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

            btn:SetScript("OnClick", function()
                box:SetFocus()
                box:HighlightText()
            end)
            y = y - 48
        end
        local hint = linksPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 12, y - 6)
        hint:SetText("Нажми на кнопку — ссылка выделится, скопируй её " ..
            C("FFFF00", "Ctrl+C") .. ".")
    end

    local PANELS = {
        { panel = hidePanel,
          intro = "Отметь элементы интерфейса, которые нужно скрыть." },
        { panel = toolsPanel,
          intro = "Игровые инструменты: стикеры сбора рейда, напоминания и оповещения." },
        { panel = profPanel,
          intro = "Профессии: баффы крафта, недельные знания и «Купи сумку»." },
        { panel = featuresPanel,
          intro = "Удобства: телепорт, перезагрузка в игровом меню, метка танка, звук воскрешения." },
        { panel = macroPanel,
          intro = "Паладин: баф освящения оружия и готовые макросы (РУ/ЕУ)." },
        { panel = linksPanel,
          intro = "Полезные ссылки автора: библиотека аддонов и поддержка." },
    }

    local tabs = {}
    local function SelectTab(index)
        f.selectedTab = index
        for i, tab in ipairs(tabs) do
            tab.SelectedTexture:SetShown(i == index)
        end
        for i, entry in ipairs(PANELS) do
            entry.panel:SetShown(i == index)
        end
        container:SetHeight(PANELS[index].panel:GetHeight())
        intro:SetText(PANELS[index].intro)
        -- На вкладке «Скрипты» сверху две кнопки, поэтому пояснение сдвигаем
        -- ниже них; на остальных вкладках кнопок нет и текст вверху.
        local isHide = (index == 1)
        setupBtn:SetShown(isHide)
        resetBtn:SetShown(isHide)
        intro:ClearAllPoints()
        if isHide then
            UpdateSetupBtn()
            intro:SetPoint("TOPLEFT", 16, -60)
            intro:SetPoint("TOPRIGHT", -16, -60)
        else
            intro:SetPoint("TOPLEFT", 16, -34)
            intro:SetPoint("TOPRIGHT", -16, -34)
        end
        scroll:SetVerticalScroll(0)
    end

    -- Боковые вкладки слева: квадратные ячейки вплотную к рамке окна,
    -- как вкладки гильдейского банка (чёрная подложка + иконка +
    -- слот-рамка UI-Quickslot2 + подсветка выбора CheckButtonHilight).
    local function MakeTab(index, iconID, tooltip)
        local tab = CreateFrame("Button", nil, f)
        tab:SetSize(36, 36)
        tab:SetPoint("TOPRIGHT", f, "TOPLEFT", 1, -56 - (index - 1) * 42)
        tab:SetFrameLevel(f:GetFrameLevel() + 2)

        tab.bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.bg:SetAllPoints()
        tab.bg:SetColorTexture(0, 0, 0, 0.85)

        tab.Icon = tab:CreateTexture(nil, "ARTWORK")
        tab.Icon:SetPoint("TOPLEFT", 2, -2)
        tab.Icon:SetPoint("BOTTOMRIGHT", -2, 2)
        tab.Icon:SetTexture(iconID)
        tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- стандартная квадратная слот-рамка (рисуется с запасом 60х60,
        -- как у кнопок действий и вкладок гильд-банка)
        tab.Border = tab:CreateTexture(nil, "OVERLAY")
        tab.Border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        tab.Border:SetSize(60, 60)
        tab.Border:SetPoint("CENTER")

        tab.SelectedTexture = tab:CreateTexture(nil, "OVERLAY", nil, 1)
        tab.SelectedTexture:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        tab.SelectedTexture:SetBlendMode("ADD")
        tab.SelectedTexture:SetAllPoints()
        tab.SelectedTexture:Hide()

        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")
        hl:SetAllPoints()

        tab:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            SelectTab(index)
        end)
        tab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tabs[index] = tab
        return tab
    end

    MakeTab(1, 237447, "Скрипты")
    MakeTab(2, 134376, "Инструменты")
    -- иконка флакона — у самого заклинания, hardcode IconID был битым
    local phialTexture = ns.GetSpellTexture and ns.GetSpellTexture(1239755)
    MakeTab(3, phialTexture or 134756, "Профессии")
    MakeTab(4, 1030099, "Удобства")
    MakeTab(5, "Interface\\Icons\\ClassIcon_Paladin", "Паладин")
    MakeTab(6, "Interface\\Icons\\INV_Misc_Book_09", "Ссылки")

    -- Кнопка перезагрузки: квадратик у левого нижнего угла окна,
    -- в том же стиле, что и боковые вкладки
    local reload = CreateFrame("Button", nil, f)
    reload:SetSize(36, 36)
    reload:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 1, 8)
    reload:SetFrameLevel(f:GetFrameLevel() + 2)

    reload.bg = reload:CreateTexture(nil, "BACKGROUND")
    reload.bg:SetAllPoints()
    reload.bg:SetColorTexture(0, 0, 0, 0.85)

    reload.Icon = reload:CreateTexture(nil, "ARTWORK")
    reload.Icon:SetPoint("TOPLEFT", 6, -6)
    reload.Icon:SetPoint("BOTTOMRIGHT", -6, 6)
    -- Современная иконка «обновить» (круговые стрелки), не пиксельная
    reload.Icon:SetAtlas("questlog-questtypeicon-Recurring")

    reload.Border = reload:CreateTexture(nil, "OVERLAY")
    reload.Border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    reload.Border:SetSize(60, 60)
    reload.Border:SetPoint("CENTER")

    local rhl = reload:CreateTexture(nil, "HIGHLIGHT")
    rhl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    rhl:SetBlendMode("ADD")
    rhl:SetAllPoints()

    reload:SetScript("OnClick", ReloadUI)
    reload:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Перезагрузить интерфейс")
        GameTooltip:Show()
    end)
    reload:SetScript("OnLeave", function() GameTooltip:Hide() end)

    SelectTab(1)
    f:Hide()
    return f
end

local function ToggleOptions()
    if not ns.db then return end
    -- Защита от сбоя: в бою окно настроек не открываем и не создаём.
    -- Переключение галочек скрытия могло прятать защищённые фреймы Blizzard
    -- и валить lua-ошибки, поэтому все настройки — только вне боя.
    if InCombatLockdown() then
        ns.Print("настройки недоступны в бою — открой их после боя.")
        return
    end
    if not optionsFrame then
        optionsFrame = CreateOptionsWindow()
    end
    optionsFrame:SetShown(not optionsFrame:IsShown())
end

-- При входе в бой прячем окно настроек, если оно открыто.
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if optionsFrame and optionsFrame:IsShown() then
        optionsFrame:Hide()
    end
end)

SLASH_RAINONUI1 = "/rainon"
SLASH_RAINONUI2 = "/rs"
SlashCmdList.RAINONUI = ToggleOptions

-- Если другой аддон перехватил /rs — забираем команду себе после входа
-- в мир (хэш слэш-команд перезаписывается напрямую).
ns.RegisterMessage("RAINON_REAPPLY", function()
    SlashCmdList.RAINONUI = ToggleOptions
    if _G.hash_SlashCmdList then
        _G.hash_SlashCmdList["/RS"] = ToggleOptions
        _G.hash_SlashCmdList["/RAINON"] = ToggleOptions
    end
end)