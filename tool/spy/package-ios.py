"""Package a no-codesign device build for user re-signing, then verify the IPA."""

import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path


def verify_ipa(ipa: Path, expected_bundle_id: str | None = None) -> dict:
    if expected_bundle_id is None:
        config = json.loads(Path(__file__).with_name('release.json').read_text(encoding='utf-8-sig'))
        expected_bundle_id = config['iosBundleId']
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise ValueError('IPA ZIP integrity check failed')
        names = archive.namelist()
        if any(n.startswith('/') or '..' in n.split('/') for n in names):
            raise ValueError('Unsafe archive path')
        apps = [n for n in names if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        if apps != ['Payload/Runner.app/Info.plist']:
            raise ValueError('IPA must contain one Payload/Runner.app')
        info = plistlib.loads(archive.read(apps[0]))
        if info['CFBundleIdentifier'] != expected_bundle_id:
            raise ValueError('Bundle identifier differs from the expected build identity')
        if info['CFBundleDisplayName'] != 'PiliPlus':
            raise ValueError('Unexpected release application name')
        if 2 not in info.get('UIDeviceFamily', []):
            raise ValueError('Build does not support iPad')
        orientations = info.get('UISupportedInterfaceOrientations~ipad', [])
        if set(orientations) != {
            'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
            'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight',
        } or info.get('UIRequiresFullScreen', False):
            raise ValueError('iPad orientation or resizable window support is missing')
        executable = f"Payload/Runner.app/{info['CFBundleExecutable']}"
        if executable not in names:
            raise ValueError('Missing application executable')
        with archive.open(executable) as binary:
            magic = binary.read(4)
        if magic not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
            raise ValueError('Application executable is not a Mach-O binary')
        for framework in ('App.framework/App', 'Flutter.framework/Flutter'):
            if f'Payload/Runner.app/Frameworks/{framework}' not in names:
                raise ValueError(f'Missing Flutter framework: {framework}')
    with ipa.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    return {
        'ipa': str(ipa.resolve()), 'ipaSha256': digest,
        'ipaBytes': ipa.stat().st_size, 'bundleIdentifier': info['CFBundleIdentifier'],
        'displayName': info['CFBundleDisplayName'], 'version': info['CFBundleShortVersionString'],
        'buildNumber': info['CFBundleVersion'], 'minimumIosVersion': info.get('MinimumOSVersion'),
        'supportsIpad': True, 'supportsResizableWindows': True,
        'signing': 'frameworks ad-hoc signed; requires user self-signing',
        'zipIntegrity': 'passed', 'nativeIpadAcceptance': 'pending',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--build-id')
    parser.add_argument('--verify', type=Path)
    parser.add_argument('--expected-bundle-id', help='Expected original ID when verifying an earlier build')
    args = parser.parse_args()
    if args.verify:
        print(json.dumps(verify_ipa(args.verify, args.expected_bundle_id), ensure_ascii=False, indent=2))
        return
    if sys.platform != 'darwin':
        parser.error('Native packaging requires macOS')
    if not args.app or not args.app.is_dir() or not args.output or not args.build_id:
        parser.error('--app, --output and --build-id are required')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]*', args.build_id):
        parser.error('Invalid build identifier')
    args.output.mkdir(parents=True, exist_ok=False)
    payload = args.output / 'Payload'
    app = payload / 'Runner.app'
    shutil.copytree(args.app, app, symlinks=True)
    executable = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleExecutable']
    arches = subprocess.check_output(['lipo', '-archs', str(app / executable)], text=True).split()
    if 'arm64' not in arches:
        raise ValueError('Device build lacks arm64')
    # Match upstream's AltSign-compatible packaging without a signing identity.
    frameworks = sorted((app / 'Frameworks').rglob('*.framework'), key=lambda p: len(p.parts), reverse=True)
    for framework in frameworks:
        subprocess.run(['codesign', '--force', '--sign', '-', '--preserve-metadata=identifier,entitlements', str(framework)], check=True)
        subprocess.run(['codesign', '--verify', str(framework)], check=True)
    ipa = args.output.resolve() / f'PiliPlus-SPY-{args.build_id}-ipad-unsigned.ipa'
    subprocess.run(['zip', '-qry', str(ipa), 'Payload'], cwd=args.output, check=True)
    report = verify_ipa(ipa, args.expected_bundle_id)
    report['architectures'] = arches
    report['frameworksAdhocVerified'] = len(frameworks)
    (args.output / 'ipa-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    # Keep native build and packaging staging for inspection on runner failures.
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
