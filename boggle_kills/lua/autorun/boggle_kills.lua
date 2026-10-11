BoggleKills = BoggleKills or {}
BoggleKills.Version = "2.0.0"

BoggleKills.Config = BoggleKills.Config or {
    Brand = "BLOODY SANDBOX",
    Subtitle = "Lifetime Kill Count (Players, NPCs)"
}

if SERVER then
    AddCSLuaFile()
    AddCSLuaFile( "boggle_kills/cl_scores.lua" )
    resource.AddFile( "materials/boggle_kills/logo.png" )

    include( "boggle_kills/sv_scores.lua" )
else
    include( "boggle_kills/cl_scores.lua" )
end
