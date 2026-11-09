-- =========================================================================
-- RainonUI / OrderQueue (ЭКСПЕРИМЕНТАЛЬНЫЙ, ТЕСТОВЫЙ модуль).
-- «Очередь заказов» — окно справа от окна профессии: заказы покровителей (NPC),
-- одна кнопка «Дальше» проводит верхний заказ по шагам: взять → сделать → сдать
-- (каждый шаг — одно нажатие; без нажатия игрока игра эти действия не разрешает).
--
-- РАБОТАЕТ САМ, БЕЗ CRAFTSIM. «Мозги» взяты из CraftSim (MIT, © Florian
-- Schneider) и перенесены сюда упрощённо:
--   * качество с учётом талантов/инструментов/реагентов спрашиваем у САМОЙ ИГРЫ —
--     C_TradeSkillUI.GetCraftingOperationInfoForOrder (так же делает CraftSim,
--     Classes/ReagentData.lua); свои таблицы талантов не нужны;
--   * схема реагентов — C_TradeSkillUI.GetRecipeSchematic (как Classes/Reagent.lua:
--     слот с >1 предметом = реагент с качеством, индекс = качество);
--   * подбор реагентов — ПРОСТОЙ: всё на низшем качестве, затем по шагу повышаем
--     там, где прибавка навыка дешевле всего, пока игра не скажет «качество хватает»;
--   * шаги заказа — как очередь CraftSim (Modules/CraftQueue/UI.lua): ClaimOrder →
--     CraftRecipe(…, orderID, false) → FulfillOrder.
--   * качество — как CraftSim (ResultData:Update): навык (baseSkill+bonusSkill)
--     против порогов сложности baseDifficulty (RecipeInfo:GetQualityThresholds).
-- КОНЦЕНТРАЦИЮ НЕ ИСПОЛЬЗУЕМ НИКОГДА (решение Миши 16.10): в CraftRecipe всегда false.
-- Цены реагентов — Auctionator (если включён). Без него очередь работает по
-- качеству, а цена/убыток помечаются «нет цены».
--
-- Правила:
--   ✗ крестик  — рецепт никогда не берём;
--   ✓ галочка  — берём ВСЕГДА, порог убытка не действует; если рецепт «запомнен»
--                (вы делали его сами при включённой записи) — ваши реагенты и
--                концентрация, а не подбор;
--   без отметки — общие условия: качество хватает + убыток ≤ порога.
--   Качество ниже нужного заказу — всегда серым (игра такой заказ не примет).
--
-- Журнал: план (наша цена) и что реально ушло из сумок (до/после крафта).
-- Чёрный список предметов: если без них нужного качества не выйти — заказ серый.
-- Пропуск кнопок Blizzard «Начать/Завершить заказ» + предупреждения о своих
-- реагентах — своя реализация (идея — No Mats No Make); в нашей очереди «взять» и «сдать» идут сами,
-- нажатие нужно только на «Сделать» (крафт без нажатия игра не разрешает).
-- Данные: SavedVariables RainonUIOrdersDB (settings, recipes — «мозги», log).
-- Гейт: features.orderQueue (ВЫКЛ). Вкладка «Тест», /rsorders, тестер.
-- =========================================================================
local _, ns = ...

ns.OrderQueue = ns.OrderQueue or {}
local OQ = ns.OrderQueue

local CALLER   = "RainonUI"
local GOLD     = 10000
local LOG_MAX  = 3000    -- (02.11) день подробной проверки: много заказов
local TRACE_MAX = 8000   -- (02.11) подробный след шагов (временно, потом урежем)
local WIN_W    = 400
OQ.WINDOW_WIDTH = WIN_W
local WIN_H    = 608     -- +26 (02.11): строка «Сферы знаний»; +22 (02.11): строка «Оплата Консорциума»
local ROW_H    = 26
local ROWS     = 14
local ROW_MAX  = 40      -- (02.11) окно по высоте = окно профессии: строк создаём с запасом, видно сколько влезает
local NAME_MAX = 20      -- (02.11) длина названия = «Энтропийный экстракт»; длиннее — сокращаем «…»
local FONT_ADD = 1.3     -- (02.11) шрифт строк крупнее: было +0,5, Миша попросил ещё +0,8
local PAD      = 12
local REAGENT_REQUIRED = 1     -- reagentType «обязательный» (как CraftSim CONST.REAGENT_TYPE.REQUIRED)
local BIG      = 1e12          -- «цена неизвестна» при подборе

-- -------------------------------------------------------------------------
-- База данных модуля
-- -------------------------------------------------------------------------
local function DB()
    RainonUIOrdersDB = RainonUIOrdersDB or {}
    local d = RainonUIOrdersDB
    -- One-time local statistics restart requested by Misha, 2026-11-08.
    -- Dashboard reads active fields only; the original data remains recoverable.
    if not d.accountingReset20261108 then
        d.accountingArchive20261108 = {
            procs = d.procs, procLog = d.procLog, bags = d.bags,
        }
        d.procs, d.procLog, d.bags = {}, {}, {}
        d.accountingReset20261108 = time()
    end
    d.version  = d.version or 1
    d.settings = d.settings or {}
    local s = d.settings
    if s.maxLoss == nil then s.maxLoss = 100 * GOLD end   -- убыток на заказ не больше 100з (старое поле)
    -- (02.11) «Прибыль не меньше» (может быть минусом): −50 = убыток до 50, +20 = только прибыль от 20.
    -- Один раз переносим из старого «Убыток не больше».
    if s.minProfit == nil then s.minProfit = -(s.maxLoss or 0) end
    s.allowConc = nil                                      -- концентрация запрещена (старый ключ чистим)
    if s.remember == nil then s.remember = false end       -- запоминать мои ручные крафты
    if s.skipStart == nil then s.skipStart = true end         -- сам брать заказ (кнопка «Начать»)
    if s.skipComplete == nil then s.skipComplete = true end   -- сам сдавать заказ (кнопка «Завершить»)
    if s.skipOwnReagent == nil then s.skipOwnReagent = true end -- подтверждать «свои реагенты»
    -- Сферы знаний в награде (02.11): учитывать ли и сколько золота стоит одна сфера.
    if s.kpOn == nil then s.kpOn = true end                    -- общий выключатель
    if s.kpGlimmer == nil then s.kpGlimmer = 50 * GOLD end     -- «Отблеск знания»
    if s.kpLight == nil then s.kpLight = 100 * GOLD end        -- «Свет знания»
    -- (02.11) свои реагенты лучшего качества вместо покупных, если дороже не больше чем на N (за заказ)
    if s.ownSwap == nil then s.ownSwap = 10 * GOLD end
    d.recipes = d.recipes or {}
    d.log     = d.log or {}
    d.black   = d.black or {}
    -- Sunglass Vial: ЗОЛОТОЙ = 240990 (проверено в игре 16.10: 240991 — серебряный, с вендора).
    if not d.blackInit then d.black[240990] = true; d.blackInit = true; d.blackFix1 = true end
    if not d.blackFix1 then d.black[240991] = nil; d.black[240990] = true; d.blackFix1 = true end
    -- (02.11) Проки (мультикрафт): список предметов, за которыми следим (как чёрный список).
    -- По умолчанию — ЗОЛОТЫЕ (кач.2): Зелье безрассудства 241288, Талассийское масло феникса 243734
    -- (ID проверены по журналу крафтов: кач.2 → 241288 / 243734, кач.1 зелья → 241289).
    d.watch   = d.watch or {}
    if not d.watchInit then d.watch[241288] = true; d.watch[243734] = true; d.watchInit = true end
    d.procs   = d.procs or {}     -- [itemID][персонаж] = { c крафтов, p проков, x сверх, n всего, best, t }
    d.procLog = d.procLog or {}   -- по крафту: { t, w персонаж, i предмет, n вышло, m сверх } (≤ 5000)
    return d
end

local function Enabled()
    return ns.ProfEnabled() and ns.db and ns.db.features and ns.db.features.orderQueue and true or false
end

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function Num(v) if IsSecret(v) then return nil end return tonumber(v) end
local function SameID(a, b) return a ~= nil and b ~= nil and tostring(a) == tostring(b) end

-- Деньги: «12з» с иконкой золота.
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local function Gold(c)
    if type(c) ~= "number" then return "?" end
    local neg = c < 0
    local g = math.floor(math.abs(c) / GOLD + 0.5)
    return (neg and "-" or "") .. g .. GOLD_ICON
end

-- Цена реагента по Auctionator (если включён).
local function HasPrices()
    return Auctionator and Auctionator.API and Auctionator.API.v1
        and Auctionator.API.v1.GetAuctionPriceByItemID and true or false
end
local function PriceLink(link)
    if not link or not HasPrices() or not Auctionator.API.v1.GetAuctionPriceByItemLink then return nil end
    local ok, p = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, CALLER, link)
    if ok and type(p) == "number" then return p end
    return nil
end
local function Price(itemID)
    if not itemID or not HasPrices() then return nil end
    local ok, p = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, CALLER, itemID)
    if ok and type(p) == "number" then return p end
    return nil
end

-- Сколько предмета есть (сумки + банк + банк реагентов + банк отряда).
local function Count(itemID)
    if not (C_Item and C_Item.GetItemCount) then return 0 end
    local ok, n = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
    return (ok and Num(n)) or 0
end

local function ItemName(id)
    local nm = id and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    return nm or ("предмет " .. tostring(id))
end

-- (02.11) Имена предметов для дашборда на ПК (в файле данных игры имён нет): запоминаем то,
-- что встречалось в заказах, сумках и проверке цен. RainonUIOrdersDB.names[itemID] = "Название".
local function RememberName(id)
    id = tonumber(id)
    if not id then return end
    local d = RainonUIOrdersDB
    if not d then return end
    d.names = d.names or {}
    if d.names[id] then return end
    local nm = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if nm and nm ~= "" and not IsSecret(nm) then d.names[id] = nm end
end

-- Чёрный список: при подборе такие предметы не берём (allowBanned — проверочный проход).
local allowBanned = false
local function Banned(id) return id and not allowBanned and DB().black[id] and true or false end

-- CraftingReagentInfo бывает {reagent={itemID|currencyID}, quantity, dataSlotIndex}.
local function RInfo(r)
    if type(r) ~= "table" then return nil end
    local inner = r.reagent or r
    return inner.itemID, inner.currencyID, r.quantity or 0, r.dataSlotIndex
end

-- (02.11) Валюта для рецепта: название и сколько её у персонажа сейчас.
local function CurName(cid)
    local ci = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(cid)
    local nm = (ci and ci.name and not IsSecret(ci.name)) and ci.name or ("валюта " .. tostring(cid))
    return nm, (ci and Num(ci.quantity)) or 0
end
-- Хватает ли валюты на крафт (проверяем и при «Обновить», и перед самим нажатием «Сделать»).
local function CurrencyOK(m)
    for _, c in ipairs((m and m.cur) or {}) do
        local nm, have = CurName(c.currencyID)
        if have < c.qty then return false, ("Не хватает валюты «%s»: нужно %d, есть %d"):format(nm, c.qty, have) end
    end
    return true
end

-- -------------------------------------------------------------------------
-- «Мозги» расчёта (без CraftSim)
-- -------------------------------------------------------------------------
-- Какие слоты/предметы положил сам заказчик (их не кладём и не покупаем).
-- Реагенты заказчика. Форма order.reagents у Blizzard бывает разной — разбор как у CraftSim
-- (RecipeData:GetOrderReagentDescriptor): предмет из reagentInfo.reagent / reagent.reagent / reagent;
-- если предмета нет — по номеру слота берём первый предмет этого слота схемы.
-- Свой/чужой реагент определяем ТОЛЬКО по предмету (как CraftSim Craft и No Mats No Make).
local function SuppliedOf(order, sch)
    local sup = { items = {}, qty = {}, cur = {} }
    local slotsByData = {}
    for i, sl in ipairs((sch and sch.reagentSlotSchematics) or {}) do
        if sl.dataSlotIndex then slotsByData[sl.dataSlotIndex] = sl end
        sl._idx = i
    end
    for _, ri in ipairs((order and order.reagents) or {}) do
        local cr
        if ri.reagentInfo and ri.reagentInfo.reagent then cr = ri.reagentInfo.reagent
        elseif ri.reagent and ri.reagent.reagent and (ri.reagent.reagent.itemID or ri.reagent.reagent.currencyID) then cr = ri.reagent.reagent
        elseif ri.reagent and (ri.reagent.itemID or ri.reagent.currencyID) then cr = ri.reagent end
        local id = cr and Num(cr.itemID)
        if id == 0 then id = nil end
        local cid = cr and Num(cr.currencyID)
        if cid and cid > 0 and not id then
            -- (02.11) заказчик положил ВАЛЮТУ (например, гребни) — запоминаем отдельно от предметов
            local q = Num((ri.reagentInfo and ri.reagentInfo.quantity) or ri.quantity) or 0
            sup.cur[cid] = (sup.cur[cid] or 0) + q
        elseif not id then
            local ds = ri.dataSlotIndex or (ri.reagentInfo and ri.reagentInfo.dataSlotIndex)
                or (ri.reagent and ri.reagent.dataSlotIndex)
            local sl = ds and slotsByData[ds]
            if not sl and ri.slotIndex and sch then sl = sch.reagentSlotSchematics[ri.slotIndex] end
            local first = sl and sl.reagents and sl.reagents[1]
            id = first and first.itemID
        end
        if id then
            sup.items[id] = true
            local q = Num((ri.reagentInfo and ri.reagentInfo.quantity) or ri.quantity) or 0
            sup.qty[id] = (sup.qty[id] or 0) + q
        end
    end
    return sup
end

