#!/bin/bash
# Quick and dirty OpenVPN install script
# Tested on debian 5.0 32bit, openvz minimal debian OS template
# and Ubuntu 9.04 32 bit minimal, should work on 64bit images as well
# Please submit feedback and questions at support@vpsnoc.com

# John Malkowski vpsnoc.com 01/18/2010


WANIF=`ip route get 8.8.8.8 | awk '{ for(f=0;f<NF;f++){if($f=="dev"){print $(f+1);exit;}} }'`
WANIP=`ip route get 8.8.8.8 | awk '{ print $NF; exit }'`
PORT=443
VPNUSER="${HOSTNAME}-openvpn"

function error() {
    echo -e "\e[0;31m $* \e[0m"
    exit 1
}

function info() {
    echo -e "\e[0;32m $* \e[0m"
}

[ -c /dev/net/tun ] || error "Error : TUN module is not enabled, abort."
[[ $EUID -eq 0 ]]   || error "Error : This script must be run as root!"

echo "####################################"
echo "Server IP         : $WANIP"
echo "Server Port (UDP) : $PORT"
echo "VPN User          : $VPNUSER"
echo "####################################"

read -p "Press [ENTER] to continue..."

_PKG_COUNT=`dpkg-query -l iptables expect openvpn openssl| grep -c ^ii`
if [ $_PKG_COUNT -ne 4 ]; then
	apt-get update
	apt-get install -y iptables expect openvpn openssl
fi

dpkg-query -l easy-rsa | grep ^ii > /dev/null || \
apt-get install -y easy-rsa

#openvpn 2.3.x with external easy-rsa
if [ -d "/usr/share/easy-rsa/" ]; then
  rm -rf /etc/openvpn/easy-rsa
  cp -R /usr/share/easy-rsa/ /etc/openvpn/
fi

#openvpn 2.2.x with bulitin easy-rsa
if [ -d "/usr/share/doc/openvpn/examples/easy-rsa/2.0" ]; then
  rm -rf /etc/openvpn/easy-rsa
  cp -R /usr/share/doc/openvpn/examples/easy-rsa/2.0 /etc/openvpn/easy-rsa
fi

[ ! -d "/etc/openvpn/easy-rsa" ] && \
  error "Error : OpenVPN and/or easy-rsa install failed, abort."

cd /etc/openvpn/easy-rsa/
chmod +rwx *

sed -i s/KEY_SIZE=2048/KEY_SIZE=1024/g vars
source ./vars > /dev/null 2>&1
./clean-all

echo -e "\n\n\n\n\n\n\n" | ./build-ca > /dev/null 2>&1

if [ -s keys/ca.crt ] && [ -s keys/ca.key ] ; then
	echo ""
	info "Building ca... OK"
	sleep 1
else
	error "Building ca... FAILED, abort.";
fi

expect -c "
        spawn ./build-key-server server
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        expect \"\[\y\/\n\]\"
        send \"y\r\"
        expect \"\[\y\/\n\]\"
        send \"y\r\"
        expect eof" > /dev/null

if [ -s keys/server.crt ] && [ -s keys/server.key ] && [ -s keys/server.csr ] ; then
	echo ""
	info "Building server certs... OK"
	sleep 1
else
	error "Building server certs... FAILED, abort.";
fi

./build-dh > /dev/null 2>&1

if [ -s keys/dh1024.pem ] ; then
	echo ""
	info "Generating DH parameters... OK"
else
	error "Generating DH parameters... FAILED, abort.";
fi

cp keys/{ca.crt,ca.key,server.crt,server.key,dh1024.pem} /etc/openvpn/

expect -c "
        spawn ./build-key $VPNUSER
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        send \"\r\"
        expect \"\[\y\/\n\]\"
        send \"y\r\"
        expect \"\[\y\/\n\]\"
        send \"y\r\"
        expect eof" > /dev/null

if [ -s keys/$VPNUSER.crt ] && [ -s keys/$VPNUSER.key ] && [ -s keys/$VPNUSER.csr ] ; then
	echo ""
	info "Building client certs... OK"
	sleep 1
else
	error "Building client certs... FAILED, abort.";
fi

cd keys/

client="
client
remote $WANIP $PORT
dev tun
comp-lzo
ca ca.crt
cert ${VPNUSER}.crt
key ${VPNUSER}.key
route-delay 2
route-method exe
redirect-gateway def1
dhcp-option DNS 8.8.8.8
verb 3"

echo "$client" > ${VPNUSER}.ovpn

tar czf keys.tgz ca.crt ${VPNUSER}.crt ${VPNUSER}.key ${VPNUSER}.ovpn
mv keys.tgz /root

opvpn="
port $PORT
dev tun
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
ca ca.crt
cert server.crt
key server.key
dh dh1024.pem
push \"route 10.8.0.0 255.255.255.0\"
push \"redirect-gateway\"
comp-lzo
keepalive 10 60
ping-timer-rem
persist-tun
persist-key
group daemon
daemon
duplicate-cn"

echo "$opvpn" > /etc/openvpn/openvpn.conf


echo 1 > /proc/sys/net/ipv4/ip_forward
iptables --list -t nat | grep 10.8.0.0 | grep MASQUERADE > /dev/null || \
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $WANIF -j MASQUERADE
iptables-save > /etc/iptables.conf
echo '#!/bin/sh' > /etc/network/if-up.d/iptables
echo "iptables-restore < /etc/iptables.conf" >> /etc/network/if-up.d/iptables
chmod +x /etc/network/if-up.d/iptables

grep '^net.ipv4.ip_forward.*=.*1$' /etc/sysctl.conf > /dev/null || \
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

service openvpn restart > /dev/null 2>&1

service openvpn status > /dev/null && (
echo ""
info "OpenVPN service is running, installation SUCCESS."
echo ""

echo "OpenVPN has been installed.
1) Download and Install OpenVPN software from http://openvpn.net/index.php/open-source/downloads.html.
   openvpn-install-2.3.x-I002-i686.exe or openvpn-install-2.3.x-I002-x86_64.exe.
2) Download /root/keys.tgz using winscp or other sftp/scp client such as filezilla.
3) Create a directory named vpn at C:\Program Files\OpenVPN\config\ and untar the content of keys.tgz there.
4) Start openvpn-gui, right click the tray icon go to vpn and click connect." 
) || (
echo ""
echo "##########################################################"
lsb_release -s -d
dpkg-query -l iptables expect openvpn openssl easy-rsa
echo "##########################################################"
error "OpenVPN service is not running, something wrong happend, please report with above information."
)