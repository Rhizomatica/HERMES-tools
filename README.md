
# HERMES-tools
Scripts and tools for HERMES

## Building a station image: `image_installer.sh`

Builds a ready-to-flash SD card image for one HERMES station on Raspberry Pi
OS Lite (arm64), based on **Debian 13 (trixie)**.

```sh
sudo ./image_installer.sh auto hermes-installer.tar.gz estacao1.hermes.radio
```

The steps:

1. `auto` downloads Raspberry Pi OS Lite `RASPIOS_RELEASE` (default
   `2026-09-15`) from `downloads.raspberrypi.com/raspios_lite_arm64`, checks
   it against its published SHA-256, and grows it to 16 GB. Instead of
   `auto`, you can pass the path of an image you already have.
2. The HERMES installer runs inside the image with `systemd-nspawn` (arm64
   through qemu-user binfmt), as `installer.sh -v <station>`.
3. The image boots once in `qemu-system-aarch64 -M raspi4b`, with the
   image's own `kernel8.img` and `bcm2711-rpi-4-b.dtb`. The installer's
   first-boot script finishes the setup and powers the VM off.
4. The image is grown to 30 GB, defragmented, has its free space zeroed,
   and is compressed to `<station>.img.gz` with an `.md5`.

The script runs without a terminal, so it can go in the background:
`sudo ./image_installer.sh ... < /dev/null > build.log 2>&1`. Expect a few
hours; the installer runs under emulation.

### What you need

- **Host packages:** `systemd-container qemu-user-binfmt qemu-system-arm
  qemu-utils parted e2fsprogs zerofree pigz xz-utils wget`. QEMU 9 or later
  is needed for `-M raspi4b`.
- **A hermes-installer tarball with a top-level `hermes-installer/`
  directory**, from main at `40987c6` or later. Earlier installers stop
  inside systemd-nspawn: at `apt-get update`, because `umask 077` from the
  station secrets step stays in effect (hermes-installer#44), or right
  after "Installing Mercury", on a `systemctl daemon-reload` with no
  running systemd (#45). To make one:

  ```sh
  git -C hermes-installer archive --prefix=hermes-installer/ -o hermes-installer.tar.gz main
  ```

- **A station file** for the station, in the installer's `stations/`.

### Keep images private

An image contains that station's private keys (SSH host keys, NNCP keys, TLS
key, VPN keys) and its passwords (`/etc/hermes/secrets`). Build one image per
station, and never publish an image on a public server.
