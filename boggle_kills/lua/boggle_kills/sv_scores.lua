if not SERVER then return end

util.AddNetworkString( "BoggleKills" )
util.AddNetworkString( "BoggleKills_Req" )
util.AddNetworkString( "BoggleKills_You" )
util.AddNetworkString( "BoggleKills_Feed" )
util.AddNetworkString( "BoggleKills_Chat" )

local cvNpc = CreateConVar( "boggle_kills_npc", "1", FCVAR_ARCHIVE, "Count NPC / NextBot kills", 0, 1 )
local cvTop = CreateConVar( "boggle_kills_top", "10", FCVAR_ARCHIVE, "Rows shown on the board", 1, 10 )
local cvBots = CreateConVar( "boggle_kills_bots", "0", FCVAR_ARCHIVE, "Track bots, and count kills of bots", 0, 1 )
local cvAnnounce = CreateConVar( "boggle_kills_announce", "1", FCVAR_ARCHIVE, "Announce new #1s and kill streaks in chat", 0, 1 )
local cvChat = CreateConVar( "boggle_kills_chat", "1", FCVAR_ARCHIVE, "Enable the !kills and !top chat commands", 0, 1 )
local cvKdMin = GetConVar( "boggle_kills_kd_min" )

local PAGE_TOTAL = BoggleKills.PAGE_TOTAL
local PAGE_PLAYERS = BoggleKills.PAGE_PLAYERS
local PAGE_NPCS = BoggleKills.PAGE_NPCS
local PAGE_STREAK = BoggleKills.PAGE_STREAK
local PAGE_KD = BoggleKills.PAGE_KD
local PAGE_COUNT = BoggleKills.PAGE_COUNT

local DIR = "boggle_kills"
local SAVE_PATH = DIR .. "/scores.json"
local BACKUP_PATH = DIR .. "/scores_backup.json"
local PRE_V2_PATH = DIR .. "/scores_pre_v2.json"
local PRE_V21_PATH = DIR .. "/scores_pre_v2_1.json"

local MAX_STORED = 4000
local MAX_NAME_CHARS = 32
local MAX_COUNT = 16777215 -- 24-bit wire fields
local MAX_RANK = 65535     -- 16-bit wire field
local MAX_LIVE = 65535     -- 16-bit wire field (current streak)
local MAX_MOVE = 127       -- 8-bit signed wire field
local MAX_TOTAL = 4294967295 -- 32-bit wire field
local MAX_AGE = 4095       -- 12-bit wire field, seconds
local SAVE_DELAY = 4
local REFRESH_DELAY = 0.5
local AUTOSAVE_INTERVAL = 90
local REQUEST_COOLDOWN = 5
local CHAT_COOLDOWN = 3
local FEED_KEEP = 4
local TOP_IN_CHAT = 5
local STREAK_END_MIN = 10
local STREAK_MILESTONES = { [10] = true, [25] = true, [50] = true, [100] = true, [250] = true, [500] = true, [1000] = true }

--[[
    Store shape (2.1): scores[SteamID64 string] = { sid, name, pkills, nkills, deaths, streak, seen }.
    A row is "verified" when row.sid equals its key. Rows written by 1.x have no sid;
    see claimLegacyRows for why they can't be trusted by key. "streak" (best kill
    streak) is new in 2.1 and starts at 0 for existing rows; nothing else changed.

    Kept on the global table so a Lua autorefresh doesn't reload from disk and
    discard kills that haven't been saved yet.
]]
local scores = BoggleKills.Scores
local dirty = BoggleKills.Dirty == true
local lastBoardSig

-- Current streaks only live in memory (a streak ends on death or disconnect),
-- keyed like scores.
local streaks = BoggleKills.Streaks or {}
BoggleKills.Streaks = streaks

-- Recent kills for the board's live ticker, oldest first.
local feed = BoggleKills.Feed or {}
BoggleKills.Feed = feed
local lastTotalsSig

