"""Build the working tree's addon ZIP and run both load-order fixtures against its extracted contents."""

import argparse
from pathlib import Path, PurePosixPath
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
ADDON = "AzerothWaypoint"


def release_files():
    toc = f"{ADDON}.toc"
    files = [toc, "Bindings.xml", "LICENSE", "README.md", "CHANGELOG.md"]
    for line in (ROOT / toc).read_text(encoding="utf-8-sig").splitlines():
        entry = line.strip().replace("\\", "/")
        if not entry or entry.startswith("#"):
            continue
        path = PurePosixPath(entry)
        if path.is_absolute() or ".." in path.parts or path.suffix != ".lua":
            raise ValueError(f"Review the release manifest entry {entry!r}")
        files.append(entry)
    files.extend(p.relative_to(ROOT).as_posix() for p in sorted((ROOT / "media").rglob("*")) if p.is_file())
    if len(set(files)) != len(files):
        raise ValueError("Duplicate file in the release manifest")
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Destination .zip file")
    output = parser.parse_args().output.resolve()
    if output.suffix.lower() != ".zip":
        parser.error("The output must be a .zip file")
    files = release_files()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as tmp:
        work = Path(tmp)
        archive = work / "candidate.zip"
        with zipfile.ZipFile(archive, "w") as package:
            for name in files:
                member = zipfile.ZipInfo(f"{ADDON}/{name}")
                member.compress_type = zipfile.ZIP_DEFLATED
                member.create_system = 3
                member.external_attr = 0o100644 << 16
                package.writestr(member, (ROOT / name).read_bytes())
        with zipfile.ZipFile(archive) as package:
            package.extractall(work)
        extracted = work / ADDON
        for name in files:
            if (extracted / name).read_bytes() != (ROOT / name).read_bytes():
                raise ValueError(f"Extracted contents differ for {name}")
        for client in ("retail", "forever"):
            subprocess.run(["lua", "tests/addon_load_order_test.lua", client, str(extracted)], cwd=ROOT, check=True)
        archive.replace(output)
    print(f"{len(files)} files verified on extraction, Retail and Forever load order passed.\n{output}")


if __name__ == "__main__":
    main()
