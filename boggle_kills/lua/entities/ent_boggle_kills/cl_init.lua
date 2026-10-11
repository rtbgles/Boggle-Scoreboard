include( "shared.lua" )

surface.CreateFont( "BoggleKills_Brand", { font = "Trebuchet MS", size = 42, weight = 800, antialias = true } )
surface.CreateFont( "BoggleKills_Sub", { font = "Tahoma", size = 16, weight = 700, antialias = true } )
surface.CreateFont( "BoggleKills_Head", { font = "Tahoma", size = 18, weight = 700, antialias = true } )
surface.CreateFont( "BoggleKills_Row", { font = "Tahoma", size = 26, weight = 600, antialias = true } )

local BOARD_W, BOARD_H = 820, 560
local BOARD_SCALE = 0.18
local BOARD_OFFSET_UP = 12
local BOARD_OFFSET_FORWARD = 2

-- Fade band in world units (linear, so the fade feels even across the band).
local NEAR = 700
local FAR = 1600
local MIN_ALPHA = 0.05
local REQUEST_INTERVAL = 30
local THINK_INTERVAL = 5

-- The prop is a small cube but the board is ~148 x 101 units, so without wider
-- render bounds the board vanishes whenever the cube itself leaves the screen.
local RENDER_MINS = Vector( -8, -160, -110 )
local RENDER_MAXS = Vector( 8, 160, 24 )

local HEADER_H = 92
local COLUMNS_Y = 100
local COLUMNS_H = 30
local ROWS_TOP = 136
local ROW_MAX_H = 42
local FOOTER_H = 40

local X_RANK, X_NAME = 28, 80
local X_PLAYERS, X_NPCS, X_TOTAL, X_DEATHS = 470, 580, 690, 792
local NAME_MAX_W = X_PLAYERS - X_NAME - 80

local BG = Color( 8, 8, 10, 245 )
local HEADER_BG = Color( 16, 8, 8 )
local ACCENT = Color( 180, 24, 28 )
local ACCENT_SOFT = Color( 180, 24, 28, 120 )
local ACCENT_FILL = Color( 180, 24, 28, 40 )
local SUB = Color( 220, 60, 60 )
local META = Color( 200, 180, 180 )
local COL_HEAD_BG = Color( 0, 0, 0, 70 )
local COL_HEAD = Color( 170, 140, 140 )
local STRIPE = Color( 255, 255, 255, 8 )
local SELF_FILL = Color( 255, 255, 255, 22 )
local RANK = Color( 200, 170, 170 )
local LEADER = Color( 255, 80, 80 )
local PLAYERS = Color( 230, 70, 70 )
local NPCS = Color( 220, 160, 80 )
local WHITE = Color( 255, 255, 255 )
local EMPTY = Color( 180, 160, 160 )

local LOGO = Material( "boggle_kills/logo.png", "smooth noclamp" )

--[[ Text cache: every board shows the same data, so measure once per update. ]]

local function fit( font, text, maxW )
    surface.SetFont( font )
    if surface.GetTextSize( text ) <= maxW then return text end

    while #text > 1 and surface.GetTextSize( text .. "…" ) > maxW do
        local lastChar = utf8.offset( text, -1 ) or #text
        text = string.sub( text, 1, lastChar - 1 )
    end

    return text .. "…"
end

local cache = { revision = -1 }

local function textCache()
    if cache.revision == BoggleKills.Revision then return cache end

    local rows = {}
    for i, row in ipairs( BoggleKills.List ) do
        rows[i] = {
            rank = string.format( "%02d", i ),
            name = fit( "BoggleKills_Row", row.name, NAME_MAX_W ),
            pkills = string.Comma( row.pkills ),
            nkills = string.Comma( row.nkills ),
            total = string.Comma( row.total ),
            deaths = string.Comma( row.deaths )
        }
    end

    local me = BoggleKills.Me
    local footer
    if me.rank > 0 then
        footer = string.format( "YOU  ·  #%s  ·  %s kills (%s players, %s NPCs)  ·  %s deaths",
            string.Comma( me.rank ), string.Comma( me.total ), string.Comma( me.pkills ), string.Comma( me.nkills ), string.Comma( me.deaths ) )
    else
        footer = "YOU  ·  unranked. Get a kill to join the board."
    end

    cache = {
        revision = BoggleKills.Revision,
        rows = rows,
        listed = #rows .. " listed",
        footer = footer,
        selfRank = me.rank
    }

    return cache
end

