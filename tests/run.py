"""Run the Lua 5.1 regression fixtures from a development checkout."""

import argparse
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("all", "standalone"), default="all")
    parser.add_argument("--require-guide-parity", action="store_true",
                        help="Show per-case parity exclusions (the full suite always fails on uncovered cases)")
    args = parser.parse_args()
    if args.require_guide_parity and args.suite != "all":
        parser.error("--require-guide-parity requires both installed clients")
    root = Path(__file__).resolve().parents[1]
    env = {**os.environ, "AWP_TEST_SUITE": args.suite}
    cases = [(p.relative_to(root).as_posix(),) for p in sorted((root / "tests").glob("*_test.lua"))]
    cases.append(("tests/gw2ui_appearance_test.lua", "retail"))
    cases.append(("tests/addon_load_order_test.lua", "forever"))
    passed = skipped = 0
    for case in cases:
        show_coverage = case[0] == "tests/guide_presentation_parity_test.lua"
        if show_coverage and args.require_guide_parity:
            case = (*case, "--strict")
        result = subprocess.run(["lua", *case], cwd=root, env=env, capture_output=True)
        if result.returncode == 77 and args.suite == "standalone":
            skipped += 1
        elif result.returncode:
            print("Failed", *case, flush=True)
            sys.stderr.buffer.write(result.stdout + result.stderr)
            return 1
        else:
            if show_coverage:
                sys.stdout.buffer.write(result.stdout)
                sys.stdout.flush()
            passed += 1
    print(f"{passed} passed, {skipped} require installed addons")
    return 0


if __name__ == "__main__":
    sys.exit(main())
