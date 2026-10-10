-- PaladinSealAlert: popup banners + options panel

-- ---------------------------------------------------------------------------
-- Popup banners — two separate ones (seal vs. group blessing), each with its
-- own color/size/position, so they're easy to tell apart at a glance.
-- ---------------------------------------------------------------------------

local function CreatePopup(frameName, yOffset, colorKey, sizeKey, defaultColor, defaultSize)
    local popup = CreateFrame("Frame", frameName, UIParent)
    popup:SetSize(320, 50)
    popup:SetPoint("TOP", UIParent, "TOP", 0, yOffset)
    popup:SetFrameStrata("HIGH")
    popup:Hide()

    local text = popup:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    popup.text = text

    -- Pin a known-good Blizzard font file directly. Grabbing whatever font
    -- the default template resolves to (via GetFont) can return a face that
    -- is missing glyphs on some client builds, which renders as tofu boxes.
    local function ApplyTextStyle()
        local db = PaladinSealAlertDB
        local size = (db and db[sizeKey]) or defaultSize
        local r = (db and db[colorKey .. "R"]) or defaultColor.r
        local g = (db and db[colorKey .. "G"]) or defaultColor.g
        local b = (db and db[colorKey .. "B"]) or defaultColor.b

        local ok = pcall(function()
            text:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
        end)
        if not ok then
            text:SetFontObject("GameFontNormalLarge")
        end
        text:SetTextColor(r, g, b)
    end
    ApplyTextStyle()
    popup.ApplyTextStyle = ApplyTextStyle

    local pop = popup:CreateAnimationGroup()
    local scaleUp = pop:CreateAnimation("Scale")
    scaleUp:SetScale(1.25, 1.25)
    scaleUp:SetDuration(0.12)
    scaleUp:SetOrder(1)
    local scaleDown = pop:CreateAnimation("Scale")
    scaleDown:SetScale(0.8, 0.8)
    scaleDown:SetDuration(0.12)
    scaleDown:SetOrder(2)

    local hideTimer = nil

    popup.Show2 = function(message, duration)
        ApplyTextStyle()
        popup.text:SetText(message)
        popup:SetAlpha(1)
        popup:Show()
        pop:Stop()
        pop:Play()

        if hideTimer then
            hideTimer:Cancel()
        end
        hideTimer = C_Timer.NewTimer(duration or 3, function()
            UIFrameFadeOut(popup, 0.6, popup:GetAlpha(), 0)
            C_Timer.After(0.6, function() popup:Hide() end)
        end)
    end

    return popup
end

local sealPopup = CreatePopup("PaladinSealAlertPopup", -150, "textColor", "textSize", { r = 1, g = 0.15, b = 0.15 }, 20)
local groupPopup = CreatePopup("PaladinSealAlertGroupPopup", -220, "groupTextColor", "groupTextSize", { r = 0.3, g = 0.6, b = 1 }, 18)

function PaladinSealAlert_ShowPopup(message, duration)
    sealPopup.Show2(message, duration)
end

function PaladinSealAlert_ShowGroupPopup(message, duration)
    groupPopup.Show2(message, duration)
end

function PaladinSealAlert_ApplyTextStyle()
    sealPopup.ApplyTextStyle()
    groupPopup.ApplyTextStyle()
end

-- ---------------------------------------------------------------------------
-- Options panel
-- ---------------------------------------------------------------------------

local panel = CreateFrame("Frame", "PaladinSealAlertOptionsPanel", UIParent)
panel.name = "Sealkeeper: Forever"
panel:SetSize(760, 600)
panel:Hide()

-- There's more here than fits the Options window, so it scrolls.
local scrollFrame = CreateFrame("ScrollFrame", "PaladinSealAlertScrollFrame", panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 0, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

local content = CreateFrame("Frame", "PaladinSealAlertScrollContent", scrollFrame)
content:SetSize(700, 1)
scrollFrame:SetScrollChild(content)

-- If something outside the panel changes a setting (e.g. the status window's
-- own Close button), a widget can go stale and show the wrong value. Every
-- Add* helper below registers a re-sync closure here, replayed on each show.
local refreshCallbacks = {}

local function AddCheckbox(parent, labelText, x, y, getFunc, setFunc)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.Text:SetText(labelText)
    cb:SetChecked(getFunc())
    cb:SetScript("OnClick", function(self)
        setFunc(self:GetChecked() and true or false)
    end)
    table.insert(refreshCallbacks, function() cb:SetChecked(getFunc()) end)
    return cb
end

local function AddEditBox(parent, labelText, x, y, width, getFunc, setFunc)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", x + 10, y - 18)
    box:SetAutoFocus(false)
    box:SetText(tostring(getFunc()))
    box:SetScript("OnEnterPressed", function(self)
        setFunc(self:GetText())
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(getFunc()))
        self:ClearFocus()
    end)
    -- Also commit on losing focus — otherwise clicking away loses the edit.
    box:SetScript("OnEditFocusLost", function(self)
        setFunc(self:GetText())
    end)
    table.insert(refreshCallbacks, function()
        if not box:HasFocus() then box:SetText(tostring(getFunc())) end
    end)
    return box
