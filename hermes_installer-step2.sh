#!/bin/bash

INSTALLER_DIR="/root"

# download the installer here...

cd ${INSTALLER_DIR}
rm -f hermes-installer.tar.gz
wget --http-user=adm --http-password=0aSgeklPbU60Q http://aco-connexion.org/downloads/hermes-installer.tar.gz
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
