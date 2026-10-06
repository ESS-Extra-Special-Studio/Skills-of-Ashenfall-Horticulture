"""Which hybrid looks get a baked fruit layer, offline.

Runs the mod's own resolution (horticulture_looks.placement_for and
build_fruit_layer, in Lua): flagship placement data when it has a shape for the
host mesh, else the generic look; then the fruit-layer manifest by host mesh +
hybrid id, else host mesh + scion. Every legal 1-25 combo on every host mesh
the combos file lists (plot stages, grown trees, saplings).

usage: python tools/fruit_layer_audit.py [--md out.md]
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pylib"))
from lupa import lua54  # noqa: E402

SCRIPTS = os.path.join(ROOT, "SkillsOfAshenfallHorticulture", "Scripts")

AUDIT = r"""
local scripts = ...
package.path = scripts .. "\\?.lua;" .. package.path
local Rules = require("horticulture_splice_rules")
local P = require("horticulture_placements")
local G = require("horticulture_hybrid_generic")
local F = require("horticulture_fruit_layers")
assert(G.Load(scripts .. "\\placements"), "generic data")
assert(F.Load(scripts .. "\\placements"), "fruit layer manifest")
local out = {}
local data = loadfile((function()
    for v = 50, 1, -1 do
        local f = string.format("%s\\placements\\hort_plant_generic_hybrids_1_25_combos_v%03d.lua", scripts, v)
        if io.open(f) then return f end
    end
end)())()
for _, e in ipairs(data.combos) do
    local scion, host = e.key:match("^(.-)>(.+)$")
    local hid = Rules.HybridId(scion, host)
    local flag = Rules.Flagship(scion, host) and true or false
    local fdata = flag and P.Load(scripts, hid) or nil
    local gdata = G.Placement(scion, host)
    for kind, list in pairs(data.host_meshes[host] or {}) do
        for _, mesh in ipairs(list) do
            local src, shape = "none", nil
            if fdata then shape = P.Shape(fdata, mesh) if shape then src = "flagship" end end
            if not shape and gdata then shape = P.Shape(gdata, mesh) if shape then src = "generic" end end
            local n = shape and #(shape.attachments or {}) or 0
            local layer = shape and F.Find(mesh, hid, scion) or nil
            out[#out + 1] = table.concat({ e.key, hid, kind, mesh, src, n, layer and layer.asset:match("([^%.]+)$") or "-",
                Rules.IsTree(scion) and "tree" or "crop", Rules.IsTree(host) and "tree" or "crop" }, "|")
        end
    end
end
return table.concat(out, "\n")
"""


def main():
    lua = lua54.LuaRuntime()
    rows = [r.split("|") for r in lua.execute(AUDIT, SCRIPTS).split("\n")]
    combos = {}
    for key, hid, kind, mesh, src, n, layer, sk, hk in rows:
        c = combos.setdefault(key, {"hid": hid, "type": "%s-on-%s" % (sk, hk), "hosts": []})
        c["hosts"].append((kind, mesh.rsplit("/", 1)[-1], src, int(n), layer))

    def why(c, h):
        kind, mesh, src, n, layer = h
        if layer != "-":
            return "layer"
        if src == "none":
            return "no look data for this mesh"
        if c["type"].endswith("on-crop"):
            return "crop host: no layers (plot)"
        if c["type"].startswith("tree"):
            return "tree cutting: limb, no produce layer"
        return "MISSING layer"

    out = []
    summary = {}
    for key in sorted(combos, key=lambda k: (combos[k]["type"], k)):
        c = combos[key]
        reasons = [why(c, h) for h in c["hosts"]]
        tree_hosts = [h for h in c["hosts"] if h[0] != "plot"]
        lay = sum(1 for h in c["hosts"] if h[4] != "-")
        status = ("LAYER %d/%d" % (lay, len(tree_hosts))) if tree_hosts and c["type"] == "crop-on-tree" else sorted(set(reasons))[0]
        if "MISSING layer" in reasons:
            status = "MISSING on " + ", ".join(h[1] for h, r in zip(c["hosts"], reasons) if r == "MISSING layer")
        nodata = [h[1] for h, r in zip(c["hosts"], reasons) if r == "no look data for this mesh"]
        out.append((c["type"], key, c["hid"], status, nodata, sorted(set(h[4] for h in c["hosts"] if h[4] != "-"))))
        summary.setdefault((c["type"], status.split(" ")[0]), []).append(key)

    md = "--md" in sys.argv and sys.argv[sys.argv.index("--md") + 1]
    lines = ["| type | combo | hybrid id | result | meshes without look data | layer assets |", "|---|---|---|---|---|---|"]
    for t, key, hid, status, nodata, assets in out:
        lines.append("| %s | %s | %s | %s | %s | %s |" % (t, key, hid if hid != key else "", status, ", ".join(nodata) or "", ", ".join(assets)))
    if md:
        with open(md, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    for (t, s), keys in sorted(summary.items()):
        print("%-13s %-28s %3d" % (t, s, len(keys)))
    for t, key, hid, status, nodata, assets in out:
        if t != "crop-on-crop" or nodata or status.startswith("MISSING"):
            print("  %-26s %-14s %-24s nodata=%s" % (key, hid if hid != key else "", status, ",".join(nodata)))
    bad = [o for o in out if o[3].startswith("MISSING")]
    print("RESULT " + ("PASS" if not bad else "FAIL (%d combos missing a layer)" % len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
