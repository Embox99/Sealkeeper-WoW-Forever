-- PaladinSealAlert: core logic (aura scanning, alert triggering, saved settings, slash commands)

local PREFIX = "|cff3399ffSealkeeper|r: "

-- Which Blessing each click type on a status window row casts — keyed so
-- both the slash command and the options panel dropdown can validate/label
-- against the same list. Exposed below for UI.lua.
local BLESSING_SPELLS = {
    kings  = "Blessing of Kings",
    might  = "Blessing of Might",
    wisdom = "Blessing of Wisdom",
}
local BLESSING_ORDER = { "kings", "might", "wisdom" }

-- Rank 1 spell IDs — only used to look up the client's own localized name,
-- so /cast works on non-English clients (the English name above is the
-- fallback if the ID isn't known to this client).
local BLESSING_SPELL_IDS = {
    kings = 20217, might = 19740, wisdom = 19742,
}
local BLESSING_CLICK_DB_KEYS = {
    click = "blessingPlainKey",
    ctrl  = "blessingCtrlKey",
    shift = "blessingShiftKey",
}

-- ---------------------------------------------------------------------------
-- Defaults / saved settings
-- ---------------------------------------------------------------------------

local defaults = {
    enablePopup = true,
    enableSound = true,
    soundPreset = "raidwarning",   -- see SOUND_PRESET_ORDER below
    warnBeforeSeconds = 3,         -- seconds of remaining duration to fire an early warning; 0 disables it
    alertThrottleSeconds = 2,      -- minimum gap between repeat alerts for the same buff (guards against lag-flicker spam)
    popupDuration = 3,             -- how long the popup stays on screen
    msgExpired = "SEAL EXPIRED",
    msgWarning = "Seal expiring",
    debug = false,
    soundChannel = "Master",       -- "Master" | "SFX" | "Ambience" | "Music" | "Dialog"
    soundVolume = 100,             -- 0-100, relative to that channel's own volume setting
    textColorR = 1,
    textColorG = 0.15,
    textColorB = 0.15,
    textSize = 20,
    enableGroupBlessingWatch = true,
    msgGroupExpired = "Blessing expired: {name}",
    msgGroupWarning = "Blessing expiring: {name}",
    groupTextColorR = 0.3,
    groupTextColorG = 0.6,
    groupTextColorB = 1,
    groupTextSize = 18,
    groupPopupDuration = 3,
    groupSoundPreset = "readycheck", -- see SOUND_PRESET_ORDER below
    groupSoundChannel = "Master",
    groupSoundVolume = 100,        -- 0-100, relative to that channel's own volume setting
    enableRighteousFuryWatch = true,
    msgRFExpired = "RIGHTEOUS FURY EXPIRED",
    msgRFWarning = "Righteous Fury expiring",
    showStatusWindow = true,
    statusWindowScale = 1.0,
    statusWindowLocked = false,
    statusWindowMinimal = false,   -- hide the title bar and close button
    statusIconLabels = true,       -- show icon textures instead of "Seal"/"RF"/"Aura" text on the badges
    blessingPlainKey = "kings",    -- which Blessing each click type casts on a party row — see BLESSING_SPELLS below
    blessingCtrlKey = "might",
    blessingShiftKey = "wisdom",
    groupWarnBeforeSeconds = 10,   -- early warning for party Blessings (they last minutes, so 3s is too late to rebuff); 0 disables it
    enableAuraWatch = true,
    msgAuraExpired = "AURA NOT ACTIVE",
    msgAuraWarning = "",
}

-- Bump when saved data needs migrating. New keys don't need a bump —
-- InitDB fills in anything missing from defaults.
local DB_VERSION = 3

local function InitDB()
    PaladinSealAlertDB = PaladinSealAlertDB or {}
    -- Pre-v3 layouts used different keys, so those get one clean start.
    -- Anything newer is kept as-is: a version bump must never wipe people's
    -- settings and window position again, only migrate what changed.
    if (PaladinSealAlertDB.dbVersion or 0) < 3 then
        PaladinSealAlertDB = {}
    end
    for key, value in pairs(defaults) do
        if PaladinSealAlertDB[key] == nil then
            PaladinSealAlertDB[key] = value
        end
    end
    PaladinSealAlertDB.dbVersion = DB_VERSION
end

-- ---------------------------------------------------------------------------
-- Sound handling
-- ---------------------------------------------------------------------------

local SOUND_PRESET_NAMED = {}

local function SafeSoundKit(presetKey, name, fallbackID)
    if SOUNDKIT and SOUNDKIT[name] then
        SOUND_PRESET_NAMED[presetKey] = true
        return SOUNDKIT[name]
    end
    SOUND_PRESET_NAMED[presetKey] = false
    return fallbackID
end

-- All built from the client's own sound library (SOUNDKIT), never an
-- external file — PlaySoundFile on a real external file is the thing
-- that's silently broken on this beta client; PlaySound(kitID) isn't.
local SOUND_PRESETS = {
    raidwarning = SafeSoundKit("raidwarning", "RAID_WARNING", 8959),
    readycheck  = SafeSoundKit("readycheck", "READY_CHECK", 8960),
    alarm       = SafeSoundKit("alarm", "ALARM_CLOCK_WARNING_3", 12867),
    alarm2      = SafeSoundKit("alarm2", "ALARM_CLOCK_WARNING_2", 12866),
    alarm1      = SafeSoundKit("alarm1", "ALARM_CLOCK_WARNING_1", 12865),
    whisper     = SafeSoundKit("whisper", "TELL_MESSAGE", 3081),
    pvpqueue    = SafeSoundKit("pvpqueue", "PVP_THROUGH_QUEUE", 8458),
    epicloot    = SafeSoundKit("epicloot", "UI_EPICLOOT_TOAST", 8960),
}

local SOUND_PRESET_ORDER = {
    "raidwarning", "readycheck", "alarm", "alarm2", "alarm1",
    "whisper", "pvpqueue", "epicloot",
}

-- One entry per sound you can configure separately (seal/RF/Aura alert vs.
-- group blessing alert) — playback and slash commands both read this table.
local SOUND_TARGETS = {
    sound = { presetKey = "soundPreset", channelKey = "soundChannel",
        volumeKey = "soundVolume", tag = "seal", label = "sound" },
    groupsound = { presetKey = "groupSoundPreset", channelKey = "groupSoundChannel",
        volumeKey = "groupSoundVolume", tag = "group", label = "group sound" },
}

-- There's no per-call volume on PlaySound/PlaySoundFile — the standard
-- workaround (same one most alert-sound addons use) is to nudge the
-- channel's own volume cvar for the duration of the sound, then put it
-- back. volumePercent 100 skips all of this and just plays normally.
local CHANNEL_CVARS = {
    Master   = "Sound_MasterVolume",
    SFX      = "Sound_SFXVolume",
    Ambience = "Sound_AmbienceVolume",
    Music    = "Sound_MusicVolume",
    Dialog   = "Sound_DialogVolume",
}

local function PlayAtVolume(channel, volumePercent, playFunc)
    volumePercent = volumePercent or 100
    local cvarName = CHANNEL_CVARS[channel]
    if not cvarName or volumePercent >= 100 then
        return playFunc()
    end

    local original = tonumber(GetCVar(cvarName))
    local ok = pcall(SetCVar, cvarName, (original or 1) * (volumePercent / 100))
    local willPlay, handle = playFunc()
    if ok and original then
        C_Timer.After(2.5, function() pcall(SetCVar, cvarName, original) end)
    end
    return willPlay, handle
end

local function PlayConfiguredSound(isGroup)
    local db = PaladinSealAlertDB
    local target = isGroup and SOUND_TARGETS.groupsound or SOUND_TARGETS.sound
    local tag = target.tag
    local preset = db[target.presetKey]
    local channel = db[target.channelKey]
    local volume = db[target.volumeKey]

    local kitID = SOUND_PRESETS[preset] or SOUND_PRESETS.raidwarning
    local willPlay, handle = PlayAtVolume(channel, volume, function()
        return PlaySound(kitID, channel, true)
    end)
    if db.debug then
        print(PREFIX .. "[" .. tag .. "] PlaySound preset=" .. preset .. " kitID=" .. tostring(kitID)
            .. " named=" .. tostring(SOUND_PRESET_NAMED[preset])
            .. " -> willPlay=" .. tostring(willPlay) .. " handle=" .. tostring(handle))
    end
end

-- ---------------------------------------------------------------------------
-- Aura scanning (compatible with the modern C_UnitAuras API, with a
-- fallback to the legacy UnitAura() call in case it is still exposed)
-- ---------------------------------------------------------------------------

local GetAuraData
if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    GetAuraData = function(unit, index)
        return C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
    end
elseif UnitAura then
    GetAuraData = function(unit, index)
        local name, _, _, _, duration, expirationTime, unitCaster, _, _, spellId = UnitAura(unit, index, "HELPFUL")
        if not name then return nil end
        return { name = name, duration = duration, expirationTime = expirationTime, spellId = spellId, sourceUnit = unitCaster }
    end
end

-- Each matcher is: English/Russian name patterns, plus spell IDs whose
-- localized names get resolved at login (so German, French, Spanish,
-- Chinese, etc. clients work too), plus names that must never match.

local function GetSpellNameByID(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and name then return name end
    end
    return nil
end

local SEAL_MATCHER = {
    patterns = { "^Seal of ", "^Печать " },
    -- Righteousness (both rank-1 IDs seen across versions), Crusader,
    -- Command, Justice, Light, Wisdom
    spellIDs = { 20154, 21084, 21082, 20375, 20164, 20165, 20166 },
}

-- Protection/Freedom/Sacrifice are short
-- emergency buffs, not "your Blessing" on someone — they'd otherwise fire a
-- bogus "Blessing expired" seconds after every BoP.
local BLESSING_MATCHER = {
    patterns = { "^Blessing of ", "^Благословение " },
    spellIDs = { 19740, 19742, 20217 },
    excludeNames = { "Blessing of Protection", "Blessing of Freedom", "Blessing of Sacrifice",
                     "Благословение защиты", "Благословение свободы", "Благословение жертвенности" },
    excludeSpellIDs = { 1022, 1044, 6940 },
}

local RIGHTEOUS_FURY_MATCHER = {
    patterns = { "^Righteous Fury$", "^Праведная ярость$" },
    spellIDs = { 25780 },
}

-- Devotion Aura, Retribution Aura, resistance auras, etc. These don't expire
-- on their own (only cancelled/replaced/death removes them) — we're just
-- checking whether any of them is up, not which one.
local AURA_MATCHER = {
    patterns = { " Aura$", "^Аура " },
    spellIDs = { 465, 7294, 19746, 19876, 19888, 19891, 20218 },
}

local ALL_MATCHERS = { SEAL_MATCHER, BLESSING_MATCHER, RIGHTEOUS_FURY_MATCHER, AURA_MATCHER }

-- Called at login, once spell data is available.
local function ResolveLocalizedSpellNames()
    for _, matcher in ipairs(ALL_MATCHERS) do
        matcher.names = {}
        for _, id in ipairs(matcher.spellIDs or {}) do
            local name = GetSpellNameByID(id)
            if name then matcher.names[name] = true end
        end
        matcher.excluded = {}
        for _, name in ipairs(matcher.excludeNames or {}) do
            matcher.excluded[name] = true
        end
        for _, id in ipairs(matcher.excludeSpellIDs or {}) do
            local name = GetSpellNameByID(id)
            if name then matcher.excluded[name] = true end
        end
    end
end

local function MatchesAura(name, matcher)
    if not name then return false end
    if matcher.excluded and matcher.excluded[name] then return false end
    if matcher.names and matcher.names[name] then return true end
    for _, pattern in ipairs(matcher.patterns) do
        if name:find(pattern) then
            return true
        end
    end
    return false
end

-- Unit checks can return "secret" values on this client in some states,
-- which throw when tested — treat anything unreadable as `fallback`.
local function SafeUnitCheck(func, unit, fallback)
    if not func then return fallback end
    local ok, result = pcall(function() return func(unit) and true or false end)
    if ok then return result end
    return fallback
end

local function GetBlessingSpellName(key)
    local id = BLESSING_SPELL_IDS[key]
    return (id and GetSpellNameByID(id)) or BLESSING_SPELLS[key] or BLESSING_SPELLS.kings
end

-- In combat, this client blocks all aura reads from addons (even your own
-- buffs) — a deliberate anti-bot restriction, not something to work around.
-- We just detect it and skip that tick's scan.
local function AurasAreSecret()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        return ok and secret
    end
    return false
end

-- sourceUnit, if given, only matches auras YOU cast — otherwise any
-- paladin's Blessing on someone reads as "buffed", even if yours fell off.
local function FindAuraMatching(unit, matcher, sourceUnit)
    if not GetAuraData then return nil end
    if AurasAreSecret() then return nil end

    local index = 1
    while true do
        local ok, aura = pcall(GetAuraData, unit, index)
        if not ok or not aura then break end
        if MatchesAura(aura.name, matcher) then
            if not sourceUnit or (aura.sourceUnit and UnitIsUnit(aura.sourceUnit, sourceUnit)) then
                return aura
            end
        end
        index = index + 1
    end
    return nil
end

-- Same scan, but for a Blessing from anyone EXCEPT excludeSourceUnit — lets
-- the status window show "someone else already buffed them" separately.
local function FindAuraMatchingOtherSource(unit, matcher, excludeSourceUnit)
    if not GetAuraData then return nil end
    if AurasAreSecret() then return nil end

    local index = 1
    while true do
        local ok, aura = pcall(GetAuraData, unit, index)
        if not ok or not aura then break end
        if MatchesAura(aura.name, matcher) then
            if not (aura.sourceUnit and UnitIsUnit(aura.sourceUnit, excludeSourceUnit)) then
                return aura
            end
        end
        index = index + 1
    end
    return nil
end

local function FindActiveSeal()
    return FindAuraMatching("player", SEAL_MATCHER)
end

local function FindActiveRighteousFury()
    return FindAuraMatching("player", RIGHTEOUS_FURY_MATCHER)
end

-- Only YOUR aura counts — otherwise another paladin's Devotion Aura (or a
-- hunter's Trueshot Aura, which also ends in " Aura") hides that yours is off.
local function FindActiveAura()
    return FindAuraMatching("player", AURA_MATCHER, "player")
end

-- ---------------------------------------------------------------------------
-- Alert state machine
-- ---------------------------------------------------------------------------

local function TriggerAlert(message, isGroup)
    local db = PaladinSealAlertDB
    if db.enableSound then
        PlayConfiguredSound(isGroup)
    end
    -- An emptied message text means "sound only" for that alert.
    if not db.enablePopup or not message or message == "" then return end

    if isGroup and PaladinSealAlert_ShowGroupPopup then
        PaladinSealAlert_ShowGroupPopup(message, db.groupPopupDuration)
    elseif not isGroup and PaladinSealAlert_ShowPopup then
        PaladinSealAlert_ShowPopup(message, db.popupDuration)
    end
end

local function FormatGroupMessage(template, name)
    return (template:gsub("{name}", name))
end

-- ---------------------------------------------------------------------------
-- Shared "did it fall off, should we warn" logic — used both for your own
-- buffs (seal/RF/Aura) and for each party member's Blessing.
-- ---------------------------------------------------------------------------

-- Guards against alert spam when a buff flickers (lag causing the aura scan
-- to briefly see it drop and reappear) — won't fire the same kind of alert
-- for this state twice within alertThrottleSeconds.
local function PassesThrottle(state, fieldKey)
    local db = PaladinSealAlertDB
    local throttle = (db and db.alertThrottleSeconds) or 0
    local now = GetTime()
    if throttle > 0 and state[fieldKey] and (now - state[fieldKey]) < throttle then
        return false
    end
    state[fieldKey] = now
    return true
end

local function UpdateBuffState(state, aura, warnBeforeSeconds, onWarning, onExpired)
    if aura then
        local signature = aura.name .. tostring(aura.expirationTime)
        if signature ~= state.signature then
            state.signature = signature
            state.warned = false
        end
        state.has = true

        if warnBeforeSeconds > 0 and not state.warned
            and aura.expirationTime and aura.expirationTime > 0 then
            local remaining = aura.expirationTime - GetTime()
            if remaining > 0 and remaining <= warnBeforeSeconds then
                state.warned = true
                if PassesThrottle(state, "lastWarnAlert") then
                    onWarning()
                end
            end
        end
    else
        if state.has and PassesThrottle(state, "lastExpireAlert") then
            onExpired()
        end
        state.has = false
        state.signature = nil
        state.warned = false
    end
end

-- Forget a buff without alerting — used when it's gone for a reason that
-- isn't worth an alert (death wipes every buff at once).
local function ClearBuffStateSilently(state)
    state.has = false
    state.signature = nil
    state.warned = false
    state.icon = nil
end

-- ---------------------------------------------------------------------------
-- Group blessing watch (player + party1-4). Keyed by GUID, not unit token,
-- so someone leaving/joining mid-session doesn't get mixed up with whoever
-- was in that slot before.
-- ---------------------------------------------------------------------------

local GROUP_UNITS = { "player", "party1", "party2", "party3", "party4" }
local groupState = {}

local function ScanGroupBlessings()
    local db = PaladinSealAlertDB
    if not db.enableGroupBlessingWatch then return end

    for _, unit in ipairs(GROUP_UNITS) do
        local guid = UnitExists(unit) and UnitGUID(unit)
        if guid then
            local name = UnitName(unit) or unit
            local state = groupState[guid]
            if not state then
                state = { has = false, signature = nil, warned = false }
                groupState[guid] = state
            end

            if SafeUnitCheck(UnitIsDeadOrGhost, unit, false) then
                -- Dying wipes every buff — that's not a missed Blessing.
                ClearBuffStateSilently(state)
                state.otherIcon = nil
            elseif SafeUnitCheck(UnitIsConnected, unit, true)
                and SafeUnitCheck(UnitIsVisible, unit, true) then
                -- Offline or too far away to be visible: the client returns
                -- no auras at all, which would read as "Blessing fell off".
                -- Those are skipped, keeping the last known state.
                local aura = FindAuraMatching(unit, BLESSING_MATCHER, "player")
                state.icon = aura and aura.icon or nil

                local otherAura = FindAuraMatchingOtherSource(unit, BLESSING_MATCHER, "player")
                state.otherIcon = otherAura and otherAura.icon or nil

                UpdateBuffState(state, aura, db.groupWarnBeforeSeconds or db.warnBeforeSeconds,
                    function() TriggerAlert(FormatGroupMessage(db.msgGroupWarning, name), true) end,
                    function() TriggerAlert(FormatGroupMessage(db.msgGroupExpired, name), true) end)
            end
        end
    end
end

-- Drops state for people who've left the group, so someone rejoining later
-- doesn't fire an "expired" alert for a Blessing from an hour ago.
local function PruneGroupState()
    local present = {}
    for _, unit in ipairs(GROUP_UNITS) do
        local guid = UnitExists(unit) and UnitGUID(unit)
        if guid then present[guid] = true end
    end
    for guid in pairs(groupState) do
        if not present[guid] then groupState[guid] = nil end
    end
end

-- ---------------------------------------------------------------------------
-- Self-buff watches (seal, Righteous Fury, ...). Same fall-off/early-warning
-- state machine, parameterized so adding another watched self-buff is just
-- another entry in SELF_WATCHES.
-- ---------------------------------------------------------------------------

local SELF_WATCHES = {
    { key = "seal", find = FindActiveSeal, enabledKey = nil,
      msgExpiredKey = "msgExpired", msgWarningKey = "msgWarning",
      has = false, signature = nil, warned = false },
    { key = "rf", find = FindActiveRighteousFury, enabledKey = "enableRighteousFuryWatch",
      msgExpiredKey = "msgRFExpired", msgWarningKey = "msgRFWarning",
      has = false, signature = nil, warned = false },
    { key = "aura", find = FindActiveAura, enabledKey = "enableAuraWatch",
      msgExpiredKey = "msgAuraExpired", msgWarningKey = "msgAuraWarning",
      has = false, signature = nil, warned = false },
}

local function GetSelfWatch(key)
    for _, watch in ipairs(SELF_WATCHES) do
        if watch.key == key then return watch end
    end
    return nil
end

local function ProcessSelfWatch(watch)
    local db = PaladinSealAlertDB
    if watch.enabledKey and not db[watch.enabledKey] then
        watch.has = false
        watch.signature = nil
        watch.warned = false
        watch.icon = nil
        return
    end

    -- Cache the aura's own icon so the status window can show it instead of
    -- a plain text label (each Seal/Aura variant has a different icon).
    local aura = watch.find()
    watch.icon = aura and aura.icon or nil

    UpdateBuffState(watch, aura, db.warnBeforeSeconds,
        function() TriggerAlert(db[watch.msgWarningKey]) end,
        function() TriggerAlert(db[watch.msgExpiredKey]) end)
end

local function OnTick()
    if AurasAreSecret() then
        -- Buff tracking is silently paused for the duration of combat (see
        -- AurasAreSecret) and resumes on its own once combat ends.
        return
    end

    if SafeUnitCheck(UnitIsDeadOrGhost, "player", false) then
        -- Dead: Seal/RF/Aura are all gone, and alerting about it while you
        -- wait for a rez is just noise.
        for _, watch in ipairs(SELF_WATCHES) do
            ClearBuffStateSilently(watch)
        end
    else
        for _, watch in ipairs(SELF_WATCHES) do
            ProcessSelfWatch(watch)
        end
    end
    ScanGroupBlessings()
end

-- UNIT_AURA can fire many times in one frame (a whole party buffed at
-- once); batch those into a single scan shortly after.
local scanPending = false
local function RequestScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.1, function()
        scanPending = false
        OnTick()
    end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local ticker = nil

local function IsPlayerPaladin()
    if UnitClassBase then
        return UnitClassBase("player") == "PALADIN"
    end
    return select(2, UnitClass("player")) == "PALADIN"
end

local function StartWatching()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.5, OnTick)
end

local function StopWatching()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        InitDB()
        ResolveLocalizedSpellNames()
        if IsPlayerPaladin() then
            print(PREFIX .. "loaded. Type /sealalert help for options.")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsPlayerPaladin() then
            StartWatching()
        else
            StopWatching()
        end
    elseif event == "UNIT_AURA" then
        if IsPlayerPaladin() and (unit == "player" or (unit and unit:match("^party%d$"))) then
            RequestScan()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        PruneGroupState()
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

-- "sfx" -> "SFX", "master" -> "Master"; nil for anything that isn't a real
-- channel (PlaySound with a bogus channel name just plays nothing).
local function NormalizeChannel(input)
    if not input then return nil end
    for channel in pairs(CHANNEL_CVARS) do
        if channel:lower() == input:lower() then return channel end
    end
    return nil
end

local function SetChannel(dbKey, label, input)
    local channel = NormalizeChannel(input)
    if channel then
        PaladinSealAlertDB[dbKey] = channel
        print(PREFIX .. label .. " channel: " .. channel)
    else
        print(PREFIX .. "unknown channel. Available: Master, SFX, Ambience, Music, Dialog")
    end
end

local function PrintHelp()
    print(PREFIX .. "commands:")
    print("  /sealalert sound on|off — toggle sound")
    print("  /sealalert popup on|off — toggle popup text")
    print("  /sealalert sound preset <name> — pick a built-in sound: " .. table.concat(SOUND_PRESET_ORDER, ", "))
    print("  /sealalert warn <seconds> — warn N seconds before the seal expires (0 disables it)")
    print("  /sealalert groupwarn <seconds> — warn N seconds before a party member's Blessing expires (0 disables it)")
    print("  /sealalert throttle <seconds> — minimum gap between repeat alerts for the same buff (0 disables it)")
    print("  /sealalert duration <seconds> — how long the popup stays on screen")
    print("  /sealalert text expired <text> — message shown when the seal is gone")
    print("  /sealalert text warning <text> — early-warning message")
    print("  /sealalert channel <Master|SFX|Ambience|Music|Dialog> — change the sound channel")
    print("  /sealalert sound volume <0-100> — seal/RF/Aura alert volume")
    print("  /sealalert groupsound preset <name> — same list, for group blessing alerts")
    print("  /sealalert groupsound channel <Master|SFX|Ambience|Music|Dialog> — channel for group blessing alerts")
    print("  /sealalert groupsound volume <0-100> — group blessing alert volume")
    print("  /sealalert debug on|off — print diagnostic info when playing sounds")
    print("  /sealalert rf on|off — toggle watching Righteous Fury")
    print("  /sealalert rftext expired|warning <text> — Righteous Fury alert text")
    print("  /sealalert testrf — test the Righteous Fury alert")
    print("  /sealalert aura on|off — toggle watching your Paladin Aura (Devotion, etc.)")
    print("  /sealalert auratext expired|warning <text> — Aura alert text")
    print("  /sealalert testaura — test the Aura alert")
    print("  /sealalert group on|off — toggle watching party members' Blessings")
    print("  /sealalert statuswindow on|off — toggle the status window (who lacks a Blessing, Righteous Fury up?)")
    print("  /sealalert scale <0.6-1.6> — resize the status window")
    print("  /sealalert icons on|off — show icons instead of text labels on the status window badges")
    print("  /sealalert lock on|off — lock the status window in place (stops accidental dragging)")
    print("  /sealalert minimal on|off — hide the status window's title and close button")
    print("  /sealalert blessing click|ctrl|shift kings|might|wisdom — set which Blessing each click type casts on a party row")
    print("  /sealalert status — show current settings")
    print("  /sealalert test — test the seal alert")
    print("  /sealalert testgroup — test the group blessing alert")
    print("  /sealalert reset — reset to defaults")
    print("  /sealalert options — open the settings panel")
end

local function PrintStatus()
    local db = PaladinSealAlertDB
    print(PREFIX .. "current settings:")
    print("  sound: " .. (db.enableSound and "on" or "off") .. ", channel: " .. db.soundChannel ..
        ", volume: " .. db.soundVolume .. "%" ..
        ", preset: " .. db.soundPreset)
    print("  popup: " .. (db.enablePopup and "on" or "off") .. ", duration: " .. db.popupDuration .. "s")
    print("  early warning: " .. db.warnBeforeSeconds .. "s before expiry (party Blessings: " .. db.groupWarnBeforeSeconds .. "s)")
    print("  alert throttle: " .. db.alertThrottleSeconds .. "s")
    print("  text (expired): " .. db.msgExpired)
    print("  text (warning): " .. db.msgWarning)
    print("  status window: " .. (db.showStatusWindow and "on" or "off") ..
        ", icons: " .. (db.statusIconLabels and "on" or "off") ..
        ", locked: " .. (db.statusWindowLocked and "on" or "off"))
    print("  party row clicks: click=" .. db.blessingPlainKey .. ", ctrl=" .. db.blessingCtrlKey .. ", shift=" .. db.blessingShiftKey)
    print("  Righteous Fury watch: " .. (db.enableRighteousFuryWatch and "on" or "off"))
    print("  Aura watch: " .. (db.enableAuraWatch and "on" or "off"))
    print("  group blessing watch: " .. (db.enableGroupBlessingWatch and "on" or "off") ..
        ", channel: " .. db.groupSoundChannel .. ", volume: " .. db.groupSoundVolume .. "%" ..
        ", preset: " .. db.groupSoundPreset)
end

-- Most commands are just an on/off toggle or an expired/warning text pair —
-- these tables let the dispatcher handle all of them with a couple branches
-- instead of one pair per command.

local TOGGLE_COMMANDS = {
    sound = { dbKey = "enableSound", label = "sound" },
    popup = { dbKey = "enablePopup", label = "popup" },
    debug = { dbKey = "debug", label = "debug" },
    rf = { dbKey = "enableRighteousFuryWatch", label = "Righteous Fury watch" },
    aura = { dbKey = "enableAuraWatch", label = "Aura watch" },
    group = { dbKey = "enableGroupBlessingWatch", label = "group blessing watch" },
    statuswindow = { dbKey = "showStatusWindow", label = "status window",
        onChange = function()
            if PaladinSealAlert_RefreshStatusWindowVisibility then PaladinSealAlert_RefreshStatusWindowVisibility() end
        end },
    icons = { dbKey = "statusIconLabels", label = "status window icon labels" },
    lock = { dbKey = "statusWindowLocked", label = "status window lock" },
    minimal = { dbKey = "statusWindowMinimal", label = "status window minimal look",
        onChange = function()
            if PaladinSealAlert_ApplyStatusWindowChrome then PaladinSealAlert_ApplyStatusWindowChrome() end
        end },
}

local TEXT_COMMANDS = {
    text = { expiredKey = "msgExpired", warningKey = "msgWarning", label = "" },
    rftext = { expiredKey = "msgRFExpired", warningKey = "msgRFWarning", label = "Righteous Fury " },
    auratext = { expiredKey = "msgAuraExpired", warningKey = "msgAuraWarning", label = "Aura " },
}

SLASH_PALADINSEALALERT1 = "/sealalert"
SLASH_PALADINSEALALERT2 = "/pechat"

SlashCmdList["PALADINSEALALERT"] = function(input)
    local db = PaladinSealAlertDB
    input = input or ""
    local args = {}
    for word in input:gmatch("%S+") do
        table.insert(args, word)
    end
    local cmd = (args[1] or ""):lower()
    local sub = (args[2] or ""):lower()

    local toggle = TOGGLE_COMMANDS[cmd]
    local soundTarget = SOUND_TARGETS[cmd]
    local textCmd = TEXT_COMMANDS[cmd]

    if toggle and sub == "on" then
        db[toggle.dbKey] = true
        if toggle.onChange then toggle.onChange() end
        print(PREFIX .. toggle.label .. " on")
    elseif toggle and sub == "off" then
        db[toggle.dbKey] = false
        if toggle.onChange then toggle.onChange() end
        print(PREFIX .. toggle.label .. " off")
    elseif soundTarget and sub == "preset" and args[3] then
        local preset = args[3]:lower()
        if SOUND_PRESETS[preset] then
            db[soundTarget.presetKey] = preset
            print(PREFIX .. soundTarget.label .. " preset: " .. preset)
        else
            print(PREFIX .. "unknown preset. Available: " .. table.concat(SOUND_PRESET_ORDER, ", "))
        end
    elseif soundTarget and sub == "channel" and args[3] then
        SetChannel(soundTarget.channelKey, soundTarget.label, args[3])
    elseif soundTarget and sub == "volume" and args[3] then
        local volume = tonumber(args[3])
        if volume then
            db[soundTarget.volumeKey] = math.max(0, math.min(100, volume))
            print(PREFIX .. soundTarget.label .. " volume: " .. db[soundTarget.volumeKey] .. "%")
        end
    elseif textCmd and sub == "expired" and args[3] then
        db[textCmd.expiredKey] = table.concat(args, " ", 3)
        print(PREFIX .. textCmd.label .. "expired text updated")
    elseif textCmd and sub == "warning" and args[3] then
        db[textCmd.warningKey] = table.concat(args, " ", 3)
        print(PREFIX .. textCmd.label .. "warning text updated")
    elseif cmd == "channel" and args[2] then
        -- Backward-compatible alias for "sound channel <x>".
        SetChannel("soundChannel", "sound", args[2])
    elseif cmd == "warn" and args[2] then
        local seconds = tonumber(args[2])
        if seconds then
            db.warnBeforeSeconds = seconds
            print(PREFIX .. "early warning: " .. seconds .. "s")
        end
    elseif cmd == "groupwarn" and args[2] then
        local seconds = tonumber(args[2])
        if seconds then
            db.groupWarnBeforeSeconds = math.max(0, seconds)
            print(PREFIX .. "party Blessing early warning: " .. db.groupWarnBeforeSeconds .. "s")
        end
    elseif cmd == "duration" and args[2] then
        local seconds = tonumber(args[2])
        if seconds then
            db.popupDuration = seconds
            print(PREFIX .. "popup duration: " .. seconds .. "s")
        end
    elseif cmd == "throttle" and args[2] then
        local seconds = tonumber(args[2])
        if seconds then
            db.alertThrottleSeconds = seconds
            print(PREFIX .. "alert throttle: " .. seconds .. "s")
        end
    elseif cmd == "scale" and args[2] then
        local scale = tonumber(args[2])
        if scale then
            db.statusWindowScale = scale
            if PaladinSealAlert_ApplyStatusWindowScale then PaladinSealAlert_ApplyStatusWindowScale() end
            print(PREFIX .. "status window scale: " .. scale)
        end
    elseif cmd == "blessing" and args[2] and args[3] then
        local clickKey = args[2]:lower()
        local blessingKey = args[3]:lower()
        local dbKey = BLESSING_CLICK_DB_KEYS[clickKey]
        if not dbKey then
            print(PREFIX .. "unknown click type. Available: click, ctrl, shift")
        elseif not BLESSING_SPELLS[blessingKey] then
            print(PREFIX .. "unknown blessing. Available: " .. table.concat(BLESSING_ORDER, ", "))
        else
            db[dbKey] = blessingKey
            if PaladinSealAlert_RefreshBlessingBindings then PaladinSealAlert_RefreshBlessingBindings() end
            print(PREFIX .. clickKey .. "-click now casts " .. GetBlessingSpellName(blessingKey))
        end
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "test" then
        TriggerAlert(db.msgExpired)
    elseif cmd == "testrf" then
        TriggerAlert(db.msgRFExpired)
    elseif cmd == "testaura" then
        TriggerAlert(db.msgAuraExpired)
    elseif cmd == "testgroup" then
        TriggerAlert(FormatGroupMessage(db.msgGroupExpired, UnitName("player")), true)
    elseif cmd == "reset" then
        for key, value in pairs(defaults) do
            db[key] = value
        end
        -- Push the restored values out to the popups, status window and
        -- click bindings right away instead of only after a /reload.
        if PaladinSealAlert_ApplyAllSettings then PaladinSealAlert_ApplyAllSettings() end
        print(PREFIX .. "settings reset")
    elseif cmd == "options" then
        if PaladinSealAlert_OpenOptions then
            PaladinSealAlert_OpenOptions()
        else
            print(PREFIX .. "settings panel unavailable, use slash commands.")
        end
    else
        PrintHelp()
    end
end

-- Exposed for UI.lua
PaladinSealAlert_SoundPresetOrder = SOUND_PRESET_ORDER
PaladinSealAlert_BlessingSpells = BLESSING_SPELLS
PaladinSealAlert_BlessingOrder = BLESSING_ORDER
PaladinSealAlert_GetBlessingSpellName = GetBlessingSpellName
PaladinSealAlert_IsPaladin = IsPlayerPaladin
PaladinSealAlert_TriggerTest = function() TriggerAlert(PaladinSealAlertDB.msgExpired) end
PaladinSealAlert_TriggerGroupTest = function()
    TriggerAlert(FormatGroupMessage(PaladinSealAlertDB.msgGroupExpired, UnitName("player")), true)
end
PaladinSealAlert_TriggerRFTest = function() TriggerAlert(PaladinSealAlertDB.msgRFExpired) end
PaladinSealAlert_TriggerAuraTest = function() TriggerAlert(PaladinSealAlertDB.msgAuraExpired) end

-- Snapshot for the status window. `locked` means we're in combat, so these
-- numbers are last-known rather than live.
function PaladinSealAlert_GetStatusSnapshot()
    local sealWatch = GetSelfWatch("seal")
    local rfWatch = GetSelfWatch("rf")
    local auraWatch = GetSelfWatch("aura")
    local members = {}
    for _, unit in ipairs(GROUP_UNITS) do
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            local state = guid and groupState[guid]
            local classToken
            if UnitClassBase then
                classToken = UnitClassBase(unit)
            else
                classToken = select(2, UnitClass(unit))
            end
            -- UnitInRange's results are "secret" values on this client (same
            -- anti-automation system as aura reads) — booleans that throw if
            -- you test them directly. Wrapped in pcall; if it throws, we
            -- just can't tell and assume in-range rather than block casts.
            local outOfRange = false
            pcall(function()
                local inRange, rangeChecked = UnitInRange(unit)
                if rangeChecked and not inRange then
                    outOfRange = true
                end
            end)
            table.insert(members, {
                unit = unit,
                name = UnitName(unit) or unit,
                hasBuff = state and state.has or false,
                buffIcon = state and state.icon or nil,
                otherBuffIcon = state and state.otherIcon or nil,
                class = classToken,
                online = SafeUnitCheck(UnitIsConnected, unit, true),
                dead = SafeUnitCheck(UnitIsDeadOrGhost, unit, false),
                outOfRange = outOfRange,
            })
        end
    end
    return {
        locked = AurasAreSecret(),
        sealUp = sealWatch and sealWatch.has or false,
        sealIcon = sealWatch and sealWatch.icon or nil,
        auraEnabled = PaladinSealAlertDB.enableAuraWatch,
        auraUp = auraWatch and auraWatch.has or false,
        auraIcon = auraWatch and auraWatch.icon or nil,
        rfEnabled = PaladinSealAlertDB.enableRighteousFuryWatch,
        rfUp = rfWatch and rfWatch.has or false,
        members = members,
    }
end
