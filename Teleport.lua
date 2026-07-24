-- =========================================================================
-- RainonUI / Teleport: окно телепорта в подземелье при вступлении в группу.
--
-- Когда игрок принимает приглашение в группу Поиска групп (LFG) на подземелье,
-- у которого есть телепорт, показываем маленький попап с названием подземелья
-- и кнопкой телепорта в один клик. Попап прячется при входе в подземелье,
-- выходе из группы или входе в бой.
--
-- Порт логики Ellesmere QoL под наш стиль. Критично — безопасность тейнта и
-- «секретных значений» Midnight (12.0):
--  * spellID телепорта, который идёт в SetAttribute("spell", id), — ВСЕГДА
--    статичное целое из нашей таблицы имён, никогда не поле LFG.
--  * подземелье определяем на LFG_LIST_JOINED_GROUP (после вступления инфо
--    результата читается; во время просмотра/заявки это секреты). Каждое поле
--    защищаем issecretvalue() и весь разбор оборачиваем в pcall — секрет может
--    только отменить показ, но не уронить с ошибкой.
--  * секретную кнопку создаём один раз вне боя; атрибут "spell" переписываем
--    только вне боя (в бою откладываем до PLAYER_REGEN_ENABLED).
--  * никакие фреймы Blizzard не хукаем и не трогаем.
-- =========================================================================
local _, ns = ...

local issecretvalue = issecretvalue or function() return false end

-- Порталы текущего сезона: spellID + имена (англ/рус, нижним регистром).
-- Обновлять здесь раз в сезон. altSpellIDs — если у подземелья несколько
-- вариантов спелла телепорта (берём тот, что изучен).
local SEASON_PORTALS = {
    { spellID = 1254400, names = { "windrunner spire", "шпиль ветрокрылых" } },
    { spellID = 1254572, names = { "magisters' terrace", "терраса магистров" } },
    { spellID = 1254563, names = { "nexus-point xenas", "нексус-пойнт ксенас", "нексус-поинт ксенас" } },
    { spellID = 1254559, names = { "maisara caverns", "пещеры майсара" } },
    { spellID = 159898,  altSpellIDs = { 1254557 }, names = { "skyreach", "небесный путь" } },
    { spellID = 1254555, names = { "pit of saron", "яма сарона" } },
    { spellID = 1254551, names = { "seat of the triumvirate", "престол триумвирата" } },
    { spellID = 393273,  names = { "algeth'ar academy", "академия алгет'ар", "академия алгетар" } },
}

-- имя (нижним регистром, без хвостовой скобки) -> запись портала
local PORTAL_BY_NAME = {}
for _, e in ipairs(SEASON_PORTALS) do
    for _, n in ipairs(e.names) do PORTAL_BY_NAME[n] = e end
end

-- Выбрать изученный спелл среди основного и альтернативных (или основной).
local function PickSpell(entry)
    if not entry then return nil end
    if IsPlayerSpell and IsPlayerSpell(entry.spellID) then return entry.spellID end
    if entry.altSpellIDs then
        for _, sid in ipairs(entry.altSpellIDs) do
            if IsPlayerSpell and IsPlayerSpell(sid) then return sid end
        end
    end
    return entry.spellID
end

-- Чистый резолвер: имя подземелья -> статичный integer spellID (или nil).
local function ResolveSpellByName(displayName)
    if type(displayName) ~= "string" then return nil end
    local n = displayName:lower():gsub("%s*%b()%s*$", "")
    return PickSpell(PORTAL_BY_NAME[n])
end

local function Enabled()
    return not (ns.db and ns.db.features and ns.db.features.teleportPrompt == false)
end

-- -------------------------------------------------------------------------
-- Состояние
-- -------------------------------------------------------------------------
local popup, secureBtn
local pendingSpellID       -- статичный integer спелла для показа
local pendingName          -- чистое имя подземелья для заголовка
local pendingAttrSpellID   -- отложенная запись атрибута (сработает вне боя)
local pendingShow, pendingHide

-- -------------------------------------------------------------------------
-- Постройка попапа + secure-кнопки (один раз, вне боя)
-- -------------------------------------------------------------------------
local POPUP_W, POPUP_H = 240, 150

local function UpdateButtonVisuals()
    if not (secureBtn and pendingSpellID) then return end
    local sid = pendingSpellID
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
    if info and info.iconID then secureBtn._icon:SetTexture(info.iconID) end
    local known = IsPlayerSpell and IsPlayerSpell(sid)
    secureBtn._icon:SetDesaturated(not known)
    secureBtn._icon:SetAlpha(known and 1 or 0.4)
    local lc = known and 1 or 0.5
    if secureBtn._label then secureBtn._label:SetTextColor(lc, lc, lc, 1) end
    local cd = secureBtn._cd
    if known then
        local ci = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
        if ci and ci.startTime and ci.duration and ci.duration > 0 then
            cd:SetCooldown(ci.startTime, ci.duration)
        else cd:Clear() end
    else
        cd:Clear()
    end
