"""Check the addon using the same WoW API declarations as the local editor."""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("server", nargs="?", default="lua-language-server", help="LuaLS executable")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    settings = root / ".vscode/settings.json"
    if not settings.is_file():
        parser.error("Initialize the WoW API extension's workspace settings in VS Code first.")
    editor = json.loads(settings.read_text(encoding="utf-8-sig"))
    config = {key[4:]: value for key, value in editor.items() if key.startswith("Lua.")}
    config.update(json.loads((root / ".luarc.json").read_text(encoding="utf-8")))
    libraries = [Path(path).expanduser() for path in config.get("workspace.library", [])]
    if not libraries or any(not path.is_dir() for path in libraries):
        parser.error("Check Lua.workspace.library in .vscode/settings.json against the installed WoW API annotations.")
    config["workspace.library"] = [str(path) for path in libraries]
    with tempfile.TemporaryDirectory(prefix="awp-luals-") as tmp:
        directory = Path(tmp)
        profile = directory / "config.json"
        profile.write_text(json.dumps(config), encoding="utf-8")
        return subprocess.run([
            args.server, f"--check={root}", "--checklevel=Warning", f"--configpath={profile}",
            f"--logpath={directory}", f"--metapath={directory / 'meta'}",
        ], cwd=root).returncode


if __name__ == "__main__":
    raise SystemExit(main())