end

local function AddSlider(parent, labelText, x, y, minVal, maxVal, step, getFunc, setFunc)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y)
    slider:SetWidth(220)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    if slider.Text then slider.Text:SetText(labelText) end
    if slider.Low then slider.Low:SetText(tostring(minVal)) end
    if slider.High then slider.High:SetText(tostring(maxVal)) end
    slider:SetValue(getFunc())
    slider:SetScript("OnValueChanged", function(self, value)
        setFunc(value)
    end)
    table.insert(refreshCallbacks, function() slider:SetValue(getFunc()) end)
    return slider
end

local SOUND_PRESET_LABELS = {
    raidwarning = "Raid Warning",
    readycheck  = "Ready Check",
    alarm       = "Alarm Clock",
    custom      = "Custom File",
}

local CHANNELS = { "Master", "SFX", "Ambience", "Music", "Dialog" }

-- A dropdown built from plain Frames/Buttons/Textures — never Blizzard's
-- UIDropDownMenuTemplate, which taints the addon on this client and breaks
-- aura reads ("Auras cannot be accessed when secret while tainted").
local openDropdownList = nil

local function CloseOpenDropdown()
    if openDropdownList then
        openDropdownList:Hide()
        openDropdownList = nil
    end
end

local function AddDropdown(parent, labelText, x, y, width, items, itemLabels, getFunc, setFunc)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", x, y - 18)

    local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")

    local function Refresh()
        local current = getFunc()
        button:SetText((itemLabels and itemLabels[current]) or current)
    end

    local list = CreateFrame("Frame", nil, button, "BackdropTemplate")
    list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    list:SetSize(width, 8 + #items * 20)
    list:SetFrameStrata("TOOLTIP")
    if list.SetBackdrop then
        list:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        list:SetBackdropColor(0, 0, 0, 0.95)
    end
    list:Hide()

    for i, key in ipairs(items) do
        local rowBtn = CreateFrame("Button", nil, list)
        rowBtn:SetSize(width - 8, 20)
        rowBtn:SetPoint("TOP", 0, -4 - (i - 1) * 20)

        local rowHighlight = rowBtn:CreateTexture(nil, "HIGHLIGHT")
        rowHighlight:SetAllPoints()
        rowHighlight:SetColorTexture(1, 1, 1, 0.15)
        rowBtn:SetHighlightTexture(rowHighlight)

        local rowText = rowBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rowText:SetPoint("LEFT", 4, 0)
        rowText:SetText((itemLabels and itemLabels[key]) or key)

        rowBtn:SetScript("OnClick", function()
            setFunc(key)
            Refresh()
            CloseOpenDropdown()
        end)
    end

    button:SetScript("OnClick", function()
        if openDropdownList == list then
            CloseOpenDropdown()
        else
            CloseOpenDropdown()
            list:Show()
            openDropdownList = list
        end
    end)

    Refresh()
    button.Refresh = Refresh
    return button
end

-- RGB + size sliders with a live preview swatch, reused for both the seal
-- and group popups so each can be styled independently.
local function AddColorSizeControls(parent, x, y, colorKeyPrefix, sizeKey, labelText)
    local db = PaladinSealAlertDB

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local swatch = parent:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(20, 20)
    swatch:SetPoint("LEFT", label, "RIGHT", 10, 0)
    swatch:SetColorTexture(db[colorKeyPrefix .. "R"], db[colorKeyPrefix .. "G"], db[colorKeyPrefix .. "B"])

    local function Refresh()
        swatch:SetColorTexture(db[colorKeyPrefix .. "R"], db[colorKeyPrefix .. "G"], db[colorKeyPrefix .. "B"])
        if PaladinSealAlert_ApplyTextStyle then PaladinSealAlert_ApplyTextStyle() end
    end

    AddSlider(parent, "Red", x, y - 30, 0, 1, 0.05,
        function() return db[colorKeyPrefix .. "R"] end,
        function(v) db[colorKeyPrefix .. "R"] = v; Refresh() end)

    AddSlider(parent, "Green", x + 260, y - 30, 0, 1, 0.05,
        function() return db[colorKeyPrefix .. "G"] end,
        function(v) db[colorKeyPrefix .. "G"] = v; Refresh() end)

    AddSlider(parent, "Blue", x, y - 80, 0, 1, 0.05,
        function() return db[colorKeyPrefix .. "B"] end,
        function(v) db[colorKeyPrefix .. "B"] = v; Refresh() end)

    AddSlider(parent, "Text size", x + 260, y - 80, 12, 40, 1,
        function() return db[sizeKey] end,
        function(v) db[sizeKey] = v; Refresh() end)

    return y - 130 -- next free y
end

-- Preset + channel + custom file + beta-bug warning, shared by the seal and
-- group alert sections instead of copy-pasting each block twice.
local function AddSoundControls(y, presetKey, channelKey, fileKey)
    local db = PaladinSealAlertDB

    local presetButton = AddDropdown(content, "Sound preset:", 20, y, 170,
        PaladinSealAlert_SoundPresetOrder, SOUND_PRESET_LABELS,
        function() return db[presetKey] end,
        function(v) db[presetKey] = v end)

    AddDropdown(content, "Sound channel:", 300, y, 150, CHANNELS, nil,
        function() return db[channelKey] end,
        function(v) db[channelKey] = v end)
    y = y - 56

    AddEditBox(content, "Custom sound (filename in Sounds folder, or full Interface\\... path):", 20, y, 400,
        function() return db[fileKey] end,
        function(v)
            db[fileKey] = v
            -- Typing a custom file only has an effect once the preset is
            -- actually switched to "custom" — do that automatically so the
            -- box and the button label can't fall out of sync.
            if v ~= "" then
                db[presetKey] = "custom"
                presetButton.Refresh()
            end
        end)
    y = y - 42

    local warning = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warning:SetPoint("TOPLEFT", 20, y)
    warning:SetWidth(660)
    warning:SetJustifyH("LEFT")
    warning:SetText("Known WoW: Forever beta bug — custom sound files are currently silent. Built-in presets work.")
    warning:SetTextColor(1, 0.6, 0.1)
    y = y - 30

    return y
end

-- A test-alert button; chains off `anchorFrame`'s right edge when given, or
-- else sits at an absolute (x, y). Used for the four "Test ..." buttons.
local function AddTestButton(width, text, globalFnName, anchorFrame, x, y)
    local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    btn:SetSize(width, 24)
    if anchorFrame then
        btn:SetPoint("LEFT", anchorFrame, "RIGHT", 10, 0)
    else
        btn:SetPoint("TOPLEFT", x, y)
    end
    btn:SetText(text)
    btn:SetScript("OnClick", function()
        local fn = _G[globalFnName]
        if fn then fn() end
    end)
    return btn
end

local function BuildPanel()
    local db = PaladinSealAlertDB
    local y = -16

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, y)
    title:SetText("Sealkeeper: Forever")
    y = y - 24

    local subtitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 16, y)
    subtitle:SetText("Alerts you when your paladin seal or Righteous Fury expires, or a party member's Blessing falls off")
    y = y - 34

    AddCheckbox(content, "Sound", 20, y, function() return db.enableSound end, function(v) db.enableSound = v end)
    y = y - 26
    AddCheckbox(content, "Popup text", 20, y, function() return db.enablePopup end, function(v) db.enablePopup = v end)
    y = y - 26
    AddCheckbox(content, "Debug messages", 20, y, function() return db.debug end, function(v) db.debug = v end)
    y = y - 26
    AddCheckbox(content, "Track Righteous Fury", 20, y,
        function() return db.enableRighteousFuryWatch end,
        function(v) db.enableRighteousFuryWatch = v end)
    y = y - 26
    AddCheckbox(content, "Track Paladin Aura (Devotion, etc.)", 20, y,
        function() return db.enableAuraWatch end,
        function(v) db.enableAuraWatch = v end)
    y = y - 26
    AddCheckbox(content, "Show status window (who lacks a Blessing / Righteous Fury up)", 20, y,
        function() return db.showStatusWindow end,
        function(v)
            db.showStatusWindow = v
            if PaladinSealAlert_RefreshStatusWindowVisibility then PaladinSealAlert_RefreshStatusWindowVisibility() end
        end)
    y = y - 46

    AddSlider(content, "Status window size", 20, y, 0.6, 1.6, 0.05,
        function() return db.statusWindowScale end,
        function(v)
            db.statusWindowScale = v
            if PaladinSealAlert_ApplyStatusWindowScale then PaladinSealAlert_ApplyStatusWindowScale() end
        end)
    y = y - 40

    AddCheckbox(content, "Use icons instead of text labels (Seal/RF/Aura badges)", 20, y,
        function() return db.statusIconLabels end,
        function(v) db.statusIconLabels = v end)
    y = y - 26

    AddCheckbox(content, "Lock status window position", 20, y,
        function() return db.statusWindowLocked end,
        function(v) db.statusWindowLocked = v end)
    y = y - 40

    local blessingTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    blessingTitle:SetPoint("TOPLEFT", 20, y)
    blessingTitle:SetText("Click-to-Blessing (clicking a party row)")
    y = y - 24

    local BLESSING_LABELS = {}
    for key, spellName in pairs(PaladinSealAlert_BlessingSpells or {}) do
        BLESSING_LABELS[key] = spellName:gsub("^Blessing of ", "")
    end
    local blessingOrder = PaladinSealAlert_BlessingOrder or {}

    local BLESSING_CLICK_SLOTS = {
        { label = "Click:",       x = 20,  dbKey = "blessingPlainKey" },
        { label = "Ctrl-click:",  x = 160, dbKey = "blessingCtrlKey" },
        { label = "Shift-click:", x = 300, dbKey = "blessingShiftKey" },
    }
    for _, slot in ipairs(BLESSING_CLICK_SLOTS) do
        AddDropdown(content, slot.label, slot.x, y, 110, blessingOrder, BLESSING_LABELS,
            function() return db[slot.dbKey] end,
            function(v)
                db[slot.dbKey] = v
                if PaladinSealAlert_RefreshBlessingBindings then PaladinSealAlert_RefreshBlessingBindings() end
            end)
    end
    y = y - 56

    -- ---- Seal / self alert sound ----
    local sealSoundTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sealSoundTitle:SetPoint("TOPLEFT", 20, y)
    sealSoundTitle:SetText("Seal / Righteous Fury Alert")
    y = y - 30

    y = AddSoundControls(y, "soundPreset", "soundChannel", "customSoundFile")

    AddSlider(content, "Warn early (sec, 0 = off)", 20, y, 0, 10, 1,
        function() return db.warnBeforeSeconds end,
        function(v) db.warnBeforeSeconds = v end)
    AddSlider(content, "Popup duration (sec)", 300, y, 1, 8, 1,
        function() return db.popupDuration end,
        function(v) db.popupDuration = v end)
    y = y - 50

    y = AddColorSizeControls(content, 20, y, "textColor", "textSize", "Popup color & size:")

    AddEditBox(content, "Text: seal expired", 20, y, 400,
        function() return db.msgExpired end,
        function(v) db.msgExpired = v end)
    y = y - 42

    AddEditBox(content, "Text: seal expiring soon", 20, y, 400,
        function() return db.msgWarning end,
        function(v) db.msgWarning = v end)
    y = y - 42

    AddEditBox(content, "Text: Righteous Fury expired", 20, y, 400,
        function() return db.msgRFExpired end,
        function(v) db.msgRFExpired = v end)
    y = y - 42

    AddEditBox(content, "Text: Righteous Fury expiring soon", 20, y, 400,
        function() return db.msgRFWarning end,
        function(v) db.msgRFWarning = v end)
    y = y - 42

    AddEditBox(content, "Text: Aura not active", 20, y, 400,
        function() return db.msgAuraExpired end,
        function(v) db.msgAuraExpired = v end)
    y = y - 44

    local testButton = AddTestButton(100, "Test Seal", "PaladinSealAlert_TriggerTest", nil, 20, y)
    local testRFButton = AddTestButton(140, "Test Righteous Fury", "PaladinSealAlert_TriggerRFTest", testButton)
    AddTestButton(100, "Test Aura", "PaladinSealAlert_TriggerAuraTest", testRFButton)
    y = y - 50

    -- ---- Divider ----
    local divider = content:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetPoint("TOPLEFT", 20, y)
    divider:SetSize(660, 1)
    y = y - 30

    -- ---- Group Blessing Watch (player + party1-4) — its own sound and
    -- popup style so it's clearly distinguishable from the seal/RF alert.
    local groupTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    groupTitle:SetPoint("TOPLEFT", 20, y)
    groupTitle:SetText("Group Blessing Watch (party)")
    y = y - 30

    AddCheckbox(content, "Track party members' Blessings", 20, y,
        function() return db.enableGroupBlessingWatch end,
        function(v) db.enableGroupBlessingWatch = v end)
    y = y - 40

    y = AddSoundControls(y, "groupSoundPreset", "groupSoundChannel", "groupCustomSoundFile")

    y = AddColorSizeControls(content, 20, y, "groupTextColor", "groupTextSize", "Group popup color & size:")

    AddEditBox(content, "Group text: blessing expired ({name} = player)", 20, y, 400,
        function() return db.msgGroupExpired end,
        function(v) db.msgGroupExpired = v end)
    y = y - 42

    AddEditBox(content, "Group text: blessing expiring ({name} = player)", 20, y, 400,
        function() return db.msgGroupWarning end,
        function(v) db.msgGroupWarning = v end)
    y = y - 40

    local groupNote = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupNote:SetPoint("TOPLEFT", 20, y)
    groupNote:SetWidth(660)
    groupNote:SetJustifyH("LEFT")
    groupNote:SetText("Watches Blessing of Might/Wisdom/Kings/etc. on yourself and party1-4.")
    y = y - 30

    AddTestButton(160, "Test Group Alert", "PaladinSealAlert_TriggerGroupTest", nil, 20, y)
    y = y - 40

    content:SetHeight(-y + 20)
end

panel:SetScript("OnShow", function()
    for _, refresh in ipairs(refreshCallbacks) do
        refresh()
    end
end)
panel:SetScript("OnHide", CloseOpenDropdown)

local built = false

local function EnsureBuiltAndRegistered()
    if built then return end
    BuildPanel()
    built = true

    if Settings and Settings.RegisterCanvasLayoutCategory then
        pcall(function()
            local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(category)
            panel.category = category
            panel.registered = true
        end)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        panel.registeredLegacy = true
    end
end

function PaladinSealAlert_OpenOptions()
    EnsureBuiltAndRegistered()

    -- This client wants the numeric category ID here — passing the category
    -- object or the name string both throw "bad argument #1 ... out of range".
    if panel.registered and Settings and Settings.OpenToCategory and panel.category then
        Settings.OpenToCategory(panel.category.ID or panel.category)
        return
    end

    if panel.registeredLegacy and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        return
    end

    panel:Show()
end

local optionsInit = CreateFrame("Frame")
optionsInit:RegisterEvent("PLAYER_LOGIN")
optionsInit:SetScript("OnEvent", function()
    if PaladinSealAlertDB then
        EnsureBuiltAndRegistered()
    end
end)

-- ---------------------------------------------------------------------------
-- Status window — small movable panel showing who lacks a Blessing and
-- whether your Seal/RF/Aura are up. During combat it shows last-known data
-- with a note, since the client blocks aura reads in combat.
-- ---------------------------------------------------------------------------

local statusWindow = CreateFrame("Frame", "PaladinSealAlertStatusWindow", UIParent, "BackdropTemplate")
statusWindow:SetSize(170, 100)
statusWindow:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -220)
statusWindow:SetFrameStrata("MEDIUM")
statusWindow:SetMovable(true)
statusWindow:EnableMouse(true)
statusWindow:RegisterForDrag("LeftButton")
statusWindow:SetClampedToScreen(true)

if statusWindow.SetBackdrop then
    statusWindow:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    statusWindow:SetBackdropColor(0, 0, 0, 0.6)
end

local function SaveStatusWindowPosition()
    local db = PaladinSealAlertDB
    if not db then return end
    local point, _, relPoint, x, y = statusWindow:GetPoint()
    db.statusWindowPoint = point
    db.statusWindowRelPoint = relPoint
    db.statusWindowX = x
    db.statusWindowY = y
end

statusWindow:SetScript("OnDragStart", function(self)
    local db = PaladinSealAlertDB
    if db and db.statusWindowLocked then return end
    self:StartMoving()
end)
statusWindow:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveStatusWindowPosition()
end)

local statusTitle = statusWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusTitle:SetPoint("TOP", 0, -8)
statusTitle:SetText("Sealkeeper")

local closeButton = CreateFrame("Button", nil, statusWindow, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", -2, -2)
closeButton:SetSize(20, 20)
closeButton:SetScript("OnClick", function()
    PaladinSealAlertDB.showStatusWindow = false
    statusWindow:Hide()
end)

-- ---- Right-click context menu: size, lock/unlock, advanced settings ----

local SCALE_STEP = 0.1

local function NudgeStatusWindowScale(delta)
    local db = PaladinSealAlertDB
    if not db then return end
    db.statusWindowScale = math.max(0.6, math.min(1.6, db.statusWindowScale + delta))
    if PaladinSealAlert_ApplyStatusWindowScale then PaladinSealAlert_ApplyStatusWindowScale() end
end

local contextMenu = CreateFrame("Frame", nil, statusWindow, "BackdropTemplate")
contextMenu:SetSize(130, 96)
contextMenu:SetFrameStrata("TOOLTIP")
contextMenu:SetClampedToScreen(true)
if contextMenu.SetBackdrop then
    contextMenu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    contextMenu:SetBackdropColor(0, 0, 0, 0.95)
end
contextMenu:Hide()

-- Catches a click anywhere else on screen to close the menu, since it's
-- plain Frames/Buttons (not Blizzard's menu system — see the dropdown note
-- in the options panel above for why).
local menuCatcher = CreateFrame("Button", nil, UIParent)
menuCatcher:SetAllPoints(UIParent)
menuCatcher:SetFrameStrata("TOOLTIP")
menuCatcher:Hide()
contextMenu:SetFrameLevel(menuCatcher:GetFrameLevel() + 1)

local function HideStatusContextMenu()
    contextMenu:Hide()
    menuCatcher:Hide()
end
menuCatcher:SetScript("OnClick", HideStatusContextMenu)

local function AddMenuButton(index)
    local btn = CreateFrame("Button", nil, contextMenu)
    btn:SetSize(122, 20)
    btn:SetPoint("TOP", 0, -4 - (index - 1) * 22)

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.15)
    btn:SetHighlightTexture(highlight)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 4, 0)
    btn.text = text
    return btn
