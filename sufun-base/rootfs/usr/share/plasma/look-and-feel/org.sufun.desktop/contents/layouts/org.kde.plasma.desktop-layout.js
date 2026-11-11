// Windows 11-style desktop and taskbar. Plasma runs this once, the first time
// a new user logs in (live USB and installed system).
//
// Taskbar, left to right:
//   [spacer] start | search box | Task View | Files Firefox Konsole Settings [spacer] tray | clock
// Which tray icons are always visible is set here too. Win+N for the
// notifications widget inside the tray is set by /usr/lib/sufun/first-login,
// because that widget only exists after Plasma has started.

// --- Desktop: icons like Windows (top-left, top-to-bottom columns) ---
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    var d = desktopsArray[j];
    d.wallpaperPlugin = "org.kde.image";        // keep the default wallpaper
    d.currentConfigGroup = ["General"];
    d.writeConfig("arrangement", 1);            // 1 = columns (top to bottom)
    d.writeConfig("alignment", 0);              // 0 = start at the left
    d.writeConfig("iconSize", 2);               // 2 = 48 px, Windows' "medium icons"
    // 2 = by date, oldest first: icons keep the order first-login creates them in
    // (휴지통, Firefox, Steam, Writer, 메모장) and new files go to the end, like
    // Windows. (The default 0 means "by name", not "unsorted".)
    d.writeConfig("sortMode", 2);
}

// --- Taskbar ---
var panel = new Panel;
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.6 / 2);   // about 48 px at 100% scale
panel.floating = false;                              // attached to the screen edge, like Windows 11
panel.opacity = "opaque";                            // no transparency (performance)

// Expanding spacers on both sides keep the start button and apps in the middle.
panel.addWidget("org.kde.plasma.panelspacer");

// Start menu (Kickoff). The Win key alone opens it (kwinrc ModifierOnlyShortcuts).
// Pinned apps: /etc/xdg/kicker-extra-favoritesrc.
var kickoff = panel.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "start-here-kde");      // SUFUN logo (icon theme "SUFUN")
kickoff.writeConfig("favoritesDisplay", 0);         // pinned apps as a grid
kickoff.writeConfig("applicationsDisplay", 1);      // "All apps" as a list
kickoff.writeConfig("primaryActions", 0);           // power buttons in the footer
kickoff.writeConfig("systemFavorites", ["suspend", "reboot", "shutdown"]);
kickoff.writeConfig("showActionButtonCaptions", false);
kickoff.globalShortcut = "Alt+F1";

panel.addWidget("org.sufun.search");                // "검색" box -> KRunner
panel.addWidget("org.sufun.taskview");              // Task View -> KWin Overview

var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "preferred://filemanager",
    "preferred://browser",
    "applications:org.kde.konsole.desktop",
    "applications:systemsettings.desktop"
]);

panel.addWidget("org.kde.plasma.panelspacer");

// System tray: the "^" arrow, 한/영, network, volume, battery. Win+A opens it
// (closest thing to Windows 11's quick settings).
var tray = panel.addWidget("org.kde.plasma.systemtray");
tray.globalShortcut = "Meta+A";
// Always visible: 한/영 (Fcitx), network, volume, battery. Behind "^": the rest.
// (Plasma 6.8 keeps these in the tray widget's own [General] settings.)
tray.currentConfigGroup = ["General"];
tray.writeConfig("shownItems", ["Fcitx", "org.kde.plasma.networkmanagement",
                                "org.kde.plasma.volume", "org.kde.plasma.battery"]);
tray.writeConfig("hiddenItems", ["org.kde.plasma.bluetooth", "org.kde.plasma.notifications",
                                 "org.kde.plasma.clipboard", "org.kde.plasma.brightness",
                                 "org.kde.plasma.manage-inputmethod"]);

// Clock at the far right (two lines, 오전/오후, YYYY-MM-DD). Click = calendar.
panel.addWidget("org.sufun.clock");
