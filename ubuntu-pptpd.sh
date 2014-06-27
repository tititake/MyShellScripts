#!/bin/bash
# Quick and dirty OpenVPN install script
# Tested on debian 5.0 32bit, openvz minimal debian OS template
# and Ubuntu 9.04 32 bit minimal, should work on 64bit images as well
# Please submit feedback and questions at support@vpsnoc.com

# John Malkowski vpsnoc.com 01/18/2010


WANIF=`ip route get 8.8.8.8 | awk '{ for(f=0;f<NF;f++){if($f=="dev"){print $(f+1);exit;}} }'`
WANIP=`ip route get 8.8.8.8 | awk '{ print $NF; exit }'`
VPNUSER="pptp"
VPNPASS="eeettt888"

function error() {
    echo -e "\e[0;31m $* \e[0m"
    exit 1
}

function info() {
    echo -e "\e[0;32m $* \e[0m"
}

[[ $EUID -eq 0 ]]   || error "Error : This script must be run as root!"

echo "####################################"
echo "Server IP         : $WANIP"
echo "VPN User          : $VPNUSER"
echo "VPN Password      : $VPNPASS"
echo "####################################"

read -p "Press [ENTER] to continue..."

dpkg-query -l iptables pptpd> /dev/null || ( \
apt-get update ; \
apt-get install iptables pptpd)

pptpd_conf="
option /etc/ppp/pptpd-options
logwtmp
localip 172.20.1.1
remoteip 172.20.1.2-254"

echo "$pptpd_conf" > /etc/pptpd.conf

pptpd_options="
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
proxyarp
nodefaultroute
lock
nobsdcomp
novj
novjccomp
nologfd
ms-dns 8.8.8.8
ms-dns 8.8.4.4"

echo "$pptpd_options" > /etc/ppp/pptpd-options

chap_secrets="
$VPNUSER * $VPNPASS *
"
echo "$chap_secrets" > /etc/ppp/chap-secrets

echo 1 > /proc/sys/net/ipv4/ip_forward
grep '^net.ipv4.ip_forward.*=.*1$' /etc/sysctl.conf > /dev/null || \
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

iptables --list -t nat | grep 172.20.1.0 | grep MASQUERADE > /dev/null || \
iptables -t nat -A POSTROUTING -s 172.20.1.0/24 -o $WANIF -j MASQUERADE
iptables --list | grep 172.20.1.0 | grep TCPMSS > /dev/null || \
iptables -I FORWARD -p tcp --tcp-flags SYN,RST SYN -s 172.20.1.0/24 -j TCPMSS --clamp-mss-to-pmtu

iptables-save > /etc/iptables.conf
echo '#!/bin/sh' > /etc/network/if-up.d/iptables
echo "iptables-restore < /etc/iptables.conf" >> /etc/network/if-up.d/iptables
chmod +x /etc/network/if-up.d/iptables

service pptpd restart