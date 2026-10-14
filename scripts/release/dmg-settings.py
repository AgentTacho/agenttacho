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

window_rect = ((200, 120), (660, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None

icon_size = 128
text_size = 13
icon_locations = {
    app_name: (165, 175),
    "Applications": (495, 175),
}
