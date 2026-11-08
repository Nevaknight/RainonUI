-- =========================================================================
-- RainonUI / ConcCraft — «Крафт за концентрацию» (ЭКСПЕРИМЕНТАЛЬНЫЙ, 04.11.2026, Миша п. 31).
-- Маленькое окно при открытой профессии: у каждого рецепта слева кнопка «Крафт».
-- Одно нажатие = столько крафтов, на сколько ХВАТАЕТ ВСЕГО сразу:
--   концентрация сейчас ÷ стоимость 1 крафта (стоимость говорит сама игра —
--   C_TradeSkillUI.GetCraftingOperationInfo(…, applyConcentration = true).concentrationCost),
--   реагенты в сумках/банке реагентов/банке отряда, у «Букета трав» — заряды рецепта.
-- Концентрация вернулась — жмёшь ещё раз, число пересчитывается заново. Порога нет (решение Миши).
-- Реагенты кладём сами (как очередь заказов): у слота с качеством — серебро (кач.1),
-- кроме реагентов из GOLD у этого рецепта — их золото (кач.2). Простые реагенты игра кладёт сама.
-- Работает ТОЛЬКО при открытом окне профессии; рецепты другой профессии не показываются.
-- Очередь заказов (OrderQueue.lua) не трогаем: свой вызов CraftRecipe, без заказа.
-- Настройки: ns.db.concCraft = { pos = {point, relPoint, x, y}, locked = bool }.
-- =========================================================================
local _, ns = ...

-- Рецепты (ID проверены по записям RainonUIOrdersDB.recipes 04.11). gold = ID любого из предметов
-- слота, который кладём ЗОЛОТЫМ (кач.2); conc = false — рецепт без концентрации (только заряды).
local RECIPES = {
    { id = 1230859, name = "Зелье безрассудства" },                         -- Алхимия, всё обычное
    { id = 1230892, name = "Букет трав", conc = false, charges = true },    -- Алхимия, заряды
    { id = 1236491, name = "Талассийское масло феникса", gold = { 243599 } },   -- ◆ Вечнопоющая пыль, ◇ флакон
    { id = 1230476, name = "Флакон из солнечного стекла", gold = { 242789 } },  -- Ювелирное: ◆ Затемнённый камень
    { id = 1229853, name = "Духовная звёздочка" },                          -- Инженерное, всё обычное
    { id = 1230763, name = "Сплав высокой пробы" },                         -- Кузнечное, всё обычное
}

local REAGENT_BASIC = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1
local function Num(v) if issecretvalue and issecretvalue(v) then return nil end return tonumber(v) end
local function C(hex, s) return (ns.C and ns.C(hex, s)) or s end
local function Count(id)
    if not (C_Item and C_Item.GetItemCount) then return 0 end
    local ok, n = pcall(C_Item.GetItemCount, id, true, false, true, true)
    return (ok and Num(n)) or 0
end
local function DBc() ns.db.concCraft = ns.db.concCraft or {}; return ns.db.concCraft end
local function HerbQuality(slot)
    local d = DBc()
    return (d.herbQuality and d.herbQuality[slot]) or d.herbDefaultQuality or 1
end
local function SetHerbQuality(slot, quality)
    if quality ~= 1 and quality ~= 2 then return end
    local d = DBc()
    if slot then
        d.herbQuality = d.herbQuality or {}
        d.herbQuality[slot] = quality
    else
        d.herbDefaultQuality, d.herbQuality = quality, {}
    end
end

