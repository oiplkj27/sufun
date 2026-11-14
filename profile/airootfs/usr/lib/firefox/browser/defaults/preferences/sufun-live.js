// SUFUN live system only (not on installed systems): everything the live system
// writes lands in RAM (/run/archiso/cowspace), so Firefox keeps no disk cache
// there. The memory cache stays small (policies.json: 32 MB).
pref("browser.cache.disk.enable", false);
pref("browser.cache.disk.smart_size.enabled", false);
// No crash reports and session backups piling up in RAM
pref("browser.sessionstore.interval", 60000);
