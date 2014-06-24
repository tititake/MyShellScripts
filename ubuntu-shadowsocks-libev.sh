#!/bin/bash

#===============================================================================================
#   System Required:  Debian 7+ or Ubuntu 12+ (32bit/64bit)
#   Description:  Install Shadowsocks(libev) for Debian or Ubuntu
#   Author: Teddysun <i@teddysun.com>
#   Intro:  http://teddysun.com/358.html
#===============================================================================================

echo ""
echo "#############################################################"
echo "# Install Shadowsocks(libev) for Debian or Ubuntu (32bit/64bit)"
echo "# Author: Teddysun <i@teddysun.com>"
echo "#############################################################"
echo ""

WANIF=`ip route get 8.8.8.8 | awk '{ for(f=0;f<NF;f++){if($f=="dev"){print $(f+1);exit;}} }'`
WANIP=`ip route get 8.8.8.8 | awk '{ print $NF; exit }'`
IP="0.0.0.0"
PORT="23456"
PASSWORD="eeettt888"

function error() {
    echo -e "\e[0;31m $* \e[0m"
    exit 1
}

function info() {
    echo -e "\e[0;32m $* \e[0m"
}

# Install Shadowsocks-libev
function install_shadowsocks_libev(){
    rootness
    pre_install
    download_files
    install
	config_shadowsocks
}

# Make sure only root can run our script
function rootness(){
	if [[ $EUID -ne 0 ]]; then
		error "Error:This script must be run as root!" 1>&2
	fi
}

# Pre-installation settings
function pre_install(){

    if [ -f /usr/bin/ss-server ];then
        error "Found /usr/bin/ss-server, seems shadowsocks already installed."
    fi

    #Set shadowsocks-libev config password

    echo "Please input password for shadowsocks-libev:"
	read -p "Choose your Server Port (Default : $PORT):" _port
    if [ "$_port" != "" ]; then
        PORT=$_port
    fi
    read -p "Choose your Server Port (Default : $PASSWORD):" _pwd
    if [ "$_pwd" != "" ]; then
        PASSWORD=$_pwd
    fi
	echo "####################################"
	echo "Server IP   : $IP"
	echo "Server Port : $PORT"
    echo "Password    : $PASSWORD"
    echo "####################################"
    get_char(){
        SAVEDSTTY=`stty -g`
        stty -echo
        stty cbreak
        dd if=/dev/tty bs=1 count=1 2> /dev/null
        stty -raw
        stty echo
        stty $SAVEDSTTY
    }
    echo ""
    echo "Press any key to start...or Press Ctrl+C to cancel"
    char=`get_char`
}

# Download latest shadowsocks-libev
function download_files(){
    grep "http://shadowsocks.org/debian" /etc/apt/sources.list > /dev/null|| (\
    echo "deb http://shadowsocks.org/debian wheezy main" >> /etc/apt/sources.list && \
    apt-get update)
}

# Config shadowsocks
function config_shadowsocks(){
    rm /etc/shadowsocks/config.json
    cat >>/etc/shadowsocks/config.json<<-EOF
{
    "server":"${IP}",
    "server_port":${PORT},
    "local_address":"127.0.0.1",
    "local_port":1080,
    "password":"${PASSWORD}",
    "timeout":600,
    "method":"aes-256-cfb"
}
EOF
}

# Install 
function install(){
    
	apt-get install shadowsocks || error "Install shadowsocks failed!"
    #update-rc.d shadowsocks defaults
    /etc/init.d/shadowsocks restart   

	echo ""
	info "Congratulations, shadowsocks-libev install completed!"
	info "You could change your settings in /etc/shadowsocks/config.json ."
	echo ""
}



install_shadowsocks_libev

