-- =========================================================================
-- RainonUI / MDTTooltip: наш блок в подсказке Mythic Dungeon Tools.
--
-- ЧТО ДЕЛАЕТ: когда игрок наводит курсор на противника на карте MDT, MDT
-- показывает свою модель-подсказку (глобальный фрейм "MDTModelTooltip") и
-- заполняет её моделью моба: tooltip.Model:SetCreature(npcID). Мы вешаем
-- пост-хук на SetCreature, ловим npcID и, если он есть в NOTES, дорисовываем
-- снизу свою маленькую рамку с заметкой.
--
-- ПОЧЕМУ ТАК (а не hooksecurefunc(MDT, "DisplayBlipTooltip")): в текущей MDT
-- (ветка Midnight) НЕТ глобала _G.MDT — внутренняя таблица приватная, наружу
-- отдаётся только proxy MythicDungeonToolsAPI без DisplayBlipTooltip. Поэтому
-- цепляемся за то, что MDT называет ГЛОБАЛЬНО: фрейм "MDTModelTooltip" и его
-- .Model:SetCreature(npcID). Это стабильный публичный якорь.
--
-- БЕЗОПАСНОСТЬ:
--  * фреймы MDT НЕ трогаем — только hooksecurefunc/HookScript (пост-хуки);
--  * если MDT не установлен / окно ни разу не открывали — модуль просто спит;
--  * npcID проверяем на Secret Value (issecretvalue) и tonumber;
--  * это ЭКСПЕРИМЕНТАЛЬНЫЙ модуль — строку в .toc можно закомментировать (#),
--    и остальной RainonUI продолжит работать как ни в чём не бывало.
-- =========================================================================
local ADDON_NAME, ns = ...

-- -------------------------------------------------------------------------
-- NOTES: our per-mob notes, keyed by npcID -> "text".
-- Matched purely by npcID. Dungeon headers below are COMMENTS ONLY (they
-- don't affect behaviour): they exist so an edit like "add a note to
-- Гробница Королей" is one Ctrl+F on "DUNGEON: <ru name>". Source of entries:
-- the per-dungeon Obsidian page linked from _INDEX/MDT_TOOLTIP.md
-- (Имя | NPC_ID | Текст) — copy NPC_ID + text here. Note text stays RU
-- (shown in-game); code comments are EN.
-- -------------------------------------------------------------------------
local NOTES = {
    -- == DUNGEON: Алтарь Клыков ==
    -- == DUNGEON: Арена Шрама Бездны ==
    -- == DUNGEON: Гробница Королей ==
    -- == DUNGEON: Закоулок Душегубов ==
    [234763] = "Это тестовое сообщение и проверка работы.",  -- Литиэль Пепельная Ярость
    -- == DUNGEON: Рубиновые Омуты ==
    -- == DUNGEON: Храм Сетралисс ==
    -- == DUNGEON: Слепящая Долина ==
}

-- -------------------------------------------------------------------------
-- Наша рамка (создаём лениво, привязываем к тултипу MDT)
-- -------------------------------------------------------------------------
local block

local function EnsureBlock(mdtTip)
    if block then return block end
    if not mdtTip then return nil end

    block = CreateFrame("Frame", "RainonUI_MDTNoteBlock", mdtTip, "TooltipBorderedFrameTemplate")
    block:SetFrameStrata("TOOLTIP")
    block:SetFrameLevel((mdtTip:GetFrameLevel() or 1) + 10)
    block:SetClampedToScreen(true)
    block:Hide()

    -- Приклеиваем ПОД подсказку MDT, слева по краю, с небольшим зазором.
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", mdtTip, "BOTTOMLEFT", 0, -2)

    block.caption = block:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    block.caption:SetPoint("TOPLEFT", block, "TOPLEFT", 10, -8)
    block.caption:SetJustifyH("LEFT")
    block.caption:SetTextColor(0.4, 0.7, 0.55, 1)
    block.caption:SetText("RainonUI")

    block.text = block:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    block.text:SetPoint("TOPLEFT", block.caption, "BOTTOMLEFT", 0, -4)
    block.text:SetJustifyH("LEFT")
    block.text:SetTextColor(1, 0.9, 0.5, 1)
    block.text:SetWidth(270)

    return block
end

local function ShowNote(mdtTip, note)
    local b = EnsureBlock(mdtTip)
    if not b then return end
    b.text:SetText(note)
    local h = 8 + (b.caption:GetStringHeight() or 12) + 4 + (b.text:GetStringHeight() or 12) + 10
    b:SetWidth(290)
    b:SetHeight(h)
    b:Show()
end

local function HideNote()
    if block then block:Hide() end
end

-- -------------------------------------------------------------------------
-- Установка хука на модель-тултип MDT (глобальный фрейм "MDTModelTooltip").
-- Ставится один раз, как только фрейм существует.
-- -------------------------------------------------------------------------
local hooked = false

local function InstallTooltipHook()
    if hooked then return true end
    local tip = _G.MDTModelTooltip
    if not (tip and tip.Model and tip.Model.SetCreature) then return false end

    -- MDT на наведении зовёт tip.Model:SetCreature(npcID) — ловим npcID здесь.
    hooksecurefunc(tip.Model, "SetCreature", function(_, creatureID)
        -- Всё тело в защите: npcID может прийти как Secret Value (12.0).
        local ok = pcall(function()
            if issecretvalue and issecretvalue(creatureID) then HideNote(); return end
            local id = tonumber(creatureID)
            local note = id and NOTES[id]
            if note then ShowNote(tip, note) else HideNote() end
        end)
        if not ok then HideNote() end
    end)

    -- Тултип спрятался — прячем и наш блок.
    tip:HookScript("OnHide", HideNote)

    hooked = true
    if ns.debug and ns.Print then ns.Print("MDT-подсказка: хук на MDTModelTooltip установлен.") end
    return true
end

-- -------------------------------------------------------------------------
-- Запуск. Фрейм "MDTModelTooltip" MDT строит ЛЕНИВО — только при первом
-- открытии окна MDT. Поэтому:
--  1) пробуем сразу (вдруг окно уже открывали);
--  2) если фрейма ещё нет — коротко проверяем при старте одноразовым тикером,
--     который САМ выключается, как только хук поставлен (или после лимита).
--     Это разовая проба на старте, а НЕ постоянный опрос.
--  3) плюс повторная попытка на входе в мир (reload/смена зоны).
-- -------------------------------------------------------------------------
local function StartInstall()
    if InstallTooltipHook() then return end
    if not C_Timer or not C_Timer.NewTicker then return end
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(2, function()
        tries = tries + 1
        if InstallTooltipHook() or tries >= 30 then  -- максимум ~60 сек проб
            if ticker then ticker:Cancel() end
        end
    end)
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if not hooked then StartInstall() end
end)
