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

dpkg-query -l iptables openvpn openssl> /dev/null || ( \
apt-get update ; \
apt-get install iptables openvpn openssl)

dpkg-query -l easy-rsa | grep ^ii > /dev/null || ( \
apt-get install easy-rsa)

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
source ./vars
./clean-all

echo -e "\n\n\n\n\n\n\n" | ./build-ca

echo "####################################"
echo "Feel free to accept default values"
echo "Wouldn't recommend setting a password here"
echo "Then you'd have to type in the password each time openVPN starts/restarts"
echo "####################################"

echo ""
info "Press [ENTER] 10 times, then press [y] 2 times..."
echo ""

./build-key-server server
./build-dh
cp keys/{ca.crt,ca.key,server.crt,server.key,dh1024.pem} /etc/openvpn/

echo "####################################"
echo "Feel free to accept default values"
echo "This is your client key, you may set a password here but it's not required"
echo "####################################"

echo ""
info "Press [ENTER] 10 times, then press [y] 2 times, again..."
echo ""

./build-key $VPNUSER

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
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $WANIF -j MASQUERADE
iptables-save > /etc/iptables.conf
echo '#!/bin/sh' > /etc/network/if-up.d/iptables
echo "iptables-restore < /etc/iptables.conf" >> /etc/network/if-up.d/iptables
chmod +x /etc/network/if-up.d/iptables

grep '^net.ipv4.ip_forward.*=.*1$' /etc/sysctl.conf > /dev/null || \
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

/etc/init.d/openvpn restart

echo "OpenVPN has been installed.\n
1) Download and Install OpenVPN software from http://openvpn.net/index.php/open-source/downloads.html.
   openvpn-install-2.3.x-I002-i686.exe or openvpn-install-2.3.x-I002-x86_64.exe.
2) Download /root/keys.tgz using winscp or other sftp/scp client such as filezilla.
3) Create a directory named vpn at C:\Program Files\OpenVPN\config\ and untar the content of keys.tgz there.
4) Start openvpn-gui, right click the tray icon go to vpn and click connect."