end

local smallerMenuItem = AddMenuButton(1)
smallerMenuItem.text:SetText("Smaller")
smallerMenuItem:SetScript("OnClick", function() NudgeStatusWindowScale(-SCALE_STEP) end)

local largerMenuItem = AddMenuButton(2)
largerMenuItem.text:SetText("Larger")
largerMenuItem:SetScript("OnClick", function() NudgeStatusWindowScale(SCALE_STEP) end)

local lockMenuItem = AddMenuButton(3)
lockMenuItem:SetScript("OnClick", function()
    local db = PaladinSealAlertDB
    if db then db.statusWindowLocked = not db.statusWindowLocked end
    HideStatusContextMenu()
end)

local settingsMenuItem = AddMenuButton(4)
settingsMenuItem.text:SetText("Advanced settings...")
settingsMenuItem:SetScript("OnClick", function()
    if PaladinSealAlert_OpenOptions then PaladinSealAlert_OpenOptions() end
    HideStatusContextMenu()
end)

local function ShowStatusContextMenu()
    local db = PaladinSealAlertDB
    lockMenuItem.text:SetText(db and db.statusWindowLocked and "Unlock position" or "Lock position")

    -- Anchored to the window itself (which is already clamped to the
    -- screen) instead of the cursor, so it can't end up off-screen when the
    -- window sits near a screen edge.
    contextMenu:ClearAllPoints()
    contextMenu:SetPoint("TOP", statusWindow, "TOP", 0, -4)
    contextMenu:Show()
    menuCatcher:Show()
