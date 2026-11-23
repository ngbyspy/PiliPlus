"""IPA structure checks use synthetic fixtures; these are not native builds."""

import importlib.util
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

module_path = Path(__file__).parents[1] / 'package-ios.py'
spec = importlib.util.spec_from_file_location('ipa_package', module_path)
ipa_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ipa_package)


class IpaValidationTest(unittest.TestCase):
    def make_ipa(self, directory, *, full_screen=False, missing_executable=False, ipad=True,
                 bundle='com.spy.piliPlus', display_name='PiliPlus'):
        ipa = Path(directory) / 'fixture.ipa'
        info = {
            'CFBundleIdentifier': bundle,
            'CFBundleDisplayName': display_name,
            'CFBundleExecutable': 'Runner', 'CFBundleShortVersionString': '2.2.1',
            'CFBundleVersion': '1', 'UIDeviceFamily': [1, 2] if ipad else [1],
            'UIRequiresFullScreen': full_screen,
            'UISupportedInterfaceOrientations~ipad': [
                'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
                'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight',
            ],
        }
        with zipfile.ZipFile(ipa, 'w') as archive:
            archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(info))
            if not missing_executable:
                archive.writestr('Payload/Runner.app/Runner', b'\xcf\xfa\xed\xfe' + bytes(28))
            archive.writestr('Payload/Runner.app/Frameworks/App.framework/App', b'fixture')
            archive.writestr('Payload/Runner.app/Frameworks/Flutter.framework/Flutter', b'fixture')
        return ipa

    def test_self_signable_structure(self):
        with tempfile.TemporaryDirectory() as directory:
            result = ipa_package.verify_ipa(self.make_ipa(directory))
            self.assertTrue(result['supportsIpad'])
            self.assertEqual(result['nativeIpadAcceptance'], 'pending')

    def test_phone_only_build_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'does not support iPad'):
                ipa_package.verify_ipa(self.make_ipa(directory, ipad=False))

    def test_separate_release_identity_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'expected build identity'):
                ipa_package.verify_ipa(self.make_ipa(directory, bundle='com.ngbyspy.piliplus.spy'))

    def test_development_bundle_rejected_as_release(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'expected build identity'):
                ipa_package.verify_ipa(self.make_ipa(directory, bundle='com.spy.piliplus.dev'))

    def test_acceptance_name_and_identity_are_verified_explicitly(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = self.make_ipa(directory, bundle='com.spy.piliPlus.dev',
                                display_name='PiliPlus SPY Dev')
            result = ipa_package.verify_ipa(ipa, 'com.spy.piliPlus.dev', 'PiliPlus SPY Dev')
            self.assertEqual(result['bundleIdentifier'], 'com.spy.piliPlus.dev')
            self.assertEqual(result['displayName'], 'PiliPlus SPY Dev')

    def test_acceptance_name_does_not_bypass_formal_name_check(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = self.make_ipa(directory, display_name='PiliPlus SPY Dev')
            with self.assertRaisesRegex(ValueError, 'Unexpected application display name'):
                ipa_package.verify_ipa(ipa)

    def test_wrong_name_rejected_for_acceptance_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = self.make_ipa(directory, bundle='com.spy.piliPlus.dev')
            with self.assertRaisesRegex(ValueError, 'Unexpected application display name'):
                ipa_package.verify_ipa(ipa, 'com.spy.piliPlus.dev', 'PiliPlus SPY Dev')

    def test_acceptance_name_does_not_bypass_bundle_identity_check(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = self.make_ipa(directory, display_name='PiliPlus SPY Dev')
            with self.assertRaisesRegex(ValueError, 'expected build identity'):
                ipa_package.verify_ipa(ipa, 'com.spy.piliPlus.dev', 'PiliPlus SPY Dev')

    def test_cli_verify_accepts_the_acceptance_name_argument(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = self.make_ipa(directory, bundle='com.spy.piliPlus.dev',
                                display_name='PiliPlus SPY Dev')
            result = subprocess.run([
                sys.executable, str(module_path), '--verify', str(ipa),
                '--expected-bundle-id', 'com.spy.piliPlus.dev',
                '--expected-display-name', 'PiliPlus SPY Dev',
            ], check=True, capture_output=True, text=True)
            self.assertEqual(json.loads(result.stdout)['displayName'], 'PiliPlus SPY Dev')

    def test_earlier_build_can_be_verified_against_its_recorded_id(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = self.make_ipa(directory, bundle='com.example.piliplus')
            result = ipa_package.verify_ipa(ipa, expected_bundle_id='com.example.piliplus')
            self.assertEqual(result['bundleIdentifier'], 'com.example.piliplus')

    def test_forced_full_screen_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'resizable window'):
                ipa_package.verify_ipa(self.make_ipa(directory, full_screen=True))

    def test_missing_native_executable_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'Missing application executable'):
                ipa_package.verify_ipa(self.make_ipa(directory, missing_executable=True))


if __name__ == '__main__':
    unittest.main()
