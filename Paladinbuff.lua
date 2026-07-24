-- =========================================================================
-- RainonUI / PaladinBuff: кликабельная иконка «Освятить оружие» для паладина.
--
-- Каст спелла из кода — защищённое действие (нужен hardware-event). Поэтому
-- иконка — это SecureActionButton с type="macro": игрок сам кликает, и клик
-- (аппаратное событие) запускает макрос. Атрибуты защищённой кнопки нельзя
-- менять в бою, а Show/Hide защищённого фрейма в бою заблокированы — поэтому
-- макрос ставим один раз при создании (вне боя), а показ/скрытие в бою
-- откладываем до выхода из боя (PLAYER_REGEN_ENABLED).
--
-- Логика показа: иконка появляется, когда на основном оружии НЕТ временного
-- зачарования (GetWeaponEnchantInfo) — т.е. обряд пора наложить. Как только
-- зачар появился — прячем. В бою «всплыть» не может (защищённый фрейм), это
-- ограничение Midnight — накладывай до пула.
-- =========================================================================
local _, ns = ...

local MACRO = "/cast Обряд освящения(Усиленное оружие)\n/use 16"
local ICON  = 237172 -- fileID иконки (задаётся пользователем)
-- Обряд освящения (Усиленное оружие) — spellID 433568. Доступен ТОЛЬКО в
-- героической ветке «Кузнец света»; если талант не взят, спелл не изучен.
local RITE_SPELL = 433568

local function Enabled()
    return not (ns.db and ns.db.features and ns.db.features.paladinWeapon == false)
end

local function IsPaladin()
    local _, class = UnitClass("player")
    return class == "PALADIN"
end

-- Изучен ли обряд (т.е. взята героическая ветка «Кузнец света»)
local function KnowsRite()
    if IsPlayerSpell and IsPlayerSpell(RITE_SPELL) then return true end
    if IsSpellKnown and IsSpellKnown(RITE_SPELL) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, RITE_SPELL)
        if ok and known then return true end
    end
    return false
end

local REBUFF_MS = 30 * 60 * 1000 -- порог 30 минут: меньше — пора обновлять

-- Нужно ли напомнить об обряде: баффа нет ИЛИ осталось меньше 30 минут.
-- Возвращает: need(bool), hasBuff(bool) — hasBuff для текста подсказки.
local function NeedBuff()
    if not GetWeaponEnchantInfo then return true, false end
    local hasMainHand, mainHandExpiration = GetWeaponEnchantInfo()
    if not hasMainHand then return true, false end                 -- баффа нет
    if (mainHandExpiration or 0) < REBUFF_MS then return true, true end -- <30 мин
    return false, true
end

local btn
local pendingShow, pendingHide

local function SavePos()
    if not (btn and ns.db and ns.db.features) then return end
    local p, _, rp, x, y = btn:GetPoint()
    if p then ns.db.features.paladinPos = { p = p, rp = rp, x = x, y = y } end
end

local function RestorePos()
    if not btn then return end
    btn:ClearAllPoints()
    local pos = ns.db.features and ns.db.features.paladinPos
    if pos and pos.p then
        btn:SetPoint(pos.p, UIParent, pos.rp or pos.p, pos.x or 0, pos.y or 0)
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function Build()
    if btn or not IsPaladin() then return end

    btn = CreateFrame("Button", "RainonUIPaladinButton", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(52, 52)
    btn:SetFrameStrata("HIGH")
    -- Левый клик — каст макроса. Регистрируем и DOWN, и UP: в текущем клиенте
    -- каст привязан к нажатию (cvar ActionButtonUseKeyDown), и с одним "up"
    -- secure-действие не срабатывает. Правый — только для перетаскивания.
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", MACRO)

    btn:SetMovable(true)
    -- Свободное ПКМ-перетаскивание — только без Edit Mode-библиотеки. С ней
    -- иконка двигается в родном режиме редактирования.
    if not (ns.EditMode and ns.EditMode.Available()) then
        btn:RegisterForDrag("RightButton")
        btn:SetScript("OnDragStart", function(s)
            if not InCombatLockdown() then s:StartMoving() end
        end)
        btn:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); SavePos() end)
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = icon

    -- простая тёмная рамка
    local border = btn:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0, 0, 0, 0.9)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetColorTexture(1, 1, 1, 0.18)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Освятить оружие", 1, 1, 1)
        local _, hasBuff = NeedBuff()
        if hasBuff then
            GameTooltip:AddLine("Обряд скоро истечёт (<30 мин) — обнови. Клик.", 1, 0.82, 0.2, true)
        else
            GameTooltip:AddLine("Клик — наложить обряд освящения (усиленное оружие).", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Позиция и размер: через Edit Mode (LibEditMode), иначе — запасной способ.
    if ns.EditMode and ns.EditMode.Available() then
        ns.EditMode.Register(btn, {
            name = "RainonUI: Освящение оружия",
            key = "paladin",
            defaultX = 0, defaultY = 0,
            showInEditMode = true,
            onEditModeHide = function()
                if ns.PaladinBuff and ns.PaladinBuff.Apply then ns.PaladinBuff.Apply() end
            end,
        })
    else
        RestorePos()
    end
    btn:Hide()
end

-- Нужно ли показывать иконку сейчас: паладин + изучен обряд (герой-ветка) +
-- баффа нет или осталось меньше 30 минут.
local function WantShown()
    if not (Enabled() and IsPaladin() and KnowsRite()) then return false end
    return (NeedBuff())
end

local function Apply()
    if not IsPaladin() then
        if btn then btn:Hide() end
        return
    end
    Build()
    if not btn then return end

    -- В режиме редактирования иконка всегда видна — чтобы её можно было
    -- подвинуть, даже когда бафф активен и в бою её обычно не видно.
    if ns.EditMode and ns.EditMode.IsEditing and ns.EditMode.IsEditing() then
        btn:Show()
        return
    end

    local want = WantShown()
    if InCombatLockdown() then
        -- В бою защищённую кнопку не показать/спрятать — откладываем
        if want then pendingShow, pendingHide = true, nil
        else pendingShow, pendingHide = nil, true end
        return
    end
    pendingShow, pendingHide = nil, nil
    if want then btn:Show() else btn:Hide() end
end

-- Публичный доступ (для опций/слэша)
ns.PaladinBuff = { Apply = Apply, Toggle = function()
    if ns.db and ns.db.features then
        ns.db.features.paladinWeapon = not (ns.db.features.paladinWeapon ~= false)
    end
    Apply()
end }

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(1, Apply)
end)
ns.RegisterEvent("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" then Apply() end
end)
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", Apply)
-- смена спека/талантов меняет доступность обряда (герой-ветка)
ns.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", Apply)
ns.RegisterEvent("TRAIT_CONFIG_UPDATED", Apply)
ns.RegisterEvent("SPELLS_CHANGED", Apply)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", Apply)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if btn then
        local want = WantShown()
        if pendingShow then pendingShow = nil; if want then btn:Show() end end
        if pendingHide then pendingHide = nil; if not want then btn:Hide() end end
    end
    Apply()
end)
ns.RegisterMessage("RAINON_REAPPLY", Apply)

-- Главный триггер: проверка готовности (перед пуллом). Именно тут решаем —
-- бафф отсутствует или скоро истечёт (<30 мин): показываем иконку. Так мы не
-- опрашиваем оружие постоянно и не входим в бой без свежего обряда.
ns.RegisterEvent("READY_CHECK", Apply)