#!/usr/bin/env python3
"""Mutation check: break one thing at a time and prove a named test catches it.

A green suite only means the tests did not fire. This asserts they *would* fire, which is
the difference between a test and a comment. Runs entirely inside a throwaway copy of the
repo under the system temp directory; the real working tree is never modified.

    python mutation_check.py                 (uses Lune on PATH)
    python mutation_check.py --luau PATH     (standalone Luau CLI)

Every entry below is a real regression somebody could plausibly introduce -- a reverted
`d.slot`, a clock swapped back to wall time, a change that lands in one tree and not the
other -- paired with the test that has to notice. A SKIP means the anchor no longer matches
the source, which is itself a finding: the mutation needs re-aiming at what the code says now.
"""
import argparse, io, os, shutil, subprocess, sys, tempfile

SRC = os.path.dirname(os.path.abspath(__file__))

MUTATIONS = [
    # (label, file, old, new, test that must fail)
    ("shape call reverts to the wall clock", "System.lua",
     "ShapePhysics.evaluate(shape_f2, p, active_c, d, sclock, cur_shape_cfg",
     "ShapePhysics.evaluate(shape_f2, p, active_c, d, ft, cur_shape_cfg",
     "tests/formation_lint.lua"),
    ("a shape stops preferring d.slot", "shapes/Halo Ring.lua", None, None, None),  # placeholder, replaced below
    ("SlotMode default is no longer inert", "config.lua",
     'SlotMode = "Claim"', 'SlotMode = "Shuffle"', "tests/formation_lint.lua"),
    ("TimeScale default is no longer 1", "config.lua",
     "TimeScale = 1.0", "TimeScale = 2.0", "tests/formation_lint.lua"),
    ("Claim mode stops clearing the slots it wrote", "System.lua",
     "d.slot, d.slot_n = nil, nil", "d.slot_n = nil",
     "tests/formation_smoke.lua"),
    ("the slot sort loses its tie-break", "System.lua",
     "return (slot_ids[a] or 0) < (slot_ids[b] or 0)", "return (slot_ids[a] or 0) > (slot_ids[b] or 0)",
     "tests/formation_smoke.lua"),
    ("the ceiling stops exempting Part Control", "System.lua",
     "if d and d.pc_mode == nil then", "if d then",
     "tests/formation_smoke.lua"),
    ("the reindex stride stops scaling with the part count", "System.lua",
     "> 0.25 * (dt > 4 and 4 or dt)", "> 0.25",
     "tests/formation_lint.lua"),
    ("the stride reindexes before it enforces", "System.lua",
     "x4.enforce_part_cap()\n\t\t\t\tx4.reindex_slots()", "x4.reindex_slots()\n\t\t\t\tx4.enforce_part_cap()",
     "tests/formation_lint.lua"),
    ("the preview drops its NaN guard", "System.lua",
     "nx ~= nx or ny ~= ny or nz ~= nz", "false",
     "tests/formation_smoke.lua"),
    ("the blend shares the primary's scratch record", "System.lua",
     "blend_f2, p, active_c, bd, sclock", "blend_f2, p, active_c, d, sclock",
     "tests/formation_lint.lua"),
    ("the claim ceiling goes off by one", "System.lua",
     "(cap <= 0 or x6.n < cap)", "(cap <= 0 or x6.n <= cap)",
     "tests/formation_lint.lua"),
    ("the size rule stops rejecting", "System.lua",
     "if min_sz > 0 and sz < min_sz then", "if false then",
     "tests/formation_smoke.lua"),
    ("the name filter becomes a Lua pattern", "System.lua",
     "string.find(name, pat, 1, true)", "string.find(name, pat)",
     "tests/formation_smoke.lua"),
    ("the claim radius starts evicting held parts", "System.lua",
     "if with_radius then", "if true then",
     "tests/formation_smoke.lua"),
    ("f1 stops marking the population dirty", "System.lua",
     "x6.slot_dirty = true\n\t\treturn true", "return true",
     "tests/formation_lint.lua"),
    ("stopping stops clearing the preview", "System.lua",
     "x6.last_blend = nil\n\t\tx4.preview_clear()", "x6.last_blend = nil",
     "tests/formation_lint.lua"),
    ("the shape clock ignores the scale", "System.lua",
     "c = c + (real_dt * scale)", "c = c + real_dt",
     "tests/formation_smoke.lua"),
    ("the shape clock loses its clamp", "System.lua",
     "elseif scale > 8 then", "elseif false then",
     "tests/formation_smoke.lua"),
    ("the sort scratch is freed after the early return", "System.lua",
     "table.clear(slot_parts)\n\t\ttable.clear(slot_keys)\n\t\ttable.clear(slot_ids)\n\t\tlocal n = #arr",
     "local n = #arr",
     "tests/formation_lint.lua"),
    ("the mobile blend skips return-value validation", "mobilever/System.lua",
     "ShapePhysics.evaluate(blend_f2, p, active_c, bd, sclock", "pcall(blend_f2, p, active_c, bd, sclock",
     "tests/formation_lint.lua"),
    ("only the desktop panel gets Time Scale", "mobilever/UI.lua",
     '"Time Scale", -3, 3', '"Time Scale", -1, 1',
     "tests/formation_lint.lua"),
    ("the deviation field leaves the change detect", "UI.lua",
     "or dev ~= hud_dev then", "then",
     "tests/formation_lint.lua"),
    # The index invariant in release_marked, which is the one piece of reasoning here that
    # is easy to get wrong and impossible to see: f2 fills the hole from the end.
    ("the release walk runs upward instead of down", "System.lua",
     "for k = #arr, 1, -1 do\n\t\t\tlocal p = arr[k]\n\t\t\tif p and mark[p] then",
     "for k = 1, #arr do\n\t\t\tlocal p = arr[k]\n\t\t\tif p and mark[p] then",
     "tests/formation_smoke.lua"),
    ("the release walk marks one part too many", "System.lua",
     "for i = 1, over do\n\t\t\tmark[cap_parts[i]] = true", "for i = 1, over + 1 do\n\t\t\tmark[cap_parts[i]] = true",
     "tests/formation_smoke.lua"),
    ("the surplus sort runs the wrong way", "System.lua",
     "local function cap_less(a, b)\n\t\tlocal ka, kb = cap_keys[a], cap_keys[b]\n\t\tif ka == kb then\n\t\t\treturn (cap_ids[a] or 0) < (cap_ids[b] or 0)\n\t\tend\n\t\treturn ka < kb",
     "local function cap_less(a, b)\n\t\tlocal ka, kb = cap_keys[a], cap_keys[b]\n\t\tif ka == kb then\n\t\t\treturn (cap_ids[a] or 0) < (cap_ids[b] or 0)\n\t\tend\n\t\treturn ka > kb",
     "tests/formation_smoke.lua"),
    ("the blend weight loses its clamp", "System.lua",
     "\t\tif w < 0 then\n\t\t\treturn 0\n\t\telseif w > 1 then\n\t\t\treturn 1\n\t\tend\n\t\treturn w",
     "\t\treturn w",
     "tests/formation_smoke.lua"),
    ("the ghost name leaves the exclusion list", "System.lua",
     "\t\tGRV_GHOST = true,\n", "",
     "tests/formation_smoke.lua"),
    ("a ghost stops being anchored", "System.lua",
     "part.Anchored = true", "part.Anchored = false",
     "tests/formation_smoke.lua"),
    ("the ghost count loses its bounds", "System.lua",
     "want = math.floor(math.clamp(want, 4, 200))", "want = math.floor(want)",
     "tests/formation_smoke.lua"),
    ("the desktop blend skips return-value validation", "System.lua",
     "ShapePhysics.evaluate(blend_f2, p, active_c, bd, sclock", "pcall(blend_f2, p, active_c, bd, sclock",
     "tests/formation_lint.lua"),
    ("the resolved blend is no longer published for the preview", "System.lua",
     "x6.bl_f2, x6.bl_cfg, x6.bl_w, x6.bl_s = blend_f2, blend_cfg, blend_base, blend_stag",
     "local _unused = blend_cfg",
     "tests/formation_lint.lua"),
    # The panel layer. formation_panel.lua invokes the callbacks, which is the only way a
    # control wired to the wrong key or to a renamed runtime function shows up.
    ("a rule slider stops rechecking the parts already held", "UI.lua",
     "x1.RuleMinSize = v\n\t\t\t\trules_changed()", "x1.RuleMinSize = v\n\t\t\t\tsave_settings()",
     "tests/formation_panel.lua"),
    ("the blend box stops resolving what was typed", "UI.lua",
     "x1.BlendShape = resolved", "x1.BlendShape = tostring(v)",
     "tests/formation_panel.lua"),
    ("a cycling button stops advancing", "UI.lua",
     "set(values[(idx % #values) + 1])", "set(values[idx])",
     "tests/formation_panel.lua"),
    ("the preview toggle stops collecting its markers", "UI.lua",
     "if x4 and x4.preview_clear then\n\t\t\t\t\t\tx4.preview_clear()", "if false then\n\t\t\t\t\t\tx4.preview_clear()",
     "tests/formation_panel.lua"),
    ("the mobile panel loses a control's range", "mobilever/UI.lua",
     '"Ghost Count", 4, 200', '"Ghost Count", 4, 20',
     "tests/formation_panel.lua"),
    # The Advanced panel's ordering. UIListLayout.SortOrder defaults to Name, so a list that
    # mixes classes sorts every heading to the bottom -- which is what the panel did.
    ("the Advanced list goes back to sorting by class name", "UI.lua",
     "order_children(ac, acl)", "-- order_children(ac, acl)",
     "tests/formation_panel.lua"),
    ("the layout is left in the SortOrder default", "UI.lua",
     "layout.SortOrder = Enum.SortOrder.LayoutOrder", "local _ = layout",
     "tests/formation_panel.lua"),
    ("only the desktop panel gets its ordering fixed", "mobilever/UI.lua",
     "order_children(ac, acl)", "-- order_children(ac, acl)",
     "tests/formation_panel.lua"),
    ("the Advanced rows stop being numbered in build order", "UI.lua",
     "n = n + 1\n\t\t\t\t\tchild.LayoutOrder = n", "n = n + 1",
     "tests/formation_panel.lua"),
]

