# MinoLinux ISO

MinoLinux is a lightweight Arch-based distribution for old hardware. The system stays plain Arch: packages come from the
official repositories, and `/etc/os-release` is not replaced (pacman updates would revert it). Branding covers the image
name, the volume label, the boot menu entries and the GRUB entry (GRUB itself appends "Linux" to "Mino").
Output file: `out/minolinux-<date>-x86_64.iso`.

This is an `archiso` project: a live/install image with the tuning from the guide
(linux-lts, zram + lz4, sysctl, bfq for HDDs, Openbox + tint2, Firefox/mpv, earlyoom, ext4 with noatime).
The image is **x86_64 only** (Athlon II, Core 2 Duo and newer), BIOS and UEFI.

> The ISO is **not built** here: the environment where this project was prepared had no access to Arch mirrors
> and no `pacman`/`mkarchiso`. Only script syntax (`bash -n`, shellcheck) and profile preparation against a
> mock releng profile were checked. Everything else needs to be verified on your side: see "Not verified" below.

## Build

On Arch Linux (or in an Arch container), as root:

```bash
sudo pacman -S --needed archiso
tar xzf minolinux-iso.tar.gz && cd minolinux-iso
sudo ./build.sh                 # kernel linux-lts; result: ./out/minolinux-*.iso
```

Without an Arch machine, using Docker:

```bash
docker run --rm -it --privileged -v "$PWD":/work -w /work archlinux:latest \
  bash -c 'pacman -Syu --noconfirm archiso && ./build.sh'
```

Variables: `KERNEL=linux|linux-zen`, `WORK=...` (about 5 GB needed), `OUT=...`,
`PREPARE_ONLY=1` (only prepare the profile so you can inspect it), `SKIP_PREFLIGHT=1`.

How it works: `build.sh` copies the **stock releng profile** from your installed `archiso` package
(so the boot configs always match your archiso version), removes what is not needed (ssh, networkd, iwd, zsh),
applies `overlay/`, swaps the kernel, sets squashfs compression to zstd
(it decompresses faster than xz on an old CPU) and runs `mkarchiso`.
Before building, it checks that every package exists in the repositories.

## Test and write to USB

```bash
run_archiso -i out/minolinux-*.iso          # QEMU, requires the qemu-desktop package
sudo dd if=out/minolinux-*.iso of=/dev/sdX bs=4M status=progress oflag=sync   # sdX: YOUR USB stick
```

## Usage

Boot the image; root is logged in automatically on tty1. Then:

- `startx`: live Openbox session, to judge responsiveness on your hardware;
- `nmtui`: network setup;
- `mino-install`: install onto the ENTIRE selected disk (it asks for the disk, user name, time zone, locale,
  desktop and passwords; to confirm you must type the disk path). BIOS: MBR + GRUB, UEFI: GPT + ESP + GRUB.
  It installs over the network (pacstrap); the ISO itself contains only the installer and the settings;
- or `archinstall`, then apply by hand `/etc/sysctl.d/99-mino.conf`,
  `/etc/systemd/zram-generator.conf`, the udev rule and the kernel parameter `zswap.enabled=0`
  (all of them are present in the live system).

After installation: logging in on tty1 starts Openbox (`touch ~/.nostartx` disables this), and
`SESSION=xfce startx` starts XFCE (if option 2 was chosen). For Firefox, copy `/usr/share/mino/firefox-user.js`
into the profile directory.

In the BIOS, set SATA mode to **AHCI**.

## Customization

- Live image packages: `packages.x86_64`; desktop: `overlay/airootfs/usr/share/mino/packages-desktop.txt`
  (the installer uses the same list).
- zram/sysctl settings: `overlay/airootfs/etc/...`; the installer copies them into the installed system.
- The installer installs `linux-firmware` in full (hundreds of MB): on a slow network, replace it
  in the `PKGS` array with just the vendor packages you need.

## Not verified (check before using on a real disk)

1. The `mkarchiso` build itself has never been run. If `build.sh` stops with a message about the releng format,
   check `/usr/share/archiso/configs/releng`: its structure may have changed.
2. Package names (`pcmanfm-gtk3`, `firefox-ublock-origin`, `obconf`, etc.): the preflight check lists any that do not exist.
3. `mino-install` has never been run on a real disk: try it first in a virtual machine
   (QEMU/VirtualBox with an empty disk), and only then on real hardware. It wipes the whole disk.
4. The live console uses the `cyr-sun16` font so Cyrillic is readable; if text shows as garbage,
   run `setfont cyr-sun16`. Note that the installer prompts and the live-image banner (`/etc/motd`) are written
   in Russian and have not been translated.
5. The live session runs as root (like the standard Arch image).


New update 10.11
