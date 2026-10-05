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
