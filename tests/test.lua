-- Runs the real addon Lua (server + client) against stubs and checks that saves
-- keep every field, kills are counted, and every net message reads back exactly
-- as written.
package.path = ( arg[0]:match( "(.*/)" ) or "./" ) .. "?.lua;" .. package.path
local S = require( "stubs" )
local cjson = S.cjson

local failures = 0
local function check( cond, msg )
    if cond then
        print( "  ok   " .. msg )
    else
        failures = failures + 1
        print( "  FAIL " .. msg )
    end
end

local function section( name ) print( "\n== " .. name ) end

--[[ A 2.0 save as found on a live server, with a pre-2.0 row and a 1.x row. ]]
local ORIGINAL = cjson.encode( {
    ["76561198000000001"] = { sid = "76561198000000001", name = "Boggle", pkills = 120, nkills = 3400, deaths = 55, seen = 1700000000, custom_future_field = "keep me" },
    ["76561198000000002"] = { sid = "76561198000000002", name = "Alice", pkills = 300, nkills = 20, deaths = 150, seen = 1700000001 },
    ["76561198000000003"] = { sid = "76561198000000003", name = "Zed", pkills = 0, nkills = 0, deaths = 3, seen = 1700000002 },
    legacy_1 = { name = "OldTimer", pkills = 40, nkills = 10, deaths = 5, seen = 0 },
    ["STEAM_0:1:12345"] = { name = "Carol", kills = 15, seen = 0 }
} )

local fs = { ["boggle_kills/scores.json"] = ORIGINAL }
local bus = S.newBus()
local sv = S.newRealm( "server", bus, fs )
local cl = S.newRealm( "client", bus )

