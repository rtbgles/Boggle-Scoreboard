include( "shared.lua" )

surface.CreateFont( "BoggleKills_Brand", { font = "Trebuchet MS", size = 42, weight = 800, antialias = true } )
surface.CreateFont( "BoggleKills_Sub", { font = "Tahoma", size = 16, weight = 700, antialias = true } )
surface.CreateFont( "BoggleKills_Head", { font = "Tahoma", size = 16, weight = 700, antialias = true } )
surface.CreateFont( "BoggleKills_Row", { font = "Tahoma", size = 25, weight = 600, antialias = true } )
surface.CreateFont( "BoggleKills_Num", { font = "Tahoma", size = 21, weight = 600, antialias = true } )
surface.CreateFont( "BoggleKills_Key", { font = "Tahoma", size = 25, weight = 800, antialias = true } )
surface.CreateFont( "BoggleKills_Stat", { font = "Trebuchet MS", size = 30, weight = 800, antialias = true } )
surface.CreateFont( "BoggleKills_Badge", { font = "Tahoma", size = 18, weight = 800, antialias = true } )
surface.CreateFont( "BoggleKills_Tab", { font = "Tahoma", size = 15, weight = 800, antialias = true } )
surface.CreateFont( "BoggleKills_Ticker", { font = "Tahoma", size = 17, weight = 700, antialias = true } )
surface.CreateFont( "BoggleKills_Small", { font = "Tahoma", size = 14, weight = 700, antialias = true } )

local PAGE_TOTAL = BoggleKills.PAGE_TOTAL
local PAGE_PLAYERS = BoggleKills.PAGE_PLAYERS
local PAGE_NPCS = BoggleKills.PAGE_NPCS
local PAGE_STREAK = BoggleKills.PAGE_STREAK
local PAGE_KD = BoggleKills.PAGE_KD
local PAGE_COUNT = BoggleKills.PAGE_COUNT
local VIEW_DEFAULT = BoggleKills.VIEW_DEFAULT

local BOARD_W, BOARD_H = ENT.BoardW, ENT.BoardH

local cvMode = GetConVar( "boggle_kills_board_mode" )
local cvKdMin = GetConVar( "boggle_kills_kd_min" )

-- Fade band in world units (linear, so the fade feels even across the band).
local NEAR = 700
local FAR = 1600
local MIN_ALPHA = 0.05
local REQUEST_INTERVAL = 30
local THINK_INTERVAL = 5

-- Page timing, in seconds. The lifetime page is the one people come to read.
local DWELL_TOTAL = 20
local DWELL_OTHER = 8
local PAGE_FADE = 0.35
local PEEK_HOLD = 30   -- how long a page flipped with the use key stays up
local FLIP_RANGE = 300
local FLASH_TIME = 1.6
local LIVE_MIN = 3     -- current streak that earns a badge next to a name

-- The prop is a small cube but the board is ~148 x 101 units, so without wider
-- render bounds the board vanishes whenever the cube itself leaves the screen.
local RENDER_MINS = Vector( -8, -160, -110 )
local RENDER_MAXS = Vector( 8, 160, 24 )

-- Layout (board pixels). The board keeps its 2.0 size; sections are re-divided.
local HEADER_H = 90
local TABS_Y, TABS_H = 90, 26
local COLUMNS_Y, COLUMNS_H = 116, 24
local ROWS_TOP, ROWS_BOTTOM = 142, 488
local ROW_MAX_H = 42
local TICKER_Y, TICKER_H = 490, 30
local FOOTER_H = 38
local EDGE = 14

local X_RANK = 36 -- badge centre
local BADGE_W, BADGE_H = 38, 24
local X_DOT = 70
local X_NAME = 82
local X_KEY = 804
local COLUMN_W = 74
-- Right edges of the supporting columns, filled from the key column leftwards.
-- 88 apart leaves room for six-digit counts side by side.
local COLUMN_SLOTS = { 674, 586, 498, 410 }
local FOOTER_LEFT = EDGE + 52 -- right of the "YOU" tag
local DECO_GAP = 8
local ARROW = 9
local PILL_PAD = 6

