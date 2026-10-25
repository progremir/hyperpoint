# dmgbuild settings for the installer window. Icon positions match the wells drawn by design/installer/build.py.
import os

app = defines["app"]
app_name = os.path.basename(app)

format = "ULFO"
filesystem = "APFS"
size = None
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["volume_icon"]
badge_icon = None

background = defines["background"]
# The frame height adds the 32 pt title bar to the 400 pt background.
window_rect = ((200, 140), (640, 432))
default_view = "icon-view"
show_status_bar = show_tab_view = show_toolbar = show_pathbar = show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

arrange_by = None
icon_size = 112
text_size = 13
label_pos = "bottom"
icon_locations = {app_name: (170, 160), "Applications": (470, 160)}
