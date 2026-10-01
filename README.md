
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
3. The installer copy is removed from the image and its package cache
   cleaned.
4. The image is grown to 30 GB, defragmented, has its free space zeroed,
   and is compressed to `<station>.img.gz` with an `.md5`.

There is no emulated first boot (the Raspberry Pi OS trixie kernel doesn't
complete one under QEMU's `raspi4b`). The installer prepares the image for
it instead, and what needs the real hardware (EEPROM boot options, the root
file system's reserved space) runs once, on the station's first boot on its
Raspberry Pi, without powering it off.

The script runs without a terminal, so it can go in the background:
`sudo ./image_installer.sh ... < /dev/null > build.log 2>&1`. Expect a few
hours; the installer runs under emulation.

### What you need

- **Host packages:** `systemd-container qemu-user-binfmt qemu-utils parted
  e2fsprogs zerofree pigz xz-utils wget`.
- **A hermes-installer tarball with a top-level `hermes-installer/`
  directory**, from a main that includes hermes-installer#44, #45, #47,
  the offline first-boot setup (#48), and #49, which gives `pi` its shell
  (Raspberry Pi OS trixie ships it with none). Earlier installers stop inside
  systemd-nspawn:
  - at `apt-get update`, because `umask 077` from the station secrets step
    stays in effect (#44);
  - after "Installing Mercury", on a `systemctl daemon-reload` with no
    running systemd (#45);
  - at "SQL SETUP", when MariaDB takes more than 5 s to start under
    emulation (#47).

  Without #48, the image also expects an emulated first boot that no
  longer happens. To make one:

  ```sh
  git -C hermes-installer archive --prefix=hermes-installer/ -o hermes-installer.tar.gz main
  ```

- **A station file** for the station, in the installer's `stations/`.

### Checking a station after its first boot

Flash the image, boot it on the station's Raspberry Pi, and run
[`hermes-firstboot-check.sh`](hermes-firstboot-check.sh) on it as root. Run it
again after one reboot, which applies the EEPROM settings. It checks:
- that the first-boot setup ran once and the installer is gone;
- the swap and the root file system's reserved space;
- the EEPROM settings;
- paq8px;
- the access point, web, mail and database services.

It also lists the radio services and the station's new SSH host key. It
changes nothing on the station.

### Keep images private

An image contains that station's private keys (SSH host keys, NNCP keys, TLS
key, VPN keys) and its passwords (`/etc/hermes/secrets`). Build one image per
station, and never publish an image on a public server.
