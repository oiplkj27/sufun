// Windows 11-style desktop: one taskbar at the bottom,
// start button + app icons in the middle, tray and clock on the right.
// Plasma runs this once, the first time a new user logs in.

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
}

var panel = new Panel;
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.6 / 2);   // about 48 px at 100% scale
panel.floating = false;                              // attached to the screen edge, like Windows 11

// Expanding spacer on each side pushes the start button and icons to the middle.
panel.addWidget("org.kde.plasma.panelspacer");

panel.addWidget("org.kde.plasma.kickoff");           // start menu (Win key opens it)

var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "preferred://filemanager",
    "preferred://browser",
    "applications:org.kde.konsole.desktop",
    "applications:systemsettings.desktop"
]);

panel.addWidget("org.kde.plasma.panelspacer");

panel.addWidget("org.kde.plasma.systemtray");
panel.addWidget("org.kde.plasma.digitalclock");
panel.addWidget("org.kde.plasma.showdesktop");       // thin "show desktop" button in the corner
