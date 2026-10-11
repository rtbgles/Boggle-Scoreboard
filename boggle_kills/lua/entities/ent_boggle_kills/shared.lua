ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Kill Board"
ENT.Author = "Boggle"
ENT.Category = "Boggle"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
ENT.IsBoggleKills = true
ENT.Model = "models/hunter/blocks/cube025x025x025.mdl"

-- Board geometry, shared so the server can tell which board a player aims at.
-- Unchanged since 2.0: placed boards keep their exact size and position.
ENT.BoardW = 820
ENT.BoardH = 560
ENT.BoardScale = 0.18
ENT.BoardOffsetUp = 12
ENT.BoardOffsetForward = 2

function ENT:SetupDataTables()
    -- BoggleKills.VIEW_DEFAULT, VIEW_ROTATE, or a page number to pin.
    self:NetworkVar( "Int", 0, "View" )
end

-- The board's 3D2D origin (its top-left corner) and angles. The readable face
-- points along the entity's forward axis.
function ENT:BoardFrame()
    local ang = self:GetAngles()
    ang:RotateAroundAxis( ang:Up(), 90 )
    ang:RotateAroundAxis( ang:Forward(), 90 )
    local pos = self:GetPos() + self:GetUp() * self.BoardOffsetUp + self:GetForward() * self.BoardOffsetForward

    return pos, ang
end

-- Where a ray meets the board's readable face, in board pixels, and how far away.
-- Nil when it misses, comes from behind, or is further than maxDist.
function ENT:BoardTrace( origin, dir, maxDist )
    local normal = self:GetForward()
    if dir:Dot( normal ) >= 0 then return nil end

    local pos, ang = self:BoardFrame()
    local hit, dist = util.IntersectRayWithPlane( origin, dir, pos, normal )
    if not hit or dist > maxDist then return nil end

    -- 3D2D +x runs along the angle's forward axis and +y along its right axis.
    local offset = hit - pos
    local x = offset:Dot( ang:Forward() ) / self.BoardScale
    local y = offset:Dot( ang:Right() ) / self.BoardScale
    if x < 0 or y < 0 or x > self.BoardW or y > self.BoardH then return nil end

    return x, y, dist
end
