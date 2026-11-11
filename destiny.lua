--[[
    destiny.lua - menu, overlays and effects for lmaobox
    open with F8 (default)
]]

---------------------------------------------------------------------------
-- 1. Basics, settings, config files
---------------------------------------------------------------------------
local floor, min, max, abs, sin, cos, sqrt, pi = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt, math.pi
local function clamp(v, a, b) return max(a, min(b, v)) end
local function now() return globals.RealTime() end
local function frameDt() return clamp(globals.AbsoluteFrameTime(), 0.0001, 0.1) end
local function round(v) return floor(v + 0.5) end

-- garbage = stutters
local C_BLACK, C_WHITE = { 0, 0, 0 }, { 255, 255, 255 }
-- fixed lists and a few state values live in one table
local L = {}
-- cleanup: lmaobox's draw calls leave ~250 bytes of garbage each
pcall(collectgarbage, "generational", 20, 100)                     -- (draw.Color garbage dies young: cheap small cleanups)
pcall(collectgarbage, "restart")                                   -- (Lua's own cleanup; destiny no longer drives it)
function L.gcStep()
    if L.gcOff then return end
    local t0 = L.clock and L.clock() or 0
    local ok, err = pcall(L.gcStepInner)
    L.gcMs = ((L.clock and L.clock() or 0) - t0) * 1000
    if not ok then                                                  -- lmaobox refuses it: back to Lua's own cleanup
        L.gcOff = true
        pcall(collectgarbage, "restart")
        print("[destiny] own memory cleanup not allowed (" .. tostring(err) .. "), using the normal one")
    end
end
function L.gcStepInner()
    local kb = collectgarbage("count")
    local made = kb - (L.gcLast or kb)
    if made < 0 then made = 0 end
    -- many tiny steps instead of one big one (one big step did a whole sweep at once = 25-50 ms spikes),
    -- at most ~2 ms per frame (more only if memory gets really big)
    local want = made * 2 + 64
    local budget = (kb > 150000) and 0.006 or 0.002
    local t0, done = L.clock(), 0
    while done < want and (L.clock() - t0) < budget do
        if collectgarbage("step", 32) then break end                    -- (true = a cleanup round just finished)
        done = done + 32
    end
    L.gcLast = collectgarbage("count")
end

-- memory readout for the Info page
local perf = { kb = 0, rate = 0, lastKb = nil, at = 0, made = 0 }
local function perfTick()
    local kb = collectgarbage("count")
    if perf.lastKb and kb > perf.lastKb then perf.made = perf.made + (kb - perf.lastKb) end
    perf.lastKb, perf.kb = kb, kb
    if globals.RealTime() - perf.at >= 1 then
        perf.rate, perf.made, perf.at = perf.made / max(0.001, globals.RealTime() - perf.at), 0, globals.RealTime()
    end
end

-- where configs are saved
local LUA_DIR, DIR = "", nil
pcall(function()
    local ok, info = pcall(debug.getinfo, 1, "S")
    local src = ok and info and info.source or ""
    LUA_DIR = src:match("^@?(.*[\\/])")
    if not LUA_DIR then
        local ok2, name = pcall(GetScriptName)
        LUA_DIR = ok2 and tostring(name):match("^(.*[\\/])") or nil
    end
    if not LUA_DIR then
        local ok3, la = pcall(os.getenv, "LOCALAPPDATA")
        LUA_DIR = (ok3 and la) and (la .. "\\lua\\") or ""
    end
end)
pcall(filesystem.CreateDirectory, LUA_DIR .. "destiny_files")
pcall(filesystem.CreateDirectory, "destiny_files")
L.CFG_TRIED = {}
for _, dir in ipairs({ LUA_DIR, LUA_DIR .. "destiny_files\\", "destiny_files\\", "" }) do
    local ok, f, err = pcall(io.open, dir .. "destiny_write_test.tmp", "w")
    if ok and f then
        f:write("ok"); f:close()
        pcall(os.remove, dir .. "destiny_write_test.tmp")
        DIR = dir
        break
    end
    L.CFG_TRIED[#L.CFG_TRIED + 1] = (dir == "" and "TF2 folder" or dir) .. ": " .. tostring(ok and err or f)
end

local DEFAULTS = {
    -- appearance
    theme = 1, accent = 1, logo = 1, opacity = 100,
    bgDim = 35, bgFx = 2, bgFxAmt = 50, menuGlow = true,
    colAccent = "", colWin = "", colSide = "", colCard = "", colText = "", colText2 = "", colBorder = "", colSwitch = "",
    -- watermark
    wmOn = true, wmStyle = 2, wmFps = true, wmMap = true, wmTime = true,
    -- notifications
    ntOn = true, ntStyle = 1, ntPos = 1, ntTime = 4, ntKills = true, ntDeaths = true, ntStreaks = true, ntAssists = true, ntFeatures = true, ntDom = true,
    ntBg = true, ntBorder = 2, ntGrad = 1,
    -- hit effects: screen edge effect + extra effect + shake
    vigOn = true, vigStyle = 1, vigColor = 1, vigHit = true, vigKill = true, vigInt = 70, vigSize = 14, vigTintAmt = 10,
    vigAnim = false, vigSpeed = 5, vigStay = 900, colHit = "FF2D55", colKill = "10B981",
    fxExtra = 2, fxOnHit = false, fxOnKill = true,
    ptOn = true, ptStyle = 9, ptKillStyle = 7, ptHit = true, ptKill = true, ptAmt = 100, ptSize = 100, ptCol = 1,
    shakeOn = false, shakeStyle = 1, shakeAmt = 40, shakeOnHit = false,
    dmgOn = true, dmgStyle = 2, hitSound = 1, killSound = 1,
    -- kill announcer
    kaOn = true, kaStyle = 2, kaWindow = 4, kaSound = true, kaColor = 1, colKa = "",
    -- world
    worldOn = false, worldPreset = 1, worldHue = 260, worldBright = 80, worldSky = true, worldProps = true,
    skyOn = false, skyName = "", skySel = 1, libSel = 1,
    -- overlay HUD, input monitor, speed graph
    flOn = false, flStyle = 1, flBorder = 1, flGrad = 1, flCompact = false, flKeys = true,
    imOn = false, imStyle = 1, imBg = true, sgOn = false, sgStyle = 1, sgBg = true,
    -- waifus
    compOn = false, compChar = 1, compSize = 100, compBubbles = true, compFollow = true,
    paiVoice = true, paiFont = true, paiLogs = true, paiLogTime = 4,
    paiIdle = true, paiIdleEvery = 90, compReact = true,
    -- pets
    petOn = false, petSel = 1, petSize = 100, petDist = 60, petSide = 1, petFront = true, petCam = false, petReact = true, pdlSel = 1,
    -- extras
    hmOn = false, hmStyle = 1, hmCol = 1, hmSize = 9, hmThick = 2, hmTime = 350, hmHead = true,
    trOn = false, trStyle = 1, trCol = 1, trTime = 600,
    kcOn = false, kcTime = 4, cmOn = false, rtOn = false, mcOn = false,
    trlOn = false, trlStyle = 1, trlCol = 1, trlLen = 6, trlSpeed = 400, trlAlways = false, trlWidth = 6,
    wxOn = false, wxKind = 1, wxAmt = 40, wxAlpha = 70,
    vmOn = false, vmX = 0, vmY = 0, vmZ = 0, vmFov = 70, vmSway = false, vmHide = false,
    cleanKey = 1, ksSound = 1,
    -- player HUDs
    phStyle = 1, phBorder = 1, phGrad = 1,
    ssOn = false, kfOn = false, kfTime = 6, kfAssists = true, kfHide = false, hpOn = false, hpAmmo = true, hpHide = false,
    ksOn = true, ksStyle = 1, ksMin = 2, ksBanner = true, rsOn = true, rsTime = 8,
    lhOn = true, lhAt = 35, lhInt = 60, lhPulse = true, colLow = "",
    -- crosshair
    chOn = false, chShape = 1, chSize = 7, chGap = 4, chThick = 2, chAlpha = 100, chOutline = true, colCh = "", chGrad = 1,
    chAnim = 1, chSpeed = 5, chMove = false, chFire = false, chHit = true, chKill = true, chHide = false,
    -- config
    slot = 1,
    -- menu key
    menuKey = 1,
    gcMode = 1,                                                        -- (memory cleanup: 1 generational, 2 normal)
}

-- keys that can open the destiny menu
L.MENU_KEYS = {
    { "F8", KEY_F8 }, { "Home", KEY_HOME }, { "End", KEY_END }, { "Delete", KEY_DELETE }, { "Page Up", KEY_PAGEUP },
    { "Page Down", KEY_PAGEDOWN }, { "Right Shift", KEY_RSHIFT }, { "Right Ctrl", KEY_RCONTROL },
    { "Right Alt", KEY_RALT }, { "Scroll Lock", KEY_SCROLLLOCK }, { "F2", KEY_F2 }, { "F3", KEY_F3 },
    { "F4", KEY_F4 }, { "F5", KEY_F5 }, { "F6", KEY_F6 }, { "F7", KEY_F7 },
}

local settings = { pos = {} }
for k, v in pairs(DEFAULTS) do settings[k] = v end

local function serialize()
    local lines = {}
    for k in pairs(DEFAULTS) do lines[#lines + 1] = k .. "=" .. tostring(settings[k]) end
    for id, p in pairs(settings.pos) do lines[#lines + 1] = "pos." .. id .. "=" .. floor(p[1]) .. "," .. floor(p[2]) end
    table.sort(lines)
    return table.concat(lines, "\n")
end

local function deserialize(s)
    for line in s:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_%.]+)=(.*)$")
        if k then
            local pid = k:match("^pos%.(.+)$")
            if pid then
                local x, y = v:match("^(-?%d+),(-?%d+)$")
                if x then settings.pos[pid] = { tonumber(x), tonumber(y) } end
            elseif DEFAULTS[k] ~= nil then
                local d = DEFAULTS[k]
                if type(d) == "boolean" then settings[k] = (v == "true")
                elseif type(d) == "number" then settings[k] = tonumber(v) or d
                else settings[k] = v end
            end
        end
    end
end

-- configs: destiny_autosave.cfg, destiny_slot1.cfg, ..
local function configPath(name) return (DIR or LUA_DIR) .. "destiny_" .. name .. ".cfg" end

-- returns true, or false + the reason
local function saveConfig(name)
    if not io then return false, "file access (io) is blocked by lmaobox" end
    if not DIR then return false, "lmaobox lets destiny write in none of: " .. table.concat(L.CFG_TRIED, " | ") end
    local ok, f, err = pcall(io.open, configPath(name), "w")
    if not ok or not f then return false, tostring(ok and err or f) end
    f:write(serialize())
    f:close()
    return true
end

local function loadConfig(name)
    if not io or not DIR then return false end
    local ok, f = pcall(io.open, configPath(name), "r")
    if not ok or not f then return false end
    local s = f:read("*a")
    f:close()
    deserialize(s or "")
    return true
end

-- default settings
local function resetConfig()
    local keepSlot, keepKey = settings.slot, settings.menuKey
    for k, v in pairs(DEFAULTS) do settings[k] = v end
    settings.pos = {}
    settings.slot, settings.menuKey = keepSlot, keepKey
end

-- which slots have a saved config
L.slotHas = {}
function L.slotSaved(n)
    if L.slotHas[n] == nil then
        local ok, f = pcall(io.open, configPath("slot" .. n), "r")
        L.slotHas[n] = (ok and f) and true or false
        if ok and f then f:close() end
    end
    return L.slotHas[n]
end
function L.slotNames()
    for n = 1, 5 do L.SLOTS[n] = "Slot " .. n .. (L.slotSaved(n) and "  (saved)" or "  (empty)") end
end

-- the state before the last load / reset
function L.backup()
    L.undo = serialize()
    pcall(saveConfig, "backup")
end
function L.restoreBackup()
    local s = L.undo
    if not s then
        local ok, f = pcall(io.open, configPath("backup"), "r")
        if ok and f then s = f:read("*a"); f:close() end
    end
    if not s or s == "" then return false end
    resetConfig()
    deserialize(s)
    return true
end


loadConfig("autosave")

---------------------------------------------------------------------------
-- 2. Themes, colours, gradients
---------------------------------------------------------------------------
local THEMES = {
    { name = "Destiny", accent = { 16, 185, 129 }, pal = {
        win = { 20, 21, 24 }, side = { 15, 16, 18 }, card = { 27, 28, 33 }, hover = { 33, 34, 41 },
        border = { 38, 39, 46 }, text = { 244, 244, 245 }, text2 = { 161, 161, 170 }, muted = { 113, 113, 122 },
        off = { 56, 58, 67 }, track = { 45, 47, 56 }, thumb = C_WHITE, pill = { 32, 33, 39 }, active = { 38, 40, 48 } } },
    { name = "Radiance", accent = { 124, 108, 255 }, pal = {
        win = { 16, 18, 42 }, side = { 12, 14, 34 }, card = { 21, 24, 54 }, hover = { 29, 33, 70 },
        border = { 52, 58, 112 }, text = { 232, 234, 255 }, text2 = { 172, 178, 222 }, muted = { 120, 126, 178 },
        off = { 50, 54, 98 }, track = { 40, 44, 88 }, thumb = C_WHITE, pill = { 26, 29, 64 }, active = { 86, 74, 190 } } },
    { name = "Silentium", accent = { 232, 69, 111 }, pal = {
        win = { 16, 16, 19 }, side = { 12, 12, 15 }, card = { 24, 24, 29 }, hover = { 32, 32, 38 },
        border = { 44, 44, 52 }, text = { 240, 240, 244 }, text2 = { 170, 170, 180 }, muted = { 112, 112, 122 },
        off = { 52, 52, 60 }, track = { 42, 42, 50 }, thumb = C_WHITE, pill = { 28, 28, 34 }, active = { 60, 26, 38 } } },
    { name = "Halloween", accent = { 255, 122, 24 }, pal = {
        win = { 17, 9, 24 }, side = { 11, 5, 17 }, card = { 30, 17, 40 }, hover = { 42, 24, 54 },
        border = { 70, 40, 84 }, text = { 252, 240, 228 }, text2 = { 196, 172, 176 }, muted = { 146, 118, 134 },
        off = { 74, 50, 74 }, track = { 60, 38, 68 }, thumb = { 255, 214, 150 }, pill = { 38, 22, 48 }, active = { 66, 34, 58 } } },
    { name = "Royal", accent = { 255, 92, 170 }, pal = {
        win = { 14, 9, 22 }, side = { 10, 6, 17 }, card = { 24, 15, 36 }, hover = { 34, 21, 50 },
        border = { 58, 34, 84 }, text = { 246, 236, 252 }, text2 = { 190, 168, 210 }, muted = { 132, 110, 156 },
        off = { 58, 40, 80 }, track = { 46, 30, 66 }, thumb = C_WHITE, pill = { 30, 19, 44 }, active = { 70, 30, 88 } } },
    { name = "Liquid glass", accent = { 110, 180, 255 }, glass = true, pal = {
        win = { 22, 28, 40 }, side = { 16, 21, 32 }, card = { 255, 255, 255 }, hover = { 70, 82, 106 },
        border = { 200, 214, 236 }, text = { 255, 255, 255 }, text2 = { 222, 228, 240 }, muted = { 178, 188, 206 },
        off = { 96, 108, 132 }, track = { 74, 86, 110 }, thumb = C_WHITE, pill = { 34, 42, 60 }, active = { 60, 96, 160 } } },
    { name = "Niko OneShot", accent = { 255, 205, 80 }, pal = {
        win = { 30, 16, 40 }, side = { 22, 11, 31 }, card = { 44, 24, 58 }, hover = { 58, 32, 74 },
        border = { 92, 52, 112 }, text = { 255, 241, 214 }, text2 = { 228, 192, 216 }, muted = { 162, 128, 172 },
        off = { 72, 44, 88 }, track = { 58, 36, 76 }, thumb = { 255, 238, 176 }, pill = { 38, 21, 50 }, active = { 98, 46, 92 } } },
    { name = "Moon", accent = { 150, 140, 255 }, pal = {
        win = { 16, 18, 32 }, side = { 12, 14, 26 }, card = { 22, 25, 42 }, hover = { 30, 34, 56 },
        border = { 44, 50, 82 }, text = { 234, 236, 252 }, text2 = { 172, 178, 216 }, muted = { 122, 128, 172 },
        off = { 48, 52, 86 }, track = { 40, 44, 74 }, thumb = C_WHITE, pill = { 26, 29, 50 }, active = { 46, 46, 96 } } },
}

L.ACCENTS = {
    { "Theme colour", nil }, { "Emerald", { 16, 185, 129 } }, { "Violet", { 124, 108, 255 } }, { "Rose", { 232, 69, 111 } },
    { "Orange", { 255, 122, 24 } }, { "Sky", { 56, 189, 248 } }, { "Gold", { 250, 204, 21 } },
}

-- colours you pick yourself are stored as hex text
L.hexCache = {}
function L.hex(s)
    if not s or s == "" then return nil end
    local c = L.hexCache[s]
    if c then return c end
    local r, g, b = s:match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    c = { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
    L.hexCache[s] = c
    return c
end
function L.toHex(c) return string.format("%02X%02X%02X", round(c[1]), round(c[2]), round(c[3])) end

-- the palette in use
L.PAL = {}
local T = THEMES[1].pal
function L.buildPalette()
    local base = (THEMES[settings.theme] or THEMES[1]).pal
    local P = L.PAL
    for k, v in pairs(base) do P[k] = v end
    local function over(key, field) local c = L.hex(settings[key]); if c then P[field] = c end end
    over("colWin", "win"); over("colSide", "side"); over("colCard", "card"); over("colText", "text")
    over("colText2", "text2"); over("colBorder", "border"); over("colSwitch", "off")
    local card = L.hex(settings.colCard)
    if card then
        P.hover = L.hexCache["h" .. settings.colCard] or { min(255, card[1] + 8), min(255, card[2] + 8), min(255, card[3] + 10) }
        L.hexCache["h" .. settings.colCard] = P.hover
        P.pill = L.hexCache["p" .. settings.colCard] or { min(255, card[1] + 5), min(255, card[2] + 5), min(255, card[3] + 6) }
        L.hexCache["p" .. settings.colCard] = P.pill
    end
    T = P
end

function L.isHW()
    return (THEMES[settings.theme] or THEMES[1]).name == "Halloween"
end

function L.isNiko()
    return (THEMES[settings.theme] or THEMES[1]).name == "Niko OneShot"
end

function L.glassA()
    return (THEMES[settings.theme] or THEMES[1]).glass and 125 or 255
end

local function accent()
    local own = L.hex(settings.colAccent)
    if own then return own end
    return L.ACCENTS[settings.accent] and L.ACCENTS[settings.accent][2] or THEMES[settings.theme].accent
end

-- animated gradient presets of the logo
L.LOGOS = { "Accent Flow", "Aurora", "Sunset", "Ocean", "Fire", "Rainbow", "Candy", "Mono", "Static" }
local STOPS = {
    [2] = { { 16, 185, 129 }, { 34, 211, 238 }, { 99, 102, 241 }, { 168, 85, 247 } },
    [3] = { { 251, 146, 60 }, { 244, 63, 94 }, { 168, 85, 247 } },
    [4] = { { 34, 211, 238 }, { 59, 130, 246 }, { 20, 184, 166 } },
    [5] = { { 250, 204, 21 }, { 249, 115, 22 }, { 239, 68, 68 } },
    [6] = { { 239, 68, 68 }, { 250, 204, 21 }, { 74, 222, 128 }, { 34, 211, 238 }, { 99, 102, 241 }, { 217, 70, 239 } },
    [7] = { { 244, 114, 182 }, { 125, 211, 252 }, { 134, 239, 172 } },
}
local dynStops = { C_WHITE, C_WHITE }
local function logoStops(idx)
    idx = idx or settings.logo
    if STOPS[idx] then return STOPS[idx] end
    if idx == 8 then dynStops[1], dynStops[2] = T.text, T.muted
    else dynStops[1], dynStops[2] = accent(), T.text end
    return dynStops
end

-- mixed colours come from a ring of 128 reused tables
local mixPool, mixAt = {}, 0
for i = 1, 128 do mixPool[i] = { 0, 0, 0 } end
local function mix(c1, c2, t)
    mixAt = mixAt % 128 + 1
    local o = mixPool[mixAt]
    o[1], o[2], o[3] = c1[1] + (c2[1] - c1[1]) * t, c1[2] + (c2[2] - c1[2]) * t, c1[3] + (c2[3] - c1[3]) * t
    return o
end

-- colour at position p along a list of stops
local function sampleStops(stops, p)
    local m = #stops
    p = p - floor(p)
    local q = p * m
    local k = floor(q)
    return mix(stops[k % m + 1], stops[(k + 1) % m + 1], q - k)
end

local RED, GOLD, SKY = { 244, 112, 124 }, { 250, 204, 21 }, { 56, 189, 248 }
local RD = { white = { 236, 236, 255 }, violet = { 158, 146, 255 }, dim = { 170, 174, 220 }, icon = { 150, 138, 255 },
             body = { 24, 26, 56 }, border = { 80, 86, 152 } }
local MC = { text = { 226, 228, 245 }, val = { 130, 170, 255 }, dim = { 150, 154, 186 }, glow = { 176, 182, 255 },
             body = { 26, 28, 48 }, border = { 178, 184, 236 } }
local SL = { body = { 16, 16, 19 }, line = { 44, 44, 52 }, text = { 240, 240, 244 }, dim = { 170, 170, 180 }, rose = { 232, 69, 111 } }

---------------------------------------------------------------------------
-- 3. Drawing helpers
---------------------------------------------------------------------------
local ALPHA = 1

local F = {
    ui    = draw.CreateFont("Segoe UI", 16, 500, FONTFLAG_ANTIALIAS),
    small = draw.CreateFont("Segoe UI", 14, 500, FONTFLAG_ANTIALIAS),
    tiny  = draw.CreateFont("Segoe UI", 12, 700, FONTFLAG_ANTIALIAS),
    bold  = draw.CreateFont("Segoe UI", 17, 700, FONTFLAG_ANTIALIAS),
    title = draw.CreateFont("Segoe UI", 22, 700, FONTFLAG_ANTIALIAS),
    icon  = draw.CreateFont("Segoe UI Symbol", 16, 400, FONTFLAG_ANTIALIAS),
    iconL = draw.CreateFont("Segoe UI Symbol", 22, 400, FONTFLAG_ANTIALIAS),
    logo  = draw.CreateFont("Segoe UI Black", 24, 900, FONTFLAG_ANTIALIAS),
    big   = draw.CreateFont("Segoe UI Black", 26, 900, FONTFLAG_ANTIALIAS),
    wm    = draw.CreateFont("Verdana", 14, 600, FONTFLAG_ANTIALIAS | FONTFLAG_OUTLINE),
    rd    = draw.CreateFont("Segoe UI", 16, 700, FONTFLAG_ANTIALIAS),
    dmg   = draw.CreateFont("Segoe UI Black", 22, 900, FONTFLAG_ANTIALIAS | FONTFLAG_OUTLINE),
    kaT   = draw.CreateFont("Segoe UI Black", 44, 900, FONTFLAG_ANTIALIAS),
    kaS   = draw.CreateFont("Segoe UI", 18, 700, FONTFLAG_ANTIALIAS),
}

-- draw.Color only takes whole numbers 0..255
-- draw.Color leaves ~224 bytes of garbage per call (the cause of the lag spikes), so it is only called when the
-- colour really changes. L.ccOk = false forces the next call (start of a frame, after a texture was made).
local function rawColor(r, g, b, al)
    if L.ccOk and r == L.cr and g == L.cg and b == L.cb and al == L.ca then return end
    L.cr, L.cg, L.cb, L.ca, L.ccOk = r, g, b, al, true
    draw.Color(r, g, b, al)
end
local function color(c, a)
    rawColor(clamp(round(c[1]), 0, 255), clamp(round(c[2]), 0, 255), clamp(round(c[3]), 0, 255), clamp(round((a or 255) * ALPHA), 1, 255))
end
-- making a texture makes lmaobox forget the colour ("Color not set" on the next draw): set it again
function L.recolor() if L.cr then L.ccOk = false; rawColor(L.cr, L.cg, L.cb, L.ca) end end

-- nothing to draw when it would be invisible anyway
local function hidden(a) return (a or 255) * ALPHA < 1 end

local function rect(x, y, w, h, c, a)
    if hidden(a) then return end
    color(c, a)
    draw.FilledRect(round(x), round(y), round(x + w), round(y + h))
end

local function inside(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

-- rounded shapes come from small smooth white pictures that are made once per size
local shapeTex = {}

local function pow2(n) local p = 2; while p < n do p = p * 2 end; return p end

-- size S x S picture
local function makeTex(key, S, alphaAt)
    local t = shapeTex[key]
    if t then return t end
    local px, n = {}, 0
    for py = 0, S - 1 do
        for pxx = 0, S - 1 do
            n = n + 1
            px[n] = string.char(255, 255, 255, round(clamp(alphaAt(pxx + 0.5, py + 0.5), 0, 1) * 255))
        end
    end
    t = { id = draw.CreateTextureRGBA(table.concat(px), S, S), S = S }
    L.recolor()
    shapeTex[key] = t
    return t
end

-- one picture per corner
local cornerCache = { [true] = {}, [false] = {} }
local function cornerTex(r, outline, which)
    local byR = cornerCache[outline][r]
    if byR and byR[which] then return byR[which] end
    if not byR then byR = {}; cornerCache[outline][r] = byR end
    local S = pow2(r)
    byR[which] = makeTex((outline and "o" or "f") .. r .. "_" .. which, S, function(x, y)
        if which == 2 or which == 4 then x = S - x end
        if which == 3 or which == 4 then y = S - y end
        if x > r or y > r then return 0 end
        local d = sqrt((r - x) ^ 2 + (r - y) ^ 2)
        if outline then return 1 - abs(d - (r - 0.5)) end
        return r - d + 0.5
    end)
    return byR[which]
end

local function corners(r, outline, x, y, w, h)
    local S = pow2(r)
    draw.TexturedRect(cornerTex(r, outline, 1).id, x, y, x + S, y + S)
    draw.TexturedRect(cornerTex(r, outline, 2).id, x + w - S, y, x + w, y + S)
    draw.TexturedRect(cornerTex(r, outline, 3).id, x, y + h - S, x + S, y + h)
    draw.TexturedRect(cornerTex(r, outline, 4).id, x + w - S, y + h - S, x + w, y + h)
end

-- whole circle with radius r in the middle of an S x S picture
local circleCache = {}
local function circleTex(r)
    r = min(r, 32)
    local t = circleCache[r]
    if t then return t, r end
    local S = pow2(2 * r + 2)
    t = makeTex("c" .. r, S, function(x, y)
        local d = sqrt((S / 2 - x) ^ 2 + (S / 2 - y) ^ 2)
        return r - d + 0.5
    end)
    circleCache[r] = t
    return t, r
end

-- rounded boxes as one ready-made picture
L.boxTex, L.boxCount, L.boxN, L.boxBudget, L.boxCountAt, L.boxMadeAt = {}, {}, 0, 1, 0, -99
L.boxQuad = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
L.boxRow = {}
L.T0 = string.char(255, 255, 255, 0)

-- the 256 possible pixels
L.PIX = {}
for a = 0, 255 do L.PIX[a] = string.char(255, 255, 255, a) end

-- builds the picture of a box
function L.makeBox(outline, w, h, r)
    local Sw, Sh = pow2(w), pow2(h)
    local PIX, sq = L.PIX, sqrt
    local rows, part = {}, L.boxRow
    local function cov(xc, yc)
        local dx, dy = xc - clamp(xc, r, w - r), yc - clamp(yc, r, h - r)
        local a
        if dx ~= 0 or dy ~= 0 then
            local d = sq(dx * dx + dy * dy)
            a = outline and (1 - abs((r - d) - 0.5)) or (r - d + 0.5)
        elseif outline then
            a = 1 - abs(min(xc, w - xc, yc, h - yc) - 0.5)
        else
            a = 1
        end
        a = (a < 0) and 0 or ((a > 1) and 1 or a)
        return PIX[floor(a * 255 + 0.5)]
    end
    local edge = max(r, 1)
    for py = 0, h - 1 do
        local yc = py + 0.5
        for i = 1, edge do part[i] = cov(i - 0.5, yc) end
        local left = table.concat(part, "", 1, edge)
        for i = 1, edge do part[i] = cov(w - edge + i - 0.5, yc) end
        local right = table.concat(part, "", 1, edge)
        local mid = string.rep(cov(w / 2, yc), w - 2 * edge)
        rows[#rows + 1] = left .. mid .. right .. string.rep(L.T0, Sw - w)
    end
    local pad = string.rep(L.T0, Sw)
    for _ = h, Sh - 1 do rows[#rows + 1] = pad end
    local ok, id = pcall(draw.CreateTextureRGBA, table.concat(rows), Sw, Sh)
    L.recolor()
    if not ok or not id then return false end
    return { id = id, U = w / Sw, V = h / Sh, Sw = Sw, Sh = Sh }
end

-- the picture for this box
function L.boxGet(outline, w, h, r)
    if w > 1024 or h > 256 or w * h > 40000 or r > 63 then return nil end
    local key = ((w * 512 + h) * 64 + r) * 2 + (outline and 1 or 0)
    local e = L.boxTex[key]
    if e ~= nil then return e or nil end
    local n = (L.boxCount[key] or 0) + 1
    L.boxCount[key] = n
    -- only sizes really on screen
    if n < 30 or L.boxBudget <= 0 or L.boxN >= 600 or now() - L.boxMadeAt < 0.25 then return nil end
    L.boxBudget = L.boxBudget - 1
    L.boxMadeAt = now()
    e = L.makeBox(outline, w, h, r)
    L.boxTex[key] = e
    L.boxN = L.boxN + 1
    return e or nil
end

function L.boxClear()
    for _, e in pairs(L.boxTex) do if e then pcall(draw.DeleteTexture, e.id) end end
    L.boxTex, L.boxN = {}, 0
end

-- called once per frame
function L.boxFrame()
    L.boxBudget = 1
    if now() - L.boxCountAt > 5 then L.boxCount, L.boxCountAt = {}, now() end
end

-- the picture is drawn at its full size: the box sits in its top-left corner and the rest is see-through,
-- so no corner list has to be handed over (TexturedPolygon with a table each call made a lot of garbage)
local function drawBox(e, x, y, w, h)
    draw.TexturedRect(e.id, x, y, x + e.Sw, y + e.Sh)
end

-- filled rounded rectangle
local function roundRect(x, y, w, h, r, c, a)
    x, y, w, h = round(x), round(y), round(w), round(h)
    if w <= 0 or h <= 0 or hidden(a) then return end
    r = min(round(r), floor(h / 2), floor(w / 2))
    color(c, a)
    if r < 1 then draw.FilledRect(x, y, x + w, y + h); return end
    local e = L.boxGet(false, w, h, r)
    color(c, a)                                                       -- (again: making a picture can reset it)
    if e then drawBox(e, x, y, w, h); return end
    draw.FilledRect(x + r, y, x + w - r, y + h)
    draw.FilledRect(x, y + r, x + r, y + h - r)
    draw.FilledRect(x + w - r, y + r, x + w, y + h - r)
    corners(r, false, x, y, w, h)
end

-- 1px rounded outline
local function roundRectLine(x, y, w, h, r, c, a)
    x, y, w, h = round(x), round(y), round(w), round(h)
    if w <= 1 or h <= 1 or hidden(a) then return end
    r = min(round(r), floor(h / 2), floor(w / 2))
    color(c, a)
    local e = L.boxGet(true, w, h, r)
    color(c, a)
    if e then drawBox(e, x, y, w, h); return end
    draw.FilledRect(x + r, y, x + w - r, y + 1)
    draw.FilledRect(x + r, y + h - 1, x + w - r, y + h)
    draw.FilledRect(x, y + r, x + 1, y + h - r)
    draw.FilledRect(x + w - 1, y + r, x + w, y + h - r)
    if r < 1 then return end
    corners(r, true, x, y, w, h)
end

-- filled circle
local function disc(cx, cy, r, c, a)
    r = round(r)
    if r <= 0 or hidden(a) then return end
    local t, tr = circleTex(r)
    color(c, a)                                                       -- (after: making the circle can reset it)
    local half = t.S / 2 * r / tr
    cx, cy = round(cx), round(cy)
    draw.TexturedRect(t.id, round(cx - half), round(cy - half), round(cx + half), round(cy + half))
end

local function ring(cx, cy, r, c, a, segments)
    if r < 1 or hidden(a) then return end
    color(c, a)
    draw.OutlinedCircle(round(cx), round(cy), round(r), segments or 48)
end

local function line(x1, y1, x2, y2, c, a)
    if hidden(a) then return end
    color(c, a)
    draw.Line(round(x1), round(y1), round(x2), round(y2))
end

-- filled polygon through a tiny white texture
local WHITE = draw.CreateTextureRGBA(string.rep(string.char(255), 16), 2, 2)
local function poly(pts, c, a)
    if hidden(a) then return end
    color(c, a)
    local v = {}
    for i = 1, #pts, 2 do v[#v + 1] = { pts[i], pts[i + 1], 0.5, 0.5 } end
    draw.TexturedPolygon(WHITE, v, true)
end

-- edge fades: side = "top" | "bottom" | "left" | "right"
local function edgeFade(side, size, c, a)
    local sw, sh = draw.GetScreenSize()
    size = round(size)
    a = clamp(round(a * ALPHA), 0, 255)
    if a <= 0 or size <= 0 then return end
    rawColor(clamp(round(c[1]), 0, 255), clamp(round(c[2]), 0, 255), clamp(round(c[3]), 0, 255), 255)
    if side == "top" then draw.FilledRectFade(0, 0, sw, size, a, 0, false)
    elseif side == "bottom" then draw.FilledRectFade(0, sh - size, sw, sh, 0, a, false)
    elseif side == "left" then draw.FilledRectFade(0, 0, size, sh, a, 0, true)
    else draw.FilledRectFade(sw - size, 0, sw, sh, 0, a, true) end
end

-- text is the most frequent thing drawn
L.curFont = nil
local function setFont(font)
    if font ~= L.curFont then draw.SetFont(font); L.curFont = font end
end
L.tsz, L.tszN = {}, 0
local function tsize(font, s)
    local byF = L.tsz[font]
    if not byF then byF = {}; L.tsz[font] = byF end
    local e = byF[s]
    if e then return e[1], e[2] end
    setFont(font)
    local w, h = draw.GetTextSize(s)
    L.tszN = L.tszN + 1
    if L.tszN > 12000 then L.tsz, L.tszN = {}, 0; byF = {}; L.tsz[font] = byF end
    byF[s] = { w, h }
    return w, h
end

local function textW(font, s)
    return (tsize(font, s))
end

-- text vertically centred in a box of height h
local function text(font, s, x, y, h, c, a)
    s = tostring(s)
    if hidden(a) then return end
    local _, th = tsize(font, s)
    setFont(font)
    color(c, a)
    draw.Text(round(x), round(y + (h - th) / 2), s)
end

local function textC(font, s, cx, y, h, c, a)
    text(font, s, cx - textW(font, s) / 2, y, h, c, a)
end

-- shorten a string until it fits
local fitCache, fitCount = {}, 0
local function fit(font, s, w)
    if type(s) ~= "string" then s = tostring(s) end
    w = round(w)
    local byFont = fitCache[font]
    if not byFont then byFont = {}; fitCache[font] = byFont end
    local byW = byFont[w]
    if not byW then byW = {}; byFont[w] = byW end
    local hit = byW[s]
    if hit then return hit end
    local r = s
    if textW(font, s) > w then
        while #r > 1 and textW(font, r .. "…") > w do r = r:sub(1, -2) end
        r = r .. "…"
    end
    fitCount = fitCount + 1
    if fitCount > 6000 then fitCache, fitCount = {}, 0 end
    byW[s] = r
    return r
end

-- smooth animation
local animValues = {}
local function anim(id, target, speed)
    local v = animValues[id] or target
    v = v + (target - v) * min(1, frameDt() * (speed or 12))
    if abs(target - v) < 0.002 then v = target end
    animValues[id] = v
    return v
end

local function easeOutBack(u)
    u = clamp(u, 0, 1)
    return 1 + 2.7 * (u - 1) ^ 3 + 1.7 * (u - 1) ^ 2
end

local function easeOut(u) u = clamp(u, 0, 1); return 1 - (1 - u) ^ 3 end

-- logo: every letter its own colour from the flowing gradient + soft shadow
local function logoWidth(word, font)
    font = font or F.logo
    local w = 0
    for i = 1, #word do w = w + textW(font, word:sub(i, i)) + 1 end
    return w - 1
end

local function drawLogo(word, x, y, font, preset)
    font = font or F.logo
    local n = #word
    local stops = logoStops(preset)
    local static = (preset or settings.logo) == 9
    for i = 1, n do
        local ch = word:sub(i, i)
        local c
        if static then c = mix(stops[1], stops[2], min(1, (i - 1) / max(1, n - 1) * 1.15))
        else c = sampleStops(stops, (i - 1) / n - now() * 0.32) end
        setFont(font)
        color(c, 55); draw.Text(round(x), round(y + 1), ch)
        color(c, 255); draw.Text(round(x), round(y), ch)
        x = x + textW(font, ch) + 1
    end
end

---------------------------------------------------------------------------
-- 4. Mouse, dragging
---------------------------------------------------------------------------
local menu = { open = false, cursor = false, openT = 0, x = nil, y = nil, w = 860, h = 620, page = 1,
               scroll = 0, scrollT = 0, contentH = 0, dragging = false, dx = 0, dy = 0 }
local dropdown = nil

local mouse = { x = 0, y = 0, click = false, held = false, used = false, wheel = 0 }
L.wasDown = {}
local function pressed(button)
    local down = input.IsButtonDown(button)
    local r = down and not L.wasDown[button]
    L.wasDown[button] = down
    return r
end

L.lastWheelTick = {}
local function wheel(button)
    local ok, p, tick = pcall(input.IsButtonPressed, button)
    if ok and p and tick ~= L.lastWheelTick[button] then
        L.lastWheelTick[button] = tick
        return true
    end
    return false
end

local function takeClick(x, y, w, h)
    if mouse.click and not mouse.used and inside(mouse.x, mouse.y, x, y, w, h) then
        mouse.used = true
        return true
    end
    return false
end

local function overMenu()
    return menu.openT > 0.3 and menu.x and inside(mouse.x, mouse.y, menu.x, menu.y, menu.w, menu.h)
end

-- anything on screen can be dragged while the menu is open
local drag = { id = nil, dx = 0, dy = 0 }
local function draggable(id, x, y, w, h)
    local p = settings.pos[id]
    if p then x, y = p[1], p[2] end
    local sw, sh = draw.GetScreenSize()
    x, y = clamp(x, 0, max(0, sw - w)), clamp(y, 0, max(0, sh - h))
    if menu.open and not drag.id and not dropdown and not overMenu() and takeClick(x, y, w, h) then
        drag.id, drag.dx, drag.dy = id, mouse.x - x, mouse.y - y
    end
    if drag.id == id then
        if mouse.held and menu.open then
            x = clamp(mouse.x - drag.dx, 0, max(0, sw - w))
            y = clamp(mouse.y - drag.dy, 0, max(0, sh - h))
            settings.pos[id] = { floor(x), floor(y) }
        else
            drag.id = nil
        end
        roundRectLine(x - 3, y - 3, w + 6, h + 6, 9, accent(), 220)
    end
    return round(x), round(y)
end

---------------------------------------------------------------------------
-- 5. Player info: Steam name + letter avatar
---------------------------------------------------------------------------
local nameCache, nameAt = nil, -99
local function steamName()
    if now() - nameAt > 5 or not nameCache then
        nameAt = now()
        local ok, sid = pcall(steam.GetSteamID)
        if ok and sid then
            local ok2, n = pcall(steam.GetPlayerName, sid)
            if ok2 and n and n ~= "" then nameCache = n end
        end
        if not nameCache then
            local lp = entities.GetLocalPlayer()
            nameCache = lp and lp:GetName() or nil
        end
    end
    return nameCache or "player"
end

-- the avatar: the first letter of your Steam name on a tile in the menu's gradient
local function drawAvatar(x, y, s, r)
    roundRect(x, y, s, s, r, T.card)
    -- a soft accent glow inside the tile
    roundRect(x + 4, y + 4, s - 8, s - 8, r - 3, accent(), 38)
    local letter = steamName():match("[%w]") or steamName():sub(1, 1)
    letter = letter:upper()
    local lw = textW(F.big, letter)
    drawLogo(letter, x + (s - lw) / 2, y + (s - 30) / 2, F.big)
    roundRectLine(x, y, s, s, r, T.border)
end

---------------------------------------------------------------------------
-- 6. Effects
---------------------------------------------------------------------------
-- 6a. notifications --------------------------------------------------------
L.NT_STYLES = { "Destiny", "Radiance", "Mercury", "Silentium", "Royal", "Liquid glass", "Moon", "OneShot" }
L.NT_POS = { "Top-Right", "Bottom-Right", "Top-Center", "Bottom-Center", "Top-Left" }
local notes = {}

local function notify(icon, title, body, col)
    if not settings.ntOn then return end
    table.insert(notes, 1, { icon = icon, title = title, body = body or "", col = col or accent(), t0 = now() })
    if #notes > 6 then table.remove(notes) end
end

-- 6b. sounds -----------------------------------
L.HIT_SOUNDS = {
    { "Off" }, { "Default", "ui/hitsound.wav" }, { "Electro", "ui/hitsound_electro1.wav" }, { "Notes", "ui/hitsound_notes1.wav" },
    { "Percussion", "ui/hitsound_percussion1.wav" }, { "Retro", "ui/hitsound_retro1.wav" }, { "Space", "ui/hitsound_space.wav" },
    { "Beepo", "ui/hitsound_beepo.wav" }, { "Vortex", "ui/hitsound_vortex1.wav" }, { "Squasher", "ui/hitsound_squasher.wav" },
}
L.KILL_SOUNDS = {
    { "Off" }, { "Default", "ui/killsound.wav" }, { "Electro", "ui/killsound_electro.wav" }, { "Notes", "ui/killsound_note.wav" },
    { "Percussion", "ui/killsound_percussion.wav" }, { "Retro", "ui/killsound_retro.wav" }, { "Space", "ui/killsound_space.wav" },
    { "Beepo", "ui/killsound_beepo.wav" }, { "Vortex", "ui/killsound_vortex.wav" }, { "Squasher", "ui/killsound_squasher.wav" },
}
local function playFrom(list, idx)
    local s = list[idx]
    if s and s[2] then pcall(engine.PlaySound, s[2]) end
end

-- 6c. damage numbers -------------------------------------------------------
function L.originOf(e) return e:GetAbsOrigin() end
L.DMG_STYLES = { "Classic", "Radiance", "Mercury" }
local dmgs = {}

local function addDamage(victim, amount, crit)
    if not settings.dmgOn then return end
    local idx = victim:GetIndex()
    for _, d in ipairs(dmgs) do
        if d.idx == idx and now() - d.last < 0.45 then
            d.amt, d.last, d.t0, d.crit = d.amt + amount, now(), now(), d.crit or crit
            return
        end
    end
    dmgs[#dmgs + 1] = { idx = idx, ent = victim, amt = amount, crit = crit, t0 = now(), last = now(), ox = math.random(-18, 18) }
end

-- 6d. vignette ----------------------
L.VIG_STYLES = { "Glow", "Pulse", "Scanlines", "Glitch", "Frost", "Hard border", "Shockwave", "Chromatic split",
                 "Radar sweep", "Heartbeat", "Lightning", "Closing in", "Embers" }
L.VIG_COLORS = { "Accent", "Red", "White", "Custom colour", "Accent Flow", "Aurora", "Sunset", "Ocean", "Fire",
                 "Rainbow", "Candy", "Mono" }
L.FX_EXTRA = { "Off", "Random (new every time)", "Hit marker", "Blood splatter", "Slash", "Shatter", "Speed lines",
               "Shockwave", "Neon frame" }

local function vigTrigger(kill) L.hitEffects(kill) end

-- 6e. kill announcer --------------------------------------------------------
L.KA_STYLES = { "Neon", "Classic" }
L.KA_NAMES = { "KILL", "DOUBLE KILL", "TRIPLE KILL", "MULTI KILL", "MEGA KILL", "ULTRA KILL", "MONSTER KILL", "RAMPAGE", "UNSTOPPABLE", "GODLIKE" }
local ka = { t0 = -99, tier = 1, streak = 0, sub = "" }

local function announce(tier, streak, sub)
    if not settings.kaOn then return end
    ka.t0, ka.tier, ka.streak, ka.sub = now(), tier, streak, sub or ""
end

-- 6f. waifu speech bubbles --------------------------------------------------
L.LINES = {
    kill      = { "Nice shot!", "Another one~", "Too easy!", "Keep going!", "You're on fire!", "Wow, clean!" },
    killClass = { "That %c didn't stand a chance!", "Bye bye, %c~", "%c down!", "One less %c to worry about!",
                  "Sit down, %c!", "The %c never saw it coming~" },
    killWeap  = { "Clean kill with the %w!", "Your %w is on fire today~", "That %w hits hard!", "%w diff~" },
    headshot  = { "HEADSHOT! Right between the eyes~", "Boom, headshot!", "What aim!" },
    backstab  = { "Sneaky sneaky~", "Right in the back!", "Nice stab!" },
    streak    = { "Unstoppable!!", "Look at you go!", "Nobody can stop you~", "That's my player!" },
    death     = { "Ouch...", "You'll get them next time!", "Don't give up!", "Revenge time?", "Hey, that was close!" },
    deathBy   = { "That %c got you...", "Watch out for that %c!", "Get that %c back!", "Ugh, that %c again..." },
    idle      = { "Stay DESTINY~", "Having fun?", "I'm watching you play!", "Let's win this one!", "Hehe~" },
}
local bubble = { text = nil, t0 = -99 }
-- say a line of this kind
local function compSay(kind, class, weapon)
    if not settings.compOn or not settings.compBubbles then return end
    local lines = (settings.compChar == 1 and L.PLINES) or L.LINES
    local list = lines[kind] or L.LINES[kind]
    if not list then return end
    local s = list[math.random(#list)]
    if (s:find("%%c") and not class) or (s:find("%%w") and not weapon) then
        list = lines.kill
        s = list[math.random(#list)]
    end
    s = s:gsub("%%c", class or ""):gsub("%%w", weapon or "")
    bubble.text, bubble.t0, bubble.dur = s, now(), 3.2
end

---------------------------------------------------------------------------
-- 6g. Auto-update: checks the GitHub repo for a newer destiny.lua
---------------------------------------------------------------------------
-- settings page
local UPDATE_URL = "https://raw.githubusercontent.com/eintoaster/Destiny-Lua-/refs/heads/main/destiny.lua"
local UPDATE_DELAY = 3

local updater = { checked = false, running = false, startAt = now() + UPDATE_DELAY, path = nil }
-- which build this file is; the note in destiny_files says which build and commit was installed last
L.BUILD = "202611111904"

-- the full ABSOLUTE path to this very file
local function isAbs(p) return type(p) == "string" and (p:match("^%a:[\\/]") ~= nil or p:match("^[\\/][\\/]") ~= nil) end
local function fileExists(p)
    local ok, f = pcall(io.open, p, "rb")
    if ok and f then f:close(); return true end
    return false
end
pcall(function()
    local cands, base = {}, nil
    local ok2, name = pcall(GetScriptName)
    if ok2 and name and tostring(name) ~= "" then cands[#cands + 1] = tostring(name) end
    local ok, info = pcall(debug.getinfo, 1, "S")
    local src = ok and info and info.source or ""
    if #src < 300 and src:sub(1, 1) == "@" then cands[#cands + 1] = src:sub(2) end
    local la = os.getenv and os.getenv("LOCALAPPDATA")
    for _, c in ipairs(cands) do
        base = base or c:match("([^\\/]+)$")
        if isAbs(c) and fileExists(c) then updater.path = c; return end
    end
    base = (base and base:lower():match("%.lua$")) and base or "destiny.lua"
    if la then
        for _, nm in ipairs({ base, "destiny.lua" }) do
            local c = la .. "\\lua\\" .. nm
            if fileExists(c) then updater.path = c; return end
        end
        updater.path = la .. "\\lua\\" .. base
    end
end)

-- lmaobox's ASYNC downloads fail above ~20 KB with "WinINet Error Code
-- the commits feed isn't rate limited like api.github.com (60 checks an hour)
local function latestSha()
    local ok, feed = pcall(http.Get, "https://github.com/eintoaster/Destiny-Lua-/commits/main.atom")
    local sha = ok and type(feed) == "string" and feed:match("Commit/(%x+)")
    if sha and #sha == 40 then return sha end
    local okA, api = pcall(http.Get, "https://api.github.com/repos/eintoaster/Destiny-Lua-/commits/main")
    sha = okA and type(api) == "string" and api:match('"sha"%s*:%s*"(%x+)"')
    if sha then return sha end
    if type(api) == "string" and api:find("rate limit", 1, true) then return nil, "GitHub is busy, try again later" end
    return nil, "GitHub didn't answer"
end

local function updaterCheck(auto)
    if updater.running then return end
    if not http then if not auto then notify("✖", "Can't check for updates", "lmaobox blocks downloads (http)", RED) end; return end
    if not io or not updater.path or updater.path == "" then
        if not auto then notify("✖", "Can't check for updates", "the script's own file path is unknown", RED) end
        return
    end
    updater.running = true
    local sha, why = latestSha()
    if not sha then
        updater.running = false
        if not auto then notify("✖", "Can't check for updates", why, RED) end
        return
    end
    -- the note only counts when it was written for the file that is running now: an older destiny.lua
    -- started by hand has another build number and gets updated
    local note = nil
    local okI, fi = pcall(io.open, "destiny_files/destiny_installed.txt", "r")
    if okI and fi then note = fi:read("*a") or ""; fi:close() end
    local noteBuild, noteSha = (note or ""):match("^b(%d+) (%x+)")
    if noteSha == sha and noteBuild == L.BUILD then
        updater.running = false
        if not auto then notify("✔", "Destiny is up to date", "version " .. sha:sub(1, 7), accent()) end
        return
    end
    local ok, remote = pcall(http.Get, "https://raw.githubusercontent.com/eintoaster/Destiny-Lua-/" .. sha .. "/destiny.lua")
    updater.running = false
    if not ok then
        notify("✖", "Can't check for updates", tostring(remote), RED)
        return
    end
    if type(remote) ~= "string" or #remote < 10000 or remote:sub(1, 5) == "ERROR" then
        notify("✖", "Update check failed", tostring(remote):sub(1, 60), RED)
        return
    end
    local newBuild = remote:match('L%.BUILD = "(%d+)"') or "0"
    local function saveNote()
        pcall(filesystem.CreateDirectory, "destiny_files")
        local okS, fs = pcall(io.open, "destiny_files/destiny_installed.txt", "w")
        if okS and fs then fs:write("b" .. newBuild .. " " .. sha); fs:close() end
    end
    -- first run of a copy that is already the newest: nothing to download, just remember it
    if (not note or note == "") and newBuild == L.BUILD and L.BUILD ~= "0" then
        saveNote()
        if not auto then notify("✔", "Destiny is up to date", "version " .. sha:sub(1, 7), accent()) end
        return
    end
    -- write the download to a temp file
    local path = updater.path
    -- lmaobox only lets scripts CREATE files inside the TF2 folder
    pcall(filesystem.CreateDirectory, "destiny_files")
    local tmp, old = "destiny_files/destiny_update.tmp", path .. ".old"
    local function fail(why)
        print("[destiny] update save failed for " .. tostring(path) .. " -> " .. tostring(why))
        local short = tostring(why):gsub("[%a]:[\\/][^%s]*[\\/]", ""):sub(1, 90)
        notify("✖", "Update found but couldn't be saved", short, RED)
    end
    local ok, wf, werr = pcall(io.open, tmp, "wb")
    if not ok or not wf then return fail("can't create temp file: " .. tostring(ok and werr or wf)) end
    local okw = pcall(wf.write, wf, remote)
    wf:close()
    local okr, rf = pcall(io.open, tmp, "rb")
    local back = (okr and rf) and rf:read("*a") or nil
    if okr and rf then rf:close() end
    if not okw or back ~= remote then
        pcall(os.remove, tmp)
        return fail(".tmp written incorrectly")
    end
    pcall(os.remove, old)
    local o1, r1, e1 = pcall(os.rename, path, old)
    if not o1 or not r1 then
        pcall(os.remove, tmp)
        return fail("can't move old file: " .. tostring(o1 and e1 or r1))
    end
    local o2, r2, e2 = pcall(os.rename, tmp, path)
    if not o2 or not r2 then
        pcall(os.rename, old, path)
        pcall(os.remove, tmp)
        return fail("can't move new file into lua folder (other drive?): " .. tostring(o2 and e2 or r2))
    end
    pcall(os.remove, old)
    updater.path = path
    saveNote()
    notify("⚡", "Destiny was updated (" .. sha:sub(1, 7) .. ")", "Please restart destiny.lua to load it", GOLD)
    print("[destiny] updated: " .. tostring(path))
end

---------------------------------------------------------------------------
-- 7. Game events: kills, deaths, assists, hits
---------------------------------------------------------------------------
local me = { streak = 0, tier = 0, lastKill = -99 }

local function myUserID()
    local lp = entities.GetLocalPlayer()
    if not lp then return nil end
    local info = client.GetPlayerInfo(lp:GetIndex())
    return info and info.UserID
end

local function nameOf(uid)
    local ok, n = pcall(client.GetPlayerNameByUserID, uid)
    return (ok and n and n ~= "") and n or "someone"
end

-- the class of a player
L.CLASSES = { "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer" }
function L.classOf(uid)
    local ent = entities.GetByUserID(uid)
    if not ent then return nil end
    local ok, c = pcall(ent.GetPropInt, ent, "m_PlayerClass", "m_iClass")
    return ok and L.CLASSES[c] or nil
end

-- the "weapon" text of a kill event made readable
L.WEAPONS = {
    tf_projectile_rocket = "Rocket Launcher", tf_projectile_pipe = "Grenade Launcher", tf_projectile_pipe_remote = "Stickybomb Launcher",
    tf_projectile_arrow = "Huntsman", tf_projectile_flare = "Flare Gun", tf_projectile_syringe = "Syringe Gun",
    sniperrifle = "Sniper Rifle", minigun = "Minigun", flamethrower = "Flame Thrower", scattergun = "Scattergun",
    knife = "Knife", revolver = "Revolver", smg = "SMG", pistol = "Pistol", pistol_scout = "Pistol", shotgun_soldier = "Shotgun",
    shotgun_pyro = "Shotgun", shotgun_hwg = "Shotgun", shotgun_primary = "Shotgun", syringegun_medic = "Syringe Gun",
    bonesaw = "Bonesaw", wrench = "Wrench", obj_sentrygun = "Sentry Gun", obj_sentrygun2 = "Sentry Gun",
    obj_sentrygun3 = "Sentry Gun", obj_minisentry = "Mini-Sentry", fists = "Fists", bat = "Bat", bottle = "Bottle",
    fireaxe = "Fire Axe", shovel = "Shovel", club = "Kukri", sword = "Eyelander", deflect_rocket = "Reflected Rocket",
    deflect_promode = "Reflected Grenade", deflect_sticky = "Reflected Sticky", deflect_arrow = "Reflected Arrow",
    telefrag = "Telefrag", taunt_scout = "Home Run", taunt_heavy = "Showdown", taunt_pyro = "Hadouken",
    taunt_spy = "Fencing", taunt_sniper = "Skewer", taunt_soldier = "Kamikaze", taunt_demoman = "Decapitation",
    taunt_medic = "Spinal Tap", taunt_engineer = "Organ Grinder",
}
function L.weaponName(w)
    if not w or w == "" or w == "world" or w == "player" then return nil end
    local known = L.WEAPONS[w]
    if known then return known end
    local s = w:gsub("^tf_projectile_", ""):gsub("^tf_weapon_", ""):gsub("_", " ")
    return (s:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

-- "Heavy  •  Minigun  •  Headshot"
local function joinParts(a, b, c)
    local out = {}
    if a then out[#out + 1] = a end
    if b then out[#out + 1] = b end
    if c then out[#out + 1] = c end
    return #out > 0 and table.concat(out, "  •  ") or nil
end

L.STREAK_STEPS = { [3] = true, [5] = true, [10] = true, [15] = true, [20] = true, [25] = true, [30] = true }

local function onKill(victimName, class, weapon, custom, flags)
    me.streak = me.streak + 1
    if now() - me.lastKill <= settings.kaWindow then me.tier = me.tier + 1 else me.tier = 1 end
    me.lastKill = now()
    local how = (custom == 1) and "Headshot" or ((custom == 2) and "Backstab" or nil)

    if settings.ntKills then notify("☠", "You killed " .. victimName, joinParts(class, weapon, how), accent()) end
    if L.STREAK_STEPS[me.streak] and settings.ntStreaks then
        notify("⚡", "Killstreak " .. me.streak, "Keep it going!", GOLD)
        compSay("streak")
    elseif custom == 1 then compSay("headshot")
    elseif custom == 2 then compSay("backstab")
    else
        local r = math.random()
        if class and r < 0.45 then compSay("killClass", class)
        elseif weapon and r < 0.75 then compSay("killWeap", nil, weapon)
        else compSay("kill") end
    end
    local sub = joinParts(class, how)
    announce(me.tier, me.streak, victimName .. (sub and ("  •  " .. sub) or ""))
    vigTrigger(true)
    if settings.kaOn and settings.kaSound then playFrom(L.KILL_SOUNDS, max(2, settings.killSound)) else playFrom(L.KILL_SOUNDS, settings.killSound) end
    L.paimon.onKill()
    L.trackKill(victimName, weapon, how, flags)
end

local function onDeath(killerName, class, weapon, suicide, flags)
    local lost = me.streak
    me.streak, me.tier = 0, 0
    if settings.ntDeaths then
        local body = joinParts((not suicide) and class or nil, (not suicide) and weapon or nil,
                               lost >= 3 and ("streak of " .. lost .. " ended") or nil)
        notify("✝", suicide and "You died" or ("Killed by " .. killerName), body, RED)
    end
    if class and not suicide and math.random() < 0.6 then compSay("deathBy", class) else compSay("death") end
    L.trackDeath(killerName, weapon, suicide, lost, flags)
end

local function onGameEvent(e)
    local name = e:GetName()
    if name == "game_newmap" or name == "server_spawn" or name == "client_beginconnect" or name == "client_connected" then
        L.sky.rushUntil = now() + 30
        L.sky.enforce()
        return
    end
    if name == "teamplay_round_start" then L.roundStart(); return end
    if name == "teamplay_round_win" then
        if settings.rsOn then L.roundEnd(e:GetInt("team") or 0) end
        return
    end
    if name ~= "player_death" and name ~= "player_hurt" then return end
    local mine = myUserID()
    if not mine then return end
    local victim, attacker = e:GetInt("userid"), e:GetInt("attacker")

    if name == "player_death" then
        local weapon = L.weaponName(e:GetString("weapon"))
        if attacker == mine and victim ~= mine then
            onKill(nameOf(victim), L.classOf(victim), weapon, e:GetInt("customkill"), e:GetInt("death_flags") or 0)
            L.ptSpawn(entities.GetByUserID(victim), true)
            L.hmHit(false, true)
            L.killCard(nameOf(victim), L.classOf(victim), weapon, e:GetInt("customkill"), entities.GetByUserID(victim))
            L.pet.react(L.STREAK_STEPS[me.streak] and "spark" or "heart")
        elseif victim == mine then
            onDeath(nameOf(attacker), L.classOf(attacker), weapon, attacker == mine or attacker == 0, e:GetInt("death_flags") or 0)
            local suicide = attacker == mine or attacker == 0
            L.deadInfo = { t0 = now(), line = suicide and "You died" or
                           ("Killed by " .. nameOf(attacker) .. ((joinParts(L.classOf(attacker), weapon) and ("  •  " .. joinParts(L.classOf(attacker), weapon))) or "")) }
            L.pet.react("rain")
        elseif e:GetInt("assister") == mine then
            if settings.ntAssists then notify("✚", "Assist on " .. nameOf(victim), joinParts(L.classOf(victim), weapon), SKY) end
            L.trackAssist(nameOf(victim))
        end
    elseif attacker == mine and victim ~= mine then
        local ent = entities.GetByUserID(victim)
        local crit = e:GetInt("crit") == 1
        if ent then addDamage(ent, e:GetInt("damageamount"), crit); L.ptSpawn(ent, false) end
        L.hmHit(e:GetInt("custom") == 1, false)
        L.paimon.hitLog(nameOf(victim), L.classOf(victim), e:GetInt("damageamount"), e:GetInt("health"), crit)
        vigTrigger(false)
        playFrom(L.HIT_SOUNDS, settings.hitSound)
        L.trackHit(e:GetInt("damageamount") or 0)
    end
end

---------------------------------------------------------------------------
-- 8. Overlays
---------------------------------------------------------------------------
-- 8a. watermark -------------------------------------------------------------
L.WM_STYLES = { "Classic", "Radiance", "Mercury", "Silentium", "Royal", "Liquid glass", "Moon", "OneShot" }
local fps, fpsAt = 0, 0

local function mapName()
    local map = engine.GetMapName()
    if not map or map == "" then return nil end
    return map:match("([^/\\]+)%.bsp$") or map
end

-- the pieces the watermark shows
local function wmParts()
    local p = { { "☺", steamName() } }
    if settings.wmFps then p[#p + 1] = { "↗", tostring(fps), "Fps" } end
    local m = settings.wmMap and mapName()
    if m then p[#p + 1] = { "◉", m } end
    if settings.wmTime and os and os.date then p[#p + 1] = { "◷", os.date("%H:%M:%S") } end
    return p
end

-- radiance chip
local function chipW(icon, parts)
    local w = 18 + (icon and 18 or 0)
    for i, p in ipairs(parts) do w = w + textW(F.rd, tostring(p[1])) + (i > 1 and 4 or 0) end
    return w
end
local function chip(x, y, icon, parts, h)
    h = h or 24
    local w = chipW(icon, parts)
    roundRect(x, y + 2, w, h, 7, C_BLACK, 60)
    roundRect(x, y, w, h, 7, RD.body, 228)
    roundRectLine(x, y, w, h, 7, RD.border, 170)
    local cx = x + 9
    if icon then
        local iw = textW(F.icon, icon)
        text(F.icon, icon, cx - 2 + (20 - iw) / 2, y, h, RD.icon)
        cx = cx + 18
    end
    for _, p in ipairs(parts) do
        text(F.rd, p[1], cx, y, h, p[2])
        cx = cx + textW(F.rd, tostring(p[1])) + 4
    end
    return w
end

local function mercuryBox(x, y, w, h, r)
    for i = 1, 4 do
        local e = i * 1.6
        roundRectLine(x - e, y - e, w + 2 * e, h + 2 * e, r + e, MC.glow, 50 - i * 11)
    end
    roundRect(x, y, w, h, r, MC.body, 205)
    roundRectLine(x, y, w, h, r, MC.border, 175)
end

-- the watermark's pieces are rebuilt 4 times a second
local wmCache = { at = -99 }

local function drawWatermark()
    if now() - fpsAt > 0.5 then fps, fpsAt = floor(1 / frameDt()), now() end
    if now() - wmCache.at > 0.25 then
        wmCache.at, wmCache.parts, wmCache.chips, wmCache.items, wmCache.text = now(), wmParts(), nil, nil, nil
    end
    local parts = wmCache.parts
    local sw = draw.GetScreenSize()
    local style = settings.wmStyle

    if style == 2 then
        local chips = wmCache.chips
        if not chips then
            chips = { { "✦", { { "DESTINY", RD.violet } } } }
            for _, p in ipairs(parts) do
                local t = { { p[2], RD.white } }
                if p[3] then t[2] = { p[3], RD.dim } end
                chips[#chips + 1] = { p[1], t }
            end
            local total = -5
            for _, c in ipairs(chips) do total = total + chipW(c[1], c[2]) + 5 end
            chips.total = total
            wmCache.chips = chips
        end
        local total = chips.total
        local x, y = draggable("wm", (sw - total) / 2, 12, total, 26)
        for _, c in ipairs(chips) do x = x + chip(x, y, c[1], c[2]) + 5 end

    elseif style == 3 then
        local items = { { "DESTINY", nil } }
        for _, p in ipairs(parts) do items[#items + 1] = { tostring(p[2]), p[3] } end
        local w = 24
        for i, it in ipairs(items) do
            w = w + textW(F.rd, it[1]) + (it[2] and (textW(F.small, it[2]) + 4) or 0) + (i > 1 and 18 or 0)
        end
        local x, y = draggable("wm", (sw - w) / 2, 12, w, 28)
        mercuryBox(x, y, w, 28, 9)
        local cx = x + 12
        for i, it in ipairs(items) do
            if i > 1 then cx = cx + 18 end
            text(F.rd, it[1], cx, y, 28, i == 1 and MC.text or MC.val)
            cx = cx + textW(F.rd, it[1])
            if it[2] then text(F.small, it[2], cx + 4, y, 28, MC.dim); cx = cx + 4 + textW(F.small, it[2]) end
        end

    elseif style == 4 then
        local items = {}
        for _, p in ipairs(parts) do items[#items + 1] = tostring(p[2]) .. (p[3] and (" " .. p[3]) or "") end
        local lw = logoWidth("DESTINY", F.rd)
        local w = 16 + lw
        for _, s in ipairs(items) do w = w + 25 + textW(F.small, s) end
        local x, y = draggable("wm", (sw - w) / 2, 12, w, 30)
        roundRect(x, y + 2, w, 30, 8, C_BLACK, 70)
        roundRect(x, y, w, 30, 8, SL.body, 235)
        roundRectLine(x, y, w, 30, 8, SL.line)
        rect(x + 10, y + 28, w - 20, 1, SL.rose, 160)
        setFont(F.rd)
        drawLogo("DESTINY", x + 8, y + 5, F.rd)
        local cx = x + 8 + lw
        for _, s in ipairs(items) do
            rect(cx + 12, y + 8, 1, 14, SL.line)
            text(F.small, s, cx + 25, y, 30, SL.dim)
            cx = cx + 25 + textW(F.small, s)
        end

    elseif style >= 5 then
        local st = style + 3
        local p = L.palFor(st, 1)
        local items = wmCache.items
        if not items then
            items = {}
            for _, q in ipairs(parts) do items[#items + 1] = tostring(q[2]) .. (q[3] and (" " .. q[3]) or "") end
            wmCache.items = items
        end
        local w = 28 + textW(F.rd, "DESTINY")
        for _, it in ipairs(items) do w = w + 25 + textW(F.small, it) end
        w = floor((w + 7) / 8) * 8
        local x, y = draggable("wm", (sw - w) / 2, 12, w, 30)
        L.panelBg(st, x, y, w, 30, nil, 1, 1)
        text(F.rd, "DESTINY", x + 14, y, 30, st == 8 and L.RY.title or p.c)
        local cx = x + 14 + textW(F.rd, "DESTINY")
        for _, it in ipairs(items) do
            rect(cx + 12, y + 9, 1, 12, p.dim, 120)
            text(F.small, it, cx + 25, y, 30, p.txt)
            cx = cx + 25 + textW(F.small, it)
        end

    else
        local list = { "DESTINY" }
        for _, p in ipairs(parts) do list[#list + 1] = tostring(p[2]) .. (p[3] and (" " .. p[3]:lower()) or "") end
        local s = table.concat(list, "  |  ")
        setFont(F.wm)
        local tw, th = tsize(F.wm, s)
        local w, h = tw + 12, th + 12
        local x, y = draggable("wm", 10, 10, w, h)
        rect(x, y, w, h, { 20, 20, 24 }, 220)
        rect(x, y, w, 2, accent())
        text(F.wm, s, x + 6, y + 1, h, C_WHITE)
    end
end

-- 8b. lmaobox options for the HUD: { shown name, lmaobox option name, its key option, icon } ---------------
L.FEATURES = {
    { "Aimbot", "aim bot", "aim key", "◎" }, { "Triggerbot", "trigger bot", "trigger key", "⌖" },
    { "Auto backstab", "auto backstab", nil, "✦" }, { "Auto detonate", "auto detonate", nil, "✸" },
    { "Auto airblast", "auto airblast", nil, "≋" }, { "Bunny hop", "bunny hop", nil, "⇡" },
    { "Anti aim", "anti aim", nil, "↻" }, { "Fake lag", "fake lag", nil, "⌛" },
    { "Thirdperson", "thirdperson", "thirdperson key", "◐" }, { "ESP", "players", nil, "◉" },
    { "Chams", "chams", nil, "◆" }, { "Glow", "glow", nil, "✧" }, { "Radar", "radar", nil, "⊕" },
}
local featOn, featPrev, featAt = {}, nil, -99
L.featKeys = {}

local function isOn(v)
    if type(v) == "number" then return v ~= 0 end
    if type(v) == "boolean" then return v end
    if type(v) == "string" then local l = v:lower(); return l ~= "" and l ~= "none" and l ~= "off" and l ~= "0" end
    return false
end

-- reads one lmaobox option
L.featKnown = {}
function L.guiValue(name)
    if not name or L.featKnown[name] == false then return nil end
    local ok, v = pcall(gui.GetValue, name)
    if ok and v ~= nil then L.featKnown[name] = true; return v end
    L.featKnown[name] = false
    return nil
end

-- asks lmaobox about ONE option per frame
L.featTurn, L.featSeen = 0, {}
local function pollFeatures()
    if not settings.flOn and not settings.ntFeatures then L.featSeen = {}; return end
    local list = L.FEATURES
    L.featTurn = L.featTurn % #list + 1
    local f = list[L.featTurn]
    local v = L.guiValue(f[2])
    local on = nil
    if v ~= nil then on = isOn(v) end
    local before = featOn[f[1]]
    featOn[f[1]] = on
    if f[3] and settings.flKeys then
        local k = L.guiValue(f[3])
        L.featKeys[f[1]] = (type(k) == "number" and k > 0) and L.keyName(k) or (type(k) == "string" and k ~= "" and k or nil)
    end
    -- status popup like the macro's ON/OFF toasts
    if L.featSeen[f[1]] and settings.ntFeatures and before ~= nil and on ~= nil and before ~= on then
        notify(on and "✔" or "✖", f[1], on and "ON" or "OFF", on and accent() or RED)
    end
    L.featSeen[f[1]] = true
end

-- 8c. input monitor -----------------------------------------------------------
L.IM_STYLES = { "Destiny", "Radiance", "Mercury", "Silentium", "Royal", "Liquid glass", "Moon", "OneShot" }

local function drawInputMonitor()
    local sw, sh = draw.GetScreenSize()
    local style = settings.imStyle
    local K, G = 34, 4
    local head = (style == 3 or style == 4) and 30 or 0
    local w = K * 3 + G * 2 + 24
    local h = 12 + head + (K + G) * 4 + 12
    local x, y = draggable("im", 14, sh / 2 - h / 2, w, h)
    local acc = accent()
    local bg = settings.imBg
    local t = now()

    -- the panel behind the keys
    if style == 2 then
        if bg then
            roundRect(x, y + 3, w, h, 12, C_BLACK, 60)
            roundRect(x, y, w, h, 12, RD.body, 200)
            roundRectLine(x, y, w, h, 12, RD.border, 170)
        end
    elseif style == 3 then
        if bg then mercuryBox(x, y, w, h, 10) end
        local tw = textW(F.rd, "inputs")
        text(F.icon, "✦", x + (w - tw - 18) / 2, y + 4, 22, MC.val)
        text(F.rd, "inputs", x + (w - tw - 18) / 2 + 18, y + 4, 22, MC.text)
        rect(x + 8, y + 29, w - 16, 1, MC.border, 150)
    elseif style == 4 then
        if bg then
            for i = 1, 4 do
                local e = i * 1.7
                roundRectLine(x - e, y - e, w + 2 * e, h + 2 * e, 10 + e, acc, 46 - i * 10)
            end
            roundRect(x, y, w, h, 10, L.SLBG, 232)
            roundRectLine(x, y, w, h, 10, C_WHITE, 26)
            rect(x + 10, y, w - 20, 1, acc, 160)
        end
        text(F.script, "inputs", x + 12, y + 2, 28, mix(acc, C_WHITE, 0.2))
    elseif style >= 5 then
        L.palFor(style + 3, 1)
        if bg then L.panelBg(style + 3, x, y, w, h, nil, 1, 1) end
    else
        if bg then
            roundRect(x, y + 3, w, h, 12, C_BLACK, 70)
            roundRect(x, y, w, h, 12, T.card, 230)
            roundRectLine(x, y, w, h, 12, T.border)
        end
    end

    -- one key in the chosen look
    local function key(id, label, kx, ky, kw, kh, button)
        local down = input.IsButtonDown(button)
        local was = L.imDown[id]
        if down and not was then L.imPress[id] = t end
        L.imDown[id] = down
        local tt = anim("im" .. id, down and 1 or 0, 22)
        local fl = t - (L.imPress[id] or -9)

        if style == 2 then
            local pop = (fl < 0.3) and 2 * sin(fl / 0.3 * pi) or 0
            local px, py, pw, ph = kx - pop, ky - pop, kw + 2 * pop, kh + 2 * pop
            roundRect(px, py + 2, pw, ph, 7, C_BLACK, 60)
            roundRect(px, py, pw, ph, 7, mix(RD.body, L.IMRD_ON, tt), 235)
            roundRectLine(px, py, pw, ph, 7, mix(RD.border, RD.violet, tt), 170 + 85 * tt)
            if tt > 0.02 then roundRect(px + 2, py + ph / 2 - 7 * tt, 2.5, 14 * tt, 1, RD.violet, 255 * tt) end
            if fl < 0.45 then
                local u = fl / 0.45
                local g = 6 * easeOut(u)
                roundRectLine(px - g, py - g, pw + 2 * g, ph + 2 * g, 7 + g, RD.violet, 200 * (1 - u))
            end
            textC(F.tiny, label, px + pw / 2, py, ph, mix(RD.dim, C_WHITE, tt))
        elseif style == 3 then
            if tt > 0.02 then
                for i = 1, 3 do
                    local e = i * 1.5
                    roundRectLine(kx - e, ky - e, kw + 2 * e, kh + 2 * e, 6 + e, MC.glow, (60 - i * 17) * tt)
                end
                roundRect(kx, ky, kw, kh, 6, MC.val, 70 * tt)
            end
            roundRect(kx, ky, kw, kh, 6, MC.body, 120 * (1 - tt))
            roundRectLine(kx, ky, kw, kh, 6, mix(L.IMMC_OFF, MC.border, tt), 130 + 110 * tt)
            textC(F.tiny, label, kx + kw / 2, ky, kh, mix(MC.dim, MC.val, tt))
        elseif style == 4 then
            roundRect(kx, ky, kw, kh, 6, L.IMSL_KEY, 235)
            if tt > 0.02 then
                rawColor(round(acc[1]), round(acc[2]), round(acc[3]), 255)
                draw.FilledRectFade(round(kx + 1), round(ky + 1), round(kx + kw - 1), round(ky + kh - 1),
                    clamp(round(110 * tt * ALPHA), 0, 255), 0, true)
                rect(kx, ky + 5, 2, kh - 10, acc, 255 * tt)
            end
            roundRectLine(kx, ky, kw, kh, 6, mix(SL.line, acc, tt * 0.7))
            textC(F.tiny, label, kx + kw / 2, ky, kh, mix(SL.dim, C_WHITE, tt))
        else
            roundRect(kx, ky, kw, kh, 8, mix(T.pill, acc, tt), 240)
            roundRectLine(kx, ky, kw, kh, 8, T.border, 200)
            textC(F.tiny, label, kx + kw / 2, ky, kh, mix(T.text2, C_WHITE, tt))
        end
    end

    local x0, y0 = x + 12, y + 12 + head
    key("w", "W", x0 + K + G, y0, K, K, KEY_W)
    key("a", "A", x0, y0 + K + G, K, K, KEY_A)
    key("s", "S", x0 + K + G, y0 + K + G, K, K, KEY_S)
    key("d", "D", x0 + (K + G) * 2, y0 + K + G, K, K, KEY_D)
    key("sh", "SHIFT", x0, y0 + (K + G) * 2, K * 1.5 + G / 2, K, KEY_LSHIFT)
    key("ct", "CTRL", x0 + K * 1.5 + G * 1.5, y0 + (K + G) * 2, K * 1.5 + G / 2, K, KEY_LCONTROL)
    local r4 = y0 + (K + G) * 3
    key("lmb", "LMB", x0, r4, K, K, MOUSE_LEFT)
    key("mmb", "MMB", x0 + K + G, r4, K, K, MOUSE_MIDDLE)
    key("rmb", "RMB", x0 + (K + G) * 2, r4, K, K, MOUSE_RIGHT)
    key("sp", "", x0, r4 + K + G, K * 3 + G * 2, 9, KEY_SPACE)
end
L.imDown, L.imPress = {}, {}
L.IMRD_ON, L.IMMC_OFF, L.IMSL_KEY = { 52, 46, 120 }, { 120, 126, 170 }, { 26, 26, 31 }

-- 8d. waifu companions --------------------------------------------------------
L.COMPANIONS = { { "Paimon" }, { "Elfaria" } }
local CW = { s = 1, x = 0, y = 0, petUntil = -99, cullY = 1e9 }

-- filled shape in companion coordinates
local polyArr = {}
for n = 3, 8 do
    polyArr[n] = {}
    for i = 1, n do polyArr[n][i] = { 0, 0, 0.5, 0.5 } end
end
local function cpoly(c, a, x1, y1, x2, y2, x3, y3, x4, y4, x5, y5, x6, y6, x7, y7, x8, y8)
    if hidden(a) then return end
    if y1 > CW.cullY and y2 > CW.cullY and y3 > CW.cullY and (not y4 or y4 > CW.cullY) then return end
    local n = x8 and 8 or (x7 and 7 or (x6 and 6 or (x5 and 5 or (x4 and 4 or 3))))
    local arr = polyArr[n]
    local s, ox, oy = CW.s, CW.x, CW.y
    local v
    v = arr[1]; v[1], v[2] = ox + x1 * s, oy + y1 * s
    v = arr[2]; v[1], v[2] = ox + x2 * s, oy + y2 * s
    v = arr[3]; v[1], v[2] = ox + x3 * s, oy + y3 * s
    if n >= 4 then v = arr[4]; v[1], v[2] = ox + x4 * s, oy + y4 * s end
    if n >= 5 then v = arr[5]; v[1], v[2] = ox + x5 * s, oy + y5 * s end
    if n >= 6 then v = arr[6]; v[1], v[2] = ox + x6 * s, oy + y6 * s end
    if n >= 7 then v = arr[7]; v[1], v[2] = ox + x7 * s, oy + y7 * s end
    if n >= 8 then v = arr[8]; v[1], v[2] = ox + x8 * s, oy + y8 * s end
    -- lmaobox only draws corners given clockwise: turn the list around when it runs the other way
    local area, p = 0, arr[n]
    for i = 1, n do
        v = arr[i]
        area = area + p[1] * v[2] - v[1] * p[2]
        p = v
    end
    if area < 0 then
        for i = 1, n // 2 do
            local q = arr[n + 1 - i]
            v = arr[i]
            v[1], v[2], q[1], q[2] = q[1], q[2], v[1], v[2]
        end
    end
    color(c, a)
    draw.TexturedPolygon(WHITE, arr, false)
end

-- filled ellipse
local function oval(cx, cy, rx, ry, c, a)
    if hidden(a) then return end
    if cy - ry > CW.cullY then return end
    color(c, a)
    local t = circleTex(32)
    local s = CW.s
    local x, y = CW.x + cx * s, CW.y + cy * s
    local hx, hy = rx * s * t.S / 64, ry * s * t.S / 64
    draw.TexturedRect(t.id, round(x - hx), round(y - hy), round(x + hx), round(y + hy))
end

-- thick line
local function tline(x1, y1, x2, y2, w, c, a)
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    local nx, ny = -dy / len * w / 2, dx / len * w / 2
    cpoly(c, a, x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny)
    -- round ends only where you can see them
    if w * CW.s >= 7 then oval(x1, y1, w / 2, w / 2, c, a); oval(x2, y2, w / 2, w / 2, c, a) end
end

local function crr(x, y, w, h, r, c, a)
    if y > CW.cullY then return end
    local s = CW.s
    roundRect(CW.x + x * s, CW.y + y * s, w * s, h * s, r * s, c, a)
end

-- a colour worked out on the fly
local function rgb(r, g, b)
    local o = mix(C_BLACK, C_BLACK, 0)
    o[1], o[2], o[3] = r, g, b
    return o
end

-- where the pupils look
local function eyeOffset(y0)
    if not menu.open or not settings.compFollow then return 0, 0 end
    local s = CW.s
    local ox = clamp((mouse.x - (CW.x + 120 * s)) / 260, -1, 1) * 3.6
    local oy = clamp((mouse.y - (CW.y + (y0 + 120) * s)) / 260, -1, 1) * 3.0
    return ox, oy
end

local function talking() return bubble.text ~= nil and now() - bubble.t0 < 3.2 end
local function petted() return now() < CW.petUntil end

-- colours
local K = {
    shadow = C_BLACK, white = C_WHITE,
    -- elfaria
    eSkin = { 255, 238, 232 }, eInk = { 58, 80, 150 }, gold = { 230, 184, 78 }, goldD = { 190, 140, 50 },
    brown = { 168, 84, 40 }, eWhite = { 248, 248, 255 }, skirt = { 238, 240, 253 }, skirt2 = { 214, 218, 244 },
    cream = { 255, 246, 220 }, sandal = { 112, 132, 234 }, gem = { 48, 138, 242 }, gemL = { 170, 220, 255 },
    eBlush = { 255, 165, 188 }, blushHot = { 255, 110, 150 }, eIris = { 86, 160, 236 }, ePupil = { 30, 56, 150 },
    eMouth = { 196, 90, 110 }, eSmile = { 196, 110, 130 }, lockLine = { 140, 190, 244 }, ice = { 190, 230, 255 },
}

local function elfHair(f, shade)
    shade = shade or 1
    f = clamp(f, 0, 1)
    return rgb((232 + (46 - 232) * f) * shade, (246 + (108 - 246) * f) * shade, (254 + (226 - 254) * f) * (shade * 0.5 + 0.5))
end

local function drawElf(t)
    local oy = 76
    local bob = 3 * sin(t * 2.0)
    local y0 = oy + bob
    local sway = sin(t * 1.3)

    oval(120, oy + 300, 50 - bob, 7, K.shadow, 50)

    -- very long wavy hair behind
    oval(120, y0 + 104, 66, 66, elfHair(0.1, 0.84))
    for side = -1, 1, 2 do
        for k = 1, 3 do
            local s = (k == 1) and 3 or (k == 2 and 1 or 0)
            local topx, topy = 120 + side * (40 + s * 9), y0 + 90
            local tipx, tipy = 120 + side * (58 + s * 17) + sway * (9 + s * 5) * side, y0 + 214 + s * 13
            local segs = 15
            for i = 1, segs do
                local f = (i - 1) / (segs - 1)
                local py = topy + (tipy - topy) * f
                local rr = (14.6 - 8 * f) * (1 - s * 0.08)
                local wave = 5 * sin(f * 8 + t * 1.2 + s * 1.3 + (side > 0 and 0 or 2)) * f
                local px = topx + (tipx - topx) * f + sway * 7 * f * f + wave
                oval(px, py, rr * 0.88, rr * 1.4, elfHair(0.1 + f * 0.95 - s * 0.04, 0.92))
            end
        end
    end

    -- legs: white boots with gold and brown trim, blue sandals
    for i = 1, 2 do
        local lx = (i == 1) and 108 or 132
        tline(lx, y0 + 248, lx, y0 + 292 - bob, 11, K.eWhite)
        crr(lx - 6, y0 + 252, 12, 4, 1, K.gold)
        crr(lx - 6, y0 + 270, 12, 3, 1, K.brown)
        oval(lx, oy + 296, 11, 6, K.sandal)
    end
    -- skirt with a brown and gold hem
    cpoly(K.skirt, nil, 96, y0 + 172, 144, y0 + 172, 170, y0 + 266, 70, y0 + 266)
    cpoly(K.skirt2, nil, 110, y0 + 176, 130, y0 + 176, 138, y0 + 266, 102, y0 + 266)
    crr(70, y0 + 258, 100, 8, 3, K.brown)
    crr(70, y0 + 253, 100, 2.5, 1, K.gold)
    cpoly(K.brown, nil, 146, y0 + 168, 160, y0 + 172, 176, y0 + 268, 158, y0 + 268)
    tline(151, y0 + 172, 166, y0 + 266, 1.6, K.gold)
    for i = 1, 4 do oval(160 + i * 3.4, y0 + 200 + i * 17, 2.1, 2.1, K.cream) end
    -- bodice, bare shoulders, gold collar and the gem
    crr(86, y0 + 150, 20, 14, 7, K.eSkin)
    crr(134, y0 + 150, 20, 14, 7, K.eSkin)
    cpoly(K.eWhite, nil, 98, y0 + 160, 142, y0 + 160, 140, y0 + 186, 100, y0 + 186)
    cpoly(K.gold, nil, 94, y0 + 154, 146, y0 + 154, 138, y0 + 164, 102, y0 + 164)
    crr(100, y0 + 184, 40, 8, 3, K.brown)
    tline(100, y0 + 160, 140, y0 + 186, 6, K.brown)
    for i = 1, 4 do oval(104 + i * 8.5, y0 + 163 + i * 5.2, 1.6, 1.6, K.cream) end
    cpoly(K.goldD, nil, 120, y0 + 156, 131, y0 + 170, 120, y0 + 186, 109, y0 + 170)
    cpoly(K.gold, nil, 120, y0 + 158, 129, y0 + 170, 120, y0 + 184, 111, y0 + 170)
    cpoly(K.gem, nil, 120, y0 + 161, 126, y0 + 170, 120, y0 + 180, 114, y0 + 170)
    cpoly(K.gemL, nil, 120, y0 + 164, 123.5, y0 + 170, 120, y0 + 175, 116.5, y0 + 170)
    -- arms with gold bands
    tline(94, y0 + 162, 82, y0 + 214 + 3 * sin(t * 2.0 + 1), 9, K.eSkin)
    crr(86, y0 + 172, 9, 5, 2, K.gold)
    oval(82, y0 + 218 + 3 * sin(t * 2.0 + 1), 5.5, 5.5, K.eSkin)
    local wv = sin(t * 2.6)
    tline(146, y0 + 162, 164 + 5 * wv, y0 + 196 + 4 * sin(t * 2.6 + 1.2), 9, K.eSkin)
    crr(143, y0 + 172, 9, 5, 2, K.gold)
    oval(166 + 6 * wv, y0 + 194 + 4 * sin(t * 2.6 + 1.2), 5.5, 5.5, K.eSkin)
    crr(112, y0 + 146, 16, 12, 4, K.eSkin)

    -- face
    oval(120, y0 + 114, 50, 46, K.eSkin)
    oval(83, y0 + 139, 8, 4.4, K.eBlush, 90)
    oval(157, y0 + 139, 8, 4.4, K.eBlush, 90)
    if petted() then
        oval(83, y0 + 139, 11, 5.6, K.blushHot, 110)
        oval(157, y0 + 139, 11, 5.6, K.blushHot, 110)
    end
    local ox, oyy = eyeOffset(y0)
    local cyc = t % 11.0
    local happy = (cyc > 8.6) or petted()
    local blink = (t % 4.6) > 4.42
    for i = 1, 2 do
        local ex, dir = (i == 1) and 98 or 142, (i == 1) and 1 or -1
        if happy then
            tline(ex - 10, y0 + 127, ex, y0 + 119, 2.8, K.eInk)
            tline(ex, y0 + 119, ex + 10, y0 + 127, 2.8, K.eInk)
        elseif blink then
            oval(ex, y0 + 121, 13, 16, K.eSkin)
            tline(ex - 10, y0 + 123, ex, y0 + 127, 2.6, K.eInk)
            tline(ex, y0 + 127, ex + 10, y0 + 123, 2.6, K.eInk)
        else
            oval(ex, y0 + 122, 11.5, 13.5, K.white)
            oval(ex + ox, y0 + 123 + oyy, 8.6, 11.2, K.eIris)
            oval(ex + ox, y0 + 124 + oyy, 5, 7, K.ePupil)
            oval(ex + ox + 3, y0 + 118 + oyy, 3.3, 3.3, K.white)
            oval(ex + ox - 3, y0 + 128 + oyy, 1.7, 1.7, K.white, 210)
            tline(ex - 12 * dir, y0 + 112, ex + 11 * dir, y0 + 109, 3.2, K.eInk)
            tline(ex - 12 * dir, y0 + 112, ex - 15.5 * dir, y0 + 115, 2.2, K.eInk)
            tline(ex + 4 * dir, y0 + 109.6, ex + 9 * dir, y0 + 106.6, 1.8, K.eInk)
        end
    end
    if talking() then
        oval(120, y0 + 143, 3.4, 2.0 + 2.0 * abs(sin(t * 12)), K.eMouth)
    else
        tline(114, y0 + 142.5, 120, y0 + 145, 1.5, K.eSmile)
        tline(120, y0 + 145, 126, y0 + 142.5, 1.5, K.eSmile)
    end

    -- messy hair on top
    cpoly(elfHair(0.05), nil, 76, y0 + 72, 74, y0 + 51, 96, y0 + 72)
    cpoly(elfHair(0.05), nil, 94, y0 + 66, 99, y0 + 42, 114, y0 + 66)
    cpoly(elfHair(0.09), nil, 126, y0 + 66, 141, y0 + 42, 146, y0 + 66)
    cpoly(elfHair(0.09), nil, 144, y0 + 72, 166, y0 + 51, 164, y0 + 72)
    oval(66, y0 + 128, 9, 30, elfHair(0.28))
    oval(174, y0 + 128, 9, 30, elfHair(0.28))
    local hc = elfHair(0.05)
    cpoly(hc, nil, 64, y0 + 96, 64, y0 + 70, 88, y0 + 52, 120, y0 + 46, 152, y0 + 52, 176, y0 + 70, 176, y0 + 96)
    cpoly(hc, nil, 176, y0 + 70, 178, y0 + 120, 168, y0 + 96)
    cpoly(hc, nil, 168, y0 + 96, 160, y0 + 134, 150, y0 + 98)
    cpoly(hc, nil, 150, y0 + 98, 140, y0 + 126, 130, y0 + 96)
    cpoly(hc, nil, 130, y0 + 96, 120, y0 + 124, 110, y0 + 96)
    cpoly(hc, nil, 110, y0 + 96, 100, y0 + 126, 90, y0 + 98)
    cpoly(hc, nil, 90, y0 + 98, 80, y0 + 134, 72, y0 + 96)
    cpoly(hc, nil, 72, y0 + 96, 62, y0 + 120, 64, y0 + 70)
    for k = 1, 6 do
        tline(120, y0 + 49, 62 + k * 19, y0 + 104 + ((k == 1 or k == 6) and 22 or 0), 1.5, K.lockLine, 120)
    end
    for side = -1, 1, 2 do
        for i = 1, 9 do
            local f = (i - 1) / 8
            local px = 120 + side * (58 + 3 * f) + sway * 5 * f * side + 3 * sin(f * 7 + t * 1.2) * f
            local py = y0 + 126 + 124 * f
            oval(px, py, 6.6 - 3.2 * f, 10.5 - 3 * f, elfHair(0.15 + f * 0.85))
        end
    end
    local ah = elfHair(0.3)
    tline(120, y0 + 50, 114, y0 + 36, 3, ah)
    tline(114, y0 + 36, 121, y0 + 25, 3, ah)
    tline(121, y0 + 25, 133, y0 + 27, 3, ah)

    -- floating ice sparkles
    for k = 1, 4 do
        local sx, sy = 120 + 94 * cos(t * 0.7 + k * 1.6), y0 + 110 + 70 * sin(t * 0.7 + k * 1.6)
        local s = 3.2 + 2.2 * sin(t * 4.6 + k)
        tline(sx - s, sy, sx + s, sy, 1.5, K.ice, 210)
        tline(sx, sy - s, sx, sy + s, 1.5, K.ice, 210)
    end
end

local function drawBubble(x, y, s)
    local w = textW(F.small, s) + 24
    roundRect(x + 2, y + 3, w, 30, 15, C_BLACK, 60)
    roundRect(x, y, w, 30, 15, C_WHITE, 240)
    poly({ x + 16, y + 28, x + 30, y + 28, x + 12, y + 40 }, C_WHITE, 240)
    text(F.small, s, x + 12, y, 30, { 30, 30, 40 })
end

local function drawWaifuBody(t) drawElf(t) end

local function drawSpeech()
    local dur = bubble.dur or 3.2
    if not bubble.text or now() - bubble.t0 >= dur then return end
    local a = clamp((now() - bubble.t0) / 0.2, 0, 1) * clamp((dur - (now() - bubble.t0)) / 0.3, 0, 1)
    local keep = ALPHA
    ALPHA = ALPHA * a
    drawBubble(CW.x + 150 * CW.s - textW(F.small, bubble.text) * 0.3, CW.y + 30 * CW.s - 30, bubble.text)
    ALPHA = keep
end

local function drawCompanion()
    local sw, sh = draw.GetScreenSize()
    local s = 0.8 * settings.compSize / 100
    local t = now()
    CW.s = s

    if settings.compChar ~= 2 then L.paimon.draw(sw, sh); return end

    -- her visible box is x 0..262
    local bw, bh = 262 * s, 260 * s
    -- click on her while the menu is open
    local p = settings.pos.comp
    local px, py = p and p[1] or (sw - bw - 20), p and p[2] or (sh - bh - 20)
    if menu.open and mouse.click and not mouse.used and not dropdown and inside(mouse.x, mouse.y, px, py, bw, bh) then
        CW.petUntil = now() + 1.6
        compSay("idle")
    end
    local x, y = draggable("comp", sw - bw - 20, sh - bh - 20, bw, bh)
    CW.x, CW.y = x, y - 50 * s
    CW.cullY = 1e9

    drawWaifuBody(t)
    drawSpeech()
end

---------------------------------------------------------------------------
-- 8d+. Paimon: the animated sprite waifu
---------------------------------------------------------------------------
local P = { tex = {}, loaded = 0, frame = 0, frameAt = 0, state = "idle", done = 0, failed = 0, idx = 0,
            current = "", voiceUntil = -99, lastVoice = 0, voiceLen = {}, installedCache = nil }
L.paimon = P
P.REPO = "https://raw.githubusercontent.com/eintoaster/paimon/main/"
P.W, P.H = 397, 465
P.TOTAL = 1 + 53 + 57

-- paimon's own lines
L.PLINES = {
    kill      = { "Paimon saw that! Nice one!", "Another one down~ Ehe!", "Too easy! Paimon could do that too... probably.",
                  "Woohoo! Paimon is cheering for you!", "That's how it's done, traveler!", "Hehe, they didn't stand a chance!" },
    killClass = { "Bye bye, %c! Hehe~", "That %c is toast!", "Paimon gives that %c a zero out of ten!",
                  "Hmph! That %c had it coming!", "One %c down! Who's next?" },
    killWeap  = { "Paimon really likes that %w!", "Your %w is on fire today!", "Wow, that %w hits hard!" },
    headshot  = { "Right in the head! Paimon is impressed!", "Headshot! Paimon didn't even blink!", "Boom! Perfect aim!" },
    backstab  = { "So sneaky! Paimon didn't even see you!", "Right in the back! Hehe~", "Ninja traveler!" },
    streak    = { "Unstoppable! Paimon wants a reward too!", "Nobody can stop us now!", "Paimon is so proud of you!" },
    death     = { "Hey! That's not fair!", "Ouch... Paimon felt that one.", "Get up! We're not done yet!", "Paimon will remember that..." },
    deathBy   = { "That %c is so mean! Paimon gives them an ugly nickname!", "Grr, that %c again!", "Watch out for that %c next time!" },
    idle      = { "Paimon is hungry... Got any snacks?", "Ehe~", "Let's go, traveler!", "Paimon is the best guide, right?",
                  "Don't forget about Paimon!" },
}

-- the 111 files to download: { file in the repo, path, kind }
P.MIRRORS = { "https://raw.githubusercontent.com/eintoaster/paimon/main/", "https://cdn.jsdelivr.net/gh/eintoaster/paimon@main/" }   -- (GitHub first: jsDelivr can keep old copies for days)
function P.files()
    if P.list then return P.list end
    local l = {}
    for i = 0, 52 do l[#l + 1] = { "paimon_frames_b64/frame_" .. i .. ".b64", "destiny_files/paimon/frames/frame_" .. i .. ".png", "png" } end
    for i = 1, 57 do l[#l + 1] = { "paimon_voice_b64/" .. i .. ".b64", "tf/sound/destiny_paimon/" .. i .. ".wav", "wav" } end
    l[#l + 1] = { "Genshin_Impact.b64", "destiny_files/paimon/Genshin_Impact.ttf", "ttf" }
    P.list = l
    return l
end

local function fileExists(path)
    local ok, f = pcall(io.open, path, "rb")
    if ok and f then f:close(); return true end
    return false
end

-- installed = the last frame
-- installed with the padded 512x512 frames? (older installs get an "Update" button)
function P.isV2()
    if P.v2 == nil then
        local ok, f = pcall(io.open, "destiny_files/paimon/frames_v2.txt", "r")
        P.v2 = (ok and f) and true or false
        if ok and f then f:close() end
    end
    return P.v2
end

function P.installed()
    if P.installedCache == nil then
        P.installedCache = fileExists("destiny_files/paimon/frames/frame_52.png")
            and fileExists("destiny_files/paimon/Genshin_Impact.ttf") and fileExists("tf/sound/destiny_paimon/57.wav")
    end
    return P.installedCache
end

-- base64 -> bytes for the text between positions i and j
L.B64 = {}
do
    local a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do L.B64[a:byte(i)] = i - 1 end
end
P.buf = {}
function P.b64(s, i, j)
    local D, buf, out = L.B64, P.buf, {}
    local bn, byte, char, unpack = 0, string.byte, string.char, table.unpack
    for k = i, j, 4 do
        local a, b, c, d = byte(s, k, k + 3)
        local va, vb = D[a], D[b]
        if not va or not vb then break end
        local vc, vd = D[c], D[d]
        local v = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
        bn = bn + 1; buf[bn] = v >> 16
        if vc then bn = bn + 1; buf[bn] = (v >> 8) & 255 end
        if vd then bn = bn + 1; buf[bn] = v & 255 end
        if bn >= 3000 then out[#out + 1] = char(unpack(buf, 1, bn)); bn = 0 end
    end
    if bn > 0 then out[#out + 1] = char(unpack(buf, 1, bn)) end
    return table.concat(out)
end

function P.install()
    if P.state == "downloading" then return end
    if not http or not io then notify("✖", "Can't install Paimon", "lmaobox blocks downloads or files", RED); return end
    for _, d in ipairs({ "destiny_files", "destiny_files/paimon", "destiny_files/paimon/frames", "tf/sound", "tf/sound/destiny_paimon" }) do
        pcall(filesystem.CreateDirectory, d)
    end
    P.state, P.done, P.failed, P.idx = "downloading", 0, 0, 0
    P.job, P.waiting, P.result, P.try = nil, false, nil, 1
    P.startNext = true
end

-- "Test downloads"
P.TESTS = {
    { "tiny page (async)", "https://catfact.ninja/fact", true },
    { "18 KB jsDelivr (async)", "https://cdn.jsdelivr.net/gh/eintoaster/paimon@main/paimon.lua", true },
    { "106 KB jsDelivr (async)", "https://cdn.jsdelivr.net/gh/eintoaster/paimon@main/paimon_frames_b64/frame_0.b64", true },
    { "106 KB GitHub (async)", "https://raw.githubusercontent.com/eintoaster/paimon/main/paimon_frames_b64/frame_0.b64", true },
    { "106 KB jsDelivr (wait)", "https://cdn.jsdelivr.net/gh/eintoaster/paimon@main/paimon_frames_b64/frame_0.b64", false },
    { "6 MB jsDelivr (async)", "https://cdn.jsdelivr.net/gh/eintoaster/paimon@main/paimon_voice_b64/11.b64", true },
}
P.diag = nil
local function describe(data)
    if type(data) ~= "string" then return "nothing (" .. type(data) .. ")" end
    if data:sub(1, 5) == "ERROR" then return data:sub(1, 60) end
    return #data .. " bytes: " .. data:sub(1, 18):gsub("[^%g ]", "?")
end
function P.runTest()
    P.diag = {}
    for i, tst in ipairs(P.TESTS) do
        P.diag[i] = "waiting..."
        if tst[3] then
            local ok, err = pcall(http.GetAsync, tst[2], function(data) P.diag[i] = describe(data) end)
            if not ok then P.diag[i] = "could not start: " .. tostring(err) end
        else
            local ok, data = pcall(http.Get, tst[2])
            P.diag[i] = ok and describe(data) or ("error: " .. tostring(data))
        end
    end
    print("[destiny] download test started, see Waifus > Paimon")
end

-- the callback only hands the answer over
function P.request(f)
    P.waiting, P.result = true, nil
    local url = P.MIRRORS[P.try] .. f[1]
    -- (waits for the answer
    local ok, data = pcall(http.Get, url)
    P.result = { f = f, data = ok and data or nil }
end

function P.finish()
    P.state = (P.failed == 0) and "done" or "failed"
    P.installedCache = nil
    P.unloadTextures()
    P.voiceLen, P.fontId = {}, nil
    if P.failed == 0 then
        local okM, fm = pcall(io.open, "destiny_files/paimon/frames_v2.txt", "w")      -- (padded 512x512 frames)
        if okM and fm then fm:write("1"); fm:close() end
        P.v2 = true
        notify("✔", "Paimon installed", P.done .. " files downloaded", accent())
    else
        notify("✖", "Paimon: " .. P.failed .. " files failed", tostring(P.lastFail) .. ": " .. tostring(P.why), RED)
        print("[destiny] Paimon install: " .. P.failed .. " failed, last " .. tostring(P.lastFail) .. " (" .. tostring(P.why) .. ")")
    end
end

-- checks an answer
local SIG = { png = function(h) return h:sub(2, 4) == "PNG" end, wav = function(h) return h:sub(1, 4) == "RIFF" end,
              ttf = function(h) return h:sub(1, 4) == "\0\1\0\0" or h:sub(1, 4) == "OTTO" or h:sub(1, 4) == "true" end }
function P.check(f, data)
    if type(data) ~= "string" or #data < 16 then return nil, "got " .. (type(data) == "string" and #data or 0) .. " bytes" end
    if data:sub(1, 5) == "ERROR" then return nil, data:sub(1, 40) end
    if #data % 4 ~= 0 or data:find("[^%w%+/=]") then data = data:gsub("[^%w%+/=]", "") end
    if not SIG[f[3]](P.b64(data, 1, 16)) then return nil, "not a " .. f[3] .. " (" .. data:sub(1, 24) .. ")" end
    return data
end

-- runs every frame while installing
function P.work()
    if P.state ~= "downloading" then return end
    local list = P.files()

    if P.startNext and not P.waiting and not P.job then
        P.startNext = false
        P.idx, P.try = P.idx + 1, 1
        local f = list[P.idx]
        if not f then return P.finish() end
        P.current = f[2]:match("[^/]+$")
        P.request(f)
        return
    end

    if P.waiting and P.result then
        local f, data = P.result.f, P.result.data
        P.waiting, P.result = false, nil
        local text, why = P.check(f, data)
        if not text then
            if P.try < #P.MIRRORS then P.try = P.try + 1; P.request(f); return end
            P.failed, P.lastFail, P.why = P.failed + 1, P.current, why
            P.startNext = true
            return
        end
        local ok, fh = pcall(io.open, f[2], "wb")
        if not ok or not fh then
            P.failed, P.lastFail, P.why = P.failed + 1, P.current, "can't write " .. f[2]
            P.startNext = true
            return
        end
        P.job = { data = text, pos = 1, fh = fh }
    end

    local job = P.job
    if job then
        local t0 = L.clock()
        local n = #job.data
        repeat
            local j = min(n, job.pos + 49151)
            job.fh:write(P.b64(job.data, job.pos, j))
            job.pos = j + 1
        until job.pos > n or (L.clock() - t0) > 0.003
        if job.pos > n then
            job.fh:close()
            P.job = nil
            P.done = P.done + 1
            P.startNext = true
        end
    end
end

-- textures: loaded a few per frame from the absolute path
function P.frameDir()
    if not P.dir then
        local ok, gd = pcall(engine.GetGameDir)
        gd = (ok and gd) and tostring(gd) or ""
        P.dir = gd:gsub("[\\/]tf[\\/]?$", "") .. "\\destiny_files\\paimon\\frames\\frame_"
    end
    return P.dir
end

function P.loadSome()
    local n = 0
    while P.loaded < 53 and n < 4 do
        local ok, id = pcall(draw.CreateTexture, P.frameDir() .. P.loaded .. ".png")
        L.recolor()
        P.tex[P.loaded] = ok and id or false
        P.loaded = P.loaded + 1
        n = n + 1
    end
end

function P.unloadTextures()
    for i, id in pairs(P.tex) do if id then pcall(draw.DeleteTexture, id) end end
    P.tex, P.loaded = {}, 0
end

-- the Genshin font for her bubbles
function P.font()
    if not settings.paiFont then return F.small end
    if P.fontId == nil then
        P.fontId = false
        if P.installed() then
            local okD, gd = pcall(engine.GetGameDir)
            local root = ((okD and gd) and tostring(gd) or ""):gsub("[\\/]tf[\\/]?$", "")
            pcall(draw.AddFontResource, root .. "\\destiny_files\\paimon\\Genshin_Impact.ttf")
            local ok, id = pcall(draw.CreateFont, "Default_SC", 17, 600, FONTFLAG_ANTIALIAS)
            if ok and id then P.fontId = id end
        end
    end
    return P.fontId or F.small
end

-- the Genshin-style speech bubble
L.PB_BG, L.PB_EDGE, L.PB_TEXT = { 236, 229, 216 }, { 196, 186, 166 }, { 73, 83, 102 }
function P.bubble(cx, bottomY, s)
    local font = P.font()
    local w = textW(font, s) + 30
    local h = 30
    local x, y = cx - w / 2, bottomY - h - 8
    roundRect(x + 1, y + 2, w, h, 15, C_BLACK, 50)
    roundRect(x, y, w, h, 15, L.PB_BG, 245)
    roundRectLine(x, y, w, h, 15, L.PB_EDGE, 200)
    L.screenSpace()
    cpoly(L.PB_BG, 245, cx - 7, y + h - 1, cx + 7, y + h - 1, cx, y + h + 7)
    textC(font, s, cx, y, h, L.PB_TEXT)
end

-- paimon on screen
function P.draw(sw, sh)
    local s = settings.compSize / 100
    local W, H = P.W / 2.8 * s, P.H / 2.8 * s
    if not P.installed() then
        local msg = { { "Install Paimon in the Waifus tab", RD.white } }
        local cw2 = chipW("♥", msg)
        chip(sw - cw2 - 20, sh - 46, "♥", msg)
        return
    end
    P.loadSome()
    P.idleVoice()
    local t = now()
    local steps = floor((t - P.frameAt) / 0.03)
    if steps > 0 then
        P.frame = (P.frame + steps) % 53
        P.frameAt = (steps > 10) and t or (P.frameAt + steps * 0.03)
    end
    local p = settings.pos.comp
    local px, py = p and p[1] or (sw - W - 20), p and p[2] or (sh - H - 20)
    if menu.open and mouse.click and not mouse.used and not dropdown and inside(mouse.x, mouse.y, px, py, W, H) then
        compSay("idle")
    end
    local x, y = draggable("comp", sw - W - 20, sh - H - 20, W, H)
    local id = P.tex[P.frame] or P.tex[0]
    if id then
        color(C_WHITE)
        -- lmaobox puts each 397x465 frame into a 512x512 texture
        local U, V = 397 / 512, 465 / 512
        draw.TexturedPolygon(id, { { round(x), round(y), 0, 0 }, { round(x + W), round(y), U, 0 },
            { round(x + W), round(y + H), U, V }, { round(x), round(y + H), 0, V } }, false)
    end
    -- the bubble above her head
    local dur = bubble.dur or 3.2
    if bubble.text and t - bubble.t0 < dur then
        local keep = ALPHA
        ALPHA = ALPHA * clamp((t - bubble.t0) / 0.2, 0, 1) * clamp((dur - (t - bubble.t0)) / 0.3, 0, 1)
        P.bubble(x + W / 2, y + H * 0.06, bubble.text)
        ALPHA = keep
    end
end

-- a random voice line
function P.voiceLength(i)
    if not P.voiceLen[i] then
        local len = 2
        local ok, f = pcall(io.open, "tf/sound/destiny_paimon/" .. i .. ".wav", "rb")
        if ok and f then
            local size = f:seek("end")
            f:close()
            if size then len = size / (44100 * 4) end
        end
        P.voiceLen[i] = len
    end
    return P.voiceLen[i]
end

function P.speak(force)
    if not P.installed() then return end
    if not force and now() < P.voiceUntil then return end
    local i
    repeat i = math.random(1, 57) until i ~= P.lastVoice
    P.lastVoice = i
    pcall(engine.PlaySound, "destiny_paimon/" .. i .. ".wav")
    P.voiceUntil = now() + P.voiceLength(i)
end

-- every now and then she says something on her own
function P.idleVoice()
    if not settings.paiIdle then P.nextIdle = nil; return end
    local t = now()
    if not P.nextIdle then P.nextIdle = t + settings.paiIdleEvery * (0.5 + math.random()) end
    if t >= P.nextIdle then
        P.nextIdle = t + settings.paiIdleEvery * (0.5 + math.random())
        if t >= P.voiceUntil then
            P.speak(false)
            if math.random() < 0.5 then compSay("idle") end
        end
    end
end

-- called by the kill event
function P.onKill()
    if settings.compOn and settings.compChar == 1 and settings.paiVoice then P.speak(false) end
end

-- hit logs like the old paimon.lua: "You hit Heavy for 54 damage
function P.hitLog(name, class, dmg, hp, crit)
    if not (settings.compOn and settings.compChar == 1 and settings.paiLogs and settings.compBubbles) then return end
    if now() - (L.reactAt or -99) < 2.5 then return end
    local who = class and (name .. " (" .. class .. ")") or name
    local s
    if hp and hp > 0 then
        s = string.format("%sYou hit %s for %d damage! %d HP left!", crit and "Crit! " or "", who, dmg, hp)
    else
        s = string.format("%sYou hit %s for %d damage!", crit and "Crit! " or "", who, dmg)
    end
    bubble.text, bubble.t0, bubble.dur = s, now(), settings.paiLogTime
end

-- 8e. notifications -----------------------------------
local function noteSize(n, style)
    if style == 2 then
        local parts = { { n.title } }
        if n.body ~= "" then parts[2] = { n.body } end
        return chipW(n.icon, parts), 26
    elseif style == 3 then
        return 44 + textW(F.rd, n.title) + (n.body ~= "" and (textW(F.rd, n.body) + 8) or 0), 28
    end
    return 316, 58
end

local function drawNote(n, x, y, w, h, style, idx)
    local col = n.col
    local gst = L.gradStops(settings.ntGrad)
    if gst and col ~= RED then col = sampleStops(gst, now() * 0.12 + idx * 0.1) end
    if style == 2 then
        local parts = { { n.title, gst and col or RD.white } }
        if n.body ~= "" then parts[2] = { n.body, (n.col == RED) and RED or (gst and sampleStops(gst, now() * 0.12 + idx * 0.1 + 0.35) or RD.violet) } end
        chip(x, y, n.icon, parts, 26)
        L.styledBorder(settings.ntBorder == 2 and 1 or settings.ntBorder, settings.ntGrad, x, y, w, 26, 7)
    elseif style == 3 then
        local bright = (idx == 1) and 1 or 0.55
        for i = 1, 3 do
            local e = i * 1.5
            roundRectLine(x - e, y - e, w + 2 * e, h + 2 * e, 7 + e, col, (62 - i * 17) * bright)
        end
        roundRect(x, y, w, h, 7, L.MCPILL, 160 + 60 * bright)
        roundRectLine(x, y, w, h, 7, col, 140 + 90 * bright)
        text(F.icon, n.icon, x + 10, y, h, col)
        text(F.rd, n.title, x + 32, y, h, gst and col or MC.text, 180 + 75 * bright)
        if n.body ~= "" then text(F.rd, n.body, x + 38 + textW(F.rd, n.title), y, h, col) end
    elseif style == 4 then
        roundRect(x, y + 2, w, h, 6, C_BLACK, 70)
        roundRect(x, y, w, h, 6, SL.body, 240)
        roundRectLine(x, y, w, h, 6, SL.line)
        L.styledBorder(settings.ntBorder == 2 and 1 or settings.ntBorder, settings.ntGrad, x, y, w, h, 6)
        rect(x, y + 8, 2, h - 16, col)
        text(F.icon, n.icon, x + 14, y, h, col)
        rect(x + 36, y + 10, 1, h - 20, SL.line)
        text(F.bold, fit(F.bold, n.title, w - 58), x + 46, y + (n.body ~= "" and 7 or 0), n.body ~= "" and 22 or h, gst and col or SL.text)
        if n.body ~= "" then text(F.small, fit(F.small, n.body, w - 58), x + 46, y + 28, 20, SL.dim) end
    elseif style >= 5 then
        local st = style + 3
        local p = L.palFor(st, settings.ntGrad)
        L.panelBg(st, x, y, w, h, nil, settings.ntBorder == 2 and 1 or settings.ntBorder, settings.ntGrad)
        local ic = (n.col == RED) and RED or ((st == 8 and not gst) and L.RY.pink or col)
        disc(x + 30, y + 29, 15, ic, st == 9 and 64 or 46)
        textC(F.icon, n.icon, x + 30, y + 17, 24, ic)
        if n.body == "" then
            text(F.bold, fit(F.bold, n.title, w - 72), x + 58, y + 4, h - 8, p.txt)
        else
            text(F.bold, fit(F.bold, n.title, w - 72), x + 58, y + 9, 20, p.txt)
            text(F.small, fit(F.small, n.body, w - 72), x + 58, y + 29, 18, p.dim)
        end
    else
        if settings.ntBg then
            roundRect(x - 1, y + 3, w + 2, h, 15, C_BLACK, 50)
            roundRect(x, y, w, h, 14, T.card, 245)
        end
        if settings.ntBorder == 2 then roundRectLine(x, y, w, h, 14, T.border)
        else L.styledBorder(settings.ntBorder, settings.ntGrad, x, y, w, h, 14) end
        disc(x + 30, y + 29, 15, col, 40)
        textC(F.icon, n.icon, x + 30, y + 17, 24, col)
        local tc = gst and col or T.text
        if n.body == "" then
            text(F.bold, fit(F.bold, n.title, w - 72), x + 58, y + 4, h - 8, tc)
        else
            text(F.bold, fit(F.bold, n.title, w - 72), x + 58, y + 9, 20, tc)
            text(F.small, fit(F.small, n.body, w - 72), x + 58, y + 29, 18, T.text2)
        end
    end
end
L.MCPILL = { 24, 24, 40 }

local function drawNotifications()
    local sw, sh = draw.GetScreenSize()
    local style, pos = settings.ntStyle, settings.ntPos
    local gap = (style == 2 or style == 3) and 8 or 10
    local life = settings.ntTime
    for k = #notes, 1, -1 do
        if now() - notes[k].t0 > life + 0.4 then table.remove(notes, k) end
    end
    local i = 0
    for idx, n in ipairs(notes) do
        local w, h = noteSize(n, style)
        local age = now() - n.t0
        local inT = easeOutBack(age / 0.48)
        local out = (age > life) and min(1, (age - life) / 0.4) ^ 2 or 0
        n.key = n.key or ("nslot" .. tostring(n))
        local slot = anim(n.key, i, 12)
        local x, y
        local fromRight = (pos == 1 or pos == 2)
        local slide = w + 40
        if pos == 3 or pos == 4 then x = (sw - w) / 2 else x = fromRight and (sw - w - 16) or 16 end
        if pos == 1 or pos == 3 or pos == 5 then y = 56 + slot * (h + gap) else y = sh - 16 - h - slot * (h + gap) end
        if pos == 3 or pos == 4 then y = y + ((1 - min(1, inT)) + out) * (pos == 3 and -30 or 30)
        else x = x + ((1 - inT) + out) * (fromRight and slide or -slide) end
        ALPHA = clamp(min(age / 0.2, 1) * (1 - out), 0, 1)
        drawNote(n, x, y, w, h, style, idx)
        -- time left bar
        local left = clamp(1 - age / life, 0, 1)
        if style == 1 then
            local gst = L.gradStops(settings.ntGrad)
            local bc = (gst and n.col ~= RED) and sampleStops(gst, now() * 0.12 + idx * 0.1) or n.col
            roundRect(x + 16, y + h - 6, (w - 32) * left, 2.5, 1, bc, 150)
        elseif style == 4 then rect(x + 10, y + h - 3, (w - 20) * left, 2, n.col, 160)
        elseif style >= 5 then roundRect(x + 20, y + h - 7, (w - 40) * left, 2.5, 1, (style == 5 and n.col ~= RED) and L.RY.pink or n.col, 180) end
        ALPHA = 1
        i = i + 1
    end
end

-- 8f. damage numbers ----------------------------------------------------------
local function drawDamage()
    local life = 1.1
    for k = #dmgs, 1, -1 do if now() - dmgs[k].t0 > life then table.remove(dmgs, k) end end
    for _, d in ipairs(dmgs) do
        local ok, pos = pcall(L.originOf, d.ent)
        if ok and pos then pos.z = pos.z + 82 end
        local sx, sy
        if ok and pos then
            local a, b = client.WorldToScreen(pos)
            if type(a) == "table" then sx, sy = a[1], a[2] elseif a then sx, sy = a, b end
        end
        if sx then
            local u = (now() - d.t0) / life
            sy = sy - 34 * easeOut(u)
            sx = sx + d.ox
            ALPHA = clamp((1 - u) / 0.35, 0, 1)
            local s = "-" .. d.amt
            local pop = easeOutBack(u / 0.18)
            if settings.dmgStyle == 2 then
                local col = d.crit and GOLD or RD.white
                local w = chipW("✦", { { s } })
                chip(sx - w / 2, sy - 12 - (1 - pop) * 6, "✦", { { s, col } })
            elseif settings.dmgStyle == 3 then
                local w = textW(F.rd, s) + 20
                mercuryBox(sx - w / 2, sy - 13, w, 26, 8)
                textC(F.rd, s, sx, sy - 13, 26, d.crit and GOLD or MC.val)
            else
                local col = d.crit and GOLD or C_WHITE
                textC(F.dmg, s, sx, sy - 14 - (1 - pop) * 8, 28, col)
            end
            ALPHA = 1
        end
    end
end

-- 8h. kill announcer ---------------------------------------------------------------
local function drawAnnouncer()
    local el = now() - ka.t0
    if el > 2.4 or el < 0 then return end
    local sw, sh = draw.GetScreenSize()
    local tier = min(ka.tier, 10)
    local wt = min(tier, 5)
    local fade = el < 1.95 and 1 or max(0, 1 - (el - 1.95) / 0.42)
    local s = easeOutBack(el / 0.38) * (1 - 0.12 * (1 - fade)) * (0.86 + 0.05 * wt)
    local stops = L.kaStops()
    local t = now()
    local c1, c2 = sampleStops(stops, t * 0.25), sampleStops(stops, t * 0.25 + 0.45)
    local cx, cy = sw / 2, sh * 0.24
    ALPHA = fade

    -- burst: ring, rays and sparks fly out when it appears
    if el < 0.65 then
        local b = el / 0.65
        local e = 1 - (1 - b) ^ 3
        for k = 1, 3 do ring(cx, cy, 30 + 150 * e + k, c1, (210 - k * 50) * (1 - b), 64) end
        for k = 1, 16 do
            local ang = k * 0.3927 + 0.2
            local r0 = 46 + 40 * e
            local r1 = r0 + 70 * (1 - b)
            line(cx + cos(ang) * r0, cy + sin(ang) * r0, cx + cos(ang) * r1, cy + sin(ang) * r1, C_WHITE, 170 * (1 - b))
        end
        for k = 1, 14 do
            local ang = k * 0.4488 + tier
            local r = 50 + 170 * e * (0.6 + 0.4 * ((k * 7) % 5) / 5)
            disc(cx + cos(ang) * r, cy + sin(ang) * r, 3.2 * (1 - b) + 0.5, c2, 230 * (1 - b))
        end
    end

    -- soft breathing glow behind the emblem
    local gl = 0.75 + 0.25 * sin(t * 4)
    for k = 1, 5 do disc(cx, cy, (70 - k * 10) * s, c1, 16 * gl) end

    if settings.kaStyle == 2 then
        -- classic: wings, more and longer feathers the higher the streak
        local nf = 1 + wt
        for _, side in ipairs({ -1, 1 }) do
            for k = 1, nf do
                local ang = (nf == 1) and -0.2 or ((-38 + (k - 1) * (70 / max(1, nf - 1))) * 0.01745)
                local len = (54 + k * 9 + wt * 4) * s
                local flap = 0.06 * sin(t * 5 + k)
                local bx, by = cx + side * 30 * s, cy + (-4 + k * 3) * s
                local tx, ty = bx + side * cos(ang + flap) * len, by + sin(ang + flap) * len * 0.8
                local px, py = bx + side * cos(ang + flap - 0.18) * len * 0.5, by + sin(ang + flap - 0.18) * len * 0.5 - 4 * s
                local mx, my = bx + side * cos(ang + flap + 0.22) * len * 0.55, by + sin(ang + flap + 0.22) * len * 0.55 + 8 * s
                local col = sampleStops(stops, t * 0.25 + k * 0.07)
                poly({ bx, by - 6 * s, px, py, tx, ty }, col, 210)
                poly({ bx, by - 6 * s, tx, ty, mx, my, bx, by + 8 * s }, col, 210)
                line(bx, by - 6 * s, tx, ty, C_WHITE, 120)
            end
        end
        -- emblem: a diamond in the gradient with the tier in
        local r = 30 * s
        poly({ cx, cy - r - 4, cx + r + 4, cy, cx, cy + r + 4, cx - r - 4, cy }, C_WHITE, 230)
        poly({ cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy }, c1, 255)
        poly({ cx, cy - r * 0.62, cx + r * 0.62, cy, cx, cy + r * 0.62, cx - r * 0.62, cy }, c2, 255)
    else
        -- neon: glowing rings that pulse
        local r = 34 * s
        for k = 0, 3 do ring(cx, cy, r + k * 2, c1, 200 - k * 50, 48) end
        ring(cx, cy, r * 0.7, c2, 220, 48)
        ring(cx, cy, r * 0.7 + 1, c2, 140, 48)
        for k = 1, 6 do
            local ang = t * 1.5 + k * pi / 3
            disc(cx + cos(ang) * r * 1.25, cy + sin(ang) * r * 1.25, 2.5, c2, 220)
        end
    end
    -- number in the middle
    textC(F.big, tostring(ka.streak), cx, cy - 18, 36, settings.kaStyle == 2 and C_WHITE or c1)

    -- title
    local ta = clamp((el - 0.12) / 0.22, 0, 1)
    ALPHA = fade * ta
    local title = L.KA_NAMES[tier]
    local ty = cy + 52 + (1 - ta) * 10
    local tw = textW(F.kaT, title)
    if settings.kaStyle == 1 then
        for _, o in ipairs({ { -3, 0 }, { 3, 0 }, { 0, -3 }, { 0, 3 } }) do textC(F.kaT, title, cx + o[1], ty + o[2], 50, c1, 40) end
        for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do textC(F.kaT, title, cx + o[1], ty + o[2], 50, c1, 200) end
        textC(F.kaT, title, cx, ty, 50, C_WHITE)
        local lw = 120 * easeOut((el - 0.2) / 0.4)
        rect(cx - tw / 2 - 16 - lw, ty + 25, lw, 2, c2, 220)
        rect(cx + tw / 2 + 16, ty + 25, lw, 2, c2, 220)
    else
        for _, o in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }) do textC(F.kaT, title, cx + o[1], ty + o[2], 50, c1, 255) end
        textC(F.kaT, title, cx, ty + 2, 50, C_BLACK, 90)
        textC(F.kaT, title, cx, ty, 50, C_WHITE)
    end
    if ka.sub ~= "" then textC(F.kaS, ka.sub, cx, ty + 50, 24, { 235, 235, 245 }, 220) end
    ALPHA = 1
end

---------------------------------------------------------------------------
-- 8i. Hit effects: colours, screen edge styles, extra effects, screen shake
---------------------------------------------------------------------------
L.RED_FX = { 255, 45, 85 }
L.BLOOD = { 138, 0, 14 }

-- the effect colour at position p
function L.fxColor(kill, p)
    local i = settings.vigColor
    local t = now() * settings.vigSpeed * 0.06
    if i >= 5 then return sampleStops(logoStops(i - 4), (p or 0) + t) end
    local base
    if i == 2 then base = L.RED_FX
    elseif i == 3 then base = C_WHITE
    elseif i == 4 then base = L.hex(kill and settings.colKill or settings.colHit) or accent()
    else base = accent() end
    if settings.vigAnim then
        return mix(base, C_WHITE, 0.55 * (0.5 + 0.5 * sin(((p or 0) + t) * 6.283)))
    end
    return base
end

-- screen-space drawing with the waifu shape helpers
function L.screenSpace() CW.s, CW.x, CW.y, CW.cullY = 1, 0, 0, 1e9 end

-- a wide ring: at most 3 circle outlines, with as many pieces as the size needs
function L.thickRing(cx, cy, r, w, c, a)
    if r < 1 or hidden(a) then return end
    local segs = clamp(floor(r / 7), 20, 56)
    local lines = clamp(floor(w / 3), 1, 3)
    if lines == 1 then ring(cx, cy, r, c, a, segs); return end
    local step = w / (lines - 1)
    for i = 0, lines - 1 do ring(cx, cy, r - w / 2 + i * step, c, a, segs) end
end

-- the four glowing screen edges
function L.edges(size, a, kill, sideMul)
    sideMul = sideMul or 0.85
    edgeFade("top", size, L.fxColor(kill, 0.0), a)
    edgeFade("bottom", size, L.fxColor(kill, 0.5), a)
    edgeFade("left", size, L.fxColor(kill, 0.75), a * sideMul)
    edgeFade("right", size, L.fxColor(kill, 0.25), a * sideMul)
end

-- scanlines: a 2 x 256 picture with a line on every 4th row, drawn a few times down the screen
function L.scanlines(c, a)
    if hidden(a) then return end
    if not L.scanTex then
        local px = {}
        for row = 0, 255 do
            local p = (row % 4 == 0) and string.char(255, 255, 255, 255) or string.char(255, 255, 255, 0)
            px[#px + 1] = p; px[#px + 1] = p
        end
        L.scanTex = draw.CreateTextureRGBA(table.concat(px), 2, 256)
        L.recolor()
    end
    local sw, sh = draw.GetScreenSize()
    color(c, a)
    for y = 0, sh, 256 do draw.TexturedRect(L.scanTex, 0, y, sw, y + 256) end
end

-- small random numbers that stay the same for one effect
function L.rnd(seed, i)
    local x = sin(seed * 12.9898 + i * 78.233) * 43758.5453
    return x - floor(x)
end

-- a frame of 4 bars, a given distance in from the screen edges
function L.frame(inset, th, c, a)
    local sw, sh = draw.GetScreenSize()
    rect(inset, inset, sw - 2 * inset, th, c, a)
    rect(inset, sh - inset - th, sw - 2 * inset, th, c, a)
    rect(inset, inset + th, th, sh - 2 * inset - 2 * th, c, a)
    rect(sw - inset - th, inset + th, th, sh - 2 * inset - 2 * th, c, a)
end

-- an L-shaped bracket in each corner
function L.brackets(inset, len, th, c, a)
    local sw, sh = draw.GetScreenSize()
    for i = 0, 3 do
        local rx, by = i % 2 == 1, i >= 2
        local x0, y0 = rx and (sw - inset - len) or inset, by and (sh - inset - th) or inset
        rect(x0, y0, len, th, c, a)
        rect(rx and (sw - inset - th) or inset, by and (sh - inset - len) or inset, th, len, c, a)
    end
end

-- a band across the screen that fades from one strength to another, top to bottom
function L.band(y0, y1, c, a0, a1)
    local sw = draw.GetScreenSize()
    rawColor(clamp(round(c[1]), 0, 255), clamp(round(c[2]), 0, 255), clamp(round(c[3]), 0, 255), 255)
    draw.FilledRectFade(0, round(y0), sw, round(y1), clamp(round(a0 * ALPHA), 0, 255), clamp(round(a1 * ALPHA), 0, 255), false)
end

L.vfx = { t0 = -99, len = 1, power = 0, kill = false, seed = 0 }

function L.drawEdgeEffect()
    local v = L.vfx
    local el = now() - v.t0
    local u = el / v.len
    if u >= 1 or u < 0 then return end
    local sw, sh = draw.GetScreenSize()
    local kill = v.kill
    local env = min(1, el / 0.05) * (1 - u) ^ 1.4
    local a = 235 * settings.vigInt / 100 * v.power * env
    local size = max(40, min(sw, sh) * settings.vigSize / 100 * 2.2) * (kill and 1.15 or 0.85)
    local style = settings.vigStyle

    if settings.vigTintAmt > 0 then rect(0, 0, sw, sh, L.fxColor(kill, 0), settings.vigTintAmt * 2.2 * env * v.power) end

    if style == 2 then
        L.edges(size * 0.6, a * 0.5, kill)
        for k = 0, 2 do
            local ph = (el * 1.7 + k / 3) % 1
            L.frame(easeOut(ph) * size * 1.5, 2 + 6 * (1 - ph), L.fxColor(kill, k / 3), a * (1 - ph))
        end
    elseif style == 3 then
        local c = L.fxColor(kill, 0)
        L.scanlines(c, 70 * env * v.power)
        L.edges(size * 0.45, a * 0.45, kill)
        local by = ((el * 1.1) % 1) * (sh + 240) - 120
        L.band(by - 110, by, c, 0, 110 * env * v.power)
        L.band(by, by + 30, c, 110 * env * v.power, 0)
        rect(0, by - 1, sw, 2, C_WHITE, 190 * env)
    elseif style == 4 then
        local frame = floor(el * 22)
        edgeFade("left", size * 0.5, L.MAGENTA, a * 0.6)
        edgeFade("right", size * 0.5, L.CYAN, a * 0.6)
        for i = 1, 6 do
            local th = 2 + L.rnd(v.seed + frame, i + 100) * 12
            local ty = L.rnd(v.seed + frame, i + 120) * (sh - th)
            local off = (L.rnd(v.seed + frame, i + 140) - 0.5) * 80
            rect(off, ty, sw, th, (i % 2 == 0) and L.CYAN or L.MAGENTA, (22 + 34 * L.rnd(v.seed, i)) * env)
            rect(off + ((i % 2 == 0) and 8 or -8), ty + th, sw, 1, C_WHITE, 80 * env)
        end
        L.brackets(22 + (L.rnd(v.seed + frame, 90) - 0.5) * 14, 54, 3, L.fxColor(kill, 0), 230 * env)
        for i = 1, 8 do
            local bh = 3 + L.rnd(v.seed + frame, i) * 14
            local by = L.rnd(v.seed + frame, i + 20) * (sh - bh)
            local bw = sw * (0.04 + 0.2 * L.rnd(v.seed + frame, i + 40))
            local right = L.rnd(v.seed + frame, i + 60) > 0.5
            rect(right and (sw - bw) or 0, by, bw, bh, (i % 2 == 0) and L.CYAN or L.MAGENTA, (70 + 80 * L.rnd(v.seed, i)) * env)
        end
    elseif style == 5 then
        edgeFade("top", size * 0.9, L.FROST, a * 0.5)
        edgeFade("bottom", size * 0.9, L.FROST, a * 0.5)
        edgeFade("left", size * 0.9, L.FROST, a * 0.45)
        edgeFade("right", size * 0.9, L.FROST, a * 0.45)
        L.edges(size * 0.45, a * 0.5, kill)
        L.screenSpace()
        local grow = easeOut(el / 0.22)
        for i = 1, 40 do
            local e = i % 4
            local p = L.rnd(v.seed, i + 2000)
            local len = (0.3 + 0.7 * L.rnd(v.seed, i + 2050)) * size * 0.95 * grow
            local wd = 5 + 13 * L.rnd(v.seed, i + 2090)
            local skew = (L.rnd(v.seed, i + 2130) - 0.5) * len * 0.9
            local bx, by, tx, ty, ox, oy
            if e == 0 then bx, by, tx, ty, ox, oy = p * sw, 0, p * sw + skew, len, wd, 0
            elseif e == 1 then bx, by, tx, ty, ox, oy = p * sw, sh, p * sw + skew, sh - len, wd, 0
            elseif e == 2 then bx, by, tx, ty, ox, oy = 0, p * sh, len, p * sh + skew, 0, wd
            else bx, by, tx, ty, ox, oy = sw, p * sh, sw - len, p * sh + skew, 0, wd end
            cpoly(L.FROST, (60 + 90 * L.rnd(v.seed, i + 2170)) * env, bx - ox, by - oy, bx + ox, by + oy, tx, ty)
            line(bx, by, tx, ty, C_WHITE, 210 * env)
        end
        for i = 1, 60 do
            local e = floor(L.rnd(v.seed, i) * 4)
            local d = L.rnd(v.seed, i + 300) * size * 0.8
            local px = (e < 2) and L.rnd(v.seed, i + 600) * sw or (e == 2 and d or sw - d)
            local py = (e == 0) and d or (e == 1 and sh - d or L.rnd(v.seed, i + 900) * sh)
            local s = 1 + floor(L.rnd(v.seed, i + 1200) * 3)
            rect(px, py, s, s, L.FROST, (80 + 90 * L.rnd(v.seed, i + 1500)) * env)
        end
    elseif style == 6 then
        local t = max(2, round(settings.vigSize / 2))
        local n = 28
        for i = 1, n do
            local x0, x1 = floor((i - 1) * sw / n), floor(i * sw / n)
            local y0, y1 = floor((i - 1) * sh / n), floor(i * sh / n)
            rect(x0, 0, x1 - x0 + 1, t, L.fxColor(kill, (i - 0.5) / n * 0.25), a)
            rect(x0, sh - t, x1 - x0 + 1, t, L.fxColor(kill, 0.75 - (i - 0.5) / n * 0.25), a)
            rect(0, y0, t, y1 - y0 + 1, L.fxColor(kill, 1 - (i - 0.5) / n * 0.25), a)
            rect(sw - t, y0, t, y1 - y0 + 1, L.fxColor(kill, 0.25 + (i - 0.5) / n * 0.25), a)
        end
        L.edges(size * 0.6, a * 0.5, kill)
        L.brackets(t + 8, 70 * easeOutBack(el / 0.2), t + 2, C_WHITE, a)
    elseif style == 7 then
        L.edges(size * 0.7, a * 0.6, kill)
        for k = 0, 2 do
            local e = easeOut((el - k * 0.09) / (v.len * 0.8))
            if e > 0 then
                local r = e * max(sw, sh) * 0.62
                L.thickRing(sw / 2, sh / 2, r, 22, L.fxColor(kill, k * 0.2), 50 * (1 - e) * v.power)
                L.thickRing(sw / 2, sh / 2, r, 6, L.fxColor(kill, k * 0.2 + 0.3), 150 * (1 - e) * v.power)
                ring(sw / 2, sh / 2, r, C_WHITE, 200 * (1 - e) * v.power, 48)
            end
        end
    elseif style == 8 then
        local off = 10 * env
        edgeFade("left", size, L.RED_FX, a)
        edgeFade("left", size * 0.55 + off, L.CYAN, a * 0.5)
        edgeFade("right", size, L.CYAN, a)
        edgeFade("right", size * 0.55 + off, L.RED_FX, a * 0.5)
        edgeFade("top", size * 0.8, L.MAGENTA, a * 0.75)
        edgeFade("bottom", size * 0.8, L.CYAN, a * 0.75)
    elseif style == 9 then
        L.edges(size * 0.8, a * 0.7, kill)
        local cx, cy = sw / 2, sh / 2
        local R = sqrt(sw * sw + sh * sh) / 2
        local ang = el * 5
        for k = 0, 14 do
            local aa = ang - k * 0.035
            line(cx, cy, cx + cos(aa) * R, cy + sin(aa) * R, L.fxColor(kill, k / 14), (200 - k * 13) * env * v.power)
        end
    elseif style == 10 then
        local ph = el % 0.85
        local beat = max(0, 1 - ph / 0.16) + 0.7 * max(0, 1 - abs(ph - 0.26) / 0.12)
        L.edges(size * (0.8 + 0.4 * beat), a * (0.35 + 0.65 * beat), kill)
    elseif style == 11 then
        L.edges(size, a * 0.75, kill)
        L.screenSpace()
        local frame = floor(el * 14)
        for b = 1, 3 do
            local side = floor(L.rnd(v.seed + frame, b) * 4)
            local px, py
            if side == 0 then px, py = L.rnd(v.seed + frame, b + 5) * sw, 0
            elseif side == 1 then px, py = L.rnd(v.seed + frame, b + 5) * sw, sh
            elseif side == 2 then px, py = 0, L.rnd(v.seed + frame, b + 5) * sh
            else px, py = sw, L.rnd(v.seed + frame, b + 5) * sh end
            local dx = (side == 2) and 1 or (side == 3 and -1 or 0)
            local dy = (side == 0) and 1 or (side == 1 and -1 or 0)
            for s = 1, 7 do
                local nx = px + dx * 26 + (L.rnd(v.seed + frame, b * 10 + s) - 0.5) * 50
                local ny = py + dy * 26 + (L.rnd(v.seed + frame, b * 20 + s) - 0.5) * 50
                tline(px, py, nx, ny, 6, L.fxColor(kill, s / 7), 90 * env)
                tline(px, py, nx, ny, 2, C_WHITE, 230 * env)
                px, py = nx, ny
            end
        end
    elseif style == 12 then
        local k = sin(u * pi)
        L.edges(size * (0.3 + 1.1 * easeOut(u * 1.4)), 235 * settings.vigInt / 100 * v.power * k, kill)
    elseif style == 13 then
        L.edges(size * 0.8, a * 0.7, kill)
        edgeFade("bottom", size * 1.3, L.fxColor(kill, 0.5), a * 0.6)
        for i = 1, 40 do
            local x = L.rnd(v.seed, i) * sw
            local rise = (el * (90 + 120 * L.rnd(v.seed, i + 70))) % (sh * 0.45)
            local y = sh - rise + sin(el * 3 + i) * 8
            local fl = 0.6 + 0.4 * sin(el * 12 + i)
            disc(x, y, 4, L.fxColor(kill, L.rnd(v.seed, i + 140)), 40 * fl * env)
            disc(x, y, 1.6, L.EMBER, 230 * fl * env)
        end
    else
        local br = 0.85 + 0.15 * sin(el * 10)
        L.edges(size * 1.8, a * 0.38, kill)
        L.edges(size * 0.5 * br, a, kill)
        local cr = size * 1.25
        disc(0, 0, cr, L.fxColor(kill, 0.9), a * 0.3)
        disc(sw, 0, cr, L.fxColor(kill, 0.15), a * 0.3)
        disc(sw, sh, cr, L.fxColor(kill, 0.4), a * 0.3)
        disc(0, sh, cr, L.fxColor(kill, 0.65), a * 0.3)
    end
end
L.CYAN, L.MAGENTA, L.FROST, L.EMBER = { 0, 255, 255 }, { 255, 0, 170 }, { 235, 245, 255 }, { 255, 190, 90 }

-- extra effects ------------------------------------------------
L.kf = nil

function L.kfStart(kill)
    local style = settings.fxExtra
    if style <= 1 then return end
    if style == 2 then style = 3 + math.random(0, 6) end
    local sw, sh = draw.GetScreenSize()
    local k = min(sw, sh) / 1080
    local st = { style = style, t0 = now(), kill = kill, sw = sw, sh = sh, k = k,
                 dur = kill and max(0.38, settings.vigStay / 1000 * 0.9) or 0.42, seed = math.random() * 1000 }
    if style == 4 then
        st.blobs = {}
        for i = 1, 6 do
            local side = math.random(1, 4)
            local x = (side == 1) and math.random() * 0.16 * sw or (side == 2 and sw - math.random() * 0.16 * sw or (0.05 + math.random() * 0.9) * sw)
            local y = (side == 3) and math.random() * 0.18 * sh or (side == 4 and sh - math.random() * 0.18 * sh or (0.05 + math.random() * 0.9) * sh)
            local b = { x = x, y = y, r = (55 + math.random() * 80) * k, sats = {}, drips = {} }
            for j = 1, 9 do b.sats[j] = { (math.random() * 3.4 - 1.7) * b.r, (math.random() * 3.4 - 1.7) * b.r, (6 + math.random() * 20) * k } end
            for j = 1, 3 do b.drips[j] = { (math.random() * 1.2 - 0.6) * b.r, (5 + math.random() * 7) * k, 0.7 + math.random() * 0.9 } end
            st.blobs[i] = b
        end
    elseif style == 5 then
        st.slashes = {}
        for i = 1, 3 do
            local ang = ((math.random() * 76 - 38) + ((i % 2 == 1) and 0 or 180)) * 0.01745
            local px, py, Ln = sw / 2 + (math.random() * 0.36 - 0.18) * sw, sh / 2 + (math.random() * 0.28 - 0.14) * sh, 1.5 * sw
            st.slashes[i] = { sx = px - cos(ang) * Ln / 2, sy = py - sin(ang) * Ln / 2, dx = cos(ang), dy = sin(ang), L = Ln }
        end
    elseif style == 6 then
        st.ox, st.oy = sw / 2 + (math.random() * 240 - 120) * k, sh / 2 + (math.random() * 180 - 90) * k
        st.cracks = {}
        for i = 1, 13 do
            local ang = (i * 27.7 + math.random() * 18 - 9) * 0.01745
            local x, y, total, maxL = st.ox, st.oy, 0, (0.22 + math.random() * 0.33) * sw
            local pts = { x, y }
            while total < maxL do
                ang = ang + math.random() * 0.8 - 0.4
                local sl = (28 + math.random() * 52) * k
                x, y, total = x + cos(ang) * sl, y + sin(ang) * sl, total + sl
                pts[#pts + 1] = x; pts[#pts + 1] = y
                if math.random(1, 100) <= 18 then
                    local bx, by, ba = x, y, ang + math.random() * 2.2 - 1.1
                    local bp = { bx, by }
                    for _ = 1, 3 do
                        ba = ba + math.random() * 0.8 - 0.4
                        local bl = (18 + math.random() * 27) * k
                        bx, by = bx + cos(ba) * bl, by + sin(ba) * bl
                        bp[#bp + 1] = bx; bp[#bp + 1] = by
                    end
                    st.cracks[#st.cracks + 1] = bp
                end
            end
            st.cracks[#st.cracks + 1] = pts
        end
    end
    L.kf = st
end

function L.drawExtraEffect()
    local st = L.kf
    if not st then return end
    local el = now() - st.t0
    if el > st.dur then L.kf = nil; return end
    L.screenSpace()
    local W, H, k = st.sw, st.sh, st.k
    local cx, cy = W / 2, H / 2
    local t = min(1, el / st.dur)
    local fade = (t < 0.55) and 1 or max(0, 1 - (t - 0.55) / 0.45)
    local c1, c2 = L.fxColor(st.kill, 0.15 + t * 0.2), L.fxColor(st.kill, 0.6 + t * 0.2)
    c1 = { c1[1], c1[2], c1[3] }
    local keep = ALPHA
    ALPHA = keep * settings.vigInt / 100 * 1.15
    local s = st.style

    if s == 3 then
        local pop = easeOut(el / 0.14)
        local gap, len = (16 + 26 * easeOut(t * 1.4)) * k, (36 + 10 * (1 - pop)) * k
        for dx = -1, 1, 2 do
            for dy = -1, 1, 2 do
                local x1, y1 = cx + dx * gap * 0.707, cy + dy * gap * 0.707
                local x2, y2 = x1 + dx * len * 0.707, y1 + dy * len * 0.707
                tline(x1, y1, x2, y2, 15 * k, c1, 130 * fade)
                tline(x1, y1, x2, y2, 5.5 * k, (el < 0.16) and c1 or C_WHITE, 255 * fade)
            end
        end
        L.thickRing(cx, cy, (18 + 120 * easeOut(el / 0.32)) * k, 3 * k, c2, 170 * (1 - easeOut(el / 0.32)))
        for i = 1, 10 do
            local a, r = i * 0.628 + 0.3, (30 + 150 * easeOut(el / 0.38)) * k
            disc(cx + cos(a) * r, cy + sin(a) * r, 3 * k * (1 - t) + 0.5, C_WHITE, 230 * (1 - t))
        end
    elseif s == 4 then
        local g = easeOut(el / 0.09)
        local cb = (settings.vigColor == 2 or settings.vigColor == 1) and L.BLOOD or mix(c1, C_BLACK, 0.4)
        cb = { cb[1], cb[2], cb[3] }
        for _, b in ipairs(st.blobs) do
            for _, sp in ipairs(b.sats) do disc(b.x + sp[1] * g, b.y + sp[2] * g, sp[3] * g, cb, 205 * fade) end
            disc(b.x, b.y, b.r * g, cb, 215 * fade)
            for _, dr in ipairs(b.drips) do
                local Ld = b.r * (0.3 + 1.8 * t * dr[3])
                roundRect(b.x + dr[1] - dr[2] / 2, b.y + b.r * 0.2, dr[2], Ld, dr[2] / 2, cb, 205 * fade)
                disc(b.x + dr[1], b.y + b.r * 0.2 + Ld, dr[2] * 0.75, cb, 205 * fade)
            end
            disc(b.x - b.r * 0.3, b.y - b.r * 0.3, b.r * 0.22 * g, C_WHITE, 36 * fade)
        end
    elseif s == 5 then
        for j, sl in ipairs(st.slashes) do
            local p = easeOut((el - (j - 1) * 0.055) / 0.12)
            if p > 0 then
                local ex, ey = sl.sx + sl.dx * sl.L * p, sl.sy + sl.dy * sl.L * p
                local mx, my, nx, ny = (sl.sx + ex) / 2, (sl.sy + ey) / 2, -sl.dy, sl.dx
                for layer = 1, 3 do
                    local w = (layer == 1 and 30 or (layer == 2 and 14 or 5)) * k
                    local c = (layer == 1) and c1 or (layer == 2 and c2 or C_WHITE)
                    local a = (layer == 1) and 60 or (layer == 2 and 150 or 255)
                    cpoly(c, a * fade, sl.sx, sl.sy, mx + nx * w, my + ny * w, ex, ey, mx - nx * w, my - ny * w)
                end
            end
        end
    elseif s == 6 then
        if el < 0.13 then rect(0, 0, W, H, C_WHITE, 70 * (1 - el / 0.13)) end
        local p = easeOut(el / 0.15)
        L.thickRing(st.ox, st.oy, (10 + 40 * p) * k, 3 * k, c1, 200 * fade)
        for _, cr in ipairs(st.cracks) do
            local n = floor(#cr / 2) - 1
            local upto = n * p
            for i = 1, n do
                if i > upto + 1 then break end
                local f = min(1, upto - (i - 1))
                local x1, y1 = cr[2 * i - 1], cr[2 * i]
                local x2, y2 = x1 + (cr[2 * i + 1] - x1) * f, y1 + (cr[2 * i + 2] - y1) * f
                L.seg(x1, y1, x2, y2, 7 * k, c1, 80 * fade)
                L.seg(x1, y1, x2, y2, 2 * k, C_WHITE, 230 * fade)
            end
        end
    elseif s == 7 then
        local frame = floor(el / 0.045)
        local ro = sqrt(W * W + H * H) / 2 + 20
        local ia = min(1, el / 0.06) * fade
        for i = 1, 56 do
            local ang = L.rnd(st.seed + frame, i) * 6.2832
            local ri = (0.25 + 0.17 * L.rnd(st.seed + frame, i + 100)) * min(W, H)
            local wd = (4 + 11 * L.rnd(st.seed + frame, i + 200)) * k
            local dx, dy = cos(ang), sin(ang)
            cpoly((i % 3 == 0) and c1 or C_WHITE, ((i % 3 == 0) and 170 or 150) * ia,
                  cx + dx * ri, cy + dy * ri, cx + dx * ro - dy * wd, cy + dy * ro + dx * wd, cx + dx * ro + dy * wd, cy + dy * ro - dx * wd)
        end
        disc(cx, cy, 70 * k * (1 - t), C_WHITE, 90 * max(0, 1 - t * 2))
    elseif s == 8 then
        for i = 1, 3 do
            local e = easeOut((el - (i - 1) * 0.09) / (st.dur * 0.8))
            if e > 0 then
                local R = e * 0.75 * W
                L.thickRing(cx, cy, R, 26 * k, c1, 70 * (1 - e))
                L.thickRing(cx, cy, R, 9 * k, c2, 160 * (1 - e))
                L.thickRing(cx, cy, R, 2.5 * k, C_WHITE, 220 * (1 - e))
            end
        end
        disc(cx, cy, 90 * k * (1 - t), C_WHITE, 130 * max(0, 1 - t * 3))
    elseif s == 9 then
        local ins = (14 + 60 * (1 - easeOut(el / 0.16))) * k
        for i = 1, 6 do
            local j = i * 2
            roundRectLine(ins - j, ins - j, W - 2 * ins + 2 * j, H - 2 * ins + 2 * j, 18 * k + j, c1, (80 - i * 12) * fade)
        end
        roundRectLine(ins, ins, W - 2 * ins, H - 2 * ins, 18 * k, C_WHITE, 210 * fade)
        local bl, bi = 80 * k, ins + 10 * k
        for q = 1, 4 do
            local qx = (q == 1 or q == 3) and bi or W - bi
            local qy = (q <= 2) and bi or H - bi
            local sx = (q == 1 or q == 3) and 1 or -1
            local sy = (q <= 2) and 1 or -1
            tline(qx, qy, qx + sx * bl, qy, 5 * k, c2, 255 * fade)
            tline(qx, qy, qx, qy + sy * bl, 5 * k, c2, 255 * fade)
        end
        local sy = H * easeOut(el / (st.dur * 0.7))
        color(c1, 90 * fade)
        rawColor(round(c1[1]), round(c1[2]), round(c1[3]), 255)
        draw.FilledRectFade(0, round(sy - 40 * k), W, round(sy), 0, clamp(round(90 * fade * ALPHA), 0, 255), false)
    end
    ALPHA = keep
end

-- screen shake: only the picture moves, never where you aim
L.SHAKE_STYLES = { "Jitter", "Punch", "Horizontal", "Vertical", "Earthquake", "Recoil" }
L.shake = { t0 = -99, dur = 0, amt = 0 }

function L.shakeStart(kill)
    if not settings.shakeOn then return end
    if not kill and not settings.shakeOnHit then return end
    L.shake.t0 = now()
    L.shake.dur = kill and 0.45 or 0.22
    L.shake.amt = settings.shakeAmt / 100 * (kill and 2.6 or 1.2)
end

function L.onRenderView(view)
    local sh = L.shake
    local el = now() - sh.t0
    if el < 0 or el > sh.dur or not view or not view.angles then return end
    local u = el / sh.dur
    local env = (1 - u) ^ 2
    local a = sh.amt * env
    local st = settings.shakeStyle
    local dp, dy, dr = 0, 0, 0
    if st == 1 then dp, dy = (math.random() - 0.5) * 2 * a, (math.random() - 0.5) * 2 * a
    elseif st == 2 then dp = -a * 1.6 * (1 - u) * cos(u * 9)
    elseif st == 3 then dy = a * 1.4 * sin(el * 55)
    elseif st == 4 then dp = a * 1.4 * sin(el * 55)
    elseif st == 5 then dp, dy, dr = (math.random() - 0.5) * 3 * a, (math.random() - 0.5) * 3 * a, (math.random() - 0.5) * 2 * a
    else dp = -a * 2 * max(0, 1 - el / 0.08) + a * 0.6 * sin(el * 30) * env end
    local ang = view.angles
    view.angles = EulerAngles(ang.x + dp, ang.y + dy, ang.z + dr)
end

-- one call for everything a hit or a kill sets off
function L.hitEffects(kill)
    local v = L.vfx
    if settings.vigOn and ((kill and settings.vigKill) or (not kill and settings.vigHit)) then
        if kill or not (v.kill and now() - v.t0 < v.len * 0.6) then
            v.t0, v.kill, v.seed = now(), kill, math.random() * 1000
            v.len = kill and max(0.2, settings.vigStay / 1000) or max(0.18, settings.vigStay / 1000 * 0.4)
            v.power = kill and 1 or 0.55
        end
    end
    if (kill and settings.fxOnKill) or (not kill and settings.fxOnHit) then L.kfStart(kill) end
    L.shakeStart(kill)
end

---------------------------------------------------------------------------
-- 8j. lmaobox HUD
---------------------------------------------------------------------------
L.HUD_STYLES = { "Destiny", "Skeet", "Neverlose", "Radiance", "Mercury", "Gamesense", "Silentium", "Royal", "Liquid glass", "Moon", "OneShot" }
L.BORDERS = { "Off", "Plain", "Accent", "Animated gradient", "Rainbow" }
L.GRADS = { "Off", "Accent Flow", "Aurora", "Sunset", "Ocean", "Fire", "Rainbow", "Candy", "Mono" }
F.sk = draw.CreateFont("Verdana", 12, 400, FONTFLAG_ANTIALIAS | FONTFLAG_DROPSHADOW)
F.nlT = draw.CreateFont("Calibri", 18, 700, FONTFLAG_ANTIALIAS)
F.nlR = draw.CreateFont("Calibri", 16, 400, FONTFLAG_ANTIALIAS)
F.gs = draw.CreateFont("Segoe UI", 18, 800, FONTFLAG_ANTIALIAS)
F.gsI = draw.CreateFont("Segoe UI Symbol", 17, 400, FONTFLAG_ANTIALIAS)
F.script = draw.CreateFont("Segoe Script", 19, 700, FONTFLAG_ANTIALIAS)

-- key codes -> short names
L.keyNames = nil
function L.keyName(code)
    if type(code) ~= "number" or code <= 0 then return "-" end
    if not L.keyNames then
        L.keyNames = {}
        pcall(function()
            for k, v in pairs(_G) do
                if type(v) == "number" and type(k) == "string" and (k:find("^KEY_") or k:find("^MOUSE_")) then
                    local n = k:gsub("^KEY_", ""):gsub("^MOUSE_", "M")
                    if not L.keyNames[v] or #n < #L.keyNames[v] then L.keyNames[v] = n end
                end
            end
        end)
    end
    return L.keyNames[code] or tostring(code)
end

-- the gradient a HUD / notification uses
function L.gradStops(gi) return (gi and gi > 1) and logoStops(gi - 1) or nil end

-- a 2px border whose colour runs around the box
function L.gbSeg(px, py, pw, ph, pos, stops, per, phase) rect(px, py, pw, ph, sampleStops(stops, pos / per + phase), 230) end
function L.gbCor(cx, cy, which, pos, stops, per, phase, r)
    color(sampleStops(stops, pos / per + phase), 230)
    local S = pow2(r)
    local tex = cornerTex(r, true, which).id
    if which == 1 then draw.TexturedRect(tex, round(cx), round(cy), round(cx + S), round(cy + S))
    elseif which == 2 then draw.TexturedRect(tex, round(cx - S), round(cy), round(cx), round(cy + S))
    elseif which == 3 then draw.TexturedRect(tex, round(cx), round(cy - S), round(cx + S), round(cy))
    else draw.TexturedRect(tex, round(cx - S), round(cy - S), round(cx), round(cy)) end
end

function L.gradBorder(x, y, w, h, r, stops, phase)
    local per = 2 * (w + h)
    local n = 10
    local seg = L.gbSeg
    for i = 0, n - 1 do
        local sx = x + r + (w - 2 * r) * i / n
        local sl = (w - 2 * r) / n + 1
        seg(sx, y, sl, 2, (sx - x), stops, per, phase)
        seg(sx, y + h - 2, sl, 2, w + h + (x + w - sx), stops, per, phase)
        local sy = y + r + (h - 2 * r) * i / n
        local hl = (h - 2 * r) / n + 1
        seg(x + w - 2, sy, 2, hl, w + (sy - y), stops, per, phase)
        seg(x, sy, 2, hl, 2 * w + h + (y + h - sy), stops, per, phase)
    end
    -- the corners in the colour of the spot they sit
    if r >= 1 then
        L.gbCor(x, y, 1, 0, stops, per, phase, r); L.gbCor(x + w, y, 2, w, stops, per, phase, r)
        L.gbCor(x, y + h, 3, 2 * w + h, stops, per, phase, r); L.gbCor(x + w, y + h, 4, w + h, stops, per, phase, r)
    end
end
-- border by setting
function L.styledBorder(bstyle, gi, x, y, w, h, r)
    if bstyle == 2 then roundRectLine(x, y, w, h, r, T.border)
    elseif bstyle == 3 then roundRectLine(x, y, w, h, r, accent(), 210)
    elseif bstyle == 4 then L.gradBorder(x, y, w, h, r, L.gradStops(gi) or logoStops(1), now() * 0.3)
    elseif bstyle == 5 then L.gradBorder(x, y, w, h, r, logoStops(6), now() * 0.3) end
end

-- the rows the HUD shows
L.hudRows = {}
function L.collectHud()
    local rows, n = L.hudRows, 0
    for _, f in ipairs(L.FEATURES) do
        local on = featOn[f[1]]
        if on ~= nil and (on or not settings.flCompact) then
            n = n + 1
            local r = rows[n] or {}
            rows[n] = r
            r.name, r.on, r.key, r.icon = f[1], on, L.featKeys[f[1]], f[4] or "●"
        end
    end
    for i = n + 1, #rows do rows[i] = nil end
    return rows
end

function L.hudTail(r)
    if settings.flKeys and r.key then return r.key end
    return r.on and "on" or "off"
end

function L.drawHud()
    local rows = L.collectHud()
    local sw = draw.GetScreenSize()
    local st = settings.flStyle
    local gst = L.gradStops(settings.flGrad)
    local acc = accent()
    local t = now()
    local function rowCol(i, on)
        if not on then return nil end
        return gst and sampleStops(gst, t * 0.12 + i * 0.11) or acc
    end

    if st == 2 then
        local cw, cnt = 160, max(1, #rows)
        local ch = 19 + 15 * cnt
        local x, y = draggable("fl", sw - cw - 14, 60, cw, ch)
        local function out(ox, oy, w, h, c, s) rect(ox, oy, w, s, c); rect(ox, oy + h - s, w, s, c); rect(ox, oy + s, s, h - 2 * s, c); rect(ox + w - s, oy + s, s, h - 2 * s, c) end
        out(x, y, cw, ch, L.SK1, 1); out(x + 1, y + 1, cw - 2, ch - 2, L.SK2, 1); out(x + 2, y + 2, cw - 4, ch - 4, L.SK3, 3); out(x + 5, y + 5, cw - 10, ch - 10, L.SK2, 1)
        rect(x + 6, y + 6, cw - 12, ch - 12, L.SKBG, 245)
        local w1 = floor((cw - 14) / 2)
        color(L.SKB, 255); draw.FilledRect(x + 7, y + 7, x + 7 + w1, y + 8)
        rawColor(L.SKP[1], L.SKP[2], L.SKP[3], 255); draw.FilledRectFade(x + 7, y + 7, x + 7 + w1, y + 8, 0, 255, true)
        color(L.SKP, 255); draw.FilledRect(x + 7 + w1, y + 7, x + cw - 7, y + 8)
        rawColor(L.SKY[1], L.SKY[2], L.SKY[3], 255); draw.FilledRectFade(x + 7 + w1, y + 7, x + cw - 7, y + 8, 0, 255, true)
        if #rows == 0 then text(F.sk, "nothing running", x + 10, y + 11, 15, L.SKG)
        else
            for i, r in ipairs(rows) do
                local ry = y + 11 + (i - 1) * 15
                text(F.sk, r.name, x + 10, ry, 15, r.on and C_WHITE or L.SKG)
                local tail = "[" .. L.hudTail(r) .. "]"
                text(F.sk, tail, x + cw - 10 - textW(F.sk, tail), ry, 15, r.on and L.SKON or L.SKOFF)
            end
        end

    elseif st == 3 then
        local bw, cnt = 170, max(1, #rows)
        local bh = 24 + 20 * (cnt - 1) + 4
        local x, y = draggable("fl", sw - bw - 14, 60, bw, 25 + bh)
        rect(x, y, bw, 25, L.NLBAR, 200)
        local ix, iy = x + 7, y + 8
        roundRectLine(ix, iy, 16, 10, 2, L.NLBLUE)
        for i = 0, 2 do rect(ix + 3 + i * 4, iy + 3, 2, 2, L.NLBLUE) end
        rect(ix + 4, iy + 6, 8, 2, L.NLBLUE)
        text(F.nlT, "lmaobox", x + 30, y, 25, C_WHITE)
        rect(x, y + 25, bw, bh, L.NLBAR, 120)
        rect(x, y + 25, bw, bh, L.NLLIST, 15)
        if #rows == 0 then text(F.nlR, "nothing running", x + 6, y + 27, 18, L.NLDIM)
        else
            for i, r in ipairs(rows) do
                local ry = y + 27 + (i - 1) * 20
                text(F.nlR, r.name, x + 6, ry, 18, r.on and C_WHITE or L.NLDIM)
                local tail = L.hudTail(r)
                text(F.nlR, tail, x + bw - 7 - textW(F.nlR, tail), ry, 18, r.on and C_WHITE or L.NLDIM2)
            end
        end

    elseif st == 4 then
        local maxW = chipW("✦", { { "DESTINY" } })
        for _, r in ipairs(rows) do
            r.parts = r.parts or { { "", RD.dim }, { "", RD.dim } }
            r.parts[1][1], r.parts[2][1] = r.name, L.hudTail(r)
            maxW = max(maxW, chipW(r.icon, r.parts))
        end
        local h = 22 + max(1, #rows) * 26 + 4
        local x, y = draggable("fl", sw - maxW - 14, 60, maxW, h)
        local hw = chip(x, y, "✦", { { "DESTINY", RD.violet } }, 22)
        L.styledBorder(settings.flBorder, settings.flGrad, x, y, hw, 22, 7)
        if #rows == 0 then chip(x, y + 26, nil, { { "nothing running", RD.dim } }, 22) end
        for i, r in ipairs(rows) do
            local ry = y + i * 26
            local tt = anim("rdh" .. r.name, r.on and 1 or 0, 12)
            local ac = rowCol(i, true) or RD.violet
            r.parts[1][2], r.parts[2][2] = mix(RD.dim, RD.white, tt), mix(RD.dim, ac, tt)
            local w = chip(x, ry, r.icon, r.parts, 22)
            L.styledBorder(settings.flBorder, settings.flGrad, x, ry, w, 22, 7)
            if tt > 0.02 then roundRect(x + 1.5, ry + 11 - 7 * tt, 2.5, 14 * tt, 1, ac, 255 * tt) end
        end

    elseif st == 5 then
        local bw = 190
        local bh = 40 + max(1, #rows) * 21 + 6
        local x, y = draggable("fl", sw - bw - 14, 60, bw, bh)
        mercuryBox(x, y, bw, bh, 9)
        L.styledBorder(settings.flBorder, settings.flGrad, x, y, bw, bh, 9)
        local tw = textW(F.rd, "lmaobox")
        local tx = x + (bw - tw - 18) / 2
        text(F.icon, "✦", tx, y + 3, 22, MC.val)
        text(F.rd, "lmaobox", tx + 18, y + 3, 22, MC.text)
        rect(x + 8, y + 28, bw - 16, 1, MC.border, 150)
        if #rows == 0 then text(F.small, "nothing running", x + 10, y + 34, 19, MC.dim) end
        for i, r in ipairs(rows) do
            local ry = y + 34 + (i - 1) * 21
            text(F.small, r.name, x + 10, ry, 19, r.on and MC.text or MC.dim)
            local tail = L.hudTail(r)
            text(F.small, tail, x + bw - 10 - textW(F.small, tail), ry, 19, r.on and (rowCol(i, true) or MC.val) or L.MCOFF)
        end

    elseif st == 6 then
        local maxW = 60
        for _, r in ipairs(rows) do
            local s = r.name:upper() .. (settings.flKeys and r.key and (" [" .. r.key .. "]") or "")
            maxW = max(maxW, textW(F.gs, s) + 50)
        end
        local h = max(1, #rows) * 26 + 6
        local x, y = draggable("fl", sw - maxW - 14, 60, maxW, h)
        if #rows == 0 then text(F.gs, "NOTHING RUNNING", x + 4, y, 24, L.GSDIM) end
        for i, r in ipairs(rows) do
            local ry = y + 3 + (i - 1) * 26
            local col = r.on and (gst and rowCol(i, true) or L.GSON) or L.GSDIM
            local s = r.name:upper() .. (settings.flKeys and r.key and (" [" .. r.key .. "]") or "")
            for o = 1, 4 do
                local ox = (o == 1) and -1 or (o == 2 and 1 or (o == 3 and 1 or 2))
                local oy = (o <= 2) and 0 or (o == 3 and 1 or 2)
                text(F.gs, s, x + 22 + ox, ry + oy, 24, C_BLACK, 175)
                text(F.gsI, r.icon, x + ox, ry + oy, 24, C_BLACK, 175)
            end
            text(F.gsI, r.icon, x, ry, 24, col)
            text(F.gs, s, x + 22, ry, 24, col)
            if r.on then
                local scx, scy = x + 22 + textW(F.gs, s) + 13, ry + 12
                ring(scx, scy, 6, C_BLACK, 120, 24)
                local a0 = t * 7
                for j = 0, 8 do
                    local aa = a0 + j * 0.52
                    disc(scx + cos(aa) * 6, scy + sin(aa) * 6, 1.4, col, 255)
                end
            end
        end

    elseif st >= 8 then
        local p = L.palFor(st, settings.flGrad)
        local W, head = 204, L.PH[st] or 32
        local H = head + max(1, #rows) * 25 + 10
        local x, y = draggable("fl", sw - W - 14, 60, W, H)
        L.panelBg(st, x, y, W, H, "lmaobox", settings.flBorder, settings.flGrad)
        if #rows == 0 then L.pt(p.f, "nothing running", x + p.pad, y + head + 4, 25, p.dim) end
        for i, r in ipairs(rows) do
            local ry = y + head + 4 + (i - 1) * 25
            local tt = anim("gh" .. r.name, r.on and 1 or 0, 12)
            local col = rowCol(i, true) or p.c
            if tt > 0.02 then disc(x + p.pad + 4, ry + 12, 6, col, 60 * tt) end
            disc(x + p.pad + 4, ry + 12, 3.5, mix(p.dim, col, tt))
            L.pt(p.f, r.name, x + p.pad + 17, ry, 25, mix(p.dim, p.txt, tt))
            local tail = L.hudTail(r)
            local tw = textW(F.tiny, tail) + 16
            roundRect(x + W - p.pad - tw, ry + 4, tw, 17, 8, p.track, 210)
            textC(F.tiny, tail, x + W - p.pad - tw / 2, ry + 4, 17, r.on and col or p.dim)
        end

    elseif st == 7 then
        local bw = 200
        local bh = 44 + max(1, #rows) * 26 + 6
        local x, y = draggable("fl", sw - bw - 14, 60, bw, bh)
        local ac = gst and sampleStops(gst, t * 0.12) or accent()
        for i = 1, 4 do
            local e = i * 1.7
            roundRectLine(x - e, y - e, bw + 2 * e, bh + 2 * e, 10 + e, ac, 46 - i * 10)
        end
        roundRect(x, y, bw, bh, 10, L.SLBG, 232)
        roundRectLine(x, y, bw, bh, 10, C_WHITE, 26)
        rect(x + 10, y, bw - 20, 1, ac, 160)
        L.styledBorder(settings.flBorder, settings.flGrad, x, y, bw, bh, 10)
        text(F.script, "destiny", x + 14, y + 6, 30, mix(ac, C_WHITE, 0.2))
        text(F.icon, "★", x + 14 + textW(F.script, "destiny") + 2, y + 4, 16, L.SLSTAR, 230)
        if #rows == 0 then text(F.small, "nothing running", x + 14, y + 44, 22, SL.dim) end
        for i, r in ipairs(rows) do
            local ry = y + 42 + (i - 1) * 26
            local tt = anim("slh" .. r.name, r.on and 1 or 0, 12)
            if tt > 0.02 then
                color(ac, 255)
                rawColor(round(ac[1]), round(ac[2]), round(ac[3]), 255)
                draw.FilledRectFade(round(x + 6), round(ry), round(x + bw * 0.7), round(ry + 22), clamp(round(70 * tt * ALPHA), 0, 255), 0, true)
                rect(x + 6, ry + 3, 2, 16, ac, 255 * tt)
            end
            text(F.small, r.name, x + 16, ry, 22, mix(SL.dim, SL.text, tt))
            if settings.flKeys and r.key then text(F.tiny, r.key, x + bw - 64 - textW(F.tiny, r.key), ry, 22, SL.dim) end
            local fx, fy = x + bw - 50, ry + 4
            if tt > 0.02 then roundRect(fx - 3, fy - 3, 40, 20, 10, ac, 40 * tt) end
            roundRect(fx, fy, 34, 14, 7, mix(SL.line, ac, tt))
            disc(fx + 7 + 20 * tt, fy + 7, 5, C_WHITE)
        end

    else
        local W = 200
        local n = max(1, #rows)
        local H = 12 + n * 27 + 10
        local x, y = draggable("fl", sw - W - 14, 60, W, H)
        roundRect(x - 2, y + 2, W + 4, H, 18, C_BLACK, 45)
        roundRect(x, y, W, H, 16, T.card, 240)
        if settings.flBorder == 1 then roundRectLine(x, y, W, H, 16, T.border)
        else L.styledBorder(settings.flBorder, settings.flGrad, x, y, W, H, 16) end
        if #rows == 0 then textC(F.small, "nothing running", x + W / 2, y + 12, 23, T.muted) end
        for i, r in ipairs(rows) do
            local ry = y + 12 + (i - 1) * 27
            local tt = anim("dh" .. r.name, r.on and 1 or 0, 12)
            local col = rowCol(i, true)
            if tt > 0.01 then roundRect(x + 8, ry, W - 16, 23, 9, col, 40 * tt) end
            local cx2, cy2 = x + 23, ry + 11.5
            if r.on then disc(cx2, cy2, 4 + 3.2 * (0.5 + 0.5 * sin(t * 3.8 + i)), col, 55) end
            disc(cx2, cy2, 3.6, T.off)
            if tt > 0.01 then disc(cx2, cy2, 3.6, col, 255 * tt) end
            local nc = gst and sampleStops(gst, t * 0.12 + i * 0.11) or T.text
            text(F.ui, r.name, x + 37, ry, 23, nc, 150 + 105 * tt)
            if settings.flKeys and r.key then
                text(F.small, r.key, x + W - 16 - textW(F.small, r.key), ry, 23, mix(T.muted, T.text2, tt))
            elseif tt > 0.05 then
                text(F.small, "ON", x + W - 16 - textW(F.small, "ON"), ry, 23, col, 255 * tt)
            end
        end
    end
end
L.SK1, L.SK2, L.SK3, L.SKBG = { 18, 18, 18 }, { 62, 62, 62 }, { 44, 44, 44 }, { 19, 19, 19 }
L.SKB, L.SKP, L.SKY, L.SKG, L.SKON, L.SKOFF = { 59, 175, 222 }, { 202, 70, 205 }, { 201, 227, 58 }, { 150, 150, 150 }, { 126, 195, 12 }, { 120, 120, 120 }
L.NLBAR, L.NLBLUE, L.NLLIST, L.NLDIM, L.NLDIM2 = { 11, 11, 20 }, { 0, 130, 255 }, { 200, 200, 200 }, { 135, 135, 145 }, { 110, 110, 120 }
L.MCOFF, L.GSON, L.GSDIM, L.SLBG, L.SLSTAR = { 120, 124, 160 }, { 149, 204, 26 }, { 196, 196, 206 }, { 14, 14, 17 }, { 255, 235, 242 }

---------------------------------------------------------------------------
-- 8k. Speed graph: how fast you move, with the peak
---------------------------------------------------------------------------
L.SG_STYLES = { "Destiny", "Radiance", "Mercury", "Silentium", "Royal", "Liquid glass", "Moon", "OneShot" }
L.speedHist, L.speedAt, L.speedPos = {}, 0, 0
for i = 1, 120 do L.speedHist[i] = 0 end

function L.drawSpeedGraph()
    local sw, sh = draw.GetScreenSize()
    local speed = 0
    local lp = entities.GetLocalPlayer()
    if lp then
        local ok, v = pcall(lp.EstimateAbsVelocity, lp)
        if ok and v then speed = sqrt(v.x * v.x + v.y * v.y) end
    end
    if now() - L.speedAt > 1 / 40 then
        L.speedAt = now()
        L.speedPos = L.speedPos % 120 + 1
        L.speedHist[L.speedPos] = speed
    end
    local peak = 320
    for i = 1, 120 do peak = max(peak, L.speedHist[i]) end

    local W, H = 240, 96
    local x, y = draggable("sg", sw / 2 - W / 2, sh - H - 120, W, H)
    local st = settings.sgStyle
    local col, bg, txt, dim
    local panel = settings.sgBg
    if st == 2 then
        if panel then
            roundRect(x, y + 3, W, H, 12, C_BLACK, 60)
            roundRect(x, y, W, H, 12, RD.body, 220)
            roundRectLine(x, y, W, H, 12, RD.border, 170)
        end
        col, bg, txt, dim = RD.violet, L.SGRD, RD.white, RD.dim
    elseif st == 3 then
        if panel then mercuryBox(x, y, W, H, 10) end
        col, bg, txt, dim = MC.val, L.SGMC, MC.text, MC.dim
    elseif st == 4 then
        local acc = accent()
        if panel then
            for i = 1, 4 do
                local e = i * 1.7
                roundRectLine(x - e, y - e, W + 2 * e, H + 2 * e, 10 + e, acc, 46 - i * 10)
            end
            roundRect(x, y, W, H, 10, L.SLBG, 232)
            roundRectLine(x, y, W, H, 10, C_WHITE, 26)
            rect(x + 10, y, W - 20, 1, acc, 160)
        end
        col, bg, txt, dim = acc, L.IMSL_KEY, SL.text, SL.dim
    elseif st >= 5 then
        local p = L.palFor(st + 3, 1)
        if panel then L.panelBg(st + 3, x, y, W, H, nil, 1, 1) end
        col, bg, txt, dim = p.c, p.track, p.txt, p.dim
    else
        if panel then
            roundRect(x, y + 3, W, H, 12, C_BLACK, 70)
            roundRect(x, y, W, H, 12, T.card, 235)
            roundRectLine(x, y, W, H, 12, T.border)
        end
        col, bg, txt, dim = accent(), T.pill, T.text, T.muted
    end
    text(F.bold, tostring(floor(speed)), x + 12, y + 6, 24, txt)
    text(F.small, "u/s", x + 14 + textW(F.bold, tostring(floor(speed))), y + 8, 22, dim)
    local pk = "peak " .. floor(peak)
    text(F.small, pk, x + W - 12 - textW(F.small, pk), y + 8, 22, dim)
    local gx, gy, gw, gh = x + 10, y + 34, W - 20, H - 44
    roundRect(gx, gy, gw, gh, 6, bg, 220)
    -- the line: colour set once, every 3rd sample
    color(col, 235)
    local prevX, prevY
    for i = 1, 120, 3 do
        local v = L.speedHist[(L.speedPos + i - 1) % 120 + 1]
        local px = round(gx + (i - 1) / 119 * gw)
        local py = round(gy + gh - 2 - v / peak * (gh - 4))
        if prevX then draw.Line(prevX, prevY, px, py) end
        prevX, prevY = px, py
    end
end
L.SGRD, L.SGMC = { 20, 22, 48 }, { 20, 22, 40 }

---------------------------------------------------------------------------
-- 8l. "destiny loaded" message when the script starts
---------------------------------------------------------------------------
L.welcomeAt = nil

function L.drawWelcome()
    if not L.welcomeAt then L.welcomeAt = now() + 0.6 end
    local el = now() - L.welcomeAt
    if el < 0 or el > 6 then return end
    local sw = draw.GetScreenSize()
    local inT = easeOutBack(el / 0.5)
    local out = clamp((6 - el) / 0.5, 0, 1)
    local keyName = (L.MENU_KEYS[settings.menuKey] or L.MENU_KEYS[1])[1]
    local line2a, line2b = "Press ", " to open the menu"
    local w2 = textW(F.small, line2a) + textW(F.tiny, keyName) + 16 + textW(F.small, line2b)
    local W = max(300, 92 + max(logoWidth("DESTINY") + textW(F.small, "  loaded") + 8, w2))
    local H = 66
    local x = (sw - W) / 2
    local y = 70 - (1 - inT) * 40
    local keep = ALPHA
    ALPHA = keep * clamp(el / 0.25, 0, 1) * out
    local acc = accent()
    roundRect(x - 1, y + 4, W + 2, H, 18, C_BLACK, 70)
    roundRect(x, y, W, H, 16, T.card, 245)
    L.gradBorder(x, y, W, H, 16, logoStops(), now() * 0.3)
    -- logo tile with a little check that draws itself
    roundRect(x + 12, y + 11, 44, 44, 12, T.pill)
    roundRect(x + 14, y + 13, 40, 40, 11, acc, 40)
    L.screenSpace()
    local ck = clamp((el - 0.3) / 0.35, 0, 1)
    local ax, ay, bx, by, cx2, cy2 = x + 25, y + 33, x + 31, y + 40, x + 44, y + 25
    if ck > 0 then
        local p1 = min(1, ck * 2)
        tline(ax, ay, ax + (bx - ax) * p1, ay + (by - ay) * p1, 3.4, acc)
        if ck > 0.5 then
            local p2 = (ck - 0.5) * 2
            tline(bx, by, bx + (cx2 - bx) * p2, by + (cy2 - by) * p2, 3.4, acc)
        end
    end
    drawLogo("DESTINY", x + 68, y + 10)
    text(F.small, "loaded", x + 74 + logoWidth("DESTINY"), y + 13, 24, T.text2)
    local lx = x + 68
    text(F.small, line2a, lx, y + 38, 20, T.text2)
    lx = lx + textW(F.small, line2a)
    local kw = textW(F.tiny, keyName) + 12
    roundRect(lx, y + 39, kw, 18, 5, T.pill)
    roundRectLine(lx, y + 39, kw, 18, 5, acc, 200)
    textC(F.tiny, keyName, lx + kw / 2, y + 39, 18, T.text)
    text(F.small, line2b, lx + kw + 4, y + 38, 20, T.text2)
    -- a light sweep across once
    local sw2 = clamp((el - 0.2) / 0.9, 0, 1)
    if sw2 > 0 and sw2 < 1 then
        roundRect(x + 4 + (W - 40) * sw2, y + 2, 30, H - 4, 12, C_WHITE, 26 * sin(sw2 * pi))
    end
    ALPHA = keep
end

---------------------------------------------------------------------------
-- 8m. menu backgrounds: Radiance ribbons, Silentium ribbons + butterflies
---------------------------------------------------------------------------
L.RDRIB = { { 124, 108, 255 }, { 150, 118, 255 }, { 96, 108, 255 }, { 170, 128, 255 }, { 110, 94, 240 }, { 140, 150, 255 }, { 120, 100, 250 } }
L.SLRIB = { { 255, 168, 198 }, { 255, 188, 212 }, { 250, 158, 192 }, { 255, 200, 220 }, { 246, 176, 204 } }
L.RDRIB_L = {}
for i, c in ipairs(L.RDRIB) do L.RDRIB_L[i] = { min(255, c[1] + 60), min(255, c[2] + 60), 255 } end
L.RIB_CORE = { 240, 236, 255 }
L.ribX, L.ribY = {}, {}

-- one straight piece of a thick line
function L.seg(x1, y1, x2, y2, w, c, a)
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    local nx, ny = -dy / len * w / 2, dx / len * w / 2
    cpoly(c, a, x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny)
end

-- glowing ribbons that wave across the screen
function L.drawRibbons(silentium)
    local sw, sh = draw.GetScreenSize()
    local n0 = 20 + settings.bgFxAmt * 1.5
    local k = silentium and max(3, min(5, round(3 + n0 / 60))) or max(3, min(6, round(3 + n0 / 40)))
    local t = now() * 1000
    local N = 18
    L.screenSpace()
    for i = 1, k do
        local ph = silentium and i * 2.3 or i * 1.9
        local sp = 1 / ((silentium and 12000 or 9000) + i * (silentium and 2600 or 2300))
        for j = 0, N do
            local f = j / N
            L.ribX[j] = -sw * 0.15 + f * sw * 1.3
            if silentium then
                L.ribY[j] = sh * (0.15 + 0.7 * (i - 0.5) / k) + sh * 0.24 * sin(f * 2.8 + t * sp * 6.28 + ph) + sh * 0.06 * sin(f * 6.3 - t * sp * 8 + ph * 2)
            else
                L.ribY[j] = sh * (0.12 + 0.76 * (i - 0.5) / k) + sh * 0.2 * sin(f * 3.2 + t * sp * 6.28 + ph) + sh * 0.07 * sin(f * 7.1 - t * sp * 9 + ph * 2)
            end
        end
        local c = silentium and L.SLRIB[i] or L.RDRIB[i]
        for layer = 1, 4 do
            local w, a, col
            if silentium then
                if layer == 1 then w, a, col = 54, 12, c elseif layer == 2 then w, a, col = 20, 34, c
                elseif layer == 3 then w, a, col = 6, 120, c else w, a, col = 2, 255, C_WHITE end
            else
                if layer == 1 then w, a, col = 60, 12, c elseif layer == 2 then w, a, col = 26, 34, c
                elseif layer == 3 then w, a, col = 8, 110, L.RDRIB_L[i] else w, a, col = 2.6, 245, L.RIB_CORE end
            end
            for j = 1, N do L.seg(L.ribX[j - 1], L.ribY[j - 1], L.ribX[j], L.ribY[j], w, col, a) end
        end
    end
end

L.BF_GLOW, L.BF_UP, L.BF_LO, L.BF_BODY = { 255, 150, 185 }, { 250, 248, 252 }, { 244, 238, 246 }, { 90, 80, 92 }

-- white butterflies that flutter across
function L.drawButterflies()
    local sw, sh = draw.GetScreenSize()
    local n0 = 20 + settings.bgFxAmt * 1.5
    local n = max(5, min(10, round(n0 / 12)))
    local t = now() * 1000
    L.screenSpace()
    for i = 1, n do
        local kk = L.rnd(9, i) * 10
        local a = L.rnd(9, i + 50)
        local sp = 22 + 34 * a
        local x = (L.rnd(9, i + 100) * sw + sp * t / 1000) % (sw + 200) - 100
        local y = L.rnd(9, i + 150) * sh + 46 * sin(t / (1500 + kk * 900) + kk * 7) + 16 * sin(t / 430 + kk * 3)
        local s = 13 + 12 * a
        local fl = 0.25 + 0.75 * abs(sin(t / (120 + kk * 70) + kk * 5))
        oval(x, y, s * 1.7, s * 1.7, L.BF_GLOW, 16)
        for side = -1, 1, 2 do
            cpoly(L.BF_UP, 232, x, y - s * 0.05, x + side * s * 1.05 * fl, y - s * 0.95, x + side * s * 1.3 * fl, y - s * 0.3, x + side * s * 0.45 * fl, y + s * 0.05)
            cpoly(L.BF_LO, 214, x, y + s * 0.05, x + side * s * 0.9 * fl, y + s * 0.2, x + side * s * 0.72 * fl, y + s * 0.85, x + side * s * 0.18 * fl, y + s * 0.55)
        end
        oval(x, y - s * 0.12, s * 0.1, s * 0.1, L.BF_BODY)
        oval(x, y + s * 0.12, s * 0.09, s * 0.09, L.BF_BODY)
    end
end

---------------------------------------------------------------------------
-- 8n. kill announcer colours: the menu's logo gradient, any preset, or your own colour
---------------------------------------------------------------------------
L.KA_COLORS = { "Logo gradient (menu)", "Accent Flow", "Aurora", "Sunset", "Ocean", "Fire", "Rainbow", "Candy", "Mono", "Custom colour" }
L.kaCustom = { C_WHITE, C_WHITE }
function L.kaStops()
    local i = settings.kaColor
    if i >= 2 and i <= 9 then return logoStops(i - 1) end
    if i == 10 then
        local c = L.hex(settings.colKa) or accent()
        L.kaCustom[1] = c
        L.kaCustom[2] = L.hexCache["l" .. settings.colKa] or { c[1] + (255 - c[1]) * 0.55, c[2] + (255 - c[2]) * 0.55, c[3] + (255 - c[3]) * 0.55 }
        L.hexCache["l" .. settings.colKa] = L.kaCustom[2]
        return L.kaCustom
    end
    return logoStops()
end

---------------------------------------------------------------------------
-- 8o. Player HUDs: stats, killfeed, health and ammo, killstreak, round summary, crosshair
---------------------------------------------------------------------------
F.ksN = draw.CreateFont("Segoe UI Black", 40, 900, FONTFLAG_ANTIALIAS | FONTFLAG_OUTLINE)
L.GREEN, L.ORANGE, L.HOT = { 16, 185, 129 }, { 255, 122, 24 }, { 255, 45, 85 }
L.NLTRACK, L.GSTXT = { 30, 30, 46 }, { 235, 235, 240 }
L.ss = { kills = 0, deaths = 0, assists = 0, best = 0, dmg = 0, t0 = now() }
L.rs = { kills = 0, deaths = 0, assists = 0, best = 0, dmg = 0 }
L.feed = {}
L.hp = { hp = 0, max = 1, clip = -1, res = -1, speed = 0, alive = false, at = -9, hpS = "0", clipS = "", resS = "" }
L.lastAction = now()

-- small numbers as text without making a new string every frame
L.numS = {}
function L.num(n)
    if n < 0 or n > 3000 then return tostring(n) end
    local s = L.numS[n]
    if not s then s = tostring(n); L.numS[n] = s end
    return s
end

-- the 7 HUD looks as a plain panel: colours and fonts first, then the box
L.pal = { c = { 255, 255, 255 } }
L.PH = { 32, 24, 27, 30, 32, 26, 38, 34, 34, 32, 34 }
L.OS = { bg = { 30, 15, 40 }, line = { 104, 58, 120 }, sun = { 255, 205, 80 }, sunL = { 255, 240, 170 }, pink = { 214, 92, 150 },
         txt = { 255, 241, 214 }, dim = { 206, 172, 204 }, track = { 60, 34, 78 } }
L.MOON = { bg = { 16, 18, 34 }, line = { 58, 64, 110 }, lav = { 150, 140, 255 }, txt = { 234, 236, 252 }, dim = { 160, 166, 206 },
           track = { 30, 34, 60 } }
L.RY = { bg = { 16, 10, 26 }, line = { 120, 62, 152 }, pink = { 255, 92, 170 }, violet = { 150, 96, 255 }, txt = { 246, 236, 252 },
         dim = { 172, 148, 198 }, track = { 42, 26, 60 }, title = { 255, 156, 208 } }
L.GL = { txt = { 255, 255, 255 }, dim = { 226, 232, 244 }, track = { 20, 26, 38 } }
function L.palFor(st, grad)
    local p = L.pal
    local gs = L.gradStops(grad)
    local col
    p.shadow, p.pad = false, 12
    if st == 2 then p.txt, p.dim, col, p.f, p.fb, p.track, p.pad = C_WHITE, L.SKG, L.SKON, F.sk, F.sk, L.SK3, 9
    elseif st == 3 then p.txt, p.dim, col, p.f, p.fb, p.track, p.pad = C_WHITE, L.NLDIM, L.NLBLUE, F.nlR, F.nlT, L.NLTRACK, 8
    elseif st == 4 then p.txt, p.dim, col, p.f, p.fb, p.track = RD.white, RD.dim, RD.violet, F.small, F.rd, L.SGRD
    elseif st == 5 then p.txt, p.dim, col, p.f, p.fb, p.track = MC.text, MC.dim, MC.val, F.small, F.rd, L.SGMC
    elseif st == 6 then p.txt, p.dim, col, p.f, p.fb, p.track, p.pad, p.shadow = L.GSTXT, L.GSDIM, L.GSON, F.gs, F.gs, C_BLACK, 4, true
    elseif st == 7 then p.txt, p.dim, col, p.f, p.fb, p.track = SL.text, SL.dim, accent(), F.small, F.bold, SL.line
    elseif st == 8 then p.txt, p.dim, col, p.f, p.fb, p.track = L.RY.txt, L.RY.dim, L.RY.pink, F.small, F.bold, L.RY.track
    elseif st == 9 then
        p.txt, p.dim, col, p.f, p.fb, p.track, p.shadow = L.GL.txt, L.GL.dim, accent(), F.small, F.bold, L.GL.track, true
    elseif st == 10 then p.txt, p.dim, col, p.f, p.fb, p.track = L.MOON.txt, L.MOON.dim, L.MOON.lav, F.small, F.bold, L.MOON.track
    elseif st == 11 then p.txt, p.dim, col, p.f, p.fb, p.track = L.OS.txt, L.OS.dim, L.OS.sun, F.small, F.bold, L.OS.track
    else p.txt, p.dim, col, p.f, p.fb, p.track = T.text, T.muted, accent(), F.small, F.bold, T.pill end
    if gs then col = sampleStops(gs, now() * 0.12) end
    p.c[1], p.c[2], p.c[3] = col[1], col[2], col[3]
    return p
end

function L.pt(font, s, x, y, h, c, a)
    if L.pal.shadow then text(font, s, x + 1, y + 1, h, C_BLACK, (a or 255) * 0.75) end
    text(font, s, x, y, h, c, a)
end

function L.skBox(x, y, w, h)
    rect(x, y, w, h, L.SK1)
    rect(x + 1, y + 1, w - 2, h - 2, L.SK2)
    rect(x + 2, y + 2, w - 4, h - 4, L.SKBG)
    if h < 40 then return end
    x, y, w = round(x), round(y), round(w)
    local w1 = floor((w - 6) / 2)
    color(L.SKB, 255); draw.FilledRect(x + 3, y + 3, x + 3 + w1, y + 4)
    rawColor(L.SKP[1], L.SKP[2], L.SKP[3], 255); draw.FilledRectFade(x + 3, y + 3, x + 3 + w1, y + 4, 0, 255, true)
    color(L.SKP, 255); draw.FilledRect(x + 3 + w1, y + 3, x + w - 3, y + 4)
    rawColor(L.SKY[1], L.SKY[2], L.SKY[3], 255); draw.FilledRectFade(x + 3 + w1, y + 3, x + w - 3, y + 4, 0, 255, true)
end

-- Halloween decorations: webs, a jack-o'-lantern, bats, a spider on its thread, a ghost and the moon
L.HW = { web = { 205, 190, 230 }, glow = { 255, 115, 20 }, rind = { 206, 78, 10 }, flesh = { 255, 124, 24 }, stem = { 96, 130, 44 },
         face = { 255, 226, 120 }, bat = { 150, 105, 190 }, thread = { 210, 200, 230 }, spider = { 176, 150, 206 }, eye = { 255, 60, 60 },
         ghost = { 240, 232, 255 }, dark = { 30, 16, 40 }, moon = { 250, 224, 160 }, moonG = { 255, 226, 150 }, crater = { 226, 196, 130 },
         wing = { 118, 72, 190 }, body = { 150, 100, 225 } }
L.fp = {}
-- a shape as a fan of triangles from its first corner (n corners in L.fp)
function L.fan(c, a, n)
    local p = L.fp
    for i = 2, n - 1 do cpoly(c, a, p[1], p[2], p[i * 2 - 1], p[i * 2], p[i * 2 + 1], p[i * 2 + 2]) end
end
-- a closed shape as a fan round a middle point
function L.fanC(c, a, mx, my, n)
    local p = L.fp
    for i = 1, n do
        local j = i % n + 1
        cpoly(c, a, mx, my, p[i * 2 - 1], p[i * 2], p[j * 2 - 1], p[j * 2])
    end
end

-- a spider web in a corner; dx, dy = +1 / -1 says which way it opens
function L.hwWeb(x, y, dx, dy, r)
    local c = L.HW.web
    for i = 0, 5 do
        local a = i * 0.314159
        line(x, y, x + dx * cos(a) * r, y + dy * sin(a) * r, c, 48)
    end
    for ki = 1, 3 do
        local k = (ki == 1) and 0.3 or ((ki == 2) and 0.55 or 0.8)
        for i = 0, 4 do
            local a1, a2 = i * 0.314159, (i + 1) * 0.314159
            local x1, y1 = x + dx * cos(a1) * r * k, y + dy * sin(a1) * r * k
            local x2, y2 = x + dx * cos(a2) * r * k, y + dy * sin(a2) * r * k
            local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            mx, my = mx + (x - mx) * 0.14, my + (y - my) * 0.14
            line(x1, y1, mx, my, c, 48)
            line(mx, my, x2, y2, c, 48)
        end
    end
end

-- jack-o'-lantern with a flickering glow (fl = -1..1)
function L.hwPumpkin(cx, cy, r, fl)
    local H = L.HW
    disc(cx, cy, r * 1.9, H.glow, 14 + 8 * fl)
    disc(cx, cy, r * 1.35, H.glow, 24 + 10 * fl)
    oval(cx - r * 0.52, cy, r * 0.62, r * 0.86, H.rind)
    oval(cx + r * 0.52, cy, r * 0.62, r * 0.86, H.rind)
    oval(cx, cy, r * 0.62, r * 0.92, H.flesh)
    roundRect(cx - 3, cy - r * 1.14, 7, r * 0.36, 2, H.stem)
    local g = 220 + 30 * fl
    cpoly(H.face, g, cx - r * 0.52, cy - r * 0.05, cx - r * 0.16, cy - r * 0.05, cx - r * 0.34, cy - r * 0.42)
    cpoly(H.face, g, cx + r * 0.16, cy - r * 0.05, cx + r * 0.52, cy - r * 0.05, cx + r * 0.34, cy - r * 0.42)
    cpoly(H.face, g, cx - r * 0.07, cy + r * 0.1, cx + r * 0.07, cy + r * 0.1, cx, cy - r * 0.05)
    local p = L.fp
    p[1], p[2], p[3], p[4], p[5], p[6] = cx - r * 0.58, cy + r * 0.24, cx - r * 0.3, cy + r * 0.34, cx, cy + r * 0.28
    p[7], p[8], p[9], p[10] = cx + r * 0.3, cy + r * 0.34, cx + r * 0.58, cy + r * 0.24
    p[11], p[12], p[13], p[14], p[15], p[16] = cx + r * 0.4, cy + r * 0.52, cx + r * 0.2, cy + r * 0.4, cx, cy + r * 0.62
    p[17], p[18], p[19], p[20] = cx - r * 0.2, cy + r * 0.4, cx - r * 0.4, cy + r * 0.52
    L.fanC(H.face, g, cx, cy + r * 0.37, 10)
end

function L.hwBat(x, y, s, ph)
    local c = L.HW.bat
    local fl = sin(ph) * 0.55
    oval(x, y, s * 0.22, s * 0.34, c, 185)
    disc(x - s * 0.1, y - s * 0.36, max(1, s * 0.1), c, 185)
    disc(x + s * 0.1, y - s * 0.36, max(1, s * 0.1), c, 185)
    local p = L.fp
    for sd = -1, 1, 2 do
        p[1], p[2] = x + sd * s * 0.15, y - s * 0.05
        p[3], p[4] = x + sd * s * 0.9, y - s * (0.55 + fl)
        p[5], p[6] = x + sd * s * 1.5, y - s * (0.1 + fl * 0.6)
        p[7], p[8] = x + sd * s * 1.25, y + s * 0.3
        p[9], p[10] = x + sd * s * 0.9, y + s * 0.08
        p[11], p[12] = x + sd * s * 0.55, y + s * 0.36
        p[13], p[14] = x + sd * s * 0.3, y + s * 0.12
        L.fan(c, 185, 7)
    end
end

-- a spider hanging on its thread from top down to len
function L.hwSpider(x, top, len)
    local H = L.HW
    line(x, top, x, top + len, H.thread, 80)
    local by = top + len + 8
    for k = 1, 4 do
        line(x, by, x - 8 - k * 3, by - 7 + k * 4, H.spider)
        line(x, by, x + 8 + k * 3, by - 7 + k * 4, H.spider)
    end
    disc(x, by, 6, H.spider)
    disc(x, by - 7, 3.6, H.spider)
    disc(x - 1.6, by - 8, 1.1, H.eye)
    disc(x + 1.6, by - 8, 1.1, H.eye)
end

function L.hwGhost(x, y)
    local H = L.HW
    roundRect(x, y, 28, 30, 13, H.ghost, 215)
    for i = 0, 2 do disc(x + 4.7 + i * 9.3, y + 30, 4.7, H.ghost, 215) end
    disc(x + 9, y + 13, 2.6, H.dark)
    disc(x + 19, y + 13, 2.6, H.dark)
    disc(x + 14, y + 21, 2.2, H.dark)
end

-- the little scene in the menu header: spider, three bats, the moon, a ghost and a pumpkin
function L.hwScene(x0, x1, top, bot, fl)
    local t = now()
    local H = L.HW
    L.screenSpace()
    L.hwSpider((x0 + x1) / 2 + 40, top, 4 + 6 * sin(t * 1.3) + 8)
    local span = max(40, x1 - x0 - 190)
    for k = 1, 3 do
        local bx = x0 + (t * (30 + k * 8) + k * 150) % span + 10
        L.hwBat(bx, top + 12 + k * 8 + 6 * sin(t * 1.6 + k * 2), 6 + k * 0.6, t * 13 + k * 2)
    end
    disc(x1 - 150, bot - 24, 15, H.moonG, 18)
    disc(x1 - 150, bot - 24, 10, H.moon, 235)
    disc(x1 - 153, bot - 27, 2.4, H.crater, 150)
    L.hwGhost(x1 - 112, bot - 42 + 3 * sin(t * 2))
    L.hwPumpkin(x1 - 40, bot - 22, 14, fl)
end

-- bats flying across the whole screen behind the menu
function L.drawBats()
    local sw, sh = draw.GetScreenSize()
    local H = L.HW
    local n = max(2, round((20 + settings.bgFxAmt * 1.5) / 9))
    local t = now()
    local p = L.fp
    L.screenSpace()
    for i = 1, n do
        local k, a = L.rnd(11, i) * 10, L.rnd(11, i + 50)
        local dir = (i % 2 == 0) and 1 or -1
        local sp = 70 + 90 * a
        local x = (L.rnd(11, i + 100) * sw + dir * sp * t) % (sw + 240) - 120
        local y = L.rnd(11, i + 150) * sh * 0.8 + 45 * sin(t / 0.9 + k * 9) + 30 * sin(t / 0.33 + k * 4)
        local s = 15 + 17 * a
        local up = s * (0.2 + 0.55 * (0.5 + 0.5 * sin(t / 0.085 + k * 12)))
        for sd = -1, 1, 2 do
            local d = dir * sd
            p[1], p[2] = x, y - s * 0.05
            p[3], p[4] = x + d * s * 0.45, y - up
            p[5], p[6] = x + d * s * 0.85, y - up * 0.55 + s * 0.1
            p[7], p[8] = x + d * s * 1.1, y + s * 0.2
            p[9], p[10] = x + d * s * 0.75, y + s * 0.08
            p[11], p[12] = x + d * s * 0.55, y + s * 0.3
            p[13], p[14] = x + d * s * 0.28, y + s * 0.1
            L.fan(H.wing, 224, 7)
        end
        disc(x, y + s * 0.05, s * 0.42, H.body, 240)
        disc(x - s * 0.1, y - s * 0.14, max(1, s * 0.12), H.face, 255)
        disc(x + s * 0.1, y - s * 0.14, max(1, s * 0.12), H.face, 255)
    end
end

L.NK = { hat = { 150, 50, 80 }, hatD = { 112, 34, 60 }, ear = { 226, 130, 150 }, hair = { 66, 58, 168 }, hairL = { 96, 88, 204 },
         skin = { 206, 138, 100 }, eye = { 255, 214, 60 }, eyeL = { 255, 244, 170 }, pupil = { 46, 26, 22 }, scarf = { 70, 104, 214 } }
function L.drawNiko(cx, cy, u, a)
    a = a or 255
    local N = L.NK
    L.screenSpace()
    local t = now()
    local blink = (t % 4.2) > 4.05
    cy = cy + sin(t * 1.6) * u * 0.02
    -- hair behind the head, with a spike on each side
    for sd = -1, 1, 2 do
        cpoly(N.hair, a, cx + sd * 0.38 * u, cy - 0.05 * u, cx + sd * 0.86 * u, cy + 0.2 * u, cx + sd * 0.4 * u, cy + 0.3 * u)
        cpoly(N.hair, a, cx + sd * 0.36 * u, cy + 0.18 * u, cx + sd * 0.74 * u, cy + 0.46 * u, cx + sd * 0.3 * u, cy + 0.46 * u)
    end
    oval(cx, cy + 0.06 * u, 0.5 * u, 0.46 * u, N.hair, a)
    -- scarf and face
    oval(cx, cy + 0.5 * u, 0.4 * u, 0.13 * u, N.scarf, a)
    oval(cx, cy + 0.14 * u, 0.42 * u, 0.35 * u, N.skin, a)
    -- fringe
    cpoly(N.hair, a, cx - 0.44 * u, cy - 0.2 * u, cx + 0.44 * u, cy - 0.2 * u, cx + 0.4 * u, cy - 0.02 * u, cx - 0.4 * u, cy - 0.02 * u)
    cpoly(N.hair, a, cx - 0.42 * u, cy - 0.04 * u, cx - 0.14 * u, cy - 0.04 * u, cx - 0.3 * u, cy + 0.12 * u)
    cpoly(N.hair, a, cx - 0.14 * u, cy - 0.04 * u, cx + 0.14 * u, cy - 0.04 * u, cx, cy + 0.1 * u)
    cpoly(N.hair, a, cx + 0.14 * u, cy - 0.04 * u, cx + 0.42 * u, cy - 0.04 * u, cx + 0.3 * u, cy + 0.12 * u)
    -- eyes: big and yellow, a thin line when she blinks
    for sd = -1, 1, 2 do
        local ex, ey = cx + sd * 0.19 * u, cy + 0.2 * u
        if blink then
            rect(ex - 0.1 * u, ey, 0.2 * u, max(1, 0.03 * u), N.pupil, a)
        else
            oval(ex, ey, 0.115 * u, 0.13 * u, N.eye, a)
            oval(ex, ey, 0.028 * u, 0.1 * u, N.pupil, a)
            oval(ex - 0.045 * u, ey - 0.055 * u, 0.03 * u, 0.03 * u, N.eyeL, a)
        end
    end
    rect(cx - 0.035 * u, cy + 0.37 * u, 0.07 * u, max(1, 0.025 * u), N.pupil, a * 0.8)
    -- hat: ears first, then the crown and the wide brim
    for sd = -1, 1, 2 do
        cpoly(N.hat, a, cx + sd * 0.14 * u, cy - 0.58 * u, cx + sd * 0.44 * u, cy - 0.96 * u, cx + sd * 0.5 * u, cy - 0.5 * u)
        cpoly(N.ear, a, cx + sd * 0.25 * u, cy - 0.6 * u, cx + sd * 0.41 * u, cy - 0.84 * u, cx + sd * 0.44 * u, cy - 0.56 * u)
    end
    oval(cx, cy - 0.44 * u, 0.42 * u, 0.3 * u, N.hat, a)
    oval(cx, cy - 0.21 * u, 0.74 * u, 0.15 * u, N.hatD, a)
    oval(cx, cy - 0.25 * u, 0.72 * u, 0.13 * u, N.hat, a)
end

function L.panelBg(st, x, y, w, h, title, bord, grad)
    -- OneShot: Niko peeks over the top right corner of the bigger panels
    if st == 11 and h >= 40 then L.drawNiko(x + w - 26, y - 1, 26, 255) end
    local p = L.pal
    if st == 2 then
        L.skBox(x, y, w, h)
        if title then text(F.sk, title, x + 9, y + 7, 15, L.SKG) end
    elseif st == 3 then
        if title then
            rect(x, y, w, 25, L.NLBAR, 200)
            text(F.nlT, title, x + 8, y, 25, C_WHITE)
            rect(x, y + 25, w, h - 25, L.NLBAR, 120)
            rect(x, y + 25, w, h - 25, L.NLLIST, 15)
        else
            rect(x, y, w, h, L.NLBAR, 185)
        end
    elseif st == 4 then
        roundRect(x, y + 3, w, h, 10, C_BLACK, 60)
        roundRect(x, y, w, h, 10, RD.body, 225)
        if bord <= 1 then roundRectLine(x, y, w, h, 10, RD.border, 170) else L.styledBorder(bord, grad, x, y, w, h, 10) end
        if title then
            text(F.icon, "✦", x + 11, y + 3, 24, p.c)
            text(F.rd, title, x + 30, y + 3, 24, RD.white)
        end
    elseif st == 5 then
        mercuryBox(x, y, w, h, 9)
        L.styledBorder(bord, grad, x, y, w, h, 9)
        if title then
            text(F.rd, title, x + 12, y + 3, 24, MC.text)
            rect(x + 8, y + 28, w - 16, 1, MC.border, 150)
        end
    elseif st == 6 then
        if title then L.pt(F.gs, title, x + 4, y, 24, p.c) end
    elseif st == 7 then
        for i = 1, 4 do
            local e = i * 1.7
            roundRectLine(x - e, y - e, w + 2 * e, h + 2 * e, 10 + e, p.c, 46 - i * 10)
        end
        roundRect(x, y, w, h, 10, L.SLBG, 232)
        roundRectLine(x, y, w, h, 10, C_WHITE, 26)
        rect(x + 10, y, w - 20, 1, p.c, 160)
        L.styledBorder(bord, grad, x, y, w, h, 10)
        if title then text(F.script, title, x + 14, y + 5, 30, mix(p.c, C_WHITE, 0.2)) end
    elseif st == 8 then
        -- Royal: near-black purple, a pink to violet line on top, a faint pink glow around it
        roundRectLine(x - 2, y - 2, w + 4, h + 4, 14, L.RY.pink, 26)
        roundRectLine(x - 1, y - 1, w + 2, h + 2, 13, L.RY.pink, 50)
        roundRect(x, y + 3, w, h, 12, C_BLACK, 70)
        roundRect(x, y, w, h, 12, L.RY.bg, 238)
        if bord <= 1 then roundRectLine(x, y, w, h, 12, L.RY.line, 170) else L.styledBorder(bord, grad, x, y, w, h, 12) end
        local x0, x1 = round(x + 12), round(x + w - 12)
        color(L.RY.violet, 255); draw.FilledRect(x0, round(y), x1, round(y) + 2)
        rawColor(L.RY.pink[1], L.RY.pink[2], L.RY.pink[3], 255)
        draw.FilledRectFade(x0, round(y), x1, round(y) + 2, clamp(round(255 * ALPHA), 0, 255), 0, true)
        if title then
            text(F.icon, "✦", x + 12, y + 5, 24, p.c)
            text(F.bold, title, x + 32, y + 5, 24, L.RY.title)
        end
    elseif st == 9 then
        -- Liquid glass: a light see-through pane with a bright rim and a soft highlight in its upper half
        -- mostly clear: a faint tint, a brighter upper half, a white rim and a soft shadow
        roundRect(x, y + 4, w, h, 18, C_BLACK, 26)
        roundRect(x, y, w, h, 18, C_WHITE, 30)
        roundRect(x + 2, y + 2, w - 4, max(8, (h - 4) * 0.45), 16, C_WHITE, 22)
        roundRectLine(x, y, w, h, 18, C_WHITE, 170)
        roundRectLine(x + 1, y + 1, w - 2, h - 2, 17, C_WHITE, 45)
        L.styledBorder(bord, grad, x, y, w, h, 18)
        if title then L.pt(F.bold, title, x + 16, y + 6, 24, L.GL.txt) end
    elseif st == 11 then
        -- OneShot: a deep plum panel with a warm sun glow, a pink to gold line on top and a little sun in the title
        local pulse = 0.75 + 0.25 * sin(now() * 2.2)
        roundRectLine(x - 3, y - 3, w + 6, h + 6, 15, L.OS.sun, 16 * pulse)
        roundRectLine(x - 1.5, y - 1.5, w + 3, h + 3, 13.5, L.OS.sun, 40 * pulse)
        roundRect(x, y + 3, w, h, 12, C_BLACK, 70)
        roundRect(x, y, w, h, 12, L.OS.bg, 236)
        if bord <= 1 then roundRectLine(x, y, w, h, 12, L.OS.line, 190) else L.styledBorder(bord, grad, x, y, w, h, 12) end
        local x0, x1 = round(x + 12), round(x + w - 12)
        color(L.OS.sun, 255); draw.FilledRect(x0, round(y), x1, round(y) + 2)
        rawColor(L.OS.pink[1], L.OS.pink[2], L.OS.pink[3], 255)
        draw.FilledRectFade(x0, round(y), x1, round(y) + 2, clamp(round(255 * ALPHA), 0, 255), 0, true)
        if title then
            disc(x + 20, y + 16, 9, L.OS.sun, 50 * pulse)
            disc(x + 20, y + 16, 5, L.OS.sunL, 255)
            text(F.bold, title, x + 34, y + 4, 24, L.OS.txt)
        end
    elseif st == 10 then
        -- Moon: dark navy pills with a lavender moon
        roundRect(x, y + 3, w, h, 9, C_BLACK, 70)
        roundRect(x, y, w, h, 9, L.MOON.bg, 228)
        if bord <= 1 then roundRectLine(x, y, w, h, 9, L.MOON.line, 200) else L.styledBorder(bord, grad, x, y, w, h, 9) end
        if title then
            text(F.icon, "☾", x + 11, y + 4, 24, p.c)
            text(F.bold, title, x + 31, y + 4, 24, L.MOON.txt)
        end
    else
        roundRect(x - 2, y + 2, w + 4, h, 16, C_BLACK, 45)
        roundRect(x, y, w, h, 14, T.card, 240)
        if bord <= 1 then roundRectLine(x, y, w, h, 14, T.border) else L.styledBorder(bord, grad, x, y, w, h, 14) end
        if title then text(F.bold, title, x + 14, y + 5, 24, T.text) end
    end
end

-- waifu lines for more than kills and deaths
L.MORE_LINES = {
    domination = { "You own them now!", "Total domination~", "They must be so mad right now!" },
    revenge    = { "Revenge! Serves them right!", "Payback time~", "That's what they get!" },
    dominated  = { "They keep getting you... Change it up!", "Don't let them farm you!", "Okay, now it's personal." },
    streakLost = { "Aww, the streak...", "It was a good run!", "Start a new one!" },
    assist     = { "Teamwork!", "Nice assist~", "You helped!" },
    roundWin   = { "We won! We won!", "Victory~ You carried!", "GG! That was great!" },
    roundLose  = { "Next round is ours!", "Unlucky... Shake it off!", "We'll get them back!" },
    lowHp      = { "Careful, you're hurt!", "Find a medkit, quick!", "Fall back, fall back!" },
    spawn      = { "Back in action!", "Let's go again!", "Round two~" },
    bored      = { "It's so quiet...", "Where is everyone?", "Go find someone to fight~" },
}
L.MORE_PLINES = {
    domination = { "Paimon declares them officially dominated!", "Hehe, they belong to us now!", "Paimon almost feels bad for them. Almost." },
    revenge    = { "Revenge! Paimon never forgets!", "Ha! Take that!", "That's what you get for messing with us!" },
    dominated  = { "They got you again?! Paimon is getting angry!", "Paimon will think of a really ugly nickname for them!", "Try a different way in, traveler!" },
    streakLost = { "Nooo, our streak!", "Paimon was counting those...", "It was fun while it lasted!" },
    assist     = { "Teamwork! Paimon helped too! ...Sort of.", "Nice assist!", "We make a great team!" },
    roundWin   = { "We won! Paimon wants a feast to celebrate!", "Victory! Paimon knew it all along!", "Hooray! Best team ever!" },
    roundLose  = { "Hmph! They just got lucky!", "Paimon demands a rematch!", "Don't be sad, we'll get them next round!" },
    lowHp      = { "Traveler, you're hurt! Eat something!", "Careful! Paimon can't carry you!", "Run away! Run away!" },
    spawn      = { "Back again! Let's go!", "Paimon missed you! Now get them!", "Okay, new plan: don't die!" },
    bored      = { "It's too quiet... Paimon is bored.", "Hellooo? Anyone out there?", "Paimon could really use a snack right now." },
}
for k, v in pairs(L.MORE_LINES) do L.LINES[k] = v end
for k, v in pairs(L.MORE_PLINES) do L.PLINES[k] = v end

function L.react(kind, chance)
    if not settings.compOn or not settings.compReact then return end
    if chance and math.random() > chance then return end
    local t = now()
    if t - (L.reactAt or -99) < 4 then return end
    L.reactAt = t
    compSay(kind)
    if settings.compChar == 1 and settings.paiVoice and (kind == "roundWin" or kind == "domination" or kind == "revenge") then
        L.paimon.speak(false)
    end
end

-- kill / death / assist entries of the killfeed, newest first
function L.feedAdd(kind, a, mid, b)
    local f = L.feed
    table.insert(f, 1, { kind = kind, a = a, mid = mid, b = b, t0 = now() })
    for i = #f, 7, -1 do f[i] = nil end
end

function L.trackKill(victim, weapon, how, flags)
    local s, r = L.ss, L.rs
    s.kills, r.kills = s.kills + 1, r.kills + 1
    if me.streak > s.best then s.best = me.streak end
    if me.streak > r.best then r.best = me.streak end
    local t = now()
    L.ksAt, L.chKillAt, L.lastAction, L.ssAt = t, t, t, nil
    if L.KS_BANNERS[me.streak] then L.ksBannerAt, L.ksBannerS = t, L.KS_BANNERS[me.streak] end
    if L.STREAK_STEPS[me.streak] and settings.ksSound > 1 then playFrom(L.STREAK_SOUNDS, settings.ksSound) end
    L.feedAdd(1, "You", (weapon or "killed") .. (how and ("  •  " .. how) or ""), victim)
    if flags & 1 ~= 0 then
        if settings.ntDom then notify("♛", "You are dominating " .. victim, "They haven't killed you in 4 of your kills", GOLD) end
        L.react("domination")
    elseif flags & 4 ~= 0 then
        if settings.ntDom then notify("⚔", "Revenge on " .. victim, "They are not dominating you any more", L.GREEN) end
        L.react("revenge")
    end
end

function L.trackDeath(killer, weapon, suicide, lost, flags)
    local s, r = L.ss, L.rs
    s.deaths, r.deaths = s.deaths + 1, r.deaths + 1
    L.lastAction, L.ssAt = now(), nil
    if suicide then L.feedAdd(2, "You", "died", "") else L.feedAdd(2, killer, weapon or "killed", "You") end
    if flags & 1 ~= 0 then
        if settings.ntDom then notify("☠", killer .. " is dominating you", "Kill them to get revenge", RED) end
        L.react("dominated")
    elseif lost >= 5 then L.react("streakLost") end
end

function L.trackAssist(victim)
    L.ss.assists, L.rs.assists, L.ssAt = L.ss.assists + 1, L.rs.assists + 1, nil
    if settings.kfAssists then L.feedAdd(3, "You", "assist", victim) end
    L.react("assist", 0.4)
end

function L.trackHit(dmg)
    L.ss.dmg, L.rs.dmg = L.ss.dmg + dmg, L.rs.dmg + dmg
    L.chHitAt, L.lastAction = now(), now()
end

function L.roundStart()
    local r = L.rs
    r.kills, r.deaths, r.assists, r.best, r.dmg = 0, 0, 0, 0, 0
end

L.rsRows = { { "KILLS", "0" }, { "DEATHS", "0" }, { "ASSISTS", "0" }, { "DAMAGE", "0" }, { "BEST STREAK", "0" } }
function L.roundEnd(team, preview)
    local r, rows = L.rs, L.rsRows
    rows[1][2], rows[2][2], rows[3][2] = tostring(r.kills), tostring(r.deaths), tostring(r.assists)
    rows[4][2], rows[5][2] = tostring(r.dmg), tostring(r.best)
    local lp = entities.GetLocalPlayer()
    local ok, mine = pcall(function() return lp:GetTeamNumber() end)
    mine = ok and mine or 0
    if preview then L.rsTitle, L.rsWin = "VICTORY", true
    elseif team < 2 then L.rsTitle, L.rsWin = "STALEMATE", nil
    elseif mine < 2 then L.rsTitle, L.rsWin = "ROUND OVER", nil
    else
        L.rsWin = (mine == team)
        L.rsTitle = L.rsWin and "VICTORY" or "DEFEAT"
        L.react(L.rsWin and "roundWin" or "roundLose")
    end
    L.rsAt = now()
end

-- my own health, ammo and speed, read 10 times a second
function L.pollSelf()
    local h = L.hp
    local t = now()
    if t - h.at < 0.1 then return end
    h.at = t
    local lp = entities.GetLocalPlayer()
    local was = h.alive
    if not lp then h.alive = false; return end
    local okA, alive = pcall(lp.IsAlive, lp)
    h.alive = (okA and alive) and true or false
    if not h.alive then h.low = false; return end
    local hp, mx = lp:GetHealth() or 0, lp:GetMaxHealth() or 1
    if hp ~= h.hp then h.hp, h.hpS = hp, L.num(hp) end
    h.max = max(1, mx)
    local okV, v = pcall(lp.EstimateAbsVelocity, lp)
    h.speed = (okV and v) and sqrt(v.x * v.x + v.y * v.y) or 0

    local clip, res = -1, -1
    local okW, w = pcall(lp.GetPropEntity, lp, "m_hActiveWeapon")
    if okW and w and w:IsValid() then
        local ok1, c = pcall(w.GetPropInt, w, "LocalWeaponData", "m_iClip1")
        local ok2, kind = pcall(w.GetPropInt, w, "LocalWeaponData", "m_iPrimaryAmmoType")
        if ok1 and c and c >= 0 and c < 500 then clip = c end
        if ok2 and kind and kind > 0 and kind < 30 then
            local ok3, tbl = pcall(lp.GetPropDataTableInt, lp, "localdata", "m_iAmmo")
            local r = ok3 and type(tbl) == "table" and tbl[kind + 1]
            if r and r >= 0 and r < 2000 then res = r end
        end
    end
    if clip ~= h.clip then h.clip, h.clipS = clip, clip >= 0 and L.num(clip) or "" end
    if res ~= h.res then h.res, h.resS = res, res >= 0 and L.num(res) or "" end

    -- waifu: respawn, low health, nothing happening
    if not was and h.seen then L.react("spawn", 0.35); L.lastAction = t end
    h.seen = true
    local low = hp / h.max < settings.lhAt / 100
    if low and not h.low and t - (h.lowSaid or -99) > 25 then h.lowSaid = t; L.react("lowHp") end
    h.low = low
    if t - L.lastAction > 150 then L.lastAction = t; L.react("bored") end
end

-- session stats card
L.ssRows = { { "Kills", "0" }, { "Deaths", "0" }, { "Assists", "0" }, { "K/D", "0.00" }, { "Best streak", "0" },
             { "Damage", "0" }, { "Time", "0:00" } }
function L.drawStats()
    local s, rows = L.ss, L.ssRows
    local t = now()
    if not L.ssAt or t - L.ssAt > 0.5 then
        L.ssAt = t
        rows[1][2], rows[2][2], rows[3][2] = tostring(s.kills), tostring(s.deaths), tostring(s.assists)
        rows[4][2] = string.format("%.2f", s.kills / max(1, s.deaths))
        rows[5][2], rows[6][2] = tostring(s.best), tostring(s.dmg)
        local sec = floor(t - s.t0)
        rows[7][2] = sec >= 3600 and string.format("%d:%02d:%02d", sec // 3600, sec % 3600 // 60, sec % 60)
                     or string.format("%d:%02d", sec // 60, sec % 60)
    end
    local st = settings.phStyle
    local _, sh = draw.GetScreenSize()
    local W, rh, head = 180, 21, L.PH[st] or 32
    local H = head + #rows * rh + 10
    local x, y = draggable("ss", 14, sh / 2 - H / 2, W, H)
    local p = L.palFor(st, settings.phGrad)
    L.panelBg(st, x, y, W, H, st == 6 and "SESSION" or "Session", settings.phBorder, settings.phGrad)
    for i, r in ipairs(rows) do
        local ry = y + head + 4 + (i - 1) * rh
        L.pt(p.f, r[1], x + p.pad, ry, rh, p.dim)
        L.pt(p.f, r[2], x + W - p.pad - textW(p.f, r[2]), ry, rh, i == 4 and p.c or p.txt)
    end
end

-- the game's own killfeed is hidden by giving its entries no time on screen, and put back afterwards
function L.kfCvar(off)
    local want = (not off) and settings.kfHide
    if want then
        local t = now()
        if not L.kfHidden then
            local ok, v = pcall(client.GetConVar, "hud_deathnotice_time")
            v = ok and tonumber(v) or 6
            L.kfOld = v > 0 and v or 6
            L.kfHidden, L.kfCheckAt = true, -9
        end
        -- looked at once a second: set again when the game or a config put it back
        if t - L.kfCheckAt > 1 then
            L.kfCheckAt = t
            local ok, v = pcall(client.GetConVar, "hud_deathnotice_time")
            if not ok or tonumber(v) ~= 0 then
                pcall(client.SetConVar, "hud_deathnotice_time", 0)
                pcall(client.Command, "hud_deathnotice_time 0", true)
            end
        end
    elseif L.kfHidden then
        L.kfHidden = false
        pcall(client.SetConVar, "hud_deathnotice_time", L.kfOld or 6)
        pcall(client.Command, "hud_deathnotice_time " .. (L.kfOld or 6), true)
    end
end

-- killfeed: only what I did and what happened to me
function L.drawFeed()
    L.kfCvar()
    if not settings.kfOn then return end
    local f = L.feed
    local t = now()
    local life = settings.kfTime
    for i = #f, 1, -1 do
        if t - f[i].t0 > life + 0.4 then f[i] = nil end
    end
    if #f == 0 and not menu.open then return end
    local sw = draw.GetScreenSize()
    local W, rh = 320, 28
    local x, y = draggable("kf", sw - W - 14, 110, W, 6 * rh)
    if #f == 0 then
        roundRectLine(x, y, W, 6 * rh, 8, T.border, 150)
        textC(F.small, "killfeed", x + W / 2, y, 6 * rh, T.muted)
        return
    end
    local st = settings.phStyle
    local p = L.palFor(st, settings.phGrad)
    local rightSide = x + W / 2 > sw / 2
    local yy = y
    for i = 1, #f do
        local e = f[i]
        local age = t - e.t0
        local aIn = easeOut(age / 0.25)
        local aOut = clamp((life + 0.4 - age) / 0.4, 0, 1)
        local wa, wm, wb = textW(p.fb, e.a), textW(p.f, e.mid), textW(p.fb, e.b)
        local w = p.pad * 2 + 6 + wa + 12 + wm + (wb > 0 and (12 + wb) or 0)
        w = min(W, floor((w + 7) / 8) * 8)
        local ex = round((rightSide and (x + W - w) or x) + (rightSide and 1 or -1) * (1 - aIn) * 26)
        local ey = round(yy)
        local kc = (e.kind == 2) and RED or ((e.kind == 3) and SKY or p.c)
        ALPHA = aIn * aOut
        L.panelBg(st, ex, ey, w, 24, nil, settings.phBorder, settings.phGrad)
        if st ~= 6 then rect(ex + 4, ey + 6, 2, 12, kc) end
        local tx = ex + p.pad + 6
        L.pt(p.fb, e.a, tx, ey, 24, e.kind == 2 and p.txt or kc)
        tx = tx + wa + 12
        L.pt(p.f, e.mid, tx, ey, 24, p.dim)
        if wb > 0 then L.pt(p.fb, e.b, tx + wm + 12, ey, 24, e.kind == 2 and RED or p.txt) end
        ALPHA = 1
        yy = yy + rh * aOut
    end
end

-- the game's own health and ammo are hidden through its "hidehud" setting (8 = the health group), which
-- is only kept while our HUD is shown and put back afterwards
function L.hpCvar(off)
    local want = (not off) and settings.hpOn and settings.hpHide
    if want then
        local t = now()
        if not L.hpHidden then
            local ok, v = pcall(client.GetConVar, "hidehud")
            L.hpOld = (ok and tonumber(v) or 0) // 1 & ~8
            L.hpHidden, L.hpCheckAt = true, -9
        end
        if t - L.hpCheckAt > 1 then
            L.hpCheckAt = t
            local ok, v = pcall(client.GetConVar, "hidehud")
            v = ok and tonumber(v) or 0
            if (v // 1) & 8 == 0 then pcall(client.SetConVar, "hidehud", L.hpOld | 8) end
        end
    elseif L.hpHidden then
        L.hpHidden = false
        pcall(client.SetConVar, "hidehud", L.hpOld or 0)
    end
end

-- health and ammo
function L.drawVitals()
    L.hpCvar()
    if not settings.hpOn then return end
    local h = L.hp
    if not h.alive and not menu.open then return end
    local sw, sh = draw.GetScreenSize()
    local st = settings.phStyle
    local ammo = settings.hpAmmo
    local W, H = ammo and 260 or 170, 52
    local x, y = draggable("hp", sw / 2 - W / 2, sh - H - 46, W, H)
    local p = L.palFor(st, settings.phGrad)
    L.panelBg(st, x, y, W, H, nil, settings.phBorder, settings.phGrad)
    local t = now()
    local frac = clamp(h.hp / h.max, 0, 1)
    local col = frac > 0.5 and mix(GOLD, L.GREEN, (frac - 0.5) * 2) or mix(RED, GOLD, frac * 2)
    if h.hp > h.max then col = SKY end
    local low = h.alive and frac < 0.35
    local pulse = low and (0.55 + 0.45 * sin(t * 9)) or 1
    L.pt(F.iconL, "♥", x + p.pad, y + 5, 28, col, 255 * pulse)
    L.pt(F.big, h.hpS, x + p.pad + 26, y + 4, 30, low and col or p.txt)
    -- bar: the white part shows what was just lost
    local bx, by, bw = x + p.pad, y + H - 14, 146 - p.pad
    local shown = anim("hpbar", frac, 14)
    local ghost = anim("hpghost", frac, 3)
    rect(bx, by, bw, 5, p.track, 220)
    if ghost > shown + 0.005 then rect(bx, by, bw * ghost, 5, C_WHITE, 170) end
    rect(bx, by, bw * shown, 5, col, 255 * pulse)
    if not ammo then return end
    rect(x + 158, y + 10, 1, H - 20, p.dim, 70)
    local rx = x + W - p.pad
    if h.clip >= 0 then
        local rs = h.res >= 0 and h.resS or ""
        local rw = rs ~= "" and textW(p.f, rs) + 14 or 0
        if rs ~= "" then
            L.pt(p.f, rs, rx - rw + 14, y + 12, 26, p.dim)
            L.pt(p.f, "/", rx - rw + 2, y + 12, 26, p.dim)
        end
        L.pt(F.big, h.clipS, rx - rw - 4 - textW(F.big, h.clipS), y + 9, 30, h.clip == 0 and RED or p.txt)
    elseif h.res >= 0 then
        L.pt(F.big, h.resS, rx - textW(F.big, h.resS), y + 9, 30, h.res == 0 and RED or p.txt)
    else
        L.pt(F.big, "—", rx - textW(F.big, "—"), y + 9, 30, p.dim)
    end
    L.pt(F.tiny, "AMMO", x + 168, y + H - 19, 14, p.dim)
end

-- killstreak counter
L.KS_BANNERS = { [5] = "KILLING SPREE", [10] = "UNSTOPPABLE", [15] = "GODLIKE", [20] = "LEGENDARY", [25] = "BEYOND GODLIKE" }
function L.ksColor(n, t)
    if n >= 20 then return sampleStops(logoStops(6), t * 0.3) end
    if n >= 15 then return L.HOT end
    if n >= 10 then return L.ORANGE end
    if n >= 5 then return GOLD end
    if n >= 3 then return accent() end
    return C_WHITE
end
L.KS_STYLES = { "Emblem", "Simple" }
L.KS_DARK, L.KS_PIP = { 12, 12, 17 }, { 60, 60, 72 }
F.ksB = draw.CreateFont("Segoe UI Black", 52, 900, FONTFLAG_ANTIALIAS | FONTFLAG_OUTLINE)
function L.ksTitle(n)
    if n >= 25 then return "BEYOND GODLIKE" end
    if n >= 20 then return "LEGENDARY" end
    if n >= 15 then return "GODLIKE" end
    if n >= 10 then return "UNSTOPPABLE" end
    if n >= 5 then return "KILLING SPREE" end
    if n >= 3 then return "ON A ROLL" end
    return "KILLSTREAK"
end

function L.ksBannerDraw(cxm, by, a, col, t)
    if not (settings.ksBanner and L.ksBannerAt) then return end
    local b = t - L.ksBannerAt
    if b >= 2.6 then return end
    ALPHA = a * easeOut(b / 0.25) * clamp((2.6 - b) / 0.5, 0, 1)
    by = by + (1 - easeOut(b / 0.3)) * 10
    local bw = textW(F.bold, L.ksBannerS) + 28
    roundRect(cxm - bw / 2, by, bw, 26, 13, C_BLACK, 150)
    roundRectLine(cxm - bw / 2, by, bw, 26, 13, col, 200)
    textC(F.bold, L.ksBannerS, cxm, by, 26, col)
end

function L.drawStreak()
    local n = me.streak
    local a = anim("ksA", (n >= settings.ksMin or menu.open) and 1 or 0, 10)
    if a < 0.02 then return end
    local sw, sh = draw.GetScreenSize()
    local t = now()
    local col = L.ksColor(n, t)
    local u = clamp((t - (L.ksAt or -9)) / 0.45, 0, 1)

    if settings.ksStyle == 2 then
        local W, H = 130, 72
        local x, y = draggable("ks", sw / 2 - W / 2, sh * 0.7, W, H)
        local cxm = x + W / 2
        ALPHA = a
        if u < 1 then L.thickRing(cxm, y + 28, 18 + 34 * easeOut(u), 3, col, 210 * (1 - u)) end
        textC(F.ksN, L.num(n), cxm, y + 4 - (1 - easeOutBack(u)) * 12, 46, col)
        textC(F.tiny, "KILLSTREAK", cxm + 1, y + 53, 16, C_BLACK, 190)
        textC(F.tiny, "KILLSTREAK", cxm, y + 52, 16, mix(C_WHITE, col, 0.35))
        L.ksBannerDraw(cxm, y + H + 2, a, col, t)
        ALPHA = 1
        return
    end

    local W, H, R = 140, 118, 31
    local x, y = draggable("ks", sw / 2 - W / 2, sh * 0.68, W, H)
    local cxm, cym = x + W / 2, y + 44
    local tier = min(5, n // 5)
    local breathe = 0.5 + 0.5 * sin(t * (2 + tier))
    ALPHA = a
    -- glow, stronger with every tier
    disc(cxm, cym, R + 14 + 3 * breathe, col, 14 + tier * 5)
    disc(cxm, cym, R + 7 + 2 * breathe, col, 26 + tier * 7)
    -- embers rising from the emblem from 5 kills on
    if tier >= 1 then
        for i = 1, 4 + tier * 2 do
            local ph = (t * (0.55 + (i % 3) * 0.12) + i * 0.37) % 1
            local ex = cxm + sin(i * 2.4 + t * 1.3) * R * 0.75 * (1 - ph * 0.4)
            disc(ex, cym - R * 0.5 - ph * 46, 3.2 * (1 - ph) + 1, mix(col, GOLD, ph), 210 * (1 - ph))
        end
    end
    disc(cxm, cym, R, L.KS_DARK, 225)
    L.thickRing(cxm, cym, R, 3, col, 235)
    ring(cxm, cym, R - 5, col, 70, 40)
    -- dots circling the emblem, more of them at higher tiers
    local dots = 2 + tier * 2
    for i = 1, dots do
        local ang = t * (1.2 + tier * 0.25) + i * (2 * pi / dots)
        disc(cxm + cos(ang) * (R + 7), cym + sin(ang) * (R + 7), 2, col, 230)
    end
    -- a kill: shockwave, sparks flying off, the number jumps
    if u < 1 then
        local e = easeOut(u)
        L.thickRing(cxm, cym, R + 6 + 40 * e, 3, col, 220 * (1 - u))
        for i = 0, 11 do
            local ang = i * (pi / 6) + 0.26
            local r0, len = R + 6 + 34 * e, 9 * (1 - u)
            line(cxm + cos(ang) * r0, cym + sin(ang) * r0, cxm + cos(ang) * (r0 + len), cym + sin(ang) * (r0 + len), C_WHITE, 255 * (1 - u))
        end
    end
    local big = u < 0.3
    textC(big and F.ksB or F.ksN, L.num(n), cxm, cym - (big and 31 or 25) - (1 - easeOutBack(u)) * 6, big and 60 or 48, col)
    if u < 0.5 then textC(big and F.ksB or F.ksN, L.num(n), cxm, cym - (big and 31 or 25), big and 60 or 48, C_WHITE, 200 * (1 - u * 2)) end
    -- five pips: how far to the next tier
    local filled = n % 5
    for i = 1, 5 do
        local px = cxm + (i - 3) * 13
        disc(px, y + 88, 4, C_BLACK, 170)
        disc(px, y + 88, 3, i <= filled and col or L.KS_PIP, 255)
        if i == filled and u < 1 then disc(px, y + 88, 3 + 5 * (1 - u), col, 150 * (1 - u)) end
    end
    local title = L.ksTitle(n)
    textC(F.tiny, title, cxm + 1, y + 99, 16, C_BLACK, 200)
    textC(F.tiny, title, cxm, y + 98, 16, mix(C_WHITE, col, 0.55))
    L.ksBannerDraw(cxm, y + H + 4, a, col, t)
    ALPHA = 1
end

-- round summary: slides in under the top of the screen when a round ends
function L.drawRound()
    if not L.rsAt then return end
    local t = now()
    local age = t - L.rsAt
    local life = settings.rsTime
    if age > life then L.rsAt = nil; return end
    local sw = draw.GetScreenSize()
    local st = settings.phStyle
    local W, H = 420, 104
    local x, y = draggable("rs", sw / 2 - W / 2, 130, W, H)
    local aIn = easeOut(age / 0.35)
    local a = aIn * clamp((life - age) / 0.5, 0, 1)
    y = round(y - (1 - aIn) * 24)
    local p = L.palFor(st, settings.phGrad)
    ALPHA = a
    L.panelBg(st, x, y, W, H, nil, settings.phBorder, settings.phGrad)
    local tc = (L.rsWin == true) and L.GREEN or ((L.rsWin == false) and RED or p.c)
    local tw = textW(F.big, L.rsTitle)
    L.pt(F.big, L.rsTitle, x + W / 2 - tw / 2, y + 8, 30, tc)
    rect(x + W / 2 - 60 * aIn, y + 42, 120 * aIn, 2, tc, 200)
    local cwid = (W - 20) / 5
    for i, r in ipairs(L.rsRows) do
        local ccx = x + 10 + (i - 0.5) * cwid
        -- each number arrives a little after the one before
        local ia = easeOut((age - 0.15 - i * 0.07) / 0.3)
        ALPHA = a * ia
        L.pt(p.fb, r[2], ccx - textW(p.fb, r[2]) / 2, y + 50 + (1 - ia) * 6, 24, i == 1 and p.c or p.txt)
        L.pt(F.tiny, r[1], ccx - textW(F.tiny, r[1]) / 2, y + 76, 16, p.dim)
    end
    -- time left
    ALPHA = a
    rect(x + 14, y + H - 5, (W - 28) * (1 - age / life), 2, tc, 150)
    ALPHA = 1
end

-- red (or any colour) screen edges while my health is low, beating like a heart
function L.drawLowHealth()
    local h = L.hp
    local thr = settings.lhAt / 100
    local frac = h.hp / h.max
    local k = anim("lowhp", (h.alive and frac < thr) and (1 - frac / thr * 0.6) or 0, 6)
    if k < 0.01 then return end
    local c = L.hex(settings.colLow) or L.HOT
    local beat = 1
    if settings.lhPulse then
        local ph = (now() * (1.1 + (1 - frac / thr) * 0.9)) % 1
        beat = 0.5 + 0.5 * max(math.exp(-((ph - 0.1) ^ 2) / 0.004), 0.7 * math.exp(-((ph - 0.32) ^ 2) / 0.006))
    end
    local _, sh = draw.GetScreenSize()
    local a = 255 * settings.lhInt / 100 * k * beat
    local size = sh * (0.14 + 0.1 * k)
    edgeFade("top", size, c, a * 0.8)
    edgeFade("bottom", size, c, a)
    edgeFade("left", size * 1.3, c, a * 0.9)
    edgeFade("right", size * 1.3, c, a * 0.9)
end

-- custom crosshair
L.CH_SHAPES = { "Cross", "Cross + dot", "Dot", "Circle", "Circle + dot", "T shape", "X", "Square" }
L.CH_ANIMS = { "Off", "Pulse", "Spin", "Breathing gap", "Heartbeat", "Blink" }

-- one arm along the screen axes (sharp), dir: 0 right, 1 down, 2 left, 3 up
function L.chArmAA(cx, cy, dir, r0, len, th, c, a, ol)
    local x, y, w, h
    local o = floor(th / 2)
    if dir == 0 then x, y, w, h = cx + r0, cy - o, len, th
    elseif dir == 1 then x, y, w, h = cx - o, cy + r0, th, len
    elseif dir == 2 then x, y, w, h = cx - r0 - len, cy - o, len, th
    else x, y, w, h = cx - o, cy - r0 - len, th, len end
    if ol then rect(x - 1, y - 1, w + 2, h + 2, C_BLACK, a * 0.85) end
    rect(x, y, w, h, c, a)
end
-- one arm at any angle
function L.chArm(cx, cy, ang, r0, r1, th, c, a, ol)
    local dx, dy = cos(ang), sin(ang)
    local nx, ny = -dy, dx
    if ol then
        local e = th / 2 + 0.5
        local ax, ay, bx, by = cx + dx * (r0 - 1), cy + dy * (r0 - 1), cx + dx * (r1 + 1), cy + dy * (r1 + 1)
        for o = -e, e, 0.5 do line(ax + nx * o, ay + ny * o, bx + nx * o, by + ny * o, C_BLACK, a * 0.6) end
    end
    local hw = (th - 1) / 2
    local ax, ay, bx, by = cx + dx * r0, cy + dy * r0, cx + dx * r1, cy + dy * r1
    for o = -hw, hw, 0.5 do line(ax + nx * o, ay + ny * o, bx + nx * o, by + ny * o, c, a) end
end

-- the game's own crosshair is hidden while ours is shown, and put back afterwards
function L.chCvar(off)
    local want = (not off) and settings.chOn and settings.chHide
    if want == (L.chHidden or false) then return end
    if want then
        local ok, v = pcall(client.GetConVar, "crosshair")
        L.chOld = (ok and tonumber(v)) or 1
        if L.chOld == 0 then L.chOld = 1 end
        pcall(client.SetConVar, "crosshair", 0)
    else
        pcall(client.SetConVar, "crosshair", L.chOld or 1)
    end
    L.chHidden = want
end

function L.drawCrosshair()
    L.chCvar()
    if not settings.chOn or not L.hp.alive then return end
    local okU, ui = pcall(engine.IsGameUIVisible)
    if okU and ui then return end
    L.screenSpace()
    local sw, sh = draw.GetScreenSize()
    local cx, cy = floor(sw / 2), floor(sh / 2)
    local t = now()
    local sp = settings.chSpeed / 5
    local size, gap, th = settings.chSize, settings.chGap, settings.chThick
    local rot, alpha, scale = 0, 255 * settings.chAlpha / 100, 1
    local an = settings.chAnim
    if an == 2 then scale = 1 + 0.22 * sin(t * 4 * sp)
    elseif an == 3 then rot = (t * 1.6 * sp) % (2 * pi)
    elseif an == 4 then gap = gap + (0.5 + 0.5 * sin(t * 3 * sp)) * max(3, size * 0.5)
    elseif an == 5 then
        local ph = (t * 1.2 * sp) % 1
        scale = 1 + 0.35 * max(math.exp(-((ph - 0.1) ^ 2) / 0.004), 0.7 * math.exp(-((ph - 0.32) ^ 2) / 0.006))
    elseif an == 6 then alpha = alpha * (0.3 + 0.7 * (0.5 + 0.5 * sin(t * 5 * sp))) end
    if settings.chMove then gap = gap + anim("chmove", min(1, L.hp.speed / 400), 10) * 8 end
    if settings.chFire then gap = gap + anim("chfire", (mouse.held and not menu.open) and 1 or 0, 18) * 4 end

    local c = L.hex(settings.colCh) or C_WHITE
    local gs = L.gradStops(settings.chGrad)
    if gs then c = sampleStops(gs, t * 0.25) end
    local hk = 1 - clamp((t - (L.chHitAt or -9)) / 0.22, 0, 1)
    if settings.chHit and hk > 0 then
        gap = gap + hk * hk * 6
        c = mix(c, L.hex(settings.colHit) or RED, hk)
    end
    local kk = 1 - clamp((t - (L.chKillAt or -9)) / 0.45, 0, 1)
    if settings.chKill and kk > 0 then
        c = mix(c, L.hex(settings.colKill) or L.GREEN, kk)
        rot = rot + (1 - easeOut(1 - kk)) * pi / 2
        L.thickRing(cx, cy, gap + size + 16 * (1 - kk), 2, c, alpha * 0.8 * kk)
    end
    size, gap = size * scale, gap * scale

    local shape = settings.chShape
    local ol = settings.chOutline
    if shape == 1 or shape == 2 or shape == 6 or shape == 7 then
        if shape == 7 then rot = rot + pi / 4 end
        for i = 0, 3 do
            if not (shape == 6 and i == 3) then
                if rot == 0 then L.chArmAA(cx, cy, i, round(gap), round(size), th, c, alpha, ol)
                else L.chArm(cx, cy, rot + i * pi / 2, gap, gap + size, th, c, alpha, ol) end
            end
        end
    elseif shape == 4 or shape == 5 then
        local r = gap + size / 2
        if ol then
            ring(cx, cy, r + th / 2 + 1, C_BLACK, alpha * 0.85, 40)
            ring(cx, cy, r - th / 2 - 1, C_BLACK, alpha * 0.85, 40)
        end
        L.thickRing(cx, cy, r, th, c, alpha)
    elseif shape == 8 then
        local hf = round(gap + size / 2)
        if ol then
            rect(cx - hf - 1, cy - hf - 1, 2 * hf + 2, th + 2, C_BLACK, alpha * 0.85)
            rect(cx - hf - 1, cy + hf - th - 1, 2 * hf + 2, th + 2, C_BLACK, alpha * 0.85)
            rect(cx - hf - 1, cy - hf - 1, th + 2, 2 * hf + 2, C_BLACK, alpha * 0.85)
            rect(cx + hf - th - 1, cy - hf - 1, th + 2, 2 * hf + 2, C_BLACK, alpha * 0.85)
        end
        rect(cx - hf, cy - hf, 2 * hf, th, c, alpha)
        rect(cx - hf, cy + hf - th, 2 * hf, th, c, alpha)
        rect(cx - hf, cy - hf, th, 2 * hf, c, alpha)
        rect(cx + hf - th, cy - hf, th, 2 * hf, c, alpha)
    end
    if shape == 3 then
        local r = max(1, round(size / 3))
        if ol then disc(cx, cy, r + 1, C_BLACK, alpha * 0.85) end
        disc(cx, cy, r, c, alpha)
    elseif shape == 2 or shape == 5 then
        local o = floor(th / 2)
        if ol then rect(cx - o - 1, cy - o - 1, th + 2, th + 2, C_BLACK, alpha * 0.85) end
        rect(cx - o, cy - o, th, th, c, alpha)
    end
end

---------------------------------------------------------------------------
-- 8p. Hit particles: a burst at the spot where the player I hit was standing
---------------------------------------------------------------------------
L.PT_STYLES = { "Explosion", "Sparks", "Embers", "Blood", "Stars", "Confetti", "Flakes", "Lightning", "Hit spark", "Neon" }
L.PT_COLORS = { "The style's own colours", "My hit and kill colours" }
L.PT_LEN = { 1.1, 0.95, 1.5, 0.75, 1.15, 1.6, 1.6, 0.9, 0.6, 1.4 }
L.PTC = { hot = { 255, 190, 90 }, fire = { 255, 130, 36 }, smoke = { 58, 50, 52 }, spark = { 255, 236, 170 },
          ember = { 255, 150, 50 }, emberIn = { 110, 26, 8 }, emberGlow = { 255, 84, 18 }, blood = { 205, 12, 24 },
          bloodD = { 104, 0, 10 }, cyan = { 40, 235, 255 }, cyanL = { 190, 252, 255 }, neonG = { 70, 255, 120 },
          neonP = { 190, 80, 255 }, neonPL = { 236, 170, 255 } }
L.pt3 = { list = {}, at = 0 }
for i = 1, 8 do L.pt3.list[i] = { t0 = -99, x = 0, y = 0, z = 0, kill = false, seed = 0, style = 1 } end

function L.ptAt(x, y, z, kill)
    local P = L.pt3
    P.at = P.at % 8 + 1
    local b = P.list[P.at]
    b.t0, b.x, b.y, b.z, b.kill, b.seed = now(), x, y, z, kill, math.random() * 1000
    b.style = kill and settings.ptKillStyle or settings.ptStyle
end

function L.ptSpawn(ent, kill)
    if not settings.ptOn or not ent then return end
    if kill and not settings.ptKill then return end
    if not kill and not settings.ptHit then return end
    local ok, pos = pcall(L.originOf, ent)
    if ok and pos then
        L.ptAt(pos.x, pos.y, pos.z + 48, kill)
        L.pt3.made = (L.pt3.made or 0) + 1
    else
        L.pt3.err = "couldn't find where the player stands"
    end
end

-- the menu's test button: a burst a few steps in front of me
function L.ptTest(kill)
    local lp = entities.GetLocalPlayer()
    if not lp then notify("✸", "Hit particles", "Join a map to see them", accent()); return end
    local ok, pos = pcall(L.originOf, lp)
    local okA, ang = pcall(engine.GetViewAngles)
    if not ok or not pos then return end
    local yaw = (okA and ang and ang.y or 0) * pi / 180
    L.ptAt(pos.x + cos(yaw) * 170, pos.y + sin(yaw) * 170, pos.z + 52, kill)
end

function L.w2s(v)
    local a, b = client.WorldToScreen(v)
    if type(a) == "table" then return a[1], a[2] end
    if a then return a, b end
end

-- where particle i of a burst is after t seconds: thrown out at an angle, slowed by the air, pulled down.
-- right and up, in world units
function L.ptPos(seed, i, t, speed, drag, grav)
    local ang = L.rnd(seed, i) * 6.2832
    local sp = speed * (0.35 + 0.65 * L.rnd(seed, i + 100))
    local d = (1 - math.exp(-drag * t)) / drag
    return cos(ang) * sp * d, sin(ang) * sp * d - 0.5 * grav * t * t
end

function L.ptBurst(b, el, ox, oy, k)
    local style, seed, kill = b.style, b.seed, b.kill
    local len = L.PT_LEN[style] or 1
    local e = el / len
    local amt = settings.ptAmt / 100 * (kill and 1.5 or 1)
    local tint = settings.ptCol == 2 and (L.hex(kill and settings.colKill or settings.colHit) or accent()) or nil
    local C = L.PTC

    if style == 1 then
        if el < 0.2 then
            local f = el / 0.2
            disc(ox, oy, 95 * k * easeOut(f), tint or C.hot, 130 * (1 - f))
            disc(ox, oy, (22 + 46 * easeOut(f)) * k, C_WHITE, 235 * (1 - f))
        end
        disc(ox, oy, (46 + 44 * e) * k, tint or C.fire, 95 * (1 - e) * (1 - e))
        for i = 1, min(26, floor(11 * amt)) do
            local u, v = L.ptPos(seed, i, el, 78, 2.2, -34)
            local r = (12 + 28 * e) * k * (0.6 + 0.8 * L.rnd(seed, i + 300))
            disc(ox + u * k, oy - v * k, r, mix(tint or C.fire, C.smoke, min(1, e * 1.7)), 150 * (1 - e))
        end
        if el < 0.45 then
            for i = 1, min(18, floor(9 * amt)) do
                local u1, v1 = L.ptPos(seed, 400 + i, el, 460, 5, 0)
                local u0, v0 = L.ptPos(seed, 400 + i, max(0, el - 0.06), 460, 5, 0)
                line(ox + u0 * k, oy - v0 * k, ox + u1 * k, oy - v1 * k, tint or C.hot, 255 * (1 - el / 0.45))
            end
        end

    elseif style == 2 then
        if el < 0.1 then disc(ox, oy, (10 + 26 * el / 0.1) * k, C_WHITE, 220 * (1 - el / 0.1)) end
        for i = 1, min(80, floor(44 * amt)) do
            local life = 0.4 + 0.5 * L.rnd(seed, i + 200)
            if el < life then
                local u1, v1 = L.ptPos(seed, i, el, 340, 3.2, 430)
                local u0, v0 = L.ptPos(seed, i, max(0, el - 0.045), 340, 3.2, 430)
                local a = 255 * (1 - el / life)
                local x1, y1 = ox + u1 * k, oy - v1 * k
                line(ox + u0 * k, oy - v0 * k, x1, y1, (i % 3 == 0) and C_WHITE or (tint or C.spark), a)
                if i % 4 == 0 then disc(x1, y1, max(1.5, 2.2 * k), C_WHITE, a) end
            end
        end

    elseif style == 3 then
        for i = 1, min(60, floor(30 * amt)) do
            local life = 0.8 + 0.6 * L.rnd(seed, i + 200)
            if el < life then
                local u, v = L.ptPos(seed, i, el, 150, 2.6, -40)
                local x, y = ox + u * k, oy - v * k
                local fade = 1 - el / life
                local fl = 0.6 + 0.4 * sin(el * 14 + i)
                local sz = max(2.5, (3 + 5 * L.rnd(seed, i + 300)) * k)
                disc(x, y, sz * 2.4, tint or C.emberGlow, 60 * fl * fade)
                local a0 = L.rnd(seed, i + 500) * 6.28 + el * (1.5 + 3 * L.rnd(seed, i + 600))
                local x1, y1 = x + cos(a0) * sz, y + sin(a0) * sz
                local x2, y2 = x + cos(a0 + 2.2) * sz * 0.9, y + sin(a0 + 2.2) * sz * 0.9
                local x3, y3 = x + cos(a0 + 4.1) * sz * 0.8, y + sin(a0 + 4.1) * sz * 0.8
                cpoly(tint or C.ember, 240 * fade, x1, y1, x2, y2, x3, y3)
                cpoly(C.emberIn, 220 * fade, x + (x1 - x) * 0.5, y + (y1 - y) * 0.5, x + (x2 - x) * 0.5, y + (y2 - y) * 0.5,
                      x + (x3 - x) * 0.5, y + (y3 - y) * 0.5)
            end
        end

    elseif style == 4 then
        disc(ox, oy, (18 + 42 * e) * k, tint or C.bloodD, 120 * (1 - e))
        for i = 1, min(60, floor(28 * amt)) do
            local u, v = L.ptPos(seed, i, el, 230, 2.5, 520)
            local r = max(1.5, (1.6 + 3 * L.rnd(seed, i + 300)) * k)
            disc(ox + u * k, oy - v * k, r, mix(tint or C.blood, C.bloodD, L.rnd(seed, i + 400)), 235 * (1 - e))
        end

    elseif style == 5 then
        for i = 1, min(36, floor(14 * amt)) do
            local u, v = L.ptPos(seed, i, el, 175, 2.4, 60)
            local x, y = ox + u * k, oy - v * k
            local tw = 0.45 + 0.55 * abs(sin(el * 9 + i * 2))
            local r = max(3, (5 + 6 * L.rnd(seed, i + 300)) * k) * tw
            local c = mix(tint or GOLD, C_WHITE, L.rnd(seed, i + 400))
            local a = 255 * (1 - e)
            disc(x, y, r * 1.6, c, 40 * (1 - e))
            line(x - r, y, x + r, y, c, a)
            line(x, y - r, x, y + r, c, a)
            line(x - r * 0.45, y - r * 0.45, x + r * 0.45, y + r * 0.45, c, a * 0.7)
            line(x - r * 0.45, y + r * 0.45, x + r * 0.45, y - r * 0.45, c, a * 0.7)
            disc(x, y, max(1.5, r * 0.3), C_WHITE, a)
        end

    elseif style == 7 then
        -- flakes: glowing chips swirling up in a column over the body
        local col = tint or C.cyan
        for i = 1, min(90, floor(46 * amt)) do
            local life = 0.9 + 0.7 * L.rnd(seed, i + 200)
            local tt = el - L.rnd(seed, i + 700) * 0.35
            if tt > 0 and tt < life then
                local f = tt / life
                local ang = L.rnd(seed, i) * 6.28 + tt * (2.5 + 2 * L.rnd(seed, i + 50))
                local rad = (5 + 13 * L.rnd(seed, i + 100)) * (1 - 0.4 * f)
                local x = ox + cos(ang) * rad * k
                local y = oy + (22 - L.rnd(seed, i + 150) * 30 - tt * (48 + 40 * L.rnd(seed, i + 400))) * k
                local sz = max(2, (2.4 + 3 * L.rnd(seed, i + 300)) * k)
                local a = 255 * (1 - f) * min(1, tt / 0.08)
                disc(x, y, sz * 2.6, col, 34 * (1 - f))
                local sp = tt * 9 + i
                cpoly(mix(col, C.cyanL, L.rnd(seed, i + 500)), a, x + cos(sp) * sz, y + sin(sp) * sz * 0.6,
                      x + cos(sp + 2.4) * sz * 0.8, y + sin(sp + 2.4) * sz, x + cos(sp + 4.2) * sz * 0.7, y + sin(sp + 4.2) * sz * 0.5)
            end
        end

    elseif style == 8 then
        -- lightning: a bright beam from the sky onto the spot with bolts crackling round it
        local col = tint or C.cyan
        local fade = (el < 0.08) and (el / 0.08) or (1 - e) ^ 1.3
        local top = -40
        local w = max(3, 7 * k) * (0.7 + 0.3 * fade)
        local flick = 0.75 + 0.25 * sin(el * 60)
        rect(ox - w * 3.5, top, w * 7, oy - top, col, 34 * fade * flick)
        rect(ox - w * 1.6, top, w * 3.2, oy - top, col, 90 * fade * flick)
        rect(ox - w * 0.5, top, w, oy - top, C_WHITE, 235 * fade)
        disc(ox, oy, (16 + 24 * e) * k, col, 120 * fade)
        disc(ox, oy, 8 * k, C_WHITE, 220 * fade)
        L.screenSpace()
        local frame = floor(el * 24)
        for b = 1, 4 do
            local px, py = ox, oy - L.rnd(seed + frame, b) * 70 * k
            local dir = (b % 2 == 0) and 1 or -1
            for st = 1, 6 do
                local nx = px + dir * (6 + 10 * L.rnd(seed + frame, b * 10 + st)) * k
                local ny = py + (L.rnd(seed + frame, b * 20 + st) - 0.5) * 22 * k
                tline(px, py, nx, ny, max(2, 3 * k), col, 120 * fade)
                line(px, py, nx, ny, C_WHITE, 230 * fade)
                px, py = nx, ny
            end
        end
        for i = 1, min(30, floor(14 * amt)) do
            local u, v = L.ptPos(seed, i, el, 260, 3, 300)
            disc(ox + u * k, oy - v * k, max(1.5, 2 * k), mix(col, C_WHITE, 0.5), 230 * (1 - e))
        end

    elseif style == 9 then
        -- hit spark: thin white streaks thrown wide, a short flash
        if el < 0.07 then disc(ox, oy, (8 + 30 * el / 0.07) * k, C_WHITE, 200 * (1 - el / 0.07)) end
        for i = 1, min(60, floor(28 * amt)) do
            local life = 0.25 + 0.35 * L.rnd(seed, i + 200)
            if el < life then
                local u1, v1 = L.ptPos(seed, i, el, 620, 4.5, 160)
                local u0, v0 = L.ptPos(seed, i, max(0, el - 0.03), 620, 4.5, 160)
                local a = 255 * (1 - el / life)
                local x0, y0, x1, y1 = ox + u0 * k, oy - v0 * k, ox + u1 * k, oy - v1 * k
                local c = tint and mix(tint, C_WHITE, 0.6) or C_WHITE
                tline(x0, y0, x1, y1, max(1.5, 2.2 * k), c, a * 0.5)
                line(x0, y0, x1, y1, C_WHITE, a)
            end
        end

    elseif style == 10 then
        -- neon: spinning triangle outlines, glowing orbs, a green bolt and a purple haze
        local fade = (1 - e) ^ 1.2
        L.screenSpace()
        for i = 1, min(12, floor(6 * amt)) do
            local u, v = L.ptPos(seed, i, el, 150, 2.2, -10)
            local x, y = ox + u * k, oy - v * k
            local r = (7 + 7 * L.rnd(seed, i + 300)) * k
            local rot = L.rnd(seed, i + 400) * 6.28 + el * (2 + 3 * L.rnd(seed, i + 500))
            local c = tint or C.cyan
            for ln = 0, 2 do
                local a1, a2 = rot + ln * 2.094, rot + (ln + 1) * 2.094
                tline(x + cos(a1) * r, y + sin(a1) * r, x + cos(a2) * r, y + sin(a2) * r, max(2, 2.6 * k), c, 90 * fade)
                line(x + cos(a1) * r, y + sin(a1) * r, x + cos(a2) * r, y + sin(a2) * r, C.cyanL, 240 * fade)
            end
        end
        for i = 1, min(20, floor(10 * amt)) do
            local u, v = L.ptPos(seed, 50 + i, el, 120, 2, -20)
            local x, y = ox + u * k, oy - v * k
            local r = max(2, (2 + 3 * L.rnd(seed, i + 600)) * k)
            disc(x, y, r * 2.5, C.neonP, 60 * fade)
            disc(x, y, r, C.neonPL, 230 * fade)
        end
        if el < 0.5 then
            local bf = 1 - el / 0.5
            local frame = floor(el * 20)
            local px, py = ox - 50 * k, oy - 60 * k
            for st = 1, 8 do
                local nx = px + (12 + 4 * L.rnd(seed + frame, st)) * k
                local ny = py + (8 + 14 * (L.rnd(seed + frame, st + 9) - 0.3)) * k
                tline(px, py, nx, ny, max(2, 3.5 * k), C.neonG, 110 * bf)
                line(px, py, nx, ny, C_WHITE, 230 * bf)
                px, py = nx, ny
            end
        end

    else
        for i = 1, min(80, floor(36 * amt)) do
            local u, v = L.ptPos(seed, i, el, 250, 2.8, 250)
            local w = max(1, 5.5 * k * abs(sin(el * 9 + i)))
            local h = max(2, 3.6 * k)
            rect(ox + u * k - w / 2, oy - v * k - h / 2, w, h, tint and mix(tint, C_WHITE, L.rnd(seed, i + 300))
                 or sampleStops(logoStops(6), L.rnd(seed, i + 300)), 245 * (1 - e * e))
        end
    end
end

function L.drawParticles()
    local P = L.pt3
    local t = now()
    local v = P.vec
    for i = 1, 8 do
        local b = P.list[i]
        local el = t - b.t0
        if el >= 0 and el < (L.PT_LEN[b.style] or 1) then
            if not v then v = Vector3(0, 0, 0); P.vec = v; L.screenSpace() end
            v.x, v.y, v.z = b.x, b.y, b.z
            local sx, sy = L.w2s(v)
            v.z = b.z + 20
            local _, sy2 = L.w2s(v)
            if sx and sy2 then
                -- how many pixels one world unit is at that distance
                local ppu = abs(sy - sy2) / 20
                if ppu > 0.03 then
                    L.screenSpace()
                    -- one broken burst must not stop the others
                    local ok, err = pcall(L.ptBurst, b, el, sx, sy, min(6, ppu) * settings.ptSize / 100)
                    ALPHA = 1
                    if ok then P.drawn = (P.drawn or 0) + 1
                    elseif not tostring(err):find("Color not set", 1, true) then
                        P.err = (L.PT_STYLES[b.style] or "?") .. ": " .. tostring(err):gsub("^.-destiny%.lua:", "line ")
                    else L.ccOk = false end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- 8q. Pets: an animated sprite that walks along with me (only I see it). Each animation is one picture with
-- 8 rows (the pet seen from 8 sides, row 1 from the front, then turning round it) and 8 frames per row.
---------------------------------------------------------------------------
L.PETS = {
    { "Klee", "klee", height = 34, len = { idle = 2, walk = 0.8, run = 0.55, crouch = 1.35, jump = 0.8 } },
    { "Mechanical Cat", "mechanical_cat", height = 32, tall = 0.7185, len = { idle = 2, walk = 0.8, run = 0.55, crouch = 1.35, jump = 0.8 } },
    { "Chiikawa", "chiikawa", height = 26, tall = 0.7185, len = { idle = 2, walk = 0.8, run = 0.55, crouch = 1.35, jump = 0.8 } },
    { "Kafka", "kafka", height = 42, tall = 0.7185, len = { idle = 2.4, walk = 0.9, run = 0.6, crouch = 2, jump = 0.8 } },
    { "Elfaria", "elfaria", height = 40, tall = 0.7185, len = { idle = 2.4, walk = 0.9, run = 0.6, crouch = 2, jump = 0.8 } },
    { "Lady Avalon", "lady_avalon", height = 40, tall = 0.7185, len = { idle = 2.4, walk = 0.9, run = 0.6, crouch = 2, jump = 0.8 } },
    { "2B", "2b", height = 40, tall = 0.7185, len = { idle = 2.4, walk = 0.9, run = 0.6, crouch = 2, jump = 0.8 } },
    { "Raiden Shogun", "raiden", height = 42, tall = 0.7185, len = { idle = 2.4, walk = 0.9, run = 0.6, crouch = 2, jump = 0.8 } },
    { "Niko", "niko", height = 30, tall = 0.7185, len = { idle = 2.4, walk = 0.9, run = 0.6, crouch = 2, jump = 0.8 } },
    { "Spice", "spice", height = 40, tall = 0.7185, len = { idle = 2.4, walk = 0.9, run = 0.6, crouch = 2, jump = 0.8 } },
}
L.PET_ANIMS = { "idle", "walk", "run", "crouch", "jump" }
L.PET_SIDES = { "Left", "Right", "Roams around me" }
-- in each 256 px cell the feet are at 228 and the top of the head at 22
L.PET_FEET, L.PET_TALL = 228 / 256, 206 / 256
L.pet = { tex = {}, texFor = nil, x = 0, y = 0, z = 0, gz = 0, yaw = 0, tyaw = 0, anim = "idle", t0 = 0, traceAt = 0,
          seen = 1, placed = false, q = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } } }

function L.pet.free()
    local Q = L.pet
    for _, id in pairs(Q.tex) do if id then pcall(draw.DeleteTexture, id) end end
    Q.tex, Q.texFor, Q.err = {}, nil, nil
end

-- the names in the pet dropdown, rebuilt when a downloaded pet joins
function L.petNameList()
    if not L.petNames then
        L.petNames = {}
        for i, p in ipairs(L.PETS) do L.petNames[i] = p[1] end
    end
    return L.petNames
end
L.pet.remove = L.pet.free

-- the pictures, loaded the first time they are needed
function L.pet.sheet(def, anim)
    local Q = L.pet
    if Q.texFor ~= def[2] then Q.free(); Q.texFor = def[2] end
    local id = Q.tex[anim]
    if id ~= nil then return id or nil end
    if not Q.dir then
        local ok, gd = pcall(engine.GetGameDir)
        Q.dir = ((ok and gd) and tostring(gd) or ""):gsub("[\\/]tf[\\/]?$", "") .. "\\destiny_files\\pets\\"
    end
    local okT, tid = pcall(draw.CreateTexture, Q.dir .. def[2] .. "\\" .. anim .. ".png")
    L.recolor()
    Q.tex[anim] = (okT and tid) or false
    if not (okT and tid) then Q.err = "missing picture destiny_files/pets/" .. def[2] .. "/" .. anim .. ".png" end
    return Q.tex[anim] or nil
end

function L.pet.update()
    local Q = L.pet
    local lp = settings.petOn and entities.GetLocalPlayer() or nil
    local alive = false
    if lp then
        local ok, a = pcall(lp.IsAlive, lp)
        alive = ok and a
    end
    if not alive then
        if lp and Q.placed then Q.active, Q.dead = true, true; Q.anim = "idle"; return end
        Q.placed, Q.active, Q.dead = false, false, false
        return
    end
    if Q.dead then Q.dead, Q.placed = false, false end
    Q.active = true
    local def = L.PETS[settings.petSel] or L.PETS[1]
    if not Q.v then Q.v, Q.t0v, Q.t1v = Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0) end

    -- where it wants to be: beside me, a little ahead or behind
    local o = lp:GetAbsOrigin()
    local okY, ang = pcall(engine.GetViewAngles)
    local vyaw = (okY and ang and ang.y or 0) * pi / 180
    -- her place is worked out from where I look, or only from where I walk
    if not settings.petCam then
        local okV, vel = pcall(lp.EstimateAbsVelocity, lp)
        if okV and vel and vel.x * vel.x + vel.y * vel.y > 900 then Q.walkYaw = math.atan(vel.y, vel.x)
        elseif not Q.walkYaw then Q.walkYaw = vyaw end
        vyaw = Q.walkYaw
    end
    local side = (settings.petSide == 2) and -1 or 1
    local d = settings.petDist
    local fb = settings.petFront and 0.9 or -0.8
    local tx = o.x + cos(vyaw) * d * fb + cos(vyaw + pi / 2) * d * 0.7 * side
    local ty = o.y + sin(vyaw) * d * fb + sin(vyaw + pi / 2) * d * 0.7 * side
    -- roaming: a new spot near me every few seconds, a new one right away when I walk off
    if settings.petSide == 3 then
        local r = d * 1.6
        local rx, ry = (Q.roamX or o.x) - o.x, (Q.roamY or o.y) - o.y
        local far = rx * rx + ry * ry > (r * 1.5) ^ 2
        -- a new distance on the slider counts right away
        if Q.roamD ~= d then Q.roamD, Q.roamX = d, nil end
        if not Q.roamX or far or (not Q.moving and now() > (Q.roamAt or 0)) then
            local a, rr = math.random() * 2 * pi, r * (0.35 + 0.65 * math.random())
            Q.roamX, Q.roamY = o.x + cos(a) * rr, o.y + sin(a) * rr
            Q.roamAt = now() + 2 + math.random() * 4
        end
        tx, ty = Q.roamX, Q.roamY
    else
        Q.roamX = nil
    end
    if not Q.placed then Q.x, Q.y, Q.z, Q.gz, Q.placed = tx, ty, o.z, o.z, true end
    local dt = frameDt()
    local dx, dy = tx - Q.x, ty - Q.y
    local dist = sqrt(dx * dx + dy * dy)
    local speed = 0
    if dist > 900 then
        Q.x, Q.y, Q.z, Q.gz = tx, ty, o.z, o.z
    elseif dist > (Q.moving and 5 or 28) then
        Q.moving = true
        speed = clamp(dist * 3.2, 90, 470)
        local step = min(dist, speed * dt)
        Q.x, Q.y = Q.x + dx / dist * step, Q.y + dy / dist * step
        Q.tyaw = math.atan(dy, dx)
    else
        Q.moving = false
    end

    -- the ground under it and whether I can see it, 10 times a second
    local t = now()
    if t - Q.traceAt > 0.1 then
        Q.traceAt = t
        Q.t0v.x, Q.t0v.y, Q.t0v.z = Q.x, Q.y, o.z + 50
        Q.t1v.x, Q.t1v.y, Q.t1v.z = Q.x, Q.y, o.z - 260
        local ok, tr = pcall(engine.TraceLine, Q.t0v, Q.t1v, 0x4000B)
        if ok and tr and tr.fraction and tr.fraction < 1 and tr.endpos then Q.gz = tr.endpos.z else Q.gz = o.z end
        local okE, eye = pcall(lp.GetPropVector, lp, "localdata", "m_vecViewOffset[0]")
        Q.t0v.x, Q.t0v.y, Q.t0v.z = o.x, o.y, o.z + ((okE and eye) and eye.z or 64)
        Q.t1v.x, Q.t1v.y, Q.t1v.z = Q.x, Q.y, Q.z + def.height * settings.petSize / 100 * 0.6
        local okV, tv = pcall(engine.TraceLine, Q.t0v, Q.t1v, 0x4000B)
        Q.hidden = okV and tv and tv.fraction and tv.fraction < 0.97
    end
    Q.z = Q.z + (Q.gz - Q.z) * min(1, dt * 14)
    local diff = (Q.tyaw - Q.yaw + pi) % (2 * pi) - pi
    Q.yaw = Q.yaw + diff * min(1, dt * 10)
    Q.seen = Q.seen + ((Q.hidden and 0 or 1) - Q.seen) * min(1, dt * 12)

    -- which animation: jump while I am in the air, run, walk, crouch with me, idle
    local okF, flags = pcall(lp.GetPropInt, lp, "m_fFlags")
    flags = okF and flags or 1
    local anim = "idle"
    if flags & 1 == 0 then anim = "jump"
    elseif speed > 240 then anim = "run"
    elseif speed > 5 then anim = "walk"
    elseif flags & 2 ~= 0 then anim = "crouch" end
    if anim ~= Q.anim then Q.anim, Q.t0 = anim, t end
end

function L.pet.draw()
    local Q = L.pet
    if not Q.active or not Q.placed or Q.seen < 0.02 then return end
    local def = L.PETS[settings.petSel] or L.PETS[1]
    local id = Q.sheet(def, Q.anim)
    if not id then return end
    local v = Q.v
    local h = def.height * settings.petSize / 100
    -- a jump lifts her off the ground in an arc (the picture itself only shows the motion)
    local hop = 0
    if Q.anim == "jump" then hop = sin(pi * clamp((now() - Q.t0) / (def.len.jump or 0.8), 0, 1)) * h * 0.75 end
    v.x, v.y, v.z = Q.x, Q.y, Q.z
    local gx, gy = L.w2s(v)
    v.z = Q.z + hop
    local sx, sy = L.w2s(v)
    v.z = Q.z + hop + h
    local _, sy2 = L.w2s(v)
    if not sx or not sy2 or sy2 >= sy then return end
    local px = sy - sy2
    -- the frame: the animation runs at its own speed, a jump plays once
    local len = def.len[Q.anim] or 1
    local u = (now() - Q.t0) / len
    local frame = (Q.anim == "jump") and min(7, floor(u * 8)) or (floor(u * 8) % 8)
    -- which of the 8 sides I see it from
    local eye = Q.t0v
    local rel = math.atan(eye.y - Q.y, eye.x - Q.x) - Q.yaw
    local side = floor(rel / (pi / 4) + 0.5) % 8
    -- the cell drawn so the feet stand on the ground
    local cellPx = px / (def.tall or L.PET_TALL)
    local x0, y0 = sx - cellPx / 2, sy - cellPx * L.PET_FEET
    local u0, v0 = frame / 8, side / 8
    local q = Q.q
    q[1][1], q[1][2], q[1][3], q[1][4] = round(x0), round(y0), u0, v0
    q[2][1], q[2][2], q[2][3], q[2][4] = round(x0 + cellPx), round(y0), u0 + 1 / 8, v0
    q[3][1], q[3][2], q[3][3], q[3][4] = round(x0 + cellPx), round(y0 + cellPx), u0 + 1 / 8, v0 + 1 / 8
    q[4][1], q[4][2], q[4][3], q[4][4] = round(x0), round(y0 + cellPx), u0, v0 + 1 / 8
    -- a soft shadow under the feet
    L.screenSpace()
    if gx then
        local shrink = 1 - 0.45 * hop / max(1, h * 0.75)
        oval(gx, gy, cellPx * 0.17 * shrink, cellPx * 0.045 * shrink, C_BLACK, 90 * Q.seen * shrink)
    end
    rawColor(255, 255, 255, clamp(round(255 * Q.seen), 1, 255))
    draw.TexturedPolygon(id, q, true)
    L.pet.fxDraw(sx, sy2, cellPx)
end

---------------------------------------------------------------------------
-- 8r. Extras: hitmarker, bullet tracers, kill card, class meters, respawn timer, match card, movement trail,
-- screen weather, viewmodel, pet reactions, clean mode, config codes, own sounds
---------------------------------------------------------------------------

-- a number from the first property path that answers; kind "i" for whole numbers
function L.pget(e, kind, ...)
    if not e then return nil end
    local fn = (kind == "i") and e.GetPropInt or e.GetPropFloat
    for i = 1, select("#", ...) do
        local ok, v = pcall(fn, e, table.unpack((select(i, ...))))
        if ok and type(v) == "number" then return v end
    end
end

-- one colour choice shared by tracers and the trail
L.TR_COLS = { "Hit effect colours", "Accent", "Rainbow", "White" }
function L.pickCol(mode, p)
    if mode == 2 then return accent() end
    if mode == 3 then return sampleStops(logoStops(6), p + now() * 0.2) end
    if mode == 4 then return C_WHITE end
    return L.fxColor(false, p)
end

-- hitmarker --------------------------------------------------------------------------------------------
L.HM_STYLES = { "Cross", "Brackets", "Dots", "Ring", "Diamond" }
L.HM_COLS = { "Hit and kill colours", "White", "Accent" }
L.hm = { t0 = -99, kill = false, head = false }

function L.hmHit(head, kill)
    if not settings.hmOn then return end
    local H, t = L.hm, now()
    -- the kill comes right after the hit that did it: that marker turns into the kill one
    if kill and t - H.t0 < 0.15 then H.kill, H.t0 = true, t; return end
    H.t0, H.kill, H.head = t, kill, head
end

function L.hmShape(st, cx, cy, s, gap, th, c, a)
    if st == 1 then
        for i = 0, 3 do L.chArm(cx, cy, pi / 4 + i * pi / 2, gap, s, th, c, a, false) end
    elseif st == 2 then
        local len = max(3, s * 0.5)
        for i = 0, 3 do
            local sx, sy = (i % 2 == 0) and -1 or 1, (i < 2) and -1 or 1
            local x0, y0 = cx + sx * s, cy + sy * s
            rect(sx < 0 and x0 or x0 - len, sy < 0 and y0 or y0 - th, len, th, c, a)
            rect(sx < 0 and x0 or x0 - th, sy < 0 and y0 or y0 - len, th, len, c, a)
        end
    elseif st == 3 then
        for i = 0, 3 do
            local an = pi / 4 + i * pi / 2
            disc(cx + cos(an) * s * 0.8, cy + sin(an) * s * 0.8, max(1.5, th * 1.3), c, a)
        end
    elseif st == 4 then
        L.thickRing(cx, cy, s * 0.85, max(2, th + 1), c, a)
    else
        tline(cx, cy - s, cx + s, cy, th, c, a)
        tline(cx + s, cy, cx, cy + s, th, c, a)
        tline(cx, cy + s, cx - s, cy, th, c, a)
        tline(cx - s, cy, cx, cy - s, th, c, a)
    end
end

function L.drawHitmarker()
    local H = L.hm
    local el = now() - H.t0
    local life = settings.hmTime / 1000 * (H.kill and 1.5 or 1)
    if el < 0 or el > life then return end
    local sw, sh = draw.GetScreenSize()
    local cx, cy = floor(sw / 2), floor(sh / 2)
    local u = el / life
    local a = 255 * (1 - u * u)
    local head = H.head and settings.hmHead
    local s = settings.hmSize * (H.kill and 1.4 or 1) * (head and 1.3 or 1) * (1 + 0.3 * (1 - easeOut(el / 0.12)))
    local th = settings.hmThick
    local c
    if head then c = GOLD
    elseif settings.hmCol == 2 then c = C_WHITE
    elseif settings.hmCol == 3 then c = accent()
    else c = H.kill and (L.hex(settings.colKill) or L.GREEN) or (L.hex(settings.colHit) or C_WHITE) end
    L.screenSpace()
    L.hmShape(settings.hmStyle, cx + 1, cy + 1, s, s * 0.4, th, C_BLACK, a * 0.6)
    L.hmShape(settings.hmStyle, cx, cy, s, s * 0.4, th, c, a)
    if H.kill then L.thickRing(cx, cy, s * 1.25 + 14 * easeOut(u), 2, c, a * 0.55) end
end

-- bullet tracers: a shot is noticed when the weapon's next-shot time jumps ahead -------------------------
L.TR_STYLES = { "Beam", "Thin line", "Laser" }
L.TR_STEPS = { 0, 0.02, 0.05, 0.1, 0.2, 0.35, 0.5, 0.7, 0.85 }
L.tr = { list = {}, at = 0 }
for i = 1, 64 do L.tr.list[i] = { t0 = -99, x1 = 0, y1 = 0, z1 = 0, x2 = 0, y2 = 0, z2 = 0, hit = false } end

function L.trShot(lp)
    local okA, ang = pcall(engine.GetViewAngles)
    if not okA or not ang then return end
    local o = lp:GetAbsOrigin()
    local okE, off = pcall(lp.GetPropVector, lp, "localdata", "m_vecViewOffset[0]")
    local ez = o.z + ((okE and off) and off.z or 64)
    local p, y = ang.x * pi / 180, ang.y * pi / 180
    local fx, fy, fz = cos(p) * cos(y), cos(p) * sin(y), -sin(p)
    local rx, ry = sin(y), -cos(y)
    local src = Vector3(o.x, o.y, ez)
    local dst = Vector3(o.x + fx * 8192, o.y + fy * 8192, ez + fz * 8192)
    local okT, tr = pcall(engine.TraceLine, src, dst, 0x4600400B)
    local e = (okT and tr and tr.endpos) or dst
    local T = L.tr
    T.at = T.at % 64 + 1
    local s = T.list[T.at]
    -- from about where the gun is: a bit ahead, to the right and lower than the eyes
    s.x1, s.y1, s.z1 = o.x + fx * 30 + rx * 7, o.y + fy * 30 + ry * 7, ez + fz * 30 - 7
    s.x2, s.y2, s.z2 = e.x, e.y, e.z
    s.hit = okT and tr and tr.fraction and tr.fraction < 1 or false
    s.t0 = now()
end

function L.trPoll()
    local T = L.tr
    local lp = entities.GetLocalPlayer()
    if not lp or not L.hp.alive then T.wep = nil; return end
    local okW, w = pcall(lp.GetPropEntity, lp, "m_hActiveWeapon")
    if not okW or not w then return end
    local okV, valid = pcall(w.IsValid, w)
    if not okV or not valid then return end
    local nxt = L.pget(w, "f", { "LocalActiveWeaponData", "m_flNextPrimaryAttack" }, { "m_flNextPrimaryAttack" })
    if not nxt then return end
    local idx = w:GetIndex()
    if T.wep ~= idx then T.wep, T.next = idx, nxt; return end
    if nxt > T.next + 0.001 then
        T.next = nxt
        local okP, pt = pcall(w.GetWeaponProjectileType, w)
        if okP and pt == 1 then L.trShot(lp) end
    elseif nxt < T.next then
        T.next = nxt
    end
end

function L.drawTracers()
    local T = L.tr
    local t = now()
    local life = settings.trTime / 1000
    local v = T.v
    if not v then v = Vector3(0, 0, 0); T.v = v end
    L.screenSpace()
    for i = 1, 64 do
        local s = T.list[i]
        local el = t - s.t0
        if el >= 0 and el < life then
            -- once I turn away the start of an older line is behind me: use the first part of it I can still see
            local ax, ay
            for _, k in ipairs(L.TR_STEPS) do
                v.x, v.y, v.z = s.x1 + (s.x2 - s.x1) * k, s.y1 + (s.y2 - s.y1) * k, s.z1 + (s.z2 - s.z1) * k
                ax, ay = L.w2s(v)
                if ax then break end
            end
            v.x, v.y, v.z = s.x2, s.y2, s.z2
            local bx, by = L.w2s(v)
            if ax and bx then
                local f = 1 - el / life
                local c = L.pickCol(settings.trCol, i / 64)
                if settings.trStyle == 1 then
                    tline(ax, ay, bx, by, 6, c, 55 * f)
                    tline(ax, ay, bx, by, 3, c, 130 * f)
                    line(ax, ay, bx, by, C_WHITE, 230 * f)
                elseif settings.trStyle == 2 then
                    line(ax, ay, bx, by, c, 235 * f)
                else
                    local pulse = 0.6 + 0.4 * sin(t * 30 + i)
                    tline(ax, ay, bx, by, 4, c, 120 * f * pulse)
                    line(ax, ay, bx, by, c, 255 * f)
                end
                if s.hit then
                    disc(bx, by, 5, c, 150 * f)
                    disc(bx, by, 2, C_WHITE, 255 * f)
                end
            end
        end
    end
end

-- kill card ----------------------------------------------------------------------------------------------
L.kc = { t0 = -99 }
function L.killCard(name, class, weapon, custom, ent)
    if not settings.kcOn then return end
    local dist = "—"
    local lp = entities.GetLocalPlayer()
    if lp and ent then
        local ok1, a = pcall(lp.GetAbsOrigin, lp)
        local ok2, b = pcall(ent.GetAbsOrigin, ent)
        if ok1 and ok2 and a and b then
            local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
            dist = string.format("%.1f m", sqrt(dx * dx + dy * dy + dz * dz) * 0.01905)
        end
    end
    L.kc = { t0 = now(), name = name or "someone",
             head = (custom == 1) and "HEADSHOT" or ((custom == 2) and "BACKSTAB" or "ELIMINATED"),
             facts = { { "CLASS", class or "—" }, { "WEAPON", weapon or "—" }, { "DISTANCE", dist } } }
end
function L.kcPreview()
    local old = settings.kcOn
    settings.kcOn = true
    L.killCard("Delicious Cake", "Soldier", "Rocket Launcher", 1, nil)
    L.kc.facts[3][2] = "14.2 m"
    settings.kcOn = old
end

function L.drawKillCard()
    local K = L.kc
    if not K.facts then return end
    local el = now() - K.t0
    local life = settings.kcTime
    if el < 0 or el > life then return end
    local sw, sh = draw.GetScreenSize()
    local st = settings.phStyle
    local W, H = 320, 80
    local x, y = draggable("kc", sw / 2 - W / 2, sh * 0.64, W, H)
    local aIn = easeOut(el / 0.25)
    y = round(y + (1 - aIn) * 16)
    local p = L.palFor(st, settings.phGrad)
    ALPHA = aIn * clamp((life - el) / 0.4, 0, 1)
    L.panelBg(st, x, y, W, H, nil, settings.phBorder, settings.phGrad)
    local lx = x + p.pad + 12
    if st ~= 6 then rect(x + p.pad + 1, y + 12, 3, H - 24, p.c) end
    L.pt(F.tiny, K.head, lx, y + 8, 16, p.c)
    L.pt(F.bold, fit(F.bold, K.name, W - (lx - x) - 12), lx, y + 22, 24, p.txt)
    local colW = (W - (lx - x) - 10) / 3
    for i = 1, 3 do
        local f = K.facts[i]
        local fx = lx + (i - 1) * colW
        L.pt(F.tiny, f[1], fx, y + 50, 12, p.dim)
        L.pt(F.small, fit(F.small, f[2], colW - 8), fx, y + 61, 16, p.txt)
    end
    ALPHA = 1
end

-- class meters ---------------------------------------------------------------------------------------------
L.CM = { rows = {}, at = 0 }
function L.meterRows()
    local C = L.CM
    local t = now()
    if t - C.at < 0.1 then return C.rows end
    C.at = t
    local rows, n = C.rows, 0
    local function add(label, frac, txt, hot)
        n = n + 1
        local r = rows[n] or {}
        rows[n] = r
        r[1], r[2], r[3], r[4] = label, clamp(frac, 0, 1), txt, hot
    end
    local lp = entities.GetLocalPlayer()
    if lp and L.hp.alive then
        local cls = L.pget(lp, "i", { "m_PlayerClass", "m_iClass" }) or 0
        local function slot(sl)
            local ok, w = pcall(lp.GetEntityForLoadoutSlot, lp, sl)
            if ok and w then return w end
        end
        local function shared(name) return L.pget(lp, "f", { "m_Shared", name }, { name }) end
        if cls == 5 then
            local u = L.pget(slot(1), "f", { "LocalTFWeaponMedigunData", "m_flChargeLevel" }, { "m_flChargeLevel" })
            if u then add("ÜBER", u, floor(u * 100 + 0.5) .. "%", u >= 0.999) end
        elseif cls == 8 then
            local c = shared("m_flCloakMeter")
            if c then add("CLOAK", c / 100, floor(c + 0.5) .. "%", false) end
        elseif cls == 4 then
            local n2 = L.pget(slot(1), "i", { "PipebombLauncherLocalData", "m_iPipebombCount" }, { "m_iPipebombCount" })
            if n2 then add("STICKIES", n2 / 8, n2 .. " / 8", n2 >= 8) end
            local c = shared("m_flChargeMeter")
            if c then add("CHARGE", c / 100, floor(c + 0.5) .. "%", c >= 100) end
        elseif cls == 2 then
            local d = L.pget(slot(0), "f", { "SniperRifleLocalData", "m_flChargedDamage" }, { "m_flChargedDamage" })
            if d then add("CHARGE", d / 150, floor(d + 0.5) .. " dmg", d >= 149) end
        elseif cls == 9 then
            local ok, tbl = pcall(lp.GetPropDataTableInt, lp, "localdata", "m_iAmmo")
            local m = ok and type(tbl) == "table" and tbl[4]
            if m then add("METAL", m / 200, m .. " / 200", m >= 200) end
        elseif cls == 3 or cls == 7 then
            local r = shared("m_flRageMeter")
            if r and r > 0 then add(cls == 3 and "BANNER" or "MMMPH", r / 100, floor(r + 0.5) .. "%", r >= 100) end
        elseif cls == 1 then
            local hy = shared("m_flHypeMeter")
            if hy and hy > 0 then add("HYPE", hy / 100, floor(hy + 0.5) .. "%", hy >= 100) end
        end
    end
    for i = n + 1, #rows do rows[i] = nil end
    return rows
end

function L.drawMeters()
    local rows = L.meterRows()
    if #rows == 0 and not menu.open then return end
    local sw, sh = draw.GetScreenSize()
    local st = settings.phStyle
    local p = L.palFor(st, settings.phGrad)
    local W, head = 220, L.PH[st] or 32
    local H = head + max(1, #rows) * 30 + 8
    local x, y = draggable("cm", sw / 2 + 160, sh - H - 46, W, H)
    L.panelBg(st, x, y, W, H, st == 6 and "METERS" or "Meters", settings.phBorder, settings.phGrad)
    if #rows == 0 then
        L.pt(p.f, "no meter for this class", x + p.pad, y + head + 4, 26, p.dim)
        return
    end
    local t = now()
    for i, r in ipairs(rows) do
        local ry = y + head + 4 + (i - 1) * 30
        L.pt(F.tiny, r[1], x + p.pad, ry, 16, p.dim)
        L.pt(p.f, r[3], x + W - p.pad - textW(p.f, r[3]), ry - 2, 18, r[4] and GOLD or p.txt)
        local bw = W - 2 * p.pad
        local shown = anim("cm" .. r[1], r[2], 12)
        rect(x + p.pad, ry + 19, bw, 5, p.track, 220)
        local c = r[4] and mix(GOLD, C_WHITE, 0.3 + 0.3 * sin(t * 8)) or p.c
        rect(x + p.pad, ry + 19, bw * shown, 5, c, 255)
    end
end

-- respawn timer ---------------------------------------------------------------------------------------------
function L.respawnLeft(lp)
    local res = entities.GetPlayerResources()
    if not res then return nil end
    local ok, tbl = pcall(res.GetPropDataTableFloat, res, "m_flNextRespawnTime")
    if not ok or type(tbl) ~= "table" then return nil end
    local v = tbl[lp:GetIndex() + 1]
    if type(v) ~= "number" or v <= 0 then return nil end
    local left = v - globals.CurTime()
    if left < -1 or left > 90 then return nil end
    return max(0, left)
end

function L.drawRespawn()
    local lp = entities.GetLocalPlayer()
    if not lp or L.hp.alive then L.rsp = nil; return end
    local okT, team = pcall(lp.GetTeamNumber, lp)
    if not okT or (team or 0) < 2 then return end
    local R = L.rsp
    if not R then R = { t0 = now() }; L.rsp = R end
    local left = L.respawnLeft(lp)
    if left and (not R.total or left > R.total) then R.total = left end
    local sw, sh = draw.GetScreenSize()
    local st = settings.phStyle
    local p = L.palFor(st, settings.phGrad)
    local W, H = 300, 96
    local x, y = draggable("rt", sw / 2 - W / 2, sh * 0.26, W, H)
    ALPHA = easeOut((now() - R.t0) / 0.3)
    L.panelBg(st, x, y, W, H, nil, settings.phBorder, settings.phGrad)
    local cxm = x + W / 2
    local big = left and string.format("%.1f", left) or tostring(floor(now() - R.t0)) .. "s"
    textC(F.tiny, left and "RESPAWN IN" or "DEAD FOR", cxm, y + 8, 14, p.dim)
    textC(F.big, big, cxm, y + 22, 32, (left and left < 1) and L.GREEN or p.txt)
    local frac = (left and R.total and R.total > 0) and (1 - left / R.total) or 0
    rect(x + 20, y + 58, W - 40, 4, p.track, 220)
    rect(x + 20, y + 58, (W - 40) * frac, 4, p.c, 255)
    local D = L.deadInfo
    if D and now() - D.t0 < 90 then textC(F.small, fit(F.small, D.line, W - 30), cxm, y + 68, 22, p.dim) end
    ALPHA = 1
end

-- match card ---------------------------------------------------------------------------------------------------
L.mc = { at = 0 }
L.TEAM_RED, L.TEAM_BLU = { 222, 76, 76 }, { 80, 146, 236 }
function L.matchPoll()
    local M = L.mc
    if now() - M.at < 0.25 then return end
    M.at = now()
    M.left, M.red, M.blu = nil, nil, nil
    local ct = globals.CurTime()
    local ok, timers = pcall(entities.FindByClass, "CTeamRoundTimer")
    if ok and type(timers) == "table" then
        for _, tm in pairs(timers) do
            local okS, show = pcall(tm.GetPropBool, tm, "m_bShowInHUD")
            if not okS or show then
                local okP, paused = pcall(tm.GetPropBool, tm, "m_bTimerPaused")
                local left
                if okP and paused then
                    local okR, r = pcall(tm.GetPropFloat, tm, "m_flTimeRemaining")
                    if okR then left = r end
                else
                    local okE, e = pcall(tm.GetPropFloat, tm, "m_flTimerEndTime")
                    if okE and e then left = e - ct end
                end
                if type(left) == "number" then
                    M.left, M.paused = max(0, left), okP and paused
                    break
                end
            end
        end
    end
    local okT, teams = pcall(entities.FindByClass, "CTFTeam")
    if okT and type(teams) == "table" then
        for _, tm in pairs(teams) do
            local okN, num = pcall(tm.GetTeamNumber, tm)
            local okS, sc = pcall(tm.GetPropInt, tm, "m_iScore")
            if okN and okS and type(sc) == "number" then
                if num == 2 then M.red = sc elseif num == 3 then M.blu = sc end
            end
        end
    end
    M.time = M.left and string.format("%d:%02d", floor(M.left / 60), floor(M.left % 60)) or "--:--"
    M.redS, M.bluS = M.red and tostring(M.red) or "-", M.blu and tostring(M.blu) or "-"
end

function L.drawMatch()
    L.matchPoll()
    local M = L.mc
    if not M.left and not M.red and not menu.open then return end
    local sw = draw.GetScreenSize()
    local st = settings.phStyle
    local p = L.palFor(st, settings.phGrad)
    local W, H = 220, 48
    local x, y = draggable("mc", sw / 2 - W / 2, 52, W, H)
    L.panelBg(st, x, y, W, H, nil, settings.phBorder, settings.phGrad)
    roundRect(x + 8, y + 8, 46, H - 16, 8, L.TEAM_RED, 215)
    textC(F.bold, M.redS or "-", x + 31, y + 8, H - 16, C_WHITE)
    roundRect(x + W - 54, y + 8, 46, H - 16, 8, L.TEAM_BLU, 215)
    textC(F.bold, M.bluS or "-", x + W - 31, y + 8, H - 16, C_WHITE)
    L.pt(F.bold, M.time or "--:--", x + W / 2 - textW(F.bold, M.time or "--:--") / 2, y + 4, 26, p.txt)
    local sub = M.paused and "PAUSED" or "ROUND"
    L.pt(F.tiny, sub, x + W / 2 - textW(F.tiny, sub) / 2, y + 28, 14, p.dim)
end

-- movement trail ---------------------------------------------------------------------------------------------
L.TRL_STYLES = { "Ribbon", "Sparkles", "Dots" }
L.trl = { pts = {}, head = 0, at = 0 }
for i = 1, 60 do L.trl.pts[i] = { x = 0, y = 0, z = 0, t = -99 } end

function L.trailPoll()
    local T = L.trl
    local lp = entities.GetLocalPlayer()
    if not lp or not L.hp.alive then return end
    local t = now()
    if t - T.at < 0.016 then return end
    local okF, flags = pcall(lp.GetPropInt, lp, "m_fFlags")
    local air = okF and type(flags) == "number" and (flags & 1) == 0
    if not settings.trlAlways and not air and L.hp.speed < settings.trlSpeed then return end
    local o = lp:GetAbsOrigin()
    -- standing still adds nothing
    local last = T.pts[T.head]
    if T.head > 0 and t - last.t < 0.3 and abs(o.x - last.x) + abs(o.y - last.y) + abs(o.z + 10 - last.z) < 2 then return end
    T.at = t
    T.head = T.head % 60 + 1
    local p = T.pts[T.head]
    p.x, p.y, p.z, p.t = o.x, o.y, o.z + 10, t
end

function L.drawTrail()
    local T = L.trl
    if T.head == 0 then return end
    local t = now()
    local life = settings.trlLen / 10
    local v = T.v
    if not v then v = Vector3(0, 0, 0); T.v = v end
    L.screenSpace()
    local px, py, pt
    for k = 0, 59 do
        local i = (T.head - k - 1) % 60 + 1
        local p = T.pts[i]
        local age = t - p.t
        if age > life or age < 0 then break end
        v.x, v.y, v.z = p.x, p.y, p.z
        local sx, sy = L.w2s(v)
        local f = 1 - age / life
        if sx then
            local c = L.pickCol(settings.trlCol, k / 60)
            if settings.trlStyle == 1 then
                if px and pt - p.t < 0.08 then
                    tline(px, py, sx, sy, 1 + settings.trlWidth * f, c, 140 * f)
                    line(px, py, sx, sy, C_WHITE, 170 * f)
                end
            elseif settings.trlStyle == 2 then
                local tw = 0.5 + 0.5 * sin(t * 14 + i)
                disc(sx + (L.rnd(i, 1) - 0.5) * 12, sy + (L.rnd(i, 2) - 0.5) * 12, 1 + settings.trlWidth * 0.35 * f, c, 230 * f * tw)
            else
                disc(sx, sy, 1 + settings.trlWidth * 0.5 * f, c, 200 * f)
            end
        end
        px, py, pt = sx, sy, p.t
    end
end

-- screen weather: the menu's particle effects over the game -----------------------------------------------
L.WX = { "Snow", "Rain", "Embers", "Fireflies", "Stars", "Radiance sparkles" }
L.WX_KIND = { 3, 4, 2, 5, 6, 7 }
L.wxField = { list = {} }
function L.drawWeather()
    if menu.openT > 0.5 then return end
    ALPHA = settings.wxAlpha / 100 * (1 - menu.openT * 2)
    L.field(L.wxField, L.WX_KIND[settings.wxKind] or 3, floor(settings.wxAmt * 1.6))
    ALPHA = 1
end

-- viewmodel: the game's own settings, put back when it is turned off ---------------------------------------
L.vm = { orig = nil, key = nil, at = 0 }
function L.cvar(name)
    local ok, i, f, s = pcall(client.GetConVar, name)
    if ok then return i, f, s end
end
function L.vmApply(off)
    local V = L.vm
    if off or not settings.vmOn then
        if V.orig then
            for k, val in pairs(V.orig) do pcall(client.SetConVar, k, val) end
            V.orig, V.key = nil, nil
        end
        return
    end
    if not V.orig then
        local _, fov = L.cvar("viewmodel_fov")
        local _, _, ofs = L.cvar("tf_viewmodels_offset_override")
        local _, sway = L.cvar("cl_wpn_sway_scale")
        local drawn = L.cvar("r_drawviewmodel")
        V.orig = { viewmodel_fov = fov or 70, tf_viewmodels_offset_override = ofs or "", cl_wpn_sway_scale = sway or 5,
                   r_drawviewmodel = drawn or 1 }
    end
    local key = settings.vmFov .. "|" .. settings.vmX .. "|" .. settings.vmY .. "|" .. settings.vmZ .. "|" ..
                tostring(settings.vmSway) .. tostring(settings.vmHide)
    local t = now()
    -- set again every 2 seconds in case the game or a config put them back
    if key == V.key and t - V.at < 2 then return end
    V.key, V.at = key, t
    pcall(client.SetConVar, "viewmodel_fov", settings.vmFov)
    pcall(client.SetConVar, "tf_viewmodels_offset_override", settings.vmX .. " " .. settings.vmY .. " " .. settings.vmZ)
    pcall(client.SetConVar, "cl_wpn_sway_scale", settings.vmSway and 0 or V.orig.cl_wpn_sway_scale)
    pcall(client.SetConVar, "r_drawviewmodel", settings.vmHide and 0 or 1)
end

-- pet reactions ----------------------------------------------------------------------------------------------------
L.PET_PINK, L.PET_CLOUD, L.PET_DROP = { 255, 96, 150 }, { 160, 166, 182 }, { 120, 170, 255 }
function L.pet.react(kind)
    local Q = L.pet
    if not settings.petOn or not settings.petReact then return end
    local fx = Q.fx
    if not fx then fx = {}; Q.fx = fx end
    if #fx >= 6 then table.remove(fx, 1) end
    fx[#fx + 1] = { kind = kind, t0 = now(), seed = math.random() * 100 }
end

function L.pet.fxDraw(hx, hy, size)
    local Q = L.pet
    local fx = Q.fx
    if not fx then return end
    local t = now()
    for i = #fx, 1, -1 do
        local f = fx[i]
        local el = t - f.t0
        local life = (f.kind == "rain") and 3 or 1.5
        if el > life then
            table.remove(fx, i)
        else
            local fade = clamp((life - el) / 0.4, 0, 1) * Q.seen
            if f.kind == "heart" then
                for k = 1, 4 do
                    local tt = el - k * 0.12
                    if tt > 0 then
                        local x = hx + (L.rnd(f.seed, k) - 0.5) * size * 0.5 + sin(tt * 5 + k) * 5
                        local y = hy - 10 - tt * 46
                        local a = 255 * fade * min(1, tt / 0.15)
                        textC(F.iconL, "♥", x + 1, y + 1, 24, C_BLACK, a * 0.5)
                        textC(F.iconL, "♥", x, y, 24, L.PET_PINK, a)
                    end
                end
            elseif f.kind == "spark" then
                local r = 10 + 30 * easeOut(el / 0.6)
                for k = 1, 6 do
                    local an = k * 1.047 + f.seed
                    textC(F.icon, "✦", hx + cos(an) * r, hy - 16 + sin(an) * r * 0.6, 16, GOLD, 255 * fade)
                end
            else
                local w = max(10, size * 0.16)
                local cy = hy - 6 - w
                disc(hx - w * 0.6, cy, w * 0.55, L.PET_CLOUD, 230 * fade)
                disc(hx + w * 0.6, cy, w * 0.5, L.PET_CLOUD, 230 * fade)
                disc(hx, cy - w * 0.35, w * 0.7, L.PET_CLOUD, 240 * fade)
                for k = 1, 5 do
                    local ph = (el * 1.6 + k / 5) % 1
                    local dx = hx + (k - 3) * w * 0.35
                    local dy = cy + w * 0.4 + ph * w * 1.6
                    line(dx, dy, dx - 1, dy + 5, L.PET_DROP, 220 * fade * (1 - ph))
                end
            end
        end
    end
end

-- clean mode keys: off, or one of the menu keys -----------------------------------------------------------------
L.CLEAN_KEYS = { { "Off" } }
for i, k in ipairs(L.MENU_KEYS) do L.CLEAN_KEYS[i + 1] = k end

-- the folder the configs are in, opened in Explorer
function L.configDir()
    local dir = DIR or ""
    if not dir:match("^%a:") then
        local ok, gd = pcall(engine.GetGameDir)
        local root = ((ok and gd) and tostring(gd) or ""):gsub("[\\/]tf[\\/]?$", "")
        dir = root .. "\\" .. dir
    end
    return (dir:gsub("/", "\\"):gsub("[\\]+$", ""))
end

function L.openConfigFolder()
    local dir = DIR or ""
    if not dir:match("^%a:") then
        local ok, gd = pcall(engine.GetGameDir)
        local root = ((ok and gd) and tostring(gd) or ""):gsub("[\\/]tf[\\/]?$", "")
        dir = root .. "\\" .. dir
    end
    dir = dir:gsub("/", "\\"):gsub("[\\]+$", "")
    -- lmaobox doesn't let scripts open Explorer, so the folder is shown on the page and in the console
    L.cfgShown = dir
    print("[destiny] configs are in: " .. dir)
    notify("▤", "Configs are in", "the path is on this page and in the console", accent())
end

-- own sounds: every .wav or .mp3 in tf/sound/destiny_custom joins the sound lists --------------------------------
L.HIT_BASE, L.KILL_BASE = L.HIT_SOUNDS, L.KILL_SOUNDS
function L.scanSounds()
    pcall(filesystem.CreateDirectory, "tf/sound/destiny_custom")
    local found = {}
    pcall(filesystem.EnumerateDirectory, "tf/sound/destiny_custom/*", function(fn)
        fn = tostring(fn)
        local low = fn:lower()
        if low:match("%.wav$") or low:match("%.mp3$") then found[#found + 1] = fn end
    end)
    table.sort(found, function(a, b) return a:lower() < b:lower() end)
    local function build(base, skipOff)
        local t = {}
        if skipOff then t[1] = { "Off" } end
        for i, s in ipairs(base) do
            if not (skipOff and i == 1) then t[#t + 1] = s end
        end
        for _, fn in ipairs(found) do t[#t + 1] = { "★ " .. (fn:gsub("%.%w+$", "")), "destiny_custom/" .. fn } end
        return t
    end
    L.HIT_SOUNDS, L.KILL_SOUNDS, L.STREAK_SOUNDS = build(L.HIT_BASE), build(L.KILL_BASE), build(L.KILL_BASE, true)
    L.ownSounds = #found
    settings.hitSound = clamp(settings.hitSound, 1, #L.HIT_SOUNDS)
    settings.killSound = clamp(settings.killSound, 1, #L.KILL_SOUNDS)
    settings.ksSound = clamp(settings.ksSound, 1, #L.STREAK_SOUNDS)
end
L.scanSounds()

-- pet library: the pets kept on GitHub as text copies of their pictures (lmaobox can only download text)
L.PET_REPO = "https://raw.githubusercontent.com/eintoaster/pets/main/"
L.pdl = { names = nil, shown = nil, state = "idle", file = 0, entry = nil }

function L.pdl.has(folder)
    local ok, f = pcall(io.open, "destiny_files/pets/" .. folder .. "/jump.png", "rb")
    if ok and f then f:close(); return true end
    return false
end

function L.pdl.mark()
    local D = L.pdl
    D.shown, D.own = {}, {}
    for i, e in ipairs(D.names) do
        D.own[e.folder] = D.has(e.folder)
        D.shown[i] = (D.own[e.folder] and "✓ " or "") .. e.name
    end
end

function L.pdl.load()
    local D = L.pdl
    local ok, body = pcall(http.Get, L.PET_REPO .. "index.txt")
    if not ok or type(body) ~= "string" or #body < 5 or body:sub(1, 3) == "404" then
        notify("✖", "Can't load the pet list", "GitHub didn't answer", RED)
        return
    end
    D.names = {}
    for line in body:gmatch("[^\r\n]+") do
        local folder, name, h, tall = line:match("^([%w_]+)|([^|]+)|([%d%.]+)|([%d%.]+)$")
        if folder then
            D.names[#D.names + 1] = { folder = folder, name = name, height = tonumber(h), tall = tonumber(tall) }
            -- a pet that isn't in destiny yet joins the pet list
            local known = false
            for _, p in ipairs(L.PETS) do if p[2] == folder then known = true end end
            if not known then
                L.PETS[#L.PETS + 1] = { name, folder, height = tonumber(h), tall = tonumber(tall),
                                        len = { idle = 2.4, walk = 0.9, run = 0.6, crouch = 2, jump = 0.8 } }
                L.petNames = nil
            end
        end
    end
    if #D.names == 0 then D.names = nil; notify("✖", "Can't load the pet list", "the list is empty", RED); return end
    D.mark()
    settings.pdlSel = clamp(settings.pdlSel, 1, #D.names)
end

function L.pdl.start()
    local D = L.pdl
    if D.state == "downloading" or not D.names then return end
    local e = D.names[settings.pdlSel]
    if not e then return end
    pcall(filesystem.CreateDirectory, "destiny_files")
    pcall(filesystem.CreateDirectory, "destiny_files/pets")
    pcall(filesystem.CreateDirectory, "destiny_files/pets/" .. e.folder)
    D.state, D.entry, D.file, D.job = "downloading", e, 0, nil
end

function L.pdl.fail(why)
    local D = L.pdl
    if D.job and D.job.fh then pcall(D.job.fh.close, D.job.fh) end
    D.state, D.job = "failed", nil
    notify("✖", "Pet download failed", why, RED)
end

-- every frame while downloading: one picture at a time, turned back into a file about 3 ms per frame
function L.pdl.work()
    local D = L.pdl
    local job = D.job
    if not job then
        D.file = D.file + 1
        local anim = L.PET_ANIMS[D.file]
        if not anim then
            D.state = "done"
            L.pet.free()
            D.mark()
            for i, p in ipairs(L.PETS) do if p[2] == D.entry.folder then settings.petSel = i end end
            notify("❖", "Pet downloaded", D.entry.name .. " is now your pet", accent())
            return
        end
        local ok, data = pcall(http.Get, L.PET_REPO .. "pets/" .. D.entry.folder .. "/" .. anim .. ".b64")
        if not ok or type(data) ~= "string" or #data < 1000 then return D.fail(anim .. ": no answer from GitHub") end
        if L.paimon.b64(data, 1, 8):sub(2, 4) ~= "PNG" then return D.fail(anim .. ": not a picture") end
        local okF, fh = pcall(io.open, "destiny_files/pets/" .. D.entry.folder .. "/" .. anim .. ".png", "wb")
        if not okF or not fh then return D.fail("can't write into destiny_files/pets") end
        D.job = { data = data, pos = 1, fh = fh }
        return
    end
    local t0, n = L.clock(), #job.data
    repeat
        local j = min(n, job.pos + 49151)
        job.fh:write(L.paimon.b64(job.data, job.pos, j))
        job.pos = j + 1
    until job.pos > n or (L.clock() - t0) > 0.003
    if job.pos > n then
        job.fh:close()
        D.job = nil
    end
end

---------------------------------------------------------------------------
-- 9. Menu background effects
---------------------------------------------------------------------------
L.EMBER_GLOW = { 255, 90, 20 }
L.RD_STOPS, L.RD_CORE = { { 124, 108, 255 }, { 158, 146, 255 }, { 99, 102, 241 } }, { 228, 224, 255 }
L.BG_FX = { "Off", "Embers", "Snow", "Rain", "Fireflies", "Stars", "Radiance sparkles", "Radiance ribbons", "Silentium", "Bats" }
local particles, particleKind = {}, nil

local function spawnParticle(kind, sw, sh, anywhere)
    local p = { x = math.random() * sw, y = anywhere and math.random() * sh or 0, s = math.random() * 2 + 1,
                ph = math.random() * 6.28, sp = math.random() * 0.6 + 0.7 }
    if kind == 2 or kind == 7 then p.y = anywhere and p.y or sh + 5 end
    return p
end

-- a field of particles (embers, snow, rain, fireflies, stars, sparkles) kept in st
L.bgField = { list = {} }
function L.field(st, kind, n)
    local sw, sh = draw.GetScreenSize()
    if st.kind ~= kind then st.list, st.kind = {}, kind end
    local particles = st.list
    while #particles < n do particles[#particles + 1] = spawnParticle(kind, sw, sh, true) end
    while #particles > n do table.remove(particles) end
    local dt, t = frameDt(), now()
    for i, p in ipairs(particles) do
        if kind == 2 then
            p.y = p.y - 40 * p.sp * dt
            p.x = p.x + sin(t * 1.3 + p.ph) * 12 * dt
            local fl = 0.6 + 0.4 * sin(t * 9 + p.ph)
            if p.s > 2 then disc(p.x, p.y, p.s + 1.5, L.EMBER_GLOW, 40 * fl) end
            disc(p.x, p.y, p.s * 0.7, { 255, 170, 60 }, 220 * fl)
            if p.y < -5 then particles[i] = spawnParticle(kind, sw, sh, false) end
        elseif kind == 3 then
            p.y = p.y + 30 * p.sp * dt
            p.x = p.x + sin(t * 0.8 + p.ph) * 18 * dt
            disc(p.x, p.y, p.s * 0.8, C_WHITE, 200)
            if p.y > sh + 5 then particles[i] = spawnParticle(kind, sw, sh, false) end
        elseif kind == 4 then
            p.y = p.y + 700 * p.sp * dt
            p.x = p.x - 120 * dt
            line(p.x, p.y, p.x + 3, p.y - 14, { 170, 200, 255 }, 120)
            if p.y > sh + 15 then particles[i] = spawnParticle(kind, sw, sh, false); particles[i].y = -15 end
        elseif kind == 5 then
            p.x = p.x + cos(t * 0.5 + p.ph) * 20 * dt
            p.y = p.y + sin(t * 0.7 + p.ph * 1.3) * 20 * dt
            local gl = 0.5 + 0.5 * sin(t * 2.5 + p.ph)
            disc(p.x, p.y, 6, { 200, 255, 120 }, 30 * gl)
            disc(p.x, p.y, 2, { 230, 255, 160 }, 230 * gl)
        elseif kind == 6 then
            local tw = 0.4 + 0.6 * abs(sin(t * 1.4 * p.sp + p.ph))
            disc(p.x, p.y, p.s * 0.6, C_WHITE, 230 * tw)
            if p.s > 2.6 then
                line(p.x - 4, p.y, p.x + 4, p.y, C_WHITE, 120 * tw)
                line(p.x, p.y - 4, p.x, p.y + 4, C_WHITE, 120 * tw)
            end
        else
            p.y = p.y - 25 * p.sp * dt
            local tw = 0.5 + 0.5 * sin(t * 3 * p.sp + p.ph)
            local c = sampleStops(L.RD_STOPS, (p.ph / 6.28) % 1)
            disc(p.x, p.y, p.s * 2 + 4, c, 80 * tw)
            disc(p.x, p.y, max(2, p.s), L.RD_CORE, 255 * tw)
            if p.s > 2 then
                local r = 5 + p.s * 2 * tw
                line(p.x - r, p.y, p.x + r, p.y, L.RD_CORE, 170 * tw)
                line(p.x, p.y - r, p.x, p.y + r, L.RD_CORE, 170 * tw)
            end
            if p.y < -5 then particles[i] = spawnParticle(kind, sw, sh, false) end
        end
    end
end

local function drawBackground(openT)
    local sw, sh = draw.GetScreenSize()
    ALPHA = openT
    if settings.bgDim > 0 then rect(0, 0, sw, sh, C_BLACK, 255 * settings.bgDim / 100) end

    local kind = settings.bgFx
    if kind == 8 then L.drawRibbons(false)
    elseif kind == 9 then L.drawRibbons(true); L.drawButterflies()
    elseif kind == 10 then L.drawBats()
    elseif kind > 1 then
        L.field(L.bgField, kind, floor(settings.bgFxAmt * 1.6))
    end
    ALPHA = 1
end

local function menuGlow(x, y, w, h, a)
    if not settings.menuGlow then return end
    local acc = accent()
    if a < 0.97 then return end
    local pulse = 0.8 + 0.2 * sin(now() * 2)
    for i = 1, 3 do
        local e = i * 4 - 2
        roundRectLine(x - e, y - e, w + 2 * e, h + 2 * e, 14 + e, acc, (74 - i * 20) * pulse)
    end
end

---------------------------------------------------------------------------
-- 10. World look
---------------------------------------------------------------------------
L.WORLD_PRESETS = {
    { "Night", { 0.35, 0.42, 0.65 } }, { "Sunset", { 1.0, 0.62, 0.45 } }, { "Halloween", { 0.95, 0.5, 0.22 } },
    { "Radiance", { 0.62, 0.52, 1.0 } }, { "Silentium", { 0.95, 0.45, 0.58 } }, { "Grey", { 0.6, 0.6, 0.6 } },
    { "Custom colour", nil },
}
local world = { key = nil, map = nil, mapSince = 0 }

local function hsv(h, s, v)
    h = (h % 360) / 60
    local i = floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
    return v, p, q
end

local function worldRGB()
    local p = L.WORLD_PRESETS[settings.worldPreset]
    local r, g, b
    if p and p[2] then r, g, b = p[2][1], p[2][2], p[2][3] else r, g, b = hsv(settings.worldHue, 0.55, 1) end
    local k = settings.worldBright / 100
    return clamp(r * k, 0, 1), clamp(g * k, 0, 1), clamp(b * k, 0, 1)
end

local function applyWorld(off)
    local r, g, b = 1, 1, 1
    if not off and settings.worldOn then r, g, b = worldRGB() end
    local sky, props = settings.worldSky and not off and settings.worldOn, settings.worldProps and not off and settings.worldOn
    pcall(materials.Enumerate, function(mat)
        local group = mat:GetTextureGroupName()
        if group == "World textures" then mat:ColorModulate(r, g, b)
        elseif group == "SkyBox textures" then
            if sky then mat:ColorModulate(r, g, b) else mat:ColorModulate(1, 1, 1) end
        elseif group == "StaticProp textures" then
            if props then mat:ColorModulate(r, g, b) else mat:ColorModulate(1, 1, 1) end
        end
    end)
end

-- own sky: one of TF2's skies, plus every full set of 6 pictures found in tf/materials/skybox
L.SKY_TF = { "sky_night_01" }
L.SKY_FACES = { rt = true, lf = true, bk = true, ft = true, up = true, dn = true }
L.SKY_DIR = "tf/materials/skybox/"
L.sky = { list = {}, names = {}, own = 0, scanned = false }

function L.sky.writeVmt(base)
    for face in pairs(L.SKY_FACES) do
        local okW, w = pcall(io.open, L.SKY_DIR .. base .. face .. ".vmt", "w")
        if okW and w then
            w:write('"UnlitGeneric"\n{\n\t"$basetexture" "skybox/' .. base .. face .. '"\n\t"$ignorez" "1"\n\t"$nofog" "1"\n}\n')
            w:close()
        end
    end
end

function L.sky.scan()
    local S = L.sky
    local count, order = {}, {}
    pcall(filesystem.EnumerateDirectory, L.SKY_DIR .. "*", function(fn)
        local base, face = tostring(fn):match("^(.+)(%a%a)%.[vV][tT][fF]$")
        if base and L.SKY_FACES[face:lower()] then
            if not count[base] then count[base] = 0; order[#order + 1] = base end
            count[base] = count[base] + 1
        end
    end)
    table.sort(order)
    local list, shown = {}, {}
    for i, n in ipairs(L.SKY_TF) do list[i], shown[i] = n, n end
    S.own = 0
    for _, base in ipairs(order) do
        if count[base] >= 6 then
            S.own = S.own + 1
            list[#list + 1] = base
            shown[#shown + 1] = "★ " .. (base:gsub("[_%-%s]+$", ""))
            -- a set without its small text files gets them written
            local ok, f = pcall(io.open, L.SKY_DIR .. base .. "dn.vmt", "r")
            if ok and f then f:close() else L.sky.writeVmt(base) end
        end
    end
    S.list, S.names, S.scanned = list, shown, true
    settings.skySel = 1
    for i, n in ipairs(list) do
        if n == settings.skyName then settings.skySel = i end
    end
end

function L.sky.restore()
    local S = L.sky
    if not S.active then return end
    S.active, S.told, S.pend = false, nil, nil
    if S.orig then pcall(client.SetConVar, "sv_skyname", S.orig) end
    S.last = nil
end

-- the game loads the sky named in sv_skyname when a map starts, and a new map puts its own name back:
-- ours is set again 4 times a second, and every frame while a map is loading
function L.sky.enforce()
    local S = L.sky
    local want = settings.skyOn and settings.skyName ~= "" and settings.skyName or nil
    if not want then return nil end
    local ok, _, _, cur = pcall(client.GetConVar, "sv_skyname")
    cur = (ok and type(cur) == "string") and cur or nil
    if cur ~= want then
        if cur and cur ~= "" and cur ~= S.last then S.orig = cur end
        pcall(client.SetConVar, "sv_skyname", want)
        S.last = want
    end
    S.active = true
    return want
end

-- the sky on screen can't be swapped while a map runs (repainting it left faces white), so a new pick is
-- only announced: it shows after a rejoin or on the next map
function L.sky.tick(map)
    local S = L.sky
    local want = S.enforce()
    if map ~= S.map then S.map, S.loaded, S.told, S.pend = map, want or "", nil, nil end
    if not want then S.restore(); return end
    if map == "" or want == S.loaded or want == S.told then return end
    if S.pend ~= want then S.pend, S.pendAt = want, now(); return end
    if now() - S.pendAt < 1 then return end
    S.told = want
    notify("☀", "Sky picked", "It shows after Rejoin (World page) or on the next map", accent())
end

-- sky library: the skies kept on GitHub as text copies (lmaobox can only download text), 6 pictures each,
-- plus a small preview strip per sky
L.SKY_REPO = "https://raw.githubusercontent.com/eintoaster/skyboxes/main/"
L.SKY_ORDER = { "rt", "lf", "bk", "ft", "up", "dn" }
L.lib = { names = nil, shown = nil, state = "idle", face = 0, name = "", tex = {}, texN = 0 }

function L.lib.has(name)
    local ok, f = pcall(io.open, L.SKY_DIR .. name .. "dn.vtf", "rb")
    if ok and f then f:close(); return true end
    return false
end

function L.lib.mark()
    local B = L.lib
    B.shown, B.own = {}, {}
    for i, n in ipairs(B.names) do
        B.own[n] = B.has(n)
        B.shown[i] = (B.own[n] and "✓ " or "") .. n
    end
end

function L.lib.load()
    local B = L.lib
    local ok, body = pcall(http.Get, L.SKY_REPO .. "index.txt")
    if not ok or type(body) ~= "string" or body:sub(1, 3) == "404" or #body < 3 then
        notify("✖", "Can't load the sky list", "GitHub didn't answer", RED)
        return
    end
    B.names = {}
    for line in body:gmatch("[^\r\n]+") do
        local n = line:match("^([%w_]+)$")
        if n then B.names[#B.names + 1] = n end
    end
    if #B.names == 0 then B.names = nil; notify("✖", "Can't load the sky list", "the list is empty", RED); return end
    B.mark()
    settings.libSel = clamp(settings.libSel, 1, #B.names)
end

function L.lib.start()
    local B = L.lib
    if B.state == "downloading" or not B.names then return end
    local name = B.names[settings.libSel]
    if not name then return end
    pcall(filesystem.CreateDirectory, "tf/materials")
    pcall(filesystem.CreateDirectory, "tf/materials/skybox")
    B.state, B.name, B.face, B.job, B.why = "downloading", name, 0, nil, nil
end

function L.lib.fail(why)
    local B = L.lib
    if B.job and B.job.fh then pcall(B.job.fh.close, B.job.fh) end
    B.state, B.job, B.why = "failed", nil, why
    notify("✖", "Sky download failed", why, RED)
end

-- every frame while downloading: fetch the next picture (the game stops for a moment), then turn the text
-- back into the file about 3 ms at a time
function L.lib.work()
    local B = L.lib
    local job = B.job
    if not job then
        B.face = B.face + 1
        local face = L.SKY_ORDER[B.face]
        if not face then
            L.sky.writeVmt(B.name)
            B.state = "done"
            settings.skyName = B.name
            L.sky.scan()
            B.mark()
            notify("☀", "Skybox downloaded", B.name .. (settings.skyOn and " is now your sky" or " is picked: turn on Use another sky"), accent())
            return
        end
        local ok, data = pcall(http.Get, L.SKY_REPO .. "sky/" .. B.name .. "/" .. face .. ".b64")
        if not ok or type(data) ~= "string" or #data < 1000 then return B.fail(face .. ": no answer from GitHub") end
        if L.paimon.b64(data, 1, 4) ~= "VTF" then return B.fail(face .. ": not a sky picture") end
        local okF, fh = pcall(io.open, L.SKY_DIR .. B.name .. face .. ".vtf", "wb")
        if not okF or not fh then return B.fail("can't write into tf/materials/skybox") end
        B.job = { data = data, pos = 1, fh = fh }
        return
    end
    local t0, n = L.clock(), #job.data
    repeat
        local j = min(n, job.pos + 49151)
        job.fh:write(L.paimon.b64(job.data, job.pos, j))
        job.pos = j + 1
    until job.pos > n or (L.clock() - t0) > 0.003
    if job.pos > n then
        job.fh:close()
        B.job = nil
    end
end

-- preview strip of a sky: kept as a small picture in destiny_files/skybox, fetched once
function L.lib.preview(name)
    local B = L.lib
    if name == "" then return nil end
    local id = B.tex[name]
    if id ~= nil then return id or nil end
    -- wait until the choice has stopped changing
    if B.pvName ~= name then B.pvName, B.pvAt = name, now(); return nil end
    if now() - B.pvAt < 0.35 then return nil end
    if not B.dir then
        local ok, gd = pcall(engine.GetGameDir)
        B.dir = ((ok and gd) and tostring(gd) or ""):gsub("[\\/]tf[\\/]?$", "") .. "\\destiny_files\\skybox\\"
        pcall(filesystem.CreateDirectory, "destiny_files")
        pcall(filesystem.CreateDirectory, "destiny_files/skybox")
    end
    local rel = "destiny_files/skybox/" .. name .. ".png"
    local okF, f = pcall(io.open, rel, "rb")
    if okF and f then f:close()
    else
        local ok, data = pcall(http.Get, L.SKY_REPO .. "preview/" .. name .. ".b64")
        local png = (ok and type(data) == "string" and #data > 200) and L.paimon.b64(data, 1, #data) or ""
        if png:sub(2, 4) ~= "PNG" then B.tex[name] = false; return nil end
        local okW, w = pcall(io.open, rel, "wb")
        if not okW or not w then B.tex[name] = false; return nil end
        w:write(png); w:close()
    end
    if B.texN >= 24 then B.clear() end
    local okT, tid = pcall(draw.CreateTexture, B.dir .. name .. ".png")
    L.recolor()
    B.tex[name] = (okT and tid) or false
    B.texN = B.texN + 1
    return B.tex[name] or nil
end

function L.lib.clear()
    for _, id in pairs(L.lib.tex) do if id then pcall(draw.DeleteTexture, id) end end
    L.lib.tex, L.lib.texN = {}, 0
end

L.worldCheckAt = 0
local function updateWorld()
    if now() - L.worldCheckAt < 0.25 then return end
    L.worldCheckAt = now()
    L.sky.tick(engine.GetMapName() or "")
    local map = engine.GetMapName() or ""
    if map ~= world.map then world.map, world.mapSince, world.key, world.again = map, now(), nil, false end
    if map == "" or now() - world.mapSince < 2 then return end
    -- once more a few seconds into the map
    if not world.again and now() - world.mapSince > 8 then
        world.again = true
        if settings.worldOn then applyWorld(false) end
    end
    local key = tostring(settings.worldOn) .. settings.worldPreset .. "|" .. settings.worldHue .. "|" ..
                settings.worldBright .. tostring(settings.worldSky) .. tostring(settings.worldProps)
    if key ~= world.key then
        if world.key == nil and not settings.worldOn then world.key = key; return end
        -- wait until the setting stops changing
        if key ~= world.pending then world.pending, world.pendingAt = key, now(); return end
        if now() - world.pendingAt < 0.3 then return end
        world.key = key
        applyWorld(false)
    end
end

---------------------------------------------------------------------------
-- 11. Menu
---------------------------------------------------------------------------
local SIDE_W = 230
local view = { top = 0, bot = 0 }
local cx, cy, cw
local sliderDrag = nil
L.savedAt = -99

-- a row is drawn when part of it is in view and it stays inside the window
local function rowVisible(h)
    -- a see-through menu can't hide rows under its header, so only whole rows are drawn there
    if L.glassA() < 255 then return cy >= view.top and cy + h <= view.bot end
    return cy + h > view.top and cy < view.bot and cy >= view.wtop + 1 and cy + h <= view.wbot - 1
end
local function rowClick(x, y, w, h)
    if dropdown or mouse.y < view.top or mouse.y >= view.bot then return false end
    return takeClick(x, y, w, h)
end

local function card(id, h)
    local hovered = id and not dropdown and inside(mouse.x, mouse.y, cx, cy, cw, h) and mouse.y >= view.top and mouse.y < view.bot
    local hv = id and anim("card" .. id, hovered and 1 or 0, 14) or 0
    if L.glassA() < 255 then
        roundRect(cx, cy, cw, h, 12, C_WHITE, 26 + 22 * hv)
        roundRectLine(cx, cy, cw, h, 12, C_WHITE, 70)
    else
        roundRect(cx, cy, cw, h, 12, mix(T.card, T.hover, hv))
        roundRectLine(cx, cy, cw, h, 12, T.border)
    end
end

local function section(title)
    if rowVisible(22) then text(F.bold, title, cx + 4, cy, 22, T.text) end
    cy = cy + 30
end

local function toggleRow(label, key)
    if rowVisible(48) then
        if rowClick(cx, cy, cw, 48) then settings[key] = not settings[key] end
        local t = anim("tg" .. key, settings[key] and 1 or 0, 10)
        card(key, 48)
        text(F.ui, fit(F.ui, label, cw - 90), cx + 16, cy, 48, T.text)
        local fx, fy = cx + cw - 60, cy + 12
        roundRect(fx, fy, 44, 24, 12, mix(T.off, accent(), t))
        disc(fx + 12 + 20 * t, fy + 12, 9, T.thumb)
    end
    cy = cy + 58
end

local function sliderRow(label, key, lo, hi, suffix)
    local tx, tw, ty = cx + 18, cw - 36, cy + 47
    if rowVisible(66) then
        if rowClick(tx - 10, cy + 36, tw + 20, 28) then sliderDrag = key end
        card(nil, 66)
        text(F.ui, label, cx + 16, cy + 8, 26, T.text)
        local nx, ny = cx + cw - 74, cy + 10
        roundRect(nx, ny, 58, 24, 8, T.pill)
        roundRectLine(nx, ny, 58, 24, 8, sliderDrag == key and accent() or T.border)
        textC(F.small, settings[key] .. (suffix or ""), nx + 29, ny, 24, T.text)
    end
    if sliderDrag == key then
        if mouse.held then
            settings[key] = round(lo + clamp((mouse.x - tx) / tw, 0, 1) * (hi - lo))
        else
            sliderDrag = nil
        end
    end
    if rowVisible(66) then
        local t = anim("sl" .. key, (settings[key] - lo) / (hi - lo), sliderDrag == key and 30 or 12)
        roundRect(tx, ty, tw, 4, 2, T.track)
        roundRect(tx, ty, max(3, tw * t), 4, 2, accent())
        disc(tx + tw * t, ty + 2, 7, T.thumb)
    end
    cy = cy + 76
end

local function dropRow(label, key, options)
    if rowVisible(48) then
        local pw = 200
        local bx, by = cx + cw - 16 - pw, cy + 10
        local isOpen = dropdown and dropdown.key == key
        if (not dropdown or isOpen) and mouse.y >= view.top and mouse.y < view.bot and takeClick(bx, by, pw, 28) then
            if isOpen then dropdown = nil
            else
                dropdown = { key = key, options = options, x = bx, y = by + 32, w = pw, by = by }
                animValues.ddopen = 0
            end
            isOpen = dropdown ~= nil
        end
        card(nil, 48)
        text(F.ui, fit(F.ui, label, cw - pw - 40), cx + 16, cy, 48, T.text)
        local hv = anim("dd" .. key, (not dropdown and inside(mouse.x, mouse.y, bx, by, pw, 28)) and 1 or 0, 14)
        roundRect(bx, by, pw, 28, 8, mix(T.pill, T.active, hv))
        roundRectLine(bx, by, pw, 28, 8, isOpen and accent() or T.border)
        text(F.small, fit(F.small, options[settings[key]] or "?", pw - 40), bx + 12, by, 28, T.text)
        text(F.icon, "▾", bx + pw - 22, by, 28, T.muted)
        if isOpen then dropdown.x, dropdown.by = bx, by end
    end
    cy = cy + 58
end

local function buttonRow(label, btn, fn)
    if rowVisible(48) then
        local bw = max(110, textW(F.small, btn) + 28)
        local bx, by = cx + cw - 16 - bw, cy + 10
        if rowClick(bx, by, bw, 28) then fn(); animValues["bt" .. label] = 1 end
        card(nil, 48)
        text(F.ui, fit(F.ui, label, cw - bw - 40), cx + 16, cy, 48, T.text)
        local hv = anim("bh" .. label, (not dropdown and inside(mouse.x, mouse.y, bx, by, bw, 28)) and 1 or 0, 14)
        local flash = anim("bt" .. label, 0, 5)
        roundRect(bx, by, bw, 28, 8, mix(mix(T.pill, T.active, hv), accent(), flash * 0.6))
        roundRectLine(bx, by, bw, 28, 8, T.border)
        textC(F.small, btn, bx + bw / 2, by, 28, T.text)
    end
    cy = cy + 58
end

-- a card with wrapped text
local wrapCache = {}
local function paraCard(s)
    local byW = wrapCache[cw]
    if not byW then byW = {}; wrapCache[cw] = byW end
    local lines = byW[s]
    if not lines then
        local cur = ""
        lines = {}
        for wd in s:gmatch("%S+") do
            local try = cur == "" and wd or (cur .. " " .. wd)
            if textW(F.small, try) > cw - 32 and cur ~= "" then lines[#lines + 1] = cur; cur = wd else cur = try end
        end
        if cur ~= "" then lines[#lines + 1] = cur end
        byW[s] = lines
    end
    local h = 20 + #lines * 20
    if rowVisible(h) then
        card(nil, h)
        for i, l in ipairs(lines) do text(F.small, l, cx + 16, cy + 10 + (i - 1) * 20, 20, T.text2) end
    end
    cy = cy + h + 10
end

-- colour picker popup -----------
local function rgbToHsv(c)
    local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
    local mx, mn = max(r, g, b), min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
        h = h * 60
    end
    return h, (mx > 0) and d / mx or 0, mx
end

L.HUE = { { 255, 0, 0 }, { 255, 255, 0 }, { 0, 255, 0 }, { 0, 255, 255 }, { 0, 0, 255 }, { 255, 0, 255 }, { 255, 0, 0 } }
L.SWATCHES = { "10B981", "7C6CFF", "E8456F", "FF7A18", "38BDF8", "FACC15", "FFFFFF", "FF2D55" }

local function fadeRect(x, y, w, h, c, a1, a2, horizontal)
    rawColor(round(c[1]), round(c[2]), round(c[3]), 255)
    draw.FilledRectFade(round(x), round(y), round(x + w), round(y + h),
        clamp(round(a1 * ALPHA), 0, 255), clamp(round(a2 * ALPHA), 0, 255), horizontal)
end

function L.drawPicker(d)
    local W, H = 240, 214
    local sw, sh = draw.GetScreenSize()
    local x = clamp(d.x, 8, sw - W - 8)
    local y = d.y
    if y + H > sh - 8 then y = d.by - 6 - H end
    local t = anim("ddopen", 1, 16)
    roundRect(x, y + 3, W, H * t, 12, C_BLACK, 80)
    roundRect(x, y, W, H * t, 12, T.card)
    roundRectLine(x, y, W, H * t, 12, T.border)
    if t < 0.9 then return end

    local sx, sy, sW, sH = x + 12, y + 12, W - 24, 120
    local hx, hy, hW, hH = x + 12, y + 140, W - 24, 12
    local r, g, b = hsv(d.h, 1, 1)
    rect(sx, sy, sW, sH, { r * 255, g * 255, b * 255 })
    fadeRect(sx, sy, sW, sH, C_WHITE, 255, 0, true)
    fadeRect(sx, sy, sW, sH, C_BLACK, 0, 255, false)
    for i = 1, 6 do
        local x0 = hx + (i - 1) * hW / 6
        rect(x0, hy, hW / 6 + 1, hH, L.HUE[i])
        fadeRect(x0, hy, hW / 6 + 1, hH, L.HUE[i + 1], 0, 255, true)
    end
    -- dragging inside the square or on the bar
    if mouse.click and not mouse.used then
        if inside(mouse.x, mouse.y, sx - 4, sy - 4, sW + 8, sH + 8) then d.drag = "sv"; mouse.used = true
        elseif inside(mouse.x, mouse.y, hx - 4, hy - 6, hW + 8, hH + 12) then d.drag = "h"; mouse.used = true end
    end
    if not mouse.held then d.drag = nil end
    if d.drag == "sv" then
        d.s = clamp((mouse.x - sx) / sW, 0, 1)
        d.v = 1 - clamp((mouse.y - sy) / sH, 0, 1)
    elseif d.drag == "h" then
        d.h = clamp((mouse.x - hx) / hW, 0, 1) * 359.9
    end
    if d.drag then
        local rr, gg, bb = hsv(d.h, d.s, d.v)
        settings[d.key] = L.toHex({ rr * 255, gg * 255, bb * 255 })
    end
    -- markers
    local mx, my = sx + d.s * sW, sy + (1 - d.v) * sH
    ring(mx, my, 6, C_BLACK, 200, 24)
    ring(mx, my, 5, C_WHITE, 255, 24)
    local hxm = hx + d.h / 360 * hW
    roundRect(hxm - 3, hy - 3, 6, hH + 6, 3, C_WHITE)
    roundRectLine(hxm - 3, hy - 3, 6, hH + 6, 3, C_BLACK, 160)

    -- quick colours
    local qy = y + 162
    for i, hx2 in ipairs(L.SWATCHES) do
        local qx = x + 12 + (i - 1) * 20
        local qc = L.hex(hx2)
        roundRect(qx, qy, 16, 16, 5, qc)
        roundRectLine(qx, qy, 16, 16, 5, T.border)
        if takeClick(qx, qy, 16, 16) then
            settings[d.key] = hx2
            d.h, d.s, d.v = rgbToHsv(qc)
        end
    end
    local cur = L.hex(settings[d.key])
    text(F.small, cur and ("#" .. settings[d.key]) or "theme colour", x + 12, y + 184, 22, T.text2)
    local bw = 64
    local bx = x + W - 12 - bw
    roundRect(bx, y + 185, bw, 20, 6, T.pill)
    roundRectLine(bx, y + 185, bw, 20, 6, T.border)
    textC(F.tiny, "Theme", bx + bw / 2, y + 185, 20, T.text)
    if takeClick(bx, y + 185, bw, 20) then settings[d.key] = "" end
    -- a click anywhere else closes the picker
    if mouse.click and not mouse.used and not inside(mouse.x, mouse.y, x, y, W, H) then mouse.used = true; dropdown = nil end
end

local function drawDropdownList()
    if not dropdown then return end
    local d = dropdown
    if d.picker then return L.drawPicker(d) end
    local t = anim("ddopen", 1, 16)
    local rowH = 30
    local full = #d.options * rowH + 8
    local maxH = min(full, 8 * rowH + 8)
    local h = maxH * t
    local sw, sh = draw.GetScreenSize()
    local y = d.by + 32
    if y + maxH > sh - 10 then y = d.by - 4 - maxH end
    local maxScroll = max(0, full - maxH)
    -- a long list opens at the entry that is picked, with a few above it
    d.scroll = d.scroll or clamp(((tonumber(settings[d.key]) or 1) - 4) * rowH, 0, maxScroll)
    if inside(mouse.x, mouse.y, d.x, y, d.w, maxH) then
        if mouse.wheel ~= 0 then d.scroll = clamp(d.scroll - mouse.wheel * rowH, 0, maxScroll); mouse.wheel = 0 end
    end

    roundRect(d.x, y + 3, d.w, h, 10, C_BLACK, 70)
    roundRect(d.x, y, d.w, h, 10, T.card)
    roundRectLine(d.x, y, d.w, h, 10, T.border)
    if t < 0.9 then return end

    for i, opt in ipairs(d.options) do
        local ry = y + 4 + (i - 1) * rowH - d.scroll
        if ry >= y and ry + rowH <= y + maxH then
            local hovered = inside(mouse.x, mouse.y, d.x + 4, ry, d.w - 8, rowH)
            if hovered then roundRect(d.x + 4, ry, d.w - 8, rowH, 7, T.hover) end
            local sel = settings[d.key] == i
            text(F.small, fit(F.small, opt, d.w - 50), d.x + 14, ry, rowH, sel and accent() or T.text)
            if sel then text(F.icon, "✓", d.x + d.w - 26, ry, rowH, accent()) end
            if takeClick(d.x + 4, ry, d.w - 8, rowH) then
                settings[d.key] = i
                dropdown = nil
                return
            end
        end
    end
    if mouse.click and not mouse.used then mouse.used = true; dropdown = nil end
end

-- a row with a label and a live value on the right
local function infoRow(label, value)
    if rowVisible(48) then
        card(nil, 48)
        text(F.ui, label, cx + 16, cy, 48, T.text)
        text(F.small, value, cx + cw - 16 - textW(F.small, value), cy, 48, accent())
    end
    cy = cy + 58
end

-- the names of a list
local namesCache = {}
local function names(list)
    local out = namesCache[list]
    if out then return out end
    out = {}
    for i, v in ipairs(list) do out[i] = type(v) == "table" and (v.name or v[1]) or v end
    namesCache[list] = out
    return out
end

-- a row with a colour swatch
local function colorRow(label, key, fallback)
    if rowVisible(48) then
        local cur = L.hex(settings[key]) or fallback
        local pw = 140
        local bx, by = cx + cw - 16 - pw, cy + 10
        if not dropdown and mouse.y >= view.top and mouse.y < view.bot and takeClick(bx, by, pw, 28) then
            local h, s, v = rgbToHsv(cur)
            dropdown = { picker = true, key = key, x = bx + pw - 240, y = by + 34, by = by, h = h, s = s, v = v }
            animValues.ddopen = 0
        end
        card(nil, 48)
        text(F.ui, fit(F.ui, label, cw - pw - 40), cx + 16, cy, 48, T.text)
        local open = dropdown and dropdown.picker and dropdown.key == key
        roundRect(bx, by, pw, 28, 8, T.pill)
        roundRectLine(bx, by, pw, 28, 8, open and accent() or T.border)
        roundRect(bx + 6, by + 5, 30, 18, 5, cur)
        roundRectLine(bx + 6, by + 5, 30, 18, 5, C_WHITE, 40)
        local own = settings[key] ~= ""
        text(F.small, own and ("#" .. settings[key]) or "theme", bx + 46, by, 28, own and T.text or T.muted)
    end
    cy = cy + 58
end

function L.saveSlot()
    local ok, err = saveConfig("slot" .. settings.slot)
    saveConfig("autosave")
    if ok then
        L.slotHas[settings.slot] = true
        notify("✔", "Saved to Slot " .. settings.slot, "destiny_slot" .. settings.slot .. ".cfg", accent())
    else
        notify("✖", "Could not save", err, RED)
    end
    return ok
end

-- loading a slot: a saved one loads
function L.loadSlot()
    local slot = settings.slot
    L.backup()
    if L.slotSaved(slot) and loadConfig("slot" .. slot) then
        settings.slot = slot
        notify("✔", "Loaded Slot " .. slot, nil, accent())
    else
        resetConfig()
        settings.slot = slot
        notify("✦", "Slot " .. slot .. " is empty", "started fresh, your other slots are untouched", accent())
    end
end

L.SLOTS = { "Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5" }
L.COLOR_KEYS = { "colAccent", "colWin", "colSide", "colCard", "colText", "colText2", "colBorder", "colSwitch" }

-- garbage test: each lmaobox call 200 times off-screen, bytes of garbage left per call (once a second, Info page)
L.GC_MODES = { "Generational (small, frequent)", "Normal (big, rare)" }
L.PROBES = {
    { "draw.Color", function() draw.Color(255, 255, 255, 1) end },
    { "draw.FilledRect", function() draw.FilledRect(-50, -50, -49, -49) end },
    { "draw.TexturedRect", function() draw.TexturedRect(WHITE, -50, -50, -49, -49) end },
    { "draw.SetFont", function() draw.SetFont(F.small) end },
    { "draw.GetTextSize", function() draw.GetTextSize("probe") end },
    { "draw.Text", function() draw.Text(-200, -200, "probe") end },
    { "draw.Line", function() draw.Line(-50, -50, -49, -49) end },
    { "draw.OutlinedCircle", function() draw.OutlinedCircle(-50, -50, 5, 12) end },
    { "input.IsButtonDown", function() input.IsButtonDown(MOUSE_LEFT) end },
    { "input.GetMousePos", function() input.GetMousePos() end },
    { "globals.RealTime", function() globals.RealTime() end },
    { "nothing (baseline)", function() end },
}
L.probeAt = 0
function L.runProbe()
    if now() - L.probeAt < 1 then return end
    L.probeAt = now()
    draw.Color(255, 255, 255, 1)
    for _, p in ipairs(L.PROBES) do
        local best = nil
        for _ = 1, 3 do                                        -- 3 tries, the lowest (a cleanup can run mid-test)
            local m0 = collectgarbage("count")
            for _ = 1, 200 do p[2]() end
            local b = (collectgarbage("count") - m0) * 1024 / 200
            if b >= 0 and (not best or b < best) then best = b end
        end
        p[3] = best or 0
    end
    L.ccOk = false
end

-- pages ---------------------------------------------------------------------------
-- sky preview window: the four sides of a sky as one wide picture that can be dragged around.
-- three sizes (small, normal, whole screen), in the menu's colours
L.pv = { open = false, name = "", mode = 2, pan = 0, x = nil, y = nil, tex = nil, texName = nil,
         q = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 1 }, { 0, 0, 0, 1 } } }
L.PV_SIZES = { { 360, 180 }, { 720, 360 } }

function L.pv.free()
    local V = L.pv
    if V.tex then pcall(draw.DeleteTexture, V.tex) end
    V.tex, V.texName = nil, nil
end

function L.pv.show(name)
    local V = L.pv
    if not name or name == "" then return end
    if V.texName ~= name then
        V.free()
        pcall(filesystem.CreateDirectory, "destiny_files")
        pcall(filesystem.CreateDirectory, "destiny_files/skybox")
        local ok, gd = pcall(engine.GetGameDir)
        local dir = ((ok and gd) and tostring(gd) or ""):gsub("[\\/]tf[\\/]?$", "") .. "\\destiny_files\\skybox\\"
        local rel = "destiny_files/skybox/" .. name .. "_wide.jpg"
        local okF, f = pcall(io.open, rel, "rb")
        if okF and f then f:close()
        else
            local okG, data = pcall(http.Get, L.SKY_REPO .. "pano/" .. name .. ".b64")
            local jpg = (okG and type(data) == "string" and #data > 500) and L.paimon.b64(data, 1, #data) or ""
            if jpg:byte(1) ~= 255 or jpg:byte(2) ~= 216 then
                notify("✖", "No preview for this sky", name, RED)
                return
            end
            local okW, w = pcall(io.open, rel, "wb")
            if not okW or not w then notify("✖", "Can't save the preview", "destiny_files/skybox", RED); return end
            w:write(jpg); w:close()
        end
        local okT, id = pcall(draw.CreateTexture, dir .. name .. "_wide.jpg")
        L.recolor()
        if not okT or not id then notify("✖", "Can't show the preview", name, RED); return end
        V.tex, V.texName = id, name
    end
    V.name, V.open = name, true
    if V.mode == 3 then V.mode = 2 end
end

-- where the window is: x, y, w, h and the height of its title bar
function L.pv.rect()
    local V = L.pv
    local sw, sh = draw.GetScreenSize()
    if V.mode == 3 then return 0, 0, sw, sh, 36 end
    local sz = L.PV_SIZES[V.mode]
    local w, h = sz[1], sz[2] + 36
    if not V.x then V.x, V.y = sw - w - 40, 80 end
    V.x, V.y = clamp(V.x, 0, max(0, sw - w)), clamp(V.y, 0, max(0, sh - h))
    return V.x, V.y, w, h, 36
end

-- runs before the menu so a click on the window doesn't reach what is under it
function L.pv.input()
    local V = L.pv
    local x, y, w, h, th = V.rect()
    if not mouse.held then V.dragWin, V.dragPan = false, false end
    if V.dragWin then V.x, V.y = mouse.x - V.dx, mouse.y - V.dy end
    if V.dragPan then
        V.pan = V.panAt - (mouse.x - V.dx) / ((h - th) * 4)
        V.moved = now()
    end
    if dropdown or not inside(mouse.x, mouse.y, x, y, w, h) then return end
    local bx = x + w - 34
    if takeClick(bx, y + 6, 26, 24) then V.open = false; V.free(); return end
    if takeClick(bx - 30, y + 6, 26, 24) then
        if V.mode == 3 then V.mode = V.back or 2 else V.back, V.mode = V.mode, 3 end
    elseif takeClick(bx - 60, y + 6, 26, 24) then
        if V.mode == 3 then V.mode = V.back or 2 elseif V.mode == 2 then V.mode = 1 else V.mode = 2 end
    elseif V.mode ~= 3 and takeClick(x, y, w, th) then
        V.dragWin, V.dx, V.dy = true, mouse.x - x, mouse.y - y
    elseif takeClick(x, y + th, w, h - th) then
        V.dragPan, V.dx, V.panAt = true, mouse.x, V.pan
    end
    mouse.used = true
    mouse.wheel = 0
end

function L.pv.button(bx, by, glyph, hot)
    local hv = inside(mouse.x, mouse.y, bx, by, 26, 24)
    if hv then roundRect(bx, by, 26, 24, 7, hot and RED or T.hover) end
    textC(F.icon, glyph, bx + 13, by, 24, hv and T.text or T.text2)
end

function L.pv.draw()
    local V = L.pv
    local x, y, w, h, th = V.rect()
    local full = V.mode == 3
    local r = full and 0 or 14
    local acc = accent()
    if not full then
        roundRect(x - 2, y + 4, w + 4, h + 2, 16, C_BLACK, 90)
        roundRect(x, y, w, h, r, T.win)
        roundRect(x, y, w, th + 14, r, T.side)
        rect(x, y + th, w, 14, T.win)
    else
        rect(x, y, w, h, T.win)
        rect(x, y, w, th, T.side)
    end
    -- the picture: as much of the ring as fits, wrapped around at the end
    local px, py, pw, ph = x + (full and 0 or 6), y + th, w - (full and 0 or 12), h - th - (full and 0 or 6)
    if not V.dragPan and now() - (V.moved or -9) > 2 then V.pan = V.pan + frameDt() * 0.012 end
    V.pan = V.pan % 1
    local span = min(1, pw / (ph * 4))
    if V.tex then
        color(C_WHITE)
        local u0, left = V.pan, span
        local cxp = px
        while left > 0.0001 do
            local part = min(left, 1 - u0)
            local wpx = pw * part / span
            local q = V.q
            local x1, x2 = round(cxp), round(cxp + wpx)
            q[1][1], q[1][2], q[1][3] = x1, round(py), u0
            q[2][1], q[2][2], q[2][3] = x2, round(py), u0 + part
            q[3][1], q[3][2], q[3][3] = x2, round(py + ph), u0 + part
            q[4][1], q[4][2], q[4][3] = x1, round(py + ph), u0
            draw.TexturedPolygon(V.tex, q, true)
            cxp, left, u0 = cxp + wpx, left - part, 0
        end
    end
    -- title bar
    rect(x + (full and 0 or 12), y + th - 1, w - (full and 0 or 24), 1, acc, 170)
    text(F.icon, "☀", x + 14, y, th, acc)
    text(F.bold, fit(F.bold, V.name, w - 150), x + 38, y, th, T.text)
    local bx = x + w - 34
    L.pv.button(bx, y + 6, "✕", true)
    L.pv.button(bx - 30, y + 6, full and "❐" or "☐", false)
    L.pv.button(bx - 60, y + 6, (V.mode == 1) and "+" or "–", false)
    if not full then roundRectLine(x, y, w, h, r, T.border) end
    if not V.dragPan and now() - (V.moved or -9) > 2 and V.mode ~= 1 then
        textC(F.tiny, "drag the picture to look around", x + w / 2 + 1, y + h - 27, 16, C_BLACK, 170)
        textC(F.tiny, "drag the picture to look around", x + w / 2, y + h - 28, 16, C_WHITE, 200)
    end
end

-- the preview strip of a sky: four sides next to each other
function L.previewCard(name)
    local h = floor((cw - 16) / 4)
    if rowVisible(h + 16) then
        card(nil, h + 16)
        local id = L.lib.preview(name)
        if id then
            color(C_WHITE)
            draw.TexturedRect(id, round(cx + 8), round(cy + 8), round(cx + cw - 8), round(cy + 8 + h))
        else
            textC(F.small, L.lib.tex[name] == false and "No preview for this sky" or "Loading the preview...", cx + cw / 2, cy, h + 16, T.muted)
        end
    end
    cy = cy + h + 26
end

-- what was added, newest first: shown on the Info page
L.CHANGELOG = {
    { "Themes and looks", {
        "New themes: Royal, Liquid glass (see-through), Moon, Niko OneShot",
        "The same four as looks for the watermark, notifications and every HUD",
        "Niko drawn in the OneShot menu and peeking over OneShot panels",
        "Halloween theme: webs, pumpkins, bats, a spider and a ghost in the menu",
        "New menu background: Bats",
    } },
    { "Pets", {
        "Pets tab: a pet walks, runs, jumps and crouches along with you",
        "10 pets: Klee, Mechanical Cat, Chiikawa, Kafka, Elfaria, Lady Avalon,",
        "2B, Raiden Shogun, Niko and Spice",
        "Left, right or roaming, with hearts, sparkles and a rain cloud as reactions",
        "yeko's Pets: download pets from GitHub",
    } },
    { "Combat effects", {
        "Hit particles on the player you hit, 10 styles, own style for hits and kills",
        "Hitmarker with 5 shapes, gold on headshots",
        "Bullet tracers and a kill card (name, class, weapon, distance)",
        "Hit effect styles redrawn: Glow, Pulse, Scanlines, Glitch, Frost, Hard border",
    } },
    { "Player HUD", {
        "Session stats, own killfeed, health and ammo, killstreak emblem",
        "Round summary, low health screen effect, class meters",
        "Respawn timer and a match card with the round timer and scores",
        "Toggles to hide the game's own killfeed, health and ammo",
        "Domination and revenge notifications",
    } },
    { "Crosshair and view", {
        "Custom crosshair: 8 shapes, animations, reacts to moving, firing, hits and kills",
        "Viewmodel: weapon position, FOV, no sway, hide weapon",
        "Movement trail and screen weather",
    } },
    { "World", {
        "Custom skyboxes: your own from tf/materials/skybox",
        "yeko's Skies: 299 skies to download, with a preview window",
    } },
    { "Other", {
        "More waifu reactions (dominations, round end, low health, respawn)",
        "Own sounds for hits, kills and killstreaks (tf/sound/destiny_custom)",
        "Clean mode key and an Open config folder button",
        "Auto-updater fixed, menu opens and closes smoother",
    } },
}

function L.logCard(title, items)
    local h = 44 + #items * 20
    if rowVisible(h) then
        card(nil, h)
        text(F.bold, title, cx + 16, cy + 8, 24, accent())
        for i, it in ipairs(items) do
            disc(cx + 21, cy + 44 + (i - 1) * 20, 2, T.muted)
            text(F.small, fit(F.small, it, cw - 52), cx + 32, cy + 34 + (i - 1) * 20, 20, T.text2)
        end
    end
    cy = cy + h + 10
end

local PAGES = {
    { group = "VISUALS", icon = "◷", name = "Watermark", draw = function()
        section("Watermark")
        toggleRow("Show the watermark bar (name, FPS, clock)", "wmOn")
        dropRow("Watermark look", "wmStyle", L.WM_STYLES)
        toggleRow("Show FPS", "wmFps")
        toggleRow("Show the map name (in a match)", "wmMap")
        toggleRow("Show the clock", "wmTime")
        paraCard("Drag the watermark anywhere while the menu is open. Your Steam name is shown in it.")
    end },
    { group = "VISUALS", icon = "✉", name = "Notifications", draw = function()
        section("Notifications")
        toggleRow("Show notifications", "ntOn")
        dropRow("Notification style", "ntStyle", L.NT_STYLES)
        dropRow("Position", "ntPos", L.NT_POS)
        sliderRow("Stays on screen", "ntTime", 2, 8, "s")
        section("Notification look")
        if settings.ntStyle == 1 then toggleRow("Background", "ntBg") end
        dropRow("Border", "ntBorder", L.BORDERS)
        dropRow("Gradient (icon, title, time bar)", "ntGrad", L.GRADS)
        section("When")
        toggleRow("My kills (class, weapon, headshots, backstabs)", "ntKills")
        toggleRow("My deaths (who and with what)", "ntDeaths")
        toggleRow("Killstreaks (3, 5, 10, ...)", "ntStreaks")
        toggleRow("Assists", "ntAssists")
        toggleRow("Dominations and revenge", "ntDom")
        toggleRow("A lmaobox option is switched on or off", "ntFeatures")
        buttonRow("Send a test notification", "Test", function()
            notify("☠", "You killed " .. steamName(), "Heavy  •  Minigun  •  Headshot", accent())
        end)
    end },
    { group = "VISUALS", icon = "✸", name = "Hit effects", draw = function()
        section("Screen effect")
        toggleRow("Screen effect", "vigOn")
        dropRow("Effect style", "vigStyle", L.VIG_STYLES)
        toggleRow("On every hit", "vigHit")
        toggleRow("On every kill (stronger)", "vigKill")
        dropRow("Colour", "vigColor", L.VIG_COLORS)
        if settings.vigColor == 4 then
            colorRow("Hit colour", "colHit", L.RED_FX)
            colorRow("Kill colour", "colKill", accent())
        end
        toggleRow("Animate the colours", "vigAnim")
        sliderRow("Animation speed", "vigSpeed", 1, 10, "")
        sliderRow("Glow size", "vigSize", 2, 30, "")
        sliderRow("Effect stays (kills)", "vigStay", 200, 3000, " ms")
        sliderRow("Intensity", "vigInt", 10, 100, "%")
        sliderRow("Screen tint", "vigTintAmt", 0, 40, "")
        section("Extra effect")
        dropRow("Extra effect", "fxExtra", L.FX_EXTRA)
        toggleRow("On kills", "fxOnKill")
        toggleRow("On every hit", "fxOnHit")
        section("Hit particles")
        toggleRow("Particles where the player I hit is standing", "ptOn")
        dropRow("On a hit", "ptStyle", L.PT_STYLES)
        dropRow("On a kill", "ptKillStyle", L.PT_STYLES)
        dropRow("Colours", "ptCol", L.PT_COLORS)
        toggleRow("On every hit", "ptHit")
        toggleRow("On kills (a bigger burst)", "ptKill")
        sliderRow("Amount", "ptAmt", 30, 200, "%")
        sliderRow("Size", "ptSize", 40, 250, "%")
        buttonRow("Try the hit one a few steps in front of you", "Hit", function() L.ptTest(false) end)
        buttonRow("Try the kill one", "Kill", function() L.ptTest(true) end)
        infoRow("Bursts started / frames drawn", (L.pt3.made or 0) .. " / " .. (L.pt3.drawn or 0))
        if L.pt3.err then infoRow("Last problem", fit(F.small, L.pt3.err, cw * 0.6)) end
        section("Bullet tracers")
        toggleRow("Lines where my bullets go", "trOn")
        dropRow("Look", "trStyle", L.TR_STYLES)
        dropRow("Colour", "trCol", L.TR_COLS)
        sliderRow("Stays", "trTime", 200, 2000, " ms")
        section("Screen shake")
        toggleRow("Shake the screen on kills (only the view, never your aim)", "shakeOn")
        dropRow("Shake style", "shakeStyle", L.SHAKE_STYLES)
        sliderRow("Shake strength", "shakeAmt", 1, 100, "")
        toggleRow("Shake on every hit too", "shakeOnHit")
        buttonRow("Try the hit effects", "Hit", function() L.hitEffects(false); if not settings.fxOnHit then L.kfStart(false) end end)
        buttonRow("Try the kill effects", "Kill", function()
            local old = settings.shakeOn
            L.hitEffects(true)
            settings.shakeOn = old
        end)
        section("Damage numbers")
        toggleRow("Show the damage I deal", "dmgOn")
        dropRow("Damage number style", "dmgStyle", L.DMG_STYLES)
        section("Sound")
        dropRow("Hit sound", "hitSound", names(L.HIT_SOUNDS))
        dropRow("Kill sound", "killSound", names(L.KILL_SOUNDS))
        dropRow("Killstreak sound (3, 5, 10 ...)", "ksSound", names(L.STREAK_SOUNDS))
        buttonRow("Own sounds (" .. (L.ownSounds or 0) .. "): .wav files in tf/sound/destiny_custom", "Rescan", function()
            L.scanSounds()
            notify("♪", "Sounds rescanned", L.ownSounds .. " of your own found", accent())
        end)
        buttonRow("Play the sounds", "Play", function()
            playFrom(L.HIT_SOUNDS, settings.hitSound)
            playFrom(L.KILL_SOUNDS, settings.killSound)
        end)
    end },
    { group = "VISUALS", icon = "♛", name = "Kill announcer", draw = function()
        section("Kill announcer")
        toggleRow("Kill announcer", "kaOn")
        dropRow("Announcer design", "kaStyle", L.KA_STYLES)
        dropRow("Colours", "kaColor", L.KA_COLORS)
        if settings.kaColor == #L.KA_COLORS then colorRow("Custom colour", "colKa", accent()) end
        sliderRow("Time for a multi kill", "kaWindow", 2, 10, "s")
        toggleRow("Always play a kill sound with it", "kaSound")
        buttonRow("Preview", "Kill", function()
            local tier = (ka.tier % 10) + 1
            announce(tier, tier, "Preview  •  Heavy  •  Headshot")
        end)
        paraCard("Kills within the multi kill time count up: KILL, DOUBLE KILL, TRIPLE KILL ... up to GODLIKE. The number in the emblem is your killstreak.")
    end },
    { group = "VISUALS", icon = "▣", name = "Player HUD", draw = function()
        section("Look")
        dropRow("Look of these HUDs", "phStyle", L.HUD_STYLES)
        dropRow("Border", "phBorder", L.BORDERS)
        dropRow("Gradient", "phGrad", L.GRADS)
        section("Session stats")
        toggleRow("Show the session card (kills, deaths, K/D, time)", "ssOn")
        buttonRow("Start the session over", "Reset", function()
            local s = L.ss
            s.kills, s.deaths, s.assists, s.best, s.dmg, s.t0, L.ssAt = 0, 0, 0, 0, 0, now(), nil
        end)
        section("Killfeed")
        toggleRow("Show my kills and deaths", "kfOn")
        toggleRow("Also show assists", "kfAssists")
        toggleRow("Hide the game's own killfeed", "kfHide")
        sliderRow("An entry stays", "kfTime", 3, 15, "s")
        section("Health and ammo")
        toggleRow("Show my health", "hpOn")
        toggleRow("With ammo", "hpAmmo")
        toggleRow("Hide the game's own health and ammo", "hpHide")
        section("Killstreak counter")
        toggleRow("Show the killstreak counter", "ksOn")
        dropRow("Look", "ksStyle", L.KS_STYLES)
        sliderRow("Show from", "ksMin", 1, 5, " kills")
        toggleRow("Banner at 5, 10, 15, 20 and 25", "ksBanner")
        section("Round summary")
        toggleRow("Show a summary when a round ends", "rsOn")
        sliderRow("Stays on screen", "rsTime", 4, 15, "s")
        buttonRow("See what it looks like", "Preview", function() L.roundEnd(0, true) end)
        section("Kill card")
        toggleRow("A card for every kill (name, class, weapon, distance)", "kcOn")
        sliderRow("Stays", "kcTime", 2, 8, "s")
        buttonRow("See what it looks like", "Preview", L.kcPreview)
        section("Class meters")
        toggleRow("Über, cloak, charge, stickies, sniper charge, metal, rage", "cmOn")
        section("Respawn timer")
        toggleRow("Countdown while I'm dead, with who killed me", "rtOn")
        section("Match")
        toggleRow("Round timer and team scores", "mcOn")
        section("Low health")
        toggleRow("Colour the screen edges when my health is low", "lhOn")
        sliderRow("Starts below", "lhAt", 10, 60, "%")
        sliderRow("Strength", "lhInt", 10, 100, "%")
        toggleRow("Beat like a heart", "lhPulse")
        colorRow("Colour", "colLow", L.HOT)
        paraCard("Drag any of these anywhere while the menu is open. The killfeed only shows what you did and what happened to you. If the game's killfeed ever stays hidden, type hud_deathnotice_time 6 in the console; for its health and ammo, hidehud 0.")
    end },
    { group = "VISUALS", icon = "⌖", name = "Crosshair", draw = function()
        section("Crosshair")
        toggleRow("Show the custom crosshair", "chOn")
        toggleRow("Hide the game's own crosshair", "chHide")
        dropRow("Shape", "chShape", L.CH_SHAPES)
        sliderRow("Size", "chSize", 1, 30, "px")
        sliderRow("Gap", "chGap", 0, 20, "px")
        sliderRow("Thickness", "chThick", 1, 8, "px")
        sliderRow("Opacity", "chAlpha", 20, 100, "%")
        toggleRow("Black outline", "chOutline")
        colorRow("Colour", "colCh", C_WHITE)
        dropRow("Gradient (flowing colours)", "chGrad", L.GRADS)
        section("Animation")
        dropRow("Always running", "chAnim", L.CH_ANIMS)
        if settings.chAnim > 1 then sliderRow("Speed", "chSpeed", 1, 10, "") end
        toggleRow("Opens while I move", "chMove")
        toggleRow("Opens while I hold fire", "chFire")
        toggleRow("Kicks and changes colour on a hit", "chHit")
        toggleRow("Spins with a ring on a kill", "chKill")
        paraCard("Drawn in the middle of the screen while you are alive. Hit and kill colours are the ones from Hit effects. If the game's crosshair ever stays hidden, type crosshair 1 in the console.")
        section("Hitmarker")
        toggleRow("A hitmarker on every hit", "hmOn")
        dropRow("Shape", "hmStyle", L.HM_STYLES)
        dropRow("Colour", "hmCol", L.HM_COLS)
        sliderRow("Size", "hmSize", 4, 24, "px")
        sliderRow("Thickness", "hmThick", 1, 5, "px")
        sliderRow("Stays", "hmTime", 150, 800, " ms")
        toggleRow("Gold and bigger on headshots", "hmHead")
        buttonRow("See a hit and a kill", "Try", function()
            local old = settings.hmOn
            settings.hmOn = true
            L.hmHit(false, false); L.hm.t0 = now() - 0.05; L.hmHit(false, true)
            settings.hmOn = old
        end)
        section("Viewmodel")
        toggleRow("Change where my weapon is and how it looks", "vmOn")
        sliderRow("Forward / back", "vmX", -20, 20, "")
        sliderRow("Left / right", "vmY", -20, 20, "")
        sliderRow("Up / down", "vmZ", -20, 20, "")
        sliderRow("Weapon FOV", "vmFov", 40, 110, "")
        toggleRow("No weapon sway", "vmSway")
        toggleRow("Hide my weapon", "vmHide")
        paraCard("Uses the game's own viewmodel settings and puts them back when you turn this off or unload destiny. Some servers lock a few of them; those just don't change there. If lmaobox has its own viewmodel FOV turned on, it wins over Weapon FOV here.")
    end },
    { group = "VISUALS", icon = "☀", name = "World", draw = function()
        section("World look")
        toggleRow("Recolour the world", "worldOn")
        dropRow("Look", "worldPreset", names(L.WORLD_PRESETS))
        if settings.worldPreset == #L.WORLD_PRESETS then sliderRow("Custom colour (hue)", "worldHue", 0, 360, "°") end
        sliderRow("Brightness", "worldBright", 20, 100, "%")
        toggleRow("Sky too", "worldSky")
        toggleRow("Props too", "worldProps")
        paraCard("Applies by itself on every map while it is on, and again a few seconds in for anything that loads late.")
        section("Sky")
        local S = L.sky
        if not S.scanned then S.scan() end
        toggleRow("Use another sky", "skyOn")
        dropRow("Sky", "skySel", S.names)
        settings.skyName = S.list[settings.skySel] or ""
        infoRow("Your own skies found", tostring(S.own))
        buttonRow("Load the picked sky now (joins the server again)", "Rejoin", function()
            L.sky.rushUntil = now() + 30
            pcall(client.Command, "retry", true)
        end)
        buttonRow("Look for new skies in the folder", "Rescan", function()
            L.sky.scan()
            notify("☀", "Skies rescanned", L.sky.own .. " of your own found", accent())
        end)
        L.previewCard(settings.skyName)
        buttonRow("See the picked sky in a window", "Preview", function() L.pv.show(settings.skyName) end)
        section("yeko's Skies")
        paraCard("Downloads custom skyboxes from my GitHub.")
        local B = L.lib
        if not B.names then
            buttonRow("Show yeko's skies", "Load", B.load)
        else
            dropRow("Sky to download (" .. #B.names .. ")", "libSel", B.shown)
            local pick = B.names[settings.libSel] or ""
            if B.state == "downloading" then
                infoRow("Downloading " .. B.name, min(6, B.face) .. " / 6")
            else
                buttonRow(B.own[pick] and "Already in your folder" or "Download this sky (about 4 MB, the game pauses briefly)",
                          B.own[pick] and "Again" or "Download", B.start)
            end
            L.previewCard(pick)
            buttonRow("See how this sky looks before downloading", "Preview", function() L.pv.show(pick) end)
        end
        paraCard("Skies in your folder are marked with a star. To add one by hand, put the 6 .vtf pictures of a sky (ending in rt, lf, bk, ft, up, dn) into Team Fortress 2\\tf\\materials\\skybox and press Rescan. The game only loads a sky when a map starts: after picking one, press Rejoin or wait for the next map. Turning it off works the same way. Servers that block custom files show the map's own sky.")
        section("Movement trail")
        toggleRow("A trail behind me when I jump or move fast", "trlOn")
        dropRow("Look", "trlStyle", L.TRL_STYLES)
        dropRow("Colour", "trlCol", L.TR_COLS)
        sliderRow("Length", "trlLen", 2, 15, "")
        toggleRow("Always, not only when I jump or move fast", "trlAlways")
        if not settings.trlAlways then sliderRow("Shows from speed", "trlSpeed", 200, 800, " u/s") end
        sliderRow("Thickness", "trlWidth", 1, 16, "px")
        paraCard("The trail stays in the world where you were, so you see it when you look back or in third person.")
        section("Screen weather")
        toggleRow("Weather over the game", "wxOn")
        dropRow("Weather", "wxKind", L.WX)
        sliderRow("Amount", "wxAmt", 10, 100, "%")
        sliderRow("Opacity", "wxAlpha", 10, 100, "%")
    end },

    { group = "MISC", icon = "✎", name = "Appearance", draw = function()
        section("Design")
        dropRow("Theme", "theme", names(THEMES))
        dropRow("Accent colour", "accent", names(L.ACCENTS))
        dropRow("Logo gradient", "logo", L.LOGOS)
        section("Colours")
        local base = (THEMES[settings.theme] or THEMES[1]).pal
        colorRow("Accent", "colAccent", L.ACCENTS[settings.accent] and L.ACCENTS[settings.accent][2] or THEMES[settings.theme].accent)
        colorRow("Menu background", "colWin", base.win)
        colorRow("Sidebar", "colSide", base.side)
        colorRow("Cards and buttons", "colCard", base.card)
        colorRow("Text", "colText", base.text)
        colorRow("Second text", "colText2", base.text2)
        colorRow("Borders", "colBorder", base.border)
        colorRow("Switch (off)", "colSwitch", base.off)
        buttonRow("Reset every colour to the theme", "Reset", function()
            for _, k in ipairs(L.COLOR_KEYS) do settings[k] = "" end
        end)
        section("Menu background")
        sliderRow("Darken the background", "bgDim", 0, 90, "%")
        dropRow("Effect behind the menu", "bgFx", L.BG_FX)
        sliderRow("Effect amount", "bgFxAmt", 10, 100, "%")
        toggleRow("Glow around the menu", "menuGlow")
        sliderRow("Menu opacity", "opacity", 40, 100, "%")
    end },
    { group = "MISC", icon = "▤", name = "Overlay", draw = function()
        section("lmaobox HUD")
        toggleRow("Show the HUD (which lmaobox options are on)", "flOn")
        dropRow("HUD look", "flStyle", L.HUD_STYLES)
        dropRow("HUD border", "flBorder", L.BORDERS)
        dropRow("HUD gradient", "flGrad", L.GRADS)
        toggleRow("Compact (only what is on)", "flCompact")
        toggleRow("Show keybinds", "flKeys")
        toggleRow("Popup when an option is switched on or off", "ntFeatures")
        paraCard("Reads the lmaobox menu twice a second. Options lmaobox doesn't have are left out. Drag the HUD anywhere while the menu is open.")
    end },
    { group = "MISC", icon = "⌨", name = "Input monitor", draw = function()
        section("Input monitor")
        toggleRow("Show the input monitor", "imOn")
        dropRow("Style", "imStyle", L.IM_STYLES)
        toggleRow("Background", "imBg")
        paraCard("Shows W A S D, Shift, Ctrl, Space and the mouse buttons as you press them.")
        section("Speed graph")
        toggleRow("Show the speed graph (its own window)", "sgOn")
        dropRow("Style", "sgStyle", L.SG_STYLES)
        toggleRow("Background", "sgBg")
        paraCard("How fast you move (units per second) over the last 3 seconds, with the peak. Drag both anywhere while the menu is open.")
    end },
    { group = "MISC", icon = "♥", name = "Waifus", draw = function()
        local P = L.paimon
        section("Waifus")
        toggleRow("Show the waifu", "compOn")
        dropRow("Waifu", "compChar", names(L.COMPANIONS))
        sliderRow("Size", "compSize", 50, 200, "%")
        toggleRow("Speech bubbles (kills, deaths, classes, weapons)", "compBubbles")
        toggleRow("Also reacts to dominations, round ends, low health, respawns", "compReact")
        buttonRow("Make her say something", "Talk", function()
            local old = settings.compBubbles
            settings.compBubbles = true; compSay("idle"); settings.compBubbles = old
        end)
        buttonRow("Put her back in the corner", "Reset", function() settings.pos.comp = nil end)

        section("Paimon")
        if P.state == "downloading" then
            infoRow("Installing Paimon", string.format("%d / %d  -  %s", P.done + P.failed, P.TOTAL, P.current))
        else
            if P.installed() and not P.isV2() then
                buttonRow("New Paimon files available (quieter console)", "Update", P.install)
            else
                buttonRow(P.installed() and "Paimon is installed" or "Install Paimon (about 75 MB, the game pauses briefly per file)",
                          P.installed() and "Reinstall" or "Install", P.install)
            end
        end
        if P.state == "failed" and P.why then infoRow("Last error", fit(F.small, P.lastFail .. ": " .. P.why, cw * 0.6)) end
        toggleRow("Paimon speaks on kills (her voice)", "paiVoice")
        toggleRow("She also talks on her own (random voice lines)", "paiIdle")
        if settings.paiIdle then sliderRow("About every", "paiIdleEvery", 20, 300, "s") end
        toggleRow("Hit logs in her bubble (who, damage, HP left)", "paiLogs")
        if settings.paiLogs then sliderRow("Hit log stays", "paiLogTime", 2, 12, "s") end
        toggleRow("Genshin font in her bubbles", "paiFont")
        buttonRow("Play a random voice line", "Play", function() P.speak(true) end)
        paraCard("Paimon's pictures and font go to Team Fortress 2\\destiny_files\\paimon, her voice lines to tf\\sound\\destiny_paimon (TF2 only plays sounds from its sound folder). On servers that block custom sounds she just talks in bubbles.")

        section("Elfaria")
        toggleRow("Eyes follow the mouse (menu open)", "compFollow")
        paraCard("Elfaria is drawn live: she floats, blinks, talks and watches your mouse. Click her while the menu is open to pet her, drag her anywhere.")
    end },

    { group = "MISC", icon = "❖", name = "Pets", draw = function()
        local Q = L.pet
        section("Pets")
        toggleRow("A pet walks along with me", "petOn")
        dropRow("Pet", "petSel", L.petNameList())
        sliderRow("Size", "petSize", 40, 250, "%")
        sliderRow("Distance from me", "petDist", 30, 150, " u")
        dropRow("Side", "petSide", L.PET_SIDES)
        toggleRow("Walks a little ahead of me (so I can see it)", "petFront")
        toggleRow("Moves when I only turn the camera", "petCam")
        toggleRow("Hearts on kills, sparkles on streaks, rain when I die", "petReact")
        local state = "off"
        if settings.petOn then
            if Q.err then state = Q.err
            elseif not Q.active then state = "waiting until I am alive on a map"
            else state = "following (" .. Q.anim .. ")" end
        end
        infoRow("Status", fit(F.small, state, cw * 0.62))
        paraCard("Only you see the pet. It runs after you, jumps when you jump and crouches when you crouch, and hides behind walls. Its pictures are in Team Fortress 2\\destiny_files\\pets.")
        section("yeko's Pets")
        paraCard("Downloads pets from my GitHub.")
        local D = L.pdl
        if not D.names then
            buttonRow("Show yeko's pets", "Load", D.load)
        else
            dropRow("Pet to download (" .. #D.names .. ")", "pdlSel", D.shown)
            local e = D.names[settings.pdlSel]
            if D.state == "downloading" then
                infoRow("Downloading " .. D.entry.name, min(5, D.file) .. " / 5")
            elseif e then
                buttonRow(D.own[e.folder] and "Already downloaded" or "Download this pet (about 13 MB, the game pauses briefly)",
                          D.own[e.folder] and "Again" or "Download", D.start)
            end
        end
    end },
    { group = "SYSTEM", icon = "⚙", name = "Config", draw = function()
        section("Menu key")
        dropRow("Open the destiny menu with", "menuKey", names(L.MENU_KEYS))
        section("Clean mode")
        dropRow("Hide every destiny overlay with", "cleanKey", names(L.CLEAN_KEYS))
        if L.clean then infoRow("Clean mode", "on: overlays hidden") end
        paraCard("For screenshots and clips: the key hides everything destiny draws in the game, and pressing it again brings it back. The menu still opens.")
        section("Configs")
        dropRow("Config slot", "slot", L.SLOTS)
        L.slotNames()
        buttonRow("Save into this slot", "Save", L.saveSlot)
        buttonRow("Load this slot (an empty one starts fresh)", "Load", L.loadSlot)
        buttonRow("Undo the last load / reset", "Undo", function()
            if L.restoreBackup() then notify("↺", "Settings brought back", nil, accent())
            else notify("✖", "Nothing to undo", nil, RED) end
        end)
        buttonRow("Restore every default (nothing is saved)", "Reset", function()
            L.backup(); resetConfig(); notify("↺", "Defaults restored", "Undo brings your settings back", accent())
        end)
        buttonRow("Where are my configs? (to share them)", "Show", L.openConfigFolder)
        if L.cfgShown then paraCard(L.configDir() .. "  —  send a friend your destiny_slot1.cfg (or 2, 3 ...) and they put it in the same folder.") end
        section("Where")
        if DIR then
            paraCard("Configs are saved in: " .. (DIR == "" and "the Team Fortress 2 folder" or DIR) .. "  (autosave when you close the menu)")
        else
            paraCard("lmaobox doesn't let destiny write files anywhere, so configs can't be saved. Tried: " .. table.concat(L.CFG_TRIED, "  |  "))
        end
    end },
    { group = "SYSTEM", icon = "ⓘ", name = "Info", draw = function()
        section("About")
        paraCard("Destiny v1 Visual Lua for LMAOBOX. (BETA)")
        paraCard("Discord: yeko333")
        buttonRow("Check for updates", updater.running and "Checking..." or "Check", function() updaterCheck() end)
        section("Destiny 2.0")
        for _, e in ipairs(L.CHANGELOG) do L.logCard(e[1], e[2]) end
    end },
}

local function drawMenu(openT)
    local sw, sh = draw.GetScreenSize()
    menu.h = min(620, sh - 40)
    if not menu.x then menu.x, menu.y = floor((sw - menu.w) / 2), floor((sh - menu.h) / 2) end

    -- drag the window by the header strip of the content side
    if not dropdown and takeClick(menu.x + SIDE_W, menu.y, menu.w - SIDE_W, 56) then
        menu.dragging, menu.dx, menu.dy = true, mouse.x - menu.x, mouse.y - menu.y
    end
    if not mouse.held then menu.dragging = false end
    if menu.dragging then
        menu.x = clamp(mouse.x - menu.dx, 0, sw - menu.w)
        menu.y = clamp(mouse.y - menu.dy, 0, sh - menu.h)
    end

    local x, y, w, h = menu.x, round(menu.y + (1 - openT) * 10), menu.w, menu.h
    local acc = accent()

    menuGlow(x, y, w, h, openT)
    roundRect(x - 2, y + 4, w + 4, h + 2, 16, C_BLACK, 90)
    local ga = L.glassA()
    roundRect(x, y, w, h, 14, T.win, ga)
    if ga < 255 then
        roundRect(x + SIDE_W, y, w - SIDE_W, 70, 14, C_WHITE, 14)
        roundRectLine(x + 1, y + 1, w - 2, h - 2, 13, C_WHITE, 60)
    end
    roundRect(x, y, SIDE_W, h, 14, T.side, ga)
    rect(x + SIDE_W - 14, y, 14, h, T.side, ga)
    rect(x + SIDE_W, y + 14, 1, h - 28, T.border)
    local hw = L.isHW()
    local hwFl = (sin(now() * 7) + sin(now() * 13.3)) / 2
    if hw then
        L.hwWeb(x + 1, y + 1, 1, 1, 92)
        L.hwWeb(x + w - 1, y + h - 1, -1, -1, 110)
        roundRectLine(x, y, w, h, 14, acc, 130)
        roundRectLine(x + 3, y + 3, w - 6, h - 6, 12, acc, 34)
    end

    -- header: avatar, DESTINY logo, Steam name pill
    drawAvatar(x + 18, y + 18, 58, 14)
    disc(x + 70, y + 70, 7, T.side)
    disc(x + 70, y + 70, 5, acc)
    drawLogo("DESTINY", x + 88, y + 18)
    local nm = fit(F.small, steamName(), SIDE_W - 130)
    local pw = textW(F.small, nm) + 32
    roundRect(x + 88, y + 50, pw, 24, 12, T.pill)
    disc(x + 101, y + 62, 4, acc)
    text(F.small, nm, x + 111, y + 50, 24, T.text)
    rect(x + 16, y + 92, SIDE_W - 32, 1, T.border)

    -- navigation with group labels
    local ny = y + 104
    local lastGroup
    for i, p in ipairs(PAGES) do
        if p.group ~= lastGroup then
            lastGroup = p.group
            text(F.tiny, p.group, x + 26, ny, 20, T.muted)
            ny = ny + 22
        end
        local nx, nw = x + 12, SIDE_W - 24
        if not dropdown and takeClick(nx, ny, nw, 27) then
            if menu.page ~= i then menu.page, menu.scrollT = i, 0 end
        end
        local act = anim("nav" .. i, menu.page == i and 1 or 0, 14)
        local hv = anim("navh" .. i, (not dropdown and inside(mouse.x, mouse.y, nx, ny, nw, 27)) and 1 or 0, 14)
        roundRect(nx, ny, nw, 27, 9, mix(mix(T.side, T.hover, hv * 0.6), T.active, act))
        if act > 0.01 then roundRect(nx, ny + 6, 3, 15 * act, 2, acc) end
        text(F.icon, p.icon, nx + 14, ny, 27, menu.page == i and acc or T.muted)
        text(F.small, p.name, nx + 40, ny, 27, menu.page == i and T.text or T.text2)
        ny = ny + 28
    end

    -- "Save config" button at the bottom of the sidebar
    local bx, by, bw, bh = x + 12, y + h - 54, SIDE_W - 24, 40
    if not dropdown and takeClick(bx, by, bw, bh) then
        if L.saveSlot() then L.savedAt = now() end
    end
    local sv = anim("save", (not dropdown and inside(mouse.x, mouse.y, bx, by, bw, bh)) and 1 or 0, 14)
    local justSaved = now() - L.savedAt < 1.6
    local sweep = clamp((now() - L.savedAt) / 0.35, 0, 1)
    roundRect(bx, by, bw, bh, 12, mix(T.card, T.hover, sv))
    if justSaved then roundRect(bx, by, bw * sweep, bh, 12, acc, 120 * (1 - clamp((now() - L.savedAt - 1.1) / 0.5, 0, 1))) end
    roundRectLine(bx, by, bw, bh, 12, T.border)
    text(F.icon, justSaved and "✔" or "▣", bx + 16, by, bh, justSaved and acc or T.text2)
    text(F.ui, justSaved and "Saved" or "Save config", bx + 44, by, bh, T.text)

    -- content: title, scrolling page
    local page = PAGES[menu.page]
    local contentX = x + SIDE_W + 28
    view.top, view.bot = y + 64, y + h - 14
    view.wtop, view.wbot = y, y + h
    cw = w - SIDE_W - 56
    if inside(mouse.x, mouse.y, x + SIDE_W, view.top, w - SIDE_W, view.bot - view.top) and not dropdown and mouse.wheel ~= 0 then
        menu.scrollT = menu.scrollT - mouse.wheel * 60
        mouse.wheel = 0
    end
    local maxScroll = max(0, menu.contentH - (view.bot - view.top))
    menu.scrollT = clamp(menu.scrollT, 0, maxScroll)
    menu.scroll = menu.scroll + (menu.scrollT - menu.scroll) * min(1, frameDt() * 14)

    cx, cy = contentX, view.top - menu.scroll
    local startY = cy
    page.draw()
    menu.contentH = cy - startY

    -- cover what scrolled out of view
    if L.glassA() == 255 then
        rect(x + SIDE_W + 1, y + 1, w - SIDE_W - 27, view.top - y - 1, T.win)
        rect(x + SIDE_W + 1, view.bot, w - SIDE_W - 27, y + h - view.bot - 1, T.win)
    end
    roundRectLine(x, y, w, h, 14, T.border)
    text(F.title, page.name, contentX, y + 20, 30, T.text)
    if hw then
        L.screenSpace()
        L.hwPumpkin(contentX + textW(F.title, page.name) + 26, y + 36, 11, hwFl)
        L.hwScene(contentX + textW(F.title, page.name) + 60, x + w - 30, y + 2, y + 62, hwFl)
    end
    if L.isNiko() then
        local nx, ny = x + w - 62, y + 44
        local pulse = 0.7 + 0.3 * sin(now() * 2.2)
        disc(nx - 50, ny + 6, 15, L.OS.sun, 46 * pulse)
        disc(nx - 50, ny + 6, 8, L.OS.sunL, 255)
        L.drawNiko(nx, ny, 40, 255)
    end

    -- scrollbar
    if maxScroll > 0 then
        local trackH = view.bot - view.top
        local barH = max(30, trackH * trackH / menu.contentH)
        local barY = view.top + (trackH - barH) * (menu.scroll / maxScroll)
        roundRect(x + w - 12, barY, 4, barH, 2, acc, 200)
    end

    drawDropdownList()
end

---------------------------------------------------------------------------
-- 12. Main loop
---------------------------------------------------------------------------
-- runs one part
local reported = {}
-- how long each part takes
L.cost = {}
L.clock = (os and os.clock) or function() return 0 end
local function safe(name, fn, ...)
    local m0 = collectgarbage("count")
    local t0 = L.clock()
    local ok, err = pcall(fn, ...)
    local ms = (L.clock() - t0) * 1000
    local kb = collectgarbage("count") - m0
    if kb < 0 then kb = 0; L.gcRan = true end                          -- (memory went down = a cleanup ran in this part)
    if ms > L.slowMs then L.slowMs, L.slowName = ms, name end
    L.cost[name] = (L.cost[name] or ms) * 0.95 + ms * 0.05
    L.gc[name] = (L.gc[name] or kb) * 0.95 + kb * 0.05
    -- the worst frame of each part in the last 3 seconds
    if ms > (L.worst[name] or 0) or now() - (L.worstAt[name] or 0) > 3 then L.worst[name], L.worstAt[name] = ms, now() end
    ALPHA = 1
    if not ok and tostring(err):find("Color not set", 1, true) then L.ccOk = false; ok = true end   -- (just set it again next time)
    if not ok and not reported[name] then
        reported[name] = true
        -- short form "line 123
        local msg = tostring(err):gsub("^.-destiny%.lua:", "line ")
        print("[destiny] " .. name .. " - " .. msg)
    end
end
L.gc, L.worst, L.worstAt = {}, {}, {}
L.slowMs, L.slowName, L.gcRan, L.spikeAt = 0, "none", false, 0
L.frameWorst, L.frameWorstAt = 0, 0

local function onDraw()
    -- (no own cleanup step: it kept full cleanup rounds running nonstop = a drop every ~3 s)
    L.gcMaxMs = max(L.gcPrevMs or 0, L.gcMs or 0); L.gcPrevMs = L.gcMs
    perfTick()
    local ft = globals.AbsoluteFrameTime() * 1000
    if ft > L.frameWorst or now() - L.frameWorstAt > 3 then L.frameWorst, L.frameWorstAt = ft, now() end
    L.slowMs, L.slowName, L.gcRan = 0, "none", false
    L.curFont = nil
    L.ccOk = false                                                    -- (forget the remembered colour each frame)
    if settings.gcMode ~= L.gcModeSet then                            -- (Info > Memory cleanup)
        L.gcModeSet = settings.gcMode
        if settings.gcMode == 2 then pcall(collectgarbage, "incremental", 200, 100)
        else pcall(collectgarbage, "generational", 20, 100) end
    end
    L.boxFrame()
    if L.sky.rushUntil and settings.skyOn then
        if now() < L.sky.rushUntil then L.sky.enforce() else L.sky.rushUntil = nil end
    end
    if engine.IsTakingScreenshot() then return end
    L.buildPalette()

    -- the destiny menu has its own key
    local typing = engine.IsChatOpen() or engine.Con_IsVisible()
    local key = (L.MENU_KEYS[settings.menuKey] or L.MENU_KEYS[1])[2]
    local esc = pressed(KEY_ESCAPE)
    if pressed(key) and not typing then menu.open = not menu.open end
    if menu.open and esc then menu.open = false end
    if menu.open ~= menu.cursor then
        menu.cursor = menu.open
        pcall(input.SetMouseInputEnabled, menu.open)
        if not menu.open then L.saveAt = now() + 0.8 end
    end
    if L.saveAt and now() >= L.saveAt and not menu.open then
        L.saveAt = nil
        local text = serialize()
        if text ~= L.lastSaved and saveConfig("autosave") then L.lastSaved = text end
    end
    -- while the lmaobox menu is closed there is no cursor and GetMousePos can give nothing back
    local ok, pos = pcall(input.GetMousePos)
    if ok and type(pos) == "table" and pos[1] then mouse.x, mouse.y = pos[1], pos[2] end
    mouse.click = pressed(MOUSE_LEFT)
    mouse.held = input.IsButtonDown(MOUSE_LEFT)
    mouse.used = false
    mouse.wheel = (wheel(MOUSE_WHEEL_UP) and 1 or 0) - (wheel(MOUSE_WHEEL_DOWN) and 1 or 0)
    menu.openT = anim("menuopen", menu.open and 1 or 0, 14)
    if not menu.open then dropdown, sliderDrag = nil, nil end

    -- clicks on the menu window belong to the menu
    local onMenu = overMenu()
    if onMenu then mouse.used = true end

    safe("features", pollFeatures)
    if L.paimon.state == "downloading" then safe("paimon install", L.paimon.work) end
    if L.lib.state == "downloading" then safe("sky download", L.lib.work) end
    if L.pdl.state == "downloading" then safe("pet download", L.pdl.work) end
    safe("world", updateWorld)
    -- auto-update: the menu is already up and usable
    if not updater.checked and now() >= updater.startAt then
        updater.checked = true
        safe("update check", updaterCheck, true)
    end

    -- game-world effects first
    safe("self", L.pollSelf)
    -- clean mode: one key hides every destiny overlay (the menu still opens)
    local ck = L.CLEAN_KEYS[settings.cleanKey]
    if ck and ck[2] and ck[2] ~= key and not typing and pressed(ck[2]) then
        L.clean = not L.clean
        if not L.clean then notify("◐", "Destiny overlays are back", nil, accent()) end
    end
    if settings.vmOn or L.vm.orig then safe("viewmodel", L.vmApply) end
    if settings.trOn then safe("tracer shots", L.trPoll) end
    if settings.trlOn then safe("trail points", L.trailPoll) end
    if L.clean then
        pcall(L.chCvar, true); pcall(L.kfCvar, true); pcall(L.hpCvar, true)
    else
    if settings.wxOn then safe("weather", L.drawWeather) end
    if settings.trlOn then safe("trail", L.drawTrail) end
    if settings.trOn then safe("tracers", L.drawTracers) end
    if settings.lhOn then safe("low health", L.drawLowHealth) end
    safe("screen effect", L.drawEdgeEffect)
    safe("extra effect", L.drawExtraEffect)
    if settings.petOn then safe("pet", L.pet.update); safe("pet draw", L.pet.draw) end
    if settings.ptOn then safe("particles", L.drawParticles) end
    if settings.dmgOn then safe("damage", drawDamage) end
    safe("announcer", drawAnnouncer)
    if settings.wmOn then safe("watermark", drawWatermark) end
    if settings.flOn then safe("hud", L.drawHud) end
    if settings.imOn then safe("input monitor", drawInputMonitor) end
    if settings.sgOn then safe("speed graph", L.drawSpeedGraph) end
    if settings.chOn or L.chHidden then safe("crosshair", L.drawCrosshair) end
    if settings.hmOn then safe("hitmarker", L.drawHitmarker) end
    if settings.ssOn then safe("stats", L.drawStats) end
    if settings.kfOn or settings.kfHide or L.kfHidden then safe("killfeed", L.drawFeed) end
    if settings.hpOn or L.hpHidden then safe("health", L.drawVitals) end
    if settings.ksOn then safe("killstreak", L.drawStreak) end
    if settings.rsOn then safe("round summary", L.drawRound) end
    if settings.kcOn then safe("kill card", L.drawKillCard) end
    if settings.cmOn then safe("meters", L.drawMeters) end
    if settings.rtOn then safe("respawn", L.drawRespawn) end
    if settings.mcOn then safe("match", L.drawMatch) end
    if settings.compOn then safe("waifu", drawCompanion) end
    safe("notifications", drawNotifications)
    safe("welcome", L.drawWelcome)
    end

    if menu.openT > 0.01 then
        safe("background", drawBackground, menu.openT)
        if onMenu then mouse.used = false end
        if L.pv.open then safe("sky preview input", L.pv.input) end
        ALPHA = menu.openT * settings.opacity / 100
        safe("menu", drawMenu, menu.openT)
        if L.pv.open then
            ALPHA = menu.openT
            safe("sky preview", L.pv.draw)
        end
    end
end

callbacks.Register("Draw", "destiny_draw", onDraw)
callbacks.Register("FireGameEvent", "destiny_events", function(e) safe("events", onGameEvent, e) end)
-- screen shake: moves only the picture you see, never where you aim
callbacks.Register("RenderView", "destiny_shake", function(view) pcall(L.onRenderView, view) end)
callbacks.Register("Unload", "destiny_unload", function()
    pcall(collectgarbage, "restart")                                -- (Lua cleans up on its own again)
    saveConfig("autosave")
    if menu.cursor then pcall(input.SetMouseInputEnabled, false) end
    if settings.worldOn then applyWorld(true) end
    pcall(L.sky.restore)
    pcall(L.lib.clear)
    pcall(L.pet.remove)
    pcall(L.vmApply, true)
    pcall(L.pv.free)
    pcall(L.chCvar, true)
    pcall(L.kfCvar, true)
    pcall(L.hpCvar, true)
    pcall(draw.DeleteTexture, WHITE)
    for _, t in pairs(shapeTex) do pcall(draw.DeleteTexture, t.id) end
    L.boxClear()
    if L.scanTex then pcall(draw.DeleteTexture, L.scanTex) end
    L.paimon.unloadTextures()
    callbacks.Unregister("Draw", "destiny_draw")
    callbacks.Unregister("FireGameEvent", "destiny_events")
    callbacks.Unregister("RenderView", "destiny_shake")
end)

print("destiny loaded - press " .. (L.MENU_KEYS[settings.menuKey] or L.MENU_KEYS[1])[1] .. " to open the menu")
