if not CLIENT then return end

local PAGE_COUNT = BoggleKills.PAGE_COUNT
local FEED_KEEP = 6

-- Rows is the pool of everyone on any page; Lists[page] are ordered rows from it.
BoggleKills.Rows = BoggleKills.Rows or {}
BoggleKills.Lists = BoggleKills.Lists or {}
BoggleKills.List = BoggleKills.List or {} -- the lifetime page
BoggleKills.Me = BoggleKills.Me or { rank = 0, slot = 0, pkills = 0, nkills = 0, deaths = 0, streak = 0, live = 0, total = 0 }
BoggleKills.Feed = BoggleKills.Feed or {}
BoggleKills.Totals = BoggleKills.Totals or { kills = 0, fighters = 0 }

-- Bumped on every update so boards know to re-measure their cached text. The
-- ticker and totals change far more often than the rows, so they count apart.
BoggleKills.Revision = ( BoggleKills.Revision or 0 ) + 1
BoggleKills.FeedRevision = ( BoggleKills.FeedRevision or 0 ) + 1

local function bump()
    BoggleKills.Revision = BoggleKills.Revision + 1
end

net.Receive( "BoggleKills", function()
    local now = CurTime()
    local previous = {}
    for _, row in ipairs( BoggleKills.Rows ) do
        previous[row.name] = row
    end

    local rows = {}
    for i = 1, net.ReadUInt( 8 ) do
        local row = {
            slot = i,
            name = net.ReadString(),
            pkills = net.ReadUInt( 24 ),
            nkills = net.ReadUInt( 24 ),
            deaths = net.ReadUInt( 24 ),
            streak = net.ReadUInt( 24 ),
            live = net.ReadUInt( 16 ),
            online = net.ReadBool(),
            fresh = net.ReadBool(),
            move = net.ReadInt( 8 )
        }
        row.total = row.pkills + row.nkills
        row.kd = row.total / math.max( row.deaths, 1 )

        -- Rows that just scored flash briefly on the board.
        local old = previous[row.name]
        row.flashAt = old and ( row.total > old.total and now or old.flashAt ) or 0

        rows[i] = row
    end

    local lists = {}
    for page = 1, PAGE_COUNT do
        local list = {}
        for _ = 1, net.ReadUInt( 8 ) do
            list[#list + 1] = rows[net.ReadUInt( 8 )]
        end

        lists[page] = list
    end

    BoggleKills.Rows = rows
    BoggleKills.Lists = lists
    BoggleKills.List = lists[BoggleKills.PAGE_TOTAL]
    bump()
end )

net.Receive( "BoggleKills_You", function()
    local me = {
        rank = net.ReadUInt( 16 ),
        slot = net.ReadUInt( 8 ),
        pkills = net.ReadUInt( 24 ),
        nkills = net.ReadUInt( 24 ),
        deaths = net.ReadUInt( 24 ),
        streak = net.ReadUInt( 24 ),
        live = net.ReadUInt( 16 )
    }
    me.total = me.pkills + me.nkills

    BoggleKills.Me = me
    bump()
end )

-- Server totals plus the latest kills, newest first.
net.Receive( "BoggleKills_Feed", function()
    BoggleKills.Totals = { kills = net.ReadUInt( 32 ), fighters = net.ReadUInt( 16 ) }

    local feed = net.ReadBool() and {} or BoggleKills.Feed
    local now = CurTime()
    for _ = 1, net.ReadUInt( 4 ) do
        table.insert( feed, 1, {
            killer = net.ReadString(),
            victim = net.ReadString(),
            npc = net.ReadBool(),
            time = now - net.ReadUInt( 12 )
        } )
    end

    while #feed > FEED_KEEP do
        table.remove( feed )
    end

    BoggleKills.Feed = feed
    BoggleKills.FeedRevision = BoggleKills.FeedRevision + 1
end )

--[[ Display names for NPC victims ]]

local npcNames = {}

-- "#npc_zombie" -> "Zombie" via the game's phrases; unknown classes get tidied up.
function BoggleKills.NpcName( label )
    if not string.StartsWith( label, "#" ) then return label end

    local cached = npcNames[label]
    if cached then return cached end

    local class = string.sub( label, 2 )
    local name = language.GetPhrase( class )
    if name == class then
        name = language.GetPhrase( label )
    end

    if name == class or name == label then
        name = string.gsub( class, "^npc_", "" )
        name = string.gsub( name, "_", " " )
        name = string.gsub( name, "(%a)(%w*)", function( first, rest ) return string.upper( first ) .. rest end )
    end

    npcNames[label] = name

    return name
end

--[[ Chat ]]

local TAG = Color( 220, 45, 45 )
local TEXT = Color( 230, 220, 220 )
local NAME = Color( 255, 255, 255 )
local NUMBER = Color( 255, 140, 90 )
local MUTED = Color( 165, 145, 145 )

local function say( ... )
    chat.AddText( TAG, "[Kill Board] ", TEXT, ... )
end

local comma = string.Comma

local handlers = {}

handlers[BoggleKills.MSG_STATS] = function()
    local name = net.ReadString()
    local rank, of = net.ReadUInt( 16 ), net.ReadUInt( 16 )
    local pkills, nkills, deaths = net.ReadUInt( 24 ), net.ReadUInt( 24 ), net.ReadUInt( 24 )
    local best, live = net.ReadUInt( 24 ), net.ReadUInt( 16 )
    local total = pkills + nkills
    local kd = string.format( "%.2f", total / math.max( deaths, 1 ) )

    local parts = {
        NAME, name, MUTED, "  #", NUMBER, comma( rank ), MUTED, " of " .. comma( of ) .. "  ·  ",
        NUMBER, comma( total ), TEXT, " kills ", MUTED, "(" .. comma( pkills ) .. " players, " .. comma( nkills ) .. " NPCs)  ·  ",
        NUMBER, comma( deaths ), TEXT, " deaths  ·  K/D ", NUMBER, kd,
        TEXT, "  ·  best streak ", NUMBER, comma( best )
    }
    if live > 0 then
        table.Add( parts, { TEXT, "  ·  on a ", NUMBER, comma( live ), TEXT, " streak now" } )
    end

    say( unpack( parts ) )
end

handlers[BoggleKills.MSG_TOP] = function()
    local parts = { NAME, "Top killers:" }
    for i = 1, net.ReadUInt( 4 ) do
        local name, total = net.ReadString(), net.ReadUInt( 32 )
        table.Add( parts, { MUTED, "  " .. i .. ". ", NAME, name, NUMBER, " " .. comma( total ) } )
    end

    say( unpack( parts ) )
end

handlers[BoggleKills.MSG_MISSING] = function()
    local query = net.ReadString()
    if query == "" then
        say( "You're not on the board yet. Get a kill!" )
    else
        say( "Nobody matching ", NAME, query, TEXT, " is on the board." )
    end
end

handlers[BoggleKills.MSG_LEADER] = function()
    local name, total = net.ReadString(), net.ReadUInt( 32 )
    say( NAME, name, TEXT, " is the new ", NUMBER, "#1", TEXT, " with ", NUMBER, comma( total ), TEXT, " kills!" )
end

handlers[BoggleKills.MSG_STREAK] = function()
    local name, streak = net.ReadString(), net.ReadUInt( 16 )
    say( NAME, name, TEXT, " is on a ", NUMBER, comma( streak ), TEXT, " kill streak!" )
end

handlers[BoggleKills.MSG_STREAK_END] = function()
    local victim, streak, killer = net.ReadString(), net.ReadUInt( 16 ), net.ReadString()
    if killer == "" then
        say( NAME, victim, TEXT, "'s ", NUMBER, comma( streak ), TEXT, " kill streak is over." )
    else
        say( NAME, killer, TEXT, " ended ", NAME, victim, TEXT, "'s ", NUMBER, comma( streak ), TEXT, " kill streak!" )
    end
end

net.Receive( "BoggleKills_Chat", function()
    local handler = handlers[net.ReadUInt( 4 )]
    if handler then
        handler()
    end
end )

-- The client asks once it can actually receive; messages sent during
-- PlayerInitialSpawn can arrive before client Lua has loaded and be dropped.
hook.Add( "InitPostEntity", "BoggleKills_Ask", function()
    net.Start( "BoggleKills_Req" )
    net.SendToServer()
end )
