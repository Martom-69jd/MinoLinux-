# MinoLinux ISO

MinoLinux: лёгкий Arch-based дистрибутив для слабого железа. Система остаётся обычным Arch (пакеты из официальных
репозиториев, `/etc/os-release` не подменяется, чтобы обновления pacman его не откатывали); брендинг: имя образа,
метка тома, меню загрузки и пункт GRUB (GRUB сам добавит к «Mino» слово Linux). Итоговый файл: `out/minolinux-<дата>-x86_64.iso`.

Проект для `archiso`: live/install-образ с настройками из руководства
(linux-lts, zram+lz4, sysctl, bfq для HDD, Openbox + tint2, Firefox/mpv, earlyoom, ext4 noatime).
Образ только **x86_64** (Athlon II, Core 2 Duo и новее), BIOS и UEFI.

> ISO здесь **не собран**: у меня не было ни доступа к зеркалам Arch, ни `pacman`/`mkarchiso`.
> Проверялись только синтаксис скриптов (`bash -n`, shellcheck) и подготовка профиля на макете releng.
> Остальное нужно проверить у вас: см. «Что не проверено».

## Сборка

На Arch Linux (или в Arch-контейнере), от root:

```bash
sudo pacman -S --needed archiso
tar xzf minolinux-iso.tar.gz && cd minolinux-iso
sudo ./build.sh                 # ядро linux-lts; результат: ./out/minolinux-*.iso
```

Без Arch-машины, через Docker:

```bash
docker run --rm -it --privileged -v "$PWD":/work -w /work archlinux:latest \
  bash -c 'pacman -Syu --noconfirm archiso && ./build.sh'
```

Переменные: `KERNEL=linux|linux-zen`, `WORK=...` (нужно ~5 ГБ), `OUT=...`,
`PREPARE_ONLY=1` (только подготовить профиль и посмотреть его), `SKIP_PREFLIGHT=1`.

Как это устроено: `build.sh` копирует **штатный профиль releng** из вашего пакета `archiso`
(так загрузочные конфиги всегда соответствуют версии archiso), убирает лишнее (ssh, networkd, iwd, zsh),
накладывает `overlay/`, подменяет ядро, ставит сжатие squashfs в zstd
(на старом CPU распаковывается быстрее xz) и запускает `mkarchiso`.
Перед сборкой проверяется, что все пакеты есть в репозиториях.

## Проверка и запись

```bash
run_archiso -i out/minolinux-*.iso          # QEMU, нужен пакет qemu-desktop
sudo dd if=out/minolinux-*.iso of=/dev/sdX bs=4M status=progress oflag=sync   # sdX: ВАША флешка
```

## Использование

Загрузка, автологин root на tty1. Далее:

- `startx`: live-Openbox, чтобы оценить отзывчивость на вашем железе;
- `nmtui`: сеть;
- `mino-install`: установка на ВЕСЬ выбранный диск (спросит диск, пользователя, пояс, локаль, рабочий стол,
  пароли; для подтверждения нужно набрать путь диска). BIOS: MBR + GRUB, UEFI: GPT + ESP + GRUB.
  Устанавливает из сети (pacstrap), ISO для этого содержит только установщик и настройки;
- либо `archinstall`, а затем вручную применить `/etc/sysctl.d/99-mino.conf`,
  `/etc/systemd/zram-generator.conf`, udev-правило и параметр ядра `zswap.enabled=0` (всё лежит в live-системе).

После установки: вход на tty1 запускает Openbox (`touch ~/.nostartx`: отключить), `SESSION=xfce startx`: XFCE
(если выбран вариант 2). Для Firefox скопируйте `/usr/share/mino/firefox-user.js` в каталог профиля.

В BIOS включите режим SATA **AHCI**.

## Настройка под себя

- Пакеты live-образа: `packages.x86_64`; рабочий стол: `overlay/airootfs/usr/share/mino/packages-desktop.txt`
  (тот же список использует установщик).
- Параметры zram/sysctl: `overlay/airootfs/etc/...`; установщик копирует их в систему.
- `linux-firmware` в установщике ставится целиком (сотни МБ): при медленной сети замените
  его в массиве `PKGS` на нужные вендорные пакеты.

## Что не проверено (проверьте до использования на «живом» диске)

1. Сама сборка `mkarchiso` (ни разу не запускалась). Если `build.sh` остановится с сообщением о формате releng:
   проверьте `/usr/share/archiso/configs/releng`, структура могла измениться.
2. Имена пакетов (`pcmanfm-gtk3`, `firefox-ublock-origin`, `obconf` и др.): preflight покажет несуществующие.
3. `mino-install` ни разу не запускался на реальном диске: сначала прогоните в виртуальной машине
   (QEMU/VirtualBox с пустым диском), и только потом на железе. Он стирает диск целиком.
4. Консоль live-образа использует шрифт `cyr-sun16` для кириллицы; если текст отображается кракозябрами,
   выполните `setfont cyr-sun16`.
5. Live-сессия работает от root (как стандартный образ Arch).