local function setScores( tbl )
    scores = tbl
    BoggleKills.Scores = tbl
end

local function markDirty()
    dirty = true
    BoggleKills.Dirty = true
end

local function count( value )
    return math.Clamp( math.floor( tonumber( value ) or 0 ), 0, MAX_COUNT )
end

local function totalOf( row )
    return row.pkills + row.nkills
end

--[[
    Accepts every historical row shape: 1.0 stored only "kills", 1.1 split it,
    2.1 added "streak". Fields this version doesn't recognise are carried over
    untouched, so loading and re-saving never drops data, even data written by
    a newer version.
]]
local function normalize( row )
    if not istable( row ) then
        row = {}
    end

    local out = {}
    for k, v in pairs( row ) do
        out[k] = v
    end

    local pkills = row.pkills
    if pkills == nil then
        pkills = row.kills
    end

    out.sid = isstring( row.sid ) and row.sid or nil
    out.name = ( isstring( row.name ) and row.name ~= "" ) and row.name or "Unknown"
    out.pkills = count( pkills )
    out.nkills = count( row.nkills )
    out.deaths = count( row.deaths )
    out.streak = count( row.streak )
    out.seen = tonumber( row.seen ) or 0

    return out
end

local function clipName( name )
    local len = utf8.len( name )
    if not len then return string.sub( name, 1, MAX_NAME_CHARS ) end
    if len <= MAX_NAME_CHARS then return name end

    return string.sub( name, 1, utf8.offset( name, MAX_NAME_CHARS + 1 ) - 1 )
end

local function playerKey( ply )
    if ply:IsBot() then
        if not cvBots:GetBool() then return nil end

        return "bot_" .. ply:Nick()
    end

    local id = ply:SteamID64()
    if isstring( id ) and id ~= "" and id ~= "0" then return id end

    return nil
end

--[[
    1.x loaded the save with util.JSONToTable's default key conversion, which turns a
    SteamID64 key into a double. Doubles can't hold a SteamID64 exactly, and a number
    key never matches the string ply:SteamID64() anyway, so after every restart each
    player silently got a fresh row. The old board hid that by merging rows by name
    with math.max, which showed only the best single session.

    Those session rows are disjoint in time, so a player's true lifetime total is
    their sum. The first time a player joins under 2.0, every unverified row filed
    under their SteamID64, their old SteamID, or their current name is folded into
    one verified row.
]]
local function claimLegacyRows( row, key, sid32, nick )
    local lowerNick = string.lower( nick )
    for otherKey, other in pairs( scores ) do
        local mine = otherKey == key or otherKey == sid32 or string.lower( other.name ) == lowerNick
        if other ~= row and other.sid == nil and mine then
            row.pkills = count( row.pkills + other.pkills )
            row.nkills = count( row.nkills + other.nkills )
            row.deaths = count( row.deaths + other.deaths )
            row.streak = math.max( row.streak, other.streak )
            scores[otherKey] = nil
        end
    end
end

local function rowFor( ply )
    local key = playerKey( ply )
    if not key then return nil end

    local nick = ply:Nick()
    local row = scores[key]
    if not row or row.sid ~= key then
        row = { sid = key, name = nick, pkills = 0, nkills = 0, deaths = 0, streak = 0, seen = 0 }
        claimLegacyRows( row, key, ply:SteamID(), nick )
        scores[key] = row
        markDirty()
    end

    if row.name ~= nick then
        row.name = nick
        markDirty()
    end

    row.seen = os.time()

    return row
end

--[[ Ranking ]]

local function entryId( entry )
    return entry.sid or ( "legacy:" .. string.lower( entry.name ) )
end

-- The first ranking of the map is remembered, so rows can show how far they've
-- climbed or fallen since.
local function ensureBaseline( entries )
    if BoggleKills.Baseline then return end

    local baseline = {}
    for i, entry in ipairs( entries ) do
        baseline[entryId( entry )] = i
    end

    BoggleKills.Baseline = baseline
