#!/bin/bash

DIRECTORY=/root/system

let i=0 # define counting variable
W=() # define working array
while read -r line; do # process file by file
    let i=$i+1
    W+=($i "$line")
done < <( ls -1 ${DIRECTORY} )
FILE=$(dialog --title "List stations for installation:" --menu "Chose one" 24 80 17 "${W[@]}" 3>&2 2>&1 1>&3) # show dialog and store output
RESULT=$?
clear
if [ $RESULT -eq 0 ]; then # Exit with OK
     echo "${W[$((FILE * 2 -1))]}"
fi

dialog --yesno "Start recoding the image?" 6 25
RESULT=$?
if [[ $RESULT -eq 1 ]]; then
     exit
fi

exit

clear
echo "/home/$CHOICE"

exit

# uucp + mozjpeg
wget http://www.telemidia.puc-rio.br/~rafaeldiniz/public_files/hermes-repo/rafaeldiniz.gpg.key
apt-key add rafaeldiniz.gpg.key
echo deb http://www.telemidia.puc-rio.br/~rafaeldiniz/public_files/hermes-repo/ buster main > /etc/apt/sources.list.d/hermes.conf
apt-get update
apt-get -y install  git apache2 uucp php imagemagick gnupg seccure mozjpeg

# todo: make package
git clone https://github.com/DigitalHERMES/ardopc.git
cd ardop2ofdm
make
make install

# todo: make package
git clone https://github.com/DigitalHERMES/rhizo-uuardop.git
cd rhizo-uuardop
make
make install

rm /var/www/html/index.html

# put config files in place!

systemctl daemon-reload
systemctl enable ardop
systemctl enable uuardopd
