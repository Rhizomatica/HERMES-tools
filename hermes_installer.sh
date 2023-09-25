#!/bin/bash

IMG_NAME="reference-install-image.img.lz"
MD5_NAME="reference-install-image.img.lz.md5"
DEVICE_FILE="/dev/mmcblk0"
INSTALLER_DIR="/root"

write_to_sd_from_plzip () {

      echo "Writing HERMES system image to internal SD card..."
      plzip -c -d ${IMG_NAME} | dd of=${DEVICE_FILE} status=progress
      echo "Done!"
      echo "Press any key to exit, Remove the USB pendrive and reboot."
      read
      exit 0
}

clear
echo "Welcome to the HERMES INSTALLER! Please wait."
sleep 2
clear
echo "Welcome to the HERMES INSTALLER! Please wait.."
sleep 2
clear
echo "Welcome to the HERMES INSTALLER! Please wait..."
sleep 2
clear
echo "Welcome to the HERMES INSTALLER! Please wait...."
sleep 2
clear
echo "Welcome to the HERMES INSTALLER! Please wait....."
sleep 2
clear
echo "Welcome to the HERMES INSTALLER! Please wait......"
sleep 2
clear
echo "Welcome to the HERMES INSTALLER! Please wait......."
sleep 2
clear
echo "Welcome to the HERMES INSTALLER!"

while true; do
    read -p "Do you wish to proceed (y/n)? " yn
    case $yn in
        [Yy]* ) echo "Starting installer..."; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done


# Check for dd
if ! [ -x "$(command -v dd)" ]; then
  echo 'Error: dd is not installed.' >&2
  echo "Press any key to exit."
  read
  exit 1
fi

read -p "Are you sure you want to write HERMES to ${DEVICE_FILE}? (anwser yes or no): "
case $yn in
    [Yy]* ) echo "Checking image integrity before copy...";;
    [Nn]* ) exit;;
    * ) echo "Please answer yes or no.";;
esac


cd ${INSTALLER_DIR}
# check if file alr1eady exists...
if [ -f ${IMG_NAME} ]; then
    if md5sum --status -c ${MD5_NAME} 2> /dev/null; then
        write_to_sd_from_plzip
    else
        echo "Error: HERMES installer failure."
        echo "Press any key to exit."
        read
        exit 1
    fi
    echo "Initial setup done. Configuring the system now..."
    echo "Press any key to continue."
    read
fi

echo "Mouting the newly installed system."
partprobe ${DEVICE_FILE}
mount ${DEVICE_FILE}p2 /mnt
mount ${DEVICE_FILE}p1 /mnt/boot

cp hermes-installer.tar.gz /mnt/root/

cd /mnt

mount -o bind /dev dev
mount -o bind /dev/shm dev/shm
mount -o bind /dev/pts dev/pts
mount -o bind /sys sys
mount -o bind /proc proc

cd root
tar xvf hermes-installer.tar.gz
cd hermes-installer
echo -n "Type the station name: "
read station_name

echo "Running the installer for ${station_name}"

chroot /mnt /root/hermes-installer/installer.sh ${station_name}
