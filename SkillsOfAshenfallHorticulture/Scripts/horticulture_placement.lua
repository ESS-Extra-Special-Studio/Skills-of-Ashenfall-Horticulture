-- Where the Brassica Prime book sits in the world.
--
-- The default is beside the wild cabbage north-west of the Wise Old Man in
-- Bramblemead Valley, where Growing Pains starts. The Dragonwilds Wiki map
-- (Module:Map/Cabbage.json) puts that cabbage at 46446.8, 179729.1, and in
-- game the cabbage stands exactly there, so wiki map coordinates are world
-- units. A book on that point is hidden inside the cabbage, so it sits 1.3 m
-- out towards the Wise Old Man (Module:Map/Wise Old Man.json, 48499.7,
-- 177605.0), on the open grass players arrive over, turned to face them.
-- With no z the book is put on the ground with a line trace.
--
-- A placement.txt next to the Scripts folder overrides this. It is written
-- by the capture key in a dev build, standing on the chosen spot:
--   x=46537.2
--   y=179635.6
--   z=...
--   yaw=...
local Placement = {}

Placement.DEFAULT = {
    x = 46537.2,
    y = 179635.6,
    z = nil,
    yaw = 314,
    source = "beside the wild cabbage by the Wise Old Man",
}

local function file_path(dir)
    return dir .. "\\..\\placement.txt"
end

function Placement.Load(dir)
    local f = io.open(file_path(dir), "r")
    if not f then return Placement.DEFAULT end
    local p = { yaw = 0, source = "placement.txt" }
    for line in f:lines() do
        local k, v = line:match("^%s*([%a_]+)%s*=%s*(.-)%s*$")
        if k == "map" then
            p.map = v
        elseif k and tonumber(v) then
            p[k] = tonumber(v)
        end
    end
    f:close()
    if not (p.x and p.y) then return Placement.DEFAULT end
    return p
end

-- The ground's up vector from heights sampled r units either side of the
-- spot along X (zxp, zxm) and Y (zyp, zym). Flat when a sample is missing.
function Placement.Normal(zxp, zxm, zyp, zym, r)
    if not (zxp and zxm and zyp and zym and r and r > 0) then return { X = 0, Y = 0, Z = 1 } end
    local nx, ny = -(zxp - zxm) / (2 * r), -(zyp - zym) / (2 * r)
    local len = math.sqrt(nx * nx + ny * ny + 1)
    return { X = nx / len, Y = ny / len, Z = 1 / len }
end

-- A rotator (degrees) that lays the book on ground with up vector n, still
-- facing yaw. Unreal axes: forward (CP CY, CP SY, SP); the right axis's Z is
-- -SR CP and the up axis's Z is CR CP.
function Placement.GroundRotation(n, yaw)
    if n.Z < 1e-3 then return { Pitch = 0, Yaw = yaw or 0, Roll = 0 } end
    -- Forward keeps the yaw's heading and climbs or drops with the ground.
    local y = math.rad(yaw or 0)
    local fx, fy = math.cos(y), math.sin(y)
    local fz = -(n.X * fx + n.Y * fy) / n.Z
    local len = math.sqrt(fx * fx + fy * fy + fz * fz)
    fx, fy, fz = fx / len, fy / len, fz / len
    -- right = up x forward
    local rz = n.X * fy - n.Y * fx
    return {
        Pitch = math.deg(math.asin(math.max(-1, math.min(1, fz)))),
        Yaw = math.deg(math.atan(fy, fx)),
        Roll = math.deg(math.atan(-rz, n.Z)),
    }
end

function Placement.Save(dir, p)
    local path = file_path(dir)
    local f = io.open(path .. ".tmp", "w")
    if not f then return false end
    f:write(string.format("x=%.2f\ny=%.2f\nz=%.2f\nyaw=%.1f\n", p.x, p.y, p.z, p.yaw or 0))
    if p.map then f:write("map=" .. p.map .. "\n") end
    f:close()
    os.remove(path)
    return os.rename(path .. ".tmp", path)
end

return Placement
