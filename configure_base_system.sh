#!/bin/sh

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
