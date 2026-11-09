--[[
    destiny  -  menu, overlays and effects for lmaobox (design ported from M0MENT4M 2.2)

    Opens with its own key (F8 by default). Configs are saved next to destiny.lua
    (destiny_autosave.cfg, destiny_slot1.cfg ...) or in the first folder lmaobox lets it write to.

     1. basics, settings, config files
     2. themes, colours, gradients
     3. drawing helpers
     4. mouse, dragging
     5. player info (Steam name, letter avatar)
     6. effects: notifications, damage numbers, kill announcer, sounds, waifu bubbles
     7. game events (kills, deaths, hits; class and weapon names)
     8. overlays: watermark, input monitor, waifus, notifications, damage numbers,
        hit effects (screen edge, extra effect, shake), lmaobox HUD, speed graph, welcome message
     9. menu background effects
    10. world look
    11. menu widgets, pages, window
    12. main loop
]]

---------------------------------------------------------------------------
-- 1. Basics, settings, config files
---------------------------------------------------------------------------
local floor, min, max, abs, sin, cos, sqrt, pi = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt, math.pi
local function clamp(v, a, b) return max(a, min(b, v)) end
local function now() return globals.RealTime() end
local function frameDt() return clamp(globals.AbsoluteFrameTime(), 0.0001, 0.1) end
local function round(v) return floor(v + 0.5) end

-- Garbage = stutters: every table, function or string made per frame has to be cleaned up later, and
-- Lua's cleanup pause is what made the FPS drop every ~2 seconds. So: shared colour constants, reused
-- tables, caches without string keys, and the generational collector (cleans up in small steps).
local C_BLACK, C_WHITE = { 0, 0, 0 }, { 255, 255, 255 }
-- fixed lists and a few state values live in one table (Lua allows only 200 top-level locals)
local L = {}
-- Cleanup: lmaobox's draw calls leave ~250 bytes of garbage each (hundreds a frame). The generational mode let
-- ~110 MB pile up and then cleaned it all at once = 100 ms freezes. Incremental mode cleans
-- in small pieces as it goes, so it never piles up into one big freeze.
pcall(collectgarbage, "incremental", 200, 100)                     -- (Lua's normal pace: start when memory doubles)

-- memory readout for the Info page: Lua memory and how much new garbage is made per second
local perf = { kb = 0, rate = 0, lastKb = nil, at = 0, made = 0 }
local function perfTick()
    local kb = collectgarbage("count")
    if perf.lastKb and kb > perf.lastKb then perf.made = perf.made + (kb - perf.lastKb) end
    perf.lastKb, perf.kb = kb, kb
    if globals.RealTime() - perf.at >= 1 then
        perf.rate, perf.made, perf.at = perf.made / max(0.001, globals.RealTime() - perf.at), 0, globals.RealTime()
    end
end

-- Where configs are saved. lmaobox may only let scripts write in some folders, so a few places are tried
-- (next to destiny.lua first, as wanted) and the first one that really accepts a test file is used.
-- (the data folder is "destiny_files", not "destiny": a folder with the same name as the script stops
--  lmaobox from loading destiny.lua)
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
pcall(filesystem.CreateDirectory, "destiny_files")               -- (relative = inside the TF2 folder)
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
    -- appearance ("" colour = use the theme's own colour)
    theme = 1, accent = 1, logo = 1, opacity = 100,
    bgDim = 35, bgFx = 2, bgFxAmt = 50, menuGlow = true,
    colAccent = "", colWin = "", colSide = "", colCard = "", colText = "", colText2 = "", colBorder = "", colSwitch = "",
    -- watermark
    wmOn = true, wmStyle = 2, wmFps = true, wmMap = true, wmTime = true,
    -- notifications
    ntOn = true, ntStyle = 1, ntPos = 1, ntTime = 4, ntKills = true, ntDeaths = true, ntStreaks = true, ntAssists = true, ntFeatures = true,
    ntBg = true, ntBorder = 2, ntGrad = 1,
    -- hit effects: screen edge effect + extra effect + shake
    vigOn = true, vigStyle = 1, vigColor = 1, vigHit = true, vigKill = true, vigInt = 70, vigSize = 14, vigTintAmt = 10,
    vigAnim = false, vigSpeed = 5, vigStay = 900, colHit = "FF2D55", colKill = "10B981",
    fxExtra = 2, fxOnHit = false, fxOnKill = true,
    shakeOn = false, shakeStyle = 1, shakeAmt = 40, shakeOnHit = false,
    dmgOn = true, dmgStyle = 2, hitSound = 1, killSound = 1,
    -- kill announcer
    kaOn = true, kaStyle = 2, kaWindow = 4, kaSound = true, kaColor = 1, colKa = "",
    -- world
    worldOn = false, worldPreset = 1, worldHue = 260, worldBright = 80, worldSky = true, worldProps = true,
    -- overlay HUD (lmaobox options), input monitor, speed graph
    flOn = false, flStyle = 1, flBorder = 1, flGrad = 1, flCompact = false, flKeys = true,
    imOn = false, imStyle = 1, imBg = true, sgOn = false, sgStyle = 1, sgBg = true,
    -- waifus
    compOn = false, compChar = 1, compSize = 100, compBubbles = true, compFollow = true,
    paiVoice = true, paiFont = true, paiLogs = true, paiLogTime = 4,     -- (compChar: 1 = Paimon, 2 = Elfaria)
    paiIdle = true, paiIdleEvery = 90,                                     -- (random voice lines on her own, seconds)
    -- config
    slot = 1,
    -- menu key (index into L.MENU_KEYS)
    menuKey = 1,
}

-- keys that can open the destiny menu (its own key, so it never opens together with the lmaobox menu)
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

-- configs: destiny_autosave.cfg, destiny_slot1.cfg, ... in the folder found above
local function configPath(name) return (DIR or LUA_DIR) .. "destiny_" .. name .. ".cfg" end

-- returns true, or false + the reason (shown in a notification)
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

-- default settings, keeping the slot and the menu key (positions of things on screen are reset too)
local function resetConfig()
    local keepSlot, keepKey = settings.slot, settings.menuKey
    for k, v in pairs(DEFAULTS) do settings[k] = v end
    settings.pos = {}
    settings.slot, settings.menuKey = keepSlot, keepKey
end

-- which slots have a saved config (checked when the Config page asks, remembered after saving)
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

-- the state before the last load / reset, so "Undo" can bring it back (kept in memory and in a backup file)
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
-- 2. Themes, colours, gradients (all values from M0MENT4M 2.2designs.ahk)
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
}

L.ACCENTS = {
    { "Theme colour", nil }, { "Emerald", { 16, 185, 129 } }, { "Violet", { 124, 108, 255 } }, { "Rose", { 232, 69, 111 } },
    { "Orange", { 255, 122, 24 } }, { "Sky", { 56, 189, 248 } }, { "Gold", { 250, 204, 21 } },
}

-- colours you pick yourself are stored as hex text ("10B981"); "" means "use the theme's colour"
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

-- the palette in use: the theme's colours with your own colours on top (one reused table, rebuilt per frame)
L.PAL = {}
local T = THEMES[1].pal                                 -- current palette (updated every frame)
function L.buildPalette()
    local base = (THEMES[settings.theme] or THEMES[1]).pal
    local P = L.PAL
    for k, v in pairs(base) do P[k] = v end
    local function over(key, field) local c = L.hex(settings[key]); if c then P[field] = c end end
    over("colWin", "win"); over("colSide", "side"); over("colCard", "card"); over("colText", "text")
    over("colText2", "text2"); over("colBorder", "border"); over("colSwitch", "off")
    local card = L.hex(settings.colCard)
    if card then                                       -- hover / pill follow a custom card colour
        P.hover = L.hexCache["h" .. settings.colCard] or { min(255, card[1] + 8), min(255, card[2] + 8), min(255, card[3] + 10) }
        L.hexCache["h" .. settings.colCard] = P.hover
        P.pill = L.hexCache["p" .. settings.colCard] or { min(255, card[1] + 5), min(255, card[2] + 5), min(255, card[3] + 6) }
        L.hexCache["p" .. settings.colCard] = P.pill
    end
    T = P
end

local function accent()
    local own = L.hex(settings.colAccent)
    if own then return own end
    return L.ACCENTS[settings.accent] and L.ACCENTS[settings.accent][2] or THEMES[settings.theme].accent
end

-- animated gradient presets of the M0MENT4M logo (SPLogoStopsRaw)
L.LOGOS = { "Accent Flow", "Aurora", "Sunset", "Ocean", "Fire", "Rainbow", "Candy", "Mono", "Static" }
-- (made once; the accent-based ones reuse one table instead of making a new list every call)
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

-- mixed colours come from a ring of 128 reused tables (they are only used right away, never kept)
local mixPool, mixAt = {}, 0
for i = 1, 128 do mixPool[i] = { 0, 0, 0 } end
local function mix(c1, c2, t)
    mixAt = mixAt % 128 + 1
    local o = mixPool[mixAt]
    o[1], o[2], o[3] = c1[1] + (c2[1] - c1[1]) * t, c1[2] + (c2[2] - c1[2]) * t, c1[3] + (c2[3] - c1[3]) * t
    return o
end

-- colour at position p (loops) along a list of stops
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
local ALPHA = 1   -- global fade multiplier for whatever is drawn right now

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

-- draw.Color only takes whole numbers 0..255. Alpha never goes below 1: lmaobox treats a fully
-- transparent colour as "Color not set" and the next draw call errors (that spammed the console).
local function color(c, a)
    draw.Color(clamp(round(c[1]), 0, 255), clamp(round(c[2]), 0, 255), clamp(round(c[3]), 0, 255),
               clamp(round((a or 255) * ALPHA), 1, 255))
end

-- nothing to draw when it would be invisible anyway (saves draw calls = FPS)
local function hidden(a) return (a or 255) * ALPHA < 1 end

local function rect(x, y, w, h, c, a)
    if hidden(a) then return end
    color(c, a)
    draw.FilledRect(round(x), round(y), round(x + w), round(y + h))
end

