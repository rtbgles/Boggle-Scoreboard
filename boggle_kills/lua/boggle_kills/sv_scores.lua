if not SERVER then return end

util.AddNetworkString( "BoggleKills" )
util.AddNetworkString( "BoggleKills_Req" )
util.AddNetworkString( "BoggleKills_You" )

local cvNpc = CreateConVar( "boggle_kills_npc", "1", FCVAR_ARCHIVE, "Count NPC / NextBot kills", 0, 1 )
local cvTop = CreateConVar( "boggle_kills_top", "10", FCVAR_ARCHIVE, "Rows shown on the board", 1, 10 )
local cvBots = CreateConVar( "boggle_kills_bots", "0", FCVAR_ARCHIVE, "Track bots, and count kills of bots", 0, 1 )

local DIR = "boggle_kills"
local SAVE_PATH = DIR .. "/scores.json"
local BACKUP_PATH = DIR .. "/scores_backup.json"
local PRE_V2_PATH = DIR .. "/scores_pre_v2.json"

local MAX_STORED = 4000
local MAX_NAME_CHARS = 32
local MAX_COUNT = 16777215 -- 24-bit wire fields
local MAX_RANK = 65535     -- 16-bit wire field
local SAVE_DELAY = 4
local REFRESH_DELAY = 0.5
local AUTOSAVE_INTERVAL = 90
local REQUEST_COOLDOWN = 5

--[[
    Store shape (2.0): scores[SteamID64 string] = { sid, name, pkills, nkills, deaths, seen }.
    A row is "verified" when row.sid equals its key. Rows written by 1.x have no sid;
    see claimLegacyRows for why they can't be trusted by key.

    Kept on the global table so a Lua autorefresh doesn't reload from disk and
    discard kills that haven't been saved yet.
]]
local scores = BoggleKills.Scores
local dirty = BoggleKills.Dirty == true
local lastBoardSig

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

-- Accepts every historical row shape: 1.0 stored only "kills", 1.1 split it.
local function normalize( row )
    if not istable( row ) then
        row = {}
    end

    local pkills = row.pkills
    if pkills == nil then
        pkills = row.kills
    end

    return {
        sid = isstring( row.sid ) and row.sid or nil,
        name = ( isstring( row.name ) and row.name ~= "" ) and row.name or "Unknown",
        pkills = count( pkills ),
        nkills = count( row.nkills ),
        deaths = count( row.deaths ),
        seen = tonumber( row.seen ) or 0
    }
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
        row = { sid = key, name = nick, pkills = 0, nkills = 0, deaths = 0, seen = 0 }
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

