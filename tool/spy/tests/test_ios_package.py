"""IPA structure checks use synthetic fixtures; these are not native builds."""

import importlib.util
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

module_path = Path(__file__).parents[1] / 'package-ios.py'
spec = importlib.util.spec_from_file_location('ipa_package', module_path)
ipa_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ipa_package)


class IpaValidationTest(unittest.TestCase):
    def make_ipa(self, directory, *, full_screen=False, missing_executable=False, ipad=True, bundle='com.example.piliplus'):
        ipa = Path(directory) / 'fixture.ipa'
        info = {
            'CFBundleIdentifier': bundle,
            'CFBundleDisplayName': 'PiliPlus',
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
            with self.assertRaisesRegex(ValueError, 'inherit upstream data'):
                ipa_package.verify_ipa(self.make_ipa(directory, bundle='com.ngbyspy.piliplus.spy'))

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
