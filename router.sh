if ! [ $(id -u) = 0 ]; then
   echo "The script needs to be run as root."
   exit 1
fi

wgif="wg0"
duckdns_conf_file="./config/duckdns.conf"
interface_conf_file="./config/interface.conf"
peers_conf_file="./config/peers.conf"
portforward_conf_file="./config/portforward.conf"
duck_path="/etc/duckdns"
duck_log="$duck_path/duckdns.log"
duck_script="$duck_path/duckdns.sh"

function uninstall {
	echo removing current vpn-router configuration
	wg-quick down $wgif
	systemctl disable wg-quick@$wgif
	systemctl stop wg-quick@$wgif
	rm /etc/wireguard/$wgif.conf

	echo removing current DuckDNS configuration
	crontab -l > /tmp/crontab.tmp
	sed -e 's/\(^.*duckdns.sh$\)//g' /tmp/crontab.tmp  | crontab
	rm $duck_script
	rm /tmp/crontab.tmp
	rm /etc/wireguard/$wgif.conf
}

function setup_wireguard {
	echo "starting Wireguard VPN configuration"
	sudo apt install -y wireguard
	echo
	echo

	echo "deleteing current wireguard configuration"
	wg-quick down $wgif
	systemctl disable wg-quick@$wgif
	systemctl stop wg-quick@$wgif
	rm /etc/wireguard/$wgif.conf
	
	if [ ! -d "/etc/wireguard" ]; then
		mkdir "/etc/wireguard"
	fi

	# start installing wireguard configuration
	generated_wgconf=./generated-$wgif.conf

	# load wireguard interface configuration
	echo "load wireguard interface configuration"
	cat ./config/interface.conf > $generated_wgconf
	echo >> $generated_wgconf

	# setup port forwarding configuration
	echo "setting up port forwarding"
	echo "PreUp = sysctl -w net.ipv4.ip_forward=1" >> $generated_wgconf
	echo >> $generated_wgconf

	pf_conf=($(cat ./config/portforward.conf \
             | sed -e 's/ //g' \
             | sed -e 's/	//g' \
             | grep -Eo '^(tcp|udp):[0-9]*\:[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\:[0-9]*'))

	#readarray -t pf_conf < ./config/portforward.conf
	for pf in "${pf_conf[@]}"; do
		# split port forwarding rule
		echo "creating port forwarding rule: $pf"
		IFS=':' read -ra pfrule <<< $pf
		proto="${pfrule[0]}"
		src_port="${pfrule[1]}"
		dest_addr="${pfrule[2]}"
		dest_port="${pfrule[3]}"
		
		preup="PreUp = iptables -t nat -A PREROUTING -p $proto --dport $src_port -j DNAT --to-destination $dest_addr:$dest_port"
		postdown="PostDown = iptables -t nat -D PREROUTING -p $proto --dport $src_port -j DNAT --to-destination $dest_addr:$dest_port"
		
		echo $preup >> $generated_wgconf
		echo $postdown >> $generated_wgconf
		echo >> $generated_wgconf
	done

	echo "setting up msqueraded routing"
	echo "PreUp = iptables -t nat -A POSTROUTING -o $wgif -j MASQUERADE" >> $generated_wgconf
	echo "PostDown = iptables -t nat -D POSTROUTING -o $wgif -j MASQUERADE" >> $generated_wgconf
	echo >> $generated_wgconf

	# load peers configuration
	echo "loading peers"
	cat ./config/peers.conf >> $generated_wgconf
	echo >> $generated_wgconf

	# install generated configuration
	echo "installing wireguard configuration"
	mv $generated_wgconf /etc/wireguard/$wgif.conf

	# start wireguarguard interface and
	echo "enabling and starting wireguard interface"
	systemctl start wg-quick@$wgif
	systemctl enable wg-quick@$wgif.service

	echo "wireguard interface started"
	echo
	echo
}

