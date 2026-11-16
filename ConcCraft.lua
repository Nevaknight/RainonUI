












local _, ns = ...

-- Рецепты (ID проверены по записям RainonUIOrdersDB.recipes 04.11). gold = ID любого из предметов
-- слота, который кладём ЗОЛОТЫМ (кач.2); conc = false — рецепт без концентрации (только заряды).
local RECIPES = {
    { id = 1230859, name = "Зелье безрассудства", icon = 7548916 },
    { id = 1230892, name = "Букет трав", icon = 612962, conc = false, charges = true },
    { id = 1230856, name = "Чудесный синергетик", icon = "Interface\\Icons\\spell_animaardenweald_orb", conc = false, charges = true },
    { id = 1236491, name = "Талассийское масло феникса", icon = 7548987, gold = { 243599 } },
    { id = 1230476, name = "Флакон из солнечного стекла", icon = 7548906, gold = { 242789 } },
    { id = 1229853, name = "Духовная звёздочка", icon = 7548996 },
    { id = 1230763, name = "Сплав высокой пробы", icon = 7548919 },
}

local DERIVATE = 242651
local RECYCLE_POTIONS = 1233129
local RECYCLE_RECIPE = {
    id = RECYCLE_POTIONS, name = "Крафт вытяжки",
    icon = "Interface\\Icons\\item_alchemiststoneb",
}
local POTIONS = {
    { id = 241307, name = "Освежающая сыворотка", icon = 2057573 },
    { id = 241339, name = "Тоник просветления", icon = 236876 },
    { id = 268954, name = "Энтропийный экстракт", icon = 1416156 },
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
local function BagCount(id)
    return Num(C_Item.GetItemCount(id, false, false, false, false)) or 0
end

local function MacroSelectionKey(recipe)
    return recipe.charges and "cooldownRecipes" or "concentrationRecipes"
end

local function MacroSelected(recipe)
    local selection = DBc()[MacroSelectionKey(recipe)]
    return selection ~= nil and selection[recipe.id] == true
end

local function SetMacroSelection(recipe, selected)
    local db = DBc()
    local key = MacroSelectionKey(recipe)
    db[key] = db[key] or {}
    db[key][recipe.id] = selected
    ns.SendMessage("RAINON_CRAFT_SELECTION_CHANGED")
end

local function RecycleTarget(schematic)
    local id = DBc().recyclePotion
    if not id or id == 0 then return nil, 0, "Выбери зелье первого ранга в настройках переработки." end
    local supported = false
    for _, potion in ipairs(POTIONS) do
        if potion.id == id then supported = true; break end
    end
    if not supported then return nil, 0, "Выбери зелье первого ранга в настройках переработки." end

    local needed = Num(schematic.quantityMax)
    if not needed or needed < 1 then return nil, 0, "Игра не дала состав переработки." end
    for _, allowed in ipairs(C_TradeSkillUI.GetSalvagableItemIDs(RECYCLE_POTIONS) or {}) do
        if allowed == id then
            local best, crafts = nil, 0
            for _, target in ipairs(C_TradeSkillUI.GetCraftingTargetItems({ id }) or {}) do
                if Num(target.itemID) == id and target.itemGUID then
                    local count = math.floor((Num(target.quantity) or 0) / needed)
                    if count > crafts then best, crafts = target, count end
                end
            end
            if best then return best, crafts end
            return nil, 0, "Нужно зелий в одной стопке: " .. needed
        end
    end
    return nil, 0, "Игра не принимает выбранное зелье."
end
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

local function PickReagent(recipe, slot)
    if #slot.ids == 1 then return slot.ids[1] end
    local quality = SelectedQuality(recipe, slot)
    return ItemForQuality(slot, quality), quality
end

-- Реагенты для игры и число крафтов, на которое их хватает.
local function Plan(r, info)
    local slots, sch = ReadSlots(r.id)
    if not slots then return nil, 0, "Игра не дала схему рецепта" end
    local tbl, byReag, short = {}, math.huge, nil
    for _, slot in ipairs(slots) do
        local pick, quality = PickReagent(r, slot)
        if not pick then return nil, 0, "Игра не дала реагент качества " .. quality end
        if #slot.ids > 1 then
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
    if r ~= RECYCLE_RECIPE and ns.OrderQueue and ns.OrderQueue.PlanFinishing then
        local extras, limit = ns.OrderQueue.PlanFinishing(r.id, sch, info)
        for _, allocation in ipairs(extras) do tbl[#tbl+1] = allocation end
        if limit < byReag then
            byReag = limit
            short = "Усилителей хватает на " .. limit .. " крафт(а)"
        end
    end
    return tbl, byReag, short, sch
end

local function CheckRecycle()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    if not (page and page:IsVisible()) then return end
    if Professions and Professions.InLocalCraftingMode and not Professions.InLocalCraftingMode() then return end
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    local profession = base and Num(base.profession)
    if profession and profession ~= Enum.Profession.Alchemy then return end
    local info = C_TradeSkillUI.GetRecipeInfo(RECYCLE_POTIONS)
    if not (info and info.learned) then return end
    if info.disabled or info.craftable == false then
        return { n = 0, why = info.disabledReason }
    end
    if C_TradeSkillUI.GetRecipeRequirements then
        for _, requirement in ipairs(C_TradeSkillUI.GetRecipeRequirements(RECYCLE_POTIONS) or {}) do
            if requirement.met == false then return { n = 0, why = "Требуется: " .. requirement.name } end
        end
    end
    local reagents, available, missing, schematic = Plan(RECYCLE_RECIPE, info)
    if not reagents or available == 0 then return { n = 0, why = missing } end
    local target, count, reason = RecycleTarget(schematic)
    return { n = math.min(available, count), why = reason, tbl = reagents, target = target }
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

local function FullBatchSchedule(recipe, saved)
    local ok, cooldown, _, charges, maximum = pcall(C_TradeSkillUI.GetRecipeCooldown, recipe.id)
    if not ok then return end
    charges, maximum, cooldown = Num(charges), Num(maximum), Num(cooldown)
    if not charges or not maximum or maximum < 1 then return end

    local period = ns.Roster.GetRechargePeriod(recipe.id) or (saved and saved.synthRank and saved.period)
    if not period or period <= 0 then return end
    local missing = math.max(0, maximum - charges)
    local nextCharge = cooldown and cooldown > 0 and cooldown or period
    local first = missing == 0 and 0 or math.ceil(nextCharge + (missing - 1) * period)

    local slots = ReadSlots(recipe.id)
    if not slots then return end
    local costs = {}
    for _, slot in ipairs(slots) do
        local id = PickReagent(recipe, slot)
        if not id then return end
        costs[id] = (costs[id] or 0) + maximum * slot.qty
    end
    if not costs[DERIVATE] then return end
    return { costs = costs, first = first, interval = maximum * period }
end

local function DerivateForecast()
    local schedules, stock, firstRound = {}, {}, {}
    local guid = UnitGUID("player")
    local current = guid and ns.db.roster and ns.db.roster[guid]
    for _, recipe in ipairs(RECIPES) do
        if recipe.charges and MacroSelected(recipe) then
            local info = C_TradeSkillUI.GetRecipeInfo(recipe.id)
            if info and info.learned == false then return "Рецепт не изучен", "999999" end
            local saved = current and current.charges and current.charges[recipe.id]
            local schedule = FullBatchSchedule(recipe, saved)
            if not schedule then return "Ждём данные", "999999" end
            schedules[#schedules + 1] = schedule
            for id, cost in pairs(schedule.costs) do
                if stock[id] == nil then stock[id] = id == DERIVATE and BagCount(id) or Count(id) end
                firstRound[id] = (firstRound[id] or 0) + cost
            end
        end
    end
    if #schedules == 0 then return end
    for id, cost in pairs(firstRound) do
        if stock[id] < cost then return "Не хватает", "FF6060" end
    end

    local function BatchesBy(schedule, seconds)
        if seconds < schedule.first then return 0 end
        return 1 + math.floor((seconds - schedule.first) / schedule.interval)
    end

    local function CanAfford(seconds)
        local used = {}
        for _, schedule in ipairs(schedules) do
            local batches = BatchesBy(schedule, seconds)
            for id, cost in pairs(schedule.costs) do
                used[id] = (used[id] or 0) + batches * cost
                if used[id] > stock[id] then return false end
            end
        end
        return true
    end

    local sample = schedules[1]
    local low = 0
    -- This timestamp includes more full batches of the first recipe than the extract can cover.
    local high = sample.first + math.floor(stock[DERIVATE] / sample.costs[DERIVATE]) * sample.interval
    while low + 1 < high do
        local middle = math.floor((low + high) / 2)
        if CanAfford(middle) then low = middle else high = middle end
    end

    local total, last = 0, 0
    for _, schedule in ipairs(schedules) do
        local batches = BatchesBy(schedule, low)
        total = total + batches
        if batches > 0 then last = math.max(last, schedule.first + (batches - 1) * schedule.interval) end
    end
    if total <= #schedules + 1 then return "Последний крафт", "FFD100" end
    local days = math.ceil(last / 86400)
    return "до ~" .. date("%d.%m", GetServerTime() + days * 86400), "1EFF00"
end

-- ── Окно ──────────────────────────────────────────────────────────────────
local win, rows = nil, {}
local dismissed = false
local manualOpen = false
local moving = false
local ROW_H = 24
local W = (ns.OrderQueue and ns.OrderQueue.WINDOW_WIDTH) or 400
local ICON_SIZE, ROW_GAP = 20, 6
local Buffs = ns.OrderQueue and ns.OrderQueue.ProfessionBuffs
local buffHolder, buffButtons, missingIcons = nil, {}, {}

local function BuffState(profession)
    local missing, gate, ready = {}, nil, false
    if not Buffs or ns.db.features.concCraftBuffs == false then return missing end
    if not profession then return missing end
    local ench = profession == Enum.Profession.Enchanting
    local tools = ns.db.tools
    for _, def in ipairs(Buffs.DEFS) do
        if tools[def.key] ~= false and (not def.enchOnly or ench) then
            if not Buffs.HasBuff(def.spell) then
                local item = tools[def.cfg]
                local have = Buffs.BagCount(item) > 0
                if not have then missing[#missing + 1] = { def = def, item = item } end
                -- The flask goes first when both buffs are missing.
                if not gate or not def.enchOnly then
                    gate, ready = def, have
                end
            end
        end
    end
    return missing, gate, ready
end

-- Separate parent and screen coordinates keep the craft window movable in combat.
local function SyncBuffButtons()
    if InCombatLockdown() then return end
    for i, row in ipairs(rows) do
        local visible = win:IsVisible() and row:IsShown() and row.buffReady and not moving
        local x, y
        if visible then x, y = row.btn:GetCenter() end
        local button = buffButtons[i]
        if x and y then
            if not buffHolder then
                buffHolder = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
                buffHolder:SetAllPoints(UIParent)
                buffHolder:SetFrameStrata("HIGH")
                RegisterStateDriver(buffHolder, "visibility", "[combat] hide; show")
            end
            if not button then
                button = CreateFrame("Button", nil, buffHolder, "SecureActionButtonTemplate")
                button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
                button:SetScript("PreClick", function(self)
                    if InCombatLockdown() then return end
                    local def
                    if ns.ProfEnabled() and win:IsVisible() and row:IsVisible() and not moving
                        and ProfessionsFrame and ProfessionsFrame:IsShown() then
                        local _, current = BuffState(Buffs.CurrentProfession())
                        if current == row.buff then def = current end
                    end
                    Buffs.SetBagAction(self, def, def and ns.db.tools[def.cfg])
                end)
                button:SetScript("OnEnter", function(self)
                    row.btn:LockHighlight()
                    row.btn:GetScript("OnEnter")(self)
                end)
                local function ReleaseButton()
                    if row.btn:GetButtonState() == "PUSHED" then
                        row.btn:SetButtonState("NORMAL", false)
                    end
                end
                button:SetScript("OnMouseDown", function(_, mouseButton)
                    if mouseButton == "LeftButton" then row.btn:SetButtonState("PUSHED", true) end
                end)
                button:SetScript("OnMouseUp", ReleaseButton)
                local function ClearHover(self)
                    row.btn:UnlockHighlight()
                    ReleaseButton()
                    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
                end
                button:SetScript("OnHide", ClearHover)
                button:SetScript("OnLeave", ClearHover)
                buffButtons[i] = button
            end
            local scale = row.btn:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if x ~= button.x or y ~= button.y or scale ~= button.scale then
                button:ClearAllPoints()
                button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
                button:SetSize(row.btn:GetWidth() * scale, row.btn:GetHeight() * scale)
                button.x, button.y, button.scale = x, y, scale
            end
            local level = row.btn:GetFrameLevel() + 5
            if button:GetFrameLevel() ~= level then button:SetFrameLevel(level) end
            if not button:IsShown() then button:Show() end
        elseif button and button:IsShown() then
            button:Hide()
        end
    end
end

local function ShowMissingIcons(missing)
    for i, entry in ipairs(missing) do
        local icon = missingIcons[i]
        if not icon then
            icon = CreateFrame("Frame", nil, win)
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon:SetPoint("TOPRIGHT", win, "TOPLEFT", -8, -26 - (i - 1) * 34)
            icon.texture = icon:CreateTexture(nil, "ARTWORK")
            icon.texture:SetAllPoints()
            Buffs.Glow(icon)
            icon:EnableMouse(true)
            icon:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(self.entry.def.title)
                local item = self.entry.item
                local name = item and C_Item.GetItemNameByID(item)
                if name then GameTooltip:AddLine(name, 1, 1, 1) end
                GameTooltip:AddLine("Выбранного предмета нет в сумках.", 1, 0.4, 0.4)
                GameTooltip:Show()
            end)
            icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
            missingIcons[i] = icon
        end
        icon.entry = entry
        icon.texture:SetTexture((entry.item and C_Item.GetItemIconByID(entry.item)) or entry.def.fallback)
        if not icon:IsShown() or not icon.glowing then
            icon:Show()
            icon:SetGlow(true)
            icon.glowing = true
        end
    end
    for i = #missing + 1, #missingIcons do
        missingIcons[i]:SetGlow(false)
        missingIcons[i].glowing = false
        missingIcons[i]:Hide()
    end
end

local function OutputIcon(recipe)
    local ok, item = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipe.id)
    return (ok and item and Num(item.icon)) or recipe.icon
end

local function SavePos()
    local p, _, rp, x, y = win:GetPoint()
    DBc().pos = { p, rp, x, y }
end

local Refresh
local macroCursor = {}
local lastMacroCraft = -math.huge

local function StartCraft(r, res)
    local ok, err
    if r == RECYCLE_RECIPE then
        local location = C_Item.GetItemLocation(res.target.itemGUID)
        if not (location and location:IsValid()) then
            Refresh()
            return false
        end
        ok, err = pcall(C_TradeSkillUI.CraftSalvage, r.id, res.n, location, res.tbl, false)
    else
        ok, err = pcall(C_TradeSkillUI.CraftRecipe, r.id, res.n, res.tbl, nil, nil, res.cost ~= nil)
    end
    if ok then
        ns.Print(C("71d5ff", r.name) .. ": " .. C("1eff00", "крафтов " .. res.n) ..
            (res.cost and (" (концентрация " .. res.have .. ", 1 крафт = " .. res.cost .. ")") or "") ..
            (r.charges and (" (зарядов " .. (res.charges or 0) .. ")") or ""))
    else
        ns.Print(C("71d5ff", r.name) .. ": " .. C("ff6060", "игра не начала крафт — " .. tostring(err)))
    end
    C_Timer.After(0.5, function() if Refresh then Refresh() end end)
    return ok
end

local function CraftInProgress()
    return UnitCastingInfo("player") or UnitChannelInfo("player")
        or (Num(C_TradeSkillUI.GetRemainingRecasts()) or 0) > 0
end

local function Craft(r)
    if InCombatLockdown and InCombatLockdown() then return end
    if not (ns.ProfEnabled() and ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
    local res
    if r == RECYCLE_RECIPE then
        if CraftInProgress() then return end
        res = CheckRecycle()
    else
        local profession = Buffs and Buffs.CurrentProfession()
        local _, gate = BuffState(profession)
        if gate then Refresh(); return end
        res = Check(r)
    end
    if not res then return end
    if res.n <= 0 then ns.Print(C("71d5ff", r.name) .. ": " .. C("ff6060", res.why or "сейчас нельзя")); return end
    StartCraft(r, res)
end

local function MacroCraft(mode)
    if not ns.ProfEnabled() then return end
    if InCombatLockdown() then return end
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    if not (page and page:IsVisible()) or (Professions and Professions.InLocalCraftingMode and not Professions.InLocalCraftingMode()) then
        ns.Print("Сначала открой вкладку крафта нужной профессии.")
        return
    end
    if GetTime() - lastMacroCraft < 0.5 or CraftInProgress() then return end

    local _, gate = BuffState(Buffs and Buffs.CurrentProfession())
    if gate then
        ns.Print("Перед крафтом примени «" .. gate.title .. "».")
        return
    end

    local cooldowns = mode == "cooldowns"
    local cursor = macroCursor[mode] or 0
    for offset = 1, #RECIPES do
        local index = (cursor + offset - 1) % #RECIPES + 1
        local recipe = RECIPES[index]
        if MacroSelected(recipe) and ((cooldowns and recipe.charges) or (not cooldowns and recipe.conc ~= false)) then
            local info = C_TradeSkillUI.GetRecipeInfo(recipe.id)
            if info and info.learned and not info.disabled and info.craftable ~= false then
                local res = Check(recipe)
                if res and res.n > 0 and (cooldowns or res.cost) then
                    if StartCraft(recipe, res) then
                        macroCursor[mode] = index
                        lastMacroCraft = GetTime()
                    end
                    return
                end
            end
        end
    end
    ns.Print(cooldowns and "Сейчас нет доступных отмеченных крафтов по зарядам."
        or "Сейчас нет доступных отмеченных крафтов за концентрацию.")
end

SLASH_RAINONUICRAFT1 = "/rscraft"
SlashCmdList.RAINONUICRAFT = function(text)
    local mode = strtrim(text):lower()
    if mode == "concentration" or mode == "cooldowns" then MacroCraft(mode) end
end

local recycleForm
local recycleAllocation

local function FillRecyclePotion(form, replace)
    if not ns.ProfEnabled() or InCombatLockdown() then return end
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    if not (page and page:IsVisible() and form and form.salvageSlot) then return end
    if Professions and Professions.InLocalCraftingMode and not Professions.InLocalCraftingMode() then return end
    local info = form:GetRecipeInfo()
    if not (info and info.learned and Num(info.recipeID) == RECYCLE_POTIONS) then return end
    local transaction = form:GetTransaction()
    local selected = transaction:GetSalvageAllocation()
    if selected and (not replace or selected ~= recycleAllocation) then return end

    local schematic = transaction:GetRecipeSchematic()
    local target = schematic and RecycleTarget(schematic)
    local item = target and Item:CreateFromItemGUID(target.itemGUID)

    if selected or item then
        recycleAllocation = item
        transaction:SetSalvageAllocation(item)
        if item then form.salvageSlot:SetItem(item) else form.salvageSlot:ClearReagent() end
        form:TriggerEvent(ProfessionsRecipeSchematicFormMixin.Event.AllocationsModified)
    end
end

local function HookRecycleForm()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    if not (form and form.Init) then return end
    if recycleForm ~= form then
        recycleForm = form
        hooksecurefunc(form, "Init", function(self) FillRecyclePotion(self) end)
    end
    FillRecyclePotion(form)
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
    win:SetScript("OnDragStart", function(self)
        if DBc().locked then return end
        moving = true
        SyncBuffButtons()
        self:StartMoving()
    end)
    win:SetScript("OnDragStop", function(self)
        if not moving then return end
        moving = false
        self:StopMovingOrSizing()
        SavePos()
        SyncBuffButtons()
    end)
    win:SetTitle("Крафт за концентрацию")
    local pos = DBc().pos
    if pos then
        win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        win:SetPoint("CENTER", UIParent, "CENTER")
    end

    local close = win.CloseButton
    close:HookScript("OnClick", function()
        dismissed = true
        manualOpen = false
    end)
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
    -- Blizzard's title bar starts one pixel below the top of the frame.
    title:SetPoint("CENTER", win, "TOP", 0, -1 - win.TitleContainer:GetHeight() / 2)
    title:SetJustifyH("CENTER")
    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.empty:SetPoint("TOPLEFT", 12, -32)
    win:HookScript("OnHide", function()
        if moving then
            moving = false
            win:StopMovingOrSizing()
            SavePos()
        end
        SyncBuffButtons()
    end)
    local elapsed = 0
    win:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        SyncBuffButtons()
    end)
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
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetPoint("RIGHT", 0, 0)
    r.check = ns.MakeCheckButton(r)
    r.check:SetSize(24, 24)
    r.check:SetPoint("RIGHT", -46, 0)
    r.check:SetScript("OnClick", function(self)
        SetMacroSelection(r.recipe, self:GetChecked() and true or false)
    end)
    r.check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(r.recipe.charges and "Включить в макрос крафта по зарядам"
            or "Включить в макрос крафта за концентрацию")
        GameTooltip:Show()
    end)
    r.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.btn:SetScript("OnClick", function() if r.recipe then Craft(r.recipe) end end)
    r.btn:SetScript("OnEnter", function(self)
        if r.buff then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(r.buff.title, 1, 1, 1)
            GameTooltip:AddLine(r.buffReady and "Нажми, чтобы применить бафф." or "Выбранного предмета нет в сумках.", 1, 0.82, 0)
            GameTooltip:Show()
            return
        end
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

local function UpdateRow(row, recipe, res, gate, ready)
    local enabled = gate and ready or (not gate and res.n > 0)
    local recycling = recipe == RECYCLE_RECIPE
    if row.recipe ~= recipe then
        row.icon:SetTexture(recycling and (C_Item.GetItemIconByID(DERIVATE) or recipe.icon) or OutputIcon(recipe))
        row.name:SetPoint("RIGHT", recycling and -44 or -74, 0)
    end
    row.recipe, row.res, row.buff, row.buffReady = recipe, res, gate, gate and ready
    row.check:SetShown(not recycling)
    if not recycling then row.check:SetChecked(MacroSelected(recipe)) end
    local name = recipe.name
    local nameText = enabled and name or C("808080", name)
    if recycling then
        local forecast, color = DerivateForecast()
        if forecast then nameText = nameText .. " · " .. C(color, forecast) end
    end
    row.icon:SetDesaturated(not enabled)
    row.name:SetText(nameText)
    row.info:SetText(enabled and res.n > 0 and C("1eff00", "×" .. res.n) or C("808080", "×0"))
    row.btn:SetText(gate and "Бафф" or "Крафт")
    -- Only the separate secure button can receive a buff click.
    row.btn:SetEnabled(enabled and true or false)
    row:Show()
end

local auraWatcher = CreateFrame("Frame")
Refresh = function()
    if not ns.db or not ns.ProfEnabled() or dismissed
        or (ns.db.features.concCraft == false and not manualOpen)
        or not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
        auraWatcher:UnregisterEvent("UNIT_AURA")
        if win then
            win:Hide()
            SyncBuffButtons()
        end
        return
    end
    if not auraWatcher:IsEventRegistered("UNIT_AURA") then
        auraWatcher:RegisterUnitEvent("UNIT_AURA", "player")
    end
    local profession = Buffs and Buffs.CurrentProfession()
    local missing, gate, ready = BuffState(profession)
    local n = 0
    for _, rec in ipairs(RECIPES) do
        local res = Check(rec)
        if res then
            if not win then Build() end
            n = n + 1
            UpdateRow(Row(n), rec, res, gate, ready)
        end
    end
    local recycling = CheckRecycle()
    if recycling then
        if not win then Build() end
        n = n + 1
        UpdateRow(Row(n), RECYCLE_RECIPE, recycling)
    end
    if n == 0 and #missing == 0 and not manualOpen then
        if win then
            win:Hide()
            SyncBuffButtons()
        end
        return
    end
    if not win then Build() end
    for i = n + 1, #rows do rows[i]:Hide() end
    win.empty:SetText("У этой профессии рецептов из списка нет")
    win.empty:SetShown(n == 0)
    ShowMissingIcons(missing)
    win:SetClampRectInsets(#missing > 0 and -36 or 0, 0, 0, 0)
    win:SetHeight(math.max(36 + math.max(1, n) * ROW_H, #missing == 2 and 86 or 0))
    win:Show()
    SyncBuffButtons()
end

ns.RegisterEvent("TRADE_SKILL_SHOW", function()
    dismissed = false
    manualOpen = false
    HookRecycleForm()
    C_Timer.After(0.3, function()
        HookRecycleForm()
        Refresh()
    end)
end)
ns.RegisterEvent("TRADE_SKILL_CLOSE", function()
    manualOpen = false
    macroCursor = {}
    recycleAllocation = nil
    auraWatcher:UnregisterEvent("UNIT_AURA")
    if win then win:Hide() end
end)
for _, e in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "BAG_UPDATE_DELAYED",
    "CURRENCY_DISPLAY_UPDATE", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "PLAYER_REGEN_ENABLED" }) do
    ns.RegisterEvent(e, Refresh)
end
ns.RegisterMessage("RAINON_PROFESSIONS_TOGGLED", function()
    if ns.ProfEnabled() then
        HookRecycleForm()
    else
        manualOpen = false
        macroCursor = {}
    end
    Refresh()
end)
ns.RegisterMessage("RAINON_CRAFT_SELECTION_CHANGED", Refresh)
local auraQueued = false
auraWatcher:SetScript("OnEvent", function()
    if auraQueued or not (ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
    auraQueued = true
    C_Timer.After(0.1, function() auraQueued = false; Refresh() end)
end)

ns.ConcCraft = {
    RECIPES = RECIPES,
    Check = Check,
    Refresh = function() Refresh() end,
    Open = function()
        if not ns.ProfEnabled() then return end
        if InCombatLockdown() then
            ns.Print("Крафт за концентрацию: открой окно после боя.")
            return
        end
        if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
            ns.Print("Крафт за концентрацию: сначала открой окно профессии.")
            return
        end
        dismissed = false
        manualOpen = true
        Refresh()
    end,
    ApplyVisibility = function()
        manualOpen = false
        dismissed = false
        Refresh()
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
local function QualityOptions(values)
    local qualityOptions = {}
    for quality, label in ipairs({ "Обычное", "Золотое" }) do
        qualityOptions[quality] = {
            text = CreateAtlasMarkup(QUALITY_ATLAS .. quality, 16, 16),
            value = values and values[quality] or quality,
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
    return qualityOptions
end

local function ItemBox(parent, width, dropdown, get, set, options, withCount)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, 24)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.11, 0.11, 0.11, 0.85)
    box.dropdown = dropdown(box, 44, get, set, options)
    box.dropdown:SetPoint("LEFT", 2, 0)
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetSize(20, 20)
    box.icon:SetPoint("LEFT", box.dropdown, "RIGHT", 6, 0)
    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.label:SetPoint("LEFT", box.icon, "RIGHT", 6, 0)
    box.label:SetJustifyH("LEFT")
    box.label:SetWordWrap(false)
    box.label:SetMaxLines(1)
    if withCount then
        local separator = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        separator:SetPoint("LEFT", box, "RIGHT", -46, 0)
        separator:SetText("·")
        box.label:SetPoint("RIGHT", separator, "LEFT", -4, 0)
        box.count = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        box.count:SetPoint("LEFT", separator, "RIGHT", 5, 0)
    else
        box.label:SetPoint("RIGHT", -6, 0)
    end
    return box
end

function ns.ConcCraft.BuildPhialOption(parent, anchor, dropdown, onChange)
    local function GetItem() return ns.db.tools.phialQuality end
    local box
    local function UpdateIcon()
        box.icon:SetTexture(C_Item.GetItemIconByID(GetItem()) or 134756)
    end
    box = ItemBox(parent, 405, dropdown, GetItem, function(item)
        ns.db.tools.phialQuality = item
        UpdateIcon()
        onChange()
    end, QualityOptions({ 241313, 241312 }))
    box:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    box.label:SetText("Харанирский флакон изобретательности")
    UpdateIcon()
end

function ns.ConcCraft.BuildRecycleOption(parent, dropdown, makeSpoilerBar)
    local options = { { text = "Выключено", value = 0 } }
    for _, potion in ipairs(POTIONS) do
        options[#options + 1] = {
            text = "|T" .. potion.icon .. ":16|t " .. potion.name,
            value = potion.id,
        }
    end
    local bar, updateGlyph = makeSpoilerBar(parent, "Переработка зелий", "Interface\\Icons\\ui_profession_alchemy", 32)
    bar:SetPoint("TOPLEFT", 8, 0)
    bar:SetPoint("TOPRIGHT", -8, 0)
    local picker = dropdown(parent, 268,
        function() return DBc().recyclePotion or 0 end,
        function(itemID)
            DBc().recyclePotion = itemID
            FillRecyclePotion(recycleForm, true)
            Refresh()
        end, options)
    picker:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 12, -6)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", picker, "RIGHT", 8, 0)
    label:SetText("Зелье первого ранга")
    picker:Hide()
    label:Hide()
    parent:SetHeight(32)
    updateGlyph(true)
    bar:SetScript("OnClick", function()
        local expanded = not picker:IsShown()
        picker:SetShown(expanded)
        label:SetShown(expanded)
        updateGlyph(not expanded)
        parent:SetHeight(expanded and 66 or 32)
    end)
end

function ns.ConcCraft.BuildOptions(parent, dropdown, makeSpoilerBar)
    local rowGap = 8
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", 12, -rowGap)
    hint:SetWidth(572)
    hint:SetJustifyH("LEFT")
    hint:SetText("Окно «Крафт за концентрацию» использует выбранные реагенты из настроек текущего раздела.")
    local y = -hint:GetStringHeight() - 2 * rowGap
    local qualityOptions = QualityOptions()
    local updates = {}
    local previousRow
    for _, rec in ipairs(RECIPES) do
        local recipe = rec
        local row = CreateFrame("Frame",nil,parent)
        row:SetWidth(572)
        if previousRow then
            row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -rowGap)
        else
            row:SetPoint("TOPLEFT", 12, y)
        end
        previousRow = row
        local title = recipe.name .. (recipe.charges and recipe.conc == false and " — по зарядам, без концентрации" or "")
        local bar, updateGlyph = makeSpoilerBar(row, title, recipe.icon, 32)
        bar:SetPoint("TOPLEFT", -4, 0)
        bar:SetPoint("TOPRIGHT", 4, 0)
        local body = CreateFrame("Frame", nil, row)
        body:SetSize(572, 86)
        body:SetPoint("TOPLEFT", 0, -bar:GetHeight() - 6)
        body:Hide()
        local closedHeight = bar:GetHeight()
        local expandedHeight = closedHeight + 6 + body:GetHeight()
        row:SetHeight(closedHeight)
        updateGlyph(true)
        bar:SetScript("OnClick", function()
            local expanded = not body:IsShown()
            local oldHeight = row:GetHeight()
            row:SetHeight(expanded and expandedHeight or closedHeight)
            body:SetShown(expanded)
            updateGlyph(not expanded)
            parent:SetHeight(parent:GetHeight() + row:GetHeight() - oldHeight)
        end)
        local slots, cells = {}, {}
        local Render
        for i = 1, 6 do
            local slotIndex = i
            local cell = ItemBox(body, 280, dropdown,
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
                end, qualityOptions, true)
            cell:SetPoint("TOPLEFT", ((i - 1) % 2) * 292, -math.floor((i - 1) / 2) * 26)
            cells[i] = cell

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
        local empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", 2, 0)
        empty:SetText("Открой эту профессию, чтобы загрузить состав реагентов.")
        Render = function()
            for i, cell in ipairs(cells) do
                local slot = slots[i]
                cell:SetShown(slot ~= nil)
                if slot then
                    local hasQuality = HasQuality(slot)
                    local id = slot.ids[1]
                    cell.dropdown:SetEnabled(hasQuality)
                    if hasQuality then
                        local quality = SelectedQuality(recipe, slot)
                        id = ItemForQuality(slot, quality) or id
                        cell.dropdown:SetText(qualityOptions[quality].text)
                    else
                        cell.dropdown:SetText("")
                    end
                    cell.itemID = id
                    cell.icon:SetTexture(C_Item.GetItemIconByID(id) or 134400)
                    local name = ItemLabel(id)
                    local shorten = ns.OrderQueue and ns.OrderQueue.ShortItemName
                    cell.label:SetText(shorten and shorten(name, 17) or name)
                    cell.count:SetText(tostring(slot.qty))
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
        y = y - row:GetHeight() - rowGap
    end
    local function UpdateOptions()
        for _, update in ipairs(updates) do update() end
    end
    parent:HookScript("OnShow", UpdateOptions)
    ns.RegisterEvent("TRADE_SKILL_LIST_UPDATE",function()
        if not ns.ProfEnabled() then return end
        if parent:IsVisible() then
            UpdateOptions()
        else
            for _, recipe in ipairs(RECIPES) do Slots(recipe) end
        end
    end)
    parent:SetHeight(-y + rowGap * 2)
end
end