-- Palette: the 2.0 colours, plus medals, movement and a few animated ones.
local BG = Color( 8, 8, 10, 245 )
local HEADER_BG = Color( 16, 8, 8 )
local HEADER_SHADE = Color( 0, 0, 0, 90 )
local ACCENT = Color( 180, 24, 28 )
local ACCENT_SOFT = Color( 180, 24, 28, 120 )
local ACCENT_FILL = Color( 180, 24, 28, 40 )
local BAR = Color( 180, 24, 28, 34 )
local SHEEN = Color( 255, 150, 150, 170 )
local SUB = Color( 220, 60, 60 )
local META = Color( 200, 180, 180 )
local MUTED = Color( 150, 125, 125 )
local COL_HEAD_BG = Color( 0, 0, 0, 70 )
local COL_HEAD = Color( 170, 140, 140 )
local TAB_FILL = Color( 255, 255, 255, 10 )
local TAB_TRACK = Color( 180, 24, 28, 70 )
local STRIPE = Color( 255, 255, 255, 8 )
local SELF_FILL = Color( 255, 255, 255, 22 )
local FLASH = Color( 255, 90, 70, 0 )
local RANK = Color( 200, 170, 170 )
local LEADER = Color( 255, 80, 80 )
local PLAYERS = Color( 230, 70, 70 )
local NPCS = Color( 220, 160, 80 )
local FLAME = Color( 255, 128, 40 )
local KD = Color( 215, 205, 230 )
local WHITE = Color( 255, 255, 255 )
local DARK = Color( 28, 16, 12 )
local EMPTY = Color( 180, 160, 160 )
local ONLINE = Color( 90, 210, 110 )
local MOVE_UP = Color( 90, 210, 110 )
local MOVE_DOWN = Color( 230, 80, 80 )
local MOVE_NEW = Color( 110, 190, 255 )
local LIVE_DOT = Color( 255, 255, 255 )
local MEDALS = { Color( 236, 184, 72 ), Color( 196, 202, 210 ), Color( 205, 127, 70 ) }
local MEDAL_SHADE = Color( 0, 0, 0, 70 )

local LOGO = Material( "boggle_kills/logo.png", "smooth noclamp" )
-- The suffix names the opaque side of these stock gradients.
local GRAD_L = Material( "vgui/gradient-l" )
local GRAD_R = Material( "vgui/gradient-r" )
local GRAD_D = Material( "vgui/gradient-d" )

local comma = string.Comma

local function kd( value )
    return string.format( "%.2f", value )
end

-- Most rows have no streak yet; a dash reads better than a column of zeros.
local function streak( value )
    return value > 0 and comma( value ) or "-"
end

--[[
    Page definitions. Each page ranks by its key column (drawn largest, at the
    right edge) and shows up to four supporting columns.
]]
local PAGES = {
    [PAGE_TOTAL] = {
        tab = "LIFETIME",
        key = { label = "TOTAL", field = "total", color = WHITE },
        cols = {
            { label = "PLAYERS", field = "pkills", color = PLAYERS },
            { label = "NPCS", field = "nkills", color = NPCS },
            { label = "DEATHS", field = "deaths", color = RANK },
            { label = "K/D", field = "kd", color = KD, format = kd }
        },
        empty = "No records yet"
    },
    [PAGE_PLAYERS] = {
        tab = "PLAYERS",
        sub = "Most players killed",
        key = { label = "PLAYERS", field = "pkills", color = PLAYERS },
        cols = {
            { label = "NPCS", field = "nkills", color = NPCS },
            { label = "DEATHS", field = "deaths", color = RANK },
            { label = "TOTAL", field = "total", color = WHITE }
        },
        empty = "No player kills yet"
    },
    [PAGE_NPCS] = {
        tab = "NPCS",
        sub = "Most NPCs killed",
        key = { label = "NPCS", field = "nkills", color = NPCS },
        cols = {
            { label = "PLAYERS", field = "pkills", color = PLAYERS },
            { label = "DEATHS", field = "deaths", color = RANK },
            { label = "TOTAL", field = "total", color = WHITE }
        },
        empty = "No NPC kills yet"
    },
    [PAGE_STREAK] = {
        tab = "STREAKS",
        sub = "Longest kill streaks (kills in one life)",
        key = { label = "BEST", field = "streak", color = FLAME },
        cols = {
            { label = "NOW", field = "live", color = FLAME, format = streak },
            { label = "DEATHS", field = "deaths", color = RANK },
            { label = "TOTAL", field = "total", color = WHITE }
        },
        empty = "No kill streaks yet"
    },
    [PAGE_KD] = {
        tab = "K/D",
        key = { label = "K/D", field = "kd", color = KD, format = kd },
        cols = {
            { label = "KILLS", field = "total", color = WHITE },
            { label = "DEATHS", field = "deaths", color = RANK },
            { label = "BEST", field = "streak", color = FLAME, format = streak }
        }
    }
}

