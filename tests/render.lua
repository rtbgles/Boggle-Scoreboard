-- Drives the real board renderer (cl_init.lua) with recording surface/draw stubs
-- and writes the draw calls as JSON, one file per page, for render.py.
package.path = ( arg[0]:match( "(.*/)" ) or "./" ) .. "?.lua;" .. package.path
local S = require( "stubs" )
local cjson = S.cjson
local OUT = assert( arg[1], "usage: render.lua <outdir>" )
-- Glyph widths written by fontmetrics.py, so text is measured like it's drawn.
local metrics = dofile( OUT .. "/fontmetrics.lua" )

local function row( sid, name, p, n, d, seen )
    return { sid = sid, name = name, pkills = p, nkills = n, deaths = d, seen = seen or 1700000000 }
end

local save = {}
local roster = {
    { "76561198000000001", "Boggle", 1204, 18342, 233 },
    { "76561198000000002", "xX_DeathDealer_Xx", 2510, 3044, 1802 },
    { "76561198000000003", "Mr. Fluffy Pants the Third of His Name", 801, 4105, 640 },
    { "76561198000000004", "Alice", 1530, 2210, 410 },
    { "76561198000000005", "Головорез", 950, 2660, 905 },
    { "76561198000000006", "npc_slayer", 12, 3205, 77 },
    { "76561198000000007", "Kev", 640, 1888, 1201 },
    { "76561198000000008", "Sniper Wolf", 1977, 120, 95 },
    { "76561198000000009", "Grandpa Joe", 210, 1650, 300 },
    { "76561198000000010", "Tim", 400, 1100, 650 },
    { "76561198000000011", "Quinn", 300, 900, 120 }
}
for _, r in ipairs( roster ) do save[r[1]] = row( r[1], r[2], r[3], r[4], r[5] ) end
save.legacy_1 = { name = "OldTimer", pkills = 140, nkills = 410, deaths = 50, seen = 0 }

local fs = { ["boggle_kills/scores.json"] = cjson.encode( save ) }
local bus = S.newBus()
local sv = S.newRealm( "server", bus, fs )
local cl = S.newRealm( "client", bus )
cl.chat = { AddText = function() end }
cl.language = { GetPhrase = function( s ) return ( { npc_combine_s = "Combine Soldier", npc_zombie = "Zombie", npc_antlionguard = "Antlion Guard" } )[s] or s end }

--[[ Recording draw stubs ]]

local ops, color, mult, material, font = {}, { 255, 255, 255, 255 }, 1, nil, nil
local function cur() return { color[1], color[2], color[3], ( color[4] or 255 ) * mult } end
local function measure( f, text )
    local m = metrics[f]
    local w = 0
    for ch in text:gmatch( "[%z\1-\127\194-\244][\128-\191]*" ) do
        w = w + ( m.w[ch] or m.w["M"] * 0.8 )
    end

    return w, m.h
end

