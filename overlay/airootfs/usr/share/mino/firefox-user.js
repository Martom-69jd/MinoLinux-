// Скопируйте в каталог профиля Firefox (about:support -> Profile Folder) и перезапустите.
user_pref("browser.sessionstore.interval", 60000);
user_pref("browser.cache.disk.enable", false);
user_pref("browser.cache.memory.capacity", 65536);
user_pref("dom.ipc.processCount", 2);
