#!/usr/bin/env bash
# hermes-firstboot-check.sh
# HERMES Project
# License: GPLv3
#
# Run on a station flashed with an image from image_installer.sh, after its
# first boot (and once more after one reboot, for the EEPROM settings):
#
#   sudo ./hermes-firstboot-check.sh
#
# Prints PASS / FAIL / INFO for what the image and its first boot should have
# set up. Read-only: it changes nothing on the station.

set -u

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

fails=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
info() { printf 'INFO  %s\n' "$*"; }
check() { local what="$1"; shift; if "$@" > /dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }

echo "== $(hostname -f 2>/dev/null || hostname), $(uptime -p)"
. /etc/os-release && info "$PRETTY_NAME, kernel $(uname -r)"

echo "== First-boot setup"
check "first-boot setup ran (/root/hermes-setup-done.txt)" test -f /root/hermes-setup-done.txt
r="$(systemctl show -p Result --value hermes-1st-boot-setup.service 2>/dev/null)"
[ "$r" = "success" ] && pass "hermes-1st-boot-setup.service result: success" \
  || fail "hermes-1st-boot-setup.service result: ${r:-unknown}"
e="$(systemctl is-enabled hermes-1st-boot-setup.service 2>/dev/null)"
[ "$e" = "disabled" ] && pass "first-boot unit disabled itself" || fail "first-boot unit is $e"
check "the installer is not left in the image" test ! -e /root/hermes-installer

echo "== Storage"
root_dev="$(findmnt -n -o SOURCE /)"
disk="/dev/$(lsblk -n -o PKNAME "$root_dev" 2>/dev/null | head -1)"
info "root $root_dev: $(df -h --output=size / | tail -1 | tr -d ' ') on a $(lsblk -n -d -o SIZE "$disk" 2>/dev/null | tr -d ' ') card"
blocks="$(tune2fs -l "$root_dev" | awk -F: '/^Block count/ {gsub(/ /,"",$2); print $2}')"
reserved="$(tune2fs -l "$root_dev" | awk -F: '/^Reserved block count/ {gsub(/ /,"",$2); print $2}')"
pct="$(awk -v r="$reserved" -v b="$blocks" 'BEGIN { printf "%.1f", 100 * r / b }')"
[ "$pct" = "0.5" ] && pass "root file system reserves 0.5%" || fail "root file system reserves ${pct}% (want 0.5%)"
swap="$(swapon --show=NAME,SIZE --bytes --noheadings 2>/dev/null)"
if echo "$swap" | awk '$2 > 1900000000 { found = 1 } END { exit !found }'; then
  pass "swap: $(echo "$swap" | awk '{printf "%s %.1f GB ", $1, $2 / 1e9}')"
else
  fail "swap: ${swap:-none} (want about 2 GB)"
fi
check "swap size set (/etc/dphys-swapfile)" grep -qx 'CONF_SWAPSIZE=2000' /etc/dphys-swapfile

echo "== EEPROM (applied by the next reboot after the first boot)"
cfg="$(rpi-eeprom-config 2>/dev/null)"
for want in BOOT_ORDER=0xf14 POWER_OFF_ON_HALT=1 BOOT_UART=0 WAKE_ON_GPIO=0; do
  echo "$cfg" | grep -qx "$want" && pass "EEPROM $want" || fail "EEPROM $want (reboot once, then check again)"
done

echo "== System"
w="$(systemctl show -p RuntimeWatchdogUSec --value)"
info "systemd hardware watchdog: $w"
for f in /etc/ssh/ssh_host_ed25519_key.pub; do
  [ -f "$f" ] && info "SSH host key $(ssh-keygen -lf "$f" | awk '{print $2}'), made $(stat -c %y "$f" | cut -d. -f1)"
done
info "machine-id $(cut -c1-12 /etc/machine-id)"
check "WiFi not blocked" sh -c '! rfkill list wifi 2>/dev/null | grep -q "Soft blocked: yes"'
p="$(paq8px 2>&1 | grep -o -m1 'v[0-9]\+')"
[ "$p" = "v217" ] && pass "paq8px $p" || fail "paq8px ${p:-missing} (want v217)"

echo "== Services"
for u in hostapd dnsmasq nginx postfix dovecot mariadb ssh; do
  check "$u is active" systemctl is-active --quiet "$u"
done
for u in modem sbitx radiod uucpd nncp-daemon; do
  systemctl list-unit-files "$u.service" --no-legend 2>/dev/null | grep -q . \
    && info "$u: $(systemctl is-active "$u" 2>/dev/null)"
done
code="$(curl -skL -o /dev/null -w '%{http_code}' https://localhost/ 2>/dev/null)"
[ "$code" = "200" ] && pass "web GUI answers (https://localhost/: 200)" || fail "web GUI: https://localhost/ answered ${code:-nothing}"
code="$(curl -sk -o /dev/null -w '%{http_code}' https://localhost/api/ 2>/dev/null)"
info "web API https://localhost/api/: ${code:-nothing}"

echo
if [ "$fails" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$fails check(s) failed."
fi
exit "$fails"
