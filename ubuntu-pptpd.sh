#!/bin/bash
# Quick and dirty pptp VPN install script
# Ubuntu 12+ or Debain 7+
# Reference http://jesin.tk/setup-pptp-vpn-server-debian-ubuntu/


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

cat /dev/ppp 2>&1 | grep "No such device" > /dev/null || \
error "Error : PPP is not enabled, abort."
[[ $EUID -eq 0 ]]   || error "Error : This script must be run as root!"

echo "####################################"
echo "Server IP         : $WANIP"
echo "VPN User          : $VPNUSER"
echo "VPN Password      : $VPNPASS"
echo "####################################"

read -p "Press [ENTER] to continue..."

dpkg-query -l iptables pptpd> /dev/null || ( \
apt-get update ; \
apt-get install -y iptables pptpd)

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

echo '#!/bin/sh' > /etc/ppp/ip-up.d/set_pptp_mtu
echo "ifconfig ppp0 mtu 1500" >> /etc/ppp/ip-up.d/set_pptp_mtu
chmod +x /etc/ppp/ip-up.d/set_pptp_mtu

service pptpd restart

netstat -anp|grep pptpd|grep 1723 > /dev/null 2>&1 && \
info "pptpd service is running, seems everything is OK." || \
error "pptpd service is not running, something wrong happend."