AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )
include( "shared.lua" )

local SPAWN_LIFT = Vector( 0, 0, 28 )
local SPAWN_OFFSET = 8

function ENT:Initialize()
    self:SetModel( self.Model )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetUseType( SIMPLE_USE )
    self:SetCollisionGroup( COLLISION_GROUP_WEAPON )
    self:DrawShadow( false )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:EnableMotion( false )
    end
end

-- The board's readable face is the entity's forward side, so spawn it turned
-- toward the player who placed it.
function ENT:SpawnFunction( ply, tr, class )
    if not tr.Hit then return end

    local ent = ents.Create( class )
    if not IsValid( ent ) then return end

    ent:SetPos( tr.HitPos + tr.HitNormal * SPAWN_OFFSET + SPAWN_LIFT )
    ent:SetAngles( Angle( 0, ply:EyeAngles().y + 180, 0 ) )
    ent:Spawn()
    ent:Activate()

    return ent
end

function ENT:Use( ply )
    if IsValid( ply ) and ply:IsPlayer() then
        BoggleKills.SendTo( ply ) -- rate-limited serverside
    end
end

-- The duplicator passes the listed keys as arguments (false when missing), then
-- restores network vars itself, so a pasted board keeps its view.
duplicator.RegisterEntityClass( "ent_boggle_kills", function( ply, pos, ang )
    if IsValid( ply ) and not ply:IsAdmin() then return end

    local ent = ents.Create( "ent_boggle_kills" )
    if not IsValid( ent ) then return end

    ent:SetPos( pos or vector_origin )
    ent:SetAngles( ang or angle_zero )
    ent:Spawn()

    return ent
end, "Pos", "Angle" )
