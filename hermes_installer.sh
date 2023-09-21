#!/bin/bash

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

echo "Welcome to the HERMES INSTALLER!"

while true; do
    read -p "Do you wish to proceed (y/n)? " yn
    case $yn in
        [Yy]* ) echo "Call installer"; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
