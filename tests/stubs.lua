-- Minimal Garry's Mod API stand-ins, enough to run Boggle Kills' real Lua files
-- under LuaJIT. Server and client each get their own global environment, joined
-- by a net bus that type-checks every read against the matching write.
local cjson = require( "cjson" )
cjson.encode_sparse_array( true )

local M = {}
local HERE = debug.getinfo( 1, "S" ).source:sub( 2 ):match( "(.*/)" ) or "./"
M.ROOT = assert( os.getenv( "ADDON" ), "set ADDON to the addon folder" ) .. "/lua/"

--[[ GMod extensions to the shared standard libraries ]]

function string.Comma( number )
    if type( number ) == "number" then
        number = string.format( "%f", number )
        number = string.match( number, "^(.-)%.?0*$" )
    end

    local index = -1
    while index ~= 0 do
        number, index = string.gsub( number, "^(-?%d+)(%d%d%d)", "%1,%2" )
    end

    return number
end

function string.StartsWith( s, prefix ) return string.sub( s, 1, #prefix ) == prefix end
function math.Clamp( v, lo, hi ) return math.min( math.max( v, lo ), hi ) end
function table.Empty( t ) for k in pairs( t ) do t[k] = nil end end
function table.IsEmpty( t ) return next( t ) == nil end
function table.Add( dst, src ) for _, v in ipairs( src ) do dst[#dst + 1] = v end return dst end

local function charStarts( s )
    local starts, i = {}, 1
    while i <= #s do
        starts[#starts + 1] = i
        local c = s:byte( i )
        i = i + ( c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4 )
    end

    return starts
end

utf8 = {
    len = function( s ) return #charStarts( s ) end,
    offset = function( s, n )
        local st = charStarts( s )
        if n > 0 then return st[n] or ( n == #st + 1 and #s + 1 or nil ) end

        return st[#st + n + 1]
    end
}

--[[ Vector / Angle with Source conventions ]]

local Vec = {}
Vec.__index = Vec
local function Vector( x, y, z ) return setmetatable( { x = x or 0, y = y or 0, z = z or 0 }, Vec ) end
Vec.__add = function( a, b ) return Vector( a.x + b.x, a.y + b.y, a.z + b.z ) end
Vec.__sub = function( a, b ) return Vector( a.x - b.x, a.y - b.y, a.z - b.z ) end
Vec.__mul = function( a, b )
    if type( a ) == "number" then a, b = b, a end

    return Vector( a.x * b, a.y * b, a.z * b )
end
function Vec:Dot( b ) return self.x * b.x + self.y * b.y + self.z * b.z end
function Vec:Length() return math.sqrt( self:Dot( self ) ) end
function Vec:Distance( b ) return ( self - b ):Length() end
function Vec:DistToSqr( b ) local d = self - b return d:Dot( d ) end
function Vec:GetNormalized() return self * ( 1 / self:Length() ) end
local function cross( a, b ) return Vector( a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x ) end

local Ang = {}
Ang.__index = Ang
local function Angle( p, y, r ) return setmetatable( { p = p or 0, y = y or 0, r = r or 0 }, Ang ) end
local rad, deg = math.rad, math.deg
function Ang:Forward()
    local sp, cp, sy, cy = math.sin( rad( self.p ) ), math.cos( rad( self.p ) ), math.sin( rad( self.y ) ), math.cos( rad( self.y ) )

    return Vector( cp * cy, cp * sy, -sp )
end
function Ang:Right()
    local sp, cp = math.sin( rad( self.p ) ), math.cos( rad( self.p ) )
    local sy, cy = math.sin( rad( self.y ) ), math.cos( rad( self.y ) )
    local sr, cr = math.sin( rad( self.r ) ), math.cos( rad( self.r ) )

    return Vector( -sr * sp * cy + cr * sy, -sr * sp * sy - cr * cy, -sr * cp )
end
function Ang:Up()
    local sp, cp = math.sin( rad( self.p ) ), math.cos( rad( self.p ) )
    local sy, cy = math.sin( rad( self.y ) ), math.cos( rad( self.y ) )
    local sr, cr = math.sin( rad( self.r ) ), math.cos( rad( self.r ) )

    return Vector( cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp )
end
-- Right-hand rotation of the basis, then back to pitch/yaw/roll.
function Ang:RotateAroundAxis( axis, degrees )
    local k = axis:GetNormalized()
    local t = rad( degrees )
    local function rot( v ) return v * math.cos( t ) + cross( k, v ) * math.sin( t ) + k * ( k:Dot( v ) * ( 1 - math.cos( t ) ) ) end
    local f, r, u = rot( self:Forward() ), rot( self:Right() ), rot( self:Up() )
    self.p = deg( math.asin( -f.z ) )
    self.y = deg( math.atan2( f.y, f.x ) )
    self.r = deg( math.atan2( -r.z, u.z ) )
end

M.Vector, M.Angle = Vector, Angle

--[[ Net bus ]]

local Bus = {}
Bus.__index = Bus
function M.newBus() return setmetatable( { outbox = {} }, Bus ) end

local function netLib( bus, realm )
    local net, writing, reading = {}, nil, nil
    local receivers = {}
    net.receivers = receivers

    function net.Start( name ) writing = { name = name, data = {} } end
    local function w( kind, bits ) return function( v ) writing.data[#writing.data + 1] = { kind = kind, bits = bits, v = v } end end
    function net.WriteUInt( v, bits )
        assert( v == math.floor( v ) and v >= 0 and v < 2 ^ bits, ( "WriteUInt out of range: %s in %d bits (%s)" ):format( tostring( v ), bits, writing.name ) )
        writing.data[#writing.data + 1] = { kind = "uint", bits = bits, v = v }
    end
    function net.WriteInt( v, bits )
        assert( v == math.floor( v ) and v >= -2 ^ ( bits - 1 ) and v < 2 ^ ( bits - 1 ), "WriteInt out of range" )
        writing.data[#writing.data + 1] = { kind = "int", bits = bits, v = v }
    end
    net.WriteString = w( "string" )
    net.WriteBool = w( "bool" )
    net.WriteEntity = w( "entity" )

    local function post( to )
        writing.from = realm
        writing.to = to
        bus.outbox[#bus.outbox + 1] = writing
        writing = nil
    end
    function net.Send( ply ) post( ply ) end
    function net.Broadcast() post( "all" ) end
    function net.SendToServer() post( "server" ) end

    local function r( kind ) return function( bits )
        local item = table.remove( reading.data, 1 )
        assert( item, "read past end of " .. reading.name )
        assert( item.kind == kind and item.bits == bits,
            ( "%s: read %s/%s but wrote %s/%s" ):format( reading.name, kind, tostring( bits ), item.kind, tostring( item.bits ) ) )

        return item.v
    end end
    net.ReadUInt = r( "uint" )
    net.ReadInt = r( "int" )
    local rs, rb, re = r( "string" ), r( "bool" ), r( "entity" )
    net.ReadString = function() return rs() end
    net.ReadBool = function() return rb() end
    net.ReadEntity = function() return re() end

    function net.Receive( name, fn ) receivers[name] = fn end
    function net.Deliver( msg, ply )
        local fn = receivers[msg.name]
        assert( fn, "no receiver for " .. msg.name )
        reading = { name = msg.name, data = {} }
        for i, item in ipairs( msg.data ) do reading.data[i] = item end
        fn( 0, ply )
        assert( #reading.data == 0, msg.name .. ": " .. #reading.data .. " unread field(s)" )
        reading = nil
    end

    return net
end

--[[ Realms ]]

M.clock = { now = 1000 }
M.osTime = 1760000000

function M.newRealm( realm, bus, fs )
    local env = setmetatable( {}, { __index = _G } )
    env._G = env
    env.SERVER = realm == "server"
    env.CLIENT = realm == "client"
    env.Vector, env.Angle = Vector, Angle
    env.vector_origin, env.angle_zero = Vector(), Angle()
    env.isstring = function( v ) return type( v ) == "string" end
    env.istable = function( v ) return type( v ) == "table" end
    env.isnumber = function( v ) return type( v ) == "number" end
    env.isfunction = function( v ) return type( v ) == "function" end
    env.IsValid = function( o )
        if o == nil or o == false then return false end
        if type( o ) == "table" and o.IsValid then return o:IsValid() end

        return true
    end
    env.Color = function( r, g, b, a ) return { r = r, g = g, b = b, a = a or 255 } end
    env.CurTime = function() return M.clock.now end
    env.os = setmetatable( { time = function() return M.osTime end }, { __index = os } )
    env.printed = {}
    env.print = function( ... )
        local parts = {}
        for i = 1, select( "#", ... ) do parts[i] = tostring( select( i, ... ) ) end
        env.printed[#env.printed + 1] = table.concat( parts, " " )
    end
    env.AddCSLuaFile = function() end
    env.resource = { AddFile = function() end }
    env.FCVAR_ARCHIVE, env.FCVAR_REPLICATED = 128, 8192

    env.convars = {}
    env.CreateConVar = function( name, default )
        local cv = { value = tostring( default ) }
        function cv:GetInt() return math.floor( tonumber( self.value ) or 0 ) end
        function cv:GetBool() return self:GetInt() ~= 0 end
        env.convars[name] = cv

        return cv
    end
    env.GetConVar = function( name ) return env.convars[name] end

    env.hooks = {}
    env.GM = {}
    env.hook = {
        Add = function( event, id, fn ) env.hooks[event] = env.hooks[event] or {} env.hooks[event][id] = fn end,
        Run = function( event, ... )
            for _, fn in pairs( env.hooks[event] or {} ) do
                local a, b = fn( ... )
                if a ~= nil then return a, b end
            end
            if env.GM[event] then return env.GM[event]( env.GM, ... ) end
        end
    }

    env.timers = {}
    env.timer = {
        Create = function( name, delay, reps, fn ) env.timers[name] = { at = M.clock.now + delay, delay = delay, reps = reps, fn = fn } end,
        Exists = function( name ) return env.timers[name] ~= nil end,
        Simple = function( delay, fn ) env.timers[{}] = { at = M.clock.now + delay, delay = delay, reps = 1, fn = fn } end
    }
    -- Fires every timer due by now; repeats reschedule.
    function env.RunTimers()
        local fired = true
        while fired do
            fired = false
            for name, t in pairs( env.timers ) do
                if t.at <= M.clock.now then
                    fired = true
                    if t.reps == 1 then env.timers[name] = nil else t.at = t.at + t.delay end
                    t.fn()
                    break
                end
            end
        end
    end

    env.util = {
        AddNetworkString = function() end,
        TableToJSON = function( t ) return cjson.encode( t ) end,
        JSONToTable = function( s )
            local ok, v = pcall( cjson.decode, s )
            if ok then return v end
        end,
        IntersectRayWithPlane = function( origin, dir, planePos, normal )
            local denom = dir:Dot( normal )
            if math.abs( denom ) < 1e-9 then return nil end
            local t = ( planePos - origin ):Dot( normal ) / denom
            if t < 0 then return nil end

            return origin + dir * t, t
        end
    }

    fs = fs or {}
    env.fs = fs
    env.file = {
        Read = function( path ) return fs[path] end,
        Write = function( path, data ) fs[path] = data return true end,
        Exists = function( path ) return fs[path] ~= nil end,
        Delete = function( path ) fs[path] = nil end,
        Rename = function( a, b ) fs[b] = fs[a] fs[a] = nil return true end,
        CreateDir = function() end
    }

    env.net = netLib( bus, realm )
    env.players = {}
    env.player = {
        Iterator = function() return ipairs( env.players ) end,
        GetAll = function() return env.players end
    }
    env.concommands = {}
    env.concommand = { Add = function( name, fn ) env.concommands[name] = fn end }
    env.properties = {
        list = {},
        Add = function( name, tab ) env.properties.list[name] = tab end,
        CanBeTargeted = function() return true end
    }
    env.gamemode = { Call = function() return true end }
    env.ents = { FindByClass = function() return env.boards or {} end }

    function env.include( path, base )
        local full = M.ROOT .. path
        local f = io.open( full )
        base = base or env.includeBase
        if not f and base then full = base .. path f = io.open( full ) end
        assert( f, "include: no file " .. path )
        f:close()
        local chunk = assert( loadfile( full ) )
        setfenv( chunk, env )

        return chunk()
    end

    return env
end

--[[ Fake players ]]

function M.newPlayer( nick, sid64, opts )
    opts = opts or {}
    local ply = { nick = nick, sid64 = sid64, bot = opts.bot, admin = opts.admin, superadmin = opts.superadmin, chat = {} }
    function ply:Nick() return self.nick end
    function ply:SteamID64() return self.sid64 end
    function ply:SteamID() return opts.sid32 or "STEAM_0:0:" .. sid64:sub( -6 ) end
    function ply:IsBot() return self.bot == true end
    function ply:IsPlayer() return true end
    function ply:IsVehicle() return false end
    function ply:IsValid() return not self.removed end
    function ply:IsAdmin() return self.admin or self.superadmin end
    function ply:IsSuperAdmin() return self.superadmin end
    function ply:ChatPrint( s ) self.chat[#self.chat + 1] = s end

    return ply
end

function M.newNpc( class, opts )
    local npc = { class = class, PrintName = opts and opts.PrintName, hp = 0, nextbot = opts and opts.nextbot }
    function npc:IsValid() return true end
    function npc:GetClass() return self.class end
    function npc:IsPlayer() return false end
    function npc:IsNextBot() return self.nextbot == true end
    function npc:Health() return self.hp end

    return npc
end

M.cjson = cjson
M.HERE = HERE

return M
