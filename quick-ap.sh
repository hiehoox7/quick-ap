#!/bin/bash
## quick and dirty AP with hostapd and dnsmasq
## exit properly with ctrl-c
### Changes written by m332478

#defining colors
RED='\033[0;31m'
GREEN='\033[1;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHTCYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m' #No Color

clear

echo -n -e "${LIGHTCYAN}"
cat << "EOF"
  ___        _      _           _    ____  
 / _ \ _   _(_) ___| | __      / \  |  _ \ 
| | | | | | | |/ __| |/ /____ / _ \ | |_) |
| |_| | |_| | | (__|   <_____/ ___ \|  __/ 
 \__\_\\__,_|_|\___|_|\_\   /_/   \_\_|    

EOF
echo -n -e "${NC}"

echo -e "[${YELLOW}*${NC}] Exit this script with ${YELLOW}CTRL+C${NC} and it will attempt to clean up properly"

#setting the wireless interface
if [ -z $1 ]; then
   echo -e -n "[${YELLOW}?${NC}] Wireless Interface (e.g ${GREEN}wlan0${NC}):${GREEN} "
   read iface
   echo -e -n "${NC}"
else
   iface=$1
fi

#setting the ssid of our access point
if [ -z $2 ]; then
   echo -e -n "[${YELLOW}?${NC}] SSID (e.g ${GREEN}AndroidAP${NC}) :${GREEN} "
   read ssid
   echo -e -n "${NC}"
else
   ssid=$2
fi

#setting the wireless channel of our access point
echo -e -n "[${YELLOW}?${NC}] Access Point Channel [${GREEN}1-12]${NC}:${GREEN} "
read channel
echo -e -n "${NC}"

# get wep key
function get_wep_key() { 
	echo -e -n "[${YELLOW}?${NC}] WEP Key [must be exactly 5 or 13 ascii characters]: " 
	read wep_key
	if [[  $wep_key =~ ^[a-zA-Z0-9]{5}$ ]] ; then
	   echo -e "${GREEN}Key accepted${NC}"
   elif [[  $wep_key =~ ^[a-zA-Z0-9]{13}$ ]] ; then
		echo -e "${GREEN}Key accepted${NC}"
	else
		echo "[${RED}X${NC}] WEP key must be exactly 5 or 13 characters"
		get_wep_key
	fi
}

# get mac
function get_mac() {
	echo -e -n "[${YELLOW}?${NC}] Enter MAC address in the following format ${GREEN}AB:CD:EF:12:34:56${NC}:${GREEN} "
	read new_mac
	echo -e -n "${NC}"
	if [[  $new_mac =~ ^[a-fA-F0-9]{2}:[a-fA-F0-9]{2}:[a-fA-F0-9]{2}:[a-fA-F0-9]{2}:[a-fA-F0-9]{2}:[a-fA-F0-9]{2}$ ]] ; then
		macchanger --mac=$new_mac ${iface}
   else
		echo "[${RED}X${NC}] MAC Address format not correct."
		get_mac
	fi
}

# ask for WEP
echo -e -n "[${YELLOW}?${NC}] Do you want WEP enabled? [y/n]: "
read wep
case $wep in
	y*)
		get_wep_key
	;;
	*)
	;;
esac

# ask for MAC change
echo -e -n "[${YELLOW}?${NC}] Do you want to change your MAC? [y/n]: "
read changemac
case $changemac in
	y*)
		echo -e -n "[${YELLOW}?${NC}] Custom MAC? [y/n]: "
      read random_mac
		case $random_mac in
			y*)
				get_mac
			;;
			n*)
				ifconfig ${iface} down
				echo ""
				macchanger -a ${iface}
				echo ""
				ifconfig ${iface} up
				sleep 1
			;;
			*)
				echo "[${RED}X${NC}] Invalid choice, keeping current MAC address."
			;;
		esac
	;;
   n*)
	;;
esac

# install packages if need be
if [ $(dpkg-query -W -f='${Status}' dnsmasq 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
  apt-get install dnsmasq
fi
if [ $(dpkg-query -W -f='${Status}' hostapd 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
  apt-get install hostapd
fi

# trap control c
trap ctrl_c INT

function ctrl_c() {
   echo ""
   echo -e "[${YELLOW}*${NC}] Putting ${iface} into managed mode"
   iwconfig ${iface} mode managed
   echo -e "[${YELLOW}*${NC}] Downing ${iface}"
   ifconfig ${iface} down
   echo -e "[${YELLOW}*${NC}] Flushing iptables rules"
   iptables -F
   iptables -F -t nat
   echo -e "[${YELLOW}*${NC}] Resetting ${iface} MAC"
   echo ""
   macchanger -p ${iface}
   echo ""
   echo -e "[${YELLOW}*${NC}] Killing dnsmasq"
   kill -9 `cat /tmp/dnsmasq.run`
   echo -e "[${YELLOW}*${NC}] Upping ${iface}"
   ifconfig ${iface} up
   nmcli radio wifi off	
}


## script begins

# stop and disable services
service hostapd stop
service dnsmasq stop
pkill -9 dnsmasq
pkill -9 hostapd

# bring up ${iface}
nmcli radio wifi off
rfkill unblock wlan
ifconfig ${iface} down
iwconfig ${iface} mode monitor
ifconfig ${iface} 192.168.0.1/24 up

# forwarding and nat
sysctl net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# dns masq conf
cat > /tmp/dnsmasq.conf <<!
bind-interfaces
interface=${iface}
dhcp-range=192.168.0.2,192.168.0.255
!

# hostapd conf
cat > /tmp/hostapd.conf<<!
interface=${iface}
driver=nl80211
ssid=${ssid}
hw_mode=g
channel=${channel}
!

# if WEP key, add to hostapd conf
if [[ -n $wep_key ]]; then echo -e "wep_default_key=0\nwep_key0=\"${wep_key}\"" >> /tmp/hostapd.conf; fi

# run dnsmasq and hostapd
dnsmasq --pid-file=/tmp/dnsmasq.run -C /tmp/dnsmasq.conf
hostapd /tmp/hostapd.conf