local function paintBoard( w, h )
    local data = textCache()
    local config = BoggleKills.Config

    surface.SetDrawColor( BG )
    surface.DrawRect( 0, 0, w, h )
    surface.SetDrawColor( HEADER_BG )
    surface.DrawRect( 0, 0, w, HEADER_H )
    surface.SetDrawColor( ACCENT )
    surface.DrawRect( 0, 0, w, 5 )
    surface.SetDrawColor( ACCENT_SOFT )
    surface.DrawRect( 0, HEADER_H - 1, w, 1 )

    if not LOGO:IsError() then
        surface.SetDrawColor( WHITE )
        surface.SetMaterial( LOGO )
        surface.DrawTexturedRect( 14, 14, 68, 68 )
    end

    draw.SimpleText( config.Brand, "BoggleKills_Brand", 96, 36, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
    draw.SimpleText( config.Subtitle, "BoggleKills_Sub", 96, 66, SUB, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
    draw.SimpleText( data.listed, "BoggleKills_Sub", w - 20, 48, META, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )

    local headMid = COLUMNS_Y + COLUMNS_H * 0.5
    surface.SetDrawColor( COL_HEAD_BG )
    surface.DrawRect( 0, COLUMNS_Y, w, COLUMNS_H )
    draw.SimpleText( "#", "BoggleKills_Head", X_RANK, headMid, COL_HEAD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
    draw.SimpleText( "NAME", "BoggleKills_Head", X_NAME, headMid, COL_HEAD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
    draw.SimpleText( "PLAYERS", "BoggleKills_Head", X_PLAYERS, headMid, COL_HEAD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
    draw.SimpleText( "NPCS", "BoggleKills_Head", X_NPCS, headMid, COL_HEAD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
    draw.SimpleText( "TOTAL", "BoggleKills_Head", X_TOTAL, headMid, COL_HEAD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
    draw.SimpleText( "DEATHS", "BoggleKills_Head", X_DEATHS, headMid, COL_HEAD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )

    local footerY = h - FOOTER_H
    surface.SetDrawColor( COL_HEAD_BG )
    surface.DrawRect( 0, footerY, w, FOOTER_H )
    surface.SetDrawColor( ACCENT_SOFT )
    surface.DrawRect( 0, footerY, w, 1 )
    draw.SimpleText( data.footer, "BoggleKills_Sub", w * 0.5, footerY + FOOTER_H * 0.5, META, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

    local rows = data.rows
    if #rows == 0 then
        draw.SimpleText( "No records yet", "BoggleKills_Row", w * 0.5, ( ROWS_TOP + footerY ) * 0.5, EMPTY, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

        return
    end

    local rowH = math.min( ROW_MAX_H, ( footerY - ROWS_TOP - 8 ) / #rows )
    for i, row in ipairs( rows ) do
        local y = ROWS_TOP + ( i - 1 ) * rowH
        if i == 1 then
            surface.SetDrawColor( ACCENT_FILL )
            surface.DrawRect( 0, y, w, rowH )
            surface.SetDrawColor( ACCENT )
            surface.DrawRect( 0, y, 4, rowH )
        elseif i % 2 == 0 then
            surface.SetDrawColor( STRIPE )
            surface.DrawRect( 0, y, w, rowH )
        end

        if i == data.selfRank then
            surface.SetDrawColor( SELF_FILL )
            surface.DrawRect( 0, y, w, rowH )
            surface.SetDrawColor( WHITE )
            surface.DrawRect( w - 4, y, 4, rowH )
        end

        local mid = y + rowH * 0.5
        draw.SimpleText( row.rank, "BoggleKills_Row", X_RANK, mid, RANK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
        draw.SimpleText( row.name, "BoggleKills_Row", X_NAME, mid, i == 1 and LEADER or WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
        draw.SimpleText( row.pkills, "BoggleKills_Row", X_PLAYERS, mid, PLAYERS, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
        draw.SimpleText( row.nkills, "BoggleKills_Row", X_NPCS, mid, NPCS, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
        draw.SimpleText( row.total, "BoggleKills_Row", X_TOTAL, mid, WHITE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
        draw.SimpleText( row.deaths, "BoggleKills_Row", X_DEATHS, mid, RANK, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
    end
end

function ENT:Initialize()
    self:SetRenderBounds( RENDER_MINS, RENDER_MAXS )
end

function ENT:Think()
    if #BoggleKills.List == 0 and CurTime() >= ( self.BK_NextAsk or 0 ) then
        local ply = LocalPlayer()
        if IsValid( ply ) and ply:GetShootPos():DistToSqr( self:GetPos() ) < FAR * FAR then
            self.BK_NextAsk = CurTime() + REQUEST_INTERVAL
            net.Start( "BoggleKills_Req" )
            net.SendToServer()
        end
    end

    self:SetNextClientThink( CurTime() + THINK_INTERVAL )

    return true
end

function ENT:Draw()
end

function ENT:DrawTranslucent()
    local eye = EyePos()
    local origin = self:GetPos()
    local dist = eye:Distance( origin )
    if dist >= FAR then return end

    local alpha = 1
    if dist > NEAR then
        alpha = 1 - ( dist - NEAR ) / ( FAR - NEAR )
        if alpha < MIN_ALPHA then return end
    end

    -- The readable face points along the entity's forward axis; from behind the
    -- board would draw mirrored, so skip it.
    local forward = self:GetForward()
    if ( eye - origin ):Dot( forward ) <= 0 then return end

    local ang = self:GetAngles()
    ang:RotateAroundAxis( ang:Up(), 90 )
    ang:RotateAroundAxis( ang:Forward(), 90 )
    local pos = origin + self:GetUp() * BOARD_OFFSET_UP + forward * BOARD_OFFSET_FORWARD

    -- One multiplier fades everything, instead of rebuilding every Color per frame.
    surface.SetAlphaMultiplier( alpha )
    cam.Start3D2D( pos, ang, BOARD_SCALE )
        paintBoard( BOARD_W, BOARD_H )
    cam.End3D2D()
    surface.SetAlphaMultiplier( 1 )
end