end

-- Right-click anywhere on the window opens the context menu above. Shared
-- by the window background, the party rows, and the combat row below —
-- they're separate mouse-enabled frames, so each needs its own hookup.
local function OnRightClickOpenMenu(self, button)
    if button == "RightButton" then
        ShowStatusContextMenu()
    end
end
statusWindow:SetScript("OnMouseUp", OnRightClickOpenMenu)

-- Status colors shared by the badges and the member bars below.
local COLOR_OK      = { 0.25, 1, 0.25 }
local COLOR_BAD     = { 1, 0.3, 0.3 }
local COLOR_WARN    = { 1, 0.6, 0 }
local COLOR_OFFLINE = { 0.55, 0.55, 0.55 }

-- ---- Top row: 3 small badges for Seal / Righteous Fury / Aura ----

local BADGE_WIDTH, BADGE_HEIGHT, BADGE_GAP, BADGE_Y = 48, 30, 4, -26

local RF_ICON = "Interface\\Icons\\Spell_Holy_SealOfFury"
local DEFAULT_SEAL_ICON = "Interface\\Icons\\Spell_Holy_SealOfWrath"
local DEFAULT_AURA_ICON = "Interface\\Icons\\Spell_Holy_DevotionAura"

local function CreateBadge(label)
    local badge = CreateFrame("Frame", nil, statusWindow, "BackdropTemplate")
    badge:SetSize(BADGE_WIDTH, BADGE_HEIGHT)
    if badge.SetBackdrop then
        badge:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        badge:SetBackdropColor(0, 0, 0, 0.4)
        badge:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end
    local text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    badge.text = text

    -- Alternate to the text label when icon mode is on (see SetBadgeStatus).
    -- Square and centered, not stretched to the (wider-than-tall) badge.
    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetSize(BADGE_HEIGHT - 6, BADGE_HEIGHT - 6)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's built-in border art
    icon:Hide()
    badge.icon = icon

    return badge
end

local sealBadge = CreateBadge("Seal")
local rfBadge = CreateBadge("RF")
local auraBadge = CreateBadge("Aura")

local function SetBadgeStatus(badge, up, iconPath)
    local c = up and COLOR_OK or COLOR_BAD
    badge:SetBackdropBorderColor(c[1], c[2], c[3], 1)

    local db = PaladinSealAlertDB
    if db and db.statusIconLabels and iconPath then
        badge.icon:SetTexture(iconPath)
        badge.icon:SetDesaturated(not up)
        badge.icon:Show()
        badge.text:Hide()
    else
        badge.text:SetTextColor(c[1], c[2], c[3])
        badge.text:Show()
        badge.icon:Hide()
    end

    badge:Show()
end

local function LayoutBadges(visibleBadges)
    local x = 8
    for _, badge in ipairs(visibleBadges) do
        badge:ClearAllPoints()
        badge:SetPoint("TOPLEFT", x, BADGE_Y)
        x = x + BADGE_WIDTH + BADGE_GAP
    end
end

-- ---- Below: one row per party member, red/green tinted by status ----
-- Each row casts a Blessing on its own member directly: plain click = Kings,
-- Ctrl = Might, Shift = Wisdom. Rows are built once per possible unit slot
-- (player/party1-4) at load time and never rebound afterward — a secure
-- frame's attributes can't be changed from insecure code during combat, so
-- reusing rows by position (whoever's Nth in the list) would break the
-- first time someone's state changed mid-fight. One fixed row per unit,
-- shown or hidden as that unit comes and goes, avoids that entirely. This
-- mirrors Decursive's own click-cast buttons (SecureUnitButtonTemplate +
-- per-modifier macrotext, see Dcr_DebuffsFrame.lua).

