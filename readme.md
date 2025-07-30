# Setup slurm

This is the documentation and automatic setup scripts for my slurm cluster.
It is generally structured in the following components:

 - DHCP and name server
 - Code distribution server (for distribution cluster-optimized python)
 - Slurm Master Node
 - Slurm Worker Nodes


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
        option domain-name-servers 192.168.0.1;  # DNS servers
    }

We insert the IP of the device itself as the name server, since we will be hosting our own name server on this same server.
You also have to specify the network interface where the DHCP server should be serving leases:
This config is located at /etc/default/isc-dhcp-server and we again use

    sudo vim /etc/default/isc-dhcp-server

and add

    INTERFACESv4="eth0"

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

