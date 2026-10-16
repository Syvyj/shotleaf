# The disk image's window for dmgbuild (make-release.sh): the background from
# make-dmg-background.swift, and the two icons on their places in it.
app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
background = defines["background"]
window_rect = ((200, 200), (640, 400))
icon_size = 128
text_size = 13
icon_locations = {"Shotleaf.app": (170, 210), "Applications": (470, 210)}
show_status_bar = show_tab_view = show_toolbar = show_pathbar = show_sidebar = False
format = "UDZO"
filesystem = "HFS+"
