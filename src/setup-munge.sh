#!/bin/bash

# Setup munge
#
# This script will setup munge required for the slurm authentication

# import log prefix
source prefix.sh 


# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "$ERROR This script must be run as root!"
    exit 1
fi


# Install munge
echo -e "$DEBUG Installing munge..."
sudo apt update -qq || { echo -e "$ERROR Failed to update package list."; exit 1; }
sudo apt install -y munge libmunge2 libmunge-dev || { echo -e "$ERROR Failed to install munge."; exit 1; }

# Check installation
output=$(munge -n | unmunge | grep "STATUS")
if [[ $output == *"Success"* ]]; then
    echo -e "$SUCCESS Munge is installed and working correctly."
else
    echo -e "$ERROR Munge was not installed properly:"
    echo -e "$ERROR: $output"
    exit 1
fi


# enable munge
echo -e "$DEBUG enabling munge to be started on boot and starting service"

sudo systemctl enable munge
sudo systemctl restart munge

# check if it is running
if ! systemctl is-active --quiet munge; then
    echo -e "$ERROR Could not start munge service!"
    echo -e "$ERROR Please check the state via systemctl status munge:"
    systemctl status munge --no-pager
    exit 1
else
    echo -e "$SUCCESS Munge is running as expected - nice!"
fi