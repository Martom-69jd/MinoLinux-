#!/usr/bin/env bash
# Build the MinoLinux (Arch-based) live/install ISO on top of the stock releng profile from the archiso package.
# Run: ./build.sh (archiso >= 91, no root needed) or sudo ./build.sh
# Variables: KERNEL=linux-lts|linux|linux-zen   WORK=~/minolinux-work   OUT=~/minolinux-out
#            RELENG=/usr/share/archiso/configs/releng   MIRRORLIST=/path/to/mirrorlist
#            PREPARE_ONLY=1   SKIP_PREFLIGHT=1
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KERNEL=${KERNEL:-linux-lts}
RELENG=${RELENG:-/usr/share/archiso/configs/releng}
# Everything lives in the home folder of the real user by default (also when started with sudo)
BUILD_USER=${SUDO_USER:-${USER:-root}}
USER_HOME=$(getent passwd "$BUILD_USER" | cut -d: -f6 || true)
USER_HOME=${USER_HOME:-$HOME}
WORK=${WORK:-$USER_HOME/minolinux-work}
OUT=${OUT:-$USER_HOME/minolinux-out}
P=$WORK/profile
A=$P/airootfs

msg() { printf '\n==> %s\n' "$*"; }
die() { echo "Error: $*" >&2; exit 1; }

case $KERNEL in linux|linux-lts|linux-zen) ;; *) die "KERNEL must be linux, linux-lts or linux-zen" ;; esac
[[ -n $WORK && $WORK != / ]] || die "invalid WORK"
if [[ -z ${PREPARE_ONLY:-} ]]; then
  command -v mkarchiso >/dev/null || die "mkarchiso not found (pacman -S archiso)"
  if [[ $EUID -ne 0 ]]; then
    # archiso >= 91 builds without root (unshare --map-root-user)
    msg "Building without root (requires archiso >= 91)"
  fi
fi
[[ -d $RELENG ]] || die "releng profile not found: $RELENG (install the archiso package)"

msg "Copying the releng profile -> $P"
mkdir -p "$WORK"
rm -rf "$P"
cp -a "$RELENG" "$P"

if [[ $EUID -ne 0 ]]; then
  msg "Building without root: package cache -> $WORK/cache"
  mkdir -p "$WORK/cache"
  sed -i "/^\[options\]/a CacheDir = $WORK/cache" "$P/pacman.conf"
fi

if [[ -n ${MIRRORLIST:-} ]]; then
  [[ -f $MIRRORLIST ]] || die "MIRRORLIST not found: $MIRRORLIST"
  msg "Using custom mirrorlist: $MIRRORLIST"
  install -Dm0644 "$MIRRORLIST" "$P/pacman.d/mirrorlist"
  sed -i "s|/etc/pacman.d/mirrorlist|$P/pacman.d/mirrorlist|g" "$P/pacman.conf"
fi

msg "Removing what is not needed from releng (ssh, systemd-networkd/resolved, iwd, zsh, speech, guest agents)"
find "$A/etc" \( -name 'iwd.service' -o -name 'sshd.service' -o -name 'systemd-network*' \
  -o -name 'systemd-resolved.service' -o -name 'livecd-*' -o -name 'qemu-guest-agent.service' \
  -o -name 'vboxservice.service' -o -name 'vmtoolsd.service' -o -name 'vmware-vmblock-fuse.service' \
  -o -name 'hv_*.service' \) -not -type d -delete
rm -rf "$A/etc/systemd/network" "$A/etc/resolv.conf" "$A/etc/ssh" "$A/etc/zsh" \
       "$A/root/.zlogin" "$A/root/.zshrc"
if [[ -f $A/etc/passwd ]]; then sed -i 's#/usr/bin/zsh#/usr/bin/bash#' "$A/etc/passwd"; fi

msg "Applying the overlay"
cp -a --remove-destination "$HERE/overlay/airootfs/." "$A/"

msg "Package list (kernel: $KERNEL)"
{
  sed "s/@KERNEL@/$KERNEL/" "$HERE/packages.x86_64"
  echo "# --- desktop (packages-desktop.txt) ---"
  cat "$HERE/overlay/airootfs/usr/share/mino/packages-desktop.txt"
} > "$P/packages.x86_64"