function setup_duckdns {
	echo "starting DuckDNS host names configuration"
	sudo apt install -y curl cron
	echo
	echo

	# uninstall current configuration
	echo "uninstalling current DuckDNS configuration"
	rm -R $duck_path
	crontab -l > /tmp/crontab.tmp
	sed -e 's/\(^.*duckdns.sh$\)//g' /tmp/crontab.tmp  | crontab
	rm /tmp/crontab.tmp

	# create paths
	if [ ! -d "$duck_path" ]; then
		mkdir "$duck_path"
	fi
	rm $duck_script
	touch $duck_script
	chmod 755 $duck_script

	# load configuration and create duck script
	echo "loading configuration and creating duck script"
	
	
	duckdns_conf=($(cat $duckdns_conf_file \
		| sed -e 's/ //g' \
                | sed -e 's/	//g' \
		| grep -Eo '^[0-9a-z]*\.duckdns\.org:[0-9a-fA-F\-]*'))

	for duckhost in "${duckdns_conf[@]}"; do
		IFS=':' read -ra duckhost_part <<< $duckhost
		host="${duckhost_part[0]}"
		token="${duckhost_part[1]}"
		duck_sub_domain="${host%%.*}"

		echo adding DuckDNS host: $host
		update_cmd="echo url=\"https://www.duckdns.org/update?domains=$duck_sub_domain&token=$token&ip=\" | curl -k -o $duck_log -K -"

		# test host
		echo "testing DuckDNS host: $host"
		eval $update_cmd

		# show response
		response=$( cat $duck_log )
		echo "Duck DNS server response for $host : $response"
		if [ "$response" != "OK" ]; then
			echo "DuckDNS Error for $host host. Check your configuration file."
		else
			echo "$host host setup complete."
		fi
		echo

		echo $update_cmd > $duck_script
	done

	# add cron job
	current_cron=$( crontab -l | grep -c $duck_script )
	if [ "$current_cron" -eq 0 ]; then
		echo "Adding cron job for Duck DNS hosts"
		crontab -l | { cat; echo "*/5 * * * * $duck_script"; } | crontab -
	fi
}

case $1 in
--uninstall | -u)
	uninstall
	exit
	;;

--wg-only | -wg)
	setup_wireguard
	exit
	;;

--duckdns-only | -dns)
	setup_duckdns
	exit
	;;

--help | -h)
	echo "
	
	usage: $0 [--help | -wg-only | --duckdns-only | --uninstall]

	Installs the Wireguard VPN software, sets up a VPN interface and a DuckDNS update job, based on the configuration specified int the ./config directory
	
	Available command are:
	--help | -h : shows this help page
	--wg-only | -wg : installs the Wireguard configuration only, without installing DuckDNS's one
	--duckdns-only | -dns : installs the DuckDNS configuration only, without installing Wireguard's one
	--uninstall | -u : removes the Wireguard and DuckDNS configurations completely

	Invoking without arguments installs the entire configuration.

	In the ./config directory four files are needed:
	
	- duckdns.conf: each line contains the duckdns domains and tokens for which the IP address should be updated by this node in the format <full duckdns domain>:<duckdns token>
		example:
			mydomain.duckdns.org:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
			myseconddomain.duckdns.org:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

	- interface.conf: contains the [Interface] part of wireguard configuration, see details on the Wireguard documentation.
		example:
			[Interface]
			Address = 10.10.10.1/32
			ListenPort = 47224
			MTU = 1350
			PrivateKey = ...
	
	- peers.conf: contains one ore more entries for the [Peer] tag of Wireguard, see details on the Wireguard documentation.
		example:
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
	
	- portforward.conf: each line contains a port forward configuration in the form <tcp|udp>:<local port>:<wireguard client IP>:<wireguard client port>.
		example:
			tcp:80:10.10.10.2:8080
			udp:10022:10.10.10.3:22
			tcp:443:10.10.10.3:443

	"
	exit
	;;
*)
	setup_wireguard
	setup_duckdns
	;;
esac

