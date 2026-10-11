if not CLIENT then return end

BoggleKills.List = BoggleKills.List or {}
BoggleKills.Me = BoggleKills.Me or { rank = 0, pkills = 0, nkills = 0, deaths = 0 }

-- Bumped on every update so boards know to re-measure their cached text.
BoggleKills.Revision = ( BoggleKills.Revision or 0 ) + 1

net.Receive( "BoggleKills", function()
    local rows = {}
    for i = 1, net.ReadUInt( 8 ) do
        local row = {
            name = net.ReadString(),
            pkills = net.ReadUInt( 24 ),
            nkills = net.ReadUInt( 24 ),
            deaths = net.ReadUInt( 24 )
        }
        row.total = row.pkills + row.nkills
        rows[i] = row
    end

    BoggleKills.List = rows
    BoggleKills.Revision = BoggleKills.Revision + 1
end )

net.Receive( "BoggleKills_You", function()
    local me = {
        rank = net.ReadUInt( 16 ),
        pkills = net.ReadUInt( 24 ),
        nkills = net.ReadUInt( 24 ),
        deaths = net.ReadUInt( 24 )
    }
    me.total = me.pkills + me.nkills

    BoggleKills.Me = me
    BoggleKills.Revision = BoggleKills.Revision + 1
end )

-- The client asks once it can actually receive; messages sent during
-- PlayerInitialSpawn can arrive before client Lua has loaded and be dropped.
hook.Add( "InitPostEntity", "BoggleKills_Ask", function()
    net.Start( "BoggleKills_Req" )
    net.SendToServer()
end )