if [[ $KERNEL != linux ]]; then
  msg "Switching boot loaders to $KERNEL (the initramfs preset comes from the kernel package)"
  { grep -rlE 'vmlinuz-linux|initramfs-linux' "$P/syslinux" "$P/efiboot" "$P/grub" 2>/dev/null || true; } \
    | xargs -r sed -i -E "s#vmlinuz-linux([[:space:]]|\$)#vmlinuz-$KERNEL\1#g; s#initramfs-linux\.img#initramfs-$KERNEL.img#g"
  echo "Remaining mentions of the old kernel name (should be empty):"
  { grep -rnE "vmlinuz-linux([[:space:]]|\$)|initramfs-linux\.img" "$P/syslinux" "$P/efiboot" "$P/grub" 2>/dev/null || true; }
fi

msg "Branding: MinoLinux in the boot menus (syslinux / systemd-boot / grub)"
{ grep -rl 'Arch Linux' "$P/syslinux" "$P/efiboot" "$P/grub" 2>/dev/null || true; } \
  | xargs -r sed -i 's/Arch Linux/MinoLinux/g'

msg "initramfs: removing the PXE hooks (network/NFS/NBD boot is not needed)"
if [[ -f $A/etc/mkinitcpio.conf.d/archiso.conf ]]; then
  sed -i -E 's/[[:space:]]archiso_pxe_[a-z_]+//g' "$A/etc/mkinitcpio.conf.d/archiso.conf"
  grep -n '^HOOKS' "$A/etc/mkinitcpio.conf.d/archiso.conf" || true
fi

msg "profiledef.sh: image name, zstd squashfs compression (decompresses faster than xz on an old CPU)"
sed -i -E \
  -e 's|^iso_name=.*|iso_name="minolinux"|' \
  -e 's|^iso_label="ARCH_|iso_label="MINO_|' \
  -e 's|^iso_application=.*|iso_application="MinoLinux live/install ISO"|' \
  -e 's|^iso_publisher=.*|iso_publisher="local build"|' \
  -e "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')|" \
  "$P/profiledef.sh"
cat >> "$P/profiledef.sh" <<'EOF'

file_permissions+=(
  ["/usr/local/bin/mino-install"]="0:0:755"
  ["/usr/local/bin/mino-lang"]="0:0:755"
  ["/usr/local/bin/neofetch"]="0:0:755"
  ["/usr/local/bin/screenfetch"]="0:0:755"
  ["/usr/share/mino/skel/.xinitrc"]="0:0:755"
)
EOF
bash -n "$P/profiledef.sh" || die "profiledef.sh does not pass bash -n after the edit (the releng format changed)"

if [[ -n ${PREPARE_ONLY:-} ]]; then msg "Profile prepared: $P (PREPARE_ONLY)"; exit 0; fi

if [[ -z ${SKIP_PREFLIGHT:-} ]]; then
  msg "Checking that every package exists in the repositories (pacman -Si, uses your system pacman.conf)"
  missing=()
  while read -r pkg; do
    pacman -Si "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done < <(sed -E 's/#.*//; /^[[:space:]]*$/d' "$P/packages.x86_64")
  if ((${#missing[@]})); then
    echo "Not found: ${missing[*]}" >&2
    echo "Run pacman -Syu (stale databases?) or fix the package lists. Bypass: SKIP_PREFLIGHT=1" >&2
    exit 1
  fi
fi

msg "Building the ISO (mkarchiso)"
rm -rf "$WORK/w"
mkdir -p "$OUT"
mkarchiso -v -w "$WORK/w" -o "$OUT" "$P"

msg "Done"
ls -lh "$OUT"/*.iso
(cd "$OUT" && sha256sum ./*.iso | tee SHA256SUMS)
# frees several GB in the home folder; archiso leaves read-only dirs (proc/dev/run), make them removable
chmod -R u+rwX "$WORK/w" 2>/dev/null || true
if ! rm -rf "$WORK/w"; then
  echo "Warning: could not remove temporary directory $WORK/w" >&2
fi
if [[ -n ${SUDO_USER:-} ]]; then chown -R "$SUDO_USER:" "$OUT" "$WORK"; fi
echo "ISO saved in: $OUT"