for _, def in pairs( PAGES ) do
    local n = #def.cols
    for c, col in ipairs( def.cols ) do
        col.x = COLUMN_SLOTS[n - c + 1]
    end

    def.nameMax = def.cols[1].x - COLUMN_W - X_NAME - DECO_GAP
end

--[[ Shapes: shared vertex tables, mutated per draw instead of allocated. ]]

local triangle = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }

-- Clockwise winding, or DrawPoly culls the triangle. dir: "up", "down" or "right".
local function drawTriangle( x, y, size, dir )
    local h = size * 0.5
    local a, b, c = triangle[1], triangle[2], triangle[3]
    if dir == "up" then
        a.x, a.y, b.x, b.y, c.x, c.y = x, y - h, x + h, y + h, x - h, y + h
    elseif dir == "down" then
        a.x, a.y, b.x, b.y, c.x, c.y = x - h, y - h, x + h, y - h, x, y + h
    else
        a.x, a.y, b.x, b.y, c.x, c.y = x - h, y - h, x + h, y, x - h, y + h
    end

    surface.DrawPoly( triangle )
end

local CIRCLE_SEGMENTS = 12
local circle, unitCircle = {}, {}
for i = 1, CIRCLE_SEGMENTS do
    local a = ( i - 1 ) / CIRCLE_SEGMENTS * math.pi * 2
    unitCircle[i] = { math.cos( a ), math.sin( a ) }
    circle[i] = { x = 0, y = 0 }
end

local function drawCircle( x, y, r )
    for i, v in ipairs( circle ) do
        v.x = x + unitCircle[i][1] * r
        v.y = y + unitCircle[i][2] * r
    end

    surface.DrawPoly( circle )
end

--[[ Text cache: every board shows the same data, so measure once per update. ]]

local function textW( font, text )
    surface.SetFont( font )

    return ( surface.GetTextSize( text ) )
end

local function fit( font, text, maxW )
    surface.SetFont( font )
    if surface.GetTextSize( text ) <= maxW then return text end

    while #text > 1 and surface.GetTextSize( text .. "…" ) > maxW do
        local lastChar = utf8.offset( text, -1 ) or #text
        text = string.sub( text, 1, lastChar - 1 )
    end

    return text .. "…"
end

local function pageSubtitle( page, kdMin )
    if page == PAGE_TOTAL then return BoggleKills.Config.Subtitle end
    if page == PAGE_KD then return "Kills per death (min. " .. comma( kdMin ) .. " kills)" end

    return PAGES[page].sub
end

local function pageEmpty( page, kdMin )
    if page == PAGE_KD then return "Nobody has " .. comma( kdMin ) .. " kills yet" end

    return PAGES[page].empty
end

local function buildRow( page, def, i, row, top, mySlot )
    local value = row[def.key.field]
    local r = {
        row = row,
        rank = i <= 3 and tostring( i ) or string.format( "%02d", i ),
        medal = MEDALS[i],
        key = ( def.key.format or comma )( value ),
        bar = top > 0 and math.min( value / top, 1 ) or 0,
        isSelf = mySlot > 0 and row.slot == mySlot,
        cols = {}
    }

    for c, col in ipairs( def.cols ) do
        r.cols[c] = ( col.format or comma )( row[col.field] )
    end

    -- Movement since the map started, then a live streak badge, after the name.
    local deco = 0
    if page == PAGE_TOTAL and ( row.fresh or row.move ~= 0 ) then
        r.move = row.fresh and "NEW" or tostring( math.abs( row.move ) )
        r.moveDir = row.fresh and "new" or ( row.move > 0 and "up" or "down" )
        r.moveW = textW( "BoggleKills_Small", r.move ) + ( row.fresh and 0 or ARROW + 3 )
        deco = deco + DECO_GAP + r.moveW
    end

    if page ~= PAGE_STREAK and row.live >= LIVE_MIN then
        r.live = comma( row.live ) .. " STREAK"
        r.liveW = textW( "BoggleKills_Small", r.live ) + PILL_PAD * 2
        deco = deco + DECO_GAP + r.liveW
    end

    r.name = fit( "BoggleKills_Row", row.name, def.nameMax - deco )
    r.nameW = textW( "BoggleKills_Row", r.name )

    return r
