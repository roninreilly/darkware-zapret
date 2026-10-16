#!/usr/bin/env python3
"""Package only the public source inputs needed to build the application."""
import pathlib
import subprocess
import sys
import tarfile

root = pathlib.Path(__file__).resolve().parent.parent
roots = {"Sources", "vendor", "native", "scripts", "Tests"}
files = {"Package.swift", "VERSION", "create_app.sh", "install_darkware.sh", "uninstall_darkware.sh", "LICENSE", "DarkwareZapret.icns", "README.md", "README.ru.md", "CHANGELOG.md"}
if (root / ".git").exists():
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    paths = [pathlib.PurePosixPath(name) for name in names if name]
else:
    paths = [path.relative_to(root) for name in roots | files for path in ([root / name] if (root / name).is_file() else (root / name).rglob("*")) if path.is_file()]
selected = []
for path in paths:
    if path.parts[0] not in roots and path.as_posix() not in files:
        continue
    if any(part.startswith(".") or part == "__pycache__" for part in path.parts):
        continue
    source = root / path
    if source.is_symlink():
        raise SystemExit("Source packaging requires regular files")
    if source.is_file():
        selected.append(path)
if not selected or not all((root / name).is_file() for name in files):
    raise SystemExit("Public source inputs are incomplete")
with tarfile.open(sys.argv[1], "w:gz") as archive:
    for path in sorted(set(selected)):
        archive.add(root / path, arcname=path.as_posix(), recursive=False)
print(f"Packaged {len(set(selected))} public source files")
