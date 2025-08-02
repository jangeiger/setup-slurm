# Setup slurm

This is the documentation and automatic setup scripts for my slurm cluster.
It is generally structured in the following components:

 - DHCP and name server
 - Code distribution server (for distribution cluster-optimized python)
 - Slurm Master Node
 - Slurm Worker Nodes


## Automated installation

If you just want to get started you can just run the fully automated installation scripts.
For the DHCP and name server you have to run

    sudo bash setup-dhcp.sh

on the node which is supposed to host those services.
Next, you set up the master node by running

    sudo bash setup-master.sh

And lastly on each worker node you run

    sudo bash setup-worker.sh

Below, there is an explanation on what those scripts do in detail, in case anything goes wrong.


## DHCP and Name sever

### DHCP server

First, we setup the DHCP and name server to serve all addresses for the cluster.
This allows us to have the management of the IP addresses in a central location instead of giving static IPs device-local.
Also, we do not need to update the hosts.txt on the master node in case we want to add a new worker to the cluster.

It is setup based on a linux server installation (here ubuntu 24.04 server).
We then setup the DHCP server.
This can either be done by running the setup-dhcp.sh script

    bash setup-dhcp.sh

or by following the commands listed below.
For a dhcp server it is required to have a static IP address on the port you want to server the DHCP server.
This can be done by modifying the netplan configuration

    sudo vim /etc/netplan/50-cloud-init.yaml

and adding

    eth0:
      dhcp4: false
      addresses:
        - 192.168.0.1

Next, we install the dhcp server.
We use the apt package isc-dhcp-server which can be installed by running

    sudo apt update
    sudo apt install isc-dhcp-server

Next, we have to setup the DHCP configuration.
This is done in the file located at /etc/dhcp/dhcpd.conf which we open via

    sudo vim /etc/dhcp/dhcpd.conf

There, we add the configuration for the DHCP server.
An example of such a configuration is given below:

    subnet 192.168.0.1 netmask 255.255.255.0 {
        range 192.168.0.10 192.168.0.200;       # The range of IPs that can be assigned to clients
        option routers 192.168.0.1;             # Default gateway (router)
        option subnet-mask 255.255.255.0;       # Subnet mask
        option domain-name-servers 192.168.0.1; # DNS servers
    }

We insert the IP of the device itself as the name server, since we will be hosting our own name server on this same server.
You also have to specify the network interface where the DHCP server should be serving leases:
This config is located at /etc/default/isc-dhcp-server and we again use

    sudo vim /etc/default/isc-dhcp-server

and add

    INTERFACESv4="eth0"

where you have to replace the interface with the correct interface where you want to server the DHCP server.
Now we can start the DHCP server via

    sudo systemctl start isc-dhcp-server

and check if it is running:

    systemctl status isc-dhcp-server

Lastly, we can enable the service to be automatically started on boot-up:

    sudo systemctl enable isc-dhcp-server

### Name server

Additionally, we setup a name server to distribute human-readable addresses.
Again, we have to install the corresponding apt package

    sudo apt install -y bind9 bind9utils bind9-doc

Next, we setup the configuration.
We setup the local bind configuration located at /etc/bind/named.conf.local using

    sudo vim /etc/bind/named.conf.local

There we create a new local zone

    zone "local" {
        type master;
        file "/etc/bind/zones/db.cluster";
    };

We now need to create the corresponding folder

    sudo mkdir -p /etc/bind/zones

where we then edit the zone configuration

    sudo vim /etc/bind/zones/db.cluster

and insert

    $TTL    604800
    @       IN      SOA     ns.cluster. admin.cluster. (
                                 2         ; Serial
                            604800         ; Refresh
                             86400         ; Retry
                           2419200         ; Expire
                            604800 )       ; Negative Cache TTL

    ; Name servers
    @       IN      NS      ns.cluster.

    ; A records
    ns      IN      A       192.168.0.1
    master  IN      A       192.168.0.10
    worker1 IN      A       192.168.0.11
    worker2 IN      A       192.168.0.12

Lastly, we optionally open

    sudo vim /etc/bind/named.conf.options

and set the following options

    options {
        directory "/var/cache/bind";

        forwarders {
            8.8.8.8;  # google DNS
        };

        dnssec-validation auto;

        listen-on { any; };
        allow-query { any; };
    };

Make sure to set the device to resolve the DNS request via the newly setup DNS server via

    sudo resolvectl dns eth0 192.168.0.1


## Setup slurm master

Next, we setup the master node.
Again, this can be either done by the automated install script

    sudo bash setup-master.sh

which executes the commands listed below.


### Setup munge

First, we need to setup munge for the authentication.
It can be installed via

    sudo apt update
    sudo apt install munge libmunge2 libmunge-dev

We check if it is working as expected by running

    munge -n | unmunge | grep STATUS

and looking for Success in the output.
Lastly, we enable munge to automatically start on boot

    sudo systemctl enable munge
    sudo systemctl restart munge

