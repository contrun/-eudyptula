#!/usr/bin/env bash
set -euo pipefail

# adapted from https://gist.github.com/chrisdone/02e165a0004be33734ac2334f215380e

BUILD_DIR="$( cd -- "$(dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
WORKSPACE_DIR="$( cd -- "$(dirname -- "$BUILD_DIR")" &> /dev/null && pwd )"

BUSYBOX_SOURCE="$BUILD_DIR/busybox_source"
BUSYBOX_BUILD="$BUILD_DIR/busybox_build"
INITRAMFS_BUILD="$BUILD_DIR/initramfs_build"

[[ -d "$BUSYBOX_SOURCE" ]] || git clone https://github.com/mirror/busybox.git "$BUSYBOX_SOURCE"
mkdir -p "$BUSYBOX_BUILD"
cd "$BUSYBOX_SOURCE"
if ! [[ -f "$BUSYBOX_BUILD/.config" ]]; then 
  make O="$BUSYBOX_BUILD" defconfig
  sed -iE "s/.*CONFIG_STATIC[ =].*/CONFIG_STATIC=y/g" "$BUSYBOX_BUILD/.config"
fi
cd "$BUSYBOX_BUILD"
make -j install

mkdir -p "$INITRAMFS_BUILD"
cd "$INITRAMFS_BUILD"
mkdir -p bin sbin etc proc sys usr/bin usr/sbin
cp -a "$BUSYBOX_BUILD/_install/"* .

cat >> init << EOF
#!/bin/sh

mount -t proc none /proc
mount -t sysfs none /sys

cat <<!


Boot took $(cut -d' ' -f1 /proc/uptime) seconds

        _       _     __ _                  
  /\/\ (_)_ __ (_)   / /(_)_ __  _   ___  __
 /    \| | '_ \| |  / / | | '_ \| | | \ \/ /
/ /\/\ \ | | | | | / /__| | | | | |_| |>  < 
\/    \/_|_| |_|_| \____/_|_| |_|\__,_/_/\_\ 


Welcome to mini_linux


!
exec /bin/sh
EOF

chmod +x init
find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$BUILD_DIR/initramfs.cpio.gz"

echo 
echo "Running the follow command to start the VM"
python3 -c 'import shlex; import sys; print(shlex.join(sys.argv[1:]))' "$@" qemu-system-x86_64 -kernel "$WORKSPACE_DIR/arch/x86_64/boot/bzImage" -initrd "$BUILD_DIR/initramfs.cpio.gz" -nographic -append "console=ttyS0"