-- Client-only stubs.
cl.chatLines = {}
cl.chat = { AddText = function( ... )
    local parts = {}
    for i = 1, select( "#", ... ) do
        local v = select( i, ... )
        if type( v ) == "string" then parts[#parts + 1] = v end
    end
    cl.chatLines[#cl.chatLines + 1] = table.concat( parts )
end }
local PHRASES = { npc_zombie = "Zombie", npc_combine_s = "Combine Soldier" }
cl.language = { GetPhrase = function( s ) return PHRASES[s] or s end }

sv.include( "autorun/boggle_kills.lua" )
cl.include( "autorun/boggle_kills.lua" )

local dave = S.newPlayer( "Dave", "76561198000000004" )
local boggle = S.newPlayer( "Boggle", "76561198000000001", { superadmin = true } )
local alice = S.newPlayer( "Alice", "76561198000000002" )
local carol = S.newPlayer( "Carol", "76561198000000005", { sid32 = "STEAM_0:1:12345" } )
local LOCAL = dave

-- Delivers queued messages to their realm; returns the names delivered.
local function pump()
    local names = {}
    while #bus.outbox > 0 do
        local msg = table.remove( bus.outbox, 1 )
        names[#names + 1] = msg.name .. "->" .. ( msg.to == "all" and "all" or msg.to == "server" and "server" or msg.to:Nick() )
        if msg.to == "server" then
            sv.net.Deliver( msg, LOCAL )
        elseif msg.to == "all" or msg.to == LOCAL then
            cl.net.Deliver( msg )
        end
    end

    return names
end

local function step( seconds )
    S.clock.now = S.clock.now + ( seconds or 1 )
    sv.RunTimers()

    return pump()
end

local function saved()
    sv.BoggleKills.Save( true )

    return cjson.decode( fs["boggle_kills/scores.json"] )
end

section( "Loading a 2.0 save" )
check( fs["boggle_kills/scores_pre_v2_1.json"] == ORIGINAL, "untouched copy of the original save kept as scores_pre_v2_1.json" )
check( fs["boggle_kills/scores_pre_v2.json"] == ORIGINAL, "pre-2.0 rows present, so scores_pre_v2.json kept too (2.0 behaviour)" )

local before = cjson.decode( ORIGINAL )
local after = saved()
local lost = {}
for key, row in pairs( before ) do
    for field, value in pairs( row ) do
        if not after[key] or after[key][field] ~= value then
            lost[#lost + 1] = key .. "." .. field
        end
    end
end
check( #lost == 0, "every key and field of every original row survives load + save" .. ( #lost > 0 and ( " (lost: " .. table.concat( lost, ", " ) .. ")" ) or "" ) )
check( after["76561198000000001"].custom_future_field == "keep me", "unknown fields are carried over" )
check( after["76561198000000001"].streak == 0 and after["76561198000000002"].streak == 0, "new 'streak' field added, starting at 0" )
check( after["STEAM_0:1:12345"].pkills == 15, "1.0 'kills' still read as player kills" )

section( "Players joining" )
for _, p in ipairs( { dave, boggle, alice } ) do
    sv.players[#sv.players + 1] = p
    sv.hook.Run( "PlayerInitialSpawn", p )
end
cl.hook.Run( "InitPostEntity" )
local delivered = step( 1 )
print( "  messages: " .. table.concat( delivered, ", " ) )
local lists = cl.BoggleKills.Lists
check( #lists[1] == 6 and lists[1][1].name == "Boggle", "lifetime page received, Boggle first (" .. #lists[1] .. " rows)" )
check( lists[1][1].total == 3520 and lists[1][1].online == true, "Boggle's total and online flag" )
local lifetimeNames = {}
for i, row in ipairs( lists[1] ) do lifetimeNames[i] = row.name .. "=" .. row.total end
print( "  lifetime: " .. table.concat( lifetimeNames, ", " ) )
check( lists[2][1].name == "Alice", "player-kill page led by Alice" )
check( #lists[4] == 0, "no streaks recorded yet, streak page empty" )
check( #lists[5] == 3 and lists[5][2].name == "OldTimer" and lists[5][3].name == "Alice", "K/D page: the 3 entries with 25+ kills, best ratio first (" .. #lists[5] .. ")" )
check( cl.BoggleKills.Me.rank > 0 and cl.BoggleKills.Rows[cl.BoggleKills.Me.slot].name == "Dave", "local player's rank and pool slot point at Dave" )

section( "Kills, streaks and the ticker" )
local function npcKill( killer, class, opts )
    sv.hook.Run( "OnNPCKilled", S.newNpc( class, opts ), killer )
end
for _ = 1, 9 do npcKill( dave, "npc_zombie" ) end
step( 1 )
check( #cl.chatLines == 0, "no streak announcement before 10" )
npcKill( dave, "npc_combine_s" )
npcKill( dave, "npc_drg_custom", { PrintName = "Mutant Bloodsucker" } )
local nb = S.newNpc( "npc_unknown_bot", { nextbot = true } )
sv.hook.Run( "PostEntityTakeDamage", nb, { GetAttacker = function() return dave end }, true )
step( 1 )
check( cl.chatLines[1] == "[Kill Board] Dave is on a 10 kill streak!", "streak milestone announced: " .. tostring( cl.chatLines[1] ) )
local feed = cl.BoggleKills.Feed
check( #feed == 6 and feed[1].victim == "#npc_unknown_bot" and feed[2].victim == "Mutant Bloodsucker" and feed[3].victim == "#npc_combine_s", "client ticker keeps the last 6 kills, newest first" )
check( cl.BoggleKills.NpcName( "#npc_zombie" ) == "Zombie" and cl.BoggleKills.NpcName( "#npc_unknown_bot" ) == "Unknown Bot", "NPC names translated, unknown classes tidied" )
check( cl.BoggleKills.Me.live == 12 and cl.BoggleKills.Me.streak == 12, "Dave's live and best streak are 12" )
check( cl.BoggleKills.Lists[4][1].name == "Dave", "streak page now led by Dave" )

sv.hook.Run( "PlayerDeath", dave, alice, alice )
step( 1 )
check( cl.chatLines[2] == "[Kill Board] Alice ended Dave's 12 kill streak!", "streak end announced: " .. tostring( cl.chatLines[2] ) )
check( cl.BoggleKills.Me.live == 0 and cl.BoggleKills.Me.streak == 12 and cl.BoggleKills.Me.deaths == 1, "Dave: streak reset, best kept, death counted" )
check( cl.BoggleKills.Feed[1].killer == "Alice" and cl.BoggleKills.Feed[1].victim == "Dave" and not cl.BoggleKills.Feed[1].npc, "player kill on the ticker" )

sv.hook.Run( "PlayerDeath", alice, alice, alice )
step( 1 )
check( saved()["76561198000000002"].pkills == 301, "suicide adds a death but no kill" )

section( "Untracked bots" )
local bot = S.newPlayer( "Bot01", "90071996842377216", { bot = true } )
sv.players[#sv.players + 1] = bot
local feedBefore = #sv.BoggleKills.Feed
npcKill( bot, "npc_zombie" )
step( 1 )
check( #sv.BoggleKills.Feed == feedBefore and sv.BoggleKills.Feed[#sv.BoggleKills.Feed].killer ~= "Bot01", "kills by untracked bots stay off the ticker" )

section( "Chat commands" )
local function say( ply, text )
    local before = #cl.chatLines
    local ret = sv.hook.Run( "PlayerSay", ply, text, false )
    pump()

    return ret, cl.chatLines[before + 1]
end
S.clock.now = S.clock.now + 10
local ret, line = say( dave, "!kills" )
check( ret == nil and line and line:find( "Dave  #", 1, true ), "!kills shows the sender's stats and the message stays visible" )
print( "  " .. tostring( line ) )
S.clock.now = S.clock.now + 10
ret, line = say( dave, "/top" )
check( ret == "" and line and line:find( "Top killers:  1. Boggle 3,520", 1, true ), "/top lists the top 5 silently" )
print( "  " .. tostring( line ) )
S.clock.now = S.clock.now + 10
ret, line = say( dave, "!kills ali" )
check( line and line:find( "Alice", 1, true ), "!kills <partial name> finds an online player" )
S.clock.now = S.clock.now + 10
ret, line = say( dave, "!kills oldtimer" )
check( line and line:find( "OldTimer", 1, true ), "!kills finds offline/legacy players by name" )
S.clock.now = S.clock.now + 10
ret, line = say( dave, "!kills nobody_here" )
check( line == "[Kill Board] Nobody matching nobody_here is on the board.", "unknown name reported" )
ret, line = say( dave, "!kills" )
check( line == nil, "commands are rate limited" )
ret = sv.hook.Run( "PlayerSay", dave, "hello !kills", false )
check( ret == nil, "ordinary chat is left alone" )

section( "Legacy claim" )
sv.players[#sv.players + 1] = carol
sv.hook.Run( "PlayerInitialSpawn", carol )
step( 1 )
local data = saved()
check( data["STEAM_0:1:12345"] == nil and data["76561198000000005"].pkills == 15, "Carol's 1.x row merged into her verified row on join (2.0 behaviour)" )

section( "New leader" )
for _ = 1, 3600 do npcKill( dave, "npc_zombie" ) end
step( 1 )
local leaderLine
for _, l in ipairs( cl.chatLines ) do if l:find( "new #1", 1, true ) then leaderLine = l end end
check( leaderLine == "[Kill Board] Dave is the new #1 with 3,612 kills!", "new #1 announced: " .. tostring( leaderLine ) )
check( cl.BoggleKills.Lists[1][1].name == "Dave" and cl.BoggleKills.Lists[1][1].move == 4, "Dave tops the board, up 4 places since map start" )
local boggleRow
for _, r in ipairs( cl.BoggleKills.Lists[1] ) do if r.name == "Boggle" then boggleRow = r end end
check( boggleRow and boggleRow.move == -1, "Boggle shows as down one place since map start" )

section( "Newcomer" )
local erin = S.newPlayer( "Erin", "76561198000000006" )
sv.players[#sv.players + 1] = erin
sv.hook.Run( "PlayerInitialSpawn", erin )
for _ = 1, 400 do npcKill( erin, "npc_zombie" ) end
step( 1 )
local erinRow
for _, r in ipairs( cl.BoggleKills.Lists[1] ) do if r.name == "Erin" then erinRow = r end end
check( erinRow and erinRow.fresh, "a player first seen after map start is marked NEW" )

section( "Quiet refresh" )
sv.hook.Run( "PlayerInitialSpawn", alice )
local names = step( 1 )
local boards = 0
for _, n in ipairs( names ) do if n:find( "^BoggleKills%->" ) then boards = boards + 1 end end
check( boards == 0, "no board rebroadcast when nothing visible changed" )

section( "Disconnect" )
dave.removed = true
sv.hook.Run( "PlayerDisconnected", dave )
table.remove( sv.players, 1 )
step( 1 )
local daveRow
for _, r in ipairs( cl.BoggleKills.Rows ) do if r.name == "Dave" then daveRow = r end end
check( daveRow and daveRow.online == false, "online dot cleared after disconnect" )
dave.removed = false

section( "Board view command" )
sv.boards = {}
check( sv.concommands.boggle_kills_view ~= nil, "boggle_kills_view registered" )

section( "Reset" )
sv.concommands.boggle_kills_reset( alice )
check( next( sv.BoggleKills.Scores ) ~= nil, "non-superadmins can't reset" )
sv.concommands.boggle_kills_reset( boggle )
local archive
for path, content in pairs( fs ) do if path:find( "scores_reset_", 1, true ) then archive = content end end
check( archive and cjson.decode( archive )["76561198000000004"].nkills >= 3600, "reset archives the previous scores first" )
check( next( sv.BoggleKills.Scores ) == nil, "scores cleared" )
pump()

print( ( "\n%d failure(s)" ):format( failures ) )
os.exit( failures == 0 and 0 or 1 )
