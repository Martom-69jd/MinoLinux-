// Copy to the Firefox profile directory (about:support -> Profile Folder) and restart Firefox.
user_pref("browser.sessionstore.interval", 60000);
user_pref("browser.cache.disk.enable", false);
user_pref("browser.cache.memory.capacity", 65536);
user_pref("dom.ipc.processCount", 2);