-- Verified rows rank individually. Unclaimed legacy rows are grouped by name
-- (summed, see claimLegacyRows) until their owner rejoins and claims them.
local function buildRanking()
    local entries = {}
    local legacyByName = {}
    for _, row in pairs( scores ) do
        local entry
        if row.sid then
            entry = { sid = row.sid, name = row.name, pkills = row.pkills, nkills = row.nkills, deaths = row.deaths }
            entries[#entries + 1] = entry
        else
            local lower = string.lower( row.name )
            entry = legacyByName[lower]
            if not entry then
                entry = { name = row.name, pkills = 0, nkills = 0, deaths = 0 }
                legacyByName[lower] = entry
                entries[#entries + 1] = entry
            end

            entry.pkills = count( entry.pkills + row.pkills )
            entry.nkills = count( entry.nkills + row.nkills )
            entry.deaths = count( entry.deaths + row.deaths )
        end
    end

    for _, entry in ipairs( entries ) do
        entry.total = totalOf( entry )
    end

    table.sort( entries, function( a, b )
        if a.total ~= b.total then return a.total > b.total end
        if a.pkills ~= b.pkills then return a.pkills > b.pkills end

        return a.name < b.name
    end )

    return entries
end

local function boardSize( entries )
    return math.min( #entries, cvTop:GetInt() )
end

local function boardSignature( entries )
    local parts = {}
    for i = 1, boardSize( entries ) do
        local e = entries[i]
        parts[i] = e.name .. "\1" .. e.pkills .. "\1" .. e.nkills .. "\1" .. e.deaths
    end

    return table.concat( parts, "\2" )
end

local function writeBoard( entries )
    local size = boardSize( entries )
    net.WriteUInt( size, 8 )
    for i = 1, size do
        local e = entries[i]
        net.WriteString( clipName( e.name ) )
        net.WriteUInt( e.pkills, 24 )
        net.WriteUInt( e.nkills, 24 )
        net.WriteUInt( e.deaths, 24 )
    end
end

-- Each player's own rank, so the board can show "you" even outside the top rows.
-- Only sent when that player's line actually changed.
local function sendPersonal( entries, target )
    local rankBySid = {}
    for i, e in ipairs( entries ) do
        if e.sid then
            rankBySid[e.sid] = i
        end
    end

    for _, ply in player.Iterator() do
        if not target or ply == target then
            local key = playerKey( ply )
            local row = key and scores[key]
            local rank = key and rankBySid[key] or 0
            local sig = row and ( rank .. ":" .. row.pkills .. ":" .. row.nkills .. ":" .. row.deaths ) or "none"
            if target or ply.BK_PersonalSig ~= sig then
                ply.BK_PersonalSig = sig
                net.Start( "BoggleKills_You" )
                    net.WriteUInt( math.min( rank, MAX_RANK ), 16 )
                    net.WriteUInt( row and row.pkills or 0, 24 )
                    net.WriteUInt( row and row.nkills or 0, 24 )
                    net.WriteUInt( row and row.deaths or 0, 24 )
                net.Send( ply )
            end
        end
    end
end

-- The board is only rebroadcast when its visible rows changed, so kills by
-- players outside the top rows cost one small personal message, not a broadcast.
local function refresh()
    local entries = buildRanking()
    local sig = boardSignature( entries )
    if sig ~= lastBoardSig then
        lastBoardSig = sig
        net.Start( "BoggleKills" )
            writeBoard( entries )
        net.Broadcast()
    end

    sendPersonal( entries )
end

local function queueRefresh()
    if timer.Exists( "BoggleKills_Refresh" ) then return end

    timer.Create( "BoggleKills_Refresh", REFRESH_DELAY, 1, refresh )
end

function BoggleKills.SendTo( ply )
    if not IsValid( ply ) then return end
    if ( ply.BK_NextRequest or 0 ) > CurTime() then return end
    ply.BK_NextRequest = CurTime() + REQUEST_COOLDOWN

    local entries = buildRanking()
    net.Start( "BoggleKills" )
        writeBoard( entries )
    net.Send( ply )
    sendPersonal( entries, ply )
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

    if hasLegacyRows( scores ) and not file.Exists( PRE_V2_PATH, "DATA" ) then
        file.Write( PRE_V2_PATH, file.Read( source, "DATA" ) or "" )
        print( "[BoggleKills] pre-2.0 scores found; original kept at " .. PRE_V2_PATH .. " and will be merged as players rejoin" )
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

local function credit( killer, field )
    local row = rowFor( killer )
    if not row then return end

    row[field] = count( row[field] + 1 )
    changed()
end

hook.Add( "PlayerDeath", "BoggleKills", function( victim, _, atk )
    local victimRow = rowFor( victim )
    if victimRow then
        victimRow.deaths = count( victimRow.deaths + 1 )
        changed()
    end

    local killer = resolveKiller( atk )
    if not killer or killer == victim then return end
    if victim:IsBot() and not cvBots:GetBool() then return end

    credit( killer, "pkills" )
end )

hook.Add( "OnNPCKilled", "BoggleKills", function( npc, atk )
    if not IsValid( npc ) or npc.BoggleKillsDead then return end
    npc.BoggleKillsDead = true
    if not cvNpc:GetBool() then return end

    local killer = resolveKiller( atk )
    if killer then
        credit( killer, "nkills" )
    end
end )

-- NextBots don't all fire OnNPCKilled. Checked after damage is applied (and only if
-- it was), so blocked or reduced damage can no longer produce a phantom kill.
hook.Add( "PostEntityTakeDamage", "BoggleKills_NextBot", function( ent, dmg, took )
    if not took or not ent:IsNextBot() or ent.BoggleKillsDead or ent:Health() > 0 then return end
    ent.BoggleKillsDead = true
    if not cvNpc:GetBool() then return end

    local killer = resolveKiller( dmg:GetAttacker() )
    if killer then
        credit( killer, "nkills" )
    end
end )

hook.Add( "PlayerInitialSpawn", "BoggleKills", function( ply )
    if rowFor( ply ) then
        queueSave()
    end

    queueRefresh()
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
