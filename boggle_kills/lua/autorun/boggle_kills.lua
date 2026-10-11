BoggleKills = BoggleKills or {}
BoggleKills.Version = "2.1.0"

BoggleKills.Config = BoggleKills.Config or {
    Brand = "BLOODY SANDBOX",
    Subtitle = "Lifetime Kill Count (Players, NPCs)"
}

-- Board pages, in display order. The server ranks one list per page; a board
-- either rotates through them or is pinned to one.
BoggleKills.PAGE_TOTAL = 1
BoggleKills.PAGE_PLAYERS = 2
BoggleKills.PAGE_NPCS = 3
BoggleKills.PAGE_STREAK = 4
BoggleKills.PAGE_KD = 5
BoggleKills.PAGE_COUNT = 5

BoggleKills.PageNames = { "Lifetime kills", "Player kills", "NPC kills", "Best kill streaks", "K/D ratio" }

-- Per-board view (the entity's View network var). 1-5 pin a page.
BoggleKills.VIEW_DEFAULT = 0
BoggleKills.VIEW_ROTATE = -1

-- BoggleKills_Chat message kinds.
BoggleKills.MSG_STATS = 1
BoggleKills.MSG_TOP = 2
BoggleKills.MSG_MISSING = 3
BoggleKills.MSG_LEADER = 4
BoggleKills.MSG_STREAK = 5
BoggleKills.MSG_STREAK_END = 6

-- Replicated so boards know what to show and what the K/D page requires.
CreateConVar( "boggle_kills_board_mode", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
    "Default board view: 0 = rotate pages, 1-5 = always show lifetime / players / NPCs / streaks / K/D", 0, 5 )
CreateConVar( "boggle_kills_kd_min", "25", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
    "Kills needed before a player appears on the K/D page", 1, 1000000 )

if SERVER then
    AddCSLuaFile()
    AddCSLuaFile( "boggle_kills/cl_scores.lua" )
    AddCSLuaFile( "boggle_kills/sh_view.lua" )
    resource.AddFile( "materials/boggle_kills/logo.png" )

    include( "boggle_kills/sv_scores.lua" )
else
    include( "boggle_kills/cl_scores.lua" )
end

include( "boggle_kills/sh_view.lua" )
