"""Check standalone Lua fixtures without sharing mock definitions between files."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def check_file(server, source, profile, directory):
    work = Path(tempfile.mkdtemp(prefix=source.stem + "-", dir=directory))
    workspace = work / "src"
    workspace.mkdir(parents=True)
    shutil.copyfile(source, workspace / source.name)
    report = work / "result.json"
    result = subprocess.run([
        server, f"--check={workspace}", "--checklevel=Warning", "--check_format=json",
        f"--check_out_path={report}", f"--configpath={profile}",
        f"--logpath={work}/log", f"--metapath={work}/meta",
    ], capture_output=True)
    if not report.is_file():
        raise RuntimeError(f"LuaLS could not check {source.name}: {result.stderr.decode(errors='replace')}")
    diagnostics = json.loads(report.read_text(encoding="utf-8"))
    messages = []
    for entries in (diagnostics or {}).values():
        for entry in entries:
            line = entry["range"]["start"]["line"] + 1
            messages.append(f"{source.name}:{line}: {entry['code']}  {entry['message']}")
    if result.returncode and not messages:
        raise RuntimeError(f"LuaLS exited with status {result.returncode} on {source.name}")
    return messages


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", default="lua-language-server", help="LuaLS executable")
    parser.add_argument("files", nargs="*", type=Path, help="Fixture files (default: all)")
    args = parser.parse_args()
    server = shutil.which(args.server)
    if not server:
        parser.error("LuaLS executable not found. Pass its path with --server.")
    tests = Path(__file__).resolve().parent
    files = sorted({path.resolve() for path in args.files} or tests.rglob("*.lua"))
    for source in files:
        if not source.is_file() or source.suffix != ".lua":
            parser.error(f"Expected a Lua fixture file: {source}")
    config = json.loads((tests / ".luarc.json").read_text(encoding="utf-8"))
    # Editor sessions check opened fixtures. Each CLI workspace contains just one.
    config.pop("workspace.ignoreDir")
    with tempfile.TemporaryDirectory(prefix="awp-fixtures-") as tmp:
        directory = Path(tmp)
        profile = directory / "profile.json"
        profile.write_text(json.dumps(config), encoding="utf-8")
        with ThreadPoolExecutor(max_workers=4) as workers:
            reports = list(workers.map(lambda f: check_file(server, f, profile, directory), files))
    for messages in reports:
        for message in messages:
            print(message)
    count = sum(map(len, reports))
    print(f"{len(files)} files checked, {count} warnings or errors")
    return int(bool(count))


if __name__ == "__main__":
    raise SystemExit(main())
