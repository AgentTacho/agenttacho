# dmgbuild settings for the AgentMeter DMG (research.md R4).
#
# Defines passed with -D:
#   app         path to AgentMeter.app
#   background  1x background PNG; dmgbuild picks up the @2x file next to it
#   icon        volume icon (.icns)
#
# `defines` is provided by dmgbuild when it executes this file.

import os.path

application = defines["app"]  # noqa: F821
app_name = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}

icon = defines["icon"]  # noqa: F821
badge_icon = None
background = defines["background"]  # noqa: F821

# Window size and icon placement per background. The notarized artwork is
# 836 x 470 pt with free spots for the icons left and right of the mascot's
# arrow; the generated unnotarized background is 660 x 440 pt with room for the
# first-launch steps (render-dmg-backgrounds.swift). The window height includes
# Finder's title bar, so a taller title bar crops the bottom of the artwork,
# which is only hills.
LAYOUTS = {
    "background-notarized": {
        "window": (836, 498),
        "icon_size": 80,
        "app": (206, 214),
        "applications": (625, 214),
    },
    "background-unnotarized": {
        "window": (660, 440),
        "icon_size": 128,
        "app": (165, 175),
        "applications": (495, 175),
    },
}
layout = LAYOUTS[os.path.splitext(os.path.basename(background))[0]]

window_rect = ((200, 120), layout["window"])
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None

icon_size = layout["icon_size"]
text_size = 13
icon_locations = {
    app_name: layout["app"],
    "Applications": layout["applications"],
}