local function inside(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

-- Rounded shapes come from small smooth (anti-aliased) white pictures that are made once per size and
-- tinted by draw.Color. A rounded box is then 3 rectangles + 4 corner pictures (7 draw calls) instead of
-- one rectangle per pixel row (30-80 calls), which is what made the menu cost so much FPS.
local shapeTex = {}

local function pow2(n) local p = 2; while p < n do p = p * 2 end; return p end

-- size S x S picture; alphaAt(px, py) gives the coverage 0..1 of each pixel (centre of the pixel)
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
    shapeTex[key] = t
    return t
end

-- One picture per corner (1 top-left, 2 top-right, 3 bottom-left, 4 bottom-right): the quarter circle sits in
-- that corner of an S x S picture and the rest is clear. Drawn with TexturedRect at its real size, which
-- needs no Lua tables (TexturedPolygon needed 5 new tables per corner = garbage = stutters).
local cornerCache = { [true] = {}, [false] = {} }                   -- [outline][r][which], no string keys
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

-- whole circle with radius r in the middle of an S x S picture (bigger circles stretch the 32px one)
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

-- Rounded boxes as one ready-made picture: a box of a given size is built once (smooth edges, white, tinted by
-- draw.Color) and then drawn with ONE call instead of 7-8. Only sizes that come back over several frames get a
-- picture (animated sizes keep the piece-by-piece way), at most one new picture per frame (no hitches).
-- Keys are plain numbers (no strings, so looking them up makes no garbage).
L.boxTex, L.boxCount, L.boxN, L.boxBudget, L.boxCountAt, L.boxMadeAt = {}, {}, 0, 1, 0, -99
L.boxQuad = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
L.boxRow = {}
L.T0 = string.char(255, 255, 255, 0)

-- the 256 possible pixels (white with alpha 0..255), made once
L.PIX = {}
for a = 0, 255 do L.PIX[a] = string.char(255, 255, 255, a) end

-- Builds the picture of a box. Only the rounded corners are worked out pixel by pixel; the straight middle of
-- every row is the same pixel repeated (string.rep), so a 574 x 48 card is ~1000 pixels of work, not ~27000.
function L.makeBox(outline, w, h, r)
    local Sw, Sh = pow2(w), pow2(h)
    local PIX, sq = L.PIX, sqrt
    local rows, part = {}, L.boxRow
    local function cov(xc, yc)                                          -- coverage of one pixel (centre xc, yc)
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
    local edge = max(r, 1)                                               -- columns worked out on each side
    for py = 0, h - 1 do
        local yc = py + 0.5
        for i = 1, edge do part[i] = cov(i - 0.5, yc) end
        local left = table.concat(part, "", 1, edge)
        for i = 1, edge do part[i] = cov(w - edge + i - 0.5, yc) end
        local right = table.concat(part, "", 1, edge)
        local mid = string.rep(cov(w / 2, yc), w - 2 * edge)             -- the straight middle: one pixel repeated
        rows[#rows + 1] = left .. mid .. right .. string.rep(L.T0, Sw - w)
    end
    local pad = string.rep(L.T0, Sw)
    for _ = h, Sh - 1 do rows[#rows + 1] = pad end
    local ok, id = pcall(draw.CreateTextureRGBA, table.concat(rows), Sw, Sh)
    if not ok or not id then return false end
    return { id = id, U = w / Sw, V = h / Sh }
end

-- the picture for this box, or nil (then it is drawn the old way)
function L.boxGet(outline, w, h, r)
    if w > 1024 or h > 256 or w * h > 40000 or r > 63 then return nil end
    local key = ((w * 512 + h) * 64 + r) * 2 + (outline and 1 or 0)
    local e = L.boxTex[key]
    if e ~= nil then return e or nil end
    local n = (L.boxCount[key] or 0) + 1
    L.boxCount[key] = n
    -- only sizes really on screen (seen in 30+ frames within 5 s: pulsing / changing sizes never get there),
    -- at most 4 new pictures a second, and when 600 exist no more are made (they used to be thrown away and
    -- rebuilt, which made ~17 MB of garbage a second = stutters)
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

-- called once per frame: one new picture allowed, and the size counters are forgotten now and then
function L.boxFrame()
    L.boxBudget = 1
    if now() - L.boxCountAt > 5 then L.boxCount, L.boxCountAt = {}, now() end
end

local function drawBox(e, x, y, w, h)
    local q = L.boxQuad
    q[1][1], q[1][2], q[1][3], q[1][4] = x, y, 0, 0
    q[2][1], q[2][2], q[2][3], q[2][4] = x + w, y, e.U, 0
    q[3][1], q[3][2], q[3][3], q[3][4] = x + w, y + h, e.U, e.V
    q[4][1], q[4][2], q[4][3], q[4][4] = x, y + h, 0, e.V
    draw.TexturedPolygon(e.id, q, false)
end

-- filled rounded rectangle
local function roundRect(x, y, w, h, r, c, a)
    x, y, w, h = round(x), round(y), round(w), round(h)
    if w <= 0 or h <= 0 or hidden(a) then return end
    r = min(round(r), floor(h / 2), floor(w / 2))
    color(c, a)
    if r < 1 then draw.FilledRect(x, y, x + w, y + h); return end
    local e = L.boxGet(false, w, h, r)
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
    if e then drawBox(e, x, y, w, h); return end
    draw.FilledRect(x + r, y, x + w - r, y + 1)
    draw.FilledRect(x + r, y + h - 1, x + w - r, y + h)
    draw.FilledRect(x, y + r, x + 1, y + h - r)
    draw.FilledRect(x + w - 1, y + r, x + w, y + h - r)
    if r < 1 then return end
    corners(r, true, x, y, w, h)
end

-- filled circle: one smooth picture
local function disc(cx, cy, r, c, a)
    r = round(r)
    if r <= 0 or hidden(a) then return end
    color(c, a)
    local t, tr = circleTex(r)
    local half = t.S / 2 * r / tr                     -- (= S/2 when the picture is used at its real size)
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

-- filled polygon through a tiny white texture (points: {x1, y1, x2, y2, ...}, convex shapes)
local WHITE = draw.CreateTextureRGBA(string.rep(string.char(255), 16), 2, 2)
local function poly(pts, c, a)
    if hidden(a) then return end
    color(c, a)
    local v = {}
    for i = 1, #pts, 2 do v[#v + 1] = { pts[i], pts[i + 1], 0.5, 0.5 } end
    draw.TexturedPolygon(WHITE, v, true)
end

-- edge fades (vignette): side = "top" | "bottom" | "left" | "right"
local function edgeFade(side, size, c, a)
    local sw, sh = draw.GetScreenSize()
    size = round(size)
    a = clamp(round(a * ALPHA), 0, 255)
    if a <= 0 or size <= 0 then return end
    draw.Color(clamp(round(c[1]), 0, 255), clamp(round(c[2]), 0, 255), clamp(round(c[3]), 0, 255), 255)
    if side == "top" then draw.FilledRectFade(0, 0, sw, size, a, 0, false)
    elseif side == "bottom" then draw.FilledRectFade(0, sh - size, sw, sh, 0, a, false)
    elseif side == "left" then draw.FilledRectFade(0, 0, size, sh, a, 0, true)
    else draw.FilledRectFade(sw - size, 0, sw, sh, 0, a, true) end
end

-- Text is the most frequent thing drawn (hundreds of times a frame). The size of every string is measured
-- once and remembered, and the font is only switched when it is a different one (both are game calls).
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
    if L.tszN > 4000 then L.tsz, L.tszN = {}, 0; byF = {}; L.tsz[font] = byF end   -- (clock / fps texts keep changing)
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

local function textC(font, s, cx, y, h, c, a)   -- horizontally centred too
    text(font, s, cx - textW(font, s) / 2, y, h, c, a)
end

-- shorten a string until it fits
-- cache: fitCache[font][width][text] (nested tables, so looking it up makes no new strings)
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
    if fitCount > 500 then fitCache, fitCount = {}, 0 end            -- (keep the memory small)
    byW[s] = r
    return r
end

-- smooth animation: anim(id, target) moves a bit toward target every frame
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

-- logo: every letter its own colour from the flowing gradient (SPLogoBody) + soft shadow
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

-- anything on screen can be dragged while the menu is open; the spot is saved in settings.pos
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
-- 5. Player info: Steam name + Steam avatar
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
-- (the Steam profile picture could not be loaded reliably from lmaobox, so it was removed)
local function drawAvatar(x, y, s, r)
    roundRect(x, y, s, s, r, T.card)
    -- a soft accent glow inside the tile, then the letter in the logo gradient
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
L.NT_STYLES = { "Destiny", "Radiance", "Mercury", "Silentium" }
L.NT_POS = { "Top-Right", "Bottom-Right", "Top-Center", "Bottom-Center", "Top-Left" }
local notes = {}

local function notify(icon, title, body, col)
    if not settings.ntOn then return end
    table.insert(notes, 1, { icon = icon, title = title, body = body or "", col = col or accent(), t0 = now() })
    if #notes > 6 then table.remove(notes) end
end

-- 6b. sounds (TF2's own hit/kill sounds) -----------------------------------
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
        if d.idx == idx and now() - d.last < 0.45 then      -- quick hits on the same player add up
            d.amt, d.last, d.t0, d.crit = d.amt + amount, now(), now(), d.crit or crit
            return
        end
    end
    dmgs[#dmgs + 1] = { idx = idx, ent = victim, amt = amount, crit = crit, t0 = now(), last = now(), ox = math.random(-18, 18) }
end

-- 6d. vignette (screen edge effects on hits and kills) ----------------------
-- (the effects themselves are in 8i; the styles are the ones of the M0MENT4M freeze effect)
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
-- "%c" = the class (Heavy, Spy, ...), "%w" = the weapon (Scattergun, Minigun, ...)
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
-- say a line of this kind; %c / %w are filled in (lines that need a missing word fall back to a plain one)
local function compSay(kind, class, weapon)
    if not settings.compOn or not settings.compBubbles then return end
    local lines = (settings.compChar == 1 and L.PLINES) or L.LINES         -- Paimon has her own lines
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
-- Settings page: https://raw.githubusercontent.com/eintoaster/Destiny-Lua-/refs/heads/main/destiny.lua
-- Flow: the menu loads and is usable right away; a few seconds later (so nothing on load is held up)
-- this quietly asks GitHub for the current file. If it's byte-for-byte the same as what's on disk, it
-- says "up to date". If it's different, it overwrites this very file on disk and tells you to restart
-- destiny.lua so lmaobox picks up the new version (a running script can't reload itself).
local UPDATE_URL = "https://raw.githubusercontent.com/eintoaster/Destiny-Lua-/refs/heads/main/destiny.lua"
local UPDATE_DELAY = 3                                  -- seconds after load before the check fires

local updater = { checked = false, running = false, startAt = now() + UPDATE_DELAY, path = nil }

-- the full ABSOLUTE path to this very file. debug.getinfo / GetScriptName can give just "destiny.lua"
-- (relative), and writing that goes into the TF2 folder instead of %LOCALAPPDATA%\lua - so every candidate
-- must be absolute AND must really exist on disk, otherwise the next one is tried.
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
        updater.path = la .. "\\lua\\" .. base      -- last resort: the standard lmaobox folder
    end
end)

-- lmaobox's ASYNC downloads (http.GetAsync) fail above ~20 KB with "WinINet Error Code: 6 /
-- Network read failed" (the same issue the Paimon installer works around - see section 8d+).
-- destiny.lua is far bigger than that, so the update check uses the BLOCKING call (http.Get)
-- instead: it waits for the answer right there in the frame it's called from (a short one-time
-- pause, same as a Paimon file), which is what actually works for files this size.
local function updaterCheck()
    if updater.running then return end
    if not http then notify("✖", "Can't check for updates", "lmaobox blocks downloads (http)", RED); return end
    if not io or not updater.path or updater.path == "" then
        notify("✖", "Can't check for updates", "the script's own file path is unknown", RED)
        return
    end
    updater.running = true
    -- raw.githubusercontent.com caches a file for a few minutes after a push, so a check right after
    -- editing on GitHub can still get served the stale cached copy. A changing query string on the end
    -- is a different URL to the CDN, which skips that cache and goes back to GitHub for a fresh copy.
    local bust = UPDATE_URL .. "?t=" .. tostring(floor(now() * 1000))
    local ok, remote = pcall(http.Get, bust)
    updater.running = false
    if not ok then
        notify("✖", "Can't check for updates", tostring(remote), RED)
        return
    end
    if type(remote) ~= "string" or remote == "" or remote:sub(1, 5) == "ERROR" then
        notify("✖", "Update check failed", tostring(remote), RED)
        return
    end
    local okf, f = pcall(io.open, updater.path, "rb")
    local current = (okf and f) and f:read("*a") or nil
    if okf and f then f:close() end
    if current and current == remote then
        notify("✔", "Destiny is up to date", tostring(updater.path), accent())
        return
    end
    -- lmaobox refuses to create/overwrite a file named *.lua directly, but writing other extensions and
    -- renaming works. So: write the download to destiny.lua.tmp, check it, move the old file aside,
    -- rename the .tmp into place - and put the old file back if any step fails.
    local path = updater.path
    local tmp, old = path .. ".tmp", path .. ".old"
    local function fail(why)
        print("[destiny] update save failed for " .. tostring(path) .. " -> " .. tostring(why))
        notify("✖", "Update found but couldn't be saved", tostring(why):sub(1, 90), RED)
    end
    local ok, wf, werr = pcall(io.open, tmp, "wb")
    if not ok or not wf then return fail("can't create .tmp: " .. tostring(ok and werr or wf)) end
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
        pcall(os.rename, old, path)                 -- put the old script back
        pcall(os.remove, tmp)
        return fail("can't rename .tmp into place: " .. tostring(o2 and e2 or r2))
    end
    pcall(os.remove, old)
    updater.path = path
    notify("⚡", "Destiny was updated", "Please restart destiny.lua to load it", GOLD)
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

-- the class of a player (from the m_PlayerClass netvar)
L.CLASSES = { "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer" }
function L.classOf(uid)
    local ent = entities.GetByUserID(uid)
    if not ent then return nil end
    local ok, c = pcall(ent.GetPropInt, ent, "m_PlayerClass", "m_iClass")
    return ok and L.CLASSES[c] or nil
end

-- the "weapon" text of a kill event made readable ("tf_projectile_rocket" -> "Rocket Launcher")
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

local function onKill(victimName, class, weapon, custom)
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
    L.paimon.onKill()                                                -- a random Paimon voice line
end

local function onDeath(killerName, class, weapon, suicide)
    local lost = me.streak
    me.streak, me.tier = 0, 0
    if settings.ntDeaths then
        local body = joinParts((not suicide) and class or nil, (not suicide) and weapon or nil,
                               lost >= 3 and ("streak of " .. lost .. " ended") or nil)
        notify("✝", suicide and "You died" or ("Killed by " .. killerName), body, RED)
    end
    if class and not suicide and math.random() < 0.6 then compSay("deathBy", class) else compSay("death") end
end

local function onGameEvent(e)
    local name = e:GetName()
    if name ~= "player_death" and name ~= "player_hurt" then return end
    local mine = myUserID()
    if not mine then return end
    local victim, attacker = e:GetInt("userid"), e:GetInt("attacker")

    if name == "player_death" then
        local weapon = L.weaponName(e:GetString("weapon"))
        if attacker == mine and victim ~= mine then
            onKill(nameOf(victim), L.classOf(victim), weapon, e:GetInt("customkill"))
        elseif victim == mine then
            onDeath(nameOf(attacker), L.classOf(attacker), weapon, attacker == mine or attacker == 0)
        elseif e:GetInt("assister") == mine and settings.ntAssists then
            notify("✚", "Assist on " .. nameOf(victim), joinParts(L.classOf(victim), weapon), SKY)
        end
    elseif attacker == mine and victim ~= mine then
        local ent = entities.GetByUserID(victim)
        local crit = e:GetInt("crit") == 1
        if ent then addDamage(ent, e:GetInt("damageamount"), crit) end
        L.paimon.hitLog(nameOf(victim), L.classOf(victim), e:GetInt("damageamount"), e:GetInt("health"), crit)
        vigTrigger(false)
        playFrom(L.HIT_SOUNDS, settings.hitSound)
    end
end

---------------------------------------------------------------------------
-- 8. Overlays
---------------------------------------------------------------------------
-- 8a. watermark -------------------------------------------------------------
L.WM_STYLES = { "Classic", "Radiance", "Mercury", "Silentium" }
local fps, fpsAt = 0, 0

local function mapName()
    local map = engine.GetMapName()
    if not map or map == "" then return nil end
    return map:match("([^/\\]+)%.bsp$") or map
end

-- the pieces the watermark shows: { icon, value, label }
local function wmParts()
    local p = { { "☺", steamName() } }
    if settings.wmFps then p[#p + 1] = { "↗", tostring(fps), "Fps" } end
    local m = settings.wmMap and mapName()
    if m then p[#p + 1] = { "◉", m } end
    if settings.wmTime and os and os.date then p[#p + 1] = { "◷", os.date("%H:%M:%S") } end
    return p
end

-- Radiance chip: icon + texts, returns width
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

-- the watermark's pieces are rebuilt 4 times a second (enough for the clock), not every frame
local wmCache = { at = -99 }

local function drawWatermark()
    if now() - fpsAt > 0.5 then fps, fpsAt = floor(1 / frameDt()), now() end
    if now() - wmCache.at > 0.25 then
        wmCache.at, wmCache.parts, wmCache.chips, wmCache.items, wmCache.text = now(), wmParts(), nil, nil, nil
    end
    local parts = wmCache.parts
    local sw = draw.GetScreenSize()
    local style = settings.wmStyle

    if style == 2 then                                               -- Radiance chips
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

    elseif style == 3 then                                           -- Mercury: one glowing box
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

    elseif style == 4 then                                           -- Silentium: name, then items split by fine lines
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

    else                                                             -- Classic bar
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
-- Names are option names from the lmaobox menu (gui.GetValue). Unknown names are tested once and then skipped.
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

-- reads one lmaobox option; names lmaobox doesn't know are asked once and then never again (asking caused stutters)
L.featKnown = {}
function L.guiValue(name)
    if not name or L.featKnown[name] == false then return nil end
    local ok, v = pcall(gui.GetValue, name)
    if ok and v ~= nil then L.featKnown[name] = true; return v end
    L.featKnown[name] = false
    return nil
end

-- asks lmaobox about ONE option per frame, in turn (all of them at once every half second made a small
-- hitch twice a second). A full round still takes only ~13 frames.
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
    -- status popup like the macro's ON/OFF toasts (not for the very first look at an option)
    if L.featSeen[f[1]] and settings.ntFeatures and before ~= nil and on ~= nil and before ~= on then
        notify(on and "✔" or "✖", f[1], on and "ON" or "OFF", on and accent() or RED)
    end
    L.featSeen[f[1]] = true
end

-- 8c. input monitor -----------------------------------------------------------
L.IM_STYLES = { "Destiny", "Radiance", "Mercury", "Silentium" }

local function drawInputMonitor()
    local sw, sh = draw.GetScreenSize()
    local style = settings.imStyle
    local K, G = 34, 4
    local head = (style == 3 or style == 4) and 30 or 0                -- Mercury and Silentium have a title on top
    local w = K * 3 + G * 2 + 24
    local h = 12 + head + (K + G) * 4 + 12
    local x, y = draggable("im", 14, sh / 2 - h / 2, w, h)
    local acc = accent()
    local bg = settings.imBg
    local t = now()

    -- the panel behind the keys (can be switched off)
    if style == 2 then                                                -- Radiance: navy glass
        if bg then
            roundRect(x, y + 3, w, h, 12, C_BLACK, 60)
            roundRect(x, y, w, h, 12, RD.body, 200)
            roundRectLine(x, y, w, h, 12, RD.border, 170)
        end
    elseif style == 3 then                                            -- Mercury: the glowing box with a title
        if bg then mercuryBox(x, y, w, h, 10) end
        local tw = textW(F.rd, "inputs")
        text(F.icon, "✦", x + (w - tw - 18) / 2, y + 4, 22, MC.val)
        text(F.rd, "inputs", x + (w - tw - 18) / 2 + 18, y + 4, 22, MC.text)
        rect(x + 8, y + 29, w - 16, 1, MC.border, 150)
    elseif style == 4 then                                            -- Silentium: dark glass, handwritten title
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
    else                                                              -- Destiny: the menu's card
        if bg then
            roundRect(x, y + 3, w, h, 12, C_BLACK, 70)
            roundRect(x, y, w, h, 12, T.card, 230)
            roundRectLine(x, y, w, h, 12, T.border)
        end
    end

    -- one key in the chosen look; tt = how far it is pressed (0..1)
    local function key(id, label, kx, ky, kw, kh, button)
        local down = input.IsButtonDown(button)
        local was = L.imDown[id]
        if down and not was then L.imPress[id] = t end
        L.imDown[id] = down
        local tt = anim("im" .. id, down and 1 or 0, 22)
        local fl = t - (L.imPress[id] or -9)                           -- time since it was pressed

        if style == 2 then                                            -- Radiance chip: pops, a violet ring spreads out
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
        elseif style == 3 then                                        -- Mercury: thin outline, glows blue when pressed
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
        elseif style == 4 then                                        -- Silentium: dark key, accent fades in from the left
            roundRect(kx, ky, kw, kh, 6, L.IMSL_KEY, 235)
            if tt > 0.02 then
                draw.Color(round(acc[1]), round(acc[2]), round(acc[3]), 255)
                draw.FilledRectFade(round(kx + 1), round(ky + 1), round(kx + kw - 1), round(ky + kh - 1),
                    clamp(round(110 * tt * ALPHA), 0, 255), 0, true)
                rect(kx, ky + 5, 2, kh - 10, acc, 255 * tt)
            end
            roundRectLine(kx, ky, kw, kh, 6, mix(SL.line, acc, tt * 0.7))
            textC(F.tiny, label, kx + kw / 2, ky, kh, mix(SL.dim, C_WHITE, tt))
        else                                                          -- Destiny: filled key in the accent colour
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
    key("sp", "", x0, r4 + K + G, K * 3 + G * 2, 9, KEY_SPACE)     -- the space bar (thin)
end
L.imDown, L.imPress = {}, {}
L.IMRD_ON, L.IMMC_OFF, L.IMSL_KEY = { 52, 46, 120 }, { 120, 126, 170 }, { 26, 26, 31 }

-- 8d. waifu companions --------------------------------------------------------
-- Elfaria is drawn from shapes every frame, ported from CompDrawElf in
-- M0MENT4M 2.2: they float, blink, follow the mouse with their eyes (menu open), talk, and sway.
-- All coordinates below are the macro's own (a 240 x 392 box); CW turns them into screen pixels.
L.COMPANIONS = { { "Paimon" }, { "Elfaria" } }
local CW = { s = 1, x = 0, y = 0, petUntil = -99, cullY = 1e9 }   -- (cullY: nothing below this is drawn)

-- filled shape in companion coordinates: cpoly(colour, alpha, x1, y1, x2, y2, ...)
-- (vertex lists are reused per vertex count, so this makes no new tables)
-- (up to 8 points as plain parameters: reading "..." with select() for every point was ~3x slower)
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
    color(c, a)
    draw.TexturedPolygon(WHITE, arr, false)
end

-- filled ellipse: the 32px circle picture stretched (the circle fills the middle half of the picture)
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

-- thick line (round ends when it is wide)
local function tline(x1, y1, x2, y2, w, c, a)
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    local nx, ny = -dy / len * w / 2, dx / len * w / 2
    cpoly(c, a, x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny)
    -- round ends only where you can see them (7+ pixels wide on screen)
    if w * CW.s >= 7 then oval(x1, y1, w / 2, w / 2, c, a); oval(x2, y2, w / 2, w / 2, c, a) end
end

local function crr(x, y, w, h, r, c, a)
    if y > CW.cullY then return end
    local s = CW.s
    roundRect(CW.x + x * s, CW.y + y * s, w * s, h * s, r * s, c, a)
end

-- a colour worked out on the fly, written into one of the reused mix tables
local function rgb(r, g, b)
    local o = mix(C_BLACK, C_BLACK, 0)
    o[1], o[2], o[3] = r, g, b
    return o
end

-- where the pupils look: toward the mouse while the menu is open
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
    -- Elfaria
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

    -- very long wavy hair behind (pale on top, deep blue at the ends)
    oval(120, y0 + 104, 66, 66, elfHair(0.1, 0.84))
    for side = -1, 1, 2 do
        for k = 1, 3 do
            local s = (k == 1) and 3 or (k == 2 and 1 or 0)
            local topx, topy = 120 + side * (40 + s * 9), y0 + 90
            local tipx, tipy = 120 + side * (58 + s * 17) + sway * (9 + s * 5) * side, y0 + 214 + s * 13
            local segs = 15                                        -- (15 pieces per lock, a bit bigger than before)
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
    -- skirt with a brown and gold hem, centre panel and side sash
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
    -- arms with gold bands, the right one waves a little
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

    -- messy hair on top: tufts, spiky bangs (cap + one triangle per spike), face-framing locks, an ahoge
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

    if settings.compChar ~= 2 then L.paimon.draw(sw, sh); return end   -- Paimon is the default waifu

    -- her visible box is x 0..262, y 50..310 in her own coordinates
    local bw, bh = 262 * s, 260 * s
    -- click on her while the menu is open: she gets petted (happy eyes, blush) and says something
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
-- 8d+. Paimon: the animated sprite waifu (53 frames, Genshin font, 57 voice lines)
--      Installed with one button from https://github.com/eintoaster/paimon :
--        Team Fortress 2\destiny_files\paimon\frames\frame_N.png + Genshin_Impact.ttf
--        Team Fortress 2\tf\sound\destiny_paimon\N.wav   (TF2 only plays sounds from its sound folder)
---------------------------------------------------------------------------
local P = { tex = {}, loaded = 0, frame = 0, frameAt = 0, state = "idle", done = 0, failed = 0, idx = 0,
            current = "", voiceUntil = -99, lastVoice = 0, voiceLen = {}, installedCache = nil }
L.paimon = P
P.REPO = "https://raw.githubusercontent.com/eintoaster/paimon/main/"
P.W, P.H = 397, 465
P.TOTAL = 1 + 53 + 57

-- Paimon's own lines (her cheerful third-person way of talking; %c = class, %w = weapon)
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

-- The 111 files to download: { file in the repo, path (relative = inside the TF2 folder), kind }.
-- lmaobox's http library can't carry binary files (the data stops at the first zero byte), so the repo also
-- holds base64 text copies (paimon_frames_b64/, paimon_voice_b64/, Genshin_Impact.b64). Those are downloaded
-- and turned back into the real files here, a little every frame so nothing freezes.
-- Small files first, the 15 MB font last. Every request is started from the frame loop (never from inside
-- a download's callback, which made lmaobox answer "ERROR READ Network read"), and a failed file is tried
-- again from a second server.
P.MIRRORS = { "https://cdn.jsdelivr.net/gh/eintoaster/paimon@main/", "https://raw.githubusercontent.com/eintoaster/paimon/main/" }
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

-- installed = the last frame, the font and the last voice line are there (checked once, then remembered)
function P.installed()
    if P.installedCache == nil then
        P.installedCache = fileExists("destiny_files/paimon/frames/frame_52.png")
            and fileExists("destiny_files/paimon/Genshin_Impact.ttf") and fileExists("tf/sound/destiny_paimon/57.wav")
    end
    return P.installedCache
end

-- base64 -> bytes for the text between positions i and j (i - 1 and j a multiple of 4)
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
        local vc, vd = D[c], D[d]                                         -- ("=" padding gives nil)
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

-- "Test downloads": asks lmaobox's downloader for a few sizes from both servers and shows what came back
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

-- the callback only hands the answer over; everything else happens in the frame loop
function P.request(f)
    P.waiting, P.result = true, nil
    local url = P.MIRRORS[P.try] .. f[1]
    -- (waits for the answer: lmaobox's background downloads fail above ~20 KB with "WinINet Error Code: 6",
    --  the waiting one works. The game pauses for a moment per file, only while installing.)
    local ok, data = pcall(http.Get, url)
    P.result = { f = f, data = ok and data or nil }
end

function P.finish()
    P.state = (P.failed == 0) and "done" or "failed"
    P.installedCache = nil
    P.unloadTextures()
    P.voiceLen, P.fontId = {}, nil
    if P.failed == 0 then notify("✔", "Paimon installed", P.done .. " files downloaded", accent())
    else
        notify("✖", "Paimon: " .. P.failed .. " files failed", tostring(P.lastFail) .. ": " .. tostring(P.why), RED)
        print("[destiny] Paimon install: " .. P.failed .. " failed, last " .. tostring(P.lastFail) .. " (" .. tostring(P.why) .. ")")
    end
end

-- checks an answer: returns the cleaned text, or nil + the reason
local SIG = { png = function(h) return h:sub(2, 4) == "PNG" end, wav = function(h) return h:sub(1, 4) == "RIFF" end,
              ttf = function(h) return h:sub(1, 4) == "\0\1\0\0" or h:sub(1, 4) == "OTTO" or h:sub(1, 4) == "true" end }
function P.check(f, data)
    if type(data) ~= "string" or #data < 16 then return nil, "got " .. (type(data) == "string" and #data or 0) .. " bytes" end
    if data:sub(1, 5) == "ERROR" then return nil, data:sub(1, 40) end
    if #data % 4 ~= 0 or data:find("[^%w%+/=]") then data = data:gsub("[^%w%+/=]", "") end   -- (stray line breaks)
    if not SIG[f[3]](P.b64(data, 1, 16)) then return nil, "not a " .. f[3] .. " (" .. data:sub(1, 24) .. ")" end
    return data
end

-- runs every frame while installing: start the next download, take an answer, decode about 3 ms worth
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
            if P.try < #P.MIRRORS then P.try = P.try + 1; P.request(f); return end   -- once more from the other server
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
            local j = min(n, job.pos + 49151)                           -- 48 KB of text at a time (multiple of 4)
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

-- textures: loaded a few per frame from the absolute path (draw.CreateTexture doesn't know the TF2 folder)
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
        P.tex[P.loaded] = ok and id or false
        P.loaded = P.loaded + 1
        n = n + 1
    end
end

function P.unloadTextures()
    for i, id in pairs(P.tex) do if id then pcall(draw.DeleteTexture, id) end end
    P.tex, P.loaded = {}, 0
end

-- the Genshin font for her bubbles (the font file's own name is "Default_SC")
function P.font()
    if not settings.paiFont then return F.small end
    if P.fontId == nil then
        P.fontId = false
        if P.installed() then
            pcall(draw.AddFontResource, "destiny_files/paimon/Genshin_Impact.ttf")
            local ok, id = pcall(draw.CreateFont, "Default_SC", 17, 600, FONTFLAG_ANTIALIAS)
            if ok and id then P.fontId = id end
        end
    end
    return P.fontId or F.small
end

-- the Genshin-style speech bubble: cream pill, dark slate text, a little pointer down to her
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

-- Paimon on screen: 30 ms per frame like the old script, drag her while the menu is open, click to pet
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
        compSay("idle")                                                 -- poke her and she talks
    end
    local x, y = draggable("comp", sw - W - 20, sh - H - 20, W, H)
    local id = P.tex[P.frame] or P.tex[0]
    if id then
        color(C_WHITE)
        -- lmaobox puts each 397x465 frame into a 512x512 texture (top-left); the rest would show as the purple
        -- "missing texture" checker, so only the part with Paimon in it is drawn
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

-- a random voice line (never the same twice in a row, never on top of the one still playing)
function P.voiceLength(i)
    if not P.voiceLen[i] then
        local len = 2
        local ok, f = pcall(io.open, "tf/sound/destiny_paimon/" .. i .. ".wav", "rb")
        if ok and f then
            local size = f:seek("end")
            f:close()
            if size then len = size / (44100 * 4) end                  -- 16-bit stereo 44.1 kHz = 176400 bytes a second
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

-- every now and then she says something on her own (a random line, 50-150 % of the chosen time apart)
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

-- hit logs like the old paimon.lua: "You hit Heavy for 54 damage! He has 246 HP left!"
function P.hitLog(name, class, dmg, hp, crit)
    if not (settings.compOn and settings.compChar == 1 and settings.paiLogs and settings.compBubbles) then return end
    local who = class and (name .. " (" .. class .. ")") or name
    local s
    if hp and hp > 0 then
        s = string.format("%sYou hit %s for %d damage! %d HP left!", crit and "Crit! " or "", who, dmg, hp)
    else
        s = string.format("%sYou hit %s for %d damage!", crit and "Crit! " or "", who, dmg)
    end
    bubble.text, bubble.t0, bubble.dur = s, now(), settings.paiLogTime
end

-- 8e. notifications (the M0MENT4M toast looks) -----------------------------------
-- returns the width and height a notification needs in the chosen style
local function noteSize(n, style)
    if style == 2 then                                                -- Radiance: one chip
        local parts = { { n.title } }
        if n.body ~= "" then parts[2] = { n.body } end
        return chipW(n.icon, parts), 26
    elseif style == 3 then                                            -- Mercury: one pill
        return 44 + textW(F.rd, n.title) + (n.body ~= "" and (textW(F.rd, n.body) + 8) or 0), 28
    end
    return 316, 58
end

local function drawNote(n, x, y, w, h, style, idx)
    local col = n.col
    local gst = L.gradStops(settings.ntGrad)
    if gst and col ~= RED then col = sampleStops(gst, now() * 0.12 + idx * 0.1) end
    if style == 2 then                                                -- Radiance chip: icon, title and the rest in colour
        local parts = { { n.title, gst and col or RD.white } }
        if n.body ~= "" then parts[2] = { n.body, (n.col == RED) and RED or (gst and sampleStops(gst, now() * 0.12 + idx * 0.1 + 0.35) or RD.violet) } end
        chip(x, y, n.icon, parts, 26)
        L.styledBorder(settings.ntBorder == 2 and 1 or settings.ntBorder, settings.ntGrad, x, y, w, 26, 7)
    elseif style == 3 then                                            -- Mercury pill with a glow in the note's colour
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
    elseif style == 4 then                                            -- Silentium
        roundRect(x, y + 2, w, h, 6, C_BLACK, 70)
        roundRect(x, y, w, h, 6, SL.body, 240)
        roundRectLine(x, y, w, h, 6, SL.line)
        L.styledBorder(settings.ntBorder == 2 and 1 or settings.ntBorder, settings.ntGrad, x, y, w, h, 6)
        rect(x, y + 8, 2, h - 16, col)
        text(F.icon, n.icon, x + 14, y, h, col)
        rect(x + 36, y + 10, 1, h - 20, SL.line)
        text(F.bold, fit(F.bold, n.title, w - 58), x + 46, y + (n.body ~= "" and 7 or 0), n.body ~= "" and 22 or h, gst and col or SL.text)
        if n.body ~= "" then text(F.small, fit(F.small, n.body, w - 58), x + 46, y + 28, 20, SL.dim) end
    else                                                              -- Destiny (the M0MENT4M toast card)
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
        local inT = easeOutBack(age / 0.48)                           -- slides in with a little overshoot
        local out = (age > life) and min(1, (age - life) / 0.4) ^ 2 or 0
        n.key = n.key or ("nslot" .. tostring(n))                     -- (made once, not every frame)
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
        elseif style == 4 then rect(x + 10, y + h - 3, (w - 20) * left, 2, n.col, 160) end
        ALPHA = 1
        i = i + 1
    end
end

-- 8f. damage numbers ----------------------------------------------------------
local function drawDamage()
    local life = 1.1
    for k = #dmgs, 1, -1 do if now() - dmgs[k].t0 > life then table.remove(dmgs, k) end end
    for _, d in ipairs(dmgs) do
        local ok, pos = pcall(L.originOf, d.ent)                         -- (one fixed function, not a new one per number per frame)
        if ok and pos then pos.z = pos.z + 82 end
        local sx, sy
        if ok and pos then
            local a, b = client.WorldToScreen(pos)          -- (a table {x, y}, or two numbers)
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
    local stops = L.kaStops()                          -- (Kill announcer > Colours)
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
        -- Classic: wings, more and longer feathers the higher the streak
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
        -- emblem: a diamond in the gradient with the tier in it
        local r = 30 * s
        poly({ cx, cy - r - 4, cx + r + 4, cy, cx, cy + r + 4, cx - r - 4, cy }, C_WHITE, 230)
        poly({ cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy }, c1, 255)
        poly({ cx, cy - r * 0.62, cx + r * 0.62, cy, cx, cy + r * 0.62, cx - r * 0.62, cy }, c2, 255)
    else
        -- Neon: glowing rings that pulse
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
--     (ported from the M0MENT4M Fun tab, freeze effect and kill effects)
---------------------------------------------------------------------------
L.RED_FX = { 255, 45, 85 }
L.BLOOD = { 138, 0, 14 }

-- the effect colour at position p (0..1 along the screen edge), for hits or kills
function L.fxColor(kill, p)
    local i = settings.vigColor
    local t = now() * settings.vigSpeed * 0.06
    if i >= 5 then return sampleStops(logoStops(i - 4), (p or 0) + t) end   -- the logo gradients, moving
    local base
    if i == 2 then base = L.RED_FX
    elseif i == 3 then base = C_WHITE
    elseif i == 4 then base = L.hex(kill and settings.colKill or settings.colHit) or accent()
    else base = accent() end
    if settings.vigAnim then                                          -- "Animate the colours": shimmers lighter
        return mix(base, C_WHITE, 0.55 * (0.5 + 0.5 * sin(((p or 0) + t) * 6.283)))
    end
    return base
end

-- screen-space drawing with the waifu shape helpers (thick lines, filled shapes, ovals)
function L.screenSpace() CW.s, CW.x, CW.y, CW.cullY = 1, 0, 0, 1e9 end

-- a wide ring: at most 3 circle outlines, with as many pieces as the size needs
-- (it was up to 6 outlines of 72 pieces each, ~4000 lines a frame for a shockwave)
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
    end
    local sw, sh = draw.GetScreenSize()
    color(c, a)
    for y = 0, sh, 256 do draw.TexturedRect(L.scanTex, 0, y, sw, y + 256) end
end

-- small random numbers that stay the same for one effect (so shapes don't jump around every frame)
function L.rnd(seed, i)
    local x = sin(seed * 12.9898 + i * 78.233) * 43758.5453
    return x - floor(x)
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

    if style == 2 then                                                 -- Pulse
        L.edges(size, a * (0.5 + 0.5 * abs(sin(el * 14))), kill)
    elseif style == 3 then                                             -- Scanlines
        L.edges(size, a, kill)
        local c = L.fxColor(kill, 0)
        L.scanlines(c, 34 * env * v.power)                         -- (one picture instead of ~270 rectangles)
    elseif style == 4 then                                             -- Glitch bars
        L.edges(size, a, kill)
        local frame = floor(el * 22)
        for i = 1, 8 do
            local bh = 3 + L.rnd(v.seed + frame, i) * 14
            local by = L.rnd(v.seed + frame, i + 20) * (sh - bh)
            local bw = sw * (0.04 + 0.2 * L.rnd(v.seed + frame, i + 40))
            local right = L.rnd(v.seed + frame, i + 60) > 0.5
            rect(right and (sw - bw) or 0, by, bw, bh, (i % 2 == 0) and L.CYAN or L.MAGENTA, (70 + 80 * L.rnd(v.seed, i)) * env)
        end
    elseif style == 5 then                                             -- Frost speckles near the edges
        L.edges(size, a * 0.8, kill)
        for i = 1, 120 do
            local e = floor(L.rnd(v.seed, i) * 4)
            local d = L.rnd(v.seed, i + 300) * size * 0.8
            local px = (e < 2) and L.rnd(v.seed, i + 600) * sw or (e == 2 and d or sw - d)
            local py = (e == 0) and d or (e == 1 and sh - d or L.rnd(v.seed, i + 900) * sh)
            local s = 1 + floor(L.rnd(v.seed, i + 1200) * 3)
            rect(px, py, s, s, L.FROST, (80 + 90 * L.rnd(v.seed, i + 1500)) * env)
        end
    elseif style == 6 then                                             -- Hard border in segments of the gradient
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
    elseif style == 7 then                                             -- Shockwave rings from the middle
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
    elseif style == 8 then                                             -- Chromatic split: red / cyan shifted edges
        local off = 10 * env
        edgeFade("left", size, L.RED_FX, a)
        edgeFade("left", size * 0.55 + off, L.CYAN, a * 0.5)
        edgeFade("right", size, L.CYAN, a)
        edgeFade("right", size * 0.55 + off, L.RED_FX, a * 0.5)
        edgeFade("top", size * 0.8, L.MAGENTA, a * 0.75)
        edgeFade("bottom", size * 0.8, L.CYAN, a * 0.75)
    elseif style == 9 then                                             -- Radar sweep from the middle
        L.edges(size * 0.8, a * 0.7, kill)
        local cx, cy = sw / 2, sh / 2
        local R = sqrt(sw * sw + sh * sh) / 2
        local ang = el * 5
        for k = 0, 14 do
            local aa = ang - k * 0.035
            line(cx, cy, cx + cos(aa) * R, cy + sin(aa) * R, L.fxColor(kill, k / 14), (200 - k * 13) * env * v.power)
        end
    elseif style == 10 then                                            -- Heartbeat: lub-dub
        local ph = el % 0.85
        local beat = max(0, 1 - ph / 0.16) + 0.7 * max(0, 1 - abs(ph - 0.26) / 0.12)
        L.edges(size * (0.8 + 0.4 * beat), a * (0.35 + 0.65 * beat), kill)
    elseif style == 11 then                                            -- Lightning bolts along the edges
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
    elseif style == 12 then                                            -- Closing in
        local k = sin(u * pi)
        L.edges(size * (0.3 + 1.1 * easeOut(u * 1.4)), 235 * settings.vigInt / 100 * v.power * k, kill)
    elseif style == 13 then                                            -- Embers rising from the bottom
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
    else                                                               -- Glow
        L.edges(size, a, kill)
    end
end
L.CYAN, L.MAGENTA, L.FROST, L.EMBER = { 0, 255, 255 }, { 255, 0, 170 }, { 235, 245, 255 }, { 255, 190, 90 }

-- extra effects (KFRenderInner) ------------------------------------------------
L.kf = nil

function L.kfStart(kill)
    local style = settings.fxExtra
    if style <= 1 then return end
    if style == 2 then style = 3 + math.random(0, 6) end              -- random: a new one every time
    local sw, sh = draw.GetScreenSize()
    local k = min(sw, sh) / 1080
    local st = { style = style, t0 = now(), kill = kill, sw = sw, sh = sh, k = k,
                 dur = kill and max(0.38, settings.vigStay / 1000 * 0.9) or 0.42, seed = math.random() * 1000 }
    if style == 4 then                                                 -- blood: blobs near the edges and corners
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
    elseif style == 5 then                                             -- slash: long streaks through the middle
        st.slashes = {}
        for i = 1, 3 do
            local ang = ((math.random() * 76 - 38) + ((i % 2 == 1) and 0 or 180)) * 0.01745
            local px, py, Ln = sw / 2 + (math.random() * 0.36 - 0.18) * sw, sh / 2 + (math.random() * 0.28 - 0.14) * sh, 1.5 * sw
            st.slashes[i] = { sx = px - cos(ang) * Ln / 2, sy = py - sin(ang) * Ln / 2, dx = cos(ang), dy = sin(ang), L = Ln }
        end
    elseif style == 6 then                                             -- shatter: cracks with branches
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
    c1 = { c1[1], c1[2], c1[3] }                                       -- (keep them: the mix tables get reused)
    local keep = ALPHA
    ALPHA = keep * settings.vigInt / 100 * 1.15
    local s = st.style

    if s == 3 then                                                     -- hit marker: an X pops out of the crosshair
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
    elseif s == 4 then                                                 -- blood splatter with drips
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
    elseif s == 5 then                                                 -- slash: bright streaks cut across
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
    elseif s == 6 then                                                 -- shatter: cracks run out, a white flash
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
                L.seg(x1, y1, x2, y2, 7 * k, c1, 80 * fade)          -- (no round ends: they doubled the work)
                L.seg(x1, y1, x2, y2, 2 * k, C_WHITE, 230 * fade)
            end
        end
    elseif s == 7 then                                                 -- anime speed lines that flicker
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
    elseif s == 8 then                                                 -- shockwave: three rings rush out
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
    elseif s == 9 then                                                 -- neon frame: border snaps in, corner brackets
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
        draw.Color(round(c1[1]), round(c1[2]), round(c1[3]), 255)
        draw.FilledRectFade(0, round(sy - 40 * k), W, round(sy), 0, clamp(round(90 * fade * ALPHA), 0, 255), false)
    end
    ALPHA = keep
end

-- screen shake: only the picture moves (RenderView), never where you aim
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
        if kill or not (v.kill and now() - v.t0 < v.len * 0.6) then       -- (a hit doesn't cut a kill effect short)
            v.t0, v.kill, v.seed = now(), kill, math.random() * 1000
            v.len = kill and max(0.2, settings.vigStay / 1000) or max(0.18, settings.vigStay / 1000 * 0.4)
            v.power = kill and 1 or 0.55
        end
    end
    if (kill and settings.fxOnKill) or (not kill and settings.fxOnHit) then L.kfStart(kill) end
    L.shakeStart(kill)
end

---------------------------------------------------------------------------
-- 8j. lmaobox HUD (the M0MENT4M macro HUD looks: Destiny, Skeet, Neverlose, Radiance, Mercury, Gamesense, Silentium)
---------------------------------------------------------------------------
L.HUD_STYLES = { "Destiny", "Skeet", "Neverlose", "Radiance", "Mercury", "Gamesense", "Silentium" }
L.BORDERS = { "Off", "Plain", "Accent", "Animated gradient", "Rainbow" }
L.GRADS = { "Off", "Accent Flow", "Aurora", "Sunset", "Ocean", "Fire", "Rainbow", "Candy", "Mono" }
F.sk = draw.CreateFont("Verdana", 12, 400, FONTFLAG_ANTIALIAS | FONTFLAG_DROPSHADOW)
F.nlT = draw.CreateFont("Calibri", 18, 700, FONTFLAG_ANTIALIAS)
F.nlR = draw.CreateFont("Calibri", 16, 400, FONTFLAG_ANTIALIAS)
F.gs = draw.CreateFont("Segoe UI", 18, 800, FONTFLAG_ANTIALIAS)
F.gsI = draw.CreateFont("Segoe UI Symbol", 17, 400, FONTFLAG_ANTIALIAS)
F.script = draw.CreateFont("Segoe Script", 19, 700, FONTFLAG_ANTIALIAS)

-- key codes -> short names, worked out once from lmaobox's KEY_ / MOUSE_ constants
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

-- the gradient a HUD / notification uses (index into L.GRADS: 1 = off)
function L.gradStops(gi) return (gi and gi > 1) and logoStops(gi - 1) or nil end

-- a 2px border whose colour runs around the box (Animated gradient / Rainbow)
-- (the two helpers are plain functions with all values passed in: a function made inside would be new
--  garbage every time the border is drawn)
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
    -- the corners in the colour of the spot they sit at
    if r >= 1 then
        L.gbCor(x, y, 1, 0, stops, per, phase, r); L.gbCor(x + w, y, 2, w, stops, per, phase, r)
        L.gbCor(x, y + h, 3, 2 * w + h, stops, per, phase, r); L.gbCor(x + w, y + h, 4, w + h, stops, per, phase, r)
    end
end
-- border by setting: 1 off, 2 plain, 3 accent, 4 animated gradient, 5 rainbow
function L.styledBorder(bstyle, gi, x, y, w, h, r)
    if bstyle == 2 then roundRectLine(x, y, w, h, r, T.border)
    elseif bstyle == 3 then roundRectLine(x, y, w, h, r, accent(), 210)
    elseif bstyle == 4 then L.gradBorder(x, y, w, h, r, L.gradStops(gi) or logoStops(1), now() * 0.3)
    elseif bstyle == 5 then L.gradBorder(x, y, w, h, r, logoStops(6), now() * 0.3) end
end

-- the rows the HUD shows: { name, on, key }
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

    if st == 2 then                                                    -- Skeet: nested grey outlines, coloured top line
        local cw, cnt = 160, max(1, #rows)
        local ch = 19 + 15 * cnt
        local x, y = draggable("fl", sw - cw - 14, 60, cw, ch)
        local function out(ox, oy, w, h, c, s) rect(ox, oy, w, s, c); rect(ox, oy + h - s, w, s, c); rect(ox, oy + s, s, h - 2 * s, c); rect(ox + w - s, oy + s, s, h - 2 * s, c) end
        out(x, y, cw, ch, L.SK1, 1); out(x + 1, y + 1, cw - 2, ch - 2, L.SK2, 1); out(x + 2, y + 2, cw - 4, ch - 4, L.SK3, 3); out(x + 5, y + 5, cw - 10, ch - 10, L.SK2, 1)
        rect(x + 6, y + 6, cw - 12, ch - 12, L.SKBG, 245)
        local w1 = floor((cw - 14) / 2)
        color(L.SKB, 255); draw.FilledRect(x + 7, y + 7, x + 7 + w1, y + 8)
        draw.Color(L.SKP[1], L.SKP[2], L.SKP[3], 255); draw.FilledRectFade(x + 7, y + 7, x + 7 + w1, y + 8, 0, 255, true)
        color(L.SKP, 255); draw.FilledRect(x + 7 + w1, y + 7, x + cw - 7, y + 8)
        draw.Color(L.SKY[1], L.SKY[2], L.SKY[3], 255); draw.FilledRectFade(x + 7 + w1, y + 7, x + cw - 7, y + 8, 0, 255, true)
        if #rows == 0 then text(F.sk, "nothing running", x + 10, y + 11, 15, L.SKG)
        else
            for i, r in ipairs(rows) do
                local ry = y + 11 + (i - 1) * 15
                text(F.sk, r.name, x + 10, ry, 15, r.on and C_WHITE or L.SKG)
                local tail = "[" .. L.hudTail(r) .. "]"
                text(F.sk, tail, x + cw - 10 - textW(F.sk, tail), ry, 15, r.on and L.SKON or L.SKOFF)
            end
        end

    elseif st == 3 then                                                -- Neverlose: dark bar with a keyboard icon, list under it
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

    elseif st == 4 then                                                -- Radiance: a header chip, then one chip per option
        local maxW = chipW("✦", { { "DESTINY" } })
        for _, r in ipairs(rows) do                                      -- (one reused parts table per row, no new tables per frame)
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

    elseif st == 5 then                                                -- Mercury: one glowing box, title, line, rows
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

    elseif st == 6 then                                                -- Gamesense: bold capitals with a shadow, green when on
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
            if r.on then                                               -- the spinning circle while it is on
                local scx, scy = x + 22 + textW(F.gs, s) + 13, ry + 12
                ring(scx, scy, 6, C_BLACK, 120, 24)
                local a0 = t * 7
                for j = 0, 8 do
                    local aa = a0 + j * 0.52
                    disc(scx + cos(aa) * 6, scy + sin(aa) * 6, 1.4, col, 255)
                end
            end
        end

    elseif st == 7 then                                                -- Silentium: dark glass, handwritten name, switches
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
                draw.Color(round(ac[1]), round(ac[2]), round(ac[3]), 255)
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

    else                                                               -- Destiny (the M0MENT4M default HUD)
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
-- 8k. Speed graph (its own window): how fast you move, with the peak
---------------------------------------------------------------------------
L.SG_STYLES = { "Destiny", "Radiance", "Mercury", "Silentium" }
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
    if now() - L.speedAt > 1 / 40 then                                -- 40 samples a second, 3 seconds shown
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
    local panel = settings.sgBg                                       -- "Background" switch
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
    -- the line: colour set once, every 3rd sample (40 pieces instead of 120, each setting its own colour)
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
-- 8m. M0MENT4M menu backgrounds: Radiance ribbons, Silentium ribbons + butterflies (Ribbons / SlRibbons / Butterflies)
---------------------------------------------------------------------------
L.RDRIB = { { 124, 108, 255 }, { 150, 118, 255 }, { 96, 108, 255 }, { 170, 128, 255 }, { 110, 94, 240 }, { 140, 150, 255 }, { 120, 100, 250 } }
L.SLRIB = { { 255, 168, 198 }, { 255, 188, 212 }, { 250, 158, 192 }, { 255, 200, 220 }, { 246, 176, 204 } }
L.RDRIB_L = {}
for i, c in ipairs(L.RDRIB) do L.RDRIB_L[i] = { min(255, c[1] + 60), min(255, c[2] + 60), 255 } end
L.RIB_CORE = { 240, 236, 255 }
L.ribX, L.ribY = {}, {}

-- one straight piece of a thick line (no round ends, so overlapping see-through layers stay even)
function L.seg(x1, y1, x2, y2, w, c, a)
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    local nx, ny = -dy / len * w / 2, dx / len * w / 2
    cpoly(c, a, x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny)
end

-- glowing ribbons that wave across the screen: a few wide faint layers and a thin bright core
function L.drawRibbons(silentium)
    local sw, sh = draw.GetScreenSize()
    local n0 = 20 + settings.bgFxAmt * 1.5
    local k = silentium and max(3, min(5, round(3 + n0 / 60))) or max(3, min(6, round(3 + n0 / 40)))
    local t = now() * 1000
    local N = 18                                                      -- (pieces per ribbon: 18 still looks smooth)
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

-- white butterflies that flutter across (Silentium)
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
-- 9. Menu background effects (dim + particles + glow)
---------------------------------------------------------------------------
L.EMBER_GLOW = { 255, 90, 20 }
L.BG_FX = { "Off", "Embers", "Snow", "Rain", "Fireflies", "Stars", "Radiance sparkles", "Radiance ribbons", "Silentium" }
local particles, particleKind = {}, nil

local function spawnParticle(kind, sw, sh, anywhere)
    local p = { x = math.random() * sw, y = anywhere and math.random() * sh or 0, s = math.random() * 2 + 1,
                ph = math.random() * 6.28, sp = math.random() * 0.6 + 0.7 }
    if kind == 2 or kind == 7 then p.y = anywhere and p.y or sh + 5 end
    return p
end

local function drawBackground(openT)
    local sw, sh = draw.GetScreenSize()
    ALPHA = openT
    if settings.bgDim > 0 then rect(0, 0, sw, sh, C_BLACK, 255 * settings.bgDim / 100) end

    local kind = settings.bgFx
    if kind == 8 then L.drawRibbons(false)                         -- the M0MENT4M Radiance background
    elseif kind == 9 then L.drawRibbons(true); L.drawButterflies()   -- the M0MENT4M Silentium background
    elseif kind > 1 then
        local n = floor(settings.bgFxAmt * 1.6)
        if particleKind ~= kind then particles, particleKind = {}, kind end
        while #particles < n do particles[#particles + 1] = spawnParticle(kind, sw, sh, true) end
        while #particles > n do table.remove(particles) end
        local dt, t = frameDt(), now()
        for i, p in ipairs(particles) do
            if kind == 2 then                                           -- embers rise and flicker
                p.y = p.y - 40 * p.sp * dt
                p.x = p.x + sin(t * 1.3 + p.ph) * 12 * dt
                local fl = 0.6 + 0.4 * sin(t * 9 + p.ph)
                if p.s > 2 then disc(p.x, p.y, p.s + 1.5, L.EMBER_GLOW, 40 * fl) end   -- (glow only on the bigger ones)
                disc(p.x, p.y, p.s * 0.7, { 255, 170, 60 }, 220 * fl)
                if p.y < -5 then particles[i] = spawnParticle(kind, sw, sh, false) end
            elseif kind == 3 then                                       -- snow drifts down
                p.y = p.y + 30 * p.sp * dt
                p.x = p.x + sin(t * 0.8 + p.ph) * 18 * dt
                disc(p.x, p.y, p.s * 0.8, C_WHITE, 200)
                if p.y > sh + 5 then particles[i] = spawnParticle(kind, sw, sh, false) end
            elseif kind == 4 then                                       -- rain streaks
                p.y = p.y + 700 * p.sp * dt
                p.x = p.x - 120 * dt
                line(p.x, p.y, p.x + 3, p.y - 14, { 170, 200, 255 }, 120)
                if p.y > sh + 15 then particles[i] = spawnParticle(kind, sw, sh, false); particles[i].y = -15 end
            elseif kind == 5 then                                       -- fireflies wander and glow
                p.x = p.x + cos(t * 0.5 + p.ph) * 20 * dt
                p.y = p.y + sin(t * 0.7 + p.ph * 1.3) * 20 * dt
                local gl = 0.5 + 0.5 * sin(t * 2.5 + p.ph)
                disc(p.x, p.y, 6, { 200, 255, 120 }, 30 * gl)
                disc(p.x, p.y, 2, { 230, 255, 160 }, 230 * gl)
            elseif kind == 6 then                                       -- stars twinkle
                local tw = 0.4 + 0.6 * abs(sin(t * 1.4 * p.sp + p.ph))
                disc(p.x, p.y, p.s * 0.6, C_WHITE, 230 * tw)
                if p.s > 2.6 then
                    line(p.x - 4, p.y, p.x + 4, p.y, C_WHITE, 120 * tw)
                    line(p.x, p.y - 4, p.x, p.y + 4, C_WHITE, 120 * tw)
                end
            else                                                        -- radiance: violet sparkles rising
                p.y = p.y - 25 * p.sp * dt
                local tw = 0.5 + 0.5 * sin(t * 3 + p.ph)
                local c = sampleStops({ { 124, 108, 255 }, { 158, 146, 255 }, { 99, 102, 241 } }, p.ph / 6.28)
                disc(p.x, p.y, p.s + 2, c, 35 * tw)
                disc(p.x, p.y, p.s * 0.6, { 220, 215, 255 }, 230 * tw)
                if p.y < -5 then particles[i] = spawnParticle(kind, sw, sh, false) end
            end
        end
    end
    ALPHA = 1
end

local function menuGlow(x, y, w, h, a)
    if not settings.menuGlow then return end
    local acc = accent()
    local pulse = 0.8 + 0.2 * sin(now() * 2)
    for i = 1, 6 do
        local e = i * 2
        roundRectLine(x - e, y - e, w + 2 * e, h + 2 * e, 14 + e, acc, (70 - i * 11) * pulse * a)
    end
end

---------------------------------------------------------------------------
-- 10. World look (recolours world, sky and prop textures)
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

L.worldCheckAt = 0
local function updateWorld()
    if now() - L.worldCheckAt < 0.25 then return end                  -- 4 checks a second are plenty
    L.worldCheckAt = now()
    local map = engine.GetMapName() or ""
    if map ~= world.map then world.map, world.mapSince, world.key, world.again = map, now(), nil, false end
    if map == "" or now() - world.mapSince < 2 then return end      -- wait until the map has loaded its materials
    -- once more a few seconds into the map: materials that loaded late get the colour too (no button needed)
    if not world.again and now() - world.mapSince > 8 then
        world.again = true
        if settings.worldOn then applyWorld(false) end
    end
    local key = tostring(settings.worldOn) .. settings.worldPreset .. "|" .. settings.worldHue .. "|" ..
                settings.worldBright .. tostring(settings.worldSky) .. tostring(settings.worldProps)
    if key ~= world.key then
        if world.key == nil and not settings.worldOn then world.key = key; return end   -- nothing to undo yet
        -- wait until the setting stops changing (a slider being dragged), recolouring every material is slow
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
local view = { top = 0, bot = 0 }           -- visible part of the content (scrolling)
local cx, cy, cw                            -- content cursor
local sliderDrag = nil
L.savedAt = -99

-- a row is drawn when part of it is in view and it stays inside the window (the edges get covered afterwards)
local function rowVisible(h)
    return cy + h > view.top and cy < view.bot and cy >= view.wtop + 1 and cy + h <= view.wbot - 1
end
local function rowClick(x, y, w, h)
    if dropdown or mouse.y < view.top or mouse.y >= view.bot then return false end
    return takeClick(x, y, w, h)
end

local function card(id, h)
    local hovered = id and not dropdown and inside(mouse.x, mouse.y, cx, cy, cw, h) and mouse.y >= view.top and mouse.y < view.bot
    local hv = id and anim("card" .. id, hovered and 1 or 0, 14) or 0
    roundRect(cx, cy, cw, h, 12, mix(T.card, T.hover, hv))
    roundRectLine(cx, cy, cw, h, 12, T.border)
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
local wrapCache = {}                                                  -- [width][text] = lines
local function paraCard(s)
    local byW = wrapCache[cw]
    if not byW then byW = {}; wrapCache[cw] = byW end
    local lines = byW[s]                                              -- wrapped once, then remembered
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

-- colour picker popup (opened by a colour row; it lives in "dropdown" so every other click waits) -----------
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
    draw.Color(round(c[1]), round(c[2]), round(c[3]), 255)
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

    local sx, sy, sW, sH = x + 12, y + 12, W - 24, 120         -- saturation / brightness square
    local hx, hy, hW, hH = x + 12, y + 140, W - 24, 12         -- hue bar
    local r, g, b = hsv(d.h, 1, 1)
    rect(sx, sy, sW, sH, { r * 255, g * 255, b * 255 })
    fadeRect(sx, sy, sW, sH, C_WHITE, 255, 0, true)
    fadeRect(sx, sy, sW, sH, C_BLACK, 0, 255, false)
    for i = 1, 6 do                                            -- the hue rainbow in 6 fades
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

    -- quick colours, the hex text and "Theme" (back to the theme's own colour)
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
    if y + maxH > sh - 10 then y = d.by - 4 - maxH end               -- open upward when there is no room below
    d.scroll = d.scroll or 0
    local maxScroll = max(0, full - maxH)
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

-- the names of a list (for dropdowns), worked out once per list
local namesCache = {}
local function names(list)
    local out = namesCache[list]
    if out then return out end
    out = {}
    for i, v in ipairs(list) do out[i] = type(v) == "table" and (v.name or v[1]) or v end
    namesCache[list] = out
    return out
end

-- a row with a colour swatch; clicking it opens the colour picker. fallback = the colour used while it is "theme"
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

-- (these use notify / accent, so they sit after those are defined)
-- quick save (the button at the bottom of the sidebar and "Save into this slot")
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

-- loading a slot: a saved one loads; an empty one starts fresh from the defaults. Either way your other
-- slots stay untouched, and what you had before can be brought back with "Undo".
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

-- pages ---------------------------------------------------------------------------
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
    { group = "VISUALS", icon = "☀", name = "World", draw = function()
        section("World look")
        toggleRow("Recolour the world", "worldOn")
        dropRow("Look", "worldPreset", names(L.WORLD_PRESETS))
        if settings.worldPreset == #L.WORLD_PRESETS then sliderRow("Custom colour (hue)", "worldHue", 0, 360, "°") end
        sliderRow("Brightness", "worldBright", 20, 100, "%")
        toggleRow("Sky too", "worldSky")
        toggleRow("Props too", "worldProps")
        paraCard("Applies by itself on every map while it is on, and again a few seconds in for anything that loads late.")
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
        buttonRow("Make her say something", "Talk", function()
            local old = settings.compBubbles
            settings.compBubbles = true; compSay("idle"); settings.compBubbles = old
        end)
        buttonRow("Put her back in the corner", "Reset", function() settings.pos.comp = nil end)

        section("Paimon")
        if P.state == "downloading" then
            infoRow("Installing Paimon", string.format("%d / %d  -  %s", P.done + P.failed, P.TOTAL, P.current))
        else
            buttonRow(P.installed() and "Paimon is installed" or "Install Paimon (about 75 MB, the game pauses briefly per file)",
                      P.installed() and "Reinstall" or "Install", P.install)
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
        paraCard("Elfaria is drawn live, like in M0MENT4M: she floats, blinks, talks and watches your mouse. Click her while the menu is open to pet her, drag her anywhere.")
    end },

    { group = "SYSTEM", icon = "⚙", name = "Config", draw = function()
        section("Menu key")
        dropRow("Open the destiny menu with", "menuKey", names(L.MENU_KEYS))
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
        section("Where")
        if DIR then
            paraCard("Configs are saved in: " .. (DIR == "" and "the Team Fortress 2 folder" or DIR) .. "  (autosave when you close the menu)")
        else
            paraCard("lmaobox doesn't let destiny write files anywhere, so configs can't be saved. Tried: " .. table.concat(L.CFG_TRIED, "  |  "))
        end
    end },
    { group = "SYSTEM", icon = "ⓘ", name = "Info", draw = function()
        section("About")
        paraCard("Destiny v1 Visual Lua for LMAOBOX.")
        buttonRow("Check for updates", updater.running and "Checking..." or "Check", function() updaterCheck() end)
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
    roundRect(x, y, w, h, 14, T.win)
    roundRect(x, y, SIDE_W, h, 14, T.side)
    rect(x + SIDE_W - 14, y, 14, h, T.side)
    rect(x + SIDE_W, y + 14, 1, h - 28, T.border)

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

    -- navigation with group labels (green bar on the active page)
    local ny = y + 104
    local lastGroup
    for i, p in ipairs(PAGES) do
        if p.group ~= lastGroup then
            lastGroup = p.group
            text(F.tiny, p.group, x + 26, ny, 20, T.muted)
            ny = ny + 22
        end
        local nx, nw = x + 12, SIDE_W - 24
        if not dropdown and takeClick(nx, ny, nw, 30) then
            if menu.page ~= i then menu.page, menu.scrollT = i, 0 end
        end
        local act = anim("nav" .. i, menu.page == i and 1 or 0, 14)
        local hv = anim("navh" .. i, (not dropdown and inside(mouse.x, mouse.y, nx, ny, nw, 30)) and 1 or 0, 14)
        roundRect(nx, ny, nw, 30, 9, mix(mix(T.side, T.hover, hv * 0.6), T.active, act))
        if act > 0.01 then roundRect(nx, ny + 7, 3, 16 * act, 2, acc) end
        text(F.icon, p.icon, nx + 14, ny, 30, menu.page == i and acc or T.muted)
        text(F.small, p.name, nx + 40, ny, 30, menu.page == i and T.text or T.text2)
        ny = ny + 32
    end

    -- "Save config" button at the bottom of the sidebar (saves the selected slot)
    local bx, by, bw, bh = x + 12, y + h - 54, SIDE_W - 24, 40
    if not dropdown and takeClick(bx, by, bw, bh) then
        if L.saveSlot() then L.savedAt = now() end                 -- quick save into the slot you have selected
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

    -- cover what scrolled out of view (there is no clipping in the draw library)
    -- (rows end 28px before the right edge, so plain rectangles never touch the rounded corners)
    rect(x + SIDE_W + 1, y + 1, w - SIDE_W - 27, view.top - y - 1, T.win)
    rect(x + SIDE_W + 1, view.bot, w - SIDE_W - 27, y + h - view.bot - 1, T.win)
    roundRectLine(x, y, w, h, 14, T.border)
    text(F.title, page.name, contentX, y + 20, 30, T.text)

    -- scrollbar (accent, like the macro)
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
-- runs one part; an error is printed once to the console (with the part's name) instead of stopping everything
local reported = {}
-- how long each part takes (smoothed, in milliseconds), shown on the Info page
L.cost = {}
L.clock = (os and os.clock) or function() return 0 end
local function safe(name, fn, ...)
    local m0 = collectgarbage("count")
    local t0 = L.clock()
    local ok, err = pcall(fn, ...)
    local ms = (L.clock() - t0) * 1000
    local kb = collectgarbage("count") - m0
    if kb < 0 then kb = 0 end                                           -- (a cleanup ran in between)
    L.cost[name] = (L.cost[name] or ms) * 0.95 + ms * 0.05
    L.gc[name] = (L.gc[name] or kb) * 0.95 + kb * 0.05
    -- the worst frame of each part in the last 3 seconds (spikes = stutters, an average hides them)
    if ms > (L.worst[name] or 0) or now() - (L.worstAt[name] or 0) > 3 then L.worst[name], L.worstAt[name] = ms, now() end
    ALPHA = 1
    if not ok and not reported[name] then
        reported[name] = true
        -- short form "line 123: message" so the console doesn't cut it off
        local msg = tostring(err):gsub("^.-destiny%.lua:", "line ")
        print("[destiny] " .. name .. " - " .. msg)
    end
end
L.gc, L.worst, L.worstAt = {}, {}, {}
L.frameWorst, L.frameWorstAt = 0, 0

local function onDraw()
    perfTick()
    local ft = globals.AbsoluteFrameTime() * 1000
    if ft > L.frameWorst or now() - L.frameWorstAt > 3 then L.frameWorst, L.frameWorstAt = ft, now() end
    L.curFont = nil                                                   -- (other scripts may have switched the font)
    L.boxFrame()
    if engine.IsTakingScreenshot() then return end
    L.buildPalette()

    -- the destiny menu has its own key; ESC closes it too. (not while typing in chat or the console)
    local typing = engine.IsChatOpen() or engine.Con_IsVisible()
    local key = (L.MENU_KEYS[settings.menuKey] or L.MENU_KEYS[1])[2]
    local esc = pressed(KEY_ESCAPE)
    if pressed(key) and not typing then menu.open = not menu.open end
    if menu.open and esc then menu.open = false end
    if menu.open ~= menu.cursor then                                 -- show the mouse cursor while it is open
        menu.cursor = menu.open
        pcall(input.SetMouseInputEnabled, menu.open)
        if not menu.open then saveConfig("autosave") end            -- closing the menu saves your settings
    end
    -- while the lmaobox menu is closed there is no cursor and GetMousePos can give nothing back;
    -- reading it blindly crashed the script before the watermark was drawn
    local ok, pos = pcall(input.GetMousePos)
    if ok and type(pos) == "table" and pos[1] then mouse.x, mouse.y = pos[1], pos[2] end
    mouse.click = pressed(MOUSE_LEFT)
    mouse.held = input.IsButtonDown(MOUSE_LEFT)
    mouse.used = false
    mouse.wheel = (wheel(MOUSE_WHEEL_UP) and 1 or 0) - (wheel(MOUSE_WHEEL_DOWN) and 1 or 0)
    menu.openT = anim("menuopen", menu.open and 1 or 0, 14)
    if not menu.open then dropdown, sliderDrag = nil, nil end

    -- clicks on the menu window belong to the menu, not to the overlays under it
    local onMenu = overMenu()
    if onMenu then mouse.used = true end

    safe("features", pollFeatures)
    if L.paimon.state == "downloading" then safe("paimon install", L.paimon.work) end   -- (downloads + decodes a bit each frame)
    safe("world", updateWorld)
    -- auto-update: the menu is already up and usable; this just quietly checks GitHub a few seconds
    -- after load and never blocks a frame (the actual HTTP call is async)
    if not updater.checked and now() >= updater.startAt then
        updater.checked = true
        safe("update check", updaterCheck)
    end

    -- game-world effects first, overlays on top (each part on its own, so one error can't hide the rest)
    safe("screen effect", L.drawEdgeEffect)
    safe("extra effect", L.drawExtraEffect)
    if settings.dmgOn then safe("damage", drawDamage) end
    safe("announcer", drawAnnouncer)
    if settings.wmOn then safe("watermark", drawWatermark) end
    if settings.flOn then safe("hud", L.drawHud) end
    if settings.imOn then safe("input monitor", drawInputMonitor) end
    if settings.sgOn then safe("speed graph", L.drawSpeedGraph) end
    if settings.compOn then safe("waifu", drawCompanion) end   -- (she stays in her corner, menu or not)
    safe("notifications", drawNotifications)
    safe("welcome", L.drawWelcome)

    if menu.openT > 0.01 then
        safe("background", drawBackground, menu.openT)
        if onMenu then mouse.used = false end                      -- now the menu may take the click
        ALPHA = menu.openT * settings.opacity / 100
        safe("menu", drawMenu, menu.openT)
    end
end

callbacks.Register("Draw", "destiny_draw", onDraw)
callbacks.Register("FireGameEvent", "destiny_events", function(e) safe("events", onGameEvent, e) end)
-- screen shake: moves only the picture you see (the view), never where you aim
callbacks.Register("RenderView", "destiny_shake", function(view) pcall(L.onRenderView, view) end)
callbacks.Register("Unload", "destiny_unload", function()
    saveConfig("autosave")
    if menu.cursor then pcall(input.SetMouseInputEnabled, false) end   -- give the mouse back to the game
    if settings.worldOn then applyWorld(true) end              -- give the world its normal colours back
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