cl.surface = {
    CreateFont = function() end,
    SetDrawColor = function( r, g, b, a )
        if type( r ) == "table" then color = { r.r, r.g, r.b, r.a or 255 } else color = { r, g, b, a or 255 } end
    end,
    DrawRect = function( x, y, w, h ) ops[#ops + 1] = { op = "rect", x = x, y = y, w = w, h = h, c = cur() } end,
    DrawOutlinedRect = function( x, y, w, h, t ) ops[#ops + 1] = { op = "outline", x = x, y = y, w = w, h = h, t = t or 1, c = cur() } end,
    SetMaterial = function( m ) material = m end,
    DrawTexturedRect = function( x, y, w, h ) ops[#ops + 1] = { op = "tex", mat = material and material.name or "white", x = x, y = y, w = w, h = h, c = cur() } end,
    DrawPoly = function( verts )
        local pts = {}
        for i, v in ipairs( verts ) do pts[i] = { v.x, v.y } end
        ops[#ops + 1] = { op = "poly", pts = pts, c = cur() }
    end,
    SetFont = function( f ) font = f end,
    GetTextSize = function( text ) return measure( font, text ) end,
    SetAlphaMultiplier = function( m ) mult = m end,
    PlaySound = function() end
}
cl.draw = {
    SimpleText = function( text, f, x, y, c, xa, ya )
        local w, h = measure( f, text )
        ops[#ops + 1] = { op = "text", text = text, font = f, x = x, y = y, xa = xa or 0, ya = ya or 3, w = w, h = h, c = { c.r, c.g, c.b, ( c.a or 255 ) * mult } }

        return w, h
    end,
    NoTexture = function() material = nil end
}
cl.TEXT_ALIGN_LEFT, cl.TEXT_ALIGN_CENTER, cl.TEXT_ALIGN_RIGHT, cl.TEXT_ALIGN_TOP, cl.TEXT_ALIGN_BOTTOM = 0, 1, 2, 3, 4
cl.Material = function( name ) return { name = name, IsError = function() return false end } end
cl.cam = { Start3D2D = function() end, End3D2D = function() end }
cl.input = { LookupBinding = function() return "e" end }
local eyePos, eyeDir = S.Vector( 120, 74, -38 ), S.Vector( -1, 0, 0 )
cl.EyePos = function() return eyePos end
cl.EyeVector = function() return eyeDir end

sv.include( "autorun/boggle_kills.lua" )
cl.include( "autorun/boggle_kills.lua" )

cl.ENT = {}
cl.includeBase = S.ROOT .. "entities/ent_boggle_kills/"
cl.include( "entities/ent_boggle_kills/cl_init.lua" )
local ENT = cl.ENT

local board = setmetatable( { view = 0 }, { __index = ENT } )
function board:GetPos() return S.Vector( 0, 0, 0 ) end
function board:GetAngles() return S.Angle( 0, 0, 0 ) end
function board:GetForward() return S.Angle( 0, 0, 0 ):Forward() end
function board:GetUp() return S.Angle( 0, 0, 0 ):Up() end
function board:GetView() return self.view end
function board:SetRenderBounds() end
cl.boards = { board }

--[[ A believable server state ]]

local players = {}
for _, i in ipairs( { 1, 2, 3, 4, 5, 6, 10 } ) do
    local r = roster[i]
    players[i] = S.newPlayer( r[2], r[1] )
    sv.players[#sv.players + 1] = players[i]
    sv.hook.Run( "PlayerInitialSpawn", players[i] )
end

local LOCAL = players[4] -- Alice
local function pump()
    while #bus.outbox > 0 do
        local msg = table.remove( bus.outbox, 1 )
        if msg.to == "server" then sv.net.Deliver( msg, LOCAL )
        elseif msg.to == "all" or msg.to == LOCAL then cl.net.Deliver( msg ) end
    end
end
local function step( s ) S.clock.now = S.clock.now + ( s or 1 ) sv.RunTimers() pump() end

cl.hook.Run( "InitPostEntity" )
step( 1 )

local function npcKill( killer, class ) sv.hook.Run( "OnNPCKilled", S.newNpc( class ), killer ) end
-- Alice climbs past Головорез; the second-placed player is on a streak.
for _ = 1, 120 do npcKill( players[4], "npc_zombie" ) end
sv.hook.Run( "PlayerDeath", players[4], players[2], players[2] )
for _ = 1, 6 do npcKill( players[2], "npc_combine_s" ) end
sv.hook.Run( "PlayerDeath", players[3], players[1], players[1] )
npcKill( players[1], "npc_antlionguard" )
-- Tim climbs two places; a newcomer arrives; Alice starts a fresh streak.
for _ = 1, 700 do npcKill( players[10], "npc_zombie" ) end
local newbie = S.newPlayer( "Newbie", "76561198000000099" )
sv.players[#sv.players + 1] = newbie
sv.hook.Run( "PlayerInitialSpawn", newbie )
for _ = 1, 1700 do npcKill( newbie, "npc_zombie" ) end
for _ = 1, 5 do npcKill( players[4], "npc_combine_s" ) end
sv.hook.Run( "PlayerDeath", players[6], newbie, newbie )
step( 1 )
S.clock.now = S.clock.now + 0.5

for page = 1, 5 do
    ops, mult = {}, 1
    board.view = page
    board.BK_LastView = nil
    S.clock.now = S.clock.now + 2
    board:DrawTranslucent() -- starts the page's fade-in
    S.clock.now = S.clock.now + 1
    ops, mult = {}, 1
    board:DrawTranslucent()
    local f = io.open( OUT .. "/page" .. page .. ".json", "w" )
    f:write( cjson.encode( { w = ENT.BoardW, h = ENT.BoardH, ops = ops } ) )
    f:close()
end

-- Also confirm the aim test lands where the eye looks: board centre.
local x, y = board:BoardTrace( eyePos, eyeDir, 300 )
print( ( "aim test: board pixel %.1f, %.1f (expect ~%.1f, ~%.1f)" ):format( x or -1, y or -1, ( 74 ) / 0.18, ( 12 + 38 ) / 0.18 ) )
print( "rendered " .. OUT )
