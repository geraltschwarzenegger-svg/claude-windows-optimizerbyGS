"""Package an already-built EXE, notices and optionally the existing runtime resources."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from zipfile import ZipFile, ZIP_DEFLATED

folder = Path(__file__).resolve().parents[1]
repo = folder.parent
parser = argparse.ArgumentParser()
parser.add_argument('--executable', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--target', required=True)
parser.add_argument('--with-resources', action='store_true')
parser.add_argument('--extra-notices', type=Path)
parser.add_argument('--note', default='Build and read-only checks only; no hardware/performance verification.')
args = parser.parse_args()
exe = args.executable.resolve()
if exe.read_bytes()[:2] != b'MZ':
    raise SystemExit('Expected an already-built Windows PE executable')
meta = json.loads(subprocess.check_output([
    'cargo', 'metadata', '--locked', '--format-version', '1', '--filter-platform', args.target,
], cwd=folder))
notices = ['EXOVANCE RUST — THIRD-PARTY NOTICES\n']
for package in sorted(meta['packages'], key=lambda p: (p['name'], p['version'])):
    if not package.get('source'):
        continue
    base = Path(package['manifest_path']).parent
    notices.append(f"\n{'=' * 70}\n{package['name']} {package['version']}\nLicense: {package.get('license')}\nSource: {package.get('repository') or package['source']}\n")
    files = {p for pattern in ('LICENSE*', 'license*', 'COPYING*', 'COPYRIGHT*', 'UNLICENSE*') for p in base.glob(pattern) if p.is_file()}
    if package.get('license_file'):
        files.add(base / package['license_file'])
    for path in sorted(files):
        if path.is_file() and path.stat().st_size < 300_000:
            notices.append(f'\n--- {path.name} ---\n' + path.read_text(encoding='utf-8', errors='replace'))
sysroot = Path(subprocess.check_output(['rustc', '--print', 'sysroot'], text=True).strip())
licenses = sysroot / 'share/doc/rust/licenses'
if licenses.is_dir():
    for path in sorted(licenses.iterdir()):
        if path.is_file() and path.stat().st_size < 300_000:
            notices.append('\n--- Rust toolchain / standard library: ' + path.name + ' ---\n' + path.read_text(encoding='utf-8', errors='replace'))
if args.extra_notices:
    notices.append(args.extra_notices.read_text(encoding='utf-8'))
files = {'Exovance.exe': exe.read_bytes(), 'README.md': (folder / 'README.md').read_bytes(),
         'THIRD-PARTY-NOTICES.txt': '\n'.join(notices).encode('utf-8'),
         'Inspect-PowerSchemeManager.ps1': (folder / 'tools/Inspect-PowerSchemeManager.ps1').read_bytes()}
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
files['BUILD-INFO.txt'] = f'Exovance Rust 0.1.0\nTarget: {args.target}\nSource revision: {revision}\n{args.note}\nThe native menu embeds existing PowerShell 5.1 actions; migration is not complete.\n'.encode('utf-8')
if args.with_resources:
    # Ship tracked program resources only, never personal logs or saved machine settings.
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=repo).decode('utf-8').split('\0')
    for name in tracked:
        if not name:
            continue
        include = name.startswith(('DEVICE-TWEAKER-V2/', 'Resources/NVIDIA-PROFILE-INSPECTOR/'))
        include |= name in ('POWER-PLAN/EXOVANCE.pow', 'DEVICE-TWEAKER/RUN-DEVICE-TWEAKER.bat', 'DEVICE-TWEAKER/DEVICE-TWEAKER-UPDATE-2026-LLG-X-LLC-UPDATED.ps1', 'DEVICE-TWEAKER/pci.ids')
        if include:
            if any(part in ('logs', '.device-tweaker-typecache') for part in Path(name).parts) or name.endswith(('_backup.json', '.cfg')):
                raise SystemExit('Private runtime state selected: ' + name)
            files[name] = (repo / name).read_bytes()
files['SHA256SUMS.txt'] = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name, data in sorted(files.items())).encode('ascii')
args.output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(args.output, 'w', ZIP_DEFLATED, compresslevel=9) as archive:
    for name, data in sorted(files.items()):
        archive.writestr(name, data)
with ZipFile(args.output) as archive:
    assert archive.testzip() is None
    for name, data in files.items():
        assert archive.read(name) == data
args.output.with_suffix('.zip.sha256').write_text(f'{hashlib.sha256(args.output.read_bytes()).hexdigest()}  {args.output.name}\n', encoding='ascii')
print('Verified Windows package:', args.output, args.output.stat().st_size, 'bytes')