and check one last time if it is working as expected

    sudo systemctl status munge


### Install slurm

We now install slurm via

    sudo apt install slurm-wlm

Before we can start the service, we need to setup the slurm config.
This is done via

    sudo vim /etc/slurm/slurm.conf

Here is a basic minimum working example.
Please modify to your use, or use the HTML slurm config generator:

    # SLURM CONFIGURATION
    ClusterName=cluster1
    SlurmctldHost=<your-hostname-here>

    StateSaveLocation=/var/spool/slurmctld

    # COMPUTE NODES
    NodeName=worker-1 CPUs=8 RealMemory=16000 State=UNKNOWN
    PartitionName=debug Nodes=ALL Default=YES MaxTime=INFINITE State=UP

We are pointing the state save to /var/spool/slurmctld. We now need to create this folder, since slurm will not be executed with root permissions, making it impossible to create this folder.
Thus, we run

    sudo mkdir /var/spool/slurmctld
    sudo chown slurm:slurm /var/spool/slurmctld
    sudo chmod 700 /var/spool/slurmctld

Now we can start the service and check if everything works.

    sudo systemctl restart slurmctld

If you didn't get an error - nice, probably everything is working fine.
But to be sure you can double check

    sudo systemctl status slurmctld

Now everything that is left is setting up the worker node, adding them to the slurm.conf and then you are done!


## Setup slurm worker

The script for setting up a worker node can be executed as follows:

    sudo bash install-worker.sh

Alternatively you can also manually follow the commands listed below.


### Copy config files

We require the key from the master node, as well as the same slurm config on all worker nodes.
Probably the easiest way of achieving this is by using scp.
Here, we copy the cluster configuration from the master node

    scp root@master.cluster:/etc/slurm/slurm.conf /etc/slurm/slurm.conf

and do the same with the munge key for authentication

    scp root@master.cluster:/etc/slurm/slurm.conf /etc/slurm/slurm.conf


### Install munge

We install munge (same as master):

    sudo apt update
    sudo apt install munge libmunge2 libmunge-dev
    sudo systemctl enable munge


### Install slurm

Lastly, we also install slurm:

    sudo apt install slurm-wlm

This time we do not enable the control daemon, but just the "regular" slurm daemon

    systemctl enable slurmd
    systemctl restart slurmd

Now we check the status to make sure everything worked:

    systemctl status slurmd

The node should now also be visible in the slurm queue information

    sinfo


## Setup Accounting

If you want to store data about resource usage permanently, you have to setup a database.
It is recommended to setup this database on a different node than the master node.
This step is also optional, why we explain it at the end
Here, we use a mysql database, which we install via

    sudo apt install mysql-server

We will require this database to be starting automatically and to be running

    sudo systemctl enable  mysql
    sudo systemctl start mysql

Next, we have to setup the database

    sudo mysql -p

Within the sql terminal we run

    CREATE DATABASE slurm_acct_db;

to create a new database.
Lastly, we setup slurm as a user

    CREATE USER 'slurm'@'localhost' IDENTIFIED BY 'slurm_password';
    GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';
    FLUSH PRIVILEGES;

    exit

Now we are done with the setup and have to add the accounting setup to the slurm configuration in /etc/slurm/slurm.conf

    # Accounting
    AccountingStorageType=accounting_storage/slurmdbd
    AccountingStorageHost=slurm-master
    AccountingStorageUser=slurm
    AccountingStoragePort=6819

We could have directly pumped data into mysql by setting the storate type to accounting_storage/mysql, but we use slurmdbd, the official slurm database

    sudo apt install slurmdbd

Which we also have to configure by editing

    sudo vim /etc/slurm/slurmdbd.conf

and inserting

    ArchiveEvents=yes
    ArchiveJobs=yes
    ArchiveResvs=yes
    ArchiveSteps=yes
    ArchiveSuspend=yes
    ArchiveTXN=yes
    ArchiveUsage=yes
    AuthType=auth/munge
    DbdHost=localhost
    DebugLevel=info
    #PurgeEventAfter=1month
    #PurgeJobAfter=12month
    #PurgeResvAfter=1month
    #PurgeStepAfter=1month
    #PurgeSuspendAfter=1month
    #PurgeTXNAfter=12month
    #PurgeUsageAfter=24month
    LogFile=/var/log/slurmdbd.log
    PidFile=/var/run/slurmdbd.pid
    SlurmUser=slurm
    StoragePass=slurm_password
    StorageType=accounting_storage/mysql
    StorageUser=slurm

Make sure that the config file can be read by slurmdbd

    sudo chmod 600 /etc/slurm/slurmdbd.conf
    sudo chown slurm:slurm /etc/slurm/slurmdbd.conf


And setup the scripts for logging

    sudo touch /var/log/slurmdbd.log
    sudo chown slurm:slurm /var/log/slurmdbd.log

Lastly we start the database

    sudo systemctl enable slurmdbd
    sudo systemctl start slurmdbd
