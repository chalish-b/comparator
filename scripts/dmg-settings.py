# dmgbuild settings for the release disk image. The app path is passed in with
# `-D app=<path>`; see scripts/release.sh.
import os.path

application = defines["app"]
app_name = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}

# The app sits on the left and Applications on the right, so it's dragged
# left to right.
window_rect = ((200, 200), (540, 340))
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (140, 150),
    "Applications": (400, 150),
}

default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
