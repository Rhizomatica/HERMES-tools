#!/bin/bash

# sudo buggy
# show available block devices
# umount the sd card first

USE_ZIP=0
USE_XZ=1
HERMES_URL="http://www.telemidia.puc-rio.br/~rafaeldiniz/public_files/floresta"
IMG_NAME="2023-05-03-raspios-bullseye-arm64-lite.img.xz"
MD5_NAME="2023-05-03-raspios-bullseye-arm64-lite.img.xz.md5"
HERMES_INSTALLER="hermes-installer.tar.gz"
DEVICE_FILE="/dev/mmcblk0"

write_to_sd_from_xz () {

      echo "Writing HERMES image to SD..."
      xzcat ${IMG_NAME} | dd of=${DEVICE_FILE} status=progress
      echo "Done!"
      echo "Press any key to exit, Remove the USB pendrive and reboot."
      read
      exit 0
}


write_to_sd () {

      echo "Writing HERMES image to SD..."
      dd if=${IMG_NAME} of=${DEVICE_FILE} status=progress
      echo "Done. Now place the SD card in the Raspberry Pi!"
      echo "Press any key to exit."
      read
      exit 0
}


unzip_image () {
      echo "Unzipping HERMES image..."
      unzip -u -o ${IMG_NAME}.zip 2> /dev/null
}


if ! [ "$1" = "go" ]; then
  if [[ $DISPLAY ]]; then
    if [ -x "$(command -v xterm)" ]; then
      XTERMINAL="xterm"
    elif [ -x "$(command -v gnome-terminal)" ]; then
      XTERMINAL="gnome-terminal"
    fi
  fi

  if [ -n "$XTERMINAL" ]; then
    if ! [ $(id -u) = 0 ]; then
      ${XTERMINAL} -e "echo \"Installer needs to be called as root. Running with sudo.\"; sudo $0 go"
    else
      ${XTERMINAL} -e "$0 go"
    fi
    exit 0
  fi
fi

if ! [ $(id -u) = 0 ]; then
   echo "Error: This script must be run as root. Example:"
   echo "sudo $0"
   echo "Press any key to exit."
   read
   exit 0
fi

# Check for dd
if ! [ -x "$(command -v dd)" ]; then
  echo 'Error: dd is not installed.' >&2
  echo "Press any key to exit."
  read
  exit 1
fi

if  ! [ -x "$(command -v wget)" ]; then   # Check for wget
    if ! [ -x "$(command -v curl)" ]; then
        echo 'Error: wget and curl are not installed.' >&2
        echo "Press any key to exit."
        read
        exit 1
    else
      DL_CMD="curl -O "
    fi
else
  DL_CMD="wget -nv --show-progress "
fi


# set Download URL
if [ "${USE_ZIP}" = "1" ]; then
  if ! [ -x "$(command -v unzip)" ]; then
    echo "Error: unzip is not installed."
    echo "Press any key to exit."
    read
    exit 1
  fi
  DL_URL="${HERMES_URL}/${IMG_NAME}.zip"
else
  DL_URL="${HERMES_URL}/${IMG_NAME}"
fi


#echo -n "Type your SD card device (default=/dev/sdb): "
#read DEVICE_FILE
#if [ -z "${DEVICE_FILE}" ]; then
#  DEVICE_FILE="/dev/sdb"
#fi

if ! [ -b "${DEVICE_FILE}" ]
then
    echo "Error: ${DEVICE_FILE} is not a HD, SSD or SD device."
    echo "Press any key to exit."
    read
    exit 1
fi

echo -n "Are you sure you want to write HERMES to ${DEVICE_FILE}? (anwser yes or no): "
read yn
if [ "${yn}" = "yes" ]; then
#  rm -f "${MD5_NAME}"
#  ${DL_CMD} "${HERMES_URL}/${MD5_NAME}" 2> /dev/null

  # check if file already exists...
  if [ "${USE_XZ}" = "1" ] && [ -f ${IMG_NAME} ]; then
    if md5sum --status -c ${MD5_NAME} 2> /dev/null; then
      write_to_sd_from_xz
    else
      echo "Error: HERMES installer failure."
      echo "Press any key to exit."
      read
      exit 1
    fi
    echo "System HERMES installed."
    echo "Press any key to continue."
    read
  fi
fi

echo "Copying the HERMES installer.sh"

tar zxvf ${HERMES_INSTALLER}
mount /dev/mmcblk0p2 /mnt/
mv hermes-installer /mnt/root
umount /mnt