local BAR_HEIGHT, BAR_GAP = 20, 2
local STATUS_ROW_UNITS = { "player", "party1", "party2", "party3", "party4" }

local function GetBlessingSpell(dbKey, fallbackKey)
    local db = PaladinSealAlertDB
    local key = (db and db[dbKey]) or fallbackKey
    return (PaladinSealAlert_BlessingSpells and PaladinSealAlert_BlessingSpells[key]) or "Blessing of Kings"
end

-- (Re)writes a row's click attributes from the current Blessing bindings.
-- Only safe to call out of combat — secure attributes on an existing frame
-- can't be changed from insecure code during a fight.
--
-- "help" and the leading /stopcasting matter: without a condition, casting
-- on an offline or invalid unit falls through to your current target (or
-- yourself) instead of just failing — the same gotcha every mouseover macro
-- has to guard against. "exists" alone isn't enough — an offline party
-- member still "exists" in the roster; "help" requires an actually-valid
-- friendly cast target, which offline members fail.
local function ApplyBlessingAttributes(row, unit)
    local function MacroFor(spell)
        return "/stopcasting\n/cast [@" .. unit .. ",help] " .. spell
    end
    row:SetAttribute("type1", "macro")
    row:SetAttribute("macrotext1", MacroFor(GetBlessingSpell("blessingPlainKey", "kings")))
    row:SetAttribute("ctrl-type1", "macro")
    row:SetAttribute("ctrl-macrotext1", MacroFor(GetBlessingSpell("blessingCtrlKey", "might")))
    row:SetAttribute("shift-type1", "macro")
    row:SetAttribute("shift-macrotext1", MacroFor(GetBlessingSpell("blessingShiftKey", "wisdom")))
end

local function AddBarVisuals(row)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row.bg = bg

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(3)
    row.accent = accent

    -- Shows the Blessing's actual icon next to names that have one.
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 6, 0)
    icon:Hide()
    row.icon = icon

    -- Same, mirrored on the right, for some other paladin's Blessing.
    local otherIcon = row:CreateTexture(nil, "ARTWORK")
    otherIcon:SetSize(14, 14)
    otherIcon:SetPoint("RIGHT", -4, 0)
    otherIcon:Hide()
    row.otherIcon = otherIcon

    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", 26, 0)
    -- WoW's system fonts have no separate bold cut, so OUTLINE at a
    -- larger size is the usual way to get a bolder-reading name.
    local ok = pcall(function()
        text:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    end)
    if not ok then
        text:SetFontObject("GameFontHighlightSmall")
    end
    row.text = text

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.12)
    row:SetHighlightTexture(highlight)
end

