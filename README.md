# MinoLinux ISO

MinoLinux is a lightweight Arch-based distribution for old hardware. The system stays plain Arch: packages come from the
official repositories, and `/etc/os-release` is not replaced (pacman updates would revert it). Branding covers the image
name, the volume label, the boot menu entries and the GRUB entry (GRUB itself appends "Linux" to "Mino").
Output file: `~/minolinux-out/minolinux-<date>-x86_64.iso`.

This is an `archiso` project: a live/install image with the tuning from the guide
(linux-lts, zram + lz4, sysctl, bfq for HDDs, Openbox + tint2, Firefox/mpv, earlyoom, ext4 with noatime).
The image is **x86_64 only** (Athlon II, Core 2 Duo and newer), BIOS and UEFI.

> A working ISO was built from this project on 2026-11-20 (archiso 91, `linux-lts`) and checked with `sha256sum -c`,
> `xorriso` and a QEMU boot in BIOS and UEFI mode. See "Build result" below. The installer itself has not been
> run against a real disk: see "Not verified".

## Build

On Arch Linux (or in an Arch container):

```bash
sudo pacman -S --needed archiso
tar xzf minolinux-iso.tar.gz && cd minolinux-iso
./build.sh                      # archiso >= 91: no root needed; kernel linux-lts
                                # result: ~/minolinux-out/minolinux-*.iso
# or: sudo ./build.sh            # also works as root
```

Without an Arch machine, using Docker:

```bash
docker run --rm -it --privileged -v "$PWD":/work -w /work archlinux:latest \
  bash -c 'pacman -Syu --noconfirm archiso && OUT=/work/out ./build.sh'
```

