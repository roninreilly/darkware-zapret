#!/usr/bin/env python3
"""Record immutable upstream revisions and the exact shipped engine/source digests."""
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
bundle, version, output = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
sealed = '--sealed' in sys.argv[4:]
def command(*args):
    return subprocess.check_output(args, cwd=root, text=True).strip()
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
has_git_metadata = (root / '.git').exists()
upstream = json.loads((root / 'vendor/manifest.json').read_text())
manifest = {
    'format': 1,
    'version': version,
    'builtAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'gitCommit': command('git', 'rev-parse', 'HEAD') if has_git_metadata else None,
    'workingTreeDirty': bool(command('git', 'status', '--porcelain', '--untracked-files=normal', '--', 'Sources', 'vendor', 'native', 'scripts', 'Tests', 'Package.swift', 'VERSION', 'create_app.sh', 'README.md', 'README.ru.md', 'docs')) if has_git_metadata else None,
    'swift': command('swift', '--version'),
    'clang': command('xcrun', 'clang', '--version'),
    'sdkVersion': command('xcrun', '--sdk', 'macosx', '--show-sdk-version'),
    'architectures': ['arm64', 'x86_64'],
    'minimumMacOS': {'app': '13.0', 'tpws': '13.0', 'ciadpi': '13.0', 'utunws': '14.0'},
    'signing': 'ad-hoc; not notarized',
    'upstream': upstream,
    'sourceFiles': {str(p.relative_to(root)): sha(p) for base in ('vendor', 'native', 'scripts', 'Sources') for p in sorted((root/base).rglob('*')) if p.is_file()},
    'engineSHA256': {p.name: sha(p) for p in sorted((bundle/'Contents/Resources/Engines').iterdir()) if p.is_file()},
    'nativeHelperSHA256': sha(bundle/'Contents/Resources/Native/snapshot-list'),
    'appSealComplete': sealed,
}
if sealed:
    manifest['appExecutableSHA256'] = sha(bundle/'Contents/MacOS/DarkwareZapret')
    manifest['bundledProvenanceSHA256'] = sha(bundle/'Contents/Resources/build-provenance.json')
output.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
