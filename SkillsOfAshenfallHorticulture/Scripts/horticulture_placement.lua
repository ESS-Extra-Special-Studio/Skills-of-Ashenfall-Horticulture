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
local Placement = {}

Placement.DEFAULT = {
    x = 46537.2,
    y = 179635.6,
    z = nil,
    yaw = 314,
    source = "beside the wild cabbage by the Wise Old Man",
}

function Placement.Load()
    return Placement.DEFAULT
end

-- The ground's up vector from heights sampled r units either side of the
-- spot along X (zxp, zxm) and Y (zyp, zym). Flat when a sample is missing.
function Placement.Normal(zxp, zxm, zyp, zym, r)
    if not (zxp and zxm and zyp and zym and r and r > 0) then return { X = 0, Y = 0, Z = 1 } end
    local nx, ny = -(zxp - zxm) / (2 * r), -(zyp - zym) / (2 * r)
    local len = math.sqrt(nx * nx + ny * ny + 1)
    return { X = nx / len, Y = ny / len, Z = 1 / len }
end

-- The ground under the book from height samples { dx, dy, z } around the
-- spot (dx, dy relative to it). A least-squares plane through them, refitted
-- without the worst sample while one is more than `outlier` off it (a root,
-- a rock, the foot of a trunk). Returns the up vector, the plane's height at the spot, the
-- highest ground above the plane (so the book can clear it) and the number
-- of samples kept; nil with fewer than four samples.
function Placement.FitGround(samples, outlier)
    local function fit(list)
        local n, sx, sy, sz, sxx, syy, sxy, sxz, syz = 0, 0, 0, 0, 0, 0, 0, 0, 0
        for _, s in ipairs(list) do
            n = n + 1
            sx, sy, sz = sx + s[1], sy + s[2], sz + s[3]
            sxx, syy, sxy = sxx + s[1] * s[1], syy + s[2] * s[2], sxy + s[1] * s[2]
            sxz, syz = sxz + s[1] * s[3], syz + s[2] * s[3]
        end
        if n < 4 then return nil end
        local mx, my, mz = sx / n, sy / n, sz / n
        local cxx, cyy, cxy = sxx / n - mx * mx, syy / n - my * my, sxy / n - mx * my
        local cxz, cyz = sxz / n - mx * mz, syz / n - my * mz
        local det = cxx * cyy - cxy * cxy
        if math.abs(det) < 1e-9 then return nil end
        local b = (cxz * cyy - cyz * cxy) / det
        local c = (cyz * cxx - cxz * cxy) / det
        return mz - b * mx - c * my, b, c
    end
    local list = {}
    for _, s in ipairs(samples or {}) do
        if s[3] then list[#list + 1] = s end
    end
    local a, b, c = fit(list)
    if not a then return nil end
    while outlier and #list > 4 do
        local worst, at = outlier, nil
        for i, s in ipairs(list) do
            local d = math.abs(s[3] - (a + b * s[1] + c * s[2]))
            if d > worst then worst, at = d, i end
        end
        if not at then break end
        local kept = {}
        for i, s in ipairs(list) do
            if i ~= at then kept[#kept + 1] = s end
        end
        local a2, b2, c2 = fit(kept)
        if not a2 then break end
        a, b, c, list = a2, b2, c2, kept
    end
    local above = 0
    for _, s in ipairs(list) do
        above = math.max(above, s[3] - (a + b * s[1] + c * s[2]))
    end
    local len = math.sqrt(b * b + c * c + 1)
    return { X = -b / len, Y = -c / len, Z = 1 / len }, a, above, #list
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
return Placement