end

-- Verified rows rank individually. Unclaimed legacy rows are grouped by name
-- (summed, see claimLegacyRows) until their owner rejoins and claims them.
-- Returns the full lifetime ranking and the server-wide kill total.
local function buildRanking()
    local entries = {}
    local legacyByName = {}
    for _, row in pairs( scores ) do
        local entry
        if row.sid then
            entry = { sid = row.sid, name = row.name, pkills = row.pkills, nkills = row.nkills, deaths = row.deaths, streak = row.streak }
            entries[#entries + 1] = entry
        else
            local lower = string.lower( row.name )
            entry = legacyByName[lower]
            if not entry then
                entry = { name = row.name, pkills = 0, nkills = 0, deaths = 0, streak = 0 }
                legacyByName[lower] = entry
                entries[#entries + 1] = entry
            end

            entry.pkills = count( entry.pkills + row.pkills )
            entry.nkills = count( entry.nkills + row.nkills )
            entry.deaths = count( entry.deaths + row.deaths )
            entry.streak = math.max( entry.streak, row.streak )
        end
    end

    local kills = 0
    for _, entry in ipairs( entries ) do
        entry.total = totalOf( entry )
        entry.kd = entry.total / math.max( entry.deaths, 1 )
        kills = kills + entry.total
    end

    table.sort( entries, function( a, b )
        if a.total ~= b.total then return a.total > b.total end
        if a.pkills ~= b.pkills then return a.pkills > b.pkills end

        return a.name < b.name
    end )

    for i, entry in ipairs( entries ) do
        entry.rank = i
    end

    ensureBaseline( entries )

    return entries, kills
end

local function bySid( entries )
    local map = {}
    for _, entry in ipairs( entries ) do
        if entry.sid then
            map[entry.sid] = entry
        end
    end

    return map
end

--[[
    The best n entries by field, among those whose gate field reaches minValue.
    One pass with a small insertion-sorted list instead of a sort per page. entries
    arrive in lifetime order, and only a strictly better value moves an entry up,
    so ties keep their lifetime order.
]]
local function topN( entries, n, field, minValue, gateField )
    gateField = gateField or field
    local top = {}
    for _, entry in ipairs( entries ) do
        local size = #top
        local qualifies = entry[gateField] >= minValue
        if qualifies and ( size < n or entry[field] > top[size][field] ) then
            local i = math.min( size + 1, n )
            while i > 1 and entry[field] > top[i - 1][field] do
                top[i] = top[i - 1]
                i = i - 1
            end

            top[i] = entry
        end
    end

    return top
end

local function onlineKeys()
    local keys = {}
    for _, ply in player.Iterator() do
        local key = not ply.BK_Gone and playerKey( ply )
        if key then
            keys[key] = true
        end
    end

    return keys
end

local function movementOf( entry )
    local baseline = BoggleKills.Baseline
    local base = baseline[entryId( entry )]
    if not base and entry.sid then
        -- A player who just claimed their legacy rows keeps that row's history.
        base = baseline["legacy:" .. string.lower( entry.name )]
    end

    if not base then return 0, true end

    return math.Clamp( base - entry.rank, -MAX_MOVE, MAX_MOVE ), false
end

-- Every page's top rows, deduplicated into one pool: the same leaders tend to
-- appear on most pages.
local function buildBoard( entries )
    local size = cvTop:GetInt()
    local lists = {}

    local lifetime = {}
    for i = 1, math.min( #entries, size ) do
        lifetime[i] = entries[i]
    end

    lists[PAGE_TOTAL] = lifetime
    lists[PAGE_PLAYERS] = topN( entries, size, "pkills", 1 )
    lists[PAGE_NPCS] = topN( entries, size, "nkills", 1 )
    lists[PAGE_STREAK] = topN( entries, size, "streak", 1 )
    lists[PAGE_KD] = topN( entries, size, "kd", cvKdMin:GetInt(), "total" )

    local online = onlineKeys()
    local pool, slotOf = {}, {}
    for page = 1, PAGE_COUNT do
        for _, entry in ipairs( lists[page] ) do
            if not slotOf[entry] then
                local move, fresh = movementOf( entry )
                pool[#pool + 1] = {
                    name = clipName( entry.name ),
                    pkills = entry.pkills,
                    nkills = entry.nkills,
                    deaths = entry.deaths,
                    streak = entry.streak,
                    live = entry.sid and math.min( streaks[entry.sid] or 0, MAX_LIVE ) or 0,
                    online = entry.sid ~= nil and online[entry.sid] == true,
                    move = move,
                    fresh = fresh
                }
                slotOf[entry] = #pool
            end
        end
    end

    return { pool = pool, slotOf = slotOf, lists = lists }
end

local function boardSignature( board )
    local parts = {}
    for i, r in ipairs( board.pool ) do
        parts[i] = table.concat( { r.name, r.pkills, r.nkills, r.deaths, r.streak, r.live,
            r.online and 1 or 0, r.move, r.fresh and 1 or 0 }, "\1" )
    end

    for page = 1, PAGE_COUNT do
        local slots = {}
        for i, entry in ipairs( board.lists[page] ) do
            slots[i] = board.slotOf[entry]
        end

        parts[#parts + 1] = table.concat( slots, "," )
    end

    return table.concat( parts, "\2" )
end

local function writeBoard( board )
    net.WriteUInt( #board.pool, 8 )
    for _, r in ipairs( board.pool ) do
        net.WriteString( r.name )
        net.WriteUInt( r.pkills, 24 )
        net.WriteUInt( r.nkills, 24 )
        net.WriteUInt( r.deaths, 24 )
        net.WriteUInt( r.streak, 24 )
        net.WriteUInt( r.live, 16 )
        net.WriteBool( r.online )
        net.WriteBool( r.fresh )
        net.WriteInt( r.move, 8 )
    end

    for page = 1, PAGE_COUNT do
        local list = board.lists[page]
        net.WriteUInt( #list, 8 )
        for _, entry in ipairs( list ) do
            net.WriteUInt( board.slotOf[entry], 8 )
        end
    end
end

-- Each player's own line, so the board can show "you" even outside the top rows,
-- plus where they sit in the pool so their row is highlighted on every page.
-- Only sent when that player's line actually changed.
local function sendPersonal( entries, board, target )
    local entryBySid = bySid( entries )

    for _, ply in player.Iterator() do
        if not target or ply == target then
            local key = playerKey( ply )
            local row = key and scores[key]
            local entry = key and entryBySid[key]
            local rank = entry and entry.rank or 0
            local slot = entry and board.slotOf[entry] or 0
            local live = key and streaks[key] or 0
            local sig = row and table.concat( { rank, slot, row.pkills, row.nkills, row.deaths, row.streak, live }, ":" ) or "none"
            if target or ply.BK_PersonalSig ~= sig then
                ply.BK_PersonalSig = sig
                net.Start( "BoggleKills_You" )
                    net.WriteUInt( math.min( rank, MAX_RANK ), 16 )
                    net.WriteUInt( slot, 8 )
                    net.WriteUInt( row and row.pkills or 0, 24 )
                    net.WriteUInt( row and row.nkills or 0, 24 )
                    net.WriteUInt( row and row.deaths or 0, 24 )
                    net.WriteUInt( row and row.streak or 0, 24 )
                    net.WriteUInt( math.min( live, MAX_LIVE ), 16 )
                net.Send( ply )
            end
        end
    end
end

--[[ Live ticker and server totals ]]

local function pushFeed( killer, victim, isNpc )
    feed[#feed + 1] = { killer = clipName( killer:Nick() ), victim = clipName( victim ), npc = isNpc, time = CurTime(), sent = false }
    while #feed > FEED_KEEP do
        table.remove( feed, 1 )
    end
end

local function writeFeed( kills, fighters, events, replace )
    local now = CurTime()
    net.WriteUInt( math.min( kills, MAX_TOTAL ), 32 )
    net.WriteUInt( math.min( fighters, MAX_RANK ), 16 )
    net.WriteBool( replace )
    net.WriteUInt( #events, 4 )
    for _, ev in ipairs( events ) do
        net.WriteString( ev.killer )
        net.WriteString( ev.victim )
        net.WriteBool( ev.npc )
        net.WriteUInt( math.Clamp( math.floor( now - ev.time ), 0, MAX_AGE ), 12 )
    end
end

-- Totals and new kills travel together, batched by the refresh timer.
local function broadcastFeed( kills, fighters )
    local events = {}
    for _, ev in ipairs( feed ) do
        if not ev.sent then
            ev.sent = true
            events[#events + 1] = ev
        end
    end

    local sig = kills .. ":" .. fighters
    if #events == 0 and sig == lastTotalsSig then return end
    lastTotalsSig = sig

    net.Start( "BoggleKills_Feed" )
        writeFeed( kills, fighters, events, false )
    net.Broadcast()
end

--[[ Chat ]]

local function announce( kind, write )
    if not cvAnnounce:GetBool() then return end

    net.Start( "BoggleKills_Chat" )
        net.WriteUInt( kind, 4 )
        write()
    net.Broadcast()
end

-- Announces a new #1. The first ranking after a map load only records the
-- leader, and a player claiming their own legacy rows isn't a new leader.
local function checkLeader( entries )
    local top = entries[1]
    local id = ( top and top.total > 0 ) and entryId( top ) or false
    local name = top and string.lower( top.name ) or false
    local previousId, previousName = BoggleKills.LeaderId, BoggleKills.LeaderName
    BoggleKills.LeaderId = id
    BoggleKills.LeaderName = name

    if previousId == nil or not id or id == previousId or name == previousName then return end

    announce( BoggleKills.MSG_LEADER, function()
        net.WriteString( clipName( top.name ) )
        net.WriteUInt( top.total, 32 )
    end )
end

--[[ Refresh ]]

-- The board is only rebroadcast when its visible rows changed, so kills by
-- players outside the top rows cost one small personal message, not a broadcast.
local function refresh()
    local entries, kills = buildRanking()
    local board = buildBoard( entries )
    local sig = boardSignature( board )
    if sig ~= lastBoardSig then
        lastBoardSig = sig
        net.Start( "BoggleKills" )
            writeBoard( board )
        net.Broadcast()
    end

    sendPersonal( entries, board )
    broadcastFeed( kills, #entries )
    checkLeader( entries )
end

local function queueRefresh()
    if timer.Exists( "BoggleKills_Refresh" ) then return end

    timer.Create( "BoggleKills_Refresh", REFRESH_DELAY, 1, refresh )
end

function BoggleKills.SendTo( ply )
    if not IsValid( ply ) then return end
    if ( ply.BK_NextRequest or 0 ) > CurTime() then return end
    ply.BK_NextRequest = CurTime() + REQUEST_COOLDOWN

    local entries, kills = buildRanking()
    local board = buildBoard( entries )
    net.Start( "BoggleKills" )
        writeBoard( board )
    net.Send( ply )
    sendPersonal( entries, board, ply )

    -- Unsent kills reach this player with the next broadcast like everyone else.
    local sent = {}
    for _, ev in ipairs( feed ) do
        if ev.sent then
            sent[#sent + 1] = ev
        end
    end

    net.Start( "BoggleKills_Feed" )
        writeFeed( kills, #entries, sent, true )
    net.Send( ply )
end

--[[ Persistence ]]

local function prune()
    local rows = {}
    for key, row in pairs( scores ) do
        rows[#rows + 1] = { key = key, total = totalOf( row ), seen = row.seen }
    end

    if #rows <= MAX_STORED then return end

    table.sort( rows, function( a, b )
        if a.total ~= b.total then return a.total < b.total end

        return a.seen < b.seen
    end )

    for i = 1, #rows - MAX_STORED do
        scores[rows[i].key] = nil
    end
end

-- The previous save is rotated to a backup first, so a crash mid-write can never
-- leave the server with no readable copy.
function BoggleKills.Save( force )
    if not dirty and not force then return end

    prune()
    local json = util.TableToJSON( scores )
    if not json then return end

    file.CreateDir( DIR )
    if file.Exists( SAVE_PATH, "DATA" ) then
        file.Delete( BACKUP_PATH, "DATA" )
        file.Rename( SAVE_PATH, BACKUP_PATH )
    end

    file.Write( SAVE_PATH, json )
    dirty = false
    BoggleKills.Dirty = false
end

local function queueSave()
    if timer.Exists( "BoggleKills_Save" ) then return end

    timer.Create( "BoggleKills_Save", SAVE_DELAY, 1, BoggleKills.Save )
end

local function changed()
    markDirty()
    queueSave()
    queueRefresh()
end

local function parse( path )
    local raw = file.Read( path, "DATA" )
    if not raw or raw == "" then return nil end

    -- ignoreConversions = true keeps SteamID64 keys as exact strings.
    local ok, data = pcall( util.JSONToTable, raw, false, true )
    if ok and istable( data ) then return data end

    return nil
end

local function import( data )
    local out = {}
    if data[1] ~= nil then
        -- 1.0 saved a plain array with no ids at all.
        for i, row in ipairs( data ) do
            local r = normalize( row )
            r.sid = nil
            out["legacy_" .. i] = r
        end

        return out
    end

    for key, row in pairs( data ) do
        key = tostring( key )
        local r = normalize( row )
        if r.sid ~= key then
            r.sid = nil
        end

        out[key] = r
    end

    return out
end

local function hasLegacyRows( tbl )
    for _, row in pairs( tbl ) do
        if row.sid == nil then return true end
    end

    return false
end

-- Copies the file a save was loaded from, once, before this version first writes
-- over it. A safety net for rolling back; nothing ever reads it.
local function keepOriginal( source, path, reason )
    if file.Exists( path, "DATA" ) then return end

    file.Write( path, file.Read( source, "DATA" ) or "" )
    print( "[BoggleKills] " .. reason .. "; original kept at " .. path )
end

function BoggleKills.Load()
    local data = parse( SAVE_PATH )
    local source = SAVE_PATH

    if not data and file.Exists( SAVE_PATH, "DATA" ) then
        -- Move the unreadable file aside so the next save can't bury it.
        local quarantine = DIR .. "/scores_corrupt_" .. os.time() .. ".json"
        file.Rename( SAVE_PATH, quarantine )
        print( "[BoggleKills] " .. SAVE_PATH .. " was unreadable and has been moved to " .. quarantine )
    end

    if not data then
        data = parse( BACKUP_PATH )
        source = BACKUP_PATH
        if data then
            print( "[BoggleKills] restored scores from " .. BACKUP_PATH )
        end
    end

    if not data then
        setScores( {} )

        return
    end

    setScores( import( data ) )

    keepOriginal( source, PRE_V21_PATH, "first load under 2.1" )
    if hasLegacyRows( scores ) then
        keepOriginal( source, PRE_V2_PATH, "pre-2.0 scores found and will be merged as players rejoin" )
    end
end

--[[ Kill tracking ]]

-- Players get credit for kills made from a vehicle they're driving.
local function resolveKiller( atk )
    if not IsValid( atk ) then return nil end
    if atk:IsPlayer() then return atk end

    if atk:IsVehicle() then
        local driver = atk:GetDriver()
        if IsValid( driver ) and driver:IsPlayer() then return driver end
    end

    return nil
end

-- Returns whether the kill counted (untracked bots don't).
local function credit( killer, field )
    local row = rowFor( killer )
    if not row then return false end

    row[field] = count( row[field] + 1 )

    local live = ( streaks[row.sid] or 0 ) + 1
    streaks[row.sid] = live
    if live > row.streak then
        row.streak = count( live )
    end

    if STREAK_MILESTONES[live] then
        announce( BoggleKills.MSG_STREAK, function()
            net.WriteString( clipName( row.name ) )
            net.WriteUInt( math.min( live, MAX_LIVE ), 16 )
        end )
    end

    changed()

    return true
end

-- The base gamemode's kill feed name (a spawn menu name, or a "#class" phrase the
-- client translates), preferring a scripted NPC's own PrintName over the phrase.
local function npcLabel( npc )
    local name = hook.Run( "GetDeathNoticeEntityName", npc )
    if not isstring( name ) or name == "" then
        name = "#" .. npc:GetClass()
    end

    local printName = npc.PrintName
    if string.StartsWith( name, "#" ) and isstring( printName ) and printName ~= "" then return printName end

    return name
end

local function endStreak( victim, key, killer )
    local ended = streaks[key] or 0
    streaks[key] = nil
    if ended < STREAK_END_MIN then return end

    announce( BoggleKills.MSG_STREAK_END, function()
        net.WriteString( clipName( victim:Nick() ) )
        net.WriteUInt( math.min( ended, MAX_LIVE ), 16 )
        net.WriteString( killer and clipName( killer:Nick() ) or "" )
    end )
end

hook.Add( "PlayerDeath", "BoggleKills", function( victim, _, atk )
    local victimRow = rowFor( victim )
    if victimRow then
        victimRow.deaths = count( victimRow.deaths + 1 )
        changed()
    end

    local killer = resolveKiller( atk )
    if killer == victim then
        killer = nil
    end

    local victimKey = playerKey( victim )
    if victimKey then
        endStreak( victim, victimKey, killer )
    end

    if not killer then return end
    if victim:IsBot() and not cvBots:GetBool() then return end

    if credit( killer, "pkills" ) then
        pushFeed( killer, victim:Nick(), false )
    end
end )

hook.Add( "OnNPCKilled", "BoggleKills", function( npc, atk )
    if not IsValid( npc ) or npc.BoggleKillsDead then return end
    npc.BoggleKillsDead = true
    if not cvNpc:GetBool() then return end

    local killer = resolveKiller( atk )
    if killer and credit( killer, "nkills" ) then
        pushFeed( killer, npcLabel( npc ), true )
    end
end )

-- NextBots don't all fire OnNPCKilled. Checked after damage is applied (and only if
-- it was), so blocked or reduced damage can no longer produce a phantom kill.
hook.Add( "PostEntityTakeDamage", "BoggleKills_NextBot", function( ent, dmg, took )
    if not took or not ent:IsNextBot() or ent.BoggleKillsDead or ent:Health() > 0 then return end
    ent.BoggleKillsDead = true
    if not cvNpc:GetBool() then return end

    local killer = resolveKiller( dmg:GetAttacker() )
    if killer and credit( killer, "nkills" ) then
        pushFeed( killer, npcLabel( ent ), true )
    end
end )

hook.Add( "PlayerInitialSpawn", "BoggleKills", function( ply )
    if rowFor( ply ) then
        queueSave()
    end

    queueRefresh()
end )

-- Online dots and live streaks on the board change when someone leaves.
hook.Add( "PlayerDisconnected", "BoggleKills", function( ply )
    ply.BK_Gone = true
    local key = playerKey( ply )
    if key then
        streaks[key] = nil
    end

    queueRefresh()
end )

--[[ Chat commands: !kills [name], !top. "/" runs them silently, like ULX. ]]

local function findEntry( entries, query )
    local entryBySid = bySid( entries )
    query = string.lower( query )

    -- Someone on the server is usually who a partial name means.
    for _, ply in player.Iterator() do
        if string.find( string.lower( ply:Nick() ), query, 1, true ) then
            local key = playerKey( ply )
            local entry = key and entryBySid[key]
            if entry then return entry end
        end
    end

    for _, entry in ipairs( entries ) do
        if string.lower( entry.name ) == query then return entry end
    end

    for _, entry in ipairs( entries ) do
        if string.find( string.lower( entry.name ), query, 1, true ) then return entry end
    end

    return nil
end

local function sendStats( ply, query )
    local entries = buildRanking()
    local entry
    if query == "" then
        local key = playerKey( ply )
        entry = key and bySid( entries )[key]
    else
        entry = findEntry( entries, query )
    end

    net.Start( "BoggleKills_Chat" )
    if entry then
        net.WriteUInt( BoggleKills.MSG_STATS, 4 )
        net.WriteString( clipName( entry.name ) )
        net.WriteUInt( math.min( entry.rank, MAX_RANK ), 16 )
        net.WriteUInt( math.min( #entries, MAX_RANK ), 16 )
        net.WriteUInt( entry.pkills, 24 )
        net.WriteUInt( entry.nkills, 24 )
        net.WriteUInt( entry.deaths, 24 )
        net.WriteUInt( entry.streak, 24 )
        net.WriteUInt( entry.sid and math.min( streaks[entry.sid] or 0, MAX_LIVE ) or 0, 16 )
    else
        net.WriteUInt( BoggleKills.MSG_MISSING, 4 )
        net.WriteString( clipName( query ) )
    end
    net.Send( ply )
end

local function sendTop( ply )
    local entries = buildRanking()
    local size = math.min( #entries, TOP_IN_CHAT )

    net.Start( "BoggleKills_Chat" )
        net.WriteUInt( BoggleKills.MSG_TOP, 4 )
        net.WriteUInt( size, 4 )
        for i = 1, size do
            net.WriteString( clipName( entries[i].name ) )
            net.WriteUInt( entries[i].total, 32 )
        end
    net.Send( ply )
end

local COMMANDS = { kills = sendStats, stats = sendStats, top = sendTop }

hook.Add( "PlayerSay", "BoggleKills_Commands", function( ply, text )
    if not cvChat:GetBool() then return end

    local prefix, name, arg = string.match( text, "^([!/])(%a+)%s*(.-)%s*$" )
    local command = name and COMMANDS[string.lower( name )]
    if not command then return end

    if ( ply.BK_NextChat or 0 ) <= CurTime() then
        ply.BK_NextChat = CurTime() + CHAT_COOLDOWN
        command( ply, arg )
    end

    if prefix == "/" then return "" end
end )

net.Receive( "BoggleKills_Req", function( _, ply )
    BoggleKills.SendTo( ply )
end )

timer.Create( "BoggleKills_Autosave", AUTOSAVE_INTERVAL, 0, function()
    BoggleKills.Save()
end )

hook.Add( "ShutDown", "BoggleKills", function()
    BoggleKills.Save()
end )

concommand.Add( "boggle_kills_reset", function( ply )
    if IsValid( ply ) and not ply:IsSuperAdmin() then return end

    file.CreateDir( DIR )
    local archive = DIR .. "/scores_reset_" .. os.time() .. ".json"
    file.Write( archive, util.TableToJSON( scores ) or "{}" )

    setScores( {} )
    for _, p in player.Iterator() do
        p.BK_PersonalSig = nil
    end

    table.Empty( streaks )
    BoggleKills.Baseline = nil
    BoggleKills.LeaderId = nil
    lastBoardSig = nil
    BoggleKills.Save( true )
    refresh()

    local msg = "[BoggleKills] scores reset; previous data archived to " .. archive
    if IsValid( ply ) then
        ply:ChatPrint( msg )
    end

    print( msg )
end )

if not scores then
    BoggleKills.Load()
end