local function CreateBarRowForUnit(unit)
    local row = CreateFrame("Button", nil, statusWindow, "SecureUnitButtonTemplate")
    row:SetHeight(BAR_HEIGHT)
    row:Hide()
    row:RegisterForClicks("AnyUp")
    row:SetAttribute("unit", unit)
    ApplyBlessingAttributes(row, unit)

    AddBarVisuals(row)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(UnitName(unit) or unit)
        GameTooltip:AddLine("Click: " .. GetBlessingSpell("blessingPlainKey", "kings"), 1, 1, 1)
        GameTooltip:AddLine("Ctrl-click: " .. GetBlessingSpell("blessingCtrlKey", "might"), 1, 1, 1)
        GameTooltip:AddLine("Shift-click: " .. GetBlessingSpell("blessingShiftKey", "wisdom"), 1, 1, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The row is a mouse-enabled Button sitting on top of the window, so a
    -- right-click here never reaches statusWindow's own OnMouseUp — hook it
    -- straight onto the row too (see OnRightClickOpenMenu above).
    row:HookScript("OnMouseUp", OnRightClickOpenMenu)

    return row
end

-- Built once, out of combat, at load time — see the note above.
local barRowsByUnit = {}
for _, unit in ipairs(STATUS_ROW_UNITS) do
    barRowsByUnit[unit] = CreateBarRowForUnit(unit)
end

-- Called when the Blessing bindings change in the options panel. Refuses
-- in combat instead of throwing — secure attributes are frozen mid-fight.
function PaladinSealAlert_RefreshBlessingBindings()
    if InCombatLockdown and InCombatLockdown() then
        print("|cff3399ffSealkeeper|r: can't change click-cast bindings in combat — try again after the fight.")
        return
    end
    for unit, row in pairs(barRowsByUnit) do
        ApplyBlessingAttributes(row, unit)
    end
end

-- Not tied to a real unit, so it's a plain (non-secure) Button — still a
-- Button, not a Frame, since AddBarVisuals' highlight texture needs one.
local combatRow = CreateFrame("Button", nil, statusWindow)
combatRow:SetHeight(BAR_HEIGHT)
AddBarVisuals(combatRow)
combatRow:SetScript("OnMouseUp", OnRightClickOpenMenu)

local function GetClassColor(classToken)
    local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- mode: "ok" (green), "bad" (red, the default), "warn" (amber, in-combat
-- note), or "offline" (grey, member can't be clicked right now).
local MODE_COLORS = { ok = COLOR_OK, warn = COLOR_WARN, offline = COLOR_OFFLINE }

-- The bar carries the buff status; classToken colors the name by class.
-- buffIcon/otherBuffIcon show your Blessing and someone else's, if present.
local function SetBarStatus(row, label, mode, classToken, buffIcon, otherBuffIcon)
    local c = MODE_COLORS[mode] or COLOR_BAD
    row.text:SetText(label)
    row.text:SetTextColor(GetClassColor(classToken))
    row.bg:SetColorTexture(c[1], c[2], c[3], mode == "warn" and 0.2 or 0.18)
    row.accent:SetColorTexture(c[1], c[2], c[3], 1)
    if mode == "ok" and buffIcon then
        row.icon:SetTexture(buffIcon)
        row.icon:Show()
    else
        row.icon:Hide()
    end
    if otherBuffIcon then
        row.otherIcon:SetTexture(otherBuffIcon)
        row.otherIcon:Show()
    else
        row.otherIcon:Hide()
    end
    row:Show()
end

local function RefreshStatusWindow()
    if not statusWindow:IsShown() then return end
    if not PaladinSealAlert_GetStatusSnapshot then return end

    local snapshot = PaladinSealAlert_GetStatusSnapshot()

    local visibleBadges = {}
    SetBadgeStatus(sealBadge, snapshot.sealUp, snapshot.sealIcon or DEFAULT_SEAL_ICON)
    table.insert(visibleBadges, sealBadge)

    if snapshot.rfEnabled then
        SetBadgeStatus(rfBadge, snapshot.rfUp, RF_ICON)
        table.insert(visibleBadges, rfBadge)
    else
        rfBadge:Hide()
    end

    if snapshot.auraEnabled then
        SetBadgeStatus(auraBadge, snapshot.auraUp, snapshot.auraIcon or DEFAULT_AURA_ICON)
        table.insert(visibleBadges, auraBadge)
    else
        auraBadge:Hide()
    end

    LayoutBadges(visibleBadges)

    local barTop = BADGE_Y - BADGE_HEIGHT - 10
    local barWidth = statusWindow:GetWidth() - 16
    local rowIndex = 0

    local function PlaceRow(row)
        rowIndex = rowIndex + 1
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, barTop - (rowIndex - 1) * (BAR_HEIGHT + BAR_GAP))
        row:SetWidth(barWidth)
        return row
    end

    local shownUnits = {}
    for _, member in ipairs(snapshot.members) do
        local row = barRowsByUnit[member.unit]
        if row then
            shownUnits[member.unit] = true
            local label, mode
            if not member.online then
                label = member.name:sub(1, 8) .. " (offline)"
                mode = "offline"
            elseif member.outOfRange then
                label = member.name:sub(1, 8) .. " (out of range)"
                mode = "offline"
            else
                label = member.name:sub(1, 14)
                mode = member.hasBuff and "ok" or "bad"
            end
            SetBarStatus(PlaceRow(row), label, mode, member.class, member.buffIcon, member.otherBuffIcon)
        end
    end

    for unit, row in pairs(barRowsByUnit) do
        if not shownUnits[unit] then row:Hide() end
    end

    if snapshot.locked then
        SetBarStatus(PlaceRow(combatRow), "(combat)", "warn")
    else
        combatRow:Hide()
    end

    local totalHeight = (barTop * -1) + rowIndex * (BAR_HEIGHT + BAR_GAP) + 10
    statusWindow:SetHeight(math.max(70, totalHeight))
end

C_Timer.NewTicker(0.5, RefreshStatusWindow)

function PaladinSealAlert_RefreshStatusWindowVisibility()
    local db = PaladinSealAlertDB
    if not db then return end
    if db.showStatusWindow then
        statusWindow:Show()
        RefreshStatusWindow()
    else
        statusWindow:Hide()
    end
end

function PaladinSealAlert_ApplyStatusWindowScale()
    local db = PaladinSealAlertDB
    if not db then return end
    statusWindow:SetScale(db.statusWindowScale or 1.0)
end

local statusWindowInit = CreateFrame("Frame")
statusWindowInit:RegisterEvent("PLAYER_LOGIN")
statusWindowInit:SetScript("OnEvent", function()
    local db = PaladinSealAlertDB
    if not db then return end
    if db.statusWindowPoint and db.statusWindowX and db.statusWindowY then
        statusWindow:ClearAllPoints()
        statusWindow:SetPoint(db.statusWindowPoint, UIParent, db.statusWindowRelPoint or db.statusWindowPoint, db.statusWindowX, db.statusWindowY)
    end
    PaladinSealAlert_ApplyStatusWindowScale()
    PaladinSealAlert_RefreshStatusWindowVisibility()
end)

