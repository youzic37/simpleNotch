import os

# dmgbuild settings file. This is read by the `dmgbuild` CLI (or Python API).
# It uses environment variables exported by the shell wrapper script:
#  - DMG_APP_PATH: path to the .app bundle to put in the DMG
#  - DMG_VOLUME_NAME: volume name to display when the DMG is mounted
#  - DMG_BACKGROUND: absolute path to the background image to use

APP_PATH = os.environ.get('DMG_APP_PATH')
LICENSE_PATH = os.environ.get('DMG_LICENSE_PATH')
THIRD_PARTY_LICENSES_PATH = os.environ.get('DMG_THIRD_PARTY_LICENSES_PATH')
DEPENDENCY_LICENSES_PATH = os.environ.get('DMG_DEPENDENCY_LICENSES_PATH')
VOLUME_NAME = os.environ.get('DMG_VOLUME_NAME', 'simpleNotch')
BACKGROUND = os.environ.get('DMG_BACKGROUND', '')
BADGE_ICON = os.environ.get('DMG_BADGE_ICON', '')

# If DMG_BACKGROUND not provided, default to the hiDPI TIFF in .background.
if not BACKGROUND:
    base = os.path.join(os.path.dirname(__file__), '.background', 'background.tiff')

# Basic DMG metadata
volume_name = VOLUME_NAME
format = 'UDZO'
compression_level = 9

# Files and symlinks to include in the DMG
files = [
    path for path in (
        APP_PATH,
        LICENSE_PATH,
        THIRD_PARTY_LICENSES_PATH,
        DEPENDENCY_LICENSES_PATH,
    )
    if path
]
symlinks = {'Applications': '/Applications'}

# Background image path (dmgbuild will copy this file into the DMG's .background)
background = BACKGROUND


# Window rectangle: ((left, top), (right, bottom))
window_rect = ((0, 0), (660, 400))

# Icon size (points)
icon_size = 128

# Icon locations: map filename (or bundle name) -> (x, y) in window coords
app_basename = os.path.basename(APP_PATH) if APP_PATH else 'simpleNotch.app'
icon_locations = {
    app_basename: (150, 180),
    'Applications': (510, 180),
}
if LICENSE_PATH:
    icon_locations[os.path.basename(LICENSE_PATH)] = (250, 330)
if THIRD_PARTY_LICENSES_PATH:
    icon_locations[os.path.basename(THIRD_PARTY_LICENSES_PATH)] = (410, 330)
if DEPENDENCY_LICENSES_PATH:
    icon_locations[os.path.basename(DEPENDENCY_LICENSES_PATH)] = (550, 330)

# Misc Finder options
show_statusbar = False
show_tabview = False
show_toolbar = False

# Optionally set a custom icon for the DMG volume (leave empty to skip)
if BADGE_ICON and os.path.exists(BADGE_ICON):
    badge_icon = BADGE_ICON
