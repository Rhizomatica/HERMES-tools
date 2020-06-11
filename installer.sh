#!/bin/bash

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
    ${XTERMINAL} -e "$0 go"
    exit 0
  fi
fi

USE_ZIP=1
HERMES_URL="http://www.telemidia.puc-rio.br/~rafaeldiniz/public_files/floresta"
IMG_NAME="hermes-arm64-v0.1.img"
MD5_NAME="hermes-arm64-v0.1.img.zip.md5"
# DL_URL=""


if ! [ $(id -u) = 0 ]; then
   echo "Error: This script must be run as root. Example:"
   echo "sudo $0"
   exit 1
fi

# Check for dd
if ! [ -x "$(command -v dd)" ]; then
  echo 'Error: dd is not installed.' >&2
  exit 1
fi

# Check for wget
if ! [ -x "$(command -v wget)" ]; then
  echo 'Error: wget is not installed.' >&2
  exit 1
fi


# set Download URL
if [ "${USE_ZIP}" = "1" ]; then
  if ! [ -x "$(command -v unzip)" ]; then
    echo 'Error: unzip is not installed.' >&2
    exit 1
  fi
  DL_URL="${HERMES_URL}/${IMG_NAME}.zip"
else
  DL_URL="${HERMES_URL}/${IMG_NAME}"
fi


echo -n "Type your SD card device (default=/dev/sdb): "
read DEVICE_FILE
if [ -z "${DEVICE_FILE}" ]; then
  DEVICE_FILE="/dev/sdb"
fi

if ! [ -b "${DEVICE_FILE}" ]
then
    echo "Error: ${DEVICE_FILE} is not a HD, SSD or SD device."
    exit 1
fi

echo -n "Are you sure you want to write HERMES to ${DEVICE_FILE}? (anwser yes or no): "
read yn
if [ "${yn}" = "yes" ]; then
  rm -f "${MD5_NAME}"
  wget -q "${HERMES_URL}/${MD5_NAME}"

  # check if file already exists...
  if [ "${USE_ZIP}" = "1" ] && [ -f ${IMG_NAME}.zip ]; then
    if md5sum --status -c ${MD5_NAME} 2> /dev/null; then
      unzip_image
      write_to_sd
    else
      rm -f ${IMG_NAME}.zip
    fi
  elif [ -f ${IMG_NAME} ]; then
    if md5sum --status -c ${MD5_NAME} 2> /dev/null; then
      write_to_sd
    else
      rm -f ${IMG_NAME}
    fi
  fi

  wget -nv --show-progress "${DL_URL}"

  if md5sum --status -c ${MD5_NAME} 2> /dev/null; then

    if [ "${USE_ZIP}" = "1" ]; then
      unzip_image
    fi
    write_to_sd
  else
    echo "Error: HERMES image download failure."
    exit 1
  fi
else
  echo "Error: Please answer \"yes\" to proceed."
  exit 1
fi
