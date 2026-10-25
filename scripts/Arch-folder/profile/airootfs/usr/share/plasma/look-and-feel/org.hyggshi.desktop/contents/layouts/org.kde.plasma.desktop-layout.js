// Hyggshi OS default Plasma layout: one bottom panel.
// Runs only on a user's first login. To fall back to the stock KDE panel, delete the
// "LookAndFeelPackage=org.hyggshi.desktop" line from ~/.config/kdeglobals (or /etc/skel/.config/kdeglobals).

var panel = new Panel;
panel.location = "bottom";
panel.height = 44;

var launcher = panel.addWidget("org.kde.plasma.kickoff");
try {
    launcher.currentConfigGroup = ["General"];
    launcher.writeConfig("icon", "hyggshi-logo");
} catch (e) {}

panel.addWidget("org.kde.plasma.pager");

var tasks = panel.addWidget("org.kde.plasma.icontasks");
try {
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("launchers",
        "applications:systemsettings.desktop," +
        "applications:org.kde.discover.desktop," +
        "applications:org.kde.dolphin.desktop," +
        "applications:firefox.desktop," +
        "applications:org.kde.kate.desktop," +
        "applications:org.kde.konsole.desktop");
} catch (e) {}

panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");
panel.addWidget("org.kde.plasma.digitalclock");
panel.addWidget("org.kde.plasma.showdesktop");

// Desktop wallpaper
try {
    var ds = desktops();
    for (var i = 0; i < ds.length; i++) {
        ds[i].wallpaperPlugin = "org.kde.image";
        ds[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
        ds[i].writeConfig("Image", "file:///usr/share/wallpapers/Hyggshi");
    }
} catch (e) {}