end

local function buildPage( page, list, mySlot, kdMin )
    local def = PAGES[page]
    local top = list[1] and list[1][def.key.field] or 0
    local rows = {}
    for i, row in ipairs( list ) do
        rows[i] = buildRow( page, def, i, row, top, mySlot )
    end

    return { def = def, rows = rows, sub = pageSubtitle( page, kdMin ), empty = pageEmpty( page, kdMin ) }
end

-- The player's own stats. Higher priority numbers are dropped first if the line
-- wouldn't fit; rank and kills always stay.
local function buildFooter( me, maxW )
    if me.rank <= 0 then
        return { text = "Unranked. Get a kill to join the board." }
    end

    local cells = {
        { value = "#" .. comma( me.rank ), label = "RANK", color = WHITE, priority = 0 },
        { value = comma( me.total ), label = "KILLS", color = WHITE, priority = 0 },
        { value = comma( me.pkills ), label = "PLAYERS", color = PLAYERS, priority = 1 },
        { value = comma( me.nkills ), label = "NPCS", color = NPCS, priority = 1 },
        { value = comma( me.deaths ), label = "DEATHS", color = RANK, priority = 1 },
        { value = kd( me.total / math.max( me.deaths, 1 ) ), label = "K/D", color = KD, priority = 3 },
        { value = comma( me.streak ), label = "BEST", color = FLAME, priority = 4 }
    }
    if me.live > 0 then
        table.insert( cells, 3, { value = comma( me.live ), label = "STREAK", color = FLAME, priority = 2 } )
    end

    local gap = 18
    local function width()
        local total = 0
        for _, cell in ipairs( cells ) do
            total = total + cell.w + gap
        end

        return total - gap
    end

    for _, cell in ipairs( cells ) do
        cell.valueW = textW( "BoggleKills_Badge", cell.value )
        cell.w = cell.valueW + 5 + textW( "BoggleKills_Small", cell.label )
    end

    for priority = 4, 1, -1 do
        if width() <= maxW then break end

        for i = #cells, 1, -1 do
            if cells[i].priority == priority then
                table.remove( cells, i )
            end
        end
    end

    return { cells = cells, gap = gap, width = width() }
end

local cache = { revision = -1 }

