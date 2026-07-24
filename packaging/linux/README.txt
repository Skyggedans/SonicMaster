SonicMaster — Sonicake Pocket Master editor

Requirements: a desktop Linux system with GTK 3 and ALSA (libasound2).
Connect the pedal over USB and run ./sonicmaster.

Desktop integration (optional; also makes the taskbar icon show under Wayland,
where it comes from the .desktop app-id rather than the window):

  install -Dm644 dev.skyggedans.sonicmaster.desktop \
    ~/.local/share/applications/dev.skyggedans.sonicmaster.desktop
  install -Dm644 dev.skyggedans.sonicmaster.png \
    ~/.local/share/icons/hicolor/256x256/apps/dev.skyggedans.sonicmaster.png
  update-desktop-database ~/.local/share/applications 2>/dev/null || true

Edit the Exec= line in the installed .desktop to the absolute path of the
sonicmaster binary if it is not on PATH. The .desktop's app-id
(dev.skyggedans.sonicmaster) matches the window app-id, so Wayland/GNOME shows
the name and icon.

This is a portable build: everything except system GTK3/ALSA is bundled in lib/.
