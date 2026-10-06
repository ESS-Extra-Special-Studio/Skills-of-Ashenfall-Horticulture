"""Prints the names stored in cooked recipe packages, to see which recipes
carry a skill requirement (RequiredSkills / MinSkillLevel / a skill asset).

Read-only. Uses DragonwildsAssets' IoStore reader.

Usage: python recipe_names.py <path substring> [<path substring> ...]
"""
import re
import sys

sys.path.insert(0, r"<user>\IdeaProjects\DragonwildsAssets\scripts\vanilla")
import iostore_read  # noqa: E402

CHUNK_EXPORT_BUNDLE = 1


def main():
    toc = iostore_read.Toc()
    wanted = [w.lower() for w in sys.argv[1:]]
    for path, idx in sorted(toc.paths.items()):
        if not path.endswith(".uasset") or not any(w in path.lower() for w in wanted):
            continue
        data = toc.read_chunk(idx)
        names = sorted({m.group().decode("ascii") for m in re.finditer(rb"[A-Za-z_][A-Za-z0-9_/]{3,}", data)})
        skillish = [n for n in names if re.search(r"Skill|Level|Unlock|Require", n)]
        print(f"== {path.split('/Content/')[-1]}")
        print("   " + ", ".join(skillish) if skillish else "   (no skill, level, unlock or require names)")


if __name__ == "__main__":
    main()
