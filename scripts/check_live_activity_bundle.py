"""Verify the embedded WidgetKit executable before packaging or installation."""
from pathlib import Path
import plistlib
import sys


def check_bundle(app):
    app = Path(app)
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    extension = app / 'PlugIns' / 'NEU-LumenLiveActivity.appex'
    with (extension / 'Info.plist').open('rb') as stream:
        widget = plistlib.load(stream)
    assert info.get('NSSupportsLiveActivities') is True, 'App must enable Live Activities'
    assert 'neulumen' in [scheme for item in info.get('CFBundleURLTypes', [])
                          for scheme in item.get('CFBundleURLSchemes', [])], 'Missing activity URL scheme'
    assert widget['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension', 'Invalid extension point'
    assert 'NSExtensionPrincipalClass' not in widget['NSExtension'], 'WidgetKit uses the Swift @main entry point'
    assert widget['CFBundleIdentifier'].startswith(info['CFBundleIdentifier'] + '.'), 'Invalid extension identifier'
    for key in ['CFBundleShortVersionString', 'CFBundleVersion']:
        assert widget[key] == info[key], f'App/extension {key} mismatch'
    executable = widget.get('CFBundleExecutable', '')
    assert executable and Path(executable).name == executable, 'Missing extension executable name'
    assert (extension / executable).is_file(), 'Missing compiled WidgetKit executable'
    print(f'PASS: embedded WidgetKit extension {extension.name}, executable {executable}')


if __name__ == '__main__':
    check_bundle(sys.argv[1])
