-- =========================================================================
-- RainonUI / ConcCraft — «Крафт за концентрацию».
-- Маленькое окно при открытой профессии: у каждого рецепта слева кнопка «Крафт».
-- Одно нажатие = столько крафтов, на сколько ХВАТАЕТ ВСЕГО сразу:
--   концентрация сейчас ÷ стоимость 1 крафта (стоимость говорит сама игра —
--   C_TradeSkillUI.GetCraftingOperationInfo(…, applyConcentration = true).concentrationCost),
--   реагенты в сумках/банке реагентов/банке отряда, у «Букета трав» и «Чудесного синергетика» — заряды рецепта.
-- Концентрация вернулась — жмёшь ещё раз, число пересчитывается заново. Порога нет (решение Миши).
-- Для реагентов с качеством используем выбор из настроек. Простые реагенты игра кладёт сама.
-- Работает ТОЛЬКО при открытом окне профессии; рецепты другой профессии не показываются.
-- Очередь заказов (OrderQueue.lua) не трогаем: свой вызов CraftRecipe, без заказа.
-- Настройки: ns.db.concCraft = { pos = {point, relPoint, x, y}, locked = bool }.
-- =========================================================================
local _, ns = ...

-- Рецепты (ID проверены по записям RainonUIOrdersDB.recipes 04.11). gold = ID любого из предметов
-- слота, который кладём ЗОЛОТЫМ (кач.2); conc = false — рецепт без концентрации (только заряды).
local RECIPES = {
    { id = 1230859, name = "Зелье безрассудства", icon = 7548916 },  -- Алхимия, всё обычное
    { id = 1230892, name = "Букет трав", icon = 612962, conc = false, charges = true },  -- Алхимия, заряды
    { id = 1230856, name = "Чудесный синергетик", icon = "Interface\\Icons\\spell_animaardenweald_orb", conc = false, charges = true },  -- Алхимия, заряды
    { id = 1236491, name = "Талассийское масло феникса", icon = 7548987, gold = { 243599 } },  -- ◆ Вечнопоющая пыль, ◇ флакон
    { id = 1230476, name = "Флакон из солнечного стекла", icon = 7548906, gold = { 242789 } },  -- Ювелирное: ◆ Затемнённый камень
    { id = 1229853, name = "Духовная звёздочка", icon = 7548996 },  -- Инженерное, всё обычное
    { id = 1230763, name = "Сплав высокой пробы", icon = 7548919 },  -- Кузнечное, всё обычное
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
    local quality = (d.herbQuality and d.herbQuality[slot]) or d.herbDefaultQuality
    return quality == 2 and 2 or 1
end
local function ReadSlots(recipeID)
    local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(sch) ~= "table" then return end

    local slots = {}
    for _, sl in ipairs(sch.reagentSlotSchematics or {}) do
        local qty = Num(sl.quantityRequired) or 0
        if sl.reagentType == REAGENT_BASIC and qty > 0 then
            local ids = {}
            for _, reagent in ipairs(sl.reagents or {}) do
                local id = Num(reagent.itemID)
                if id then ids[#ids + 1] = id end
            end
            local slot = Num(sl.dataSlotIndex)
            if #ids == 0 or not slot then return end
            slots[#slots + 1] = { slot = slot, ids = ids, qty = qty }
        end
    end
    if #slots > 0 then return slots, sch end
end

local function ItemQuality(id)
    local ok, quality = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, id)
    return ok and Num(quality) or nil
end

local function SelectedQuality(recipe, slot)
    if recipe.id == 1230892 then return HerbQuality(slot.slot) end
    local choices = DBc().reagentQuality
    local saved = choices and choices[recipe.id] and choices[recipe.id][slot.slot]
    if saved == 1 or saved == 2 then return saved end
    for _, gold in ipairs(recipe.gold or {}) do
        for _, id in ipairs(slot.ids) do
            if id == gold or (gold == 243599 and id == 243600) then return 2 end
        end
    end
    return 1
end

local function SaveQuality(recipe, slot, quality)
    if recipe.id == 1230892 then
        local d = DBc()
        d.herbQuality = d.herbQuality or {}
        d.herbQuality[slot.slot] = quality
    else
        local d = DBc()
        d.reagentQuality = d.reagentQuality or {}
        d.reagentQuality[recipe.id] = d.reagentQuality[recipe.id] or {}
        d.reagentQuality[recipe.id][slot.slot] = quality
    end
end

local function ItemForQuality(slot, quality)
    for _, id in ipairs(slot.ids) do
        if ItemQuality(id) == quality then return id end
    end
end

-- Реагенты для игры и число крафтов, на которое их хватает.
local function Plan(r, info)
    local slots, sch = ReadSlots(r.id)
    if not slots then return nil, 0, "Игра не дала схему рецепта" end
    local tbl, byReag, short = {}, math.huge, nil
    for _, slot in ipairs(slots) do
        local pick = slot.ids[1]
        if #slot.ids > 1 then
            local quality = SelectedQuality(r, slot)
            pick = ItemForQuality(slot, quality)
            if not pick then return nil, 0, "Игра не дала реагент качества " .. quality end
            tbl[#tbl + 1] = { reagent = { itemID = pick }, quantity = slot.qty, dataSlotIndex = slot.slot }
        end
        local have = Count(pick)
        local can = math.floor(have / slot.qty)
        if can < byReag then
            byReag = can
            if can == 0 then
                local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(pick)
                short = (name or ("предмет " .. pick)) .. " (нужно " .. slot.qty .. ", есть " .. have .. ")"
            end
        end
    end
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
    if r.conc ~= false and res.n > 0 then
        local okI, op = pcall(C_TradeSkillUI.GetCraftingOperationInfo, r.id, tbl, nil, true)
        local cost = okI and op and Num(op.concentrationCost) or nil
        local cid = okI and op and Num(op.concentrationCurrencyID) or nil
        local have = 0
        if cid and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local ci = C_CurrencyInfo.GetCurrencyInfo(cid); have = ci and Num(ci.quantity) or 0
        end
        if not cost or cost < 0 then
            res.n = 0; res.why = "Игра не назвала цену концентрации"
        elseif cost > 0 then
            res.cost, res.have = cost, have
            local byConc = math.floor(have / cost)
            if byConc < res.n then res.n = byConc; res.why = (byConc == 0) and ("Мало концентрации: " .. have .. ", нужно " .. cost) or nil end
        end
    end
    return res
end

-- ── Окно ──────────────────────────────────────────────────────────────────
local win, rows = nil, {}
local dismissed = false
local ROW_H = 24
local W = (ns.OrderQueue and ns.OrderQueue.WINDOW_WIDTH) or 400
local ICON_SIZE, ROW_GAP = 20, 6

local function OutputIcon(recipe)
    local ok, item = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipe.id)
    return (ok and item and Num(item.icon)) or recipe.icon
end

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
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, r.id, res.n, res.tbl, nil, nil, res.cost ~= nil)
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
    local moving = false
    win:SetScript("OnDragStart", function(self)
        if DBc().locked then return end
        moving = true
        self:StartMoving()
    end)
    win:SetScript("OnDragStop", function(self)
        if not moving then return end
        moving = false
        self:StopMovingOrSizing()
        SavePos()
    end)
    win:SetTitle("Крафт за концентрацию")
    local pos = DBc().pos
    if pos then
        win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        win:SetPoint("CENTER", UIParent, "CENTER")
    end

    local close = win.CloseButton
    close:HookScript("OnClick", function() dismissed = true end)
    local level = close:GetFrameLevel()
    for _, region in ipairs({ "NineSlice", "TitleContainer" }) do
        if win[region] then level = math.max(level, win[region]:GetFrameLevel()) end
    end
    local headerGap = 4
    local function TitleButton(anchor, iconWidth)
        local button = CreateFrame("Button", nil, win, "UIPanelHideButtonNoScripts")
        button:SetSize(close:GetSize())
        button:SetPoint("RIGHT", anchor, "LEFT", -headerGap, 0)
        button:SetFrameLevel(level + 2)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- The stock red square includes a minus. Cover it inside the rim.
        local inset = button:CreateTexture(nil, "OVERLAY")
        inset:SetSize(16, 10)
        inset:SetPoint("CENTER")
        inset:SetColorTexture(0.26, 0.035, 0.025)

        local icon = button:CreateTexture(nil, "OVERLAY", nil, 1)
        icon:SetSize(iconWidth, 14)
        icon:SetPoint("CENTER")
        return button, icon
    end

    local gear, gearIcon = TitleButton(close, 14)
    gearIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
    gearIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    gear:SetScript("OnClick", function() ns.OpenOptions(3) end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Настройки профессий", 1, 1, 1)
        GameTooltip:Show()
    end)

    local lock, lockIcon = TitleButton(gear, 12)
    lockIcon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
    local function UpdateLockIcon()
        local locked = DBc().locked
        lockIcon:SetDesaturated(not locked)
        lockIcon:SetVertexColor(1, locked and 0.85 or 1, locked and 0.3 or 1)
        lockIcon:SetAlpha(locked and 1 or 0.45)
    end
    lock:SetScript("OnClick", function()
        DBc().locked = not DBc().locked
        UpdateLockIcon()
    end)
    lock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(DBc().locked and "Окно закреплено" or "Окно откреплено", 1, 1, 1)
        GameTooltip:Show()
    end)
    UpdateLockIcon()

    local title = win.TitleContainer.TitleText
    title:ClearAllPoints()
    local borderInset = 7 -- Left inset of ButtonFrameTemplate without a portrait.
    title:SetPoint("LEFT", win, "TOPLEFT", borderInset + headerGap, -close:GetHeight() / 2)
    title:SetPoint("RIGHT", lock, "LEFT", -headerGap, 0)
    title:SetJustifyH("LEFT")
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
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_SIZE, ICON_SIZE)
    r.icon:SetPoint("LEFT", r.btn, "RIGHT", ROW_GAP, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", ROW_GAP, 0)
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
            if r.recipe ~= rec then r.icon:SetTexture(OutputIcon(rec)) end
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
    if not ns.db or ns.db.features.concCraft == false or dismissed
        or not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
        if win then win:Hide() end
        return
    end
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

ns.RegisterEvent("TRADE_SKILL_SHOW", function()
    dismissed = false
    C_Timer.After(0.3, Show)
end)
ns.RegisterEvent("TRADE_SKILL_LIST_UPDATE", function() if win and win:IsShown() then Refresh() elseif ProfessionsFrame and ProfessionsFrame:IsShown() then Show() end end)
ns.RegisterEvent("TRADE_SKILL_CLOSE", function() if win then win:Hide() end end)
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE", "TRADE_SKILL_ITEM_CRAFTED_RESULT" }) do
    ns.RegisterEvent(e, function() if win and win:IsShown() then Refresh() end end)
end

ns.ConcCraft = {
    RECIPES = RECIPES,
    Check = Check,
    Refresh = function() Refresh() end,
    ApplyVisibility = function()
        dismissed = false
        Show()
    end,
}


-- Options uses the same recipe list and quality settings as the craft button.
do
local QUALITY_ATLAS = "Professions-ChatIcon-Quality-12-Tier"
local function Slots(rec)
    local slots = ReadSlots(rec.id) or {}
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
    return slot.saved and (ItemQuality(slot.ids[1]) or 0) > 0
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
    hint:SetText("Кнопка «Крафт» использует выбранное здесь качество реагентов.")
    y = y - 24
    local qualityOptions = {}
    for quality, label in ipairs({ "Обычное", "Золотое" }) do
        qualityOptions[quality] = {
            text = CreateAtlasMarkup(QUALITY_ATLAS .. quality, 16, 16),
            value = quality,
            initialize = function(row)
                local text = row:AttachFontString()
                text:SetFontObject(row.fontString:GetFontObject())
                text:SetHeight(row.fontString:GetHeight())
                text:SetJustifyH("LEFT")
                -- «З» выступает на один пиксель левее «О» в шрифте меню.
                local offset = 19
                if quality == 2 then
                    offset = offset + PixelUtil.GetPixelToUIUnitFactor() / row:GetEffectiveScale()
                end
                text:SetPoint("LEFT", row.fontString, "LEFT", offset, 0)
                text:SetTextToFit(label)
            end,
        }
    end
    local updates = {}
    for _, rec in ipairs(RECIPES) do
        local recipe = rec
        local row = CreateFrame("Frame",nil,parent)
        row:SetSize(572,116); row:SetPoint("TOPLEFT",12,y)
        local icon = row:CreateTexture(nil,"ARTWORK"); icon:SetSize(24,24); icon:SetPoint("TOPLEFT")
        icon:SetTexture(recipe.icon)
        local name = row:CreateFontString(nil,"OVERLAY","GameFontNormal")
        name:SetPoint("LEFT",icon,"RIGHT",6,0); name:SetWidth(540); name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        name:SetText(recipe.name .. (recipe.charges and recipe.conc == false and " — по зарядам, без концентрации" or ""))
        local slots, cells = {}, {}
        local Render
        local yy = -30
        for i = 1, 6 do
            local slotIndex = i
            local cell = CreateFrame("Frame", nil, row)
            cell:SetSize(280, 24)
            cell:SetPoint("TOPLEFT", ((i - 1) % 2) * 292, yy - math.floor((i - 1) / 2) * 26)
            local dd = dropdown(cell, 44,
                function()
                    local slot = slots[slotIndex]
                    return slot and SelectedQuality(recipe, slot) or 1
                end,
                function(quality)
                    local slot = slots[slotIndex]
                    if not slot or not HasQuality(slot) then return end
                    SaveQuality(recipe, slot, quality)
                    Render()
                    Refresh()
                end, qualityOptions)
            dd:SetPoint("LEFT")

            local itemIcon = cell:CreateTexture(nil, "ARTWORK")
            itemIcon:SetSize(20, 20)
            local label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", itemIcon, "RIGHT", 6, 0)
            label:SetPoint("RIGHT", -2, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            cells[i] = { frame = cell, label = label, icon = itemIcon, dropdown = dd }

            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                local slot = slots[slotIndex]
                if not slot then return end
                local id = cells[slotIndex].itemID
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(ItemLabel(id))
                GameTooltip:AddLine("Нужно на один крафт: " .. slot.qty, 1, 1, 1)
                if slot.saved then
                    GameTooltip:AddLine("Сохранённая часть состава. Открой профессию для полной схемы.", 1, 0.82, 0, true)
                end
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        local empty = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", 2, yy)
        empty:SetText("Открой эту профессию, чтобы загрузить состав реагентов.")
        Render = function()
            for i, cell in ipairs(cells) do
                local slot = slots[i]
                cell.frame:SetShown(slot ~= nil)
                if slot then
                    local hasQuality = HasQuality(slot)
                    local id = slot.ids[1]
                    cell.dropdown:SetShown(hasQuality)
                    if hasQuality then
                        local quality = SelectedQuality(recipe, slot)
                        id = ItemForQuality(slot, quality) or id
                        cell.dropdown:SetText(qualityOptions[quality].text)
                    end
                    cell.itemID = id
                    cell.icon:ClearAllPoints()
                    cell.icon:SetPoint("LEFT", hasQuality and 50 or 2, 0)
                    cell.icon:SetTexture(C_Item.GetItemIconByID(id) or 134400)
                    cell.label:SetText(ItemLabel(id) .. " ×" .. slot.qty)
                end
            end
            empty:SetShown(#slots == 0)
        end
        local function Update()
            slots = Slots(recipe)
            Render()
        end
        updates[#updates + 1] = Update
        Update()
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
