#!/bin/bash

# Setup slurm worker node
#
# This script will setup the slurm worker node

# import log prefix
source prefix.sh 


# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "$ERROR This script must be run as root!"
    exit 1
fi


echo -e "$DEBUG Setting up $(hostname) as slurm worker node..."

# check if the required configuration files are already present.
if [ -f "/etc/munge/munge.key" && -f "/etc/slurm/slurm.conf" ]; then
    echo -e "$SUCCESS The configuration files for slurm, and the munge key file are already present - Nice!"
else
    # Ask for some installation information
    echo -e "$DEBUG To set up the slurm worker node, we require some files from the master node."
    echo -e "$DEBUG Those are:"
    echo -e "$DEBUG   - munge.key (from /etc/munge/munge.key)"
    echo -e "$DEBUG   - slurm.conf (from /etc/slurm/slurm.conf)"
    echo -e ""
    echo -e "$DEBUG The easiest way for obtaining those is via ssh connection to the controller."
    read -p "Please enter the IP of the master (e.g. master.cluster or 192.168.0.10):" remote_address
    read -p "Please enter the username for ssh access:" remote_user


    echo -e "$DEBUG Obtaining config files from $remote_user@$remote_address."

    if [ ! -f "/etc/munge/munge.key" ]; then
        scp $remote_user@$remote_address:/etc/munge/munge.key etc/munge/munge.key
    fi
    if [ ! -f "/etc/slurm/slurm.conf" ]; then
        scp $remote_user@$remote_address:/etc/slurm/slurm.conf /etc/slurm/slurm.conf
    fi

    if [ -e "/etc/slurm/slurm.conf" ] && [ -e "etc/munge/munge.key" ]; then
        echo -e "$SUCCESS Successfully transferred all files to local machine."
    else
        echo -e "$ERROR The files are not present on this machine. Something went wrong"
        echo -e "$ERROR Please try coping those files manually."
        exit 1
    fi
fi



# Install munge
source setup-munge.sh



# Setup slurm

echo -e "$DEBUG Installing slurm..."
apt update -y || { echo -e "$ERROR Failed to update package list."; exit 1; }
sudo apt install -y slurm-wlm || { echo -e "$ERROR Failed to install slurm-wlm."; exit 1; }


# We already downloaded the slurm configuration from master node, so now we just start the service
echo -e "$DEBUG Starting slurmd..."
systemctl enable slurmd
systemctl restart slurmd

# check if it is running
if ! systemctl is-active --quiet slurmd; then
    echo -e "$ERROR Could not start slurmd service!"
    echo -e "$ERROR Please check the state via systemctl status slurmd:"
    systemctl status slurmd --no-pager
    exit 1
else
    echo -e "$SUCCESS slurmd is running as expected - we are done!"
fi