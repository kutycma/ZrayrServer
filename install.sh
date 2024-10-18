#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as root user!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
else
    echo -e "${red}System version not detected, please contact the script author!${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}Architecture detection failed, using default architecture: ${arch}${plain}"
fi

echo "Architecture: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "This software is not supported on 32-bit systems (x86), please use 64-bit systems (x86_64). If there is an error in detection, please contact the author."
    exit 2
fi


# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Please use CentOS 7 or higher system!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or higher system!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or higher system!${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt-get update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/Zrayr.service ]]; then
        return 2
    fi
    temp=$(systemctl status Zrayr | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_Zrayr() {
    if [[ -e /usr/local/Zrayr/ ]]; then
        rm -rf /usr/local/Zrayr/
    fi

    mkdir /usr/local/Zrayr/ -p
    cd /usr/local/Zrayr/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/kutycma/ZrayrServer/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to check Zrayr version. It may be due to exceeding the Github API limit. Please try again later or manually specify the Zrayr version for installation.${plain}"
            exit 1
        fi
        echo -e "Detected the latest version of Zrayr: ${last_version}, starting installation"
        wget -q -N --no-check-certificate -O /usr/local/Zrayr/Zrayr-linux.zip https://github.com/kutycma/ZrayrServer/releases/download/${last_version}/Zrayr-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download Zrayr. Please make sure your server can download files from Github.${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/kutycma/ZrayrServer/releases/download/${last_version}/Zrayr-linux-${arch}.zip"
        echo -e "Starting installation of Zrayr v$1"
        wget -q -N --no-check-certificate -O /usr/local/Zrayr/Zrayr-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download Zrayr v$1. Please make sure the version exists.${plain}"
            exit 1
        fi
    fi

    unzip Zrayr-linux.zip
    rm Zrayr-linux.zip -f
    chmod +x Zrayr
    mkdir /etc/Zrayr/ -p
    rm /etc/systemd/system/Zrayr.service -f
    file="https://github.com/kutycma/ZrayrServer/raw/master/Zrayr.service"
    wget -q -N --no-check-certificate -O /etc/systemd/system/Zrayr.service ${file}
    #cp -f Zrayr.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl stop Zrayr
    systemctl enable Zrayr
    echo -e "${green}Zrayr ${last_version}${plain} installation completed and set to start on boot"
    cp geoip.dat /etc/Zrayr/
    cp geosite.dat /etc/Zrayr/

    if [[ ! -f /etc/Zrayr/zicboard.yml ]]; then
        cp zicboard.yml /etc/Zrayr/
        echo -e ""
        echo -e "For a fresh installation, please refer to the tutorial: https://github.com/kutycma/ZrayrServer and configure the necessary content"
    else
        systemctl start Zrayr
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}Zrayr restarted successfully${plain}"
        else
            echo -e "${red}Zrayr may have failed to start, please use Zrayr log to view log information. If it cannot be started, it may have changed the configuration format, please go to the wiki for more information: https://github.com/Zrayr-project/Zrayr/wiki${plain}"
        fi
    fi

    if [[ ! -f /etc/Zrayr/dns.json ]]; then
        cp dns.json /etc/Zrayr/
    fi
    if [[ ! -f /etc/Zrayr/route.json ]]; then
        cp route.json /etc/Zrayr/
    fi
    if [[ ! -f /etc/Zrayr/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/Zrayr/
    fi
    if [[ ! -f /etc/Zrayr/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/Zrayr/
    fi
    if [[ ! -f /etc/Zrayr/AikoBlock ]]; then
        cp AikoBlock /etc/Zrayr/
    fi
    curl -o /usr/bin/Zrayr -Ls https://raw.githubusercontent.com/kutycma/ZrayrServer/master/Zrayr.sh
    chmod +x /usr/bin/Zrayr
    ln -s /usr/bin/Zrayr /usr/bin/zrayr # compatible lowercase
    chmod +x /usr/bin/zrayr
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "Usage of Zrayr management script (compatible with Zrayr execution, case-insensitive):"
    echo "------------------------------------------"
    echo "Zrayr              - Show management menu (more functions)"
    echo "Zrayr start        - Start Zrayr"
    echo "Zrayr stop         - Stop Zrayr"
    echo "Zrayr restart      - Restart Zrayr"
    echo "Zrayr status       - Check Zrayr status"
    echo "Zrayr enable       - Set Zrayr to start on boot"
    echo "Zrayr disable      - Disable Zrayr to start on boot"
    echo "Zrayr log          - Check Zrayr logs"
    echo "Zrayr generate     - Generate Zrayr configuration file"
    echo "Zrayr update       - Update Zrayr"
    echo "Zrayr update x.x.x - Update Zrayr to specified version"
    echo "Zrayr install      - Install Zrayr"
    echo "Zrayr uninstall    - Uninstall Zrayr"
    echo "Zrayr version      - Check Zrayr version"
    echo "------------------------------------------"
}

echo -e "${green}Starting installation${plain}"
install_base
install_Zrayr $1