# The d.slot revert, aimed at a shape that actually carries one.
MUTATIONS[1] = ("a shape stops preferring d.slot", "shapes/Mech Suit.lua",
                "local id = d.slot or d.id or 1", "local id = d.id or 1",
                "tests/formation_lint.lua")


def run(test, work, runner):
    p = subprocess.run([*runner, test], cwd=work, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout + p.stderr)


def check_mutations(work, runner):
    # Copy runtime modules as a group so adding a shared dependency cannot make
    # the isolated suite fail before it reaches a mutation.
    for entry in os.scandir(SRC):
        if entry.is_file() and entry.name.endswith(".lua"):
            shutil.copy2(entry.path, os.path.join(work, entry.name))
    for d in ("shapes", "shapes-onreview", "tests", "mobilever", "math", "tools"):
        src = os.path.join(SRC, d)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(work, d))

    # Baseline: the copy has to be green, or a "caught" result proves nothing.
    print("baseline (the copy must be green)")
    for t in sorted({test for _, _, _, _, test in MUTATIONS} | {"tests/shapes_smoke.lua"}):
        rc, out = run(t, work, runner)
        lines = out.strip().splitlines()
        print("  %-30s %s  %s" % (os.path.basename(t), "PASS" if rc == 0 else "FAIL", lines[-1] if lines else "(no output)"))
        if rc != 0:
            print(out)
            print("ABORT: baseline is not green")
            return 1

    print("\nmutations (each must be caught)")
    caught = missed = 0
    for label, rel, old, new, test in MUTATIONS:
        path = os.path.join(work, rel)
        with io.open(path, encoding="utf-8") as source:
            original = source.read()
        n = original.count(old)
        if n != 1:
            print("  %-52s SKIP  anchor appears %d times in %s" % (label, n, rel))
            missed += 1
            continue
        with io.open(path, "w", encoding="utf-8") as changed:
            changed.write(original.replace(old, new, 1))
        try:
            rc, out = run(test, work, runner)
        finally:
            with io.open(path, "w", encoding="utf-8") as restored:
                restored.write(original)
        first = ""
        for line in out.splitlines():
            if "FAIL" in line:
                first = line.strip()[:72]
                break
        if rc != 0:
            caught += 1
            print("  %-52s caught by %-26s %s" % (label, os.path.basename(test), first))
        else:
            missed += 1
            print("  %-52s NOT CAUGHT by %s" % (label, os.path.basename(test)))

    print("\n%d caught, %d missed, of %d mutations" % (caught, missed, len(MUTATIONS)))
    return 0 if missed == 0 else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    runtimes = parser.add_mutually_exclusive_group()
    runtimes.add_argument("--luau", help="path to the standalone Luau CLI")
    runtimes.add_argument("--lune", help="path to Lune (defaults to Lune on PATH)")
    options = parser.parse_args()
    luau = options.luau or (os.environ.get("LUAU") if not options.lune else None)
    if luau:
        executable = shutil.which(luau)
        if not executable:
            parser.error("cannot find the requested Luau CLI")
        runner = [sys.executable, "tools/test_luau.py", "--luau", os.path.abspath(executable)]
    else:
        executable = shutil.which(options.lune or "lune")
        if not executable:
            parser.error("install Lune on PATH or supply --luau PATH")
        runner = [os.path.abspath(executable), "run", "tools/test_luau.luau"]
    # A unique directory protects concurrent checks and never removes another
    # process's scratch files. The copy is cleaned up even when a suite fails.
    with tempfile.TemporaryDirectory(prefix="gravity-mutation-") as work:
        return check_mutations(work, runner)


if __name__ == "__main__":
    sys.exit(main())