end

local SavePosition, RestorePosition, HidePrompt

local function BuildPopup()
    if popup then return popup end

    -- Окно в нашем стиле — на шаблоне Blizzard ButtonFrameTemplate (как окно
    -- знаний): рамка, инсет-бокс, крестик. Портрет прячем.
    popup = CreateFrame("Frame", "RainonUITeleportPopup", UIParent, "ButtonFrameTemplate")
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    -- Свободное перетаскивание — только без Edit Mode-библиотеки. С ней окно
    -- двигается в родном режиме редактирования (Esc → Настройка интерфейса).
    if not (ns.EditMode and ns.EditMode.Available()) then
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", function(s) s:StartMoving() end)
        popup:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); SavePosition() end)
    end
    if popup.SetTitle then popup:SetTitle("Телепорт") end
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(popup) end
    if popup.PortraitContainer then popup.PortraitContainer:Hide() end
    if popup.portrait then popup.portrait:Hide() end
    if popup.CloseButton then
        popup.CloseButton:SetScript("OnClick", function() HidePrompt() end)
    end

    local host = popup.Inset or popup

    -- Имя подземелья (может быть секретной строкой — SetText принимает секреты)
    local nameFS = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameFS:SetPoint("TOPLEFT", host, "TOPLEFT", 6, -8)
    nameFS:SetPoint("TOPRIGHT", host, "TOPRIGHT", -6, -8)
    nameFS:SetHeight(22)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(true)
    popup._name = nameFS

    -- Secure-кнопка телепорта (создаётся вне боя один раз; type/clicks больше
    -- не трогаем, переписываем только "spell" и только вне боя). Клик — на
    -- нажатие И отпускание: в текущем клиенте каст привязан к нажатию.
    -- Красная кнопка в стиле игрового меню (ESC) — MainMenuFrameButtonTemplate
    -- даёт вид, SecureActionButtonTemplate — защищённый каст. Совмещаем шаблоны.
    secureBtn = CreateFrame("Button", "RainonUITeleportButton", host,
        "SecureActionButtonTemplate, MainMenuFrameButtonTemplate")
    secureBtn:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 8, 8)
    secureBtn:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 8)
    secureBtn:SetHeight(40)
    secureBtn:RegisterForClicks("AnyDown", "AnyUp")
    secureBtn:SetAttribute("type", "spell")
    secureBtn:SetText("Телепортироваться")
    secureBtn._label = secureBtn:GetFontString()

    -- Маленькая иконка спелла слева + кулдаун на ней
    local icon = secureBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    secureBtn._icon = icon

    local cd = CreateFrame("Cooldown", nil, secureBtn, "CooldownFrameTemplate")
    cd:SetPoint("CENTER", icon, "CENTER", 0, 0)
    cd:SetSize(26, 26)
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawSwipe(true); cd:SetDrawBling(false); cd:SetDrawEdge(false)
    secureBtn._cd = cd

    secureBtn:SetScript("OnEnter", function(self)
        local sid = pendingSpellID
        if not sid then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not (IsPlayerSpell and IsPlayerSpell(sid)) then
            GameTooltip:SetText("Телепорт ещё не изучен.", 1, 0.5, 0.5, nil, true)
        else
            local ci = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
            if ci and ci.duration and ci.duration > 0 then
                GameTooltip:SetText("Телепорт на кулдауне", 1, 0.7, 0.3)
            else
                GameTooltip:SetText("Телепорт: " .. (pendingName or "подземелье"), 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    secureBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Позиция и размер: через Edit Mode (LibEditMode), иначе — запасной способ.
    if ns.EditMode and ns.EditMode.Available() then
        ns.EditMode.Register(popup, {
            name = "RainonUI: Телепорт",
            key = "teleport",
            defaultX = 0, defaultY = 150,
            showInEditMode = true,
            onEditModeShow = function(f)
                if f._name then f._name:SetText("") end
            end,
        })
    else
        popup:SetScale((ns.db.features and ns.db.features.teleportScale) or 1.0)
        RestorePosition()
    end
    popup:Hide()
    return popup
end

SavePosition = function()
    if not (popup and ns.db and ns.db.features) then return end
    local p, _, rp, x, y = popup:GetPoint()
    if p then ns.db.features.teleportPos = { p = p, rp = rp, x = x, y = y } end
end

RestorePosition = function()
    if not popup then return end
    popup:ClearAllPoints()
    local pos = ns.db.features and ns.db.features.teleportPos
    if pos and pos.p then
        popup:SetPoint(pos.p, UIParent, pos.rp or pos.p, pos.x or 0, pos.y or 0)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

-- -------------------------------------------------------------------------
-- Показ / скрытие
-- -------------------------------------------------------------------------
local function ShowPrompt()
    if not Enabled() or not pendingSpellID then return end
    BuildPopup()
    popup._name:SetText(pendingName or "")
    if InCombatLockdown() then
        -- В бою нельзя писать secure-атрибут и показывать защищённую кнопку
        -- (да и телепорт в бою не сработает) — откладываем весь показ.
        pendingAttrSpellID = pendingSpellID
        pendingShow = true
        pendingHide = nil
        return
    end
    secureBtn:SetAttribute("spell", pendingSpellID)
    pendingAttrSpellID = nil
    pendingHide = nil
    UpdateButtonVisuals()
    popup:Show()
end

HidePrompt = function()
    pendingShow = nil
    -- popup содержит secure-кнопку, поэтому popup:Hide() в бою заблокирован.
    if not (popup and popup:IsShown()) then pendingHide = nil; return end
    if InCombatLockdown() then pendingHide = true; return end
    pendingHide = nil
    popup:Hide()
end

local function ClearPending()
    pendingSpellID = nil
    pendingName = nil
    pendingShow = nil
end

-- Определить подземелье из принятого результата LFG (чистой строковой цепочкой)
local function ResolveDungeon(resultID)
    if not (C_LFGList and C_LFGList.GetSearchResultInfo) then return end
    pcall(function()
        local info = C_LFGList.GetSearchResultInfo(resultID)
        if type(info) ~= "table" then return end
        local activityID = info.activityID
        if activityID == nil and info.activityIDs and not issecretvalue(info.activityIDs) then
            activityID = info.activityIDs[1]
        end
        if issecretvalue(activityID) or activityID == nil then return end
        local act = C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(activityID)
        if type(act) ~= "table" then return end
        local fullName = act.fullName
        if type(fullName) ~= "string" or issecretvalue(fullName) then return end
        local spellID = ResolveSpellByName(fullName)
        if spellID then
            pendingSpellID = spellID
            pendingName = (fullName:gsub("%s*%b()%s*$", "")) -- убрать хвост «(…)»
        end
    end)
end

-- Публичное — для опций/слэша
ns.Teleport = {
    Refresh = function()
        if not popup then return end
        popup:SetScale((ns.db.features and ns.db.features.teleportScale) or 1.0)
    end,
    Hide = function() ClearPending(); HidePrompt() end,
    -- Тест окна вне ЛФГ: подставляем первый портал сезона и показываем.
    -- Ошибку печатаем в чат, даже если скрипт-ошибки в игре отключены.
    Test = function()
        local e = SEASON_PORTALS[1]
        pendingSpellID = PickSpell(e)
        pendingName = "Тест телепорта"
        local ok, err = pcall(ShowPrompt)
        if not ok then
            ns.Print("ошибка окна телепорта: " .. tostring(err))
        elseif popup and popup:IsShown() then
            ns.Print("окно телепорта показано (тест). Enabled=" .. tostring(Enabled()))
        else
            ns.Print("ShowPrompt отработал, но окно скрыто. Enabled=" ..
                tostring(Enabled()) .. ", spell=" .. tostring(pendingSpellID))
        end
    end,
}

-- Тест-команда: /rstptest — форсим показ окна, чтобы отделить рендер от ЛФГ.
SLASH_RAINONTELETEST1 = "/rstptest"
SlashCmdList.RAINONTELETEST = function() ns.Teleport.Test() end

-- -------------------------------------------------------------------------
-- События
-- -------------------------------------------------------------------------
ns.RegisterEvent("PLAYER_LOGIN", function()
    if Enabled() then BuildPopup() end -- логин вне боя — безопасно создать secure-кнопку
end)

ns.RegisterEvent("LFG_LIST_JOINED_GROUP", function(searchResultID)
    if not Enabled() then return end
    -- Момент вступления в группу — инфо результата читаемо (в отличие от фазы
    -- просмотра/заявки). Захватываем сразу: результат может протухнуть.
    ClearPending()
    ResolveDungeon(searchResultID)
    if pendingSpellID then ShowPrompt() end
end)

ns.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if not IsInGroup() then ClearPending(); HidePrompt() end
end)

local function OnZone()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "party" then
        ClearPending(); HidePrompt()
    end
end
ns.RegisterEvent("PLAYER_ENTERING_WORLD", OnZone)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", OnZone)

ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    HidePrompt() -- телепорт в бою невозможен
end)

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    -- дописать secure-атрибут, заблокированный в бою
    if pendingAttrSpellID and secureBtn then
        secureBtn:SetAttribute("spell", pendingAttrSpellID)
        pendingAttrSpellID = nil
    end
    if pendingShow and pendingSpellID and Enabled() then
        pendingShow = nil
        UpdateButtonVisuals()
        if popup then popup:Show() end
    end
    if pendingHide then
        pendingHide = nil
        if popup and popup:IsShown() then popup:Hide() end
    end
end)