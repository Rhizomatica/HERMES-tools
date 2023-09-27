#!/bin/bash

INSTALLER_DIR="/root"

cd ${INSTALLER_DIR}
tar xvf hermes-installer.tar.gz
cd hermes-installer
echo -n "Type the station name: "
read station_name

echo "Running the installer for ${station_name}"

./installer.sh ${station_name}

echo "Installation finished!"

systemctl disable installer

echo "Press any key to REBOOT the radio..."
read
reboot
