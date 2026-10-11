-- How a board's view is chosen: a right-click (C menu) property and a console
-- command for admins, plus the "which board is this player looking at" test the
-- client also uses to flip pages with the use key.

local VIEW_DEFAULT = BoggleKills.VIEW_DEFAULT
local VIEW_ROTATE = BoggleKills.VIEW_ROTATE
local AIM_RANGE = 512

-- The board nearest along the player's aim, and where on it they're looking.
function BoggleKills.BoardAt( ply, range )
    local origin = ply:EyePos()
    local dir = ply:GetAimVector()
    local best, bestDist, bestX, bestY
    for _, board in ipairs( ents.FindByClass( "ent_boggle_kills" ) ) do
        local x, y, dist = board:BoardTrace( origin, dir, range or AIM_RANGE )
        if x and ( not bestDist or dist < bestDist ) then
            best, bestDist, bestX, bestY = board, dist, x, y
        end
    end

    return best, bestX, bestY
end

local function validView( view )
    return view == VIEW_DEFAULT or view == VIEW_ROTATE or ( view >= 1 and view <= BoggleKills.PAGE_COUNT )
end

local function choices()
    local list = {
        { view = VIEW_DEFAULT, label = "Server default" },
        { view = VIEW_ROTATE, label = "Rotate all pages" }
    }

    for page, name in ipairs( BoggleKills.PageNames ) do
        list[#list + 1] = { view = page, label = "Only " .. string.lower( name ) }
    end

    return list
end

-- The prop the board hangs from is the small (invisible) cube behind its logo.
properties.Add( "boggle_kills_view", {
    MenuLabel = "Kill Board View",
    Order = 1600,
    MenuIcon = "icon16/application_view_list.png",

    Filter = function( self, ent, ply )
        if not IsValid( ent ) or not ent.IsBoggleKills then return false end
        if not IsValid( ply ) or not ply:IsAdmin() then return false end

        return gamemode.Call( "CanProperty", ply, "boggle_kills_view", ent ) ~= false
    end,

    MenuOpen = function( self, option, ent )
        local submenu = option:AddSubMenu()
        local current = ent:GetView()
        for _, choice in ipairs( choices() ) do
            local opt = submenu:AddOption( choice.label, function()
                self:SetView( ent, choice.view )
            end )
            opt:SetRadio( true )
            opt:SetChecked( current == choice.view )
        end
    end,

    Action = function()
        -- Nothing: the submenu options call SetView.
    end,

    SetView = function( self, ent, view )
        self:MsgStart()
            net.WriteEntity( ent )
            net.WriteInt( view, 8 )
        self:MsgEnd()
    end,

    Receive = function( self, _, ply )
        local ent = net.ReadEntity()
        local view = net.ReadInt( 8 )

        if not properties.CanBeTargeted( ent, ply ) then return end
        if not self:Filter( ent, ply ) then return end
        if not validView( view ) then return end

        ent:SetView( view )
    end
} )

if CLIENT then return end

local VIEW_NAMES = { default = VIEW_DEFAULT, rotate = VIEW_ROTATE }

-- boggle_kills_view <default|rotate|1-5>, applied to the board you're looking at.
concommand.Add( "boggle_kills_view", function( ply, _, args )
    if not IsValid( ply ) or not ply:IsAdmin() then return end

    local arg = string.lower( args[1] or "" )
    local view = VIEW_NAMES[arg] or tonumber( arg )
    if not view or not validView( view ) then
        ply:ChatPrint( "[BoggleKills] usage: boggle_kills_view <default|rotate|1-5>  (1 lifetime, 2 players, 3 NPCs, 4 streaks, 5 K/D)" )

        return
    end

    local board = BoggleKills.BoardAt( ply )
    if not board then
        ply:ChatPrint( "[BoggleKills] look at a kill board first" )

        return
    end

    board:SetView( view )
    ply:ChatPrint( "[BoggleKills] board view set" )
end )
