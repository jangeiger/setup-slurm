#!/bin/bash

# Setup slurm master node
#
# This script will setup the slurm master node

# import log prefix
source prefix.sh 


# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "$ERROR This script must be run as root!"
    exit 1
fi


# Install munge
source setup-munge.sh


# Setup slurm

echo -e "$DEBUG Installing slurm..."
sudo apt update -q || { echo -e "$ERROR Failed to update package list."; exit 1; }
sudo apt install -y slurm-wlm || { echo -e "$ERROR Failed to install slurm-wlm."; exit 1; }


# setup basic slurm configuration
# check if config file does not exists
if [ ! -f "/etc/slurm/slurm.conf" ]; then
    echo -e "$DEBUG Setup minimum working example slurm config in /etc/slurm/slurm.conf"
    echo -e "$DEBUG Please modify this config for your use-case"

    cat >> /etc/slurm/slurm.conf <<EOF
    ClusterName=cluster1
    SlurmctldHost=$(hostname)
    StateSaveLocation=/var/spool/slurmctld

    # COMPUTE NODES
    #TODO: You need to define your computational nodes here!
    # NodeName=worker1.cluster CPUs=?? RealMemory=?? State=UNKNOWN
    # PartitionName=main Nodes=ALL Default=YES MaxTime=INFINITE State=UP
EOF
else
    echo -e "$DEBUG Already found slurm configuration - will not modify"
fi


# create required slurm paths
echo -e "$DEBUG Creating slurm paths..."
sudo mkdir /var/spool/slurmctld
sudo chown slurm:slurm /var/spool/slurmctld
sudo chmod 700 /var/spool/slurmctld
# check if slurm is owner
if [ "$(stat -c %U /var/spool/slurmctld)" == "slurm" ]; then
    echo -e "$SUCCESS Setup slurm paths correctly."
else
    echo -e "$ERROR The /vat/spool/slurmctld path is not setup properly. Slurm will probably not be able to start, but we will try anyways."
fi


# start slurm
systemctl enable slurmctld
systemctl restart slurmctld

# check if it is running
if ! systemctl is-active --quiet slurmctld; then
    echo -e "$ERROR Could not start slurmctld service!"
    echo -e "$ERROR Please check the state via systemctl status slurmctld:"
    systemctl status slurmctld --no-pager
    exit 1
else
    echo -e "$SUCCESS slurmctld is running as expected - we are done!"
fi