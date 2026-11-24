#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
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
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
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
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release wget curl unzip tar crontabs socat ca-certificates -y >/dev/null 2>&1
        update-ca-trust force-enable >/dev/null 2>&1
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add wget curl unzip tar socat ca-certificates >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"debian" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat ca-certificates -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"ubuntu" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat -y >/dev/null 2>&1
        apt-get install ca-certificates wget -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"arch" ]]; then
        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman -S --noconfirm --needed wget curl unzip tar cron socat >/dev/null 2>&1
        pacman -S --noconfirm --needed ca-certificates wget >/dev/null 2>&1
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/V2bX/V2bX ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service V2bX status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status V2bX | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

install_V2bX() {
    if [[ -e /usr/local/V2bX/ ]]; then
        rm -rf /usr/local/V2bX/
    fi

    mkdir /usr/local/V2bX/ -p
    cd /usr/local/V2bX/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/proxynav/V2bX/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 V2bX 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 V2bX 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 V2bX 最新版本：${last_version}，开始安装"
        wget --no-check-certificate -N --progress=bar -O /usr/local/V2bX/V2bX-linux.zip https://github.com/proxynav/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 V2bX 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/proxynav/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
        echo -e "开始安装 V2bX $1"
        wget --no-check-certificate -N --progress=bar -O /usr/local/V2bX/V2bX-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 V2bX $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip V2bX-linux.zip
    rm V2bX-linux.zip -f
    chmod +x V2bX
    mkdir /etc/V2bX/ -p
    cp geoip.dat /etc/V2bX/
    cp geosite.dat /etc/V2bX/
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/V2bX -f
        cat <<EOF > /etc/init.d/V2bX
#!/sbin/openrc-run

name="V2bX"
description="V2bX"

command="/usr/local/V2bX/V2bX"
command_args="server"
command_user="root"

pidfile="/run/V2bX.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
        echo -e "${green}V2bX ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/V2bX.service -f
        cat <<EOF > /etc/systemd/system/V2bX.service
[Unit]
Description=V2bX Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/V2bX/
ExecStart=/usr/local/V2bX/V2bX server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop V2bX
        systemctl enable V2bX
        echo -e "${green}V2bX ${last_version}${plain} 安装完成，已设置开机自启"
    fi

    if [[ ! -f /etc/V2bX/config.json ]]; then
        cp config.json /etc/V2bX/
        echo -e ""
        echo -e "全新安装，请先参看教程：https://v2bx.v-50.me/，配置必要的内容"
        first_install=true
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service V2bX start
        else
            systemctl start V2bX
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}V2bX 重启成功${plain}"
        else
            echo -e "${red}V2bX 可能启动失败，请稍后使用 V2bX log 查看日志信息，若无法启动，则可能更改了配置格式，请前往 wiki 查看：https://github.com/V2bX-project/V2bX/wiki${plain}"
        fi
        first_install=false
    fi

    if [[ ! -f /etc/V2bX/dns.json ]]; then
        cp dns.json /etc/V2bX/
    fi
    if [[ ! -f /etc/V2bX/route.json ]]; then
        cp route.json /etc/V2bX/
    fi
    if [[ ! -f /etc/V2bX/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/V2bX/
    fi
    if [[ ! -f /etc/V2bX/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/V2bX/
    fi
    curl -o /usr/bin/V2bX -Ls https://raw.githubusercontent.com/proxynav/V2bX-script/master/V2bX.sh
    chmod +x /usr/bin/V2bX
    if [ ! -L /usr/bin/v2bx ]; then
        ln -s /usr/bin/V2bX /usr/bin/v2bx
        chmod +x /usr/bin/v2bx
    fi
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "V2bX 管理脚本使用方法 (兼容使用V2bX执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "V2bX              - 显示管理菜单 (功能更多)"
    echo "V2bX start        - 启动 V2bX"
    echo "V2bX stop         - 停止 V2bX"
    echo "V2bX restart      - 重启 V2bX"
    echo "V2bX status       - 查看 V2bX 状态"
    echo "V2bX enable       - 设置 V2bX 开机自启"
    echo "V2bX disable      - 取消 V2bX 开机自启"
    echo "V2bX log          - 查看 V2bX 日志"
    echo "V2bX x25519       - 生成 x25519 密钥"
    echo "V2bX generate     - 生成 V2bX 配置文件"
    echo "V2bX update       - 更新 V2bX"
    echo "V2bX update x.x.x - 更新 V2bX 指定版本"
    echo "V2bX install      - 安装 V2bX"
    echo "V2bX uninstall    - 卸载 V2bX"
    echo "V2bX version      - 查看 V2bX 版本"
    echo "------------------------------------------"
    # 首次安装询问是否生成配置文件
    if [[ $first_install == true ]]; then
        read -rp "检测到你为第一次安装V2bX,是否自动直接生成配置文件？(y/n): " if_generate
        if [[ $if_generate == [Yy] ]]; then
            curl -o ./initconfig.sh -Ls https://raw.githubusercontent.com/proxynav/V2bX-script/master/initconfig.sh
            source initconfig.sh
            rm initconfig.sh -f
            generate_config_file
        fi
    fi
}

echo -e "${green}开始安装${plain}"
install_base
install_V2bX $1