-- Модель рецепта: слоты с качеством (qslots) и простые обязательные (fixed).
local function BuildModel(recipeID, order)
    local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(sch) ~= "table" then return nil, "игра не дала схему рецепта" end
    local sup = SuppliedOf(order, sch)
    local rinfo = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
    local m = { recipeID = recipeID, orderID = order and order.orderID, qslots = {}, fixed = {},
                given = {}, cur = {}, maxQ = rinfo and Num(rinfo.maxQuality) or 0 }
    for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local reagents = slot.reagents or {}
        local first = reagents[1]
        local supplied = false
        for _, r in ipairs(reagents) do if r.itemID and sup.items[r.itemID] then supplied = true end end
        if first and first.currencyID and (slot.required or slot.reagentType == REAGENT_REQUIRED) then
            -- (02.11) Рецепт требует ВАЛЮТУ (например, инженерные на мейне). Делаем как CraftSim:
            -- валюта — «обязательный слот с выбором», её передаём игре вместе с реагентами.
            --   * заказчик положил сам → в расчёт навыка входит, сами не тратим;
            --   * вариант один → берём его; вариантов несколько → берём тот, что был в вашем
            --     запомненном ручном крафте этого рецепта; иначе не угадываем — делать руками;
            --   * валюты меньше, чем нужно → заказ не берём, пишем сколько нужно и сколько есть.
            local opts, nOpts, giv = {}, 0, nil
            for _, r in ipairs(reagents) do
                if r.currencyID then
                    opts[r.currencyID] = true; nOpts = nOpts + 1
                    if sup.cur[r.currencyID] then giv = r.currencyID end
                end
            end
            local need = slot.quantityRequired or 0
            if giv then
                m.given[#m.given + 1] = { reagent = { currencyID = giv },
                    quantity = (sup.cur[giv] > 0) and sup.cur[giv] or need, dataSlotIndex = slot.dataSlotIndex }
            else
                local pick
                if nOpts == 1 then pick = first.currencyID
                else
                    local b = DB().recipes[recipeID]
                    for _, r in ipairs((b and b.manual and b.manual.reagents) or {}) do
                        if r.c and opts[r.c] then pick = r.c end
                    end
                end
                if not pick then
                    return nil, ("Рецепт просит выбрать валюту (вариантов: %d) — сделайте его один раз руками " ..
                        "с включённым «Запоминать мои крафты», дальше очередь возьмёт тот же выбор"):format(nOpts)
                end
                local nm, have = CurName(pick)
                if have < need then
                    return nil, ("Не хватает валюты «%s»: нужно %d, есть %d"):format(nm, need, have)
                end
                m.cur[#m.cur + 1] = { currencyID = pick, qty = need, slot = slot.dataSlotIndex }
            end
        elseif supplied and #reagents > 1 then
            -- Реагенты с качеством от заказчика: сами не кладём и не покупаем, НО в расчёт
            -- навыка они входят (как CraftSim: ApplyOrderReagentsToSlots). Иначе навык занижен.
            for _, r in ipairs(reagents) do
                if r.itemID and sup.items[r.itemID] then
                    m.given[#m.given + 1] = { reagent = { itemID = r.itemID },
                        quantity = (sup.qty[r.itemID] and sup.qty[r.itemID] > 0) and sup.qty[r.itemID] or (slot.quantityRequired or 0),
                        dataSlotIndex = slot.dataSlotIndex }
                end
            end
        elseif supplied or (first and first.currencyID) then
            -- заказчик положил сам (простой реагент) / необязательная валюта — пропускаем
        elseif slot.reagentType == REAGENT_REQUIRED then
            if #reagents > 1 then
                local items = {}
                for q, r in ipairs(reagents) do items[q] = r.itemID end
                -- Порядок по качеству берём у игры (порядок в схеме бывает не по возрастанию).
                local rq = C_TradeSkillUI.GetItemReagentQualityByItemInfo
                if rq then
                    local qOf = {}
                    for _, id in ipairs(items) do
                        local okQ, qq = pcall(rq, id)
                        qOf[id] = (okQ and Num(qq)) or nil
                    end
                    local all = true
                    for _, id in ipairs(items) do if not qOf[id] then all = false end end
                    if all then table.sort(items, function(a, b) return qOf[a] < qOf[b] end) end
                end
                m.qslots[#m.qslots + 1] = { slot = slot.dataSlotIndex, qty = slot.quantityRequired or 0,
                                            items = items, alloc = {} }
            elseif first and first.itemID then
                m.fixed[#m.fixed + 1] = { itemID = first.itemID, qty = slot.quantityRequired or 0 }
            end
        elseif slot.required then
            return nil, "нужен особый реагент (например, искра) — пока не поддерживаем"
        end
    end
    return m
end

-- Реагенты с качеством для вызова игры (простые игра кладёт сама — как CraftSim).
local function ReagentTbl(m)
    local t = {}
    for _, s in ipairs(m.qslots) do
        for q, n in pairs(s.alloc) do
            if n > 0 and s.items[q] then
                t[#t + 1] = { reagent = { itemID = s.items[q] }, quantity = n, dataSlotIndex = s.slot }
            end
        end
    end
    -- (02.11) валюта рецепта (слот с выбором) — игре её надо передать явно, как CraftSim
    for _, c in ipairs(m.cur or {}) do
        t[#t + 1] = { reagent = { currencyID = c.currencyID }, quantity = c.qty, dataSlotIndex = c.slot }
    end
    return t
end

-- Расчёт игры: качество/навык/концентрация (таланты и инструменты уже внутри).
local function OpInfo(m)
    local tbl = ReagentTbl(m)
    for _, g in ipairs(m.given or {}) do tbl[#tbl + 1] = g end
    local ok, info
    if m.orderID and C_TradeSkillUI.GetCraftingOperationInfoForOrder then
        ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfoForOrder, m.recipeID, tbl, m.orderID, false)
    else
        ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, m.recipeID, tbl, nil, false)
    end
    if ok and type(info) == "table" then return info end
end
local function Skill(info) return (Num(info.baseSkill) or 0) + (Num(info.bonusSkill) or 0) end
-- Качество по навыку — как CraftSim (ResultData:Update + RECIPE_INFO:GetQualityThresholds).
local function QualityBySkill(skill, maxQ, diff)
    if not maxQ or maxQ <= 1 or not diff or diff <= 0 then return nil end
    local th
    if maxQ == 2 then th = { diff }
    elseif maxQ == 3 then th = { diff * 0.5, diff }
    elseif maxQ == 5 then th = { diff * 0.2, diff * 0.5, diff * 0.8, diff }
    else return nil end
    local q = 1
    for _, t in ipairs(th) do if skill >= t then q = q + 1 end end
    return q
end
local function QualityOf(m, info)
    if not info then return 0 end
    return QualityBySkill(Skill(info), m.maxQ, Num(info.baseDifficulty)) or Num(info.craftingQuality) or 0
end

local function SetAll(m, q)
    for _, s in ipairs(m.qslots) do
        local qq = math.min(q, #s.items)
        while qq < #s.items and Banned(s.items[qq]) do qq = qq + 1 end
        s.alloc = { [qq] = s.qty }
    end
end

-- Один шаг подбора: поднять качество там, где прибавка навыка дешевле всего.
local function StepUp(m)
    local base = OpInfo(m)
    if not base then return false end
    local baseSkill = Skill(base)
    local best, bestScore
    for _, s in ipairs(m.qslots) do
        local from
        for q = 1, #s.items - 1 do if (s.alloc[q] or 0) > 0 then from = q; break end end
        if from and Banned(s.items[from + 1]) then from = nil end
        if from then
            local n = math.min(s.alloc[from], math.max(1, math.ceil(s.qty / 4)))
            s.alloc[from] = s.alloc[from] - n
            s.alloc[from + 1] = (s.alloc[from + 1] or 0) + n
            local info = OpInfo(m)
            s.alloc[from] = s.alloc[from] + n
            s.alloc[from + 1] = s.alloc[from + 1] - n
            local gain = info and (Skill(info) - baseSkill) or 0
            if gain > 0 then
                local p1, p2 = Price(s.items[from]), Price(s.items[from + 1])
                local d = (p1 and p2) and math.max(p2 - p1, 0) * n or BIG
                local score = d / gain
                if not bestScore or score < bestScore then best, bestScore = { s = s, from = from, n = n }, score end
            end
        end
    end
    if not best then return false end
    local s, from, n = best.s, best.from, best.n
    s.alloc[from] = s.alloc[from] - n
    s.alloc[from + 1] = (s.alloc[from + 1] or 0) + n
    return true
end

-- Самый дешёвый набор, дающий качество target (или максимум, что вышло).
local function Climb(m, target)
    SetAll(m, 1)
    local info = OpInfo(m)
    if not info then return nil end
    local q, guard = QualityOf(m, info), 0
    while target > 0 and q < target and guard < 80 do
        guard = guard + 1
        if not StepUp(m) then break end
        info = OpInfo(m)
        q = QualityOf(m, info)
    end
    return q, info
end

-- План: самый дешёвый набор под нужное качество. БЕЗ концентрации.
local function Plan(m, minQ)
    local q, info = Climb(m, minQ)
    if not q then return nil, "игра не дала расчёт качества" end
    return { quality = q, skill = info and Skill(info), diff = info and Num(info.baseDifficulty) }
end

-- (02.11) Свои реагенты лучшего качества. Подбор берёт самое дешёвое качество, даже если его
-- нет в сумках, а лучшее лежит (пример Миши: 107 золотых «Луносветских обмоток» по 5,60 —
-- а подбор хотел серую по 4,95, которой нет). Если нужного качества не хватает, а лучшего
-- хватает и доплата за заказ не больше settings.ownSwap — кладём своё лучшее.
-- Лучшее качество реагента только поднимает навык, поэтому качество результата не упадёт.
local function UseOwnBetter(m)
    if not ns.ProfEnabled() then return end
    local limit = DB().settings.ownSwap or 0
    if limit <= 0 then return end
    m.swapped = nil
    for _, sl in ipairs(m.qslots) do
        for q = 1, #sl.items - 1 do
            local n = sl.alloc[q] or 0
            if n > 0 then
                local short = n - Count(sl.items[q])
                if short > 0 then
                    for q2 = q + 1, #sl.items do
                        local id2 = sl.items[q2]
                        local have2 = Count(id2) - (sl.alloc[q2] or 0)
                        if not Banned(id2) and have2 >= short then
                            local p1, p2 = Price(sl.items[q]), Price(id2)
                            local extra = (p2 and p1) and math.max(p2 - p1, 0) * short or (p2 and 0) or BIG
                            if extra <= limit then
                                sl.alloc[q] = n - short
                                sl.alloc[q2] = (sl.alloc[q2] or 0) + short
                                m.swapped = m.swapped or {}
                                m.swapped[#m.swapped + 1] = { from = sl.items[q], to = id2, n = short, extra = extra }
                            end
                            break
                        end
                    end
                end
            end
        end
    end
end

local function Cost(m)
    local sum, noPrice, plan = 0, 0, {}
    local function add(id, n)
        if not id or n <= 0 then return end
        plan[id] = (plan[id] or 0) + n
        local p = Price(id)
        if p then sum = sum + p * n else noPrice = noPrice + 1 end
    end
    for _, s in ipairs(m.qslots) do for q, n in pairs(s.alloc) do add(s.items[q], n) end end
    for _, f in ipairs(m.fixed) do add(f.itemID, f.qty) end
    return sum, noPrice, plan
end

local function CanCraftPlan(plan)
    for id, n in pairs(plan or {}) do
        local have = Count(id)
        if have < n then return false, id, n - have end
    end
    return true
end

-- Иконки наград покровителя (как столбец «Commission» у Blizzard).
local function RewardIcons(order)
    local t = {}
    for _, rw in ipairs((order and order.npcOrderRewards) or {}) do
        local icon
        local n = Num(rw.count) or 1
        if rw.itemLink and not IsSecret(rw.itemLink) and C_Item and C_Item.GetItemInfoInstant then
            icon = select(5, C_Item.GetItemInfoInstant(rw.itemLink))
        elseif rw.currencyType and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local ci = C_CurrencyInfo.GetCurrencyInfo(rw.currencyType)
            icon = ci and ci.iconFileID
        end
        if icon then t[#t + 1] = "|T" .. icon .. ":16:16|t" .. ((n > 1) and n or "") end
    end
    return table.concat(t, " ")
end

-- -------------------------------------------------------------------------
-- «Мозги» рецептов: аддон узнаёт рецепты сам (из заказов и ваших крафтов).
-- -------------------------------------------------------------------------
local function Brain(recipeID)
    local recipes = DB().recipes
    local b = recipes[recipeID]
    if not b then b = {}; recipes[recipeID] = b end
    return b
end

local function LearnRecipe(recipeID, prof)
    local b = Brain(recipeID)
    local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
    if info then
        b.name = info.name or b.name
        b.icon = info.icon or b.icon
    end
    b.prof = prof or b.prof
    return b
end

local function MarkOf(recipeID)
    local b = DB().recipes[recipeID]
    return b and b.mark or nil
end

-- Записать ваш ручной крафт (реагенты как вы их положили + концентрация).
local function RememberManual(recipeID, reagents, concentrating, orderID)
    local b = LearnRecipe(recipeID)
    local list = {}
    for _, r in ipairs(reagents or {}) do
        local id, cur, qty, slot = RInfo(r)
        if (id or cur) and not IsSecret(id) then
            list[#list + 1] = { i = id, c = cur, q = qty, s = slot }
        end
    end
    b.manual = { reagents = list, conc = concentrating and true or false, t = time(),
                 order = orderID and true or false }
    b.crafted = (b.crafted or 0) + 1
end

-- Разложить запомненные реагенты по слотам модели (правило галочки).
local function ApplyManual(m, manual)
    local byItem = {}
    for _, r in ipairs(manual.reagents or {}) do
        if r.i then byItem[r.i] = (byItem[r.i] or 0) + (r.q or 0) end
    end
    for _, s in ipairs(m.qslots) do
        s.alloc = {}
        local total = 0
        for q, id in ipairs(s.items) do
            local n = byItem[id] or 0
            if n > 0 then s.alloc[q] = n; total = total + n end
        end
        if total == 0 then s.alloc = { [1] = s.qty } end   -- в памяти слота нет — низшее качество
    end
end

-- -------------------------------------------------------------------------
-- Очередь
-- -------------------------------------------------------------------------
local entries  = {}       -- текущая очередь (по последнему «Обновить»)
local scanning = false
local scanProf           -- профессия последнего «Обновить» (для сверки заказов)
local current             -- идущий крафт: { e=entry|nil, log=строка журнала, before={[id]=n} }
local ourCraft = false    -- CraftRecipe зовём мы (не путать с ручным крафтом)
local win
local view = "queue"      -- queue | recipes | log
local offset = 0
local statusText = ""
local profSession          -- текущий заход в профессию: { t, who, prof, ids = {[orderID]=true} }
local lastScanAt = 0
local autoChain = false   -- после первого «Дальше» очередь сама берёт/сдаёт заказы
local fulfillSent = {}    -- [orderID] = true — «сдать» уже отправлено (защита от двойного)
local pauseUntil = 0      -- (02.11) после сдачи кнопка серая 2,5 с — игре нужно время (просьба Миши)
local PAUSE_AFTER_DONE = 2.5
local autoScanAt = 0      -- (02.11) когда последний раз сами нажимали «Обновить» (очередь опустела)

local Refresh             -- вперёд-объявление
local Trace               -- вперёд-объявление (02.11, подробный след)
local FindEntry           -- вперёд-объявление (нужна в OnManualCraft)

local function Status(t) statusText = t or ""; if win and win.status then win.status:SetText(statusText) end end

local function Profession()
    if C_TradeSkillUI and C_TradeSkillUI.GetChildProfessionInfo then
        local child = C_TradeSkillUI.GetChildProfessionInfo()
        if child and child.profession then return child.profession end
    end
    if ProfessionsFrame and ProfessionsFrame.professionInfo then
        return ProfessionsFrame.professionInfo.profession
    end
end

local function ApplyRule(e)
    local s = DB().settings
    e.mark = MarkOf(e.recipeID)
    if e.fatal then e.ok = false; e.reason = e.fatal; e.rule = nil; return end
    if e.black then e.ok = false; e.rule = nil; e.reason = "Чёрный список: " .. ItemName(e.black); return end
    if e.mark == "no" then e.ok = false; e.reason = "Крестик: рецепт исключён"; e.rule = "cross"; return end
    if e.minQ > 0 and (e.expQ or 0) < e.minQ then
        e.ok = false; e.rule = nil
        e.reason = ("Качество: выйдет %d, нужно %d (таланты/реагенты)"):format(e.expQ or 0, e.minQ)
            .. (e.note and (" — " .. e.note) or "")
        return
    end
    if e.plan and e.state == "wait" then e.canCraft, e.missing, e.missingN = CanCraftPlan(e.plan) end
    -- Не хватает реагентов — НЕ серым: заказ проходит фильтры, просто помечаем «нужны реагенты»
    -- (кнопка «Дальше» такие пропускает, пока реагентов нет).
    e.needText = (e.canCraft == false)
        and ("Нужны реагенты" .. (e.missing and (": " .. ItemName(e.missing) .. " x" .. (e.missingN or "?")) or ""))
        or nil
    if e.mark == "yes" then e.ok = true; e.rule = "check"; e.reason = nil; return end
    if (e.profit or 0) < (s.minProfit or 0) then
        e.ok = false; e.rule = nil
        e.reason = ((e.profit or 0) < 0 and ("Убыток " .. Gold(-(e.profit or 0))) or ("Прибыль " .. Gold(e.profit or 0)))
            .. " — меньше порога «Прибыль не меньше» " .. Gold(s.minProfit or 0)
        return
    end
    e.ok = true; e.rule = "general"; e.reason = nil
end

-- -------------------------------------------------------------------------
-- Сферы знаний в награде заказа (02.11, решение Миши).
-- На аукционе их не продать, поэтому цены у них нет. Если у персонажа стоит галка
-- «Сферы» (окно «Знания и заряды», ns.db.roster[guid].wantKP) и общий выключатель
-- включён, считаем сферу как деньги по цене из настроек (окно очереди, строка «Сферы»).
-- ID — из заметки Миши «Моя ферма профессий». У наложения чар таких сфер в заметке нет.
-- -------------------------------------------------------------------------
local PAYOUT_BAG = 246585   -- Оплата Консорциума ремесленников
local KP_ITEMS = {
    [246320] = "glimmer", [246321] = "light",   -- Алхимия: Отблеск / Свет знания
    [246322] = "glimmer", [246323] = "light",   -- Кузнечное дело
    [246326] = "glimmer", [246327] = "light",   -- Инженерное дело
    [246328] = "glimmer", [246329] = "light",   -- Начертание
    [246330] = "glimmer", [246331] = "light",   -- Ювелирное дело
    [246332] = "glimmer", [246333] = "light",   -- Кожевничество
    [246334] = "glimmer", [246335] = "light",   -- Портняжное дело
}
OQ.KP_ITEMS = KP_ITEMS

-- (02.11) Галка «Сферы» — по КАЖДОЙ профессии персонажа (ns.db.roster[guid].wantKP[base] = true).
-- Профессию сферы узнаём по самому предмету (у каждой профессии свои Отблеск/Свет).
local KP_PROF = {
    [246320] = 171, [246321] = 171,   -- Алхимия
    [246322] = 164, [246323] = 164,   -- Кузнечное дело
    [246326] = 202, [246327] = 202,   -- Инженерное дело
    [246328] = 773, [246329] = 773,   -- Начертание
    [246330] = 755, [246331] = 755,   -- Ювелирное дело
    [246332] = 165, [246333] = 165,   -- Кожевничество
    [246334] = 197, [246335] = 197,   -- Портняжное дело
}
OQ.KP_PROF = KP_PROF
local function WantKP(base)
    local g = UnitGUID and UnitGUID("player")
    local re = g and ns.db and ns.db.roster and ns.db.roster[g]
    local w = re and re.wantKP
    if type(w) == "table" then return base and w[base] and true or false end
    return w == true   -- старый формат (одна галка на персонажа)
end
OQ.WantKP = WantKP

-- Сколько золота (в меди) дают сферы заказа сейчас; 0 — если не учитываем.
-- kpCount = { [base] = { glimmer = n, light = n } }
local function KPWorth(kpCount)
    if not kpCount or not next(kpCount) then return 0 end
    local s = DB().settings
    if not s.kpOn then return 0 end
    local sum = 0
    for base, c in pairs(kpCount) do
        if WantKP(base) then
            sum = sum + (c.glimmer or 0) * (s.kpGlimmer or 0) + (c.light or 0) * (s.kpLight or 0)
        end
    end
    return sum
end

-- Пересчитать прибыль заказа с учётом сфер (без нового запроса заказов).
local function ApplyKP(e)
    if not e.profitBase then return end
    e.kpValue = KPWorth(e.kpCount)
    e.profit = e.profitBase + e.kpValue
    e.loss = (e.profit < 0) and -e.profit or 0
end

-- -------------------------------------------------------------------------
-- Сбор данных для анализа (1–2 дня): каждый увиденный заказ + что с ним сделал Миша.
-- RainonUIOrdersDB.seen[orderID] — см. _INDEX/ORDER_QUEUE «Сбор данных».
-- -------------------------------------------------------------------------
local SEEN_MAX = 3000

-- Прибыль ровно по формуле No Mats No Make (PublicOrdersReagentsColumn.lua ~324–368):
-- оплата − доля консорциума + предметы-награды по Auctionator − обязательные реагенты,
-- которых не дал заказчик, по цене ПЕРВОГО (низшего) качества × количество.
-- (Его ручные цены наград по умолчанию 0 — не учитываем.)
local function NmnmProfit(order, sch)
    local profit = (Num(order.tipAmount) or 0) - (Num(order.consortiumCut) or 0)
    for _, rw in ipairs(order.npcOrderRewards or {}) do
        if rw.itemLink and not IsSecret(rw.itemLink) then
            profit = profit + (PriceLink(rw.itemLink) or 0) * (Num(rw.count) or 1)
        end
    end
    local provided = {}
    for _, ri in ipairs(order.reagents or {}) do
        local cr = ri.reagentInfo and ri.reagentInfo.reagent
        if cr and cr.itemID then provided[cr.itemID] = true end
    end
    for _, sl in ipairs((sch and sch.reagentSlotSchematics) or {}) do
        if sl.required then
            local found = false
            for _, r in ipairs(sl.reagents or {}) do if r.itemID and provided[r.itemID] then found = true end end
            local first = sl.reagents and sl.reagents[1]
            if not found and first and first.itemID then
                profit = profit - (Price(first.itemID) or 0) * (sl.quantityRequired or 0)
            end
        end
    end
    return math.floor(profit / 100) * 100
end

local function PlayerKey()
    return (UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName and GetNormalizedRealmName() or "")
end

local function SeenOf(orderID)
    local d = DB()
    d.seen = d.seen or {}
    return d.seen[tostring(orderID)]
end

local seenAdds = 0
local function Observe(order, e)
    local d = DB()
    d.seen = d.seen or {}
    local key = tostring(order.orderID)
    local o = d.seen[key]
    if not o then
        o = { first = time(), recipeID = e.recipeID, name = e.name, who = PlayerKey(), prof = e.prof,
              minQ = e.minQ, tip = Num(order.tipAmount), cut = Num(order.consortiumCut),
              expires = Num(order.expirationTime), rewards = {} }
        for _, rw in ipairs(order.npcOrderRewards or {}) do
            if rw.itemLink and not IsSecret(rw.itemLink) then
                local id = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(rw.itemLink)
                o.rewards[#o.rewards + 1] = { item = id, n = Num(rw.count) or 1, p = PriceLink(rw.itemLink) }
                RememberName(id)
            elseif rw.currencyType then
                o.rewards[#o.rewards + 1] = { cur = rw.currencyType, n = Num(rw.count) or 1 }
            end
        end
        d.seen[key] = o
        seenAdds = seenAdds + 1
        if seenAdds % 200 == 0 then
            local keys = {}
            for k, v in pairs(d.seen) do keys[#keys + 1] = { k = k, t = v.last or v.first or 0 } end
            if #keys > SEEN_MAX then
                table.sort(keys, function(a, b) return a.t < b.t end)
                for i = 1, #keys - SEEN_MAX do d.seen[keys[i].k] = nil end
            end
        end
    end
    o.last = time()
    o.n = (o.n or 0) + 1
    o.ourProfit, o.ourCost, o.noPrice = e.profit, e.ourCost, e.noPrice
    o.nmnm = e.nmnm
    o.kpValue = (e.kpValue and e.kpValue > 0) and e.kpValue or nil   -- сколько добавили за сферы
    o.expQ, o.skill, o.diff = e.expQ, e.skill, e.diff
    o.verdict = e.ok and (e.rule or "ok") or (e.reason or "нет")
    o.need = (e.canCraft == false) or nil
    o.black, o.mark = e.black, e.mark
    o.plan = e.plan
    -- сколько нужных реагентов было в момент выбора (сумки + банк + банк отряда)
    if e.plan then
        o.have = {}
        for id in pairs(e.plan) do o.have[id] = Count(id) end
    end
    -- сколько оставалось времени до конца заказа
    if o.expires and o.expires > 1000000000 then o.left = o.expires - time() end
    -- оценка наград-сумок (Оплата Консорциума) по нашему замеру — ТОЛЬКО записываем, в прибыль не входит
    local bagV = 0
    for _, r in pairs(o.rewards or {}) do
        if r.item == 246585 and OQ.BagValue then
            local v = OQ.BagValue(246585)
            if v then bagV = bagV + v * (r.n or 1) end
        end
    end
    o.payoutValue = (bagV > 0) and math.floor(bagV) or nil
    local nSup = 0
    for _ in pairs(e.supplied or {}) do nSup = nSup + 1 end
    o.supplied = nSup
end

-- Оценить один заказ (без CraftSim): схема → подбор → цена → правила.
local function Evaluate(order, prof, noCount)
    local recipeID = order.spellID
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    local b = LearnRecipe(recipeID, prof)
    if not noCount then
        b.seen = (b.seen or 0) + 1
        b.lastSeen = time()
    end

    local e = {
        orderID = order.orderID, recipeID = recipeID, prof = prof, state = "wait",
        minQ = Num(order.minQuality) or 0,
        name = (info and info.name) or b.name or ("Рецепт " .. tostring(recipeID)),
        icon = (info and info.icon) or b.icon,
        reward = (Num(order.tipAmount) or 0) - (Num(order.consortiumCut) or 0),
        order = order,   -- (02.11) для меню ПКМ в нашем окне («почему не беру», чёрный список)
    }
    -- (02.11) в чёрном списке сам заказанный предмет (рецепт сложно получить и т.п.)
    do
        local outID = Num(order.itemID)
        if outID and DB().black[outID] then e.black, e.blackOut = outID, true end
    end
    if order.isRecraft or order.outputItemGUID then
        e.fatal = "Перековка — пока не поддерживаем"; ApplyRule(e); return e
    end
    if not (info and info.learned) then
        e.fatal = "Рецепт не изучен"; e.notLearned = true
        -- (02.11) прибыль по самым дешёвым реагентам (как No Mats No Make): видно, стоит ли учить рецепт
        local okS, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        local okN, nmP = pcall(NmnmProfit, order, okS and sch or nil)
        e.nmnm = okN and nmP or nil
        ApplyRule(e)
        if not noCount then pcall(Observe, order, e) end
        return e
    end
    do
        local okS, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        e.supplied = SuppliedOf(order, okS and sch or nil).items
        local okN, nm = pcall(NmnmProfit, order, okS and sch or nil)
        e.nmnm = okN and nm or nil
    end
    local m, err = BuildModel(recipeID, order)
    if not m then e.fatal = err; ApplyRule(e); return e end
    e.model = m

    if MarkOf(recipeID) == "yes" and b.manual then
        -- Галочка + запомненный рецепт → ваши реагенты, без подбора.
        ApplyManual(m, b.manual)
        e.manual = true
        local mi = OpInfo(m)
        e.expQ = QualityOf(m, mi)
        e.skill, e.diff = mi and Skill(mi), mi and Num(mi.baseDifficulty)
        if b.manual.conc then e.note = "в памяти крафт с концентрацией — делаем без неё" end
    else
        local res, perr = Plan(m, e.minQ)
        if not res then e.fatal = perr; ApplyRule(e); return e end
        if e.minQ > 0 and res.quality < e.minQ and next(DB().black) then
            -- Без чёрного списка не хватает — а с ним хватило бы? Тогда заказ «Чёрный список».
            allowBanned = true
            local ok2, res2 = pcall(Plan, m, e.minQ)
            allowBanned = false
            if ok2 and res2 and res2.quality >= e.minQ then res = res2 else Plan(m, e.minQ) end
        end
        e.expQ, e.skill, e.diff = res.quality, res.skill, res.diff
        UseOwnBetter(m)
        if m.swapped then
            -- после замены качество может только вырасти — пересчитываем по игре
            local si = OpInfo(m)
            if si then e.expQ, e.skill, e.diff = QualityOf(m, si), Skill(si), Num(si.baseDifficulty) end
            e.swapped = m.swapped
        end
    end

    e.ourCost, e.noPrice, e.plan = Cost(m)
    -- (02.11) Качество достигается дорогими (золотыми) реагентами из нашего подбора? Тогда
    -- окно Blizzard с дешёвыми реагентами по умолчанию покажет «нужна концентрация» —
    -- предупреждаем в подсказке, что делать надо нашей кнопкой «Сделать».
    e.highReagents = nil
    for _, sl in ipairs(m.qslots or {}) do
        for q, n in pairs(sl.alloc or {}) do
            if q > 1 and n > 0 then e.highReagents = true end
        end
    end
    for id in pairs(e.plan) do if DB().black[id] then e.black = id; break end end
    e.rewardIcons = RewardIcons(order)
    -- Награды покровителя (предметы) — по цене Auctionator, как в No Mats No Make.
    e.rewardItems, e.rewardList, e.kpCount = 0, {}, {}
    for _, rw in ipairs(order.npcOrderRewards or {}) do
        if rw.itemLink and not IsSecret(rw.itemLink) then
            local n = Num(rw.count) or 1
            local iid = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(rw.itemLink)
            local kind = iid and KP_ITEMS[iid]
            if kind then
                -- сфера знаний: в цену идёт отдельно (ApplyKP), по настройкам и галке профессии
                local base = KP_PROF[iid]
                e.kpCount[base] = e.kpCount[base] or {}
                e.kpCount[base][kind] = (e.kpCount[base][kind] or 0) + n
                e.rewardList[#e.rewardList + 1] = { link = rw.itemLink, n = n, kp = kind, id = iid, kpBase = base }
            else
                local p = PriceLink(rw.itemLink)
                e.rewardList[#e.rewardList + 1] = { link = rw.itemLink, n = n, p = p, id = iid }
                if p then e.rewardItems = e.rewardItems + p * n end
                -- (02.11) сумка за заказы: в прибыль НЕ входит, показываем рядом отдельно
                if iid == PAYOUT_BAG then e.bagN = (e.bagN or 0) + n end
            end
        elseif rw.currencyType then
            e.rewardList[#e.rewardList + 1] = { currency = rw.currencyType, n = Num(rw.count) or 1 }
        end
    end
    e.profitBase = e.reward + e.rewardItems - e.ourCost   -- без сфер
    ApplyKP(e)                                             -- + сферы, если учитываем
    ApplyRule(e)
    if not noCount then pcall(Observe, order, e) end
    return e
end

local function SortEntries()
    local rank = { check = 1, general = 2 }
    for i, e in ipairs(entries) do e.idx = i end
    table.sort(entries, function(a, b)
        -- (04.11, Миша) чёрный список — в самом низу
        local ra = a.black and 10 or (a.ok and (rank[a.rule] or 3) or 9)
        local rb = b.black and 10 or (b.ok and (rank[b.rule] or 3) or 9)
        if ra ~= rb then return ra < rb end
        return a.idx < b.idx
    end)
end

local function BuildEntries(orders, prof)
    local old = {}
    for _, e in ipairs(entries) do old[tostring(e.orderID)] = e end
    local present = {}
    for _, o in ipairs(orders) do present[tostring(o.orderID)] = true end
    -- Заказы, которые пропали из списка, не взяв их, — «ушли» (для анализа выбора).
    for k, e in pairs(old) do
        if not present[k] and e.state == "wait" then
            local o = SeenOf(k)
            if o and not o.done and not o.crafted then o.gone = o.gone or time() end
        end
    end
    entries = {}
    local i = 0
    local function nextOne()
        i = i + 1
        local order = orders[i]
        if not order then
            scanning = false
            lastScanAt = GetTime()
            if profSession then
                for _, e in ipairs(entries) do profSession.ids[tostring(e.orderID)] = true end
                profSession.prof = profSession.prof or prof
            end
            SortEntries()
            local okN = 0
            for _, e in ipairs(entries) do if e.ok then okN = okN + 1 end end
            Trace("scan", { prof = prof, n = #entries, ok = okN })
            Status(("Заказов: %d · к работе: %d"):format(#entries, okN)
                .. (HasPrices() and "" or " · цен нет (Auctionator выключен)"))
            Refresh()
            return
        end
        Status(("Считаю %d из %d…"):format(i, #orders))
        local ok, e = pcall(Evaluate, order, prof)
        if ok and e then
            local was = old[tostring(order.orderID)]
            local cl = C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
            local isClaimed = cl and SameID(cl.orderID, order.orderID)
            if was and isClaimed then
                -- взятый сейчас заказ: помним, что уже сделали/сдаём
                e.crafted, e.fulfilling = was.crafted, was.fulfilling
                if was.state ~= "wait" then e.state = was.state end
            elseif was and (was.state ~= "wait" or was.crafted or was.fulfilling) then
                -- (02.11) игра снова показывает заказ в списке → он НЕ сдан: возвращаем в работу.
                -- Раньше старое «сдан» переносилось, и после «Обновить» заказ пропадал из очереди.
                fulfillSent[tostring(order.orderID)] = nil
                Trace("revive", { oid = tostring(order.orderID), name = e.name, was = was.state,
                    crafted = was.crafted, fulfilling = was.fulfilling })
            end
        end
        if not ok then
            e = { orderID = order.orderID, recipeID = order.spellID, prof = prof, state = "wait",
                  minQ = 0, name = "Рецепт " .. tostring(order.spellID), fatal = "Ошибка расчёта: " .. tostring(e) }
            ApplyRule(e)
        end
        entries[#entries + 1] = e
        C_Timer.After(0, nextOne)   -- по одному за кадр, чтобы не подвисало
    end
    nextOne()
end

-- Цены сфер / галка персонажа изменились — пересчитать уже найденные заказы.
function OQ.RescoreKP()
    for _, e in ipairs(entries) do
        if e.profitBase then ApplyKP(e); ApplyRule(e) end
    end
    SortEntries()
    if Refresh then Refresh() end
end

-- Запрос заказов (с повтором, если игра просит «не так часто»).
local function RequestOrders(request, onResult, tries)
    request.callback = C_FunctionContainers.CreateCallback(function(result)
        local R = Enum.CraftingOrderResult or {}
        if (result == R.ThrottleViolation or result == R.Timeout) and tries > 0 then
            C_Timer.After(1.5, function() RequestOrders(request, onResult, tries - 1) end)
            return
        end
        onResult(result)
    end)
    local ok = pcall(C_CraftingOrders.RequestCrafterOrders, request)
    if not ok then onResult(-1) end
end

-- Заказы уже загружены игрой (вкладка «Patron» сама их запрашивает) — берём готовые,
-- без своего запроса. Как CraftSim: обновляемся сразу при открытии вкладки.
function OQ.ScanCached()
    if scanning or InCombatLockdown() then return end
    local prof = Profession()
    if not prof then return end
    local orders, seen = {}, {}
    for _, o in ipairs(C_CraftingOrders.GetCrafterOrders() or {}) do
        if o.orderType == Enum.CraftingOrderType.Npc then
            orders[#orders + 1] = o; seen[tostring(o.orderID)] = true
        end
    end
    local claimed = C_CraftingOrders.GetClaimedOrder()
    if claimed and claimed.orderType == Enum.CraftingOrderType.Npc and not seen[tostring(claimed.orderID)] then
        table.insert(orders, 1, claimed)
    end
    if #orders == 0 then return end
    scanning = true
    scanProf = prof
    BuildEntries(orders, prof)
end

function OQ.Scan(quiet)
    if scanning then return end
    if InCombatLockdown() then return end
    local prof = Profession()
    if not prof then if not quiet then ns.Print("Очередь заказов: откройте окно профессии.") end; return end
    scanning = true
    scanProf = prof
    offset = 0
    Status("Ищу заказы покровителей…")
    Refresh()

    local request = {
        orderType = Enum.CraftingOrderType.Npc,
        searchFavorites = false,
        initialNonPublicSearch = false,
        primarySort = { sortType = Enum.CraftingOrderSortType.ItemName, reversed = false },
        secondarySort = { sortType = Enum.CraftingOrderSortType.MaxTip, reversed = false },
        forCrafter = true,
        offset = 0,
        profession = prof,
    }
    RequestOrders(request, function(result)
        if result ~= Enum.CraftingOrderResult.Ok then
            scanning = false
            Status("Заказы не загрузились (код " .. tostring(result) .. "). Подойдите к столу заказов и повторите.")
            Refresh()
            return
        end
        local orders, seen = {}, {}
        for _, o in ipairs(C_CraftingOrders.GetCrafterOrders() or {}) do
            if o.orderType == Enum.CraftingOrderType.Npc then
                orders[#orders + 1] = o; seen[tostring(o.orderID)] = true
            end
        end
        local claimed = C_CraftingOrders.GetClaimedOrder()
        if claimed and claimed.orderType == Enum.CraftingOrderType.Npc and not seen[tostring(claimed.orderID)] then
            table.insert(orders, 1, claimed)
        end
        BuildEntries(orders, prof)
    end, 3)
end

-- -------------------------------------------------------------------------
-- Журнал
-- -------------------------------------------------------------------------
-- -------------------------------------------------------------------------
-- (02.11) ПОДРОБНЫЙ СЛЕД для дня проверки (Миша делает много заказов только нашими кнопками).
-- RainonUIOrdersDB.trace = { {t, gt, who, step, oid, name, ...}, ... } (≤ TRACE_MAX).
-- Шаги: press (нажатие «Дальше» + текст кнопки), claim_resp, craft_start, craft_result,
-- craft_fail, craft_close, fulfill_send, fulfill_resp, ui_error, scan.
-- Потом по этим данным решим, какие записи оставить для работы, остальное уберём.
-- -------------------------------------------------------------------------
Trace = function(step, data)
    local d = DB()
    d.trace = d.trace or {}
    local r = data or {}
    r.t, r.gt, r.step = time(), math.floor((GetTime() or 0) * 100) / 100, step
    r.who = r.who or ((UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName and GetNormalizedRealmName() or ""))
    d.trace[#d.trace + 1] = r
    if #d.trace > TRACE_MAX then table.remove(d.trace, 1) end
    return r
end
OQ.Trace = Trace

-- Сколько есть валюты (для проверки наград-валют при сдаче).
local function CurrencyQty(id)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    return ok and type(info) == "table" and Num(info.quantity) or nil
end

-- Снимок наград заказа ДО сдачи: деньги + предметы + валюты.
local function RewardSnapshot(e)
    local snap = { money = GetMoney(), items = {}, cur = {} }
    for _, rw in ipairs((e and e.rewardList) or {}) do
        if rw.id then snap.items[rw.id] = Count(rw.id)
        elseif rw.currency then snap.cur[rw.currency] = CurrencyQty(rw.currency) end
    end
    return snap
end

local BAG_ICON
local function BagIcon()
    if not BAG_ICON then
        local ic = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(PAYOUT_BAG)
        BAG_ICON = "|T" .. tostring(ic or 134400) .. ":14:14:0:0|t"
    end
    return BAG_ICON
end

local function AddLog(en)
    local log = DB().log
    log[#log + 1] = en
    while #log > LOG_MAX do table.remove(log, 1) end
    return en
end

local function NewLogEntry(kind, recipeID, name)
    return {
        t = time(), kind = kind,
        who = (UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName and GetNormalizedRealmName() or ""),
        recipeID = recipeID, name = name,
    }
end

local function Snapshot(plan)
    local before = {}
    for id in pairs(plan or {}) do before[id] = Count(id) end
    return before
end

-- Через пару секунд после результата: что реально ушло из сумок + флаги.
local function CloseCraft()
    local c = current
    if not c then return end
    current = nil
    local en = c.log
    local consumed, spent, miss = {}, 0, 0
    for id, b in pairs(c.before or {}) do
        local used = b - Count(id)
        if used > 0 then
            consumed[id] = used
            local p = en.prices and en.prices[id]
            if p then spent = spent + p * used else miss = miss + 1 end
        end
    end
    if c.noSnap then
        en.realSpent = nil   -- крафт в окне Blizzard без снимка сумок: реальный расход неизвестен
    else
        en.consumed, en.realSpent, en.realNoPrice = consumed, spent, miss
    end

    local flags = {}
    if not c.noSnap and en.ourCost and spent > en.ourCost * 1.1 + GOLD then
        flags[#flags + 1] = "потрачено больше плана"
    end
    for id, n in pairs(c.noSnap and {} or consumed) do
        if not (en.reagents and en.reagents[id]) then
            flags[#flags + 1] = "ушёл реагент не из плана (" .. tostring(id) .. " x" .. n .. ")"
        elseif n > en.reagents[id] then
            flags[#flags + 1] = "реагента ушло больше плана (" .. tostring(id) .. ": " .. n .. " > " .. en.reagents[id] .. ")"
        end
    end
    if en.gotQ and en.minQ and en.minQ > 0 and en.gotQ < en.minQ then
        flags[#flags + 1] = "качество ниже нужного заказу"
    elseif en.gotQ and en.expQ and en.gotQ < en.expQ then
        flags[#flags + 1] = "качество ниже расчёта"
    end
    if (en.noPrice or 0) > 0 then flags[#flags + 1] = "нет цены у части реагентов" end
    if en.kind == "queue" and (en.concSpent or 0) > 0 then flags[#flags + 1] = "потрачена концентрация (не должна!)" end
    en.flags = (#flags > 0) and flags or nil
    en.dur = c.started and math.floor((GetTime() - c.started) * 10) / 10 or nil
    Trace("craft_close", { oid = en.orderID, name = en.name, gotQ = en.gotQ, concSpent = en.concSpent,
        consumed = en.consumed, realSpent = en.realSpent, flags = en.flags, dur = en.dur })

    if c.e then c.e.crafting = false end
    if Refresh then Refresh() end
end

local function StartCraftLog(e, kind, recipeID, name, plan, extra)
    local en = NewLogEntry(kind, recipeID, name)
    for k, v in pairs(extra or {}) do en[k] = v end
    if en.orderID then
        local o = SeenOf(en.orderID)
        if o then o.crafted = o.crafted or time(); o.craftKind = kind end
    end
    en.reagents = plan
    en.av = 2
    -- (02.11) подробно: цены реагентов в момент крафта, деньги, точное время
    en.prices = {}
    for id in pairs(plan or {}) do en.prices[id] = Price(id); RememberName(id) end
    en.money0, en.gt0 = GetMoney(), GetTime()
    if e and e.bagN then en.bagN = e.bagN end
    if e and e.kpValue and e.kpValue > 0 then en.kpValue = e.kpValue end
    AddLog(en)
    Trace("craft_start", { oid = en.orderID, name = name, kind = kind, minQ = en.minQ, expQ = en.expQ,
        skill = en.skill, diff = en.diff, plan = plan, ourCost = en.ourCost, profit = en.profit })
    current = { e = e, log = en, before = Snapshot(plan), started = GetTime() }
    -- Страховка: если результат не пришёл (прервали) — закрываем через 20с.
    local mine = current
    C_Timer.After(20, function() if current == mine then CloseCraft() end end)
end

-- Сделать текущий заказ (по нажатию «Дальше»).
local function DoCraft(e)
    if not e or not e.model or current then return end
    e.crafting = true
    StartCraftLog(e, "queue", e.recipeID, e.name, e.plan, {
        orderID = tostring(e.orderID), rule = e.rule, manual = e.manual,
        minQ = e.minQ, expQ = e.expQ, skill = e.skill, diff = e.diff,
        ourCost = e.ourCost, noPrice = e.noPrice, reward = e.reward, rewardItems = e.rewardItems, profit = e.profit,
    })
    ourCraft = true
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, e.recipeID, 1, ReagentTbl(e.model), nil, e.orderID, false)
    ourCraft = false
    if not ok then
        e.crafting = false
        current.log.error = tostring(err)
        current = nil
        ns.Print("Очередь заказов: крафт не начался — " .. tostring(err))
    end
    Refresh()
end

-- Ручной крафт (не из очереди): при включённой записи — в «мозги» и в журнал.
local function OnManualCraft(recipeID, amount, reagents, _, orderID, concentrating)
    if ourCraft then return end
    if IsSecret(recipeID) then return end
    -- Заказ из нашего списка (сделан в окне Blizzard) — пишем в журнал ВСЕГДА, с оплатой и наградами.
    local e = orderID and not IsSecret(orderID) and FindEntry(orderID)
    -- (02.11) ⚠ КОРЕНЬ «зависаний»: крафт без предмета (Раскалывание сущности — это бафф) не присылает
    -- «результат крафта», наш журнал держал «идёт крафт», и очередь показывала «Делаю…» до сторожа (10 с).
    -- Пойман по следу: Zulrain 15:33 и Nevaknight 15:41 — кнопка раскалывания, сразу за ней «Взять».
    -- Крафты, у которых в схеме нет предмета на выходе, не пишем и не запоминаем.
    if not e then
        local okS, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        local out = okS and type(sch) == "table" and Num(sch.outputItemID)
        if not out or out == 0 then return end
    end
    local remember = ns.ProfEnabled() and DB().settings.remember
    if remember then RememberManual(recipeID, reagents, concentrating, orderID) end
    if not (remember or e) or current then return end
    local sup = e and e.supplied or {}
    local plan, sum, noPrice = {}, 0, 0
    local function add(id, n)
        if not id or n <= 0 or sup[id] then return end
        plan[id] = (plan[id] or 0) + n
        local p = Price(id)
        if p then sum = sum + p * n else noPrice = noPrice + 1 end
    end
    for _, r in ipairs(reagents or {}) do
        local id, cur, qty = RInfo(r)
        if id and not cur and qty and qty > 0 then add(id, qty * (amount or 1)) end
    end
    -- простые реагенты (без качества) игра кладёт сама — добираем из модели заказа
    for _, f in ipairs((e and e.model and e.model.fixed) or {}) do
        if not plan[f.itemID] then add(f.itemID, f.qty) end
    end
    local b = DB().recipes[recipeID] or {}
    local extra = {
        orderID = orderID and tostring(orderID) or nil, conc = concentrating and true or false,
        ourCost = sum, noPrice = noPrice, amount = amount,
    }
    if e then
        e.crafted = true
        extra.minQ, extra.expQ = e.minQ, e.expQ
        extra.reward, extra.rewardItems = e.reward, e.rewardItems
        extra.profit = (e.reward or 0) + (e.rewardItems or 0) - sum
        extra.rule = e.rule
    end
    StartCraftLog(e or nil, "manual", recipeID, b.name or (e and e.name), plan, extra)
    if Refresh then Refresh() end
end

-- -------------------------------------------------------------------------
-- Кнопка «Дальше»: что сейчас делать с верхним заказом
-- -------------------------------------------------------------------------
FindEntry = function(orderID)
    for _, e in ipairs(entries) do if SameID(e.orderID, orderID) then return e end end
end

local function MarkDone(e)
    if not e or e.state ~= "wait" then return end
    local o = SeenOf(e.orderID)
    if o then o.done = o.done or time() end
    e.state = "done"
    e.fulfilling = false
    local log = DB().log
    for i = #log, 1, -1 do
        if SameID(log[i].orderID, e.orderID) then log[i].fulfilled = true; break end
    end
end

local function CurrentEntry()
    local claimed = C_CraftingOrders and C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
    if claimed then
        local e = FindEntry(claimed.orderID)
        if e and e.state == "wait" then return e, claimed end
    end
    for _, e in ipairs(entries) do
        if e.ok and e.state == "wait" then
            -- Уже сдавали / сделали, а заказ больше не взят — значит, он закрыт.
            if (e.fulfilling or fulfillSent[tostring(e.orderID)] or e.crafted) and not claimed then
                MarkDone(e)
            elseif e.canCraft ~= false then
                return e, claimed
            end
        end
    end
    return nil, claimed
end

-- Сверка со списком игры: заказы, которых больше нет, убираем (сданы/истекли).
local syncing = false
local function SyncPresence()
    if syncing or scanning or not scanProf then return end
    syncing = true
    local request = {
        orderType = Enum.CraftingOrderType.Npc, searchFavorites = false, initialNonPublicSearch = false,
        primarySort = { sortType = Enum.CraftingOrderSortType.ItemName, reversed = false },
        secondarySort = { sortType = Enum.CraftingOrderSortType.MaxTip, reversed = false },
        forCrafter = true, offset = 0, profession = scanProf,
    }
    RequestOrders(request, function(result)
        syncing = false
        if result ~= Enum.CraftingOrderResult.Ok then return end
        local present = {}
        for _, o in ipairs(C_CraftingOrders.GetCrafterOrders() or {}) do present[tostring(o.orderID)] = true end
        local claimed = C_CraftingOrders.GetClaimedOrder()
        if claimed then present[tostring(claimed.orderID)] = true end
        for _, e in ipairs(entries) do
            if e.state == "wait" and not present[tostring(e.orderID)] then
                if e.crafted or e.fulfilling or fulfillSent[tostring(e.orderID)] then MarkDone(e) else e.state = "gone" end
            end
        end
        if Refresh then Refresh() end
    end, 2)
end

-- Сам сдать сделанный заказ (как «Skip Complete Order»).
local function AutoFulfill()
    if not (autoChain and DB().settings.skipComplete) then return end
    if InCombatLockdown() then return end
    local claimed = C_CraftingOrders.GetClaimedOrder()
    if not (claimed and claimed.isFulfillable) then return end
    local e = FindEntry(claimed.orderID)
    local key = tostring(claimed.orderID)
    if not e or e.state ~= "wait" or fulfillSent[key] then return end
    fulfillSent[key] = true
    e.fulfilling = true
    e.rsnap = RewardSnapshot(e)
    Trace("fulfill_send", { oid = tostring(e.orderID), name = e.name, auto = true, reward = e.reward })
    C_CraftingOrders.FulfillOrder(claimed.orderID, "", e.prof)
end

-- Возвращает: текст, активна ли, действие.
local function NextAction()
    if InCombatLockdown() then return "В бою", false end
    if scanning then return "Считаю…", false end
    if GetTime() < pauseUntil then return "Подожди секунду…", false end
    if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then return "Откройте окно профессии у стола заказов", false end
    local e, claimed = CurrentEntry()
    if not e then
        if claimed then return "Взят чужой заказ — завершите его", false end
        return (#entries > 0) and "Нет подходящих заказов" or "Нажмите «Обновить»", false
    end
    local prof = e.prof
    if C_TradeSkillUI.IsNearProfessionSpellFocus and not C_TradeSkillUI.IsNearProfessionSpellFocus(prof) then
        return "Подойдите к столу заказов", false
    end
    if not claimed then
        return "Взять: " .. e.name, true, function()
            C_CraftingOrders.ClaimOrder(e.orderID, prof)
            e.claiming = true
        end
    end
    if not SameID(claimed.orderID, e.orderID) then
        return "Взят другой заказ — завершите его", false
    end
    if not e.ok then
        return "Этот заказ не проходит: " .. (e.reason or "?"), false
    end
    if claimed.isFulfillable then
        if fulfillSent[tostring(e.orderID)] then return "Сдаю…", false end
        return "Сдать: " .. e.name, true, function()
            e.fulfilling = true
            fulfillSent[tostring(e.orderID)] = true
            e.rsnap = RewardSnapshot(e)
            Trace("fulfill_send", { oid = tostring(e.orderID), name = e.name, reward = e.reward })
            C_CraftingOrders.FulfillOrder(e.orderID, "", prof)
        end
    end
    if e.crafting or current then return "Делаю…", false end
    if not CanCraftPlan(e.plan) then return "Не хватает реагентов: " .. e.name, false end
    if not CurrencyOK(e.model) then return "Не хватает валюты: " .. e.name, false end
    return "Сделать: " .. e.name, true, function() DoCraft(e) end
end

-- -------------------------------------------------------------------------
-- Окно
-- -------------------------------------------------------------------------
local QCOL = { [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
-- (02.11) Значок качества как в игре (ромбик), а не текст «кач.N». Атлас берём у самой игры:
-- по предмету (C_TradeSkillUI.GetItemReagentQualityInfo / GetItemCraftedQualityInfo) или по
-- рецепту (GetRecipeItemQualityInfo) — поле iconChat/iconSmall. Найденный атлас запоминаем
-- по номеру качества; если игра ничего не дала — запасной текст «кач.N».
local qAtlasCraft, qAtlasReag, qItemCache = {}, {}, {}
local function AtlasOf(info)
    if type(info) ~= "table" then return nil end
    local a = info.iconChat or info.iconSmall or info.icon
    if type(a) == "string" and a ~= "" and not IsSecret(a) then return a end
end
local function QAtlas(n, recipeID, itemID)
    local TS = C_TradeSkillUI
    if itemID and TS then
        local c = qItemCache[itemID]
        if c == nil then
            c = false
            for _, fn in ipairs({ "GetItemReagentQualityInfo", "GetItemCraftedQualityInfo" }) do
                if TS[fn] then
                    local ok, info = pcall(TS[fn], itemID)
                    local a = ok and AtlasOf(info)
                    if a then
                        c = a
                        local q = Num(info.quality) or n
                        if q then if fn == "GetItemReagentQualityInfo" then qAtlasReag[q] = a else qAtlasCraft[q] = a end end
                        break
                    end
                end
            end
            qItemCache[itemID] = c
        end
        if c then return c end
        if qAtlasReag[n] then return qAtlasReag[n] end
    end
    if recipeID and TS and TS.GetRecipeItemQualityInfo then
        local ok, info = pcall(TS.GetRecipeItemQualityInfo, recipeID, n)
        local a = ok and AtlasOf(info)
        if a then qAtlasCraft[n] = a; return a end
    end
    return qAtlasCraft[n] or qAtlasReag[n]
end
local function Q(n, recipeID, itemID)
    if not n or n <= 0 then return "" end
    local a = QAtlas(n, recipeID, itemID)
    if a and CreateAtlasMarkup then
        local ok, mk = pcall(CreateAtlasMarkup, a, 16, 16)
        if ok and mk then return mk end
    end
    return ns.C(QCOL[n] or "ffffff", "кач." .. n)
end

local function SetMark(btn, mark, minQ)
    btn.tex:Hide(); btn.txt:SetText("")
    if btn.q then btn.q:Hide() end
    if mark == "yes" then
        if pcall(btn.tex.SetAtlas, btn.tex, "common-icon-checkmark") then btn.tex:Show() else btn.txt:SetText(ns.C("1eff00", "V")) end
    elseif mark == "no" then
        if pcall(btn.tex.SetAtlas, btn.tex, "common-icon-redx") then btn.tex:Show() else btn.txt:SetText(ns.C("ff3333", "X")) end
    else
        -- (04.11) у заказа с требуемым качеством вместо точки — значок качества (как в игре)
        if btn.q and minQ and minQ > 0 and pcall(btn.q.SetAtlas, btn.q, "Professions-ChatIcon-Quality-12-Tier" .. minQ) then
            btn.q:Show()
        else
            btn.txt:SetText(ns.C("808080", "·"))
        end
    end
end

local function CycleMark(recipeID)
    local b = Brain(recipeID)
    if b.mark == nil then b.mark = "yes" elseif b.mark == "yes" then b.mark = "no" else b.mark = nil end
    for _, e in ipairs(entries) do if e.recipeID == recipeID then ApplyRule(e) end end
    if b.mark == "yes" and b.manual then
        ns.Print("Очередь заказов: у рецепта есть запомненные реагенты — нажмите «Обновить», чтобы пересчитать по ним.")
    end
    Refresh()
end

local function MarkTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Отметка рецепта")
    GameTooltip:AddLine("Клик: нет → галочка → крестик → нет.", 1, 1, 1, true)
    GameTooltip:AddLine(ns.C("1eff00", "Галочка") .. " — брать всегда, порог убытка не действует; " ..
        "если рецепт запомнен — ваши реагенты.", 1, 1, 1, true)
    GameTooltip:AddLine(ns.C("ff3333", "Крестик") .. " — никогда не брать.", 1, 1, 1, true)
    GameTooltip:Show()
end

local function EntryTooltip(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name)
    if e.ok then
        GameTooltip:AddLine(e.rule == "check" and ns.C("1eff00", "Берём по галочке") or "Берём по общим условиям", 1, 1, 1)
    else
        GameTooltip:AddLine(ns.C("ff6060", e.reason or "Не проходит"), 1, 1, 1, true)
    end
    if e.notLearned and e.nmnm then
        GameTooltip:AddLine(("Если выучить: прибыль ~%s%s (оценка по самым дешёвым реагентам, без учёта нужного качества)."):format(
            e.nmnm < 0 and "-" or "+", Gold(math.abs(e.nmnm))), 1, 0.82, 0, true)
    end
    if e.minQ > 0 then GameTooltip:AddDoubleLine("Нужно качество", Q(e.minQ, e.recipeID), 1, 1, 1) end
    if e.expQ then GameTooltip:AddDoubleLine("Выйдет (по талантам)", Q(e.expQ, e.recipeID), 1, 1, 1) end
    if e.skill and e.diff then
        GameTooltip:AddDoubleLine("Навык / сложность", ("%d / %d (макс. кач.%d)"):format(e.skill, e.diff, e.model and e.model.maxQ or 0),
            1, 1, 1, 0.7, 0.7, 0.7)
    end
    if e.note then GameTooltip:AddLine(e.note, 1, 0.6, 0.2, true) end
    if e.highReagents and e.ok and not e.manual then
        GameTooltip:AddLine("Качество выходит за счёт золотых реагентов из нашего подбора (список ниже). " ..
            "В окне Blizzard по умолчанию стоят дешёвые — там игра попросит концентрацию. " ..
            "Делай кнопкой «Сделать» в очереди: она кладёт наши реагенты, без концентрации.", 1, 0.82, 0, true)
    end
    if e.manual then GameTooltip:AddLine("Реагенты: запомненные ваши", 0.6, 0.8, 1) end
    for _, sw in ipairs(e.swapped or {}) do
        GameTooltip:AddLine(("Своё лучшее качество: %s x%d вместо покупного (доплата %s)"):format(
            ItemName(sw.to), sw.n, Gold(sw.extra)), 0.6, 0.8, 1, true)
    end
    if e.model then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Реагенты (наш подбор):", 1, 0.82, 0)
        -- (04.11, Миша) реагенты — от дорогих к дешёвым (без цены — в конце)
        local rlist = {}
        for id, n in pairs(e.plan or {}) do local p = Price(id); rlist[#rlist + 1] = { id = id, n = n, v = p and p * n or -1 } end
        table.sort(rlist, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.id < b.id end)
        for _, rr in ipairs(rlist) do
            local id, n = rr.id, rr.n
            local nm = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
            local rq = C_TradeSkillUI.GetItemReagentQualityByItemInfo
            local okQ, qq = false, nil
            if rq then okQ, qq = pcall(rq, id) end
            if okQ and Num(qq) then nm = (nm or ("предмет " .. id)) .. " " .. Q(Num(qq), nil, id) end
            local p = Price(id)
            GameTooltip:AddDoubleLine((nm or ("предмет " .. id)) .. " x" .. n,
                p and Gold(p * n) or ns.C("ff6060", "нет цены"), 1, 1, 1, 1, 1, 1)
        end
        for _, c in ipairs(e.model.cur or {}) do
            local cn, have = CurName(c.currencyID)
            GameTooltip:AddDoubleLine(cn .. " x" .. c.qty, ns.C(have >= c.qty and "a0a0a0" or "ff6060",
                "валюта, есть " .. have), 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Цена реагентов", Gold(e.ourCost) ..
            (((e.noPrice or 0) > 0) and ns.C("ff6060", " (без цены: " .. e.noPrice .. ")") or ""), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Оплата заказа", Gold(e.reward), 1, 1, 1, 1, 1, 1)
        -- (04.11, Миша) награды — от дорогих к дешёвым; сумку не сортируем (она в конце)
        local rws = {}
        for i, rw in ipairs(e.rewardList or {}) do
            local v = (rw.id == PAYOUT_BAG and not rw.p) and -2
                or (rw.kp and KPWorth({ [rw.kpBase or 0] = { [rw.kp] = 1 } }) * rw.n)
                or (rw.p and rw.p * rw.n) or -1
            rws[#rws + 1] = { rw = rw, v = v, i = i }
        end
        table.sort(rws, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.i < b.i end)
        for _, x in ipairs(rws) do
            local rw = x.rw
            if rw.link and rw.kp then
                local per = KPWorth({ [rw.kpBase or 0] = { [rw.kp] = 1 } })
                GameTooltip:AddDoubleLine("Награда: " .. rw.link .. " x" .. rw.n,
                    per > 0 and (Gold(per * rw.n) .. " (сфера)") or ns.C("808080", "сфера не учитывается"), 1, 1, 1, 1, 1, 1)
            elseif rw.link and rw.id == PAYOUT_BAG and not rw.p then
                local bv = OQ.BagValue(PAYOUT_BAG)
                GameTooltip:AddDoubleLine("Награда: " .. rw.link .. " x" .. rw.n,
                    bv and ns.C("ffd100", "~" .. Gold(bv * rw.n) .. " (замер, не в прибыли)") or ns.C("ff6060", "нет замеров"), 1, 1, 1, 1, 1, 1)
            elseif rw.link then
                GameTooltip:AddDoubleLine("Награда: " .. rw.link .. " x" .. rw.n,
                    rw.p and Gold(rw.p * rw.n) or ns.C("ff6060", "нет цены"), 1, 1, 1, 1, 1, 1)
            else
                local ci = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(rw.currency)
                GameTooltip:AddDoubleLine("Награда: " .. ((ci and ci.name) or ("валюта " .. tostring(rw.currency))) .. " x" .. rw.n,
                    ns.C("808080", "не в золоте"), 1, 1, 1, 1, 1, 1)
            end
        end
        if e.profit then
            GameTooltip:AddDoubleLine(e.profit < 0 and "Убыток" or "Прибыль", Gold(math.abs(e.profit)),
                1, 1, 1, e.profit < 0 and 1 or 0.3, e.profit < 0 and 0.4 or 1, 0.3)
        end
    end
    if e.needText then GameTooltip:AddLine(ns.C("ff9900", e.needText), 1, 1, 1, true) end
    GameTooltip:Show()
end

local function LogTooltip(self)
    local en = self.logEntry
    if not en then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine((en.name or ("Рецепт " .. tostring(en.recipeID))))
    GameTooltip:AddLine(date("%d.%m %H:%M", en.t) .. " · " .. ((en.kind == "manual" and "вручную") or (en.kind == "blizzard" and "в окне Blizzard") or "из очереди") ..
        " · " .. (en.who or ""), 0.7, 0.7, 0.7)
    if en.minQ and en.minQ > 0 then GameTooltip:AddDoubleLine("Нужно", Q(en.minQ, en.recipeID), 1, 1, 1) end
    if en.expQ then GameTooltip:AddDoubleLine("Расчёт", Q(en.expQ, en.recipeID), 1, 1, 1) end
    if en.gotQ then GameTooltip:AddDoubleLine("Вышло", Q(en.gotQ, en.recipeID), 1, 1, 1) end
    if (en.concSpent or 0) > 0 then GameTooltip:AddDoubleLine("Концентрация потрачена", tostring(en.concSpent), 1, 0.4, 0.4) end
    if en.ourCost then GameTooltip:AddDoubleLine("План (цена реагентов)", Gold(en.ourCost), 1, 1, 1, 1, 1, 1) end
    if en.realSpent then GameTooltip:AddDoubleLine("Реально ушло из сумок", Gold(en.realSpent), 1, 1, 1, 1, 1, 1) end
    if en.reward then GameTooltip:AddDoubleLine("Оплата заказа", Gold(en.reward), 1, 1, 1, 1, 1, 1) end
    if en.resourceful then GameTooltip:AddLine("Сработала экономия реагентов", 0.6, 0.8, 1) end
    if en.fulfilled then GameTooltip:AddLine(ns.C("1eff00", "Заказ сдан")) end
    if en.error then GameTooltip:AddLine(ns.C("ff6060", "Ошибка: " .. en.error), 1, 1, 1, true) end
    for _, f in ipairs(en.flags or {}) do GameTooltip:AddLine(ns.C("ff9900", "⚠ " .. f), 1, 1, 1, true) end
    GameTooltip:Show()
end

-- (02.11) Сократить название до NAME_MAX букв (UTF-8): одинаковая длина — ровная колонка.
local function Short(text, limit)
    if type(text) ~= "string" then return text end
    limit = limit or NAME_MAX
    local n, cut = 0, nil
    for pos in text:gmatch("()[^\128-\191]") do
        n = n + 1
        if n == limit then cut = pos end
        if n > limit then return (text:sub(1, cut - 1):gsub("%s+$", "")) .. "…" end
    end
    return text
end
OQ.ShortItemName = Short

-- (02.11) Шрифт строк: как GameFontHighlightSmall, но на FONT_ADD крупнее.
local rowFont
local function RowFont()
    if rowFont then return rowFont end
    rowFont = CreateFont("RainonUIOrderQueueRowFont")
    rowFont:CopyFontObject(GameFontHighlightSmall)
    local file, size, flags = GameFontHighlightSmall:GetFont()
    if file and size then rowFont:SetFont(file, size + FONT_ADD, flags or "") end
    return rowFont
end

local function NewRow(parent, i, listW)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(listW, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)

    r.mark = CreateFrame("Button", nil, r)
    r.mark:SetSize(18, 18)
    r.mark:SetPoint("LEFT", 4, 0)
    r.mark.tex = r.mark:CreateTexture(nil, "ARTWORK")
    r.mark.tex:SetAllPoints()
    r.mark.txt = r.mark:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.mark.txt:SetPoint("CENTER")
    -- (04.11, Миша) значок требуемого качества — на месте серой точки (центр значка = центр точки)
    r.mark.q = r.mark:CreateTexture(nil, "ARTWORK")
    r.mark.q:SetSize(16, 16)
    r.mark.q:SetPoint("CENTER")
    r.mark.q:Hide()
    r.mark:SetScript("OnEnter", MarkTooltip)
    r.mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.mark:SetScript("OnClick", function(self)
        local row = self:GetParent()
        if row.watchID then
            DB().watch[row.watchID] = nil
            ns.Print("Очередь заказов: " .. ItemName(row.watchID) .. " — больше не следим за проками (записанное остаётся).")
            Refresh()
        elseif row.blackID then
            DB().black[row.blackID] = nil
            for _, e in ipairs(entries) do if e.black == row.blackID then e.black = nil; ApplyRule(e) end end
            ns.Print("Очередь заказов: убрано из чёрного списка — нажмите «Обновить» для пересчёта.")
            Refresh()
        elseif row.recipeID then CycleMark(row.recipeID) end
    end)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", r.mark, "RIGHT", 4, 0)

    r.info = r:CreateFontString(nil, "OVERLAY")
    r.info:SetFontObject(RowFont())
    r.info:SetPoint("RIGHT", -6, 0)
    r.info:SetJustifyH("RIGHT")
    r.info:SetWordWrap(false)

    -- (02.11) название — до NAME_MAX букв (Short), колонка одной ширины → правая часть ровная
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFontObject(RowFont())
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.info, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)

    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- (02.11) ПКМ по заказу в НАШЕМ окне — «почему не беру» и чёрный список (в окно Blizzard больше не лезем)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
        local e = self.entry
        if button ~= "RightButton" or not (e and e.order) or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(_, root) if OQ.OrderMenu then OQ.OrderMenu(root, e.order) end end)
    end)
    return r
end

-- (02.11) Строка «Оплата Консорциума» в окне очереди.
local function UpdateBagRow()
    local r = win and win.bagRow
    if not r then return end
    local ic = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(PAYOUT_BAG)
    r.icon:SetTexture(ic or 134400)
    local v, _, b = OQ.BagValue(PAYOUT_BAG)
    local last = OQ.BagLastValue and OQ.BagLastValue(PAYOUT_BAG)
    local tail = v and ((" ~%s (%d)"):format(Gold(v), b.opened) ..
        (last and (" · последнее: " .. Gold(last)) or "")) or (" " .. ns.C("808080", "нет замеров"))
    local maxW = r:GetWidth() - 20
    for _, label in ipairs({ ItemName(PAYOUT_BAG) .. ":", "Оплата Консорциума:", "Сумка:" }) do
        r.text:SetText(label .. tail)
        if r.text:GetStringWidth() <= maxW then break end
    end
end

local function FillRows()
    if not win then return end
    local items
    if view == "queue" then
        items = entries
    elseif view == "recipes" then
        items = {}
        for id, b in pairs(DB().recipes) do items[#items + 1] = { id = id, b = b } end
        table.sort(items, function(a, b) return (a.b.name or "") < (b.b.name or "") end)
    elseif view == "black" then
        items = {}
        for id in pairs(DB().black) do items[#items + 1] = { blackID = id } end
        table.sort(items, function(a, b) return ItemName(a.blackID) < ItemName(b.blackID) end)
    elseif view == "procs" then
        items = {}
        for id in pairs(DB().watch) do items[#items + 1] = { watchID = id } end
        table.sort(items, function(a, b) return ItemName(a.watchID) < ItemName(b.watchID) end)
    else
        items = {}
        local log = DB().log
        for i = #log, 1, -1 do items[#items + 1] = log[i] end   -- свежие сверху
    end
    -- (02.11) сколько строк влезает в список (окно растянуто по высоте окна профессии)
    local lh = win.list and win.list:GetHeight() or 0
    local nVis = (lh and lh > ROW_H) and math.min(ROW_MAX, math.floor(lh / ROW_H)) or ROWS
    local maxOff = math.max(0, #items - nVis)
    if offset > maxOff then offset = maxOff end

    for i = 1, ROW_MAX do
        local r = win.rows[i]
        local it = (i <= nVis) and items[i + offset] or nil
        r.entry, r.logEntry, r.recipeID, r.blackID, r.watchID = nil, nil, nil, nil, nil
        r:SetScript("OnEnter", nil)
        if not it then
            r:Hide()
        else
            r:Show()
            r:SetAlpha(1)
            if view == "queue" then
                local e = it
                r.entry, r.recipeID = e, e.recipeID
                r.mark:Show(); SetMark(r.mark, e.mark, e.minQ)
                r.icon:SetTexture(e.icon or 134400)
                local nm = Short(e.name)
                local cl = C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
                local isClaimed = e.state == "wait" and cl and SameID(cl.orderID, e.orderID)
                -- (02.11) статус вместо награды и цены: Сдан / Исчез / Взят / Делаю… / Сделан
                local status
                if e.state == "done" then status = ns.C("808080", "Сдан")
                elseif e.state == "gone" then status = ns.C("808080", "Исчез")
                elseif isClaimed and e.crafting then status = ns.C("ffd100", "Делаю…")
                elseif isClaimed and (e.crafted or cl.isFulfillable) then status = ns.C("60ff60", "Сделан")
                elseif isClaimed then status = ns.C("ffd100", "Взят") end
                if e.state ~= "wait" then nm = ns.C("808080", nm)
                elseif e.black then nm = ns.C("ff6060", nm)   -- (02.11) чёрный список — название красным
                elseif e.notLearned then nm = ns.C("ff6060", nm)   -- (02.11) не изучен — красным (и бледным)
                elseif not e.ok then nm = ns.C("808080", nm)
                elseif e.canCraft == false then nm = ns.C("ff9900", nm) end
                r.name:SetText(nm)
                local loss = ""
                if e.black then
                    loss = ns.C("ff6060", "Чёрный список")
                elseif e.notLearned and e.nmnm then
                    -- (02.11) «~» — оценка по самым дешёвым реагентам (рецепта нет — точный подбор не посчитать)
                    loss = (e.nmnm < 0) and ns.C("ff6060", "~-" .. Gold(-e.nmnm)) or ns.C("60ff60", "~+" .. Gold(e.nmnm))
                elseif e.profit and (e.noPrice or 0) == 0 then
                    loss = (e.profit < 0) and ns.C("ff6060", "-" .. Gold(-e.profit)) or ns.C("60ff60", "+" .. Gold(e.profit))
                elseif e.model then
                    loss = ns.C("808080", "цена ?")
                end
                -- (04.11, Миша) подпись сумки рядом с ценой убрана: цена сумки — в строке «Оплата Консорциума» внизу окна
                if e.ok and e.canCraft == false then loss = ns.C("ff9900", "реги ") .. loss end
                -- (02.11) у заказа из чёрного списка награды не показываем — только пометку;
                -- у взятого / сданного / исчезнувшего — только статус
                if status then r.info:SetText(status)
                else r.info:SetText(e.black and loss or ((e.rewardIcons or "") .. "  " .. loss)) end
                if not e.ok or e.state ~= "wait" then r:SetAlpha(0.6) end
                r:SetScript("OnEnter", EntryTooltip)
            elseif view == "recipes" then
                local b = it.b
                r.recipeID = it.id
                r.mark:Show(); SetMark(r.mark, b.mark)
                r.icon:SetTexture(b.icon or 134400)
                r.name:SetText(Short(b.name or ("Рецепт " .. it.id)))
                r.info:SetText(("в заказах %d · сделано %d%s"):format(b.seen or 0, b.crafted or 0,
                    b.manual and (" · " .. ns.C("60c0ff", "запомнен")) or ""))
                r:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(b.name or ("Рецепт " .. it.id))
                    GameTooltip:AddLine("ID рецепта: " .. it.id, 0.7, 0.7, 0.7)
                    if b.manual then
                        GameTooltip:AddLine("Запомненные реагенты (" .. date("%d.%m %H:%M", b.manual.t) .. "):", 1, 0.82, 0)
                        for _, rr in ipairs(b.manual.reagents or {}) do
                            local nmI = rr.i and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(rr.i)
                            GameTooltip:AddDoubleLine(nmI or tostring(rr.i or rr.c), "x" .. tostring(rr.q), 1, 1, 1, 1, 1, 1)
                        end
                        if b.manual.conc then GameTooltip:AddLine("Делали с концентрацией — очередь её не использует", 1, 0.6, 0.2, true) end
                    else
                        GameTooltip:AddLine("Ещё не запомнен: включите «Запоминать мои крафты» и сделайте его сами.", 0.8, 0.8, 0.8, true)
                    end
                    GameTooltip:Show()
                end)
            elseif view == "black" then
                local id = it.blackID
                r.mark:Show(); SetMark(r.mark, "no")
                r.blackID = id
                r.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400)
                local link = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(id))
                r.name:SetText(Short(ItemName(id)))
                local rq = C_TradeSkillUI.GetItemReagentQualityByItemInfo
                local okQ, qq = false, nil
                if rq then okQ, qq = pcall(rq, id) end
                r.info:SetText(((okQ and Num(qq)) and (Q(Num(qq), nil, id) .. "  ") or "") .. ns.C("808080", "ID " .. id))
                r:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(id)
                    GameTooltip:AddLine("Клик по крестику слева — убрать из чёрного списка.", 1, 0.82, 0, true)
                    GameTooltip:Show()
                end)
            elseif view == "procs" then
                -- (02.11) строка списка «Проки»: предмет + итог у ЭТОГО персонажа
                local id = it.watchID
                r.mark:Show(); SetMark(r.mark, "no")
                r.watchID = id
                r.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400)
                r.name:SetText(Short(ItemName(id)))
                local all = DB().procs[id] or {}
                local a = all[PlayerKey()]
                r.info:SetText(a and (("%d из %d · +%d"):format(a.p, a.c, a.x)) or ns.C("808080", "ещё не крафтили"))
                r:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(id)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Проки (крафтов с прибавкой / всего · сколько сверх):", 1, 0.82, 0)
                    local rows = {}
                    for who, x in pairs(all) do rows[#rows + 1] = { who = who, x = x } end
                    table.sort(rows, function(p, q) return (p.x.c or 0) > (q.x.c or 0) end)
                    for k, row in ipairs(rows) do
                        if k > 10 then GameTooltip:AddLine(("…и ещё %d"):format(#rows - 10), 0.6, 0.6, 0.6); break end
                        GameTooltip:AddDoubleLine(row.who, ("%d из %d · +%d"):format(row.x.p, row.x.c, row.x.x), 1, 1, 1, 1, 1, 1)
                    end
                    if #rows == 0 then GameTooltip:AddLine("Пока ни одного крафта.", 0.8, 0.8, 0.8) end
                    GameTooltip:AddLine("Подробно по персонажам — дашборд, страница «Тест».", 0.7, 0.7, 0.7, true)
                    GameTooltip:AddLine("Клик по крестику слева — убрать из списка.", 1, 0.82, 0, true)
                    GameTooltip:Show()
                end)
            else
                local en = it
                r.logEntry = en
                r.mark:Hide()
                r.icon:SetTexture(en.recipeID and C_TradeSkillUI.GetRecipeInfo and
                    (C_TradeSkillUI.GetRecipeInfo(en.recipeID) or {}).icon or 134400)
                local nm = Short(en.name or ("Рецепт " .. tostring(en.recipeID)))
                if en.flags then nm = ns.C("ff9900", "⚠ ") .. nm end
                r.name:SetText(date("%H:%M ", en.t) .. nm)
                r.info:SetText((en.gotQ and Q(en.gotQ, en.recipeID) or "") .. "  " .. (en.realSpent and Gold(en.realSpent) or ""))
                r:SetScript("OnEnter", LogTooltip)
            end
        end
    end
    win.empty:SetShown(#items == 0)
    if #items == 0 then
        win.empty:SetText(view == "queue" and "Пусто. Нажмите «Обновить» у стола заказов."
            or view == "recipes" and "Рецептов пока нет — аддон узнает их из заказов и ваших крафтов."
            or view == "black" and "Чёрный список пуст. Перетащите предмет в поле внизу или вставьте ссылку (Shift+клик)."
            or view == "procs" and "Список пуст. Перетащите в поле внизу ЗОЛОТОЙ предмет, за проками которого следить."
            or "Журнал пуст.")
    end
end

-- (02.11) Сторож зависаний: кнопка висит на «Делаю… / Сдаю… / Считаю…» дольше 10 с —
-- сбрасываем застрявшее состояние и пишем в след (step = "watchdog").
local lastBtnText, lastBtnAt = nil, 0
local STUCK = { ["Делаю…"] = true, ["Сдаю…"] = true, ["Считаю…"] = true }
local function Watchdog(text)
    if not STUCK[text] or (GetTime() - lastBtnAt) < 10 then return false end
    local cl = C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
    Trace("watchdog", { text = text, oid = cl and tostring(cl.orderID), fulfillable = cl and cl.isFulfillable or nil,
        current = current and current.log and current.log.name or nil })
    if text == "Делаю…" then
        if current then CloseCraft() end
        for _, e in ipairs(entries) do e.crafting = false end
    elseif text == "Сдаю…" then
        if cl then fulfillSent[tostring(cl.orderID)] = nil end
        for _, e in ipairs(entries) do e.fulfilling = false end
    elseif text == "Считаю…" then
        scanning = false
    end
    lastBtnAt = GetTime()
    return true
end

local function UpdateButtons()
    if not win then return end
    local text, enabled, action = NextAction()
    if text ~= lastBtnText then
        lastBtnText, lastBtnAt = text, GetTime()
        Trace("btn", { text = text, on = enabled and true or false })
    elseif Watchdog(text) then
        text, enabled, action = NextAction()
    end
    win.next:SetText(text)
    win.next:SetEnabled(enabled and true or false)
    win.next.action = enabled and action or nil
    win.scan:SetEnabled(not scanning and not InCombatLockdown())
    for k, b in pairs(win.tabs) do
        if k == view then b:LockHighlight() else b:UnlockHighlight() end
    end
    win.clear:SetShown(view == "log")
    if win.macros then win.macros:SetShown(view ~= "log") end
    -- поле добавления (чёрный список / проки) стоит на месте строки «Сумка»
    local listView = (view == "black" or view == "procs")
    win.blackBox:SetShown(listView)
    win.blackAdd:SetShown(listView)
    if win.bagRow then win.bagRow:SetShown(not listView) end
end

-- Заказ взят (кем угодно: нашей кнопкой или в окне Blizzard). Работает и без окна очереди.
-- Взятый заказ пересчитываем по ЖИВЫМ данным (как CraftSim Craft: «prefer live claimed-order
-- data») и делаем снимок сумок — чтобы у крафта в окне Blizzard был реальный расход.
local function OnClaimed()
    if scanning then return end
    local cl = C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
    if not cl then return end
    local o = SeenOf(cl.orderID)
    if o and not o.claimed then o.claimed = time() end
    local ce = FindEntry(cl.orderID)
    if ce and ce.state == "wait" and not ce.live and not ce.crafting then
        local okE, ne = pcall(Evaluate, cl, ce.prof, true)
        if okE and ne then for k, v in pairs(ne) do ce[k] = v end end
        ce.live = true
        ce.snap = Snapshot(ce.plan)
    end
end
OQ.OnClaimed = OnClaimed

Refresh = function()
    if not win or not win:IsShown() then return end
    if not scanning then
        OnClaimed()
        for _, e in ipairs(entries) do if e.state == "wait" and e.plan then ApplyRule(e) end end
        AutoFulfill()
    end
    pcall(UpdateBagRow)
    FillRows()
    UpdateButtons()
    win.status:SetText(statusText)
end

local function BuildWindow()
    if win then return win end
    win = CreateFrame("Frame", "RainonUIOrderQueue", UIParent, "ButtonFrameTemplate")
    win:SetSize(WIN_W, WIN_H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(win) end
    -- (02.11) заголовок как у «Знания и заряды»; ButtonFrameTemplate сам ставит его по центру
    if win.SetTitle then win:SetTitle("RainonUI — Очередь заказов") end
    if win.PortraitContainer then win.PortraitContainer:Hide() end
    -- (02.11) ESC закрывает окно (если открыто вместе с окном профессии — закроются оба, как у Blizzard)
    table.insert(UISpecialFrames, "RainonUIOrderQueue")
    win:Hide()

    local listW = WIN_W - PAD * 2 - 8
    local y = -30

    -- (02.11) РАСКЛАДКА ОКНА (просьба Миши, по устройству ButtonFrameTemplate):
    --   серый верх (над чёрной рамкой Inset): кнопки в две строки, все одного размера, текст по центру —
    --     Очередь | Рецепты | Журнал | Чёрный список
    --     Проки   | Обновить | Покупки | Макросы (во вкладке «Журнал» на её месте — «Очистить»)
    --   чёрная рамка (Inset): список заказов, с небольшим отступом от кнопок;
    --   серый низ, всё по одной левой границе: «Заказов: …» / «Прибыль не меньше» / «Сферы знаний» /
    --     «Сумка» (во вкладках «Чёрный список» и «Проки» на её месте — поле добавления) / кнопка «Дальше».
    local GRID_N, GRID_GAP, BTN_H = 4, 4, 22
    local BTN_W = math.floor((WIN_W - PAD * 2 - GRID_GAP * (GRID_N - 1)) / GRID_N)   -- 400 → 91
    local function GridBtn(row, col, text, onClick)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetSize(BTN_W, BTN_H)
        b:SetPoint("TOPLEFT", PAD + (col - 1) * (BTN_W + GRID_GAP), -28 - (row - 1) * (BTN_H + GRID_GAP))
        b:SetText(text)
        if b.SetNormalFontObject then b:SetNormalFontObject("GameFontNormalSmall"); b:SetHighlightFontObject("GameFontHighlightSmall") end
        local fs = b:GetFontString()
        if fs then fs:ClearAllPoints(); fs:SetPoint("CENTER", 0, 0); fs:SetJustifyH("CENTER") end
        b:SetScript("OnClick", onClick)
        return b
    end
    win.tabs = {}
    local tabDefs = { { "queue", "Очередь", 1, 1 }, { "recipes", "Рецепты", 1, 2 }, { "log", "Журнал", 1, 3 },
                      { "black", "Чёрный список", 1, 4 }, { "procs", "Проки", 2, 1 } }
    for _, d in ipairs(tabDefs) do
        win.tabs[d[1]] = GridBtn(d[3], d[4], d[2], function() view = d[1]; offset = 0; Refresh() end)
    end
    win.scan = GridBtn(2, 2, "Обновить", function() OQ.Scan() end)
    win.shop = GridBtn(2, 3, "Покупки", function() OQ.MakeShoppingList() end)
    win.shop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Список покупок", 1, 1, 1)
        GameTooltip:AddLine("Добавляет в список Auctionator «!RainonUI — покупки» реагенты, которых не хватает на заказы" ..
            " «к работе» этого стола. У другого стола — добавит его часть. Купил на аукционе — строка исчезает сама.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Shift + клик — очистить список.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    win.shop:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- (02.11) «Макросы» — создать/обновить макросы панели: Сумка, Травы, «Дальше» (во вкладке «Журнал» — «Очистить»)
    win.macros = GridBtn(2, 4, "Макросы", function() OQ.CreateBagMacros() end)
    win.macros:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Макросы для панели", 1, 1, 1)
        GameTooltip:AddLine("Создаёт или обновляет общие макросы:", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("0.0_RainonUI — открыть сумку за заказы", 1, 1, 1)
        GameTooltip:AddLine("0.1_RainonUI — открыть букет трав", 1, 1, 1)
        GameTooltip:AddLine("0.2_RainonUI — нажать «Дальше»", 1, 1, 1)
        GameTooltip:AddLine("Потом /macro → перетащи на панель.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    win.macros:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.clear = GridBtn(2, 4, "Очистить", function()
        if not IsShiftKeyDown() then ns.Print("Очередь заказов: зажмите Shift, чтобы очистить журнал."); return end
        DB().log = {}
        Refresh()
    end)
    win.clear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Очистить журнал", 1, 1, 1)
        GameTooltip:AddLine("С зажатым Shift.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    win.clear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- серый верх заканчивается под второй строкой кнопок (−28 − 22 − 4 − 22 = −76) → чёрная рамка с −80
    local TOP_Y, BOTTOM_H = -80, 144   -- BOTTOM_H — высота серого низа (строки настроек + «Дальше»)
    if win.Inset then
        win.Inset:ClearAllPoints()
        win.Inset:SetPoint("TOPLEFT", win, "TOPLEFT", PAD - 6, TOP_Y)
        win.Inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -(PAD - 6), BOTTOM_H)
    end
    -- строки серого низа (снизу вверх): «Дальше» 10..42, сумка/поле ~50, сферы ~74, прибыль ~100, «Заказов» ~126
    local LINE4, LINE3, LINE2, LINE1 = 50, 74, 110, 126

    local s = DB().settings
    -- (02.11) Строка «Оплата Консорциума»: сумка относится ко всем профессиям, поэтому она здесь.
    -- Иконка, средняя цена по замерам, сколько открыто, цена последнего открытия.
    -- Без переноса: если не влезает — короче подпись (правило CODE_CORE: текст не наезжает).
    local bagRow = CreateFrame("Frame", nil, win)
    bagRow:SetPoint("BOTTOMLEFT", PAD, LINE4 + 1)
    bagRow:SetSize(WIN_W - PAD * 2 - 4, 18)
    bagRow.icon = bagRow:CreateTexture(nil, "ARTWORK")
    bagRow.icon:SetSize(16, 16)
    bagRow.icon:SetPoint("LEFT", 0, 0)
    bagRow.text = bagRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagRow.text:SetPoint("LEFT", bagRow.icon, "RIGHT", 4, 0)
    bagRow.text:SetJustifyH("LEFT")
    bagRow.text:SetWordWrap(false)
    bagRow:EnableMouse(true)
    bagRow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(PAYOUT_BAG) end
        GameTooltip:Show()
    end)
    bagRow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.bagRow = bagRow
    y = y - 22

    -- Порог убытка
    local box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    box:SetSize(54, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(6)   -- (02.11) не SetNumeric: нужен знак минус
    box:SetText(tostring(math.floor((s.minProfit or 0) / GOLD + 0.5)))
    local function commit(self)
        local txt = tostring(self:GetText() or ""):gsub("%s", ""):gsub(",", ".")
        local n = tonumber(txt)
        if not n then n = math.floor((DB().settings.minProfit or 0) / GOLD + 0.5) end
        n = math.floor(n)
        DB().settings.minProfit = n * GOLD
        self:SetText(tostring(n))
        self:ClearFocus()
        for _, e in ipairs(entries) do ApplyRule(e) end
        Refresh()
    end
    box:SetScript("OnEnterPressed", commit)
    box:SetScript("OnEditFocusLost", commit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local boxL = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    boxL:SetPoint("LEFT", win, "BOTTOMLEFT", PAD, LINE2)
    boxL:SetText("Прибыль не меньше:")
    box:SetPoint("LEFT", boxL, "RIGHT", 12, 0)   -- у поля ввода рамка слева шире на ~5px
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Прибыль не меньше")
        GameTooltip:AddLine("−50 — берём и в убыток до 50 золотых; 0 — только без убытка; 20 — только с прибылью от 20." ..
            " Сферы знаний входят в прибыль, сумка за заказы — нет.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local boxG = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    boxG:SetPoint("LEFT", box, "RIGHT", 2, 0)
    boxG:SetText(GOLD_ICON)
    y = y - 26

    -- Сферы знаний (02.11): общий выключатель + цена Отблеска и Света (в золоте).
    local kp = ns.MakeCheckButton(win)
    kp:SetSize(24, 24)
    kp:SetPoint("BOTTOMLEFT", PAD - 4, LINE3)   -- у галки прозрачный край ~4px: сам квадрат — по левой границе
    kp.Text:SetText("Сферы знаний")
    kp.Text:SetFontObject("GameFontHighlightSmall")
    kp:SetChecked(s.kpOn)
    kp:SetScript("OnClick", function(self)
        DB().settings.kpOn = self:GetChecked() and true or false
        OQ.RescoreKP()
    end)
    kp:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Сферы знаний в награде")
        GameTooltip:AddLine("Включено: «Отблеск знания» и «Свет знания» в награде считаются как деньги по ценам справа, " ..
            "но только у персонажей с галкой «Сферы» в окне «Знания и заряды». Выключено: сферы не учитываются нигде.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    kp:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local function KPBox(key, label, after)
        local b = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
        b:SetSize(44, 20)
        b:SetAutoFocus(false)
        b:SetNumeric(true)
        b:SetMaxLetters(5)
        b:SetText(tostring(math.floor((s[key] or 0) / GOLD)))
        local function save(self)
            local n = tonumber(self:GetText()) or 0
            DB().settings[key] = n * GOLD
            self:SetText(tostring(n))
            self:ClearFocus()
            OQ.RescoreKP()
        end
        b:SetScript("OnEnterPressed", save)
        b:SetScript("OnEditFocusLost", save)
        b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local g = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        g:SetPoint("LEFT", b, "RIGHT", 2, 0)
        g:SetText(GOLD_ICON)
        local l = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("LEFT", after, "RIGHT", 14, 0)
        l:SetText(label)
        b:SetPoint("LEFT", l, "RIGHT", 10, 0)
        return g
    end
    local glimG = KPBox("kpGlimmer", "Отблеск:", kp.Text)
    KPBox("kpLight", "Свет:", glimG)
    y = y - 26

    y = y - 6

    -- Список
    local list = CreateFrame("Frame", nil, win)
    list:SetPoint("TOPLEFT", PAD + 2, TOP_Y - 4)                       -- (02.11) внутри чёрной рамки, отступ 4
    list:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD - 2, BOTTOM_H + 4)
    list:SetWidth(listW)
    win.list = list
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        Refresh()
    end)
    win.rows = {}
    for i = 1, ROW_MAX do win.rows[i] = NewRow(list, i, listW) end
    win.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty:SetPoint("TOPLEFT", 4, -8)
    win.empty:SetPoint("TOPRIGHT", -4, -8)
    win.empty:SetJustifyH("LEFT")
    win.empty:SetWordWrap(true)

    -- Низ: статус, «Обновить», «Дальше», «Очистить журнал»
    -- (02.11) имя у кнопки — для макроса /click RainonUIOrderQueueNext (нажатие клавиши/макроса = «живое» нажатие)
    win.next = CreateFrame("Button", "RainonUIOrderQueueNext", win, "UIPanelButtonTemplate")
    win.next:SetSize(WIN_W - PAD * 2, 32)
    win.next:SetPoint("BOTTOM", 0, 10)
    -- (02.11) раз в секунду, пока окно открыто, перепроверяем кнопку (для сторожа зависаний)
    local tick = 0
    win:HookScript("OnUpdate", function(_, el)
        tick = tick + el
        if tick < 1 then return end
        tick = 0
        UpdateButtons()
    end)
    win.next:SetScript("OnClick", function(self)
        local fn = self.action
        if fn then
            Trace("press", { text = self:GetText() })
            autoChain = true
            self.action = nil
            self:SetEnabled(false)
            fn()
            C_Timer.After(0.3, function() Refresh() end)
        end
    end)

    -- Чёрный список: поле (ID / ссылка Shift+клик / перетащить предмет) + «Добавить»
    local function AddBlack(text)
        local id = tonumber(text) or tonumber(tostring(text or ""):match("item:(%d+)"))
        if not id then ns.Print("Очередь заказов: нужен ID предмета или ссылка (Shift+клик)."); return end
        win.blackBox:SetText("")
        win.blackBox:ClearFocus()
        if view == "procs" then
            DB().watch[id] = true
            RememberName(id)
            ns.Print("Очередь заказов: следим за проками — " .. ItemName(id) .. ".")
            Refresh()
            return
        end
        DB().black[id] = true
        ns.Print("Очередь заказов: в чёрный список — " .. ItemName(id) .. ". Нажмите «Обновить» для пересчёта.")
        Refresh()
    end
    local function DropItem()
        local kind, id = GetCursorInfo()
        if kind == "item" and id then ClearCursor(); AddBlack(id) end
    end
    win.blackBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    win.blackBox:SetSize(BTN_W * 2 + GRID_GAP - 10, 20)
    win.blackBox:SetPoint("BOTTOMLEFT", PAD + 6, LINE4)   -- рамка поля шире слева на ~5px
    win.blackBox:SetAutoFocus(false)
    win.blackBox:SetScript("OnEnterPressed", function(self) AddBlack(self:GetText()) end)
    win.blackBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    win.blackBox:SetScript("OnReceiveDrag", DropItem)
    win.blackBox:SetScript("OnMouseDown", DropItem)
    win.blackBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(view == "procs" and "Следить за проками" or "Добавить в чёрный список")
        GameTooltip:AddLine("Перетащите сюда предмет, вставьте ссылку (Shift+клик) или впишите ID и нажмите Enter.", 1, 1, 1, true)
        if view == "procs" then
            GameTooltip:AddLine("Кладите ЗОЛОТОЙ предмет: у каждого качества свой ID, считаются только проки этого предмета.", 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    win.blackBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.blackAdd = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.blackAdd:SetSize(BTN_W, BTN_H)
    win.blackAdd:SetPoint("LEFT", win.blackBox, "RIGHT", GRID_GAP + 2, 0)
    win.blackAdd:SetText("Добавить")
    win.blackAdd:SetScript("OnClick", function() AddBlack(win.blackBox:GetText()) end)
    -- Shift+клик по предмету вставляет ссылку в наше поле, если оно в фокусе.
    local function InsertLinkHook(link)
        if win and win.blackBox and win.blackBox:IsShown() and win.blackBox:HasFocus() and link then
            win.blackBox:SetText(link)
        end
    end
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", InsertLinkHook) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLinkHook) end

    win.status = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.status:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD, LINE1)
    win.status:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, LINE1)
    win.status:SetJustifyH("LEFT")
    win.status:SetWordWrap(false)

    win:SetScript("OnShow", function() Refresh() end)
    return win
end

-- -------------------------------------------------------------------------
-- Показ рядом с окном профессии
-- -------------------------------------------------------------------------
local function Dock()
    if not (win and ProfessionsFrame) then return end
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 4, 0)
    -- (02.11) высота = высота окна профессии (с поправкой на разный масштаб окон)
    local h = ProfessionsFrame:GetHeight()
    local s1, s2 = ProfessionsFrame:GetEffectiveScale(), win:GetEffectiveScale()
    if h and h > 0 and s1 and s2 and s2 > 0 then
        local hh = h * s1 / s2
        win:SetHeight((hh >= 400) and hh or WIN_H)
    end
    if not win.dockHooked then
        win.dockHooked = true
        ProfessionsFrame:HookScript("OnSizeChanged", function()
            if win:IsShown() and not InCombatLockdown() then Dock(); if Refresh then Refresh() end end
        end)
    end
end

function OQ.Show()
    if InCombatLockdown() then return end
    BuildWindow()
    if ProfessionsFrame and ProfessionsFrame:IsShown() then
        Dock()
    else
        -- окно профессии закрыто (открыли кнопкой «Крафт») — ставим рядом с «Знания и заряды»
        win:ClearAllPoints()
        local k = _G.RainonUIKnowledge
        if k and k:IsShown() then win:SetPoint("TOPLEFT", k, "TOPRIGHT", 4, 0)
        else win:SetPoint("CENTER") end
    end
    win:Show()
    Refresh()
end

function OQ.Hide() autoChain = false; if win then win:Hide() end end

function OQ.Toggle()
    if win and win:IsShown() then OQ.manualOpen = false; OQ.Hide() else OQ.manualOpen = true; OQ.Show() end
end

function OQ.Refresh()
    if not Enabled() then OQ.Hide(); return end
    if ProfessionsFrame and ProfessionsFrame:IsShown() then OQ.Show() end
end

local hooked = false
local function HookProfessions()
    if hooked or not ProfessionsFrame then return end
    hooked = true
    -- Окно очереди живёт во вкладке «Patron» (заказы покровителей); там же прячем
    -- «Знания и заряды» и возвращаем его, когда уходим из вкладки.
    local inPatron, knowHidden, acc = false, false, 0
    ns.RegisterMessage("RAINON_PROFESSIONS_TOGGLED", function()
        inPatron, knowHidden = false, false
    end)
    -- Вкладка «Patron»: обычная страница заказов Blizzard ИЛИ её копия от No Mats No Make
    -- (OrdersPageOffline — когда стол заказов далеко).
    local function IsPatronTab()
        for _, page in ipairs({ ProfessionsFrame.OrdersPage, ProfessionsFrame.OrdersPageOffline }) do
            if page and page:IsVisible() and page.orderType == Enum.CraftingOrderType.Npc then return true end
        end
        return false
    end
    -- Игра загрузила заказы покровителей → сразу пересчитываем очередь (без своего запроса).
    local page = ProfessionsFrame.OrdersPage
    if page and page.OrderRequestCallback then
        hooksecurefunc(page, "OrderRequestCallback", function(_, _, orderType)
            if orderType == Enum.CraftingOrderType.Npc then   -- сбор данных — всегда, даже без окна
                C_Timer.After(0.1, OQ.ScanCached)
            end
        end)
    end
    -- Какие заказы Миша открывал в окне Blizzard (для анализа выбора).
    -- (хук SetOrder не сработал в игре — смотрим поле order при показе окна заказа)
    local ov = page and page.OrderView
    if ov then
        local function MarkViewed()
            local order = ov.order
            if not (order and order.orderID) or IsSecret(order.orderID) then return end
            local o = SeenOf(order.orderID)
            if o then o.viewed = (o.viewed or 0) + 1; o.viewedAt = o.viewedAt or time() end
        end
        ov:HookScript("OnShow", function() C_Timer.After(0.1, MarkViewed) end)
        if ov.SetOrder then hooksecurefunc(ov, "SetOrder", function() C_Timer.After(0.1, MarkViewed) end) end
    end
    local watcher = CreateFrame("Frame", nil, ProfessionsFrame)
    watcher:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.2 then return end
        acc = 0
        -- (02.11) «Окна сами» — только при включённой очереди (галка «Очередь заказов (тест)» во вкладке
        -- «Профессии»; по умолчанию выкл.) и включённой «Окна сами» (features.oqAutoOpen, по умолчанию вкл.)
        local autoOn = Enabled() and not (ns.db and ns.db.features and ns.db.features.oqAutoOpen == false)
        if not autoOn or InCombatLockdown() then return end
        local now = IsPatronTab()
        if now == inPatron then return end
        inPatron = now
        local k = _G.RainonUIKnowledge
        if now then
            OQ.Show()
            if k and k:IsShown() then k:Hide(); knowHidden = true end
            -- сразу обновить очередь (если игра уже отдала список — берём его, иначе свой запрос)
            C_Timer.After(0.3, function()
                if not scanning then
                    OQ.ScanCached()
                    if not scanning and #entries == 0 then OQ.Scan() end
                end
            end)
        else
            -- (02.11) ушёл с вкладки «Клиент» (например, на «Рецепты») — очередь закрываем всегда,
            -- даже если её открывали вручную (кнопкой «Крафт» / /rsorders)
            OQ.manualOpen = false
            OQ.Hide()
            -- (02.11) вкладка крафта → «Знания и заряды»: вернуть, если прятали мы,
            -- или открыть, если включено «Открывать с профессией»
            if k and not k:IsShown() then
                if knowHidden then
                    if ns.Knowledge and ns.Knowledge.Open then ns.Knowledge:Open() else k:Show() end
                elseif ns.Knowledge then
                    ns.Knowledge:OpenWithProfession()
                end
            end
            knowHidden = false
        end
    end)
    ProfessionsFrame:HookScript("OnHide", function()
        inPatron, knowHidden = false, false
        OQ.manualOpen = false
        OQ.Hide()
    end)

    -- (02.11) Окно заказа Blizzard, заказы покровителей: «Начать» и «Завершить» нажимаем сами,
    -- вопрос «положить свои реагенты?» подтверждаем сами. Своя реализация (идея — No Mats No Make):
    -- правила в одной таблице, одна проверка. Наша очередь («Дальше», клавиша, макрос) от этого
    -- не зависит — она сама зовёт ClaimOrder/FulfillOrder. Включён No Mats No Make — молчим (не жмём дважды).
    local function AutoAllowed(key)
        if not (Enabled() and DB().settings[key]) then return false end
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("PublicOrdersReagentsColumn") then return false end
        local page = ProfessionsFrame.OrdersPage
        return page ~= nil and page.orderType == Enum.CraftingOrderType.Npc
    end
    local view = ProfessionsFrame.OrdersPage and ProfessionsFrame.OrdersPage.OrderView
    local autoPress = {
        { key = "skipStart",    button = view and view.OrderInfo and view.OrderInfo.StartOrderButton },
        { key = "skipComplete", button = view and view.CompleteOrderButton, onlyOnce = true },
    }
    for _, rule in ipairs(autoPress) do
        if rule.button then
            rule.button:HookScript("OnShow", function(btn)
                if not AutoAllowed(rule.key) then return end
                if rule.onlyOnce then   -- «сдать» один раз на заказ (общая защита с нашей очередью)
                    local claimed = C_CraftingOrders.GetClaimedOrder()
                    local id = claimed and tostring(claimed.orderID)
                    if id then
                        if fulfillSent[id] then return end
                        fulfillSent[id] = true
                    end
                end
                btn:Click()
            end)
        end
    end
    if StaticPopup_ShowCustomGenericConfirmation then
        hooksecurefunc("StaticPopup_ShowCustomGenericConfirmation", function(info)
            if type(info) ~= "table" or not AutoAllowed("skipOwnReagent") then return end
            if issecrettable and issecrettable(info) then return end
            if IsSecret(info.text) or info.text ~= CRAFTING_ORDERS_OWN_REAGENTS_CONFIRMATION then return end
            if type(info.callback) ~= "function" then return end
            info.callback()
            if StaticPopup_Hide then pcall(StaticPopup_Hide, "GENERIC_CONFIRMATION") end
            if StaticPopup1 and StaticPopup1:IsShown() and StaticPopup1.which == "GENERIC_CONFIRMATION" then
                StaticPopup1:Hide()
            end
        end)
    end
end

-- -------------------------------------------------------------------------
-- (02.11) Учёт проков по списку «Проки» (вкладка окна очереди). Только предметы из списка,
-- любой крафт (заказ, свой, на продажу), у любого персонажа. Нагрузки нет: одно событие игры
-- на крафт. Если стопка в сумке переполнилась, игра шлёт результат ДВУМЯ событиями (5 = 3 + 2,
-- «сверх» в обоих одинаковое) — склеиваем их в один крафт: тот же предмет и тот же operationID
-- или в пределах 0,25 с (два настоящих крафта так близко не бывают — каст дольше секунды).
-- -------------------------------------------------------------------------
-- (у главного блока файла предел 200 локальных — служебное прячем внутрь do … end)
local CountProc
do
local PROC_MAX = 5000    -- журнал проков: один крафт = одна короткая запись
local procCast
local txCost
function OQ.ReadReturns(data)
    local out, valid = {}, true
    local rr = data and data.resourcesReturned
    if IsSecret(rr) then return out, false end
    for _, x in ipairs(type(rr) == "table" and rr or {}) do
        local r = x.reagent or x
        local id, q = Num(r.itemID), Num(x.quantity)
        if id and q and q > 0 then out[id] = (out[id] or 0) + q else valid = false end
    end
    return out, valid
end
function OQ.CaptureCraftCost(recipeID, amount, reagents, _, orderID)
    txCost, OQ.costContext = nil, nil
    local rid = Num(recipeID)
    if not rid then return end
    local ctx = {recipe=rid, remaining=math.max(1,Num(amount) or 1), plan={}, prices={}, cost=0, np=0,
        complete=true, src=orderID and "order" or "self", orderID=orderID and tostring(orderID)}
    txCost, OQ.costContext = ctx, ctx
    local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, rid, false)
    if not ok or type(sch)~="table" then ctx.complete=false; return end
    if Num(sch.quantityMin)==Num(sch.quantityMax) then ctx.base=Num(sch.quantityMin) end
    if orderID then return end
    local slots={}
    for _,r in ipairs(reagents or {}) do
        local id,cur,q,slot=RInfo(r)
        id,q,slot=Num(id),Num(q),Num(slot)
        if slot and q and q>0 then
            slots[slot]=slots[slot] or {}
            slots[slot][#slots[slot]+1]={id=id,q=q}
        end
    end
    local form=ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
    local tr=form and form:IsVisible() and form.GetTransaction and form:GetTransaction()
    if not (tr and tr.GetRecipeID and Num(tr:GetRecipeID())==rid) then tr=nil end
    for _,sl in ipairs(sch.reagentSlotSchematics or {}) do
        local alloc=slots[sl.dataSlotIndex]
        if not alloc and reagents==nil and tr and tr.GetAllocations then
            local okA,aa=pcall(tr.GetAllocations,tr,sl.slotIndex)
            if okA and aa and aa.Enumerate then
                alloc={}
                for _,x in aa:Enumerate() do
                    local r=x.GetReagent and x:GetReagent()
                    local q=Num(x.GetQuantity and x:GetQuantity())
                    if r and q and q>0 then alloc[#alloc+1]={id=Num(r.itemID),q=q} end
                end
            end
        end
        local need=Num(sl.quantityRequired) or 0
        if (not alloc or #alloc==0) and sl.required and need>0 and #(sl.reagents or {})==1 then
            alloc={{id=Num(sl.reagents[1].itemID),q=need}}
        end
        local supplied=0
        for _,x in ipairs(alloc or {}) do
            supplied=supplied+x.q
            if x.id then ctx.plan[x.id]=(ctx.plan[x.id] or 0)+x.q else ctx.complete=false end
        end
        if sl.required and supplied<need then ctx.complete=false end
    end
    for id,q in pairs(ctx.plan) do
        local p=Price(id)
        if p then ctx.prices[id]=p;ctx.cost=ctx.cost+p*q else ctx.np=ctx.np+1 end
        RememberName(id)
    end
end
local function Revalue(rec,ctx)
    rec.c=nil
    if not ctx or not ctx.complete or not rec.returnsValid or rec.src~="self" then return end
    local cost=ctx.cost
    for id,q in pairs(rec.returned) do
        if ctx.plan[id] and ctx.prices[id] then cost=cost-ctx.prices[id]*math.min(q,ctx.plan[id]) end
    end
    rec.c=math.max(0,math.floor(cost+0.5))
end
CountProc=function(data)
    if type(data)~="table" or IsSecret(data.itemID) or data.firstCraftReward then return end
    local d,id=DB(),Num(data.itemID)
    if not id or not d.watch[id] then return end
    local n,m=Num(data.quantity),Num(data.multicraft) or 0
    if not n or n<=0 then return end
    local op=Num(data.operationID)
    if op==0 then op=nil end
    local ctx,pc=txCost,procCast
    local rr,valid=OQ.ReadReturns(data)
    if pc and pc.id==id and pc.ctx==ctx and op and pc.op==op then
        local old=pc.rec.m
        pc.rec.n=pc.rec.n+n;pc.rec.m=math.max(old,m)
        pc.agg.n=pc.agg.n+n;pc.agg.x=pc.agg.x+pc.rec.m-old
        if old==0 and pc.rec.m>0 then pc.agg.p=pc.agg.p+1 end
        for rid,q in pairs(rr) do pc.rec.returned[rid]=math.max(pc.rec.returned[rid] or 0,q) end
        pc.rec.returnsValid=pc.rec.returnsValid and valid
        pc.rec.quantityOK=pc.rec.base~=nil and pc.rec.n==pc.rec.base+pc.rec.m
        Revalue(pc.rec,ctx)
        pc.agg.best=math.max(pc.agg.best or 0,pc.rec.n)
        return
    end
    local cl=current and current.log
    local claimed=C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
    local oid=(ctx and ctx.orderID) or (cl and cl.orderID) or (claimed and claimed.orderID)
    local src=oid and "order" or (ctx and ctx.remaining>0 and ctx.src or "unknown")
    local rec={t=time(),w=PlayerKey(),i=id,n=n,m=m,v=Price(id),cv=3,src=src,
        orderID=oid and tostring(oid),recipe=ctx and ctx.recipe,op=op,base=ctx and ctx.base,
        np=ctx and ctx.np,returned=rr,returnsValid=valid}
    rec.quantityOK=rec.base~=nil and n==rec.base+m
    if ctx and ctx.remaining>0 then Revalue(rec,ctx);ctx.remaining=ctx.remaining-1 end
    d.procs[id]=d.procs[id] or {}
    local agg=d.procs[id][rec.w]
    if not agg then agg={c=0,p=0,x=0,n=0};d.procs[id][rec.w]=agg end
    agg.c,agg.n,agg.t=agg.c+1,agg.n+n,rec.t
    if m>0 then agg.p,agg.x=agg.p+1,agg.x+m end
    agg.best=math.max(agg.best or 0,n)
    d.procLog[#d.procLog+1]=rec
    while #d.procLog>PROC_MAX do table.remove(d.procLog,1) end
    procCast={id=id,op=op,ctx=ctx,rec=rec,agg=agg}
    RememberName(id)
end

end

-- -------------------------------------------------------------------------
-- События (свой фрейм: часть событий заказов может отсутствовать — pcall)
-- -------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, name in ipairs({
    "CRAFTINGORDERS_CLAIMED_ORDER_UPDATED", "CRAFTINGORDERS_CLAIMED_ORDER_REMOVED",
    "CRAFTINGORDERS_CLAIM_ORDER_RESPONSE", "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE",
    "TRADE_SKILL_ITEM_CRAFTED_RESULT", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED",
    "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
}) do
    pcall(ev.RegisterEvent, ev, name)
end

local refreshQueued = false
local function SoftRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.3, function() refreshQueued = false; if Refresh then Refresh() end end)
end

ev:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(function(...)
        if event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
            local data = ...
            pcall(CountProc, data)   -- (02.11) проки по списку — отдельно от очереди
            local cl = C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
            local ce = cl and FindEntry(cl.orderID)
            -- (02.11) «Сделан» ставим ТОЛЬКО если это крафт именно этого заказа: наш крафт по нему
            -- или вышел тот же предмет, что заказан. Раньше любой крафт (свой, на продажу) при
            -- взятом заказе помечал заказ сделанным → потом он считался сданным, хотя не был.
            if ce and type(data) == "table" then
                local mine = current and current.e == ce
                local sameItem = Num(cl.itemID) and Num(data.itemID) and Num(cl.itemID) == Num(data.itemID)
                if mine or sameItem then ce.crafted = true; ce.crafting = false
                else ce = nil end
            end
            -- Крафт в окне Blizzard, а перехват не сработал — всё равно пишем заказ в журнал.
            if not current and ce and type(data) == "table" then
                StartCraftLog(ce, "blizzard", ce.recipeID, ce.name, ce.plan, {
                    orderID = tostring(ce.orderID), minQ = ce.minQ, expQ = ce.expQ, rule = ce.rule,
                    ourCost = ce.ourCost, noPrice = ce.noPrice, reward = ce.reward,
                    rewardItems = ce.rewardItems, profit = ce.profit,
                })
                if ce.snap then current.before = ce.snap else current.noSnap = true end
            end
            if current and type(data) == "table" then
                local en = current.log
                en.gotQ = Num(data.craftingQuality) or en.gotQ
                en.concSpent = Num(data.concentrationSpent) or en.concSpent
                en.multi = Num(data.multicraft) or en.multi
                local returned, validReturns = OQ.ReadReturns(data)
                en.returned = en.returned or {}
                for iid, qty in pairs(returned) do en.returned[iid] = math.max(en.returned[iid] or 0, qty) end
                en.resourceful = next(en.returned) ~= nil
                en.returnsValid = validReturns
                en.resultItem = data.itemID and Num(data.itemID) or nil
                en.resultN = data.quantity and Num(data.quantity) or nil
                Trace("craft_result", { oid = en.orderID, name = en.name, gotQ = en.gotQ, concSpent = en.concSpent,
                    multi = en.multi, returned = en.returned, item = en.resultItem, n = en.resultN })
                -- Сумки обновляются чуть позже результата — считаем через 2с.
                local mine = current
                C_Timer.After(2, function() if current == mine then CloseCraft() end end)
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- (02.11) страховка: крафт прошёл, а «результата» нет (чары прямо на вещь и т.п.) —
            -- через 3 с закрываем запись, чтобы очередь не висела на «Делаю…»
            local unit, _, spellID = ...
            local sid = Num(spellID)
            if unit == "player" and current and sid and sid == current.log.recipeID then
                local mine = current
                C_Timer.After(3, function()
                    if current == mine and not mine.log.resultItem then
                        Trace("craft_noresult", { name = mine.log.name })
                        CloseCraft()
                    end
                end)
            end
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
            local unit, _, spellID = ...
            if unit == "player" and current and (GetTime() - (current.started or 0)) < 15 then
                -- только наш рецепт (другие неудачные касты не трогаем)
                local sid = Num(spellID)
                if sid and current.log.recipeID and sid ~= current.log.recipeID then return end
                -- неудачная попытка — строку журнала убираем, чтобы не плодить дубли
                local en = current.log
                Trace("craft_fail", { oid = en.orderID, name = en.name, event = event, spell = sid })
                local log = DB().log
                for i = #log, 1, -1 do if log[i] == en then table.remove(log, i); break end end
                if current.e then current.e.crafting = false end
                current = nil
                ns.Print("Очередь заказов: крафт не прошёл — попробуйте ещё раз.")
            end
        elseif event == "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE" then
            local result, orderID = ...
            -- «сдан» в сборе данных — даже если заказа нет в текущем списке очереди
            if result == Enum.CraftingOrderResult.Ok then
                local so = SeenOf(orderID)
                if so and not so.done then so.done = time() end
            end
            local e = FindEntry(orderID)
            -- (02.11) проверка оплаты и наград: что реально пришло после сдачи (через 1,5с)
            do
                local snap = e and e.rsnap
                local tr = Trace("fulfill_resp", { oid = tostring(orderID), name = e and e.name, result = result,
                    reward = e and e.reward })
                if snap and result == Enum.CraftingOrderResult.Ok then
                    local ee = e
                    C_Timer.After(1.5, function()
                        local paid = GetMoney() - (snap.money or 0)
                        local got = {}
                        for id, b in pairs(snap.items) do local dlt = Count(id) - (b or 0); if dlt ~= 0 then got["i:" .. id] = dlt end end
                        for id, b in pairs(snap.cur) do local q = CurrencyQty(id); if q and b then got["c:" .. id] = q - b end end
                        tr.paid, tr.got = paid, got
                        local flags = {}
                        if ee.reward and math.abs(paid - ee.reward) > GOLD then
                            flags[#flags + 1] = ("оплата не совпала: пришло %s, ждали %s"):format(Gold(paid), Gold(ee.reward))
                        end
                        -- (02.11) предметы-награды покровителя приходят ПОЧТОЙ, не в сумки — их не проверяем
                        -- (по 142 сдачам: деньги всегда сходились до медяка, «награда не пришла» — ложное).
                        tr.flags = (#flags > 0) and flags or nil
                        -- дописать в строку журнала этого заказа
                        local log = DB().log
                        for i = #log, math.max(1, #log - 30), -1 do
                            local en = log[i]
                            if en and SameID(en.orderID, orderID) then
                                en.paid, en.rewardGot = paid, got
                                if tr.flags then
                                    en.flags = en.flags or {}
                                    for _, f in ipairs(tr.flags) do en.flags[#en.flags + 1] = f end
                                end
                                break
                            end
                        end
                        ee.rsnap = nil
                    end)
                end
            end
            if e then
                if result == Enum.CraftingOrderResult.Ok then
                    MarkDone(e)
                    -- (02.11) кнопка серая 2,5 с после сдачи (защита от двойных нажатий, игре нужно время)
                    pauseUntil = GetTime() + PAUSE_AFTER_DONE
                    C_Timer.After(PAUSE_AFTER_DONE + 0.1, function() if Refresh then Refresh() end end)
                    -- (02.11) очередь опустела → сами один раз жмём «Обновить» (проверка, что заказы не потерялись)
                    C_Timer.After(3, function()
                        if scanning or InCombatLockdown() or (GetTime() - autoScanAt) < 15 then return end
                        local left = CurrentEntry()
                        local cl = C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
                        if not left and not cl and ProfessionsFrame and ProfessionsFrame:IsShown() then
                            autoScanAt = GetTime()
                            Trace("autoscan", {})
                            OQ.Scan(true)
                        end
                    end)
                else
                    e.fulfilling = false
                    fulfillSent[tostring(orderID)] = nil
                    ns.Print("Очередь заказов: заказ не сдался (код " .. tostring(result) .. ").")
                end
            end
            C_Timer.After(1, SyncPresence)
        elseif event == "CRAFTINGORDERS_CLAIMED_ORDER_UPDATED" then
            C_Timer.After(0.2, OnClaimed)
        elseif event == "TRADE_SKILL_SHOW" then
            -- Сбор данных: открыл профессию → пробуем проверить заказы покровителей (как CraftSim
            -- подгружает заказы). Нет заказов / далеко от стола — ничего страшного, просто пропуск.
            profSession = { t = time(), who = PlayerKey(), ids = {} }
            C_Timer.After(1.5, function()
                if scanning or (GetTime() - lastScanAt) < 5 or InCombatLockdown() then return end
                local prof = Profession()
                if prof and C_TradeSkillUI.IsNearProfessionSpellFocus and C_TradeSkillUI.IsNearProfessionSpellFocus(prof) then
                    OQ.Scan(true)
                end
            end)
        elseif event == "TRADE_SKILL_CLOSE" then
            -- «Слепок» захода: какие заказы были доступны и какие из них сделаны за этот заход.
            local ps = profSession
            profSession = nil
            if ps and next(ps.ids) then
                local d = DB()
                d.sessions = d.sessions or {}
                local rec = { t = ps.t, tEnd = time(), who = ps.who, prof = ps.prof, ids = {}, done = {} }
                for id in pairs(ps.ids) do
                    rec.ids[#rec.ids + 1] = id
                    local o = d.seen and d.seen[id]
                    if o and o.done and o.done >= ps.t then rec.done[#rec.done + 1] = id end
                end
                d.sessions[#d.sessions + 1] = rec
                while #d.sessions > 300 do table.remove(d.sessions, 1) end
            end
        elseif event == "UI_ERROR_MESSAGE" then
            -- Красное сообщение игры сразу после нажатия «Сделать» — сохраняем в журнал (поиск причин «зависания»).
            local _, msg = ...
            -- (02.11) любое красное сообщение, пока открыта профессия и идёт работа очереди
            if autoChain and type(msg) == "string" and not IsSecret(msg) and ProfessionsFrame and ProfessionsFrame:IsShown() then
                Trace("ui_error", { msg = msg, oid = current and current.log and current.log.orderID })
            end
            if current and (GetTime() - (current.started or 0)) < 5 and type(msg) == "string" and not IsSecret(msg) then
                current.log.error = msg
                ns.Print("Очередь заказов: игра ответила — " .. msg)
            end
        elseif event == "CRAFTINGORDERS_CLAIMED_ORDER_REMOVED" then
            C_Timer.After(1, SyncPresence)
        elseif event == "CRAFTINGORDERS_CLAIM_ORDER_RESPONSE" then
            local result, orderID = ...
            local e = FindEntry(orderID)
            Trace("claim_resp", { oid = tostring(orderID), name = e and e.name, result = result,
                minQ = e and e.minQ, expQ = e and e.expQ, profit = e and e.profit, rule = e and e.rule })
            if e then
                e.claiming = false
                if result ~= Enum.CraftingOrderResult.Ok then
                    ns.Print("Очередь заказов: не удалось взять заказ (код " .. tostring(result) .. ").")
                    e.fatal = "Не удалось взять заказ"
                    ApplyRule(e)
                end
            end
        end
        SoftRefresh()
    end, ...)
    if not ok and ns.debug then print("|cFFFF3333RainonUI OrderQueue:|r", event, err) end
end)

-- Ручные крафты (для «Запоминать мои крафты»). Чужой код не трогаем — только слушаем.
if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe and hooksecurefunc then
    hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function(...)
        pcall(OQ.CaptureCraftCost, ...)   -- (02.11) цена реагентов для «Проки и золото»
        local ok, err = pcall(OnManualCraft, ...)
        if not ok and ns.debug then print("|cFFFF3333RainonUI OrderQueue:|r", err) end
    end)
end

ns.RegisterMessage("RAINON_DB_READY", function() DB() end)
ns.RegisterMessage("RAINON_REAPPLY", function() HookProfessions() end)
ns.RegisterEvent("ADDON_LOADED", function(name)
    if name == "Blizzard_Professions" then HookProfessions() end
end)

-- -------------------------------------------------------------------------
-- Замер сумок (16.10): ТОЛЬКО сумки с заказов и пучки трав (решение Миши — без лишнего).
-- Кнопка-макрос «Открыть сумку» (на окне «Знания и заряды») открывает сумку и в тот же
-- момент говорит аддону «запомни»: записываем, что выпало, до закрытия окна добычи.
-- Также ловим ручной клик по этим сумкам в сумках (C_Container.UseContainerItem).
-- RainonUIOrdersDB.bags[itemID] = { name, opened, money, drops = { ["i:ID"|"c:ID"] = { n, hits } },
--   recent = { {t, who, items, money} } (≤200) }.
-- -------------------------------------------------------------------------
local BAG_IDS = { 246585, 245650, 245651,    -- Artisan's Consortium Payout; Bouquet of Herbs (2 качества)
    -- (02.11) сумки профессий за «Пыл» (600) — «Излишки реагентов мастера-…»; ID из заметки Миши
    260534, -- алхимика
    260536, -- кузнеца
    260537, -- зачаровывателя
    260538, -- инженера
    260540, -- начертателя
    260541, -- ювелира
    260542, -- кожевника
    260545, -- портного
}
local BAG_SET = {}
for _, id in ipairs(BAG_IDS) do BAG_SET[id] = true end
-- Две кнопки: игра не даёт открыть сумку и траву одним макросом.
local BAG_BUTTONS = {
    { key = "Payout", text = "Сумка", ids = { 246585 }, macro = "/use item:246585" },
    { key = "Herbs",  text = "Травы", ids = { 245650, 245651 }, macro = "/use item:245650\n/use item:245651" },
}
local BAG_RECENT_MAX = 3000  -- цена сумки считается по последним 300 открытиям (скользящее окно)

local function BagsDB()
    local d = DB()
    d.bags = d.bags or {}
    d.bagWatch = nil   -- старый ключ (общий список) больше не нужен
    return d.bags
end

local session            -- { id, name, t, items = {}, money = 0, done }

-- Снимок сумок персонажа (включая сумку реагентов): itemID → количество.
-- Нужен, когда игра кладёт содержимое сразу в сумки, без окна добычи.
local function InvSnapshot()
    local inv = {}
    local last = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
    for bag = 0, last do
        local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (okN and Num(n) or 0) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and type(info) == "table" and info.itemID and not IsSecret(info.itemID) then
                inv[info.itemID] = (inv[info.itemID] or 0) + (Num(info.stackCount) or 1)
            end
        end
    end
    return inv
end

local function BagFinish()
    local o = session
    if not o or o.done then return end
    o.done = true
    session = nil
    local now = InvSnapshot()
    if (o.inv[o.id] or 0) - (now[o.id] or 0) ~= 1 then return end
    o.verified = o.how ~= "count" and o.looted and o.slots > 0 and o.cleared == o.slots
    o.money = 0 -- account gold deltas cannot be attributed to this bag
    -- След для проверки (последние 30 открытий, даже пустые).
    local d = DB()
    d.bagDebug = d.bagDebug or {}
    local nItems = 0
    for _ in pairs(o.items) do nItems = nItems + 1 end
    d.bagDebug[#d.bagDebug + 1] = { t = time(), id = o.id, looted = o.looted or false, bagUpd = o.bagUpd or 0,
        items = nItems, money = o.money, how = o.how }
    while #d.bagDebug > 30 do table.remove(d.bagDebug, 1) end
    -- Keep unconfirmed openings, but never value them as verified loot.
    local bags = BagsDB()
    local b = bags[o.id]
    if not b then b = { name = o.name, opened = 0, money = 0, drops = {}, recent = {} }; bags[o.id] = b end
    b.name = o.name or b.name
    b.opened = b.opened + 1
    b.money = b.money + o.money
    for k, n in pairs(o.verified and o.items or {}) do
        RememberName(tostring(k):match("^i:(%d+)"))
        local dr = b.drops[k]
        if not dr then dr = { n = 0, hits = 0 }; b.drops[k] = dr end
        dr.n = dr.n + n
        dr.hits = dr.hits + 1
    end
    local prices = {}
    for k in pairs(o.items) do local id = tonumber(k:match("^i:(%d+)")); if id then prices[k] = Price(id) end end
    b.recent[#b.recent + 1] = { t = time(), who = PlayerKey(), items = o.items, money = o.money,
        av = 2, verified = o.verified and true or false, source = "loot-slots", prices = prices }
    if OQ.BagValueReset then OQ.BagValueReset(o.id) end
    while #b.recent > BAG_RECENT_MAX do table.remove(b.recent, 1) end
end

-- «Эй, запомни»: открывается сумка id.
local function BagOpened(id, how, invBefore, goldBefore)
    if not BAG_SET[id] then return end
    local now = GetTime()
    if session and not session.done then
        if session.id == id and (now - session.t) < 0.5 then return end   -- тот же клик (Down+Up)
        BagFinish()
    end
    session = { id = id, name = ItemName(id), t = now, items = {}, money = 0, gold0 = goldBefore or GetMoney(),
                inv = invBefore or InvSnapshot(), how = how, pending = {}, slots = 0, cleared = 0 }
    local o = session
    C_Timer.After(2, function() if session == o then BagFinish() end end)   -- страховка
end

-- Какая сумка откроется по макросу кнопки: первая из её списка, что есть в сумках.
local function NextBag(ids)
    for _, id in ipairs(ids) do
        local okC, n = pcall(C_Item.GetItemCount, id)
        if okC and (Num(n) or 0) > 0 then return id end
    end
end

if C_Container and C_Container.UseContainerItem and hooksecurefunc then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" and not IsSecret(info.itemID) and BAG_SET[info.itemID] then
            BagOpened(info.itemID, "click")
        end
    end)
end

local bagEv = CreateFrame("Frame")
for _, name in ipairs({ "LOOT_READY", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "PLAYER_ENTERING_WORLD" }) do
    pcall(bagEv.RegisterEvent, bagEv, name)
end
bagEv:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then session = nil; return end
    local o = session
    if not o or o.done then return end
    pcall(function(...)
        if event == "LOOT_READY" then
            if o.looted then return end
            o.looted = true
            for i = 1, (GetNumLootItems() or 0) do
                local link = GetLootSlotLink(i)
                local _, _, qty, currencyID = GetLootSlotInfo(i)
                qty = Num(qty) or 1
                local cid = Num(currencyID)
                local iid = link and not IsSecret(link) and tonumber(link:match("item:(%d+)"))
                o.slots = o.slots + 1
                local key = cid and cid > 0 and ("c:" .. cid) or iid and ("i:" .. iid)
                if key then o.pending[i] = { key = key, qty = qty } end
            end
        elseif event == "LOOT_SLOT_CLEARED" then
            local slot = Num(...)
            local x = slot and o.pending[slot]
            if x then
                o.pending[slot] = nil
                o.cleared = o.cleared + 1
                o.items[x.key] = (o.items[x.key] or 0) + x.qty
            end
        elseif event == "LOOT_CLOSED" then
            -- деньги из сумки приходят при сборе добычи — берём разницу чуть позже
            C_Timer.After(0.3, function() if session == o then BagFinish() end end)
        end
    end, ...)
end)

-- (02.11) Ловим открытие сумки, КАК БЫ её ни открыли (макрос /use, клик, другой аддон).
-- 1) ITEM_LOCK_CHANGED: игра блокирует слот с предметом в момент использования — ещё ДО
--    того, как сумка исчезнет и придёт содержимое; снимок сумок делаем здесь.
-- 2) Запасной путь: после обновления сумок число сумок уменьшилось на 1, а сессии нет —
--    берём снимок, сделанный до этого обновления (lastInv), и записываем открытие.
local lastInv, lastGold
local lockEv = CreateFrame("Frame")
pcall(lockEv.RegisterEvent, lockEv, "ITEM_LOCK_CHANGED")
pcall(lockEv.RegisterEvent, lockEv, "BAG_UPDATE_DELAYED")
pcall(lockEv.RegisterEvent, lockEv, "PLAYER_ENTERING_WORLD")
lockEv:SetScript("OnEvent", function(_, event, bag, slot)
    pcall(function()
        if event == "ITEM_LOCK_CHANGED" then
            bag, slot = Num(bag), Num(slot)
            if not (bag and slot) then return end
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and type(info) == "table" and info.isLocked and not IsSecret(info.itemID) and BAG_SET[info.itemID]
                and not (GetCursorInfo and GetCursorInfo()) then   -- взял в курсор (перекладывает) — не открытие
                BagOpened(info.itemID, "lock")   -- предмет ещё в сумке: снимок «до» берём сейчас
            end
        elseif event == "BAG_UPDATE_DELAYED" then
            local now = InvSnapshot()
            if lastInv and not (session and not session.done) then
                for _, id in ipairs(BAG_IDS) do
                    if (lastInv[id] or 0) - (now[id] or 0) == 1 then
                        BagOpened(id, "count", lastInv, lastGold)
                        local o = session
                        C_Timer.After(1.0, function() if session == o then BagFinish() end end)
                        break
                    end
                end
            end
            lastInv, lastGold = now, GetMoney()
        elseif event == "PLAYER_ENTERING_WORLD" then
            lastInv, lastGold = InvSnapshot(), GetMoney()
        end
    end)
end)

-- (02.11) Кнопки «Сумка» и «Травы» убраны (просьба Миши): макросы 0.0_/0.1_RainonUI работают сами
-- (/use + запись открытия по ITEM_LOCK_CHANGED). Старый код — Архив/BagButtons.lua.

-- (02.11) Список покупок в Auctionator — КОПИЛКА на несколько столов (просьба Миши, по образцу CraftSim):
-- у стола жмёшь «Покупки» → в список добавляется, чего не хватает на заказы «к работе» ЭТОЙ профессии
-- (повторное нажатие у того же стола заменяет её часть, а не удваивает). У другого стола — добавляется его часть.
-- На аукционе (и на почте — купленное не-товарами приходит письмом) следим, сколько предмета прибавилось
-- в сумках: купил → строка уменьшается, купил всё → строка исчезает. Shift + «Покупки» — очистить список.
-- Имя начинается с «!» — Auctionator сортирует списки по алфавиту, так наш стоит первым (CraftSim — «C…»).
-- Хранение: RainonUIOrdersDB.shop = { [itemID] = { [профессия] = сколько купить } }.
local SHOP_LIST = "!RainonUI — покупки"
do
local function ShopDB() local d = DB(); d.shop = d.shop or {}; return d.shop end
local function ShopTotal(byProf) local t = 0; for _, n in pairs(byProf) do t = t + n end; return t end
-- строка поиска Auctionator для предмета (n = nil — без количества, для поиска строки в списке)
local function TermFor(id, n)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not (api and api.ConvertToSearchString and name and name ~= "") then return nil end
    local term = { searchString = name, isExact = true, quantity = n }
    local rq = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local okQ, q = false, nil
    if rq then okQ, q = pcall(rq, id) end
    if okQ and Num(q) and Num(q) >= 1 then term.tier = Num(q) end
    local ok, str = pcall(api.ConvertToSearchString, CALLER, term)
    return (ok and type(str) == "string") and str or nil
end
-- записать список в Auctionator по копилке (пустая копилка — пустой список)
local function WriteList(silent)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.CreateShoppingList and api.ConvertToSearchString) then return false end
    local terms, noName = {}, 0
    for id, byProf in pairs(ShopDB()) do
        local n = ShopTotal(byProf)
        if n > 0 then
            local str = TermFor(id, n)
            if str then terms[#terms + 1] = str else noName = noName + 1 end
        else
            ShopDB()[id] = nil
        end
    end
    local ok, err = pcall(api.CreateShoppingList, CALLER, SHOP_LIST, terms)
    if not ok and not silent then ns.Print("Очередь заказов: Auctionator не создал список — " .. tostring(err)) end
    return ok, #terms, noName
end
-- (04.11) название профессии стола — в начале сообщения, цветом способности (как ссылка на заклинание)
local function ProfLabel()
    local nm
    local okB, bi = pcall(function() return C_TradeSkillUI.GetBaseProfessionInfo() end)
    if okB and bi and bi.professionName and bi.professionName ~= "" then nm = bi.professionName end
    if not nm then
        local okC, ci = pcall(function() return C_TradeSkillUI.GetChildProfessionInfo() end)
        nm = okC and ci and (ci.parentProfessionName or ci.professionName) or nil
    end
    return ns.C("71d5ff", nm or "Профессия")
end
function OQ.MakeShoppingList()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
        ns.Print("Очередь заказов: Auctionator не включён — список покупок не создать.")
        return
    end
    if IsShiftKeyDown() then
        DB().shop = {}
        WriteList()
        ns.Print("Список покупок: " .. ns.C("ffd100", "очищен"))
        return
    end
    -- нужно по профессиям столов, у которых сейчас стоим (заказы «к работе» в очереди)
    local need = {}   -- [prof][itemID] = сколько нужно
    for _, e in ipairs(entries) do
        if e.ok and e.state == "wait" and e.plan then
            local pk = tostring(e.prof or "?")
            need[pk] = need[pk] or {}
            for id, n in pairs(e.plan) do need[pk][id] = (need[pk][id] or 0) + n end
        end
    end
    local shop = ShopDB()
    local added = 0
    for pk, items in pairs(need) do
        for _, byProf in pairs(shop) do byProf[pk] = nil end          -- часть этого стола — заново
        for id, n in pairs(items) do
            local miss = n - Count(id)
            if miss > 0 then shop[id] = shop[id] or {}; shop[id][pk] = miss; added = added + 1 end
        end
    end
    local ok, nTerms, noName = WriteList()
    if not ok then return end
    -- (04.11, Миша) коротко: «Алхимия - Список покупок: Обновлён (N)», «Обновлён» зелёным
    if added == 0 then
        ns.Print(ProfLabel() .. " - Список покупок: " .. ns.C("1eff00", "всего хватает") ..
            (nTerms > 0 and (" (в списке " .. nTerms .. " от других столов)") or ""))
    else
        ns.Print(ProfLabel() .. " - Список покупок: " .. ns.C("1eff00", "Обновлён") .. " (" .. nTerms .. ")" ..
            (noName > 0 and (" — ещё " .. noName .. " без названия, нажми ещё раз") or ""))
    end
    Trace("shopping", { n = nTerms, added = added })
end
-- (04.11, Миша: «как в CraftSim, не придумывай») Купленное убираем из списка СРАЗУ после покупки на аукционе —
-- точно как CraftSim (Modules/Shopping/Shopping.lua): ловим подтверждение покупки товара
-- (hooksecurefunc C_AuctionHouse.ConfirmCommoditiesPurchase → itemID, сколько), на COMMODITY_PURCHASE_SUCCEEDED
-- уменьшаем строку в копилке и правим ЭТУ строку списка Auctionator (AlterShoppingListItem / DeleteShoppingListItem),
-- список не пересоздаём (раньше пересоздавали по счёту сумок — Auctionator сбрасывал поиск и строки «не пропадали»).
-- Купил всё — строка исчезает; купил всё по списку — список пустой.
local pendingBuy
local function BoughtItem(id, got)
    local shop = ShopDB()
    local byProf = shop[id]
    if not byProf then return end
    local before = ShopTotal(byProf)
    for pk, n in pairs(byProf) do   -- уменьшаем, начиная с любой профессии
        local take = math.min(n, got)
        byProf[pk], got = n - take, got - take
        if byProf[pk] <= 0 then byProf[pk] = nil end
        if got <= 0 then break end
    end
    local left = ShopTotal(byProf)
    if left <= 0 then shop[id] = nil end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local done = false
    if api and api.GetShoppingListItems and api.AlterShoppingListItem and api.DeleteShoppingListItem then
        local base = TermFor(id, nil)
        local okL, items = pcall(api.GetShoppingListItems, CALLER, SHOP_LIST)
        if base and okL and type(items) == "table" then
            for _, str in ipairs(items) do
                if type(str) == "string" and str:sub(1, #base) == base then
                    if left > 0 then
                        local new = TermFor(id, left)
                        done = new and pcall(api.AlterShoppingListItem, CALLER, SHOP_LIST, str, new) or false
                    else
                        done = pcall(api.DeleteShoppingListItem, CALLER, SHOP_LIST, str)
                    end
                    break
                end
            end
        end
    end
    if not done then WriteList(true) end   -- строку не нашли / старый Auctionator — переписываем список целиком
    Trace("shop_bought", { id = id, before = before, left = left, inPlace = done })
end
if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase and hooksecurefunc then
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
        pendingBuy = { id = Num(itemID), n = Num(quantity) or 0 }
    end)
end
ns.RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function()
    local b = pendingBuy; pendingBuy = nil
    if b and b.id and b.n > 0 then BoughtItem(b.id, b.n) end
end)
ns.RegisterEvent("COMMODITY_PURCHASE_FAILED", function() pendingBuy = nil end)
end

-- Макросы для панели команд: имена 0.0_/0.1_RainonUI — встают ПЕРЕД макросами паладина (1.x_RainonUI).
-- Иконка-заглушка «?» (134400). Общие макросы (лимит 120), как у паладина.
-- (02.11) Макросы больше НЕ нажимают наши кнопки (/click не открывал сумки) — сами /use.
-- Что открылось, аддон узнаёт сам: по блокировке предмета в сумке (ITEM_LOCK_CHANGED)
-- и запасным путём — по уменьшению числа сумок (см. «Ловим открытие» ниже).
local BAG_MACROS = {
    { name = "0.0_RainonUI", body = "/use item:246585" },                      -- Сумка (Оплата Консорциума)
    { name = "0.1_RainonUI", body = "/use item:245650\n/use item:245651" },    -- Травы: сначала кач.1, потом кач.2
    { name = "0.2_RainonUI", body = "/rsorders next" },                        -- (02.11) «Дальше» в очереди заказов
}
function OQ.CreateBagMacros()
    if InCombatLockdown() then ns.Print("нельзя создавать макросы в бою."); return end
    local created, updated, failed = 0, 0, 0
    for _, mac in ipairs(BAG_MACROS) do
        local idx = GetMacroIndexByName and GetMacroIndexByName(mac.name) or 0
        if idx and idx > 0 then
            if pcall(EditMacro, idx, mac.name, 134400, mac.body) then updated = updated + 1 else failed = failed + 1 end
        elseif ((GetNumMacros and GetNumMacros()) or 0) >= 120 then
            failed = failed + 1
        else
            if pcall(CreateMacro, mac.name, 134400, mac.body, false) then created = created + 1 else failed = failed + 1 end
        end
    end
    ns.Print(("макросы: создано %d, обновлено %d%s. 0.0_RainonUI — Сумка, 0.1_RainonUI — Травы, 0.2_RainonUI — «Дальше» (" ..
        ns.C("FFFF00", "/macro") .. ", перетащи на панель)."):format(created, updated,
        failed > 0 and (", не удалось " .. failed .. " — нет места в общих макросах") or ""))
end

-- Средняя цена одной сумки по Auctionator (+ деньги). Валюта отдельно (не в золоте).
-- (02.11) Цена ПОСЛЕДНЕГО открытия сумки: что выпало × текущие цены Auctionator (+ деньги).
function OQ.BagLastValue(id)
    local b = BagsDB()[id]
    local r = b and b.recent and b.recent[#b.recent]
    if not r then return nil end
    local sum = r.money or 0
    for k, cnt in pairs(r.items or {}) do
        local iid = tonumber(tostring(k):match("^i:(%d+)"))
        local p = iid and Price(iid)
        if p then sum = sum + p * cnt end
    end
    return sum
end

-- (02.11) кэш на 30с: строки очереди спрашивают цену сумки при каждой перерисовке.
local bagValCache = {}
function OQ.BagValueReset(id) if id then bagValCache[id] = nil else bagValCache = {} end end
local BagValueRaw
function OQ.BagValue(id)
    local c = bagValCache[id]
    local now = GetTime()
    if c and (now - c.t) < 30 then return c[1], c[2], c[3], c[4] end
    local v, np, b, n = BagValueRaw(id)
    bagValCache[id] = { t = now, v, np, b, n }
    return v, np, b, n
end
BagValueRaw = function(id)
    local b = BagsDB()[id]
    if not b then return nil end
    local sum, missing, n = 0, 0, 0
    for _, r in ipairs(b.recent or {}) do
        if r.av == 2 and r.verified then
            n = n + 1
            sum = sum + (r.money or 0)
            for k, q in pairs(r.items or {}) do
                local iid = tonumber(tostring(k):match("^i:(%d+)"))
                if iid then
                    local p = Price(iid)
                    if p then sum = sum + p*q else missing = missing+1 end
                end
            end
        end
    end
    if n == 0 or missing > 0 then return nil, missing, b, n end
    return sum/n, 0, b, n
end

-- Подсказка сумки: сколько раз открыли и средняя цена.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if not data or IsSecret(data.id) then return end
        local id = Num(data.id)
        if not id then return end
        -- (02.11) было «id and OQ.BagValue(id)» — так Lua отдаёт только ПЕРВОЕ значение, b = nil → ошибка
        local v, noPrice, b = OQ.BagValue(id)
        if not (v and b) then return end
        tt:AddLine(("RainonUI: открыто %d · в среднем ~%s за штуку%s"):format(b.opened, Gold(v),
            (noPrice and noPrice > 0) and (" (без цены: " .. noPrice .. ")") or ""), 0.4, 0.8, 1)
    end)
end

-- /rsorders bags — сводка по сумкам в чат.
function OQ.BagReport()
    local any = false
    for id, b in pairs(BagsDB()) do
        any = true
        local v, noPrice = OQ.BagValue(id)
        ns.Print(("%s: открыто %d, в среднем ~%s (деньги ~%s)%s"):format(b.name or ItemName(id), b.opened,
            Gold(v), Gold(b.money / math.max(b.opened, 1)), (noPrice and noPrice > 0) and (", без цены: " .. noPrice) or ""))
        local list = {}
        for k, dr in pairs(b.drops) do list[#list + 1] = { k = k, dr = dr } end
        table.sort(list, function(a, c) return a.dr.n > c.dr.n end)
        for i = 1, math.min(8, #list) do
            local k, dr = list[i].k, list[i].dr
            local iid = tonumber(k:match("^i:(%d+)"))
            local nm
            if iid then nm = ItemName(iid) else
                local ci = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(tonumber(k:sub(3)))
                nm = (ci and ci.name) or k
            end
            ns.Print(("   %s: всего %d, выпадало в %d из %d (в среднем %.1f)"):format(nm, dr.n, dr.hits, b.opened, dr.n / b.opened))
        end
    end
    if not any then ns.Print("Очередь заказов: сумки ещё не открывались (или модуль выключен).") end
end

-- -------------------------------------------------------------------------
-- Плашка у окна профессии (02.11, идея Миши) — дочерний фрейм ProfessionsFrame
-- (прячется вместе с окном), считается при открытии профессии, без таймеров.
--   * «Предметы профессии» — с любой профессией: [Раскалывание сущности — только наложение чар]
--     [Харанирский флакон] Звезда / Индикатор / Коллектор / Наводчик, иконка + сколько есть.
--     Видна только на вкладке крафта. Флакон и раскалывание перенесены сюда 02.11 из Tools.lua.
--   (Плашка «Средняя цена» с букетами удалена 02.11 по просьбе Миши: замеры букета теперь
--    две строки под строкой Auctionator в окне рецепта — см. UpdateAuctLine.)
-- Перетаскивается мышью; место — смещение от левого верхнего угла окна профессии
-- (settings.itemPanelPos). Закрепить — галка во вкладке «Профессии»
-- (ns.db.features.profPanelsLock).
-- ПРАВИЛО (урок 02.11): текст в плашке НЕ переносится — ширина плашки считается по
-- самой длинной строке (GetStringWidth), а не наоборот. Иначе строки наезжают друг на друга.
-- -------------------------------------------------------------------------
local PANEL_PAD, LINE_H = 6, 14

local function PanelsLocked()
    return ns.db and ns.db.features and ns.db.features.profPanelsLock and true or false
end

local function PlacePanel(f)
    local pf = ProfessionsFrame
    if not (f and pf) then return end
    local pos = DB().settings[f.posKey]
    f:ClearAllPoints()
    if pos and pos.x and pos.y then
        f:SetPoint("TOPLEFT", pf, "TOPLEFT", pos.x, pos.y)
    else
        f:SetPoint(f.defPoint, pf, f.defRel, f.defX, 4)
    end
end

-- Общая основа плашки: тёмный фон, заголовок, перетаскивание с запоминанием места.
local function NewPanel(name, title, posKey, defPoint, defRel, defX, tip)
    local f = CreateFrame("Frame", name, ProfessionsFrame)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f.posKey, f.defPoint, f.defRel, f.defX = posKey, defPoint, defRel, defX
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    f.bg = bg
    -- (02.11) иконка «инфо» слева от заголовка: клик — настройки, вкладка «Профессии» (там закрепить)
    f.info = CreateFrame("Button", nil, f)
    f.info:SetSize(14, 14)
    f.info:SetPoint("TOPLEFT", PANEL_PAD - 2, -3)
    f.info.tex = f.info:CreateTexture(nil, "ARTWORK")
    f.info.tex:SetAllPoints()
    f.info.tex:SetTexture("Interface\\Common\\help-i")   -- тот же значок «i», что в настройках (Options.lua)
    f.info:SetScript("OnClick", function()
        if ns.OpenOptions then ns.OpenOptions(3) end   -- 3 = вкладка «Профессии»
    end)
    f.info:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Настройки панели")
        GameTooltip:AddLine("Открыть настройки → «Профессии»: закрепить панель и описание.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.info:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("LEFT", f.info, "RIGHT", 3, 0)
    f.title:SetWordWrap(false)
    f.title:SetText(ns.C("FFD100", title))
    f:SetScript("OnDragStart", function(self)
        if PanelsLocked() then return end
        if self.onDrag then self.onDrag(self, true) end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.onDrag then C_Timer.After(0, function() self.onDrag(self, false) end) end
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        local pf = ProfessionsFrame
        local l, t, pl, pt = self:GetLeft(), self:GetTop(), pf and pf:GetLeft(), pf and pf:GetTop()
        if l and t and pl and pt then
            DB().settings[self.posKey] = { x = math.floor(l - pl + 0.5), y = math.floor(t - pt + 0.5) }
        end
        PlacePanel(self)
    end)
    f.tip = tip
    PlacePanel(f)
    return f
end

-- (02.11) Подсказка плашки — одна строка; описание перенесено в настройки («Профессии»).
local function PanelTip(self)
    if PanelsLocked() then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Перетащи панель в удобное место на экране.", 1, 1, 1, true)
    GameTooltip:Show()
end

-- (02.11) Вид плашки: не закреплена — фон, иконка «инфо» и заголовок; закреплена — только содержимое.
local function ApplyPanelLook(f)
    if not f then return end
    local locked = PanelsLocked()
    f.bg:SetShown(not locked)
    f.info:SetShown(not locked)
    f.title:SetShown(not locked)
    f:EnableMouse(not locked)   -- закреплена: пустое место плашки не перехватывает клики
end

-- ---- «Предметы профессии» (любая профессия) ----
-- Готовые предметы (ID — Wowhead / Warcraft Wiki) и части, из 5 которых они собираются.
local PROF_ITEMS = {
    { id = 246450 },                    -- Золотая звезда консорциума ремесленников (Мастерство +50)
    { id = 247788, part = 260630 },     -- Индикатор изобретательности ← 5 × Идентификатор изобретательности
    { id = 247724, part = 247719 },     -- Коллектор перепроизводства ← 5 × Матрица перепроизводства
    { id = 247726, part = 247725 },     -- Наводчик находчивости ← 5 × Набойка находчивости
}
local ICON, ICON_GAP = 32, 4
local itemPanel

local function ItemTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) else GameTooltip:AddLine(ItemName(self.itemID)) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Есть (сумки, банк, отряд):", tostring(Count(self.itemID)), 1, 0.82, 0, 1, 1, 1)
    if self.part then
        local n = Count(self.part)
        GameTooltip:AddDoubleLine("Частей «" .. ItemName(self.part) .. "»:", ("%d (можно собрать %d)"):format(n, math.floor(n / 5)),
            1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
end

-- ---- Баффы крафта в плашке (02.11, перенесено из Tools.lua по просьбе Миши) ----
-- Слева от Золотой звезды: [Раскалывание сущности] (только наложение чар) и [Харанирский флакон].
-- Нет баффа → слот светится; клик — как раньше: флакон — выпить выбранный (Настройки → Профессии),
-- раскалывание — проверенный макрос «CraftRecipe(1235731) + /use частица».
-- БЕЗОПАСНОСТЬ: кликает невидимая secure-кнопка. Она дочь своего держателя на UIParent и НЕ
-- привязана к плашке/окну профессии — иначе окно Blizzard стало бы «защищённым» и не
-- закрывалось бы в бою. Кнопку ставим поверх слота по экранным координатам и двигаем/прячем
-- только вне боя. В бою держатель прячется сам (драйвер состояния) — случайного клика не будет.
-- Всё про баффы — в одной таблице BF: у главного блока файла предел 200 локальных (Lua 5.1).
local BF = { pending = false, auraQ = false }
do
local PHIAL_SPELL, ESSENCE_SPELL, SHATTER_RECIPE = 1239755, 1235733, 1235731
local BUFF_DEFS = {
    { key = "prof_essence", spell = ESSENCE_SPELL, fallback = 7548988, cfg = "shatterEssence", enchOnly = true,
      title = "Раскалывание сущности", hint = "Клик — расколоть выбранную частицу (выбор: Настройки → Профессии)." },
    { key = "prof_phial", spell = PHIAL_SPELL, fallback = 134756, cfg = "phialQuality",
      title = "Харанирский флакон", hint = "Клик — выпить выбранный флакон (выбор: Настройки → Профессии)." },
}
local buffHolder, buffBtns = nil, {}

local function CurrentProfession()
    local ok, res = pcall(function()
        local info = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
        if (not info or not info.profession) and C_TradeSkillUI.GetBaseProfessionInfo then
            info = C_TradeSkillUI.GetBaseProfessionInfo()
        end
        return info and Num(info.profession)
    end)
    return ok and res or nil
end

local function HasBuff(spell)
    local a = ns.GetPlayerAura and ns.GetPlayerAura(spell)
    if IsSecret(a) or a == nil then return false end
    return true
end

local function BagCount(item)
    return item and Num(C_Item.GetItemCount(item, false, false, false, false)) or 0
end

-- Resolve the configured item again on click and target its exact bag slot.
local function SetBagAction(button, def, item)
    button:SetAttribute("type", nil)
    if not (def and item) then return end
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or Enum.BagIndex.ReagentBag
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if Num(C_Container.GetContainerItemID(bag, slot)) == item then
                local location = bag .. " " .. slot
                if def.enchOnly then
                    button:SetAttribute("macrotext", "/run C_TradeSkillUI.CraftRecipe(" .. SHATTER_RECIPE .. ")\n/use " .. location)
                    button:SetAttribute("type", "macro")
                else
                    button:SetAttribute("item", location)
                    button:SetAttribute("type", "item")
                end
                return
            end
        end
    end
end

local function BuffTip(slot, owner)
    local def = slot.def
    GameTooltip:SetOwner(owner or slot, "ANCHOR_TOP")
    GameTooltip:SetText(def.title, 1, 1, 1)
    if slot.need then
        GameTooltip:AddLine("Баффа нет. " .. def.hint, 1, 0.82, 0, true)
    else
        GameTooltip:AddLine("Бафф уже есть — клик отключён.", 0.6, 1, 0.6, true)
    end
    local item = ns.db and ns.db.tools and ns.db.tools[def.cfg]
    if item then
        GameTooltip:AddDoubleLine("Выбрано: " .. ItemName(item), "в сумках: " .. tostring(slot.have or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function SlotGlow(b)
    local glow = b:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    local pad = b:GetWidth() * 0.28
    glow:SetPoint("TOPLEFT", -pad, pad)
    glow:SetPoint("BOTTOMRIGHT", pad, -pad)
    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local al = ag:CreateAnimation("Alpha")
    al:SetFromAlpha(1); al:SetToAlpha(0.35); al:SetDuration(0.7)
    glow:Hide()
    b.SetGlow = function(_, on)
        glow:SetShown(on)
        if on then ag:Play() else ag:Stop() end
    end
end

-- Secure-кнопки: создаём один раз, только вне боя.
local function MakeBuffButtons()
    if buffHolder or InCombatLockdown() then return end
    buffHolder = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    buffHolder:SetAllPoints(UIParent)
    buffHolder:SetFrameStrata("HIGH")
    RegisterStateDriver(buffHolder, "visibility", "[combat] hide; show")
    for i, def in ipairs(BUFF_DEFS) do
        local sb = CreateFrame("Button", "RainonUIBuffBtn" .. i, buffHolder, "SecureActionButtonTemplate")
        sb:SetFrameStrata("HIGH")
        sb:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        sb:SetScript("PreClick", function(self)
            if InCombatLockdown() then return end
            local slot = self.slot
            local tools = ns.db.tools
            local active = ns.ProfEnabled() and slot and slot:IsVisible() and ProfessionsFrame and ProfessionsFrame:IsShown()
                and tools[def.key] ~= false and not HasBuff(def.spell)
                and (not def.enchOnly or CurrentProfession() == Enum.Profession.Enchanting)
            SetBagAction(self, active and def, tools[def.cfg])
        end)
        local hl = sb:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
        sb:SetScript("OnEnter", function(self) if self.slot then BuffTip(self.slot, self) end end)
        sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        sb:Hide()
        buffBtns[i] = sb
    end
end

-- Поставить/спрятать secure-кнопки по текущему виду плашки. В бою — отложить до выхода из боя.
local function SyncBuffButtons()
    if InCombatLockdown() then BF.pending = true; return end
    BF.pending = false
    MakeBuffButtons()
    local f = itemPanel
    for i in ipairs(BUFF_DEFS) do
        local sb = buffBtns[i]
        local b = f and f.buffs and f.buffs[i]
        if sb then
            local x, y
            if b and f:IsVisible() and b:IsShown() and b.need and b.have > 0 and not f.dragging then x, y = b:GetCenter() end
            if x and y then
                local sc = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                sb:ClearAllPoints()
                sb:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * sc, y * sc)
                sb:SetSize(b:GetWidth() * sc, b:GetHeight() * sc)
                sb:SetFrameLevel(f:GetFrameLevel() + 20)
                sb.slot, sb.lastX, sb.lastY = b, x, y
                sb:Show()
            else
                sb.slot = nil
                sb:Hide()
            end
        end
    end
end
BF.DEFS, BF.Glow, BF.Tip, BF.Sync = BUFF_DEFS, SlotGlow, BuffTip, SyncBuffButtons
BF.CurrentProfession, BF.HasBuff, BF.btns = CurrentProfession, HasBuff, buffBtns
BF.BagCount, BF.SetBagAction = BagCount, SetBagAction
OQ.ProfessionBuffs = BF
end

local function BuildItemPanel()
    if itemPanel or not ProfessionsFrame then return itemPanel end
    local f = NewPanel("RainonUIProfItems", "Предметы профессии", "itemPanelPos", "BOTTOMRIGHT", "TOPRIGHT", -4,
        "Сколько есть усилителей крафта (сумки + банк + банк отряда). Наведи на иконку — подробности и сколько частей.")
    f.tipTitle = "Предметы профессии"
    f.slots = {}
    for i, def in ipairs(PROF_ITEMS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(ICON, ICON)
        b:SetPoint("TOPLEFT", PANEL_PAD + (i - 1) * (ICON + ICON_GAP), -4 - LINE_H - 2)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        b.itemID, b.part = def.id, def.part
        b:SetScript("OnEnter", ItemTip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- перетаскивание за иконку тоже двигает плашку
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
        b:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
        f.slots[i] = b
    end
    -- (02.11) слоты баффов крафта (места расставляет UpdateItemPanel — раскалывание есть не всегда)
    f.buffs = {}
    for i, def in ipairs(BF.DEFS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(ICON, ICON)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        b.def = def
        BF.Glow(b)
        b:SetScript("OnEnter", function(self) BF.Tip(self) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
        b:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
        b:Hide()
        f.buffs[i] = b
    end
    f.onDrag = function(self, moving) self.dragging = moving; BF.Sync() end
    f:HookScript("OnHide", function() BF.Sync() end)
    -- окно профессии могли подвинуть — проверяем раз в 0,25 с, пока плашка видна (только вне боя)
    local acc = 0
    f:HookScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.25 then return end
        acc = 0
        if InCombatLockdown() or f.dragging then return end
        for i, sb in ipairs(BF.btns) do
            local b = f.buffs[i]
            local want = b and b:IsShown() and b.need and b.have > 0
            if want ~= (sb:IsShown() and true or false) then BF.Sync(); return end
            if want then
                local x, y = b:GetCenter()
                if x and (math.abs(x - (sb.lastX or 0)) > 0.5 or math.abs(y - (sb.lastY or 0)) > 0.5) then BF.Sync(); return end
            end
        end
    end)
    f:SetScript("OnEnter", PanelTip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    itemPanel = f
    return f
end

-- (02.11) Плашка видна ТОЛЬКО на вкладке крафта («Рецепты» = ProfessionsFrame.CraftingPage),
-- как «Знания и заряды»: на «Клиент»/«Специализации» прячется.
function BF.OnCraftTab()
    local cp = ProfessionsFrame and ProfessionsFrame.CraftingPage
    return cp and cp:IsShown() and true or false
end
local function UpdateItemPanel()
    if not ns.ProfEnabled() or not (ProfessionsFrame and ProfessionsFrame:IsShown())
        or (ns.db and ns.db.features and ns.db.features.profItemsPanel == false) or not BF.OnCraftTab() then
        if itemPanel then itemPanel:Hide() end
        return
    end
    local f = BuildItemPanel()
    if not f then return end
    -- (02.11) один раз снимаем «закреплено»: плашка стала шире (флакон и раскалывание) — переставить
    local feat = ns.db and ns.db.features
    if feat and not feat.profLockReset1102 then feat.profPanelsLock = false; feat.profLockReset1102 = true end
    local order = {}
    local tools = ns.db and ns.db.tools or {}
    local ench = BF.CurrentProfession() == Enum.Profession.Enchanting
    for i, def in ipairs(BF.DEFS) do
        local b = f.buffs[i]
        local show = tools[def.key] ~= false and (not def.enchOnly or ench)
        b:SetShown(show and true or false)
        if show then
            order[#order + 1] = b
            b.icon:SetTexture((ns.GetSpellTexture and ns.GetSpellTexture(def.spell)) or def.fallback)
            local item = tools[def.cfg]
            local n = BF.BagCount(item)
            b.have = n
            b.count:SetText(tostring(n))
            if n == 0 then b.count:SetTextColor(1, 0.25, 0.25) else b.count:SetTextColor(1, 1, 1) end
            b.need = not BF.HasBuff(def.spell)
            b:SetGlow(b.need)
            b.icon:SetAlpha(b.need and 1 or 0.6)
        else
            b.need = false
            b:SetGlow(false)
        end
    end
    for _, b in ipairs(f.slots) do
        order[#order + 1] = b
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(b.itemID)
        b.icon:SetTexture(icon or 134400)
        local n = Count(b.itemID)
        b.icon:SetDesaturated(n == 0)
        b.count:SetText(tostring(n))
        if n == 0 then b.count:SetTextColor(1, 0.25, 0.25) else b.count:SetTextColor(1, 1, 1) end
    end
    for i, b in ipairs(order) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", PANEL_PAD + (i - 1) * (ICON + ICON_GAP), -4 - LINE_H - 2)
    end
    local iconsW = #order * ICON + (#order - 1) * ICON_GAP
    f:SetSize(math.max(iconsW, math.ceil(f.title:GetStringWidth()) + 17) + PANEL_PAD * 2, 4 + LINE_H + 2 + ICON + PANEL_PAD)
    ApplyPanelLook(f)
    f:Show()
    BF.Sync()
end

-- (02.11) Строка под текстом Auctionator у рецепта «Букет трав» («Чтобы создать / Доход / Самая
-- дешёвая стоимость…»): средняя цена содержимого букета по нашим замерам, кач.1 и кач.2.
-- Наша строка — дочерняя у рамки Auctionator (AuctionatorCraftingInfoProfessionsFrame), поэтому
-- прячется вместе с ней; обновляем, когда Auctionator пересчитывает свой текст (UpdateTotal).
local AL = {}   -- строки под Auctionator: AL.l1, AL.l2, AL.hooked
local function UpdateAuctLine()
    local af = _G.AuctionatorCraftingInfoProfessionsFrame
    if not (af and AL.l1 and AL.l2) then return end
    local form = af:GetParent()
    local ok, info = pcall(function() return form and form.GetRecipeInfo and form:GetRecipeInfo() end)
    local rid = ok and info and Num(info.recipeID)
    if rid ~= (ns.Roster and ns.Roster.HERBS_RECIPE) then AL.l1:Hide(); AL.l2:Hide(); return end
    local parts, last = {}, {}
    for _, row in ipairs({ { id = 245650, q = 1 }, { id = 245651, q = 2 } }) do
        local v, _, b = OQ.BagValue(row.id)
        parts[#parts + 1] = Q(row.q, nil, row.id) .. " " .. (v and ("~%s (%d)"):format(Gold(v), b.opened) or ns.C("808080", "нет замеров"))
        -- (02.11) вторая строка: сколько стоило содержимое последнего открытого букета
        local lv = OQ.BagLastValue and OQ.BagLastValue(row.id)
        last[#last + 1] = Q(row.q, nil, row.id) .. " " .. (lv and Gold(lv) or ns.C("808080", "—"))
    end
    AL.l1:SetText("Наши замеры, букет: " .. table.concat(parts, "  ·  "))
    AL.l1:Show()
    AL.l2:SetText("Последнее открытие: " .. table.concat(last, "  ·  "))
    AL.l2:Show()
end
local function HookAuctionator()
    if AL.hooked then return end
    local af = _G.AuctionatorCraftingInfoProfessionsFrame
    if not af then return end
    AL.hooked = true
    AL.l1 = af:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    AL.l1:SetPoint("TOPLEFT", af, "BOTTOMLEFT", 0, -2)
    AL.l1:SetJustifyH("LEFT")
    AL.l1:SetWordWrap(false)
    AL.l2 = af:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    AL.l2:SetPoint("TOPLEFT", AL.l1, "BOTTOMLEFT", 0, -2)
    AL.l2:SetJustifyH("LEFT")
    AL.l2:SetWordWrap(false)
    if af.UpdateTotal then hooksecurefunc(af, "UpdateTotal", function() pcall(UpdateAuctLine) end) end
    af:HookScript("OnShow", function() pcall(UpdateAuctLine) end)
end

-- (02.11) Сами кладём ЗАВЕРШАЮЩИЕ реагенты в окно крафта Blizzard для выбранного рецепта
-- (Настройки → Профессии, по умолчанию «Зелье безрассудства»). Порядок: Коллектор
-- перепроизводства → Индикатор изобретательности → Наводчик находчивости (Звезду не трогаем).
-- Делаем ровно как сама Blizzard при выборе из списка слота (Blizzard_ProfessionsRecipeSchematicForm,
-- OnFlyoutItemSelected): transaction:OverwriteAllocation → slot:SetReagent → событие AllocationsModified.
-- Кладём только в пустой и открытый слот, только то, что слот принимает и что есть в сумках.
-- Один раз при выборе рецепта: если Миша вынул реагент сам — до следующего выбора не возвращаем.
local FINISH_ORDER = { 247724, 247788, 247726 }   -- Коллектор, Индикатор, Наводчик
local DEFAULT_FINISH_RECIPE = 1230859            -- Зелье безрассудства
local finishHooked = false

local function FinishRecipe()
    if not ns.ProfEnabled() then return end
    local v = DB().settings.finishRecipe
    if v == nil then return DEFAULT_FINISH_RECIPE end
    return (v ~= 0) and v or nil
end

-- Shared priority, availability and lock checks for manual UI and addon crafts.
function OQ.PickFinishing(sch, info, used)
    if not (sch and Professions and Professions.GetReagentSlotStatus) then return end
    local ok, locked = pcall(Professions.GetReagentSlotStatus, sch, info)
    if not ok or locked then return end
    local allowed = {}
    for _, r in ipairs(sch.reagents or {}) do if r.itemID then allowed[r.itemID] = true end end
    for _, id in ipairs(FINISH_ORDER) do
        if allowed[id] and not used[id] then
            local reagent = { itemID = id }
            local need = (sch.GetQuantityRequired and sch:GetQuantityRequired(reagent)) or sch.quantityRequired or 1
            need = math.max(1, Num(need) or 1)
            local have = Num(C_Item.GetItemCount(id)) or 0 -- bags only, like manual mode
            if have >= need then return reagent, need, math.floor(have / need) end
        end
    end
end
function OQ.PlanFinishing(recipeID, schematic, info)
    local result, limit, used = {}, math.huge, {}
    if FinishRecipe() ~= recipeID then return result, limit end
    local finishing = Enum.CraftingReagentType and Enum.CraftingReagentType.Finishing
    if not finishing then return result, limit end
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        if slot.reagentType == finishing and slot.dataSlotIndex then
            local reagent, need, count = OQ.PickFinishing(slot, info, used)
            if reagent then
                used[reagent.itemID] = true
                result[#result+1] = { reagent=reagent, quantity=need, dataSlotIndex=slot.dataSlotIndex }
                limit = math.min(limit, count)
            end
        end
    end
    return result, limit
end

local function FillFinishing(form)
    local target = FinishRecipe()
    if not (target and form and form.GetRecipeInfo and form.GetTransaction) then return end
    local info = form:GetRecipeInfo()
    if not (info and Num(info.recipeID) == target) then return end
    local slots = Enum.CraftingReagentType and form.GetSlotsByReagentType
        and form:GetSlotsByReagentType(Enum.CraftingReagentType.Finishing)
    if not slots or #slots == 0 then return end
    local tr = form:GetTransaction()
    if not tr then return end
    local used, changed, put = {}, false, {}
    for _, slot in ipairs(slots) do
        local sch = slot.GetReagentSlotSchematic and slot:GetReagentSlotSchematic()
        local idx = sch and sch.slotIndex
        if idx and not tr:HasAnyAllocations(idx) then
            local reagent, need = OQ.PickFinishing(sch, info, used)
            if reagent then
                tr:OverwriteAllocation(idx, reagent, need)
                if slot.SetReagent then slot:SetReagent(reagent) end
                used[reagent.itemID], changed = true, true
                put[#put+1] = ItemName(reagent.itemID)
            end
        end
    end
    if changed then
        if form.TriggerEvent and ProfessionsRecipeSchematicFormMixin and ProfessionsRecipeSchematicFormMixin.Event then
            form:TriggerEvent(ProfessionsRecipeSchematicFormMixin.Event.AllocationsModified)
        end
        Trace("finishing", { recipe = target, put = put })
    end
end

local function HookFinishing()
    if finishHooked then return end
    local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
    if not (form and form.Init) then return end
    finishHooked = true
    hooksecurefunc(form, "Init", function(self)
        C_Timer.After(0.1, function() local ok, err = pcall(FillFinishing, self); if not ok and ns.debug then print(err) end end)
    end)
end

function BF.HookItemTab()
    local cp = ProfessionsFrame and ProfessionsFrame.CraftingPage
    if BF.tabHooked or not cp then return end
    BF.tabHooked = true
    cp:HookScript("OnShow", function() C_Timer.After(0, function() pcall(UpdateItemPanel) end) end)
    cp:HookScript("OnHide", function() if itemPanel then itemPanel:Hide() end end)
end

function OQ.UpdateProfPanels()
    pcall(HookFinishing)
    pcall(BF.HookItemTab)
    pcall(UpdateItemPanel)
    pcall(HookAuctionator)
    pcall(UpdateAuctLine)
end
ns.RegisterEvent("TRADE_SKILL_SHOW", function() C_Timer.After(0.2, OQ.UpdateProfPanels) end)
ns.RegisterMessage("RAINON_PROFESSIONS_TOGGLED", function()
    if not ns.ProfEnabled() and not OQ.manualOpen then OQ.Hide() end
    OQ.UpdateProfPanels()
end)
-- количество предметов меняется (собрал части, получил награду) — обновляем, только если плашка видна
-- (02.11) бафф флакона/раскалывания появился или кончился — пересчитать слоты (пока плашка видна)
ns.RegisterEvent("UNIT_AURA", function(unit)
    if unit ~= "player" or BF.auraQ or not (itemPanel and itemPanel:IsVisible()) then return end
    if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
    BF.auraQ = true
    C_Timer.After(0.3, function() BF.auraQ = false; if itemPanel and itemPanel:IsVisible() then pcall(UpdateItemPanel) end end)
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if BF.pending then pcall(BF.Sync) end end)
ns.RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", function()
    C_Timer.After(0.3, function() if itemPanel and itemPanel:IsVisible() then pcall(UpdateItemPanel) end end)
end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
    if itemPanel and itemPanel:IsVisible() then pcall(UpdateItemPanel) end
end)

-- -------------------------------------------------------------------------
-- ПКМ по заказу в списке Blizzard (идея No Mats No Make): почему НЕ беру заказ.
-- Добавляем свои пункты в то же меню (тег MENU_PROFESSIONS_CRAFTER_ORDER — его используют и
-- Blizzard, и No Mats No Make), поэтому работает с ним и без него.
-- Пишем в RainonUIOrdersDB.seen[orderID].skip (+ skipAt); «рецепт дорогой» — ещё и
-- recipes[recipeID].hard (это свойство рецепта, а не заказа).
-- -------------------------------------------------------------------------
local SKIP_REASONS = {
    { key = "reagents",  text = "Плохие реги — не делаю" },
    { key = "expensive", text = "Дорого" },
    { key = "recipe",    text = "Рецепт дорогой / сложно получить" },
    -- (02.11) только запись для анализа (на очередь не влияет): Миша отмечает, Claude потом ищет закономерность
    { key = "rewards",   text = "Плохие награды" },
}

local function SkipRecord(order)
    local d = DB()
    d.seen = d.seen or {}
    local key = tostring(order.orderID)
    local o = d.seen[key]
    if not o then
        local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(order.spellID)
        o = { first = time(), recipeID = order.spellID, name = info and info.name, who = PlayerKey(),
              minQ = Num(order.minQuality), tip = Num(order.tipAmount), cut = Num(order.consortiumCut) }
        d.seen[key] = o
    end
    return o
end

local function SetSkip(order, reason)
    if not (order and order.orderID) or IsSecret(order.orderID) then return end
    local o = SkipRecord(order)
    local was = o.skip
    o.skip = reason
    o.skipAt = reason and time() or nil
    local b = order.spellID and Brain(order.spellID)
    if b then
        if reason == "recipe" then b.hard = true elseif was == "recipe" then b.hard = nil end
    end
    -- (02.11) снимок заказа в момент отметки — для разбора «почему так отметил»
    if reason then
        local snap = { tip = Num(order.tipAmount), cut = Num(order.consortiumCut), minQ = Num(order.minQuality), rewards = {} }
        for _, rw in ipairs(order.npcOrderRewards or {}) do
            if rw.itemLink and not IsSecret(rw.itemLink) then
                local id = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(rw.itemLink)
                snap.rewards[#snap.rewards + 1] = { item = id, n = Num(rw.count) or 1, p = PriceLink(rw.itemLink) }
            elseif rw.currencyType then
                snap.rewards[#snap.rewards + 1] = { cur = rw.currencyType, n = Num(rw.count) or 1 }
            end
        end
        local e = FindEntry(order.orderID)
        if e then snap.profit, snap.ourCost, snap.ok, snap.reason = e.profit, e.ourCost, e.ok, e.reason end
        snap.who = PlayerKey()
        o.skipSnap = snap
        Trace("skip", { oid = tostring(order.orderID), name = o.name, reason = reason })
    end
    local txt = "снята"
    for _, r in ipairs(SKIP_REASONS) do if r.key == reason then txt = "«" .. r.text .. "»" end end
    ns.Print("Заказ " .. tostring(o.name or order.spellID) .. ": отметка " .. txt .. ".")
end

-- (02.11) Меню заказа — ПКМ по строке в окне очереди (раньше — в списке заказов Blizzard).
function OQ.OrderMenu(rootDescription, order)
        if not (order and order.orderID) or IsSecret(order.orderID) then return end
        local o = SeenOf(order.orderID)
        rootDescription:CreateTitle("Почему не беру")
        for _, r in ipairs(SKIP_REASONS) do
            rootDescription:CreateRadio(r.text,
                function() local x = SeenOf(order.orderID); return x and x.skip == r.key end,
                function() SetSkip(order, r.key) end)
        end
        if o and o.skip then
            rootDescription:CreateButton("Снять отметку", function() SetSkip(order, nil) end)
        end
        -- (02.11) чёрный список: сам заказанный предмет (рецепт сложно получить и т.п.)
        local outID = Num(order.itemID)
        if outID then
            rootDescription:CreateDivider()
            rootDescription:CreateCheckbox("Чёрный список: " .. ItemName(outID),
                function() return DB().black[outID] and true or false end,
                function()
                    local d = DB()
                    d.black[outID] = (not d.black[outID]) or nil
                    ns.Print("Очередь заказов: " .. ItemName(outID) .. (d.black[outID] and " — в чёрном списке." or " — убран из чёрного списка."))
                    for _, e in ipairs(entries) do
                        if SameID(e.orderID, order.orderID) then
                            if d.black[outID] then e.black, e.blackOut = outID, true
                            elseif e.blackOut then e.black, e.blackOut = nil, nil end
                            ApplyRule(e)
                        end
                    end
                    if Refresh then Refresh() end
                end)
        end
end

-- -------------------------------------------------------------------------
-- Команда и тестер
-- -------------------------------------------------------------------------
SLASH_RAINONORDERS1 = "/rsorders"
-- /rsorders diag — печать расчёта по каждому заказу (для проверки качества/цен).
function OQ.Diag()
    if #entries == 0 then ns.Print("Очередь заказов: сначала «Обновить»."); return end
    for _, e in ipairs(entries) do
        local parts = {}
        for _, sl in ipairs((e.model and e.model.qslots) or {}) do
            local t = {}
            for q, id in ipairs(sl.items) do
                if (sl.alloc[q] or 0) > 0 then t[#t + 1] = ("кач.%d x%d"):format(q, sl.alloc[q]) end
            end
            parts[#parts + 1] = "слот " .. tostring(sl.slot) .. ": " .. table.concat(t, ", ")
        end
        local sup = {}
        for id in pairs(e.supplied or {}) do sup[#sup + 1] = ItemName(id) end
        ns.Print(("%s | нужно %d, выйдет %s | навык %s / сложность %s, макс %s | %s | наши: %s | заказчик: %s"):format(
            e.name, e.minQ or 0, tostring(e.expQ), tostring(e.skill), tostring(e.diff),
            tostring(e.model and e.model.maxQ), e.ok and "ОК" or (e.reason or "?"), table.concat(parts, "; "),
            (#sup > 0) and table.concat(sup, ", ") or "—"))
    end
end

-- (02.11) /rsorders check — сводка проверки за сегодня: крафты нашими кнопками, качество,
-- концентрация, расход против плана, оплата при сдаче, ошибки игры.
function OQ.CheckReport()
    local d = DB()
    local t0 = time() - (tonumber(date("%H")) * 3600 + tonumber(date("%M")) * 60 + tonumber(date("%S")))
    local n, q, conc, over, flagged, paidN, payBad, spent, plan, paid = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    local kinds, flagKinds = {}, {}
    for _, en in ipairs(d.log or {}) do
        if (en.t or 0) >= t0 and en.orderID then
            n = n + 1
            kinds[en.kind or "?"] = (kinds[en.kind or "?"] or 0) + 1
            if en.gotQ and en.minQ and en.gotQ >= en.minQ then q = q + 1 end
            if (en.concSpent or 0) > 0 then conc = conc + 1 end
            if en.realSpent and en.ourCost then
                spent, plan = spent + en.realSpent, plan + en.ourCost
                if en.realSpent > en.ourCost + GOLD then over = over + 1 end
            end
            if en.paid then paidN = paidN + 1; paid = paid + en.paid end
            if en.flags then
                flagged = flagged + 1
                for _, f in ipairs(en.flags) do
                    local k = tostring(f):gsub("%(.*", ""):gsub(":.*", ""):gsub("%s+$", "")
                    flagKinds[k] = (flagKinds[k] or 0) + 1
                end
            end
        end
    end
    local errs, fails, claimBad, fulBad = 0, 0, 0, 0
    for _, r in ipairs(d.trace or {}) do
        if (r.t or 0) >= t0 then
            if r.step == "ui_error" then errs = errs + 1
            elseif r.step == "craft_fail" then fails = fails + 1
            elseif r.step == "claim_resp" and r.result ~= Enum.CraftingOrderResult.Ok then claimBad = claimBad + 1
            elseif r.step == "fulfill_resp" and r.result ~= Enum.CraftingOrderResult.Ok then fulBad = fulBad + 1 end
            if r.flags and r.step == "fulfill_resp" then payBad = payBad + 1 end
        end
    end
    local kt = {}
    for k, v in pairs(kinds) do kt[#kt + 1] = k .. " " .. v end
    ns.Print(("Проверка за сегодня: крафтов %d (%s), качество как нужно — %d из %d, концентрация — %d."):format(
        n, table.concat(kt, ", "), q, n, conc))
    ns.Print(("Реагенты: план %s, ушло %s, больше плана — %d крафтов. Оплата при сдаче: %s за %d заказов, расхождений %d."):format(
        Gold(plan), Gold(spent), over, Gold(paid), paidN, payBad))
    ns.Print(("Ошибки: красных сообщений игры %d, сорванных крафтов %d, не взялось %d, не сдалось %d. Строк с пометками: %d."):format(
        errs, fails, claimBad, fulBad, flagged))
    for k, v in pairs(flagKinds) do ns.Print("   • " .. k .. ": " .. v) end
end

-- (02.11) «Дальше» с клавиши или макроса — как «craftnext» у CraftSim: нажатие клавиши / макроса игра
-- считает живым нажатием, поэтому взять / сделать / сдать разрешено. Клавиша — Настройки игры →
-- Назначение клавиш → AddOns → RainonUI (Bindings.xml); макрос — /rsorders next или /click RainonUIOrderQueueNext.
function OQ.PressNext()
    if win and win:IsShown() and win.next and win.next:IsEnabled() and win.next.action then win.next:Click() end
end
RainonUI_OrderNext = OQ.PressNext
BINDING_HEADER_RAINONUI = "RainonUI"
BINDING_NAME_RAINONUI_ORDER_NEXT = "Очередь заказов: «Дальше»"

SlashCmdList.RAINONORDERS = function(msg)
    msg = msg and msg:lower() or ""
    if msg:find("next") then OQ.PressNext()
    elseif msg:find("diag") then OQ.Diag()
    elseif msg:find("check") then OQ.CheckReport()
    elseif msg:find("macro") then OQ.CreateBagMacros()
    elseif msg:find("bag") then OQ.BagReport()
    else OQ.Toggle() end
end

if ns.Tester and ns.Tester.Add then
    ns.Tester.Add("Тест", "Очередь заказов", function() OQ.Toggle() end)
end