local function textCache()
    local kdMin = cvKdMin:GetInt()
    if cache.revision == BoggleKills.Revision and cache.kdMin == kdMin then return cache end

    local me = BoggleKills.Me
    local pages, order, available = {}, {}, {}
    for page = 1, PAGE_COUNT do
        local list = BoggleKills.Lists[page] or {}
        pages[page] = buildPage( page, list, me.slot or 0, kdMin )
        if #list > 0 then
            order[#order + 1] = page
            available[page] = true
        end
    end

    local cycle = 0
    for _, page in ipairs( order ) do
        cycle = cycle + ( page == PAGE_TOTAL and DWELL_TOTAL or DWELL_OTHER )
    end

    local tabs = {}
    for page, def in ipairs( PAGES ) do
        tabs[page] = { text = def.tab, w = textW( "BoggleKills_Tab", def.tab ) }
    end

    local key = input.LookupBinding( "+use" )
    local hintKey = key and string.upper( key ) or "USE"

    cache = {
        revision = BoggleKills.Revision,
        kdMin = kdMin,
        pages = pages,
        order = order,
        available = available,
        cycle = cycle,
        tabs = tabs,
        footer = buildFooter( me, BOARD_W - FOOTER_LEFT - EDGE - 16 ),
        hintKey = hintKey,
        hintKeyW = textW( "BoggleKills_Small", hintKey ) + 10
    }

    return cache
end

local function age( seconds )
    if seconds < 60 then return math.floor( seconds ) .. "s" end
    if seconds < 3600 then return math.floor( seconds / 60 ) .. "m" end

    return math.floor( seconds / 3600 ) .. "h"
end

local function buildTicker( now )
    local items = {}
    for i, ev in ipairs( BoggleKills.Feed ) do
        local victim = ev.npc and BoggleKills.NpcName( ev.victim ) or ev.victim
        local item = {
            killer = fit( "BoggleKills_Ticker", ev.killer, 150 ),
            victim = fit( "BoggleKills_Ticker", victim, 150 ),
            age = age( math.max( now - ev.time, 0 ) ),
            npc = ev.npc,
            fresh = i == 1 and now - ev.time < FLASH_TIME
        }
        item.killerW = textW( "BoggleKills_Ticker", item.killer )
        item.victimW = textW( "BoggleKills_Ticker", item.victim )
        item.ageW = textW( "BoggleKills_Small", item.age )
        item.w = item.killerW + 22 + item.victimW + 8 + item.ageW
        items[i] = item
    end

    return items
end

-- Header totals and the ticker change with every kill, so they're cached apart
-- from the pages: rebuilt when the feed updates, and once a second for the ages.
local live = { revision = -1, second = -1 }

local function liveCache( now )
    local second = math.floor( now )
    if live.revision == BoggleKills.FeedRevision and live.second == second then return live end

    local totals = BoggleKills.Totals
    local stats = {
        { value = comma( totals.kills ), label = "TOTAL KILLS" },
        { value = comma( totals.fighters ), label = "FIGHTERS" }
    }
    local statsLeft = X_KEY
    for _, stat in ipairs( stats ) do
        stat.right = statsLeft
        stat.w = math.max( textW( "BoggleKills_Stat", stat.value ), textW( "BoggleKills_Small", stat.label ) )
        statsLeft = statsLeft - stat.w - 30
    end

    live = {
        revision = BoggleKills.FeedRevision,
        second = second,
        stats = stats,
        brand = fit( "BoggleKills_Brand", BoggleKills.Config.Brand, statsLeft + 30 - 24 - 96 ),
        items = buildTicker( now )
    }

    return live
end

--[[ Page selection ]]

local function rotation( data, now )
    local order = data.order
    if #order == 0 then return PAGE_TOTAL, nil, now end

    local t = now % data.cycle
    for _, page in ipairs( order ) do
        local dwell = page == PAGE_TOTAL and DWELL_TOTAL or DWELL_OTHER
        if t < dwell then return page, t / dwell, t end
        t = t - dwell
    end

    return order[1], nil, now
end

-- The page this board shows now, how far through its turn it is (nil when it
-- isn't rotating) and how long it has been up.
function ENT:CurrentPage( data, now )
    if self.BK_PeekPage then
        if now < self.BK_PeekUntil then
            return self.BK_PeekPage, nil, now - self.BK_PeekAt
        end

        self.BK_PeekPage = nil
        self.BK_LastView = nil
    end

    local view = self:GetView()
    if view == VIEW_DEFAULT then
        view = cvMode:GetInt()
    end

    if view >= 1 and view <= PAGE_COUNT then
        if view ~= self.BK_LastView then
            self.BK_LastView = view
            self.BK_ViewAt = now
        end

        return view, nil, now - self.BK_ViewAt
    end

    self.BK_LastView = nil

    return rotation( data, now )
end

-- Use key while looking at the board: show the next page for a while.
function ENT:Flip()
    local data = textCache()
    local order = data.order
    if #order == 0 then return end

    local now = CurTime()
    local current = self:CurrentPage( data, now )
    local nextPage = order[1]
    for i, page in ipairs( order ) do
        if page == current then
            nextPage = order[i % #order + 1]
            break
        end
    end

    self.BK_PeekPage = nextPage
    self.BK_PeekAt = now
    self.BK_PeekUntil = now + PEEK_HOLD
    surface.PlaySound( "buttons/lightswitch2.wav" )
end

hook.Add( "PlayerBindPress", "BoggleKills_Flip", function( ply, bind, pressed )
    if not pressed or not string.find( bind, "+use", 1, true ) then return end

    local board = BoggleKills.BoardAt( ply, FLIP_RANGE )
    if IsValid( board ) then
        board:Flip()
    end
end )

--[[ Painting ]]

local function paintHeader( w, h, data, liveData, page, fade, alpha )
    surface.SetDrawColor( BG )
    surface.DrawRect( 0, 0, w, h )
    surface.SetDrawColor( HEADER_BG )
    surface.DrawRect( 0, 0, w, HEADER_H )

    if not GRAD_D:IsError() then
        surface.SetDrawColor( HEADER_SHADE )
        surface.SetMaterial( GRAD_D )
        surface.DrawTexturedRect( 0, 0, w, HEADER_H )
    end

    surface.SetDrawColor( ACCENT )
    surface.DrawRect( 0, 0, w, 5 )

    -- A highlight sweeps along the accent bar every few seconds.
    if not GRAD_L:IsError() and not GRAD_R:IsError() then
        local sweep = ( CurTime() % 7 ) / 7 * ( w + 320 ) - 160
        surface.SetDrawColor( SHEEN )
        surface.SetMaterial( GRAD_R )
        surface.DrawTexturedRect( sweep - 160, 0, 160, 5 )
        surface.SetMaterial( GRAD_L )
        surface.DrawTexturedRect( sweep, 0, 160, 5 )
    end

    surface.SetDrawColor( ACCENT_SOFT )
    surface.DrawRect( 0, HEADER_H - 1, w, 1 )

    if not LOGO:IsError() then
        surface.SetDrawColor( WHITE )
        surface.SetMaterial( LOGO )
        surface.DrawTexturedRect( 14, 12, 66, 66 )
    end

    draw.SimpleText( liveData.brand, "BoggleKills_Brand", 96, 34, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

    surface.SetAlphaMultiplier( alpha * fade )
    draw.SimpleText( data.pages[page].sub, "BoggleKills_Sub", 96, 66, SUB, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
    surface.SetAlphaMultiplier( alpha )

    for i, stat in ipairs( liveData.stats ) do
        draw.SimpleText( stat.value, "BoggleKills_Stat", stat.right, 38, WHITE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
        draw.SimpleText( stat.label, "BoggleKills_Small", stat.right, 64, MUTED, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
        if i > 1 then
            surface.SetDrawColor( ACCENT_SOFT )
            surface.DrawRect( stat.right + 15, 22, 1, 48 )
        end
    end
end

-- The active tab gets a fill and an underline that doubles as the rotation timer.
local function paintTab( tab, x, mid, active, progress )
    if active then
        surface.SetDrawColor( TAB_FILL )
        surface.DrawRect( x - 8, TABS_Y + 2, tab.w + 16, TABS_H - 2 )
        surface.SetDrawColor( progress and TAB_TRACK or ACCENT )
        surface.DrawRect( x - 8, TABS_Y + TABS_H - 3, tab.w + 16, 3 )
        if progress then
            surface.SetDrawColor( ACCENT )
            surface.DrawRect( x - 8, TABS_Y + TABS_H - 3, ( tab.w + 16 ) * progress, 3 )
        end
    end

    draw.SimpleText( tab.text, "BoggleKills_Tab", x, mid, active and WHITE or COL_HEAD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

    return x + tab.w + 30
end

local function paintTabs( w, data, page, progress, hint )
    local mid = TABS_Y + TABS_H * 0.5
    local x = EDGE + 6
    for p = 1, PAGE_COUNT do
        -- A pinned page keeps its tab even while it has no rows.
        if data.available[p] or p == page then
            x = paintTab( data.tabs[p], x, mid, p == page, progress )
        end
    end

    if hint and #data.order > 1 then
        local labelX = w - EDGE - 2
        draw.SimpleText( "NEXT PAGE", "BoggleKills_Small", labelX, mid, META, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
        local keyRight = labelX - textW( "BoggleKills_Small", "NEXT PAGE" ) - 6
        surface.SetDrawColor( META )
        surface.DrawOutlinedRect( keyRight - data.hintKeyW, mid - 9, data.hintKeyW, 18, 1 )
        draw.SimpleText( data.hintKey, "BoggleKills_Small", keyRight - data.hintKeyW * 0.5, mid, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    end
end

local function paintColumns( w, def )
    local mid = COLUMNS_Y + COLUMNS_H * 0.5
    surface.SetDrawColor( COL_HEAD_BG )
    surface.DrawRect( 0, COLUMNS_Y, w, COLUMNS_H )
    draw.SimpleText( "#", "BoggleKills_Head", X_RANK, mid, COL_HEAD, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    draw.SimpleText( "NAME", "BoggleKills_Head", X_NAME, mid, COL_HEAD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
    for _, col in ipairs( def.cols ) do
        draw.SimpleText( col.label, "BoggleKills_Head", col.x, mid, COL_HEAD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
    end

    draw.SimpleText( def.key.label, "BoggleKills_Head", X_KEY, mid, def.key.color, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
end

local function paintDecorations( r, x, mid )
    if r.move then
        local color = r.moveDir == "up" and MOVE_UP or ( r.moveDir == "down" and MOVE_DOWN or MOVE_NEW )
        x = x + DECO_GAP
        if r.moveDir ~= "new" then
            draw.NoTexture()
            surface.SetDrawColor( color )
            drawTriangle( x + ARROW * 0.5, mid, ARROW, r.moveDir )
            x = x + ARROW + 3
            draw.SimpleText( r.move, "BoggleKills_Small", x, mid, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
            x = x + r.moveW - ARROW - 3
        else
            draw.SimpleText( r.move, "BoggleKills_Small", x, mid, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
            x = x + r.moveW
        end
    end

    if r.live then
        x = x + DECO_GAP
        surface.SetDrawColor( FLAME )
        surface.DrawRect( x, mid - 9, r.liveW, 18 )
        draw.SimpleText( r.live, "BoggleKills_Small", x + PILL_PAD, mid, DARK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
    end
end

local function paintRow( w, def, r, i, y, rowH, now )
    local mid = y + rowH * 0.5
    local row = r.row

    -- Each row is shaded in proportion to its score against the page leader.
    if r.bar > 0 then
        surface.SetDrawColor( i == 1 and ACCENT_FILL or BAR )
        surface.DrawRect( 0, y, math.max( math.floor( w * r.bar ), 2 ), rowH )
    end

    if i % 2 == 0 then
        surface.SetDrawColor( STRIPE )
        surface.DrawRect( 0, y, w, rowH )
    end

    if i == 1 then
        surface.SetDrawColor( ACCENT )
        surface.DrawRect( 0, y, 4, rowH )
    end

    local flash = now - row.flashAt
    if flash < FLASH_TIME then
        FLASH.a = 80 * ( 1 - flash / FLASH_TIME )
        surface.SetDrawColor( FLASH )
        surface.DrawRect( 0, y, w, rowH )
    end

    if r.isSelf then
        surface.SetDrawColor( SELF_FILL )
        surface.DrawRect( 0, y, w, rowH )
        surface.SetDrawColor( WHITE )
        surface.DrawRect( w - 4, y, 4, rowH )
    end

    if r.medal then
        local bx, by = X_RANK - BADGE_W * 0.5, math.floor( mid - BADGE_H * 0.5 )
        surface.SetDrawColor( r.medal )
        surface.DrawRect( bx, by, BADGE_W, BADGE_H )
        surface.SetDrawColor( MEDAL_SHADE )
        surface.DrawRect( bx, by + BADGE_H - 3, BADGE_W, 3 )
        draw.SimpleText( r.rank, "BoggleKills_Badge", X_RANK, mid - 1, DARK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    else
        draw.SimpleText( r.rank, "BoggleKills_Num", X_RANK, mid, RANK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    end

    if row.online then
        draw.NoTexture()
        surface.SetDrawColor( ONLINE )
        drawCircle( X_DOT, mid, 4 )
    end

    draw.SimpleText( r.name, "BoggleKills_Row", X_NAME, mid, i == 1 and LEADER or WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
    paintDecorations( r, X_NAME + r.nameW, mid )

    for c, col in ipairs( def.cols ) do
        draw.SimpleText( r.cols[c], "BoggleKills_Num", col.x, mid, col.color, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
    end

    draw.SimpleText( r.key, "BoggleKills_Key", X_KEY, mid, def.key.color, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
end

local function paintRows( w, info, now )
    local rows = info.rows
    if #rows == 0 then
        draw.SimpleText( info.empty, "BoggleKills_Row", w * 0.5, ( ROWS_TOP + ROWS_BOTTOM ) * 0.5, EMPTY, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

        return
    end

    local rowH = math.floor( math.min( ROW_MAX_H, ( ROWS_BOTTOM - ROWS_TOP ) / #rows ) )
    for i, r in ipairs( rows ) do
        paintRow( w, info.def, r, i, ROWS_TOP + ( i - 1 ) * rowH, rowH, now )
    end
end

local function paintTicker( w, liveData, now )
    local mid = TICKER_Y + TICKER_H * 0.5
    surface.SetDrawColor( COL_HEAD_BG )
    surface.DrawRect( 0, TICKER_Y, w, TICKER_H )

    surface.SetDrawColor( ACCENT )
    surface.DrawRect( EDGE, mid - 9, 56, 18 )
    LIVE_DOT.a = 120 + 135 * math.abs( math.sin( now * 3 ) )
    draw.NoTexture()
    surface.SetDrawColor( LIVE_DOT )
    drawCircle( EDGE + 10, mid, 3 )
    draw.SimpleText( "LIVE", "BoggleKills_Small", EDGE + 18, mid, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

    local x = EDGE + 56 + 16
    if #liveData.items == 0 then
        draw.SimpleText( "Waiting for the next kill…", "BoggleKills_Ticker", x, mid, MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

        return
    end

    for _, item in ipairs( liveData.items ) do
        if x + item.w > w - EDGE then break end

        draw.SimpleText( item.killer, "BoggleKills_Ticker", x, mid, item.fresh and LEADER or WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
        x = x + item.killerW + 7
        draw.NoTexture()
        surface.SetDrawColor( ACCENT )
        drawTriangle( x + 4, mid, 8, "right" )
        x = x + 15
        draw.SimpleText( item.victim, "BoggleKills_Ticker", x, mid, item.npc and NPCS or PLAYERS, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
        x = x + item.victimW + 8
        draw.SimpleText( item.age, "BoggleKills_Small", x, mid + 1, MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
        x = x + item.ageW + 26
    end
end

local function paintFooter( w, h, data )
    local y = h - FOOTER_H
    local mid = y + FOOTER_H * 0.5
    surface.SetDrawColor( COL_HEAD_BG )
    surface.DrawRect( 0, y, w, FOOTER_H )
    surface.SetDrawColor( ACCENT_SOFT )
    surface.DrawRect( 0, y, w, 1 )

    surface.SetDrawColor( WHITE )
    surface.DrawRect( EDGE, mid - 10, 52, 20 )
    draw.SimpleText( "YOU", "BoggleKills_Small", EDGE + 26, mid, DARK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

    local footer = data.footer
    local centre = FOOTER_LEFT + ( w - FOOTER_LEFT - EDGE ) * 0.5
    if footer.text then
        draw.SimpleText( footer.text, "BoggleKills_Sub", centre, mid, META, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

        return
    end

    local x = centre - footer.width * 0.5
    for _, cell in ipairs( footer.cells ) do
        draw.SimpleText( cell.value, "BoggleKills_Badge", x, mid, cell.color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
        draw.SimpleText( cell.label, "BoggleKills_Small", x + cell.valueW + 5, mid + 1, MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
        x = x + cell.w + footer.gap
    end
end

-- view: page, progress, fade, alpha (the distance fade), hint.
local function paintBoard( w, h, view )
    local data = textCache()
    local now = CurTime()
    local liveData = liveCache( now )
    local info = data.pages[view.page]

    paintHeader( w, h, data, liveData, view.page, view.fade, view.alpha )
    paintTabs( w, data, view.page, view.progress, view.hint )

    surface.SetAlphaMultiplier( view.alpha * view.fade )
    paintColumns( w, info.def )
    paintRows( w, info, now )
    surface.SetAlphaMultiplier( view.alpha )

    paintTicker( w, liveData, now )
    paintFooter( w, h, data )
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

local view = {}

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
    if ( eye - origin ):Dot( self:GetForward() ) <= 0 then return end

    local now = CurTime()
    local page, progress, elapsed = self:CurrentPage( textCache(), now )
    view.page = page
    view.progress = progress
    view.fade = math.Clamp( elapsed / PAGE_FADE, 0, 1 )
    view.alpha = alpha
    view.hint = dist < FLIP_RANGE and self:BoardTrace( eye, EyeVector(), FLIP_RANGE ) ~= nil

    local pos, ang = self:BoardFrame()

    -- One multiplier fades everything, instead of rebuilding every Color per frame.
    surface.SetAlphaMultiplier( alpha )
    cam.Start3D2D( pos, ang, self.BoardScale )
        paintBoard( self.BoardW, self.BoardH, view )
    cam.End3D2D()
    surface.SetAlphaMultiplier( 1 )
end
