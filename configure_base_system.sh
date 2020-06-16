#!/bin/sh

wget http://www.telemidia.puc-rio.br/~rafaeldiniz/public_files/hermes-repo/rafaeldiniz.gpg.key
apt-key add rafaeldiniz.gpg.key
echo deb http://www.telemidia.puc-rio.br/~rafaeldiniz/public_files/hermes-repo/ buster main > /etc/apt/sources.list.d/hermes.conf
apt-get update
apt-get -y install apache2 uucp php imagemagick gnupg seccure mozjpeg


# install mozjpeg: https://github.com/mozilla/mozjpeg.git


# TODO...