-- Реагенты для игры + сколько крафтов позволяют реагенты (минимум по слотам)
local function Plan(r, info)
    local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, r.id, false)
    if not ok or type(sch) ~= "table" then return nil, 0, "игра не дала схему рецепта" end
    local gold = {}
    for _, g in ipairs(r.gold or {}) do gold[g] = true end
    local tbl, byReag, short = {}, math.huge, nil
    for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local reagents, need = slot.reagents or {}, Num(slot.quantityRequired) or 0
        if slot.reagentType == REAGENT_BASIC and need > 0 and reagents[1] and reagents[1].itemID then
            local items = {}
            for _, x in ipairs(reagents) do items[#items + 1] = x.itemID end
            local pick = items[1]
            if #items > 1 then
                -- порядок по качеству — у игры (в схеме бывает не по возрастанию)
                local rq, qOf = C_TradeSkillUI.GetItemReagentQualityByItemInfo, {}
                for _, id in ipairs(items) do local okQ, q = pcall(rq, id); qOf[id] = okQ and Num(q) or 0 end
                table.sort(items, function(a, b) return qOf[a] < qOf[b] end)
                local wantGold = false
                for _, id in ipairs(items) do if gold[id] then wantGold = true end end
                local quality = r.id == 1230892 and HerbQuality(slot.dataSlotIndex) or (wantGold and 2 or 1)
                pick = nil
                for _, id in ipairs(items) do if qOf[id] == quality then pick = id; break end end
                if not pick then return nil, 0, "Игра не дала реагент качества " .. quality end
                tbl[#tbl + 1] = { reagent = { itemID = pick }, quantity = need, dataSlotIndex = slot.dataSlotIndex }
            end
            local can = math.floor(Count(pick) / need)
            if can < byReag then
                byReag = can
                if can == 0 then
                    local nm = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(pick)
                    short = (nm or ("предмет " .. pick)) .. " (нужно " .. need .. ", есть " .. Count(pick) .. ")"
                end
            end
        end
    end
    if byReag == math.huge then byReag = 0 end
    if ns.OrderQueue and ns.OrderQueue.PlanFinishing then
        local extras, limit = ns.OrderQueue.PlanFinishing(r.id, sch, info)
        for _, allocation in ipairs(extras) do tbl[#tbl+1] = allocation end
        if limit < byReag then
            byReag = limit
            short = "Усилителей хватает на " .. limit .. " крафт(а)"
        end
    end
    return tbl, byReag, short
end

-- Сколько крафтов можно сейчас и почему не больше
local function Check(r)
    local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(r.id)
    if not (info and info.learned) then return nil end   -- не изучен / другая профессия — строки нет
    local tbl, byReag, short = Plan(r, info)
    if not tbl then return { n = 0, why = short } end
    local res = { tbl = tbl, n = byReag, why = (byReag == 0) and ("Не хватает: " .. (short or "реагентов")) or nil }
    if r.charges then
        local okC, _, _, charges = pcall(C_TradeSkillUI.GetRecipeCooldown, r.id)
        local ch = okC and Num(charges) or 0
        res.charges = ch
        if ch < res.n then res.n = ch; res.why = (ch == 0) and "Нет зарядов" or ("Зарядов: " .. ch) end
    end
    if r.conc ~= false then
        local okI, op = pcall(C_TradeSkillUI.GetCraftingOperationInfo, r.id, tbl, nil, true)
        local cost = okI and op and Num(op.concentrationCost) or nil
        local cid = okI and op and Num(op.concentrationCurrencyID) or nil
        local have = 0
        if cid and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local ci = C_CurrencyInfo.GetCurrencyInfo(cid); have = ci and Num(ci.quantity) or 0
        end
        res.cost, res.have = cost, have
        if not cost or cost <= 0 then res.n = 0; res.why = "Игра не назвала цену концентрации"
        else
            local byConc = math.floor(have / cost)
            if byConc < res.n then res.n = byConc; res.why = (byConc == 0) and ("Мало концентрации: " .. have .. ", нужно " .. cost) or nil end
        end
    end
    return res
end

-- ── Окно ──────────────────────────────────────────────────────────────────
local win, rows = nil, {}
local ROW_H, W = 24, 290

local function SavePos()
    local p, _, rp, x, y = win:GetPoint()
    DBc().pos = { p, rp, x, y }
end

local Refresh
local function Craft(r)
    if InCombatLockdown and InCombatLockdown() then return end
    local res = Check(r)
    if not res then return end
    if res.n <= 0 then ns.Print(C("71d5ff", r.name) .. ": " .. C("ff6060", res.why or "сейчас нельзя")); return end
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, r.id, res.n, res.tbl, nil, nil, r.conc ~= false)
    if ok then
        ns.Print(C("71d5ff", r.name) .. ": " .. C("1eff00", "крафтов " .. res.n) ..
            (res.cost and (" (концентрация " .. res.have .. ", 1 крафт = " .. res.cost .. ")") or "") ..
            (r.charges and (" (зарядов " .. (res.charges or 0) .. ")") or ""))
    else
        ns.Print(C("71d5ff", r.name) .. ": " .. C("ff6060", "игра не начала крафт — " .. tostring(err)))
    end
    C_Timer.After(0.5, function() if Refresh then Refresh() end end)
end

local function Build()
    win = CreateFrame("Frame", "RainonUIConcCraft", UIParent, "ButtonFrameTemplate")
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(win) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(win) end
    if win.Inset then win.Inset:Hide() end
    win:SetSize(W, 80)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) if not DBc().locked then self:StartMoving() end end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    if win.SetTitle then win:SetTitle("Крафт за концентрацию") elseif win.TitleText then win.TitleText:SetText("Крафт за концентрацию") end
    local pos = DBc().pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("TOPLEFT", ProfessionsFrame or UIParent, "BOTTOMLEFT", 0, -6) end
    -- замок: закреплённое окно не двигается
    local lock = CreateFrame("Button", nil, win)
    lock:SetSize(18, 18)
    lock:SetPoint("TOPRIGHT", -28, -2)
    local function LockTex()
        local l = DBc().locked
        lock:SetNormalTexture(l and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
    end
    lock:SetScript("OnClick", function() DBc().locked = not DBc().locked; LockTex() end)
    lock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(DBc().locked and "Окно закреплено" or "Окно можно двигать", 1, 1, 1)
        GameTooltip:AddLine("Нажми — " .. (DBc().locked and "открепить" or "закрепить"), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    lock:SetScript("OnLeave", function() GameTooltip:Hide() end)
    LockTex()
    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.empty:SetPoint("TOPLEFT", 12, -32)
    win:Hide()
end

local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, win)
    r:SetSize(W - 20, ROW_H)
    r:SetPoint("TOPLEFT", 10, -26 - (i - 1) * ROW_H)
    r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.btn:SetSize(64, 20)
    r.btn:SetPoint("LEFT", 0, 0)
    r.btn:SetText("Крафт")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.btn, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", -44, 0)
    r.name:SetJustifyH("LEFT")
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetPoint("RIGHT", 0, 0)
    r.btn:SetScript("OnClick", function() if r.recipe then Craft(r.recipe) end end)
    r.btn:SetScript("OnEnter", function(self)
        local res = r.res
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(r.recipe.name, 1, 1, 1)
        if res then
            GameTooltip:AddLine(res.n > 0 and ("Нажми — крафтов: " .. res.n) or (res.why or "Сейчас нельзя"), res.n > 0 and 0.4 or 1, res.n > 0 and 1 or 0.4, 0.4, true)
            if res.cost then GameTooltip:AddDoubleLine("Концентрация", res.have .. " (1 крафт = " .. res.cost .. ")", 1, 1, 1, 1, 0.82, 0) end
            if res.charges then GameTooltip:AddDoubleLine("Заряды", tostring(res.charges), 1, 1, 1, 1, 0.82, 0) end
            if r.recipe.gold then GameTooltip:AddLine("Золотые реагенты: по настройке рецепта, остальные — серебро", 0.8, 0.8, 0.8, true) end
        end
        GameTooltip:Show()
    end)
    r.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

Refresh = function()
    if not win or not win:IsShown() then return end
    local n = 0
    for _, rec in ipairs(RECIPES) do
        local res = Check(rec)
        if res then
            n = n + 1
            local r = Row(n)
            r.recipe, r.res = rec, res
            r.name:SetText(res.n > 0 and rec.name or C("808080", rec.name))
            r.info:SetText(res.n > 0 and C("1eff00", "×" .. res.n) or C("808080", "×0"))
            r.btn:SetEnabled(res.n > 0)
            r:Show()
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    if n == 0 then win.empty:SetText("У этой профессии рецептов из списка нет"); win.empty:Show() else win.empty:Hide() end
    win:SetHeight(36 + math.max(1, n) * ROW_H)
end

local function Show()
    if not ns.db then return end
    if not win then Build() end
    -- окно — только если у открытой профессии есть рецепт из списка
    local any = false
    for _, rec in ipairs(RECIPES) do
        local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(rec.id)
        if info and info.learned then any = true; break end
    end
    if not any then win:Hide(); return end
    win:Show()
    Refresh()
end

ns.RegisterEvent("TRADE_SKILL_SHOW", function() C_Timer.After(0.3, Show) end)
ns.RegisterEvent("TRADE_SKILL_LIST_UPDATE", function() if win and win:IsShown() then Refresh() elseif ProfessionsFrame and ProfessionsFrame:IsShown() then Show() end end)
ns.RegisterEvent("TRADE_SKILL_CLOSE", function() if win then win:Hide() end end)
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE", "TRADE_SKILL_ITEM_CRAFTED_RESULT" }) do
    ns.RegisterEvent(e, function() if win and win:IsShown() then Refresh() end end)
end

ns.ConcCraft = { RECIPES = RECIPES, Check = Check, HerbQuality = HerbQuality, SetHerbQuality = SetHerbQuality,
    Refresh = function() if Refresh then Refresh() end end }


-- Options uses the same recipe list and quality settings as the craft button.
do
local ICONS = {7548916,612962,7548987,7548906,7548996,7548919}
local function Slots(rec)
    local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, rec.id, false)
    local slots = {}
    if ok and type(sch) == "table" then
        for _, sl in ipairs(sch.reagentSlotSchematics or {}) do
            if sl.reagentType == REAGENT_BASIC and (Num(sl.quantityRequired) or 0) > 0 then
                local ids = {}
                for _, r in ipairs(sl.reagents or {}) do if Num(r.itemID) then ids[#ids+1] = r.itemID end end
                if #ids > 0 then slots[#slots+1] = { slot=sl.dataSlotIndex, ids=ids, qty=sl.quantityRequired } end
            end
        end
    end
    local d = DBc()
    d.recipeSlots = d.recipeSlots or {}
    if #slots > 0 then d.recipeSlots[rec.id] = slots; return slots end
    if d.recipeSlots[rec.id] then return d.recipeSlots[rec.id] end
    local book = RainonUIOrdersDB and RainonUIOrdersDB.recipes and RainonUIOrdersDB.recipes[rec.id]
    for _, r in ipairs(book and book.manual and book.manual.reagents or {}) do
        if r.i and r.s then slots[#slots+1] = {slot=r.s,ids={r.i},qty=r.q,saved=true} end
    end
    return slots
end
local function HasQuality(slot)
    if #slot.ids > 1 then return true end
    -- Manual-history fallback has one selected ID, not the full slot schema.
    if slot.saved and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
        local ok, q = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, slot.ids[1])
        return ok and (Num(q) or 0) > 0
    end
    return false
end
local function ItemLabel(id)
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    return name or (RainonUIOrdersDB and RainonUIOrdersDB.names and RainonUIOrdersDB.names[id]) or ("Предмет " .. id)
end
function ns.ConcCraft.BuildOptions(parent, y, dropdown)
    local title = parent:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",12,y)
    title:SetText(C("FFD100","Крафт за концентрацию"))
    y = y - 28
    local hint = parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT",12,y); hint:SetWidth(572); hint:SetJustifyH("LEFT")
    hint:SetText("Рецепты и реагенты. Качество меняется только у букета трав.")
    y = y - 24
    local updates = {}
    for index, rec in ipairs(RECIPES) do
        local recipe = rec
        local row = CreateFrame("Frame",nil,parent)
        local isHerb = recipe.id == 1230892
        row:SetSize(572,isHerb and 144 or 116); row:SetPoint("TOPLEFT",12,y)
        local icon = row:CreateTexture(nil,"ARTWORK"); icon:SetSize(24,24); icon:SetPoint("TOPLEFT")
        icon:SetTexture(ICONS[index])
        local name = row:CreateFontString(nil,"OVERLAY","GameFontNormal")
        name:SetPoint("LEFT",icon,"RIGHT",6,0); name:SetWidth(540); name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        name:SetText(recipe.name .. (isHerb and " — по зарядам, без концентрации" or ""))
        local labels, selects, checks = {}, {}, {}
        local yy = -30
        if isHerb then
            for q=1,2 do
                local quality=q
                local cb=ns.MakeCheckButton(row); cb:SetSize(24,24); cb:SetPoint("TOPLEFT",(q-1)*292,yy)
                cb.Text:SetText(q==1 and "Все реагенты: качество 1" or "Все реагенты: качество 2")
                cb:SetScript("OnClick",function()
                    SetHerbQuality(nil,quality)
                    for _, fn in ipairs(updates) do fn() end
                    if Refresh then Refresh() end
                end)
                checks[q]=cb
            end
            yy=yy-30
        end
        for i=1,6 do
            local slotIndex=i
            local cell=CreateFrame("Frame",nil,row)
            cell:SetSize(280,24); cell:SetPoint("TOPLEFT",((i-1)%2)*292,yy-math.floor((i-1)/2)*26)
            local label=cell:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            label:SetPoint("LEFT",2,0); label:SetWidth(276); label:SetJustifyH("LEFT"); label:SetWordWrap(false)
            labels[i]={cell=cell,label=label}
            if isHerb then
                local dd=dropdown(cell,280,
                    function() local s=row.slots and row.slots[slotIndex]; return s and HerbQuality(s.slot) or 1 end,
                    function(q) local s=row.slots and row.slots[slotIndex]; if s and HasQuality(s) then SetHerbQuality(s.slot,q) end
                        for _,fn in ipairs(updates) do fn() end; if Refresh then Refresh() end
                        C_Timer.After(0,function() for _,fn in ipairs(updates) do fn() end end)
                    end,
                    {{text="Качество 1",value=1},{text="Качество 2",value=2}})
                dd:SetPoint("TOPLEFT"); selects[i]=dd; label:Hide()
                local text = dd:GetFontString()
                if text then text:SetWidth(260); text:SetWordWrap(false) end
            end
            cell:SetScript("OnEnter",function(self)
                local s=row.slots and row.slots[slotIndex]; if not s then return end
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(ItemLabel(s.ids[1]))
                GameTooltip:AddLine("Нужно на один крафт: "..s.qty,1,1,1)
                GameTooltip:AddLine(isHerb and HasQuality(s) and "Выбранное качество используется кнопкой «Крафт»." or "Состав закреплён в рецепте.",0.8,0.8,0.8,true)
                if s.saved then GameTooltip:AddLine("Сохранённая часть состава. Открой профессию для полной схемы.",1,0.82,0,true) end
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave",function() GameTooltip:Hide() end)
        end
        local empty=row:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
        empty:SetPoint("TOPLEFT",2,yy); empty:SetText("Открой эту профессию, чтобы загрузить состав реагентов.")
        local function Update()
            row.slots=Slots(recipe)
            local all1,all2=true,true
            for i,entry in ipairs(labels) do
                local s=row.slots[i]
                entry.cell:SetShown(s~=nil)
                if s then
                    local id=s.ids[1]
                    local q=1
                    for _,gold in ipairs(recipe.gold or {}) do for _,iid in ipairs(s.ids) do if iid==gold or (gold==243599 and iid==243600) then q=2 end end end
                    local quality = HasQuality(s)
                    if isHerb and quality then q=HerbQuality(s.slot);all1=all1 and q==1;all2=all2 and q==2 end
                    local text=ItemLabel(id).." ×"..s.qty..(quality and (" · кач."..q) or "")
                    if selects[i] then selects[i]:SetShown(quality); if quality then selects[i]:SetText(text) end end
                    entry.label:SetShown(not (isHerb and quality)); entry.label:SetText(text)
                end
            end
            empty:SetShown(#row.slots==0)
            if isHerb then checks[1]:SetChecked(#row.slots>0 and all1);checks[2]:SetChecked(#row.slots>0 and all2) end
        end
        updates[#updates+1]=Update; Update()
        y=y-row:GetHeight()-8
    end
    parent:HookScript("OnShow",function() for _,fn in ipairs(updates) do fn() end end)
    ns.RegisterEvent("TRADE_SKILL_LIST_UPDATE",function()
        for _,r in ipairs(RECIPES) do Slots(r) end
        if parent:IsShown() then for _,fn in ipairs(updates) do fn() end end
    end)
    return y - 8
end
end
