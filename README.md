# Introduction
This is a simple script for installing and configuring a [Wireguard](https://www.wireguard.com/) entrypoint with a [DuckDNS](https://www.duckdns.org/) IP address updater, based on just four template configuration files.
This script allows you to create an easy-to-manage router that redirects traffic incoming from the internet to your Wireguard peers.

## The most frequent use case
You want to rent a VPS with a public IP (static or dynamic, it doesn't matter at all) in order to gain access to your LAN, from anywhere on the internet.

With this simple script you can rapidly configure your VPN (Virtual Private Network) to attach your hosts to your VPS and make them reachable through your DNS name, registered on [DuckDNS](https://www.duckdns.org/). What you need is to upload the 'wireguard-router' directory to your VPS, modify the four configuration template files based on your needs, and run the 'router.sh' script with no arguments. At the end, you can backup your four configuration files in order to be able to re-configure your router when a VPS failure with loss of data occurs, or just when you want to migrate your VPS provider.

# Configuration files
In the 'config' directory you can find the four configuration files that are used to generate server-side configurations for Wireguard and DuckDNS updates. Let's describe them.

## duckdns.conf
Each line contains the duckdns domains and tokens for which the IP address should be updated by this node in the format:
    
    <full duckdns domain>:<duckdns token>

Example:

    mydomain.duckdns.org:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    myseconddomain.duckdns.org:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

## interface.conf
It contains the ́'''[Interface]''' part of wireguard configuration, see more details on the [Wireguard](https://www.wireguard.com/)  documentation.

Example:

    [Interface]
    Address = 10.10.10.1/32
    ListenPort = 47224
    MTU = 1350
    PrivateKey = ...
	
## peers.conf
It contains one or more entries with the [Peer] tag of Wireguard, see more details on the [Wireguard](https://www.wireguard.com/) documentation.

Example:

    [Peer]
    # my smartphone
    AllowedIPs = 10.10.10.2/32
    PublicKey = ...

    [Peer]
    # my desktop
    AllowedIPs = 10.10.10.3/32
    PublicKey = ...

    [Peer]
    # my laptop
    AllowedIPs = 10.10.10.4/32
    PublicKey = ...
	
## portforward.conf
each line contains a port forward configuration in the form:

    <tcp|udp>:<local port>:<wireguard client IP>:<wireguard client port>.

These are four elements: transport protocol (TCP or UDP), local port where connection incomes from the internet, the destination IP address in the VPN and the destination port.

Example:

    tcp : 80 : 10.10.10.2 : 8080
    udp : 10022 : 10.10.10.3 : 22
    tcp : 443 : 10.10.10.3 : 443

# Usage
Invoke the 'router.sh' script followed by one of the following commands:

    --help | -h : shows the help page
	--wg-only | -wg : installs the Wireguard configuration only, without installing the DuckDNS's one
	--duckdns-only | -dns : installs the DuckDNS configuration only, without installing the Wireguard's one
	--uninstall | -u : removes the Wireguard and DuckDNS configurations completely

Remeber: the 'router.sh' script accepts at most a single command.

Examples:

    # processes the entire 'config' directory and installs Wireguard and DuckDNS configuration
    ./router.sh

    # processes the interface.conf, peers.conf and portforward.conf files only
    ./router.sh --wg-only

    # processes the duckdns.conf file only
    ./router.sh -dns

    # unistall the router: disables the Wireguard interface and removes DuckDNS cron jobs
    ./router.sh -u

# Maintenance use cases
When you need to open a new port for another host in your LAN, you just need to add a new port-forwarding rule to your partforward.conf file and re-run the 'router.sh' script. It will automatically update all the current configuration.

The same procedure is for adding a new peer in your VPN. You will add the new peer to your 'peer.conf' file and re-run the script.

# A more general use case
In a more general example, you have one or more servers (virtual or not, it doesn't matter) and you want to connect them in the same VPN and use some of them as entry points for one or more LAN networks. This script can help you to install your configurations on all servers and update them easily when some modification is needed (e.g., add a new peer, open a new port, add a new DuckDNS domain name). Using this script can be a more scalable solution than the traditional manual configuration of the tools.

