#!/usr/bin/env bash
# Сборка live/install ISO «MinoLinux» (Arch-based) поверх штатного профиля releng из пакета archiso.
# Запуск (root, на Arch или в Arch-контейнере):   sudo ./build.sh
# Переменные: KERNEL=linux-lts|linux|linux-zen   WORK=/var/tmp/mino-work   OUT=./out
#             RELENG=/usr/share/archiso/configs/releng   PREPARE_ONLY=1   SKIP_PREFLIGHT=1
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KERNEL=${KERNEL:-linux-lts}
RELENG=${RELENG:-/usr/share/archiso/configs/releng}
WORK=${WORK:-/var/tmp/mino-work}
OUT=${OUT:-$HERE/out}
P=$WORK/profile
A=$P/airootfs

msg() { printf '\n==> %s\n' "$*"; }
die() { echo "Ошибка: $*" >&2; exit 1; }

case $KERNEL in linux|linux-lts|linux-zen) ;; *) die "KERNEL: linux, linux-lts или linux-zen" ;; esac
[[ -n $WORK && $WORK != / ]] || die "некорректный WORK"
if [[ -z ${PREPARE_ONLY:-} ]]; then
  [[ $EUID -eq 0 ]] || die "запустите от root: sudo ./build.sh"
  command -v mkarchiso >/dev/null || die "не найден mkarchiso (pacman -S archiso)"
fi
[[ -d $RELENG ]] || die "нет профиля releng: $RELENG (установите пакет archiso)"

msg "Копирую профиль releng -> $P"
mkdir -p "$WORK"
rm -rf "$P"
cp -a "$RELENG" "$P"

msg "Убираю из releng лишнее (ssh, systemd-networkd/resolved, iwd, zsh, озвучка, гостевые агенты)"
find "$A/etc" \( -name 'iwd.service' -o -name 'sshd.service' -o -name 'systemd-network*' \
  -o -name 'systemd-resolved.service' -o -name 'livecd-*' -o -name 'qemu-guest-agent.service' \
  -o -name 'vboxservice.service' -o -name 'vmtoolsd.service' -o -name 'vmware-vmblock-fuse.service' \
  -o -name 'hv_*.service' \) -not -type d -delete
rm -rf "$A/etc/systemd/network" "$A/etc/resolv.conf" "$A/etc/ssh" "$A/etc/zsh" \
       "$A/root/.zlogin" "$A/root/.zshrc"
if [[ -f $A/etc/passwd ]]; then sed -i 's#/usr/bin/zsh#/usr/bin/bash#' "$A/etc/passwd"; fi

msg "Накладываю overlay"
cp -a --remove-destination "$HERE/overlay/airootfs/." "$A/"

msg "Список пакетов (ядро: $KERNEL)"
{
  sed "s/@KERNEL@/$KERNEL/" "$HERE/packages.x86_64"
  echo "# --- рабочий стол (packages-desktop.txt) ---"
  cat "$HERE/overlay/airootfs/usr/share/mino/packages-desktop.txt"
} > "$P/packages.x86_64"

if [[ $KERNEL != linux ]]; then
  msg "Переключаю загрузчики и initramfs-пресет на $KERNEL"
  [[ -f $A/etc/mkinitcpio.d/linux.preset ]] \
    || die "в releng нет airootfs/etc/mkinitcpio.d/linux.preset: формат профиля изменился, см. README"
  sed -E "s#vmlinuz-linux#vmlinuz-$KERNEL#g; s#initramfs-linux#initramfs-$KERNEL#g" \
    "$A/etc/mkinitcpio.d/linux.preset" > "$A/etc/mkinitcpio.d/$KERNEL.preset"
  rm -f "$A/etc/mkinitcpio.d/linux.preset"
  { grep -rlE 'vmlinuz-linux|initramfs-linux' "$P/syslinux" "$P/efiboot" "$P/grub" 2>/dev/null || true; } \
    | xargs -r sed -i -E "s#vmlinuz-linux([[:space:]]|\$)#vmlinuz-$KERNEL\1#g; s#initramfs-linux\.img#initramfs-$KERNEL.img#g"
  echo "Оставшиеся упоминания старого имени ядра (должно быть пусто):"
  { grep -rnE "vmlinuz-linux([[:space:]]|\$)|initramfs-linux\.img" "$P/syslinux" "$P/efiboot" "$P/grub" 2>/dev/null || true; }
fi

msg "Брендинг: MinoLinux в меню загрузки (syslinux / systemd-boot / grub)"
{ grep -rl 'Arch Linux' "$P/syslinux" "$P/efiboot" "$P/grub" 2>/dev/null || true; } \
  | xargs -r sed -i 's/Arch Linux/MinoLinux/g'

msg "initramfs: убираю PXE-хуки (сеть/NFS/NBD в образе не нужны)"
if [[ -f $A/etc/mkinitcpio.conf.d/archiso.conf ]]; then
  sed -i -E 's/[[:space:]]archiso_pxe_[a-z_]+//g' "$A/etc/mkinitcpio.conf.d/archiso.conf"
  grep -n '^HOOKS' "$A/etc/mkinitcpio.conf.d/archiso.conf" || true
fi

msg "profiledef.sh: имя образа, сжатие squashfs zstd (быстрее распаковка на старом CPU)"
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
  ["/usr/share/mino/skel/.xinitrc"]="0:0:755"
)
EOF
bash -n "$P/profiledef.sh" || die "profiledef.sh после правки не проходит bash -n (формат releng изменился)"

if [[ -n ${PREPARE_ONLY:-} ]]; then msg "Профиль подготовлен: $P (PREPARE_ONLY)"; exit 0; fi

if [[ -z ${SKIP_PREFLIGHT:-} ]]; then
  msg "Проверяю, что все пакеты есть в репозиториях (pacman -Si)"
  missing=()
  while read -r pkg; do
    pacman -Si "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done < <(sed -E 's/#.*//; /^[[:space:]]*$/d' "$P/packages.x86_64")
  if ((${#missing[@]})); then
    echo "Не найдены: ${missing[*]}" >&2
    echo "Выполните pacman -Sy (базы устарели?) либо поправьте списки пакетов. Обход: SKIP_PREFLIGHT=1" >&2
    exit 1
  fi
fi

msg "Сборка ISO (mkarchiso)"
rm -rf "$WORK/w"
mkdir -p "$OUT"
mkarchiso -v -w "$WORK/w" -o "$OUT" "$P"

msg "Готово"
ls -lh "$OUT"/*.iso
(cd "$OUT" && sha256sum ./*.iso | tee SHA256SUMS)