Everything is stored in your home folder by default (the real user's home, even when run with `sudo`).
In Docker the container's home is not persistent, hence the explicit `OUT=/work/out` above (the ISO appears in `./out`).

Variables: `KERNEL=linux|linux-lts|linux-zen`, `WORK=...` (about 5 GB needed; default `~/minolinux-work`, removed after a successful build), `OUT=...` (default `~/minolinux-out`),
`MIRRORLIST=/path/to/mirrorlist` (use your own fast mirrors if the default ones are slow or return HTTP 429),
`PREPARE_ONLY=1` (only prepare the profile so you can inspect it), `SKIP_PREFLIGHT=1`.

How it works: `build.sh` copies the **stock releng profile** from your installed `archiso` package
(so the boot configs always match your archiso version), removes what is not needed (ssh, networkd, iwd, zsh),
applies `overlay/`, swaps the kernel, sets squashfs compression to zstd
(it decompresses faster than xz on an old CPU) and runs `mkarchiso`.
Before building, it checks that every package exists in the repositories.

## Build without an Arch machine: GitHub Actions

The project includes `.github/workflows/build-iso.yml`, which builds the ISO inside an Arch container on GitHub's
free runners:

1. Create a new GitHub repository and upload the contents of this project (keep the `.github` folder).
2. Open the **Actions** tab, choose **Build MinoLinux ISO**, click **Run workflow**.
3. When the run finishes, download the `minolinux-iso` artifact from the run page (it contains the `.iso` and `SHA256SUMS`).

This workflow has not been run yet. If it fails, the build log shows the failing step; the most likely causes are
listed in "Not verified" below.

## Build result

Built 2026-11-20 in this environment (archiso 91, kernel `linux-lts`, x86_64):

```
~/minolinux-out/minolinux-2026.11.20-x86_64.iso   (1.5 GiB)
sha256: 5a52780c9ed0c6e0b024a1a981916b32b76fed4cd868671a11e9999a78c60c72
```

`~/minolinux-out/SHA256SUMS` contains the checksum; `sha256sum -c SHA256SUMS` passes.
The ISO contains both BIOS (ISOLINUX) and UEFI (systemd-boot) loaders with MinoLinux menu entries,
`vmlinuz-linux-lts`/`initramfs-linux-lts.img`, and a zstd-compressed `airootfs.sfs` with `archiso` initramfs hooks.
Verified in QEMU: both menus boot the LTS kernel; the live system reaches `mino login:` and activates zram swap.

## Test and write to USB

```bash
run_archiso -i ~/minolinux-out/minolinux-*.iso          # QEMU, requires the qemu-desktop package
sudo dd if=~/minolinux-out/minolinux-*.iso of=/dev/sdX bs=4M status=progress oflag=sync   # sdX: YOUR USB stick
```

## Usage

Boot the image; root is logged in automatically on tty1. Then:

- `startx`: live Openbox session, to judge responsiveness on your hardware;
- `nmtui`: network setup;
- `mino-install`: install onto the ENTIRE selected disk (it asks for the disk, host name, user name, time zone,
  desktop, mirrors and passwords; the installed system is English; to confirm you must type the disk path). BIOS: MBR + GRUB, UEFI: GPT + ESP + GRUB.
  It installs over the network (pacstrap); the ISO itself contains only the installer and the settings;
- or `archinstall`, then apply by hand `/etc/sysctl.d/99-mino.conf`,
  `/etc/systemd/zram-generator.conf`, the udev rule and the kernel parameter `zswap.enabled=0`
  (all of them are present in the live system, together with the logo files, the fetch configs and `mino-lang`).

After installation: logging in on tty1 starts Openbox (`touch ~/.nostartx` disables this), and
`SESSION=xfce startx` starts XFCE (if option 2 was chosen). For Firefox, copy `/usr/share/mino/firefox-user.js`
into the profile directory.

In the BIOS, set SATA mode to **AHCI**.

## Logo in fastfetch, neofetch and screenfetch

The logo is the sunset badge with horns, shown as a 40x20-cell truecolor image built from half-block characters
(`/usr/share/mino/logo.ansi`; the transparent PNG is `/usr/share/mino/logo.png`). It works in any terminal with
24-bit color (lxterminal, xterm, ...). On the bare Linux console (tty) colors are only approximated.

- **fastfetch** (installed from the repository): config `~/.config/fastfetch/config.jsonc`, logo type `file-raw`.
- **neofetch**: it no longer appears in the official Arch repositories (the project is archived), so the script
  (MIT, 7.1.0) is bundled as `/usr/local/bin/neofetch`; its license is in `/usr/share/mino/licenses/`.
  Config: `~/.config/neofetch/config.conf`. neofetch measures the logo width by counting characters *including*
  color escape codes, so the config computes that width the same way and compensates with a negative `gap`.
  If you replace the logo, set `_mino_w` in that file to its visible width.
- **screenfetch** (installed from the repository, version 3.9.9 at the time of writing): `/usr/local/bin/screenfetch`
  is a small wrapper that runs the real one with `-a /usr/share/mino/logo.screenfetch` (pass your own `-a` to override).
- Config files come from `/etc/skel` for new users; root in the live session uses symlinks to the same files.
  For an existing user: `mkdir -p ~/.config && cp -r /usr/share/mino/skel/.config/{fastfetch,neofetch} ~/.config/`.
- Other fetch tools (pfetch, hyfetch, macchina, ...) are not configured.
- **Image mode** (terminals with graphics, e.g. kitty/foot): in the fastfetch config use
  `"type": "kitty-direct"` (or `"sixel"`, or `"chafa"` after `pacman -S chafa`) with `"source": "/usr/share/mino/logo.png"`.
  lxterminal cannot display images, so the text logo is the default.
- **Another logo**: needs Pillow and numpy (`pip install pillow numpy`). The shipped logo was produced with
  `python3 tools/png2ansi.py badge.png overlay/airootfs/usr/share/mino/logo.ansi --frame 1 --width 40 --colors 7 --screenfetch overlay/airootfs/usr/share/mino/logo.screenfetch`
  (`--frame` cuts a border, the background is removed automatically, `--colors` limits the palette). The tool prints
  the `_mino_w` value for the neofetch config. Rebuild afterwards.

Make sure you have the right to distribute the logo before publishing the ISO.

Checked with a real fastfetch 2.70.0, the bundled neofetch 7.1.0 and screenfetch (GitHub master) in a sandbox, through
a terminal emulator (both locale modes of neofetch included). Not checked in a real lxterminal or on real hardware.

## Language

The whole system is English: the live image, the installer and the installed system. The language changes only by
command, with `mino-lang`:

```bash
mino-lang list              # supported languages: en ru de fr es it
mino-lang show              # current settings
mino-lang ru                # system-wide (asks for sudo); log out and in, or reboot, afterwards
mino-lang --user de         # only for the current user (the locale must exist: sudo mino-lang --enable de)
mino-lang en                # back to English
```

A system-wide change enables the locale in `/etc/locale.gen` and runs `locale-gen`, writes `LANG` to
`/etc/locale.conf`, sets a console font where one is needed (Cyrillic: `cyr-sun16`), writes the X keyboard layouts to
`/etc/X11/xorg.conf.d/00-keyboard.conf` (second layout switched with Alt+Shift) and installs the Firefox language pack
(`firefox-i18n-<lang>`) if Firefox is present (`--no-packages` skips this). A keyboard file that was not created by
`mino-lang` is never overwritten. Tested against a fake root directory (locale.gen, locale.conf, vconsole.conf and
the keyboard file); `locale-gen`, `pacman`, `sudo` and the per-user locale (`~/.config/locale.conf`, read by Arch's
`/etc/profile.d/locale.sh`) were not exercised on a real system.

## Customization

- Live image packages: `packages.x86_64`; desktop: `overlay/airootfs/usr/share/mino/packages-desktop.txt`
  (the installer uses the same list).
- zram/sysctl settings: `overlay/airootfs/etc/...`; the installer copies them into the installed system.
- The installer installs `linux-firmware` in full (hundreds of MB): on a slow network, replace it
  in the `PKGS` array with just the vendor packages you need.

## Not verified (check before using on a real disk)

1. The build was run with archiso 91; other archiso versions may have a different `releng` layout. If `build.sh`
   stops with a message about the releng format, inspect `/usr/share/archiso/configs/releng`.
2. All package names were checked with `pacman -Si`. The obsolete `pcmanfm-gtk3` and `obconf` were replaced with
   `pcmanfm` and `obconf-qt`. The preflight check lists any other missing packages.
3. `mino-install` has never been run on a real disk: try it first in a virtual machine
   (QEMU/VirtualBox with an empty disk), and only then on real hardware. It wipes the whole disk.
4. Everything the system prints is English. `mino-lang ru` sets the console font `cyr-sun16` (from the `kbd` package);
   this was not checked on a real console. If Cyrillic shows as garbage there, run `setfont cyr-sun16`.
5. The logo/fetch setup and `mino-lang` were verified only in a sandbox (terminal emulation, fake root), see the sections above.
6. The live session runs as root (like the standard Arch image).
