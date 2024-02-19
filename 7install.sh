#!/usr/bin/env bash
# 检测区
# -------------------------------------------------------------
# 检查系统
export LANG=en_US.UTF-8
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iEm1 "UTF-8|utf8")
[ -n "$UTF8_LOCALE" ] && export LC_ALL="$UTF8_LOCALE" LANG="$UTF8_LOCALE" LANGUAGE="$UTF8_LOCALE"

checkSystem() {
    if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
        mkdir -p /etc/yum.repos.d

        if [[ -f "/etc/centos-release" ]]; then
            centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')

            if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
                centosVersion=8
            fi
        fi

        release="centos"
        installType='yum -y install'
        removeType='yum -y remove'
        upgrade="yum update -y --skip-broken"
        checkCentosSELinux
    elif grep </etc/issue -q -i "debian" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "debian" && [[ -f "/proc/version" ]]; then
        release="debian"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'

    elif grep </etc/issue -q -i "ubuntu" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "ubuntu" && [[ -f "/proc/version" ]]; then
        release="ubuntu"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'
        if grep </etc/issue -q -i "16."; then
            release=
        fi
    fi

    if [[ -z ${release} ]]; then
        echoContent red "\n本脚本不支持此系统，请将下方日志反馈给开发者\n"
        echoContent yellow "$(cat /etc/issue)"
        echoContent yellow "$(cat /proc/version)"
        exit 0
    fi
}

# 检查CPU提供商
checkCPUVendor() {
    if [[ -n $(which uname) ]]; then
        if [[ "$(uname)" == "Linux" ]]; then
            case "$(uname -m)" in
            'amd64' | 'x86_64')
                xrayCoreCPUVendor="Xray-linux-64"
                v2rayCoreCPUVendor="v2ray-linux-64"
                trojanGoCoreCPUVendor="trojan-go-linux-amd64"
                sbCoreCPUVendor="amd"
                warpRegCoreCPUVendor="main-linux-amd64"
                ;;
            'armv8' | 'aarch64')
                cpuVendor="arm"
                xrayCoreCPUVendor="Xray-linux-arm64-v8a"
                v2rayCoreCPUVendor="v2ray-linux-arm64-v8a"
                trojanGoCoreCPUVendor="trojan-go-linux-armv8"
                sbCoreCPUVendor="arm"
                warpRegCoreCPUVendor="main-linux-arm64"
                ;;
            *)
                echo "  不支持此CPU架构--->"
                exit 1
                ;;
            esac
        fi
    else
        echoContent red "  无法识别此CPU架构，默认amd64、x86_64--->"
        xrayCoreCPUVendor="Xray-linux-64"
        trojanGoCoreCPUVendor="trojan-go-linux-amd64"
        sbCoreCPUVendor="amd"
        v2rayCoreCPUVendor="v2ray-linux-64"
    fi
}

# 初始化全局变量
initVar(){
    installType='yum -y install'
    removeType='yum -y remove'
    upgrade="yum -y update"
    echoType='echo -e'
    
    # 核心支持的cpu版本
    xrayCoreCPUVendor=""
    v2rayCoreCPUVendor=""
    trojanGoCoreCPUVendor=""
    sbCoreCPUVendor=""
    warpRegCoreCPUVendor=""
    cpuVendor=""

    # 域名
    domain=
    nginx_port=
    # CDN节点的address
    add=

    # 安装总进度
    totalProgress=1


    # 1.xray-core安装
    # 2.v2ray-core 安装
    # 3.v2ray-core[xtls] 安装
    coreInstallType=

    # 1.全部安装
    # 2.个性化安装
    v2rayAgentInstallType=

    # 当前的个性化安装方式 01234
    currentCustomInstallType=

    # 选择的个性化安装方式
    selectCustomInstallType=

    # v2ray-core配置文件的路径
    v2rayCoreConfigFilePath=

    # xray-core配置文件的路径
    xrayCoreConfigFilePath=

    # 配置文件的path
    currentPath=

    # 配置文件的host
    currentHost=

    # 安装时选择的core类型
    selectCoreType=




    # 默认core版本
    v2rayCoreVersion=

    # 随机路径
    customPath=

    # centos version
    centosVersion=

    # UUID
    currentUUID=
    currentUUIDDirect=
}

# 检测安装方式
readInstallType(){
    coreInstallType=
    v2rayAgentInstallType=
    xrayCoreConfigFilePath=
    v2rayCoreConfigFilePath=

    # 1.检测安装目录
    if [[ -d "/etc/v2ray-agent"  ]]
    then
        # 检测安装方式 v2ray-core
        if [[ -d "/etc/v2ray-agent/v2ray" && -f "/etc/v2ray-agent/v2ray/v2ray" && -f "/etc/v2ray-agent/v2ray/v2ctl" ]]
        then
            if [[ -f "/etc/v2ray-agent/v2ray/config_full.json" ]]
            then
                v2rayAgentInstallType=1
                v2rayCoreConfigFilePath=/etc/v2ray-agent/v2ray/config_full.json
                if [[ ! -z `cat /etc/v2ray-agent/v2ray/config_full.json|grep xtls` ]]
                then
                    coreInstallType=3
                elif [[ -z `cat /etc/v2ray-agent/v2ray/config_full.json|grep xtls` ]]
                then
                    coreInstallType=2
                fi

            elif [[ -d "/etc/v2ray-agent/v2ray/conf" && -f "/etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json" ]]
            then
                v2rayAgentInstallType=2
                v2rayCoreConfigFilePath=/etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json
                if [[ ! -z `cat /etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json|grep xtls` ]]
                then
                    coreInstallType=3
                elif [[ -z `cat /etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json|grep xtls` ]]
                then
                    coreInstallType=2
                fi
            fi
         fi

        if [[ -d "/etc/v2ray-agent/xray" && -f "/etc/v2ray-agent/xray/xray" ]]
        then
            # 这里检测xray-core
            if [[ -f "/etc/v2ray-agent/xray/config_full.json" ]]
            then
                xrayCoreConfigFilePath=/etc/v2ray-agent/xray/config_full.json
                v2rayAgentInstallType=1
                if [[ ! -z `cat /etc/v2ray-agent/xray/config_full.json` ]]
                then
                    coreInstallType=1
                fi

            elif [[ -d "/etc/v2ray-agent/xray/conf" && -f "/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json" ]]
            then
                xrayCoreConfigFilePath=/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json
                v2rayAgentInstallType=2

                if [[ ! -z `cat /etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json` ]]
                then
                    coreInstallType=1
                fi
            fi
        fi
    fi
}

# 检测个性化安装的方式
readCustomInstallType(){
    customConf=
    currentCustomInstallType=
    if [[ "${v2rayAgentInstallType}" = "2" ]]
    then
        local customConf=
        if [[ "${coreInstallType}" = "1" ]]
        then
            customConf="/etc/v2ray-agent/xray/conf"
        else
            customConf="/etc/v2ray-agent/v2ray/conf"
        fi

        while read row
        do
            if [[ ! -z `echo ${row}|grep VLESS_TCP_inbounds` ]]
            then
                currentCustomInstallType=${currentCustomInstallType}'0'
            fi
            if [[ ! -z `echo ${row}|grep VLESS_WS_inbounds` ]]
            then
                currentCustomInstallType=${currentCustomInstallType}'1'
            fi
            if [[ ! -z `echo ${row}|grep VMess_TCP_inbounds` ]]
            then
                currentCustomInstallType=${currentCustomInstallType}'2'
            fi
            if  [[ ! -z `echo ${row}|grep VMess_WS_inbounds` ]]
            then
                currentCustomInstallType=${currentCustomInstallType}'3'
            fi
        done < <(echo `ls ${customConf}|grep -v grep|grep inbounds.json|awk -F "[.]" '{print $1}'`)
    fi
}

# 检查文件目录以及path路径
readConfigHostPathUUID(){
    currentPath=
    currentUUID=
    currentUUIDDirect=
    currentHost=
    # currentPath
    if [[ ! -z "${v2rayCoreConfigFilePath}" ]]
    then
        local path=`cat ${v2rayCoreConfigFilePath}|jq .inbounds[0].settings.fallbacks|jq -c '.[].path'|awk -F "[\"][/]" '{print $2}'|awk -F "[\"]" '{print $1}'|tail -n +2|head -n 1`
        if [[ ! -z "${path}" ]]
        then
            # currentPath=${path:0:4}
           [ "$path" == "*tcp" ] && currentPath=${path%%tcp} || currentPath=${path%%ws}
        fi
    elif [[ ! -z "${xrayCoreConfigFilePath}" ]]
    then
        local path=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.path)' ${xrayCoreConfigFilePath} | head -1| jq -r .path | awk -F "[/]" '{print $2}')
        # local path=`cat ${xrayCoreConfigFilePath}|jq .inbounds[0].settings.fallbacks|jq -c '.[].path'|awk -F "[\"][/]" '{print $2}'|awk -F "[\"]" '{print $1}'|tail -n +2|head -n 1`
        if [[ ! -z "${path}" ]]
        then
            [ "$path" == "*tcp" ] && currentPath=${path%%tcp} || currentPath=${path%%ws}
        fi
    fi

    # currentHost currentUUID currentUUIDDirect
    if [[ "${coreInstallType}" = "1" ]]
    then
        currentHost=`cat ${xrayCoreConfigFilePath}|jq .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile|awk -F '[t][l][s][/]' '{print $2}'|awk -F '["]' '{print $1}'|awk -F '[.][c][r][t]' '{print $1}'`
        # currentHost=$(jq -r .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile ${configPath}${frontingType}.json | awk -F '[t][l][s][/]' '{print $2}' | awk -F '[.][c][r][t]' '{print $1}')
        currentUUID=`cat ${xrayCoreConfigFilePath}|jq .inbounds[0].settings.clients[0].id|awk -F '["]' '{print $2}'`
        currentUUIDDirect=`cat ${xrayCoreConfigFilePath}|jq .inbounds[0].settings.clients[1].id|awk -F '["]' '{print $2}'`
    elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
    then
        currentHost=`cat ${v2rayCoreConfigFilePath}|jq .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile|awk -F '[t][l][s][/]' '{print $2}'|awk -F '["]' '{print $1}'|awk -F '[.][c][r][t]' '{print $1}'`
        currentUUID=`cat ${v2rayCoreConfigFilePath}|jq .inbounds[0].settings.clients[0].id|awk -F '["]' '{print $2}'`
        currentUUIDDirect=`cat ${v2rayCoreConfigFilePath}|jq .inbounds[0].settings.clients[1].id|awk -F '["]' '{print $2}'`
    fi
}

# 清理旧残留
cleanUp(){
    if [[ "$1" = "v2rayClean" ]]
    then
        # rm -rf `ls /etc/v2ray-agent/v2ray|egrep -v '(config_full.json|conf)'`
        handleV2Ray stop > /dev/null 2>&1
        # rm -f /etc/systemd/system/v2ray.service
        systemctl disable v2ray.service > /dev/null 2>&1
    elif [[ "$1" = "xrayClean" ]]
    then
        # rm -rf `ls /etc/v2ray-agent/xray|egrep -v '(config_full.json|conf)'`
        handleXray stop > /dev/null 2>&1
        # rm -f /etc/systemd/system/xray.service
        systemctl disable xray.service > /dev/null 2>&1

    elif [[ "$1" = "v2rayDel" ]]
    then
        rm -rf /etc/v2ray-agent/v2ray/*

    elif [[ "$1" = "xrayDel" ]]
    then
        rm -rf /etc/v2ray-agent/xray/*
    fi
}

initVar
checkSystem
checkCPUVendor
readInstallType
readCustomInstallType
readConfigHostPathUUID


# -------------------------------------------------------------

echoContent(){
    case $1 in
        # 红色
        "red")
            ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # 天蓝色
        "skyBlue")
            ${echoType} "\033[1;36m${printN}$2 \033[0m"
        ;;
        # 绿色
        "green")
            ${echoType} "\033[32m${printN}$2 \033[0m"
        ;;
        # 白色
        "white")
            ${echoType} "\033[37m${printN}$2 \033[0m"
        ;;
        "magenta")
            ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # 黄色
        "yellow")
            ${echoType} "\033[33m${printN}$2 \033[0m"
        ;;
    esac
}

# 初始化安装目录
mkdirTools(){
    mkdir -p /etc/v2ray-agent/tls
    mkdir -p /etc/v2ray-agent/v2ray/conf
    mkdir -p /etc/v2ray-agent/xray/conf
    mkdir -p /etc/v2ray-agent/trojan
    mkdir -p /etc/systemd/system/
    mkdir -p /tmp/v2ray-agent-tls/
}

# 安装工具包
installTools(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装工具"
    
    if [[ -n $(pgrep -f "apt") ]]; then
        pgrep -f apt | xargs kill -9
    fi
    
    echoContent green " ---> 检查、安装更新【新机器会很慢，耐心等待】"
    
    if [[ "${release}" = "centos" ]]
    then
        echoContent green " ---> 检查安装jq、nginx epel源、yum-utils"
        # jq epel源
        if [[ -z `command -v jq` ]]
        then
            rpm -ivh http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm > /dev/null 2>&1
        fi

        nginxEpel=""
        if [[ ! -z `rpm -qa|grep -v grep|grep nginx` ]]
        then
            local nginxVersion=`rpm -qa|grep -v grep|grep nginx|head -1|awk -F '[-]' '{print $2}'`;
            if [[ `echo ${nginxVersion}|awk -F '[.]' '{print $1}'` < 1 ]] && [[ `echo ${nginxVersion}|awk -F '[.]' '{print $2}'` < 17 ]]
            then
                rpm -qa|grep -v grep|grep nginx|xargs rpm -e > /dev/null 2>&1
            fi
        fi
        if [[ "${centosVersion}" = "6" ]]
        then
            nginxEpel="http://nginx.org/packages/centos/6/x86_64/RPMS/nginx-1.18.0-1.el6.ngx.x86_64.rpm"
        elif [[ "${centosVersion}" = "7" ]]
        then
            nginxEpel="http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm"
        elif [[ "${centosVersion}" = "8" ]]
        then
            nginxEpel="http://nginx.org/packages/centos/8/x86_64/RPMS/nginx-1.18.0-1.el8.ngx.x86_64.rpm"
        fi
        # nginx epel源
        rpm -ivh ${nginxEpel} > /etc/v2ray-agent/error.log 2>&1

        # yum-utils
        if [[ "${centosVersion}" = "8" ]]
        then
            upgrade="yum update -y --skip-broken --nobest"
            installType="yum -y install --nobest"
            ${installType} yum-utils > /etc/v2ray-agent/error.log 2>&1
        else
            ${installType} yum-utils > /etc/v2ray-agent/error.log 2>&1
        fi

    fi
    
    # 修复ubuntu个别系统问题
    if [[ "${release}" = "ubuntu" ]]
    then
        dpkg --configure -a
    fi

    ${upgrade} >/etc/v2ray-agent/install.log 2>&1
    if [[ "${release}" = "centos" ]]
    then
        rm -rf /var/run/yum.pid
    fi

    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep -w wget` ]]
    then
        echoContent green " ---> 安装wget"
        ${installType} wget >/dev/null 2>&1
    fi

    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep -w curl` ]]
    then
        echoContent green " ---> 安装curl"
        ${installType} curl >/dev/null 2>&1
    fi

    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep -w unzip` ]]
    then
        echoContent green " ---> 安装unzip"
        ${installType} unzip >/dev/null 2>&1
    fi

    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep -w socat` ]]
    then
        echoContent green " ---> 安装socat"
        ${installType} socat >/dev/null 2>&1
    fi

    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep -w tar` ]]
    then
        echoContent green " ---> 安装tar"
        ${installType} tar >/dev/null 2>&1
    fi

    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep cron` ]]
    then
        echoContent green " ---> 安装crontabs"
        if [[ "${release}" = "ubuntu" ]] || [[ "${release}" = "debian" ]]
        then
            ${installType} cron >/dev/null 2>&1
        else
            ${installType} crontabs >/dev/null 2>&1
        fi
    fi
    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep -w jq` ]]
    then
        echoContent green " ---> 安装jq"
        ${installType} jq >/dev/null 2>&1
    fi

    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep binutils` ]]
    then
        echoContent green " ---> 安装binutils"
        ${installType} binutils >/dev/null 2>&1
    fi
    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep -w nginx` ]]
    then
        echoContent green " ---> 安装nginx"
        ${installType} nginx >/dev/null 2>&1
    fi

    if [[ -z `find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin |grep -v grep|grep -w sudo` ]]
    then
        echoContent green " ---> 安装sudo"
        ${installType} sudo >/dev/null 2>&1
    fi
    
    if ! find /usr/bin /usr/sbin | grep -q -w lsb-release; then
        echoContent green " ---> 安装lsb-release"
        ${installType} lsb-release >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w lsof; then
        echoContent green " ---> 安装lsof"
        ${installType} lsof >/dev/null 2>&1
    fi
    # todo 关闭防火墙
    
    if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
        echoContent green " ---> 安装acme.sh"
        curl -s https://get.acme.sh | sh >/etc/v2ray-agent/tls/acme.log 2>&1

        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
            echoContent red "  acme安装失败--->"
            tail -n 100 /etc/v2ray-agent/tls/acme.log
            echoContent yellow "错误排查:"
            echoContent red "  1.获取Github文件失败，请等待Github恢复后尝试，恢复进度可查看 [https://www.githubstatus.com/]"
            echoContent red "  2.acme.sh脚本出现bug，可查看[https://github.com/acmesh-official/acme.sh] issues"
            echoContent red "  3.如纯IPv6机器，请设置NAT64,可执行下方命令，如果添加下方命令还是不可用，请尝试更换其他NAT64"
            echoContent skyBlue "  echo -e \"nameserver 2001:67c:2b0::4\\\nnameserver 2a00:1098:2c::1\" >> /etc/resolv.conf"
            # exit 0
        fi
    fi

}

# 初始化Nginx申请证书配置
initTLSNginxConfig(){
    handleNginx stop
    echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Nginx申请证书配置"
    if [[ -n "${currentHost}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ${currentHost} ？[y/N]:" historyDomainStatus
        if [ "${historyDomainStatus}" == "y" -o "${historyDomainStatus}" == "Y" ]; then
            domain=${currentHost}
            echoContent yellow "\n ---> 域名: ${domain}"
        fi
    else
        echo
        echoContent yellow "请输入要配置的域名 例: www.v2ray-agent.com --->"
        read -r -p "域名:" domain
        domain=$(echo "$domain" | xargs)
    fi

    if [[ -z ${domain} ]]; then
        echoContent red "  域名不可为空--->"
        initTLSNginxConfig
    else
        # 修改配置
        echoContent green " ---> 配置Nginx"
        touch /etc/nginx/conf.d/alone.conf
        echo "server {listen 80;server_name ${domain};root /usr/share/nginx/html;location ~ /.well-known {allow all;}location /test {return 200 'fjkvymb6len';}}" > /etc/nginx/conf.d/alone.conf
        # 检查日志，解决nginx启动失败
        if [[ ! -f /var/log/nginx/access.log ]]; then
            if [[ ! -d /var/log/nginx ]]; then
                mkdir /var/log/nginx
            fi
            
            touch /var/log/nginx/access.log
            touch /var/log/nginx/error.log
        fi
        
        # 启动nginx
        handleNginx start
        echoContent yellow "\n检查IP是否设置为当前VPS"
        #checkIP
        
        # 测试nginx
        echoContent yellow "\n检查Nginx是否正常访问"
        # domainResult=`curl -s ${domain}/test|grep fjkvymb6len`
        domainResult=1
        if [[ -n ${domainResult} ]]
        then
            handleNginx stop
            echoContent green " ---> Nginx配置成功"
        else
            echoContent red " ---> 无法正常访问服务器，请检测域名是否正确、域名的DNS解析以及防火墙设置是否正确--->"
            # exit 0;
        fi
    fi
}

# 检查ip
checkIP(){
    # pingIP=`ping -c 1 -W 1000 ${domain}|sed '1{s/[^(]*(//;s/).*//;q;}'`
    pingIP=$(curl -s -m 2 "http://${domain}:443/ip")
    if [[ ! -z "${pingIP}" ]] && [[ `echo ${pingIP}|grep '^\([1-9]\|[1-9][0-9]\|1[0-9][0-9]\|2[0-4][0-9]\|25[0-5]\)\.\([0-9]\|[1-9][0-9]\|1[0-9][0-9]\|2[0-4][0-9]\|25[0-5]\)\.\([0-9]\|[1-9][0-9]\|1[0-9][0-9]\|2[0-4][0-9]\|25[0-5]\)\.\([0-9]\|[1-9][0-9]\|1[0-9][0-9]\|2[0-4][0-9]\|25[0-5]\)$'` ]]
    then
        read -p "当前域名的IP为 [${pingIP}]，是否正确[y/n]？" domainStatus
        if [[ "${domainStatus}" = "y" ]]
        then
            echoContent green "\n ---> IP确认完成"
        else
            echoContent red "\n ---> 1.检查Cloudflare DNS解析是否正常"
            echoContent red " ---> 2.检查Cloudflare DNS云朵是否为灰色\n"
            # exit 0;
        fi
    else
        read -p "IP查询失败，是否重试[y/n]？" retryStatus
        if [[ "${retryStatus}" = "y" ]]
        then
            checkIP
        else
            exit 0;
        fi
    fi
}
# 安装TLS
installTLS(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书"
    
    # 增加关闭 nginx， 解决证书申请失败
    handleNginx stop
    if [[ -z `ls /etc/v2ray-agent/tls|grep ${domain}.crt` ]] && [[ -z `ls /etc/v2ray-agent/tls|grep ${domain}.key` ]]
    then
        echoContent green " ---> 安装TLS证书"
        
        local interfaces=("eth0" "eth1" "venet0")
        for iface in "${interfaces[@]}"; do
            local_ip=$(ip -6 addr show dev $iface | grep -v dynamic | grep inet6 | awk -F '[ \t]+|/' '$3 == "::1" { next;} $3 ~ /^fe80::/ { next;} /inet6/ {print $3}' | head -n 1) > /dev/null 2>&1
            [ -n "$local_ip" ] && echo " $LINENO, local_ip=${local_ip}" && break
        done
        if [ -n "$local_ip" ] && echo "${local_ip}" | grep -q ":"; then
            grep -q "^nameserver 2606:4700:4700::1111" /etc/resolv.conf || (sudo sed -i '1s/^/nameserver 2606:4700:4700::1111\n/' /etc/resolv.conf && sudo systemctl restart systemd-resolved)
            grep -q "^nameserver 2001:4860:4860::8844" /etc/resolv.conf || (sudo sed -i '1s/^/nameserver 2001:4860:4860::8844\n/' /etc/resolv.conf && sudo systemctl restart systemd-resolved)
            grep -q "^nameserver 2001:4860:4860::8888" /etc/resolv.conf || (sudo sed -i '1s/^/nameserver 2001:4860:4860::8888\n/' /etc/resolv.conf && sudo systemctl restart systemd-resolved)
            grep -q "^nameserver 2a01:4f8:c2c:123f::1" /etc/resolv.conf || (sudo sed -i '1s/^/nameserver 2a01:4f8:c2c:123f::1\n/' /etc/resolv.conf && sudo systemctl restart systemd-resolved)

            sudo "$HOME/.acme.sh/acme.sh" --issue -d "${domain}" --standalone -k ec-256 --server letsencrypt --listen-v6 | tee -a /etc/v2ray-agent/tls/acme.log >/dev/null
            # sudo "$HOME/.acme.sh/acme.sh" --installcert -d ${domain} --fullchainpath /etc/v2ray-agent/tls/${domain}.crt --keypath /etc/v2ray-agent/tls/${domain}.key --ecc >/dev/null
        else
            sudo "$HOME/.acme.sh/acme.sh" --issue -d "${domain}" --standalone -k ec-256 --server letsencrypt | tee -a /etc/v2ray-agent/tls/acme.log >/dev/null
        fi
        sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${domain}" --fullchainpath "/etc/v2ray-agent/tls/${domain}.crt" --keypath "/etc/v2ray-agent/tls/${domain}.key" --ecc >/dev/null

        if [[ -z `cat /etc/v2ray-agent/tls/${domain}.crt` ]]
        then
            echoContent red " ---> TLS安装失败，请检查acme日志"
            exit 0
        elif [[ -z `cat /etc/v2ray-agent/tls/${domain}.key` ]]
        then
            echoContent red " ---> TLS安装失败，请检查acme日志"
            exit 0
        fi
        echoContent green " ---> TLS生成成功"

    elif  [[ -z `cat /etc/v2ray-agent/tls/${domain}.crt` ]] || [[ -z `cat /etc/v2ray-agent/tls/${domain}.key` ]]
    then
        echoContent yellow " ---> 检测到错误证书，需重新生成，重新生成中"
        rm -rf /etc/v2ray-agent/tls/*
        installTLS $1
    else
        echoContent green " ---> 检测到证书"
        checkTLStatus
        echoContent yellow " ---> 如未过期请选择[n]"
        read -p "是否重新生成？[y/N]:" reInstallStatus
        if [[ "${reInstallStatus}" = "y" ]]
        then
            rm -rf /etc/v2ray-agent/tls/*
            installTLS $1
        fi
    fi
}
# 配置伪装博客
initNginxConfig(){
    echo
    read -r -p "nginx 监听端口 / port（默认 / default 80，注：区别于回源规则 / Origin Rules ）:" nginx_port
    nginx_port=$(echo "${nginx_port}" | xargs)
    if [[ -z "${nginx_port}" ]]; then
        nginx_port=80
    fi
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Nginx"

        cat << EOF > /etc/nginx/conf.d/alone.conf
server {
    listen ${nginx_port};
    listen [::]:${nginx_port};
    server_name ${domain};
    root /usr/share/nginx/html;
    location ~ /.well-known {allow all;}
    location /test {return 200 'fjkvymb6len';}
}
EOF
}

# 初始化随机字符串
initRandomPath() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    for i in {1..4}; do
        echo "${i}" >/dev/null
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    customPath=${initCustomPath}
}

# 自定义/随机路径
randomPathFunction(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 生成随机路径"

    if [[ ! -z "${currentPath}" ]]
    then
        echo
        read -p "读取到上次安装记录，是否使用上次安装时的path路径 ${currentPath} ？[y/N]:" historyPathStatus
        echo
    fi

    if [[ "${historyPathStatus}" = "y" ]]
    then
        customPath=${currentPath}
        echoContent green " ---> 使用成功\n"
    else
        initRandomPath
        # currentPath=${customPath}
        echoContent yellow "请输入自定义路径[例: alone]，不需要斜杠，[回车]默认随机路径 ${customPath} :"
        read -p '路径:' currentPath
        if [[ -n "${currentPath}" ]]
        then
            customPath=${currentPath}
        fi
    fi
    echoContent yellow "path：${customPath}"
    echoContent skyBlue "\n----------------------------"
}
# Nginx伪装博客
nginxBlog(){
#    echoContent yellow "添加伪装博客--->"
    echoContent skyBlue "\n进度 $1/${totalProgress} : 添加伪装博客"
    if [[ -d "/usr/share/nginx/html" && -f "/usr/share/nginx/html/check" ]]
    then echo
        # read -p "检测到安装伪装博客，是否需要重新安装[y/n]：" nginxBlogInstallStatus
        # if [[ "${nginxBlogInstallStatus}" = "y" ]]
        # then
            # rm -rf /usr/share/nginx/html
            # randomNum=$((RANDOM % 6 + 1))
            # wget -q -P /usr/share/nginx https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${randomNum}.zip > /dev/null
            # unzip -o  "/usr/share/nginx/html${randomNum}.zip" -d /usr/share/nginx/html > /dev/null
            # rm -f "/usr/share/nginx/html${randomNum}.zip*"
            # echoContent green " ---> 添加伪装博客成功"
        # fi
    else
        randomNum=$((RANDOM % 6 + 1))
        rm -rf /usr/share/nginx/html
        wget -q -P /usr/share/nginx https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${randomNum}.zip > /dev/null
        unzip -o  "/usr/share/nginx/html${randomNum}.zip" -d /usr/share/nginx/html > /dev/null
        rm -f "/usr/share/nginx/html${randomNum}.zip*"
        echoContent green " ---> 添加伪装博客成功"
    fi

}
# 操作Nginx
handleNginx(){
    if [[ -z $(pgrep -f "nginx") ]] && [[ "$1" == "start" ]]; then
        sudo kill $(sudo lsof -t -i:80) > /dev/null 2>&1
        sudo systemctl disable apache2 > /dev/null 2>&1
        systemctl start nginx 2>/etc/v2ray-agent/nginx_error.log

        sleep 0.5

        if [[ -z $(pgrep -f "nginx") ]]; then
            echoContent red " ---> Nginx启动失败"
            echoContent red " ---> 请手动尝试安装nginx后，再次执行脚本"

            # if grep -q "journalctl -xe" </etc/v2ray-agent/nginx_error.log; then
                # updateSELinuxHTTPPortT
            # fi

            # exit 0
        else
            echoContent green " ---> Nginx启动成功"
        fi

    elif [[ -n $(pgrep -f "nginx") ]] && [[ "$1" == "stop" ]]; then
        systemctl stop nginx
        sleep 0.5
        if [[ -n $(pgrep -f "nginx") ]]; then
            pgrep -f "nginx" | xargs kill -9
        fi
        
        if [[ -n $(pgrep -f "nginx") ]]; then
            nginx -s stop
        fi
        
        echoContent green " ---> Nginx关闭成功"
    fi
}

# 定时任务更新tls证书
installCronTLS(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 添加定时维护证书"
    if [[ -z `crontab -l|grep -v grep|grep 'reloadInstallTLS'` ]]
    then
        crontab -l >> /etc/v2ray-agent/backup_crontab.cron
        # 定时任务
        echo "30 1 * * * /bin/bash /etc/v2ray-agent/reloadInstallTLS.sh" >> /etc/v2ray-agent/backup_crontab.cron
        crontab /etc/v2ray-agent/backup_crontab.cron
    fi
    # 备份

    cat << EOF > /etc/v2ray-agent/reloadInstallTLS.sh
#!/usr/bin/env bash
echoContent(){
    case \$1 in
        # 红色
        "red")
            echo -e "\033[31m\${printN}\$2 \033[0m"
        ;;
        # 天蓝色
        "skyBlue")
            echo -e "\033[1;36m\${printN}\$2 \033[0m"
        ;;
        # 绿色
        "green")
            echo -e "\033[32m\${printN}\$2 \033[0m"
        ;;
        # 白色
        "white")
            echo -e "\033[37m\${printN}\$2 \033[0m"
        ;;
        "magenta")
            echo -e "\033[31m\${printN}\$2 \033[0m"
        ;;
        "skyBlue")
            echo -e "\033[36m\${printN}\$2 \033[0m"
        ;;
        # 黄色
        "yellow")
            echo -e "\033[33m\${printN}\$2 \033[0m"
        ;;
    esac
}
echoContent skyBlue "\n进度  1/1 : 更新证书"
if [[ -d "/etc/v2ray-agent" ]] && [[ -d "/etc/v2ray-agent/v2ray" ]] && [[ -d "/etc/v2ray-agent/tls" ]] && [[ -d "/etc/v2ray-agent" ]] && [[ -d "/etc/v2ray-agent/v2ray" ]] && [[ -f "/etc/v2ray-agent/v2ray/config_full.json" ]] && [[ -d "/root/.acme.sh" ]]
then
    tcp=\`cat /etc/v2ray-agent/v2ray/config_full.json|jq .inbounds[0]\`
    host=\`echo \${tcp}|jq .streamSettings.xtlsSettings.certificates[0].certificateFile|awk -F '[t][l][s][/]' '{print \$2}'|awk -F '["]' '{print \$1}'|awk -F '[.][c][r][t]' '{print \$1}'\`
    if [[ -d "/root/.acme.sh/\${host}_ecc" ]] && [[ -f "/root/.acme.sh/\${host}_ecc/\${host}.key" ]] && [[ -f "/root/.acme.sh/\${host}_ecc/\${host}.cer" ]]
    then
        modifyTime=\`stat /root/.acme.sh/\${host}_ecc/\${host}.key|sed -n '6,6p'|awk '{print \$2" "\$3" "\$4" "\$5}'\`

        modifyTime=\`date +%s -d "\${modifyTime}"\`
        currentTime=\`date +%s\`
#        currentTime=\`date +%s -d "2021-09-04 02:15:56.438105732 +0000"\`
#        currentTIme=1609459200
        stampDiff=\`expr \${currentTime} - \${modifyTime}\`
        days=\`expr \${stampDiff} / 86400\`
        remainingDays=\`expr 90 - \${days}\`
        tlsStatus=\${remainingDays}
        if [[ \${remainingDays} -le 0 ]]
        then
            tlsStatus="已过期"
        fi
        echoContent skyBlue " ---> 证书生成日期:"\`date -d @\${modifyTime} +"%F %H:%M:%S"\`
        echoContent skyBlue " ---> 证书生成天数:"\${days}
        echoContent skyBlue " ---> 证书剩余天数:"\${tlsStatus}
        if [[ \${remainingDays} -le 1 ]]
        then
            echoContent yellow " ---> 重新生成证书"
            if [[ \`ps -ef|grep -v grep|grep nginx\` ]]
            then
                nginx -s stop
            fi
            sudo ~/.acme.sh/acme.sh --installcert -d \${host} --fullchainpath /etc/v2ray-agent/tls/\${host}.crt --keypath /etc/v2ray-agent/tls/\${host}.key --ecc >> /etc/v2ray-agent/tls/acme.log
            nginx
            if [[ \`ps -ef|grep -v grep|grep nginx\` ]]
            then
                echoContent green " ---> nginx启动成功"
            else
                echoContent red " ---> nginx启动失败，请检查[/etc/v2ray-agent/tls/acme.log]"
            fi
        else
            echoContent green " ---> 证书有效"
        fi
    else
        echoContent red " ---> 无法找到相应路径，请使用脚本重新安装"
    fi
else
    echoContent red " ---> 无法找到相应路径，请使用脚本重新安装"
fi
EOF
    if [[ ! -z `crontab -l|grep -v grep|grep 'reloadInstallTLS'` ]]
    then
        echoContent green " ---> 添加定时维护证书成功"
    else
        crontab -l >> /etc/v2ray-agent/backup_crontab.cron

        # 定时任务
        crontab /etc/v2ray-agent/backup_crontab.cron
        echoContent green " ---> 添加定时维护证书成功"
    fi
}

# 更新证书
renewalTLS(){
    echoContent skyBlue "\n进度  1/1 : 更新证书"
    if [[ -d "/root/.acme.sh" ]]
    then
        if [[ -d "/root/.acme.sh/${currentHost}_ecc" ]] && [[ -f "/root/.acme.sh/${currentHost}_ecc/${currentHost}.key" ]] && [[ -f "/root/.acme.sh/${currentHost}_ecc/${currentHost}.cer" ]]
        then
            modifyTime=`stat /root/.acme.sh/${currentHost}_ecc/${currentHost}.key|sed -n '6,6p'|awk '{print $2" "$3" "$4" "$5}'`

            modifyTime=`date +%s -d "${modifyTime}"`
            currentTime=`date +%s`
            stampDiff=`expr ${currentTime} - ${modifyTime}`
            days=`expr ${stampDiff} / 86400`
            remainingDays=`expr 90 - ${days}`
            tlsStatus=${remainingDays}
            if [[ ${remainingDays} -le 0 ]]
            then
                tlsStatus="已过期"
            fi
            echoContent skyBlue " ---> 证书生成日期:"`date -d @${modifyTime} +"%F %H:%M:%S"`
            echoContent skyBlue " ---> 证书生成天数:"${days}
            echoContent skyBlue " ---> 证书剩余天数:"${tlsStatus}
            if [[ ${remainingDays} -le 1 ]]
            then
                echoContent yellow " ---> 重新生成证书"
                handleNginx stop
                sudo ~/.acme.sh/acme.sh --installcert -d ${currentHost} --fullchainpath /etc/v2ray-agent/tls/${currentHost}.crt --keypath /etc/v2ray-agent/tls/${currentHost}.key --ecc >> /etc/v2ray-agent/tls/acme.log
                handleNginx start
            else
                echoContent green " ---> 证书有效"
            fi
        else
            echoContent red " ---> 未安装"
        fi
    else
        echoContent red " ---> 未安装"
    fi
}
# 查看TLS证书的状态
checkTLStatus(){
    if [[ ! -z "${currentHost}" ]]
    then
        if [[ -d "/root/.acme.sh/${currentHost}_ecc" ]] && [[ -f "/root/.acme.sh/${currentHost}_ecc/${currentHost}.key" ]] && [[ -f "/root/.acme.sh/${currentHost}_ecc/${currentHost}.cer" ]]
        then
            modifyTime=`stat /root/.acme.sh/${currentHost}_ecc/${currentHost}.key|sed -n '6,6p'|awk '{print $2" "$3" "$4" "$5}'`

            modifyTime=`date +%s -d "${modifyTime}"`
            currentTime=`date +%s`
            stampDiff=`expr ${currentTime} - ${modifyTime}`
            days=`expr ${stampDiff} / 86400`
            remainingDays=`expr 90 - ${days}`
            tlsStatus=${remainingDays}
            if [[ ${remainingDays} -le 0 ]]
            then
                tlsStatus="已过期"
            fi
            echoContent skyBlue " ---> 证书生成日期:"`date -d @${modifyTime} +"%F %H:%M:%S"`
            echoContent skyBlue " ---> 证书生成天数:"${days}
            echoContent skyBlue " ---> 证书剩余天数:"${tlsStatus}
        fi
    fi
}

# 安装V2Ray、指定版本
installV2Ray(){
    readInstallType
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装V2Ray"
    # 首先要卸载掉其余途径安装的V2Ray
    if [[ ! -z `ps -ef|grep -v grep|grep v2ray` ]] && [[ -z `ps -ef|grep -v grep|grep v2ray|grep v2ray-agent` ]]
    then
        # ps -ef|grep -v grep|grep v2ray|awk '{print $8}'|xargs rm -f
        ps -ef|grep -v grep|grep v2ray|awk '{print $2}'|xargs kill -9 > /dev/null 2>&1
    fi

    if [[ "${coreInstallType}" != "2" && "${coreInstallType}" != "3" ]]
    then
        # if [[ "${selectCoreType}" = "2" ]]
        # then
            # version=$(curl -s https://api.github.com/repos/v2fly/v2ray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | grep -v 'v5' | head -1)
        # else
            version=v4.45.2
            # version=${v2rayCoreVersion}
        # fi

        echoContent green " ---> $LINENO, v2ray-core版本:${version}"
        if [[ ! -z `wget --help|grep show-progress` ]]
        then
            wget -c -q --show-progress -P /etc/v2ray-agent/v2ray/ "https://github.com/v2fly/v2ray-core/releases/download/${version}/${v2rayCoreCPUVendor}.zip"
        else
            wget -c -P /etc/v2ray-agent/v2ray/ "https://github.com/v2fly/v2ray-core/releases/download/${version}/${v2rayCoreCPUVendor}.zip" > /dev/null 2>&1
        fi

        unzip -o "/etc/v2ray-agent/v2ray/${v2rayCoreCPUVendor}.zip" -d /etc/v2ray-agent/v2ray > /dev/null
        # rm -rf "/etc/v2ray-agent/v2ray/${v2rayCoreCPUVendor}.zip"
    else
        if [[ "${selectCoreType}" = "3" ]]
        then
            echoContent green " ---> 锁定v2ray-core版本为v4.32.1"
            rm -f /etc/v2ray-agent/v2ray/v2ray
            rm -f /etc/v2ray-agent/v2ray/v2ctl
            installV2Ray $1
        else
            echoContent green " ---> v2ray-core版本:`/etc/v2ray-agent/v2ray/v2ray --version|awk '{print $2}'|head -1`"
            read -p "是否更新、升级？[y/N]:" reInstallV2RayStatus
            if [[ "${reInstallV2RayStatus}" = "y" ]]
            then
                rm -f /etc/v2ray-agent/v2ray/v2ray
                rm -f /etc/v2ray-agent/v2ray/v2ctl
                installV2Ray $1
            fi
        fi
    fi
}

# 安装xray
installXray(){
    readInstallType
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装Xray"
    # 首先要卸载掉其余途径安装的Xray
    if [[ ! -z `ps -ef|grep -v grep|grep xray` ]] && [[ -z `ps -ef|grep -v grep|grep v2ray|grep v2ray-agent` ]]
    then
        # ps -ef|grep -v grep|grep xray|awk '{print $8}'|xargs rm -f
        ps -ef|grep -v grep|grep xray|awk '{print $2}'|xargs kill -9 > /dev/null 2>&1
    fi
    
    # 使用稳定版
    local prereleaseStatus=false

    if [[ "${coreInstallType}" != "1" ]]
    then
        version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease=='${prereleaseStatus}')|.tag_name' | head -1)
        
        # version=`curl -s https://github.com/XTLS/Xray-core/releases|grep /XTLS/Xray-core/releases/tag/|head -1|awk '{print $3}'|awk -F "[<]" '{print $1}'`

        echoContent green " ---> Xray-core版本:${version}"
        if [[ ! -z `wget --help|grep show-progress` ]]
        then
            wget -c -q --show-progress -P /etc/v2ray-agent/xray/ https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip > /dev/null 2>&1
        else
            wget -c -P /etc/v2ray-agent/xray/ https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip > /dev/null 2>&1
        fi

        unzip -o /etc/v2ray-agent/xray/${xrayCoreCPUVendor}.zip -d /etc/v2ray-agent/xray > /dev/null
        # rm -rf /etc/v2ray-agent/xray/${xrayCoreCPUVendor}.zip
        chmod 655 /etc/v2ray-agent/xray/xray
    else
        echoContent green " ---> Xray-core版本:`/etc/v2ray-agent/xray/xray --version|awk '{print $2}'|head -1`"
        read -p "是否更新、升级？[y/N]:" reInstallXrayStatus
        if [[ "${reInstallXrayStatus}" = "y" ]]
        then
            rm -f /etc/v2ray-agent/xray/xray
            installXray $1
        fi
    fi
}

# 安装Trojan-go
installTrojanGo(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装Trojan-Go"
    if [[ -z `ls -F /etc/v2ray-agent/trojan/|grep -w "trojan-go"` ]]
    then
        version=`curl -s https://github.com/p4gefau1t/trojan-go/releases|grep /trojan-go/releases/tag/|head -1|awk -F "[/]" '{print $6}'|awk -F "[>]" '{print $2}'|awk -F "[<]" '{print $1}'`
        echoContent green " ---> Trojan-Go版本:${version}"
        if [[ ! -z `wget --help|grep show-progress` ]]
        then
            wget -c -q --show-progress -P /etc/v2ray-agent/trojan/ https://github.com/p4gefau1t/trojan-go/releases/download/${version}/${trojanGoCoreCPUVendor}.zip
        else
            wget -c -P /etc/v2ray-agent/trojan/ https://github.com/p4gefau1t/trojan-go/releases/download/${version}/${trojanGoCoreCPUVendor}.zip > /dev/null 2>&1
        fi
        unzip -o /etc/v2ray-agent/trojan/${trojanGoCoreCPUVendor}.zip -d /etc/v2ray-agent/trojan > /dev/null
        # rm -rf /etc/v2ray-agent/trojan/${trojanGoCoreCPUVendor}.zip
    else
        echoContent green " ---> Trojan-Go版本:`/etc/v2ray-agent/trojan/trojan-go --version|awk '{print $2}'|head -1`"

        read -p "是否重新安装？[y/N]:" reInstallTrojanStatus
        if [[ "${reInstallTrojanStatus}" = "y" ]]
        then
            rm -rf /etc/v2ray-agent/trojan/trojan-go*
            installTrojanGo $1
        fi
    fi
}

# v2ray版本管理
v2rayVersionManageMenu(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : V2Ray版本管理"
    if [[ ! -d "/etc/v2ray-agent/v2ray/" ]]
    then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 0;
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级"
    echoContent yellow "2.回退"
    echoContent red "=============================================================="
    read -p "请选择：" selectV2RayType
    if [[ "${selectV2RayType}" = "1" ]]
    then
        updateV2Ray
    elif [[ "${selectV2RayType}" = "2" ]]
    then
        echoContent yellow "\n1.只可以回退最近的两个版本"
        echoContent yellow "2.不保证回退后一定可以正常使用"
        echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
        echoContent skyBlue "------------------------Version-------------------------------"
        curl -s https://github.com/v2fly/v2ray-core/releases|grep /v2ray-core/releases/tag/|head -3|awk -F "[/]" '{print $6}'|awk -F "[>]" '{print $2}'|awk -F "[<]" '{print $1}'|tail -n 2|awk '{print ""NR""":"$0}'
        echoContent skyBlue "--------------------------------------------------------------"
        read -p "请输入要回退的版本：" selectV2rayVersionType
        version=`curl -s https://github.com/v2fly/v2ray-core/releases|grep /v2ray-core/releases/tag/|head -3|awk -F "[/]" '{print $6}'|awk -F "[>]" '{print $2}'|awk -F "[<]" '{print $1}'|tail -n 2|awk '{print ""NR""":"$0}'|grep "${selectV2rayVersionType}:"|awk -F "[:]" '{print $2}'`
        if [[ ! -z "${version}" ]]
        then
            updateV2Ray ${version}
        else
            echoContent red "\n ---> 输入有误，请重新输入"
            v2rayVersionManageMenu 1
        fi
    fi

}

# xray版本管理
xrayVersionManageMenu(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : Xray版本管理"
    if [[ ! -d "/etc/v2ray-agent/xray/" ]]
    then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 0;
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级"
    echoContent yellow "2.回退"
    echoContent red "=============================================================="
    read -p "请选择：" selectXrayType
    if [[ "${selectXrayType}" = "1" ]]
    then
        updateXray
    elif [[ "${selectXrayType}" = "2" ]]
    then
        echoContent yellow "\n1.只可以回退最近的两个版本"
        echoContent yellow "2.不保证回退后一定可以正常使用"
        echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
        echoContent skyBlue "------------------------Version-------------------------------"
        curl -s https://github.com/XTLS/Xray-core/releases|grep /XTLS/Xray-core/releases/tag/|head -3|awk -F "[/]" '{print $6}'|awk -F "[>]" '{print $2}'|awk -F "[<]" '{print $1}'|tail -n 2|awk '{print ""NR""":"$0}'
        echoContent skyBlue "--------------------------------------------------------------"
        read -p "请输入要回退的版本：" selectXrayVersionType
        version=`curl -s https://github.com/XTLS/Xray-core/releases|grep /XTLS/Xray-core/releases/tag/|head -3|awk -F "[/]" '{print $6}'|awk -F "[>]" '{print $2}'|awk -F "[<]" '{print $1}'|tail -n 2|awk '{print ""NR""":"$0}'|grep "${selectXrayVersionType}:"|awk -F "[:]" '{print $2}'`
        if [[ ! -z "${version}" ]]
        then
            updateXray ${version}
        else
            echoContent red "\n ---> 输入有误，请重新输入"
            xrayVersionManageMenu 1
        fi
    fi

}
# 更新V2Ray
updateV2Ray(){
    readInstallType
    if [[ -z "${coreInstallType}" ]]
    then

        if [[ ! -z "$1" ]]
        then
            version=$1
        else
            version=`curl -s https://github.com/v2fly/v2ray-core/releases|grep /v2ray-core/releases/tag/|head -1|awk -F "[/]" '{print $6}'|awk -F "[>]" '{print $2}'|awk -F "[<]" '{print $1}'`
        fi
        # 使用锁定的版本
        if [[ ! -z "${v2rayCoreVersion}" ]]
        then
            version=${v2rayCoreVersion}
        fi
        echoContent green " ---> v2ray-core版本:${version}"

        if [[ ! -z `wget --help|grep show-progress` ]]
        then
            wget -c -q --show-progress -P /etc/v2ray-agent/v2ray/ https://github.com/v2fly/v2ray-core/releases/download/${version}/${v2rayCoreCPUVendor}.zip
        else
            wget -c -P /etc/v2ray-agent/v2ray/ https://github.com/v2fly/v2ray-core/releases/download/${version}/${v2rayCoreCPUVendor}.zip > /dev/null 2>&1
        fi

        unzip -o  /etc/v2ray-agent/v2ray/${v2rayCoreCPUVendor}.zip -d /etc/v2ray-agent/v2ray > /dev/null
        # rm -rf /etc/v2ray-agent/v2ray/${v2rayCoreCPUVendor}.zip
        handleV2Ray stop
        handleV2Ray start
    else
        echoContent green " ---> 当前v2ray-core版本:`/etc/v2ray-agent/v2ray/v2ray --version|awk '{print $2}'|head -1`"

        if [[ ! -z "$1" ]]
        then
            version=$1
        else
            version=`curl -s https://github.com/v2fly/v2ray-core/releases|grep /v2ray-core/releases/tag/|head -1|awk -F "[/]" '{print $6}'|awk -F "[>]" '{print $2}'|awk -F "[<]" '{print $1}'`
        fi

        if [[ ! -z "${v2rayCoreVersion}" ]]
        then
            version=${v2rayCoreVersion}
        fi
        if [[ ! -z "$1" ]]
        then
            read -p "回退版本为${version}，是否继续？[y/n]:" rollbackV2RayStatus
            if [[ "${rollbackV2RayStatus}" = "y" ]]
            then
                if [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3"  ]]
                then
                    echoContent green " ---> 当前v2ray-core版本:`/etc/v2ray-agent/v2ray/v2ray --version|awk '{print $2}'|head -1`"
                elif [[ "${coreInstallType}" = "1"  ]]
                then
                    echoContent green " ---> 当前Xray-core版本:`/etc/v2ray-agent/xray/xray --version|awk '{print $2}'|head -1`"
                fi

                handleV2Ray stop
                rm -f /etc/v2ray-agent/v2ray/v2ray
                rm -f /etc/v2ray-agent/v2ray/v2ctl
                updateV2Ray ${version}
            else
                echoContent green " ---> 放弃回退版本"
            fi
        elif [[ "${version}" = "v`/etc/v2ray-agent/v2ray/v2ray --version|awk '{print $2}'|head -1`" ]]
        then
            read -p "当前版本与最新版相同，是否重新安装？[y/N]:" reInstallV2RayStatus
            if [[ "${reInstallV2RayStatus}" = "y" ]]
            then
                handleV2Ray stop
                rm -f /etc/v2ray-agent/v2ray/v2ray
                rm -f /etc/v2ray-agent/v2ray/v2ctl
                updateV2Ray
            else
                echoContent green " ---> 放弃重新安装"
            fi
        else
            read -p "最新版本为：${version}，是否更新？[y/N]：" installV2RayStatus
            if [[ "${installV2RayStatus}" = "y" ]]
            then
                rm -f /etc/v2ray-agent/v2ray/v2ray
                rm -f /etc/v2ray-agent/v2ray/v2ctl
                updateV2Ray
            else
                echoContent green " ---> 放弃更新"
            fi

        fi
    fi
}

# 更新Xray
updateXray(){
    readInstallType
    if [[ -z "${coreInstallType}" ]]
    then
        if [[ ! -z "$1" ]]
        then
            version=$1
        else
            # version=`curl -s https://github.com/XTLS/Xray-core/releases|grep /XTLS/Xray-core/releases/tag/|head -1|awk '{print $3}'|awk -F "[<]" '{print $1}'`
            version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -1)
        fi

        echoContent green " ---> Xray-core版本:${version}"

        if [[ ! -z `wget --help|grep show-progress` ]]
        then
            wget -c -q --show-progress -P /etc/v2ray-agent/xray/ https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip
        else
            wget -c -P /etc/v2ray-agent/xray/ https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip > /dev/null 2>&1
        fi

        unzip -o /etc/v2ray-agent/xray/${xrayCoreCPUVendor}.zip -d /etc/v2ray-agent/xray > /dev/null
        # rm -rf /etc/v2ray-agent/xray/${xrayCoreCPUVendor}.zip
        chmod 655 /etc/v2ray-agent/xray/xray
        handleXray stop
        handleXray start
    else
        echoContent green " ---> 当前Xray-core版本:`/etc/v2ray-agent/xray/xray --version|awk '{print $2}'|head -1`"

        if [[ ! -z "$1" ]]
        then
            version=$1
        else
            version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -1)
        fi

        if [[ ! -z "$1" ]]
        then
            read -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
            if [[ "${rollbackXrayStatus}" = "y" ]]
            then
                echoContent green " ---> 当前Xray-core版本:`/etc/v2ray-agent/v2ray/v2ray --version|awk '{print $2}'|head -1`"

                handleV2Ray stop
                rm -f /etc/v2ray-agent/v2ray/v2ray
                rm -f /etc/v2ray-agent/v2ray/v2ctl
                updateV2Ray ${version}
            else
                echoContent green " ---> 放弃回退版本"
            fi
        elif [[ "${version}" = "v`/etc/v2ray-agent/xray/xray --version|awk '{print $2}'|head -1`" ]]
        then
            read -p "当前版本与最新版相同，是否重新安装？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" = "y" ]]
            then
                handleXray stop
                rm -f /etc/v2ray-agent/xray/xray
                rm -f /etc/v2ray-agent/xray/xray
                updateXray
            else
                echoContent green " ---> 放弃重新安装"
            fi
        else
            read -p "最新版本为：${version}，是否更新？[y/N]：" installXrayStatus
            if [[ "${installXrayStatus}" = "y" ]]
            then
                rm -f /etc/v2ray-agent/xray/xray
                rm -f /etc/v2ray-agent/xray/xray
                updateXray
            else
                echoContent green " ---> 放弃更新"
            fi

        fi
    fi
}
# 更新Trojan-Go
updateTrojanGo(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 更新Trojan-Go"
    if [[ ! -d "/etc/v2ray-agent/trojan/" ]]
    then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 0;
    fi
    if [[ -z `ls -F /etc/v2ray-agent/trojan/|grep "trojan-go"` ]]
    then
        version=`curl -s https://github.com/p4gefau1t/trojan-go/releases|grep /trojan-go/releases/tag/|head -1|awk -F "[/]" '{print $6}'|awk -F "[>]" '{print $2}'|awk -F "[<]" '{print $1}'`
        echoContent green " ---> Trojan-Go版本:${version}"
        if [[ ! -z `wget --help|grep show-progress` ]]
        then
            wget -c -q --show-progress -P /etc/v2ray-agent/trojan/ https://github.com/p4gefau1t/trojan-go/releases/download/${version}/${trojanGoCoreCPUVendor}.zip
        else
            wget -c -P /etc/v2ray-agent/trojan/ https://github.com/p4gefau1t/trojan-go/releases/download/${version}/${trojanGoCoreCPUVendor}.zip > /dev/null 2>&1
        fi
        unzip -o /etc/v2ray-agent/trojan/${trojanGoCoreCPUVendor}.zip -d /etc/v2ray-agent/trojan > /dev/null
        # rm -rf /etc/v2ray-agent/trojan/${trojanGoCoreCPUVendor}.zip
        handleTrojanGo stop
        handleTrojanGo start
    else
        echoContent green " ---> 当前Trojan-Go版本:`/etc/v2ray-agent/trojan/trojan-go --version|awk '{print $2}'|head -1`"
        if [[ ! -z `/etc/v2ray-agent/trojan/trojan-go --version` ]]
        then
            version=`curl -s https://github.com/p4gefau1t/trojan-go/releases|grep /trojan-go/releases/tag/|head -1|awk -F "[/]" '{print $6}'|awk -F "[>]" '{print $2}'|awk -F "[<]" '{print $1}'`
            if [[ "${version}" = "`/etc/v2ray-agent/trojan/trojan-go --version|awk '{print $2}'|head -1`" ]]
            then
                read -p "当前版本与最新版相同，是否重新安装？[y/N]:" reInstalTrojanGoStatus
                if [[ "${reInstalTrojanGoStatus}" = "y" ]]
                then
                    handleTrojanGo stop
                    rm -rf /etc/v2ray-agent/trojan/trojan-go
                    updateTrojanGo 1
                else
                    echoContent green " ---> 放弃重新安装"
                fi
            else
                read -p "最新版本为：${version}，是否更新？[y/n]：" installTrojanGoStatus
                if [[ "${installTrojanGoStatus}" = "y" ]]
                then
                    rm -rf /etc/v2ray-agent/trojan/trojan-go
                    updateTrojanGo 1
                else
                    echoContent green " ---> 放弃更新"
                fi
            fi
        fi
    fi
}

# 更新 sing box
updateSb() {
    curr_sb_ver=`/etc/v2ray-agent/sing-box/sing-box version | grep version | awk '{print $3}'`
    echoContent green " ---> 当前 sing-box版本: ${curr_sb_ver}"
    new_sb_ver=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -1 | cut -c 2-)

    if [[ "${curr_sb_ver}" ==  "${new_sb_ver}" ]]; then
        echoContent yellow " ---> sing-box 已经 ${new_sb_ver} 最新版，无需升级。"
    else 
        echoContent green " ---> 最新版 sing-box版本: ${new_sb_ver}"

        if [[ ! -z `wget --help|grep show-progress` ]]
        then
            wget -c -q --show-progress -P /etc/v2ray-agent/sing-box/ https://github.com/SagerNet/sing-box/releases/download/v${new_sb_ver}/sing-box-${new_sb_ver}-linux-${sbCoreCPUVendor}64.tar.gz
        else
            wget -c -P /etc/v2ray-agent/sing-box/ https://github.com/SagerNet/sing-box/releases/download/v${new_sb_ver}/sing-box-${new_sb_ver}-linux-${sbCoreCPUVendor}64.tar.gz > /dev/null 2>&1
        fi
        tar -xf /etc/v2ray-agent/sing-box/sing-box-${new_sb_ver}-linux-${sbCoreCPUVendor}64.tar.gz -C /etc/v2ray-agent/sing-box > /dev/null
        cp -ab /etc/v2ray-agent/sing-box/sing-box /etc/v2ray-agent/sing-box/sing-box.bak
        mv /etc/v2ray-agent/sing-box/sing-box-${new_sb_ver}-linux-${sbCoreCPUVendor}64/sing-box /etc/v2ray-agent/sing-box
        rm -rf /etc/v2ray-agent/sing-box/sing-box-${new_sb_ver}-linux-${sbCoreCPUVendor}64
        chmod 655 /etc/v2ray-agent/sing-box/sing-box
        systemctl restart sing-box && echoContent green " ---> sing-box restart / 重启 successfully."
    fi
}

# 验证整个服务是否可用
checkGFWStatue(){
    echoContent skyBlue "\n进度 $1/${totalProgress} : 验证服务启动状态"
    if [[ ! -z `ps -ef|grep -v grep|grep v2ray` ]]
    then
        echoContent green " ---> 服务启动成功"
    else
        echoContent red " ---> 服务启动失败，请检查终端是否有日志打印"
        exit 0
    fi
}

# V2Ray开机自启
installV2RayService(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置V2Ray开机自启"
    if [[ ! -z `find /bin /usr/bin -name "systemctl"` ]]
    then
        rm -rf /etc/systemd/system/v2ray.service
        touch /etc/systemd/system/v2ray.service
        execStart='/etc/v2ray-agent/v2ray/v2ray -config /etc/v2ray-agent/v2ray/config_full.json'
        if [[ ! -z ${selectCustomInstallType} ]]
        then
            execStart='/etc/v2ray-agent/v2ray/v2ray -confdir /etc/v2ray-agent/v2ray/conf'
        fi
    cat << EOF > /etc/systemd/system/v2ray.service
[Unit]
Description=V2Ray - A unified platform for anti-censorship
Documentation=https://v2ray.com https://guide.v2fly.org
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=yes
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23


[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable v2ray.service
        echoContent green " ---> 配置V2Ray开机自启成功"
    fi
}

# Xray开机自启
installXrayService(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Xray开机自启"
    if [[ ! -z `find /bin /usr/bin -name "systemctl"` ]]
    then
        rm -rf /etc/systemd/system/xray.service
        touch /etc/systemd/system/xray.service
        execStart='/etc/v2ray-agent/xray/xray run -config /etc/v2ray-agent/xray/config_full.json'
        if [[ ! -z ${selectCustomInstallType} ]]
        then
            execStart='/etc/v2ray-agent/xray/xray run -confdir /etc/v2ray-agent/xray/conf'
        fi
    cat << EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray - A unified platform for anti-censorship
# Documentation=https://v2ray.com https://guide.v2fly.org
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=yes
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23


[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable xray.service
        echoContent green " ---> 配置Xray开机自启成功"
    fi
}
# Trojan开机自启
installTrojanService(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Trojan开机自启"
    if [[ ! -z `find /bin /usr/bin -name "systemctl"` ]]
    then
        rm -rf /etc/systemd/system/trojan-go.service
        touch /etc/systemd/system/trojan-go.service

    cat << EOF > /etc/systemd/system/trojan-go.service
[Unit]
Description=Trojan-Go - A unified platform for anti-censorship
Documentation=Trojan-Go
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=yes
ExecStart=/etc/v2ray-agent/trojan/trojan-go -config /etc/v2ray-agent/trojan/config_full.json
Restart=on-failure
RestartPreventExitStatus=23


[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable trojan-go.service
        echoContent green " ---> 配置Trojan开机自启成功"
    fi
}
# 操作V2Ray
handleV2Ray(){
    
    # 修复v2ray启动失败
    local v2ray_access_log=/etc/v2ray-agent/v2ray/v2ray_access.log
    local v2ray_error_log=/etc/v2ray-agent/v2ray/v2ray_error.log
    

    if [[ ! -z `find /bin /usr/bin -name "systemctl"` ]] && [[ ! -z `ls /etc/systemd/system/|grep -v grep|grep v2ray.service` ]]; then
        if [[ -z `ps -ef|grep -v grep|grep "v2ray/v2ray"` ]] && [[ "$1" = "start" ]]; then
            
            if [[ -f $v2ray_access_log ]]; then
            
                while true
                do
                    echoContent yellow "\n --> 正在取消 $v2ray_access_log 只读属性"
                    sudo chattr -i $v2ray_access_log
                    sudo chattr -i $v2ray_error_log
                    
                    sleep 0.5
                    
                    if lsattr $v2ray_access_log | grep '\-i'; then
                        sleep 1
                        continue
                    else
                        echoContent yellow "\n --> 已取消 $v2ray_access_log 只读属性"
                        echo >$v2ray_access_log
                        echo >$v2ray_error_log
                        break
                    fi
                done                
            fi
            
            systemctl start v2ray.service
            
        elif [[ ! -z `ps -ef|grep -v grep|grep "v2ray/v2ray"` ]] && [[ "$1" = "stop" ]]; then
            systemctl stop v2ray.service
        fi
    elif [[ -z `find /bin /usr/bin -name "systemctl"` ]]; then
        if [[ -z `ps -ef|grep -v grep|grep v2ray` ]] && [[ "$1" = "start" ]]; then
            /usr/bin/v2ray/v2ray -config /etc/v2ray-agent/v2ray/config_full.json & > /dev/null 2>&1
        elif [[ ! -z `ps -ef|grep -v grep|grep v2ray` ]] && [[ "$1" = "stop" ]]; then
            ps -ef|grep -v grep|grep v2ray|awk '{print $2}'|xargs kill -9
        fi
    fi
    
    sleep 0.5
    if [[ "$1" = "start" ]]; then
        if [[ ! -z `ps -ef|grep -v grep|grep "v2ray/v2ray"` ]]; then
            echoContent green " ---> V2Ray启动成功"
            echoContent yellow "\n --> 已恢复 $v2ray_access_log 只读属性"
            sudo chattr +i $v2ray_access_log 
            sudo chattr +i $v2ray_error_log 
        else
            echoContent red "V2Ray启动失败"
            echoContent red "执行 [ps -ef|grep v2ray] 查看日志"
            # exit 0;
        fi
    elif [[ "$1" = "stop" ]]; then
        if [[ -z `ps -ef|grep -v grep|grep "v2ray/v2ray"` ]]; then
            echoContent green " ---> V2Ray关闭成功"
        else
            echoContent red "V2Ray关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep v2ray|awk '{print \$2}'|xargs kill -9】"
            # exit 0;
        fi
    fi
}
# 操作xray
handleXray(){

    # 修复xray启动失败
    local xray_access_log=/etc/v2ray-agent/xray/xray_access.log
    local xray_error_log=/etc/v2ray-agent/xray/xray_error.log
    
    if [[ ! -z `find /bin /usr/bin -name "systemctl"` ]] && [[ ! -z `ls /etc/systemd/system/|grep -v grep|grep xray.service` ]]; then
        if [[ -z `ps -ef|grep -v grep|grep "xray/xray"` ]] && [[ "$1" = "start" ]]; then
            
            if [[ -f $xray_access_log ]]; then
            
                while true
                do
                    echoContent yellow "\n --> 正在取消 $v2ray_access_log 只读属性"
                    sudo chattr -i $xray_access_log
                    sudo chattr -i $xray_error_log
                    
                    sleep 0.5
                    
                    if lsattr $xray_access_log | grep '\-i'; then
                        sleep 1
                        continue
                    else
                        echoContent yellow "\n --> 已取消 $xray_access_log 只读属性"
                        echo >$xray_access_log
                        echo >$xray_error_log
                        break
                    fi
                done                
            fi
        
            systemctl start xray.service
        elif [[ ! -z `ps -ef|grep -v grep|grep "xray/xray"` ]] && [[ "$1" = "stop" ]]; then
            systemctl stop xray.service
        fi
    elif [[ -z `find /bin /usr/bin -name "systemctl"` ]]; then
        if [[ -z `ps -ef|grep -v grep|grep xray` ]] && [[ "$1" = "start" ]]; then
            /usr/bin/xray/xray -config /etc/v2ray-agent/xray/config_full.json & > /dev/null 2>&1
        elif [[ ! -z `ps -ef|grep -v grep|grep xray` ]] && [[ "$1" = "stop" ]]; then
            ps -ef|grep -v grep|grep xray|awk '{print $2}'|xargs kill -9
        fi
    fi
    
    sleep 0.5
    if [[ "$1" = "start" ]]; then
        if [[ ! -z `ps -ef|grep -v grep|grep "xray/xray"` ]]
        then
            echoContent green " ---> Xray启动成功"
            echoContent yellow "\n --> 已恢复 $xray_access_log 只读属性"
            sudo chattr +i $xray_access_log 
            sudo chattr +i $xray_error_log 
        else
            echoContent red "xray启动失败"
            echoContent red "执行 [ps -ef|grep xray] 查看日志"
            # exit 0;
        fi
    elif [[ "$1" = "stop" ]]; then
        if [[ -z `ps -ef|grep -v grep|grep "xray/xray"` ]]
        then
            echoContent green " ---> Xray关闭成功"
        else
            echoContent red "xray关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9】"
            # exit 0;
        fi
    fi
}
# 操作Trojan-Go
handleTrojanGo(){
    if [[ ! -z `find /bin /usr/bin -name "systemctl"` ]] && [[ ! -z `ls /etc/systemd/system/|grep -v grep|grep trojan-go.service` ]]
    then
        if [[ -z `ps -ef|grep -v grep|grep trojan-go` ]] && [[ "$1" = "start" ]]
        then
            systemctl start trojan-go.service
        elif [[ ! -z `ps -ef|grep -v grep|grep trojan-go` ]] && [[ "$1" = "stop" ]]
        then
            systemctl stop trojan-go.service
        fi
    elif [[ -z `find /bin /usr/bin -name "systemctl"` ]]
    then
        if [[ -z `ps -ef|grep -v grep|grep trojan-go` ]] && [[ "$1" = "start" ]]
        then
            /etc/v2ray-agent/trojan/trojan-go -config /etc/v2ray-agent/trojan/config_full.json & > /dev/null 2>&1
        elif [[ ! -z `ps -ef|grep -v grep|grep trojan-go` ]] && [[ "$1" = "stop" ]]
        then
            ps -ef|grep -v grep|grep trojan-go|awk '{print $2}'|xargs kill -9
        fi
    fi
    sleep 0.5
    if [[ "$1" = "start" ]]
    then
        if [[ ! -z `ps -ef|grep -v grep|grep trojan-go` ]]
        then
            echoContent green " ---> Trojan-Go启动成功"
        else
            echoContent red "Trojan-Go启动失败"
            echoContent red "请手动执行【/etc/v2ray-agent/trojan/trojan-go -config /etc/v2ray-agent/trojan/config_full.json】,查看错误日志"
            # exit 0;
        fi
    elif [[ "$1" = "stop" ]]
    then
        if [[ -z `ps -ef|grep -v grep|grep trojan-go` ]]
        then
            echoContent green " ---> Trojan-Go关闭成功"
        else
            echoContent red "Trojan-Go关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep trojan-go|awk '{print \$2}'|xargs kill -9】"
            # exit 0;
        fi
    fi
}
# 初始化V2Ray 配置文件
initV2RayConfig(){
    echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化V2Ray配置"
    if [[ ! -z "${currentUUID}" ]]; then
        echo
        read -p "读取到上次安装记录，是否使用上次安装时的UUID ${currentUUID} ？[y/N]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" = "y" ]]
        then
            uuid=${currentUUID}
            uuidDirect=${currentUUIDDirect}
        fi
    fi
    # else
    if [[ -z "${uuid}" ]]; then
        uuid=`/etc/v2ray-agent/v2ray/v2ctl uuid`
        read -r -p "输入 uuid（默认 / default ${uuid}）:" uuid_
        uuid_=$(echo "$uuid_" | xargs)
        if [[ -n "${uuid_}" ]]; then
            uuid=$uuid_
        fi
        uuidDirect=`/etc/v2ray-agent/v2ray/v2ctl uuid`
    fi
    # fi
    if [[ -z "${uuid}" ]]
    then
        echoContent red "\n ---> uuid读取错误，重新生成"
        uuid=`/etc/v2ray-agent/v2ray/v2ctl uuid`
    fi

    if [[ -z "${uuidDirect}" ]] && [[ "${selectCoreType}" = "3" ]]
    then
        echoContent red "\n ---> uuid XTLS-direct读取错误，重新生成"
        uuidDirect=`/etc/v2ray-agent/v2ray/v2ctl uuid`
    fi

    if [[ "${uuid}" = "${uuidDirect}" ]]
    then
        echoContent red "\n ---> uuid重复，重新生成"
        uuid=`/etc/v2ray-agent/v2ray/v2ctl uuid`
        uuidDirect=`/etc/v2ray-agent/v2ray/v2ctl uuid`
    fi
    echoContent green "\n ---> 使用成功"

    rm -rf /etc/v2ray-agent/v2ray/conf
    rm -rf /etc/v2ray-agent/v2ray/config_full.json
    if [[ "$1" = "all" ]] && [[ "${selectCoreType}" = "2" ]]
    then
        # default v2ray-core
        read -r -p "v2ray 监听端口 / port（默认 / default 443，提示：回源规则 / Origin Rules ）:" port
        port=$(echo "$port" | xargs)
        if [[ -z "${port}" ]]; then
            port=443
        fi
        cat << EOF > /etc/v2ray-agent/v2ray/config_full.json
{
  "log": {
    "access": "/dev/null",
    "error": "/dev/null",
    "loglevel": "none"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "vless",
      "tag": "VLESSTCP",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "add": "${add}",
            "email": "${domain}_VLESS_TLS_TCP"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 31296,
            "xver": 0
          },
          {
            "path": "/${customPath}",
            "dest": 31299,
            "xver": 1
          },
          {
            "path": "/${customPath}tcp",
            "dest": 31298,
            "xver": 1
          },
          {
            "path": "/${customPath}ws",
            "dest": 31297,
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "alpn": [
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/v2ray-agent/tls/${domain}.crt",
              "keyFile": "/etc/v2ray-agent/tls/${domain}.key"
            }
          ]
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 31299,
      "protocol": "vmess",
      "tag": "VMessWS",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "email": "${domain}_vmess_ws",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 31298,
      "protocol": "vmess",
      "tag": "VMessTCP",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "level": 0,
            "alterId": 0,
            "email": "${domain}_vmess_tcp"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "acceptProxyProtocol": true,
          "header": {
            "type": "http",
            "request": {
              "path": [
                "/${customPath}tcp"
              ]
            }
          }
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 31297,
      "protocol": "vless",
      "tag": "VLESSWS",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "email": "${domain}_vless_ws"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}ws"
        }
      }
    }
  ],
  "routing":{
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "blocked"
      }
    ]
  },
  "outbounds": [
    {
      "tag":"direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "dns": {
    "servers": [
      "74.82.42.42",
      "8.8.8.8",
      "8.8.4.4",
      "1.1.1.1",
      "localhost"
    ]
  }
}
EOF
    elif [[ "$1" = "all" ]] && [[ "${selectCoreType}" = "3" ]]
    then
        # 需锁定4.32.1
        cat << EOF > /etc/v2ray-agent/v2ray/config_full.json
{
  "log": {
    "access": "/etc/v2ray-agent/v2ray/v2ray_access.log",
    "error": "/etc/v2ray-agent/v2ray/v2ray_error.log",
    "loglevel": "debug"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "add": "${add}",
            "flow":"xtls-rprx-origin",
            "email": "${domain}_VLESS_XTLS/TLS-origin_TCP"
          },
          {
            "id": "${uuidDirect}",
            "flow":"xtls-rprx-direct",
            "email": "${domain}_VLESS_XTLS/TLS-direct_TCP"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 31296,
            "xver": 0
          },
          {
            "path": "/${customPath}",
            "dest": 31299,
            "xver": 1
          },
          {
            "path": "/${customPath}tcp",
            "dest": 31298,
            "xver": 1
          },
          {
            "path": "/${customPath}ws",
            "dest": 31297,
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
          "alpn": [
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/v2ray-agent/tls/${domain}.crt",
              "keyFile": "/etc/v2ray-agent/tls/${domain}.key"
            }
          ]
        }
      }
    },
    {
      "port": 31299,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 0,
            "level": 0,
            "email": "${domain}_vmess_ws"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}"
        }
      }
    },
    {
      "port": 31298,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "level": 0,
            "alterId": 0,
            "email": "${domain}_vmess_tcp"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "acceptProxyProtocol": true,
          "header": {
            "type": "http",
            "request": {
              "path": [
                "/${customPath}tcp"
              ]
            }
          }
        }
      }
    },
    {
      "port": 31297,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "level": 0,
            "email": "${domain}_vless_ws"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}ws"
        }
      }
    }
  ],
  "routing":{
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "blocked"
      }
    ]
  },
  "outbounds": [
    {
      "tag":"direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "dns": {
    "servers": [
      "74.82.42.42",
      "8.8.8.8",
      "8.8.4.4",
      "1.1.1.1",
      "localhost"
    ]
  }
}
EOF
    elif [[ "$1" = "custom" ]]
    then
        # custom v2ray-core
        cat << EOF > /etc/v2ray-agent/v2ray/conf/00_log.json
{
  "log": {
    "access": "/etc/v2ray-agent/v2ray/v2ray_access.log",
    "error": "/etc/v2ray-agent/v2ray/v2ray_error.log",
    "loglevel": "debug"
  }
}
EOF
        # outbounds
       cat << EOF > /etc/v2ray-agent/v2ray/conf/10_outbounds.json
{
    "outbounds": [
        {
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "UseIPv4"
          }
        },
        {
          "tag": "blocked",
          "protocol": "blackhole",
          "settings": {}
        }
    ]
}
EOF
       cat << EOF > /etc/v2ray-agent/v2ray/conf/09_routing.json
{
    "routing":{
        "domainStrategy": "AsIs",
        "rules": [
          {
            "type": "field",
            "protocol": [
              "bittorrent"
            ],
            "outboundTag": "blocked"
          }
        ]
  }
}
EOF
        # dns
       cat << EOF > /etc/v2ray-agent/v2ray/conf/11_dns.json
{
    "dns": {
        "servers": [
          "74.82.42.42",
          "8.8.8.8",
          "8.8.4.4",
          "1.1.1.1",
          "localhost"
        ]
  }
}
EOF
        # VLESS_TCP_TLS/XTLS
        # 没有path则回落到此端口
        local fallbacksList='{"dest":31296,"xver":0}'

        if [[ -z `echo ${selectCustomInstallType}|grep 4` ]]
        then
            fallbacksList='{"dest":80,"xver":0}'
        fi

        # VLESS_WS_TLS
        if [[ ! -z `echo ${selectCustomInstallType}|grep 1` ]]
        then
            fallbacksList=${fallbacksList}',{"path":"/'${customPath}'ws","dest":31297,"xver":1}'
            cat << EOF > /etc/v2ray-agent/v2ray/conf/03_VLESS_WS_inbounds.json
{
"inbounds":[
        {
      "port": 31297,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "level": 0,
            "email": "${domain}_vless_ws"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}ws"
        }
      }
    }
    ]
}
EOF
        fi
# VMess_TCP
        if [[ ! -z `echo ${selectCustomInstallType}|grep 2` ]]
        then
            fallbacksList=${fallbacksList}',{"path":"/'${customPath}'tcp","dest":31298,"xver":1}'
            cat << EOF > /etc/v2ray-agent/v2ray/conf/04_VMess_TCP_inbounds.json
{
"inbounds":[
    {
      "port": 31298,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "tag":"VMessTCP",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "level": 0,
            "alterId": 0,
            "email": "${domain}_vmess_tcp"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "acceptProxyProtocol": true,
          "header": {
            "type": "http",
            "request": {
              "path": [
                "/${customPath}tcp"
              ]
            }
          }
        }
      }
    }
]
}
EOF
        fi
        # VMess_WS
        if [[ ! -z `echo ${selectCustomInstallType}|grep 3` ]]
        then
            fallbacksList=${fallbacksList}',{"path":"/'${customPath}'","dest":31299,"xver":1}'
            cat << EOF > /etc/v2ray-agent/v2ray/conf/05_VMess_WS_inbounds.json
{
"inbounds":[
{
      "port": 31299,
      "protocol": "vmess",
      "tag":"VMessWS",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 0,
            "add": "${add}",
            "level": 0,
            "email": "${domain}_vmess_ws"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}"
        }
      }
    }
]
}
EOF
        fi
        # VLESS_TCP
        if [[ "${selectCoreType}" = "2" ]]
        then
            cat << EOF > /etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json
{
  "inbounds":[
    {
      "port": 443,
      "protocol": "vless",
      "tag":"VLESSTCP",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "add": "${add}",
            "email": "${domain}_VLESS_TLS_TCP"
          }
        ],
        "decryption": "none",
        "fallbacks": [
            ${fallbacksList}
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "alpn": [
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/v2ray-agent/tls/${domain}.crt",
              "keyFile": "/etc/v2ray-agent/tls/${domain}.key"
            }
          ]
        }
      }
    }
  ]
}
EOF
        elif [[ "${selectCoreType}" = "3" ]]
        then

        cat << EOF > /etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json
{
  "inbounds":[
    {
      "port": 443,
      "protocol": "vless",
      "tag":"VLESSTCP",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "add": "${add}",
            "flow":"xtls-rprx-origin",
            "email": "${domain}_VLESS_XTLS/TLS-origin_TCP"
          },
          {
            "id": "${uuidDirect}",
            "flow":"xtls-rprx-direct",
            "email": "${domain}_VLESS_XTLS/TLS-direct_TCP"
          }
        ],
        "decryption": "none",
        "fallbacks": [
            ${fallbacksList}
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
          "alpn": [
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/v2ray-agent/tls/${domain}.crt",
              "keyFile": "/etc/v2ray-agent/tls/${domain}.key"
            }
          ]
        }
      }
    }
  ]
}
EOF
        fi

    fi
}


# 初始化Xray 配置文件
initXrayConfig(){
    echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化Xray配置"
    if [[ ! -z "${currentUUID}" ]]
    then
        echo
        read -p "读取到上次安装记录，是否使用上次安装时的UUID ${currentUUID} ？[y/N]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" = "y" ]]
        then
            uuid=${currentUUID}
            uuidDirect=${currentUUIDDirect}
        fi
    fi

    if [[ -z "${uuid}" ]]; then
        uuid=`/etc/v2ray-agent/xray/xray uuid`
        read -r -p "输入 uuid（默认 / default ${uuid}）:" uuid_
        uuid_=$(echo "$uuid_" | xargs)
        if [[ -n "${uuid_}" ]]; then
            uuid=$uuid_
        fi
        uuidDirect=`/etc/v2ray-agent/xray/xray uuid`
    fi
    if [[ -z "${uuid}" ]]
    then
        echoContent red "\n ---> uuid读取错误，重新生成"
        uuid=`/etc/v2ray-agent/xray/xray uuid`
    fi

    if [[ -z "${uuidDirect}" ]] && [[ "${selectCoreType}" = "1" ]]
    then
        echoContent red "\n ---> uuid XTLS-direct读取错误，重新生成"
        uuidDirect=`/etc/v2ray-agent/xray/xray uuid`
    fi

    if [[ "${uuid}" = "${uuidDirect}" ]]
    then
        echoContent red "\n ---> uuid重复，重新生成"
        uuid=`/etc/v2ray-agent/xray/xray uuid`
        uuidDirect=`/etc/v2ray-agent/xray/xray uuid`
    fi
    echoContent green "\n ---> 使用成功"

    rm -rf /etc/v2ray-agent/xray/conf
    # rm -rf /etc/v2ray-agent/xray/config_full.json
    if [[ "$1" = "all" ]]
    then
        read -r -p "xray 监听端口 / port（默认 / default 443，提示：回源规则 / Origin Rules ）:" port
        port=$(echo "$port" | xargs)
        if [[ -z "${port}" ]]; then
            port=443
        fi
        
        # default v2ray-core
        cat << EOF > /etc/v2ray-agent/xray/config_full.json
{
  "log": {
    "error": "/dev/null",
    "loglevel": "none"
  },
  "inbounds": [
    {
      "port": ${port},
      "protocol": "vless",
      "tag": "VLESSTCP",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow":"xtls-rprx-vision",
            "email": "${domain}-VLESS_TCP/TLS_Vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 31296,
            "xver": 0
          },
          {
            "path": "/${customPath}",
            "dest": 31299,
            "xver": 1
          },
          {
            "path": "/${customPath}tcp",
            "dest": 31298,
            "xver": 1
          },
          {
            "path": "/${customPath}ws",
            "dest": 31297,
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "minVersion": "1.2",
          "alpn": [
            "http/1.1",
            "h2"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/v2ray-agent/tls/${domain}.crt",
              "keyFile": "/etc/v2ray-agent/tls/${domain}.key",
              "ocspStapling": 3600
            }
          ]
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 31299,
      "protocol": "vmess",
      "tag": "VMessWS",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "email": "${domain}_vmess_ws",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 31298,
      "protocol": "vmess",
      "tag": "VMessTCP",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "level": 0,
            "alterId": 0,
            "email": "${domain}_vmess_tcp"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "acceptProxyProtocol": true,
          "header": {
            "type": "http",
            "request": {
              "path": [
                "/${customPath}tcp"
              ]
            }
          }
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 31297,
      "protocol": "vless",
      "tag": "VLESSWS",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "email": "${domain}_vless_ws"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}ws"
        }
      }
    }
  ],
  "routing":{
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "blocked"
      }
    ]
  },
  "outbounds": [
    {
      "tag":"direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "dns": {
    "servers": [
      "74.82.42.42",
      "8.8.8.8",
      "8.8.4.4",
      "1.1.1.1",
      "localhost"
    ]
  }
}
EOF
    elif [[ "$1" = "custom" ]]
    then
        # custom xray-core
        cat << EOF > /etc/v2ray-agent/xray/conf/00_log.json
{
  "log": {
    "access": "/etc/v2ray-agent/xray/xray_access.log",
    "error": "/etc/v2ray-agent/xray/xray_error.log",
    "loglevel": "debug"
  }
}
EOF
      cat << EOF > /etc/v2ray-agent/xray/conf/09_routing.json
{
    "routing":{
        "domainStrategy": "AsIs",
        "rules": [
          {
            "type": "field",
            "protocol": [
              "bittorrent"
            ],
            "outboundTag": "blocked"
          }
        ]
  }
}
EOF

        # outbounds
       cat << EOF > /etc/v2ray-agent/xray/conf/10_outbounds.json
{
    "outbounds": [
        {
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "UseIPv4"
          }
        },
        {
          "tag": "blocked",
          "protocol": "blackhole",
          "settings": {}
        }
    ]
}
EOF
      cat << EOF > /etc/v2ray-agent/v2ray/conf/09_routing.json
{
    "routing":{
        "domainStrategy": "AsIs",
        "rules": [
          {
            "type": "field",
            "protocol": [
              "bittorrent"
            ],
            "outboundTag": "blocked"
          }
        ]
  }
}
EOF
        # dns
       cat << EOF > /etc/v2ray-agent/xray/conf/11_dns.json
{
    "dns": {
        "servers": [
          "74.82.42.42",
          "8.8.8.8",
          "8.8.4.4",
          "1.1.1.1",
          "localhost"
        ]
  }
}
EOF
        # VLESS_TCP_TLS/XTLS
        # 没有path则回落到此端口
        local fallbacksList='{"dest":31296,"xver":0}'

        if [[ -z `echo ${selectCustomInstallType}|grep 4` ]]
        then
            fallbacksList='{"dest":80,"xver":0}'
        fi

        # VLESS_WS_TLS
        if [[ ! -z `echo ${selectCustomInstallType}|grep 1` ]]
        then
            fallbacksList=${fallbacksList}',{"path":"/'${customPath}'ws","dest":31297,"xver":1}'
            cat << EOF > /etc/v2ray-agent/xray/conf/03_VLESS_WS_inbounds.json
{
"inbounds":[
        {
      "port": 31297,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "level": 0,
            "email": "${domain}_vless_ws"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}ws"
        }
      }
    }
    ]
}
EOF
        fi
# VMess_TCP
        if [[ ! -z `echo ${selectCustomInstallType}|grep 2` ]]
        then
            fallbacksList=${fallbacksList}',{"path":"/'${customPath}'tcp","dest":31298,"xver":1}'
            cat << EOF > /etc/v2ray-agent/xray/conf/04_VMess_TCP_inbounds.json
{
"inbounds":[
    {
      "port": 31298,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "tag":"VMessTCP",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "level": 0,
            "alterId": 0,
            "email": "${domain}_vmess_tcp"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "acceptProxyProtocol": true,
          "header": {
            "type": "http",
            "request": {
              "path": [
                "/${customPath}tcp"
              ]
            }
          }
        }
      }
    }
]
}
EOF
        fi
        # VMess_WS
        if [[ ! -z `echo ${selectCustomInstallType}|grep 3` ]]
        then
            fallbacksList=${fallbacksList}',{"path":"/'${customPath}'","dest":31299,"xver":1}'
            cat << EOF > /etc/v2ray-agent/xray/conf/05_VMess_WS_inbounds.json
{
"inbounds":[
{
      "port": 31299,
      "protocol": "vmess",
      "tag":"VMessWS",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 0,
            "add": "${add}",
            "level": 0,
            "email": "${domain}_vmess_ws"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "/${customPath}"
        }
      }
    }
]
}
EOF
        fi

        # VLESS_TCP

        cat << EOF > /etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json
{
  "inbounds":[
    {
      "port": 443,
      "protocol": "vless",
      "tag":"VLESSTCP",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "add": "${add}",
            "flow":"xtls-rprx-origin",
            "email": "${domain}_VLESS_XTLS/TLS-origin_TCP"
          },
          {
            "id": "${uuidDirect}",
            "flow":"xtls-rprx-direct",
            "email": "${domain}_VLESS_XTLS/TLS-direct_TCP"
          }
        ],
        "decryption": "none",
        "fallbacks": [
            ${fallbacksList}
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
          "alpn": [
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/v2ray-agent/tls/${domain}.crt",
              "keyFile": "/etc/v2ray-agent/tls/${domain}.key"
            }
          ]
        }
      }
    }
  ]
}
EOF

    fi
}
# 初始化Trojan-Go配置
initTrojanGoConfig(){

    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化Trojan配置"
    cat << EOF > /etc/v2ray-agent/trojan/config_full.json
{
    "run_type": "server",
    "local_addr": "127.0.0.1",
    "local_port": 31296,
    "remote_addr": "127.0.0.1",
    "remote_port": ${nginx_port},
    "log_level":0,
    "log_file":"/dev/null",
    "password": [
        "${uuid}"
    ],
    "dns":[
        "74.82.42.42",
        "8.8.8.8",
        "8.8.4.4",
        "1.1.1.1",
        "localhost"
    ],
    "transport_plugin":{
        "enabled":true,
        "type":"plaintext"
    },
    "websocket": {
        "enabled": true,
        "path": "/${customPath}tws",
        "host": "${domain}",
        "add":"${add}"
    },
    "router": {
        "enabled": false
    },
    "tcp":{
        "prefer_ipv4":true
    }
}
EOF
}

# 自定义CDN IP
customCDNIP(){
    echoContent skyBlue "\n进度 $1/${totalProgress} : 添加DNS智能解析"
    echoContent yellow " 移动:104.19.45.117"
    echoContent yellow " 联通:104.16.160.136"
    echoContent yellow " 电信:104.17.78.198"
    echoContent skyBlue "----------------------------"
    read -p '是否使用？[y/n]:' dnsProxy
    if [[ "${dnsProxy}" = "y" ]]
    then
        add="domain08.qiu4.ml"
        echoContent green "\n ---> 使用成功"
    else
        add="${domain}"
    fi
}

# 通用
defaultBase64Code(){
    local type=$1
    local ps=$2
    local id=$3
    local hostPort=$4
    local host=
    local port=
    if [[ ! -z `echo ${hostPort}|grep ":"` ]]
    then
        host=`echo ${hostPort}|awk -F "[:]" '{print $1}'`
        port=`echo ${hostPort}|awk -F "[:]" '{print $2}'`
    else
        host=${hostPort}
        port=443
    fi

    local path=$5
    local add=$6
    if [[ ${type} = "tcp" ]]
    then

        qrCodeBase64Default=`echo -n '{"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","net":"tcp","add":"'${host}'","allowInsecure":0,"method":"none","peer":""}'|sed 's#/#\\\/#g'|base64`
        qrCodeBase64Default=`echo ${qrCodeBase64Default}|sed 's/ //g'`
        echoContent yellow " ---> 通用json(tcp+tls)"
        echoContent green '    {"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","net":"tcp","add":"'${host}'","allowInsecure":0,"method":"none","peer":""}\n'
        # 通用Vmess
        echoContent yellow " ---> 通用vmess(tcp+tls)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        echo "通用vmess(tcp+tls)链接: " > /etc/v2ray-agent/v2ray/usersv2ray.conf
        echo "   vmess://${qrCodeBase64Default}" >> /etc/v2ray-agent/v2ray/usersv2ray.conf
    elif [[ ${type} = "wss" ]]
    then
        qrCodeBase64Default=`echo -n '{"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","path":'${path}',"net":"ws","add":"'${add}'","allowInsecure":0,"method":"none","peer":"'${host}'"}'|sed 's#/#\\\/#g'|base64`
        qrCodeBase64Default=`echo ${qrCodeBase64Default}|sed 's/ //g'`
        echoContent yellow " ---> 通用json(ws+tls)"
        echoContent green '    {"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","path":'${path}',"net":"ws","add":"'${add}'","allowInsecure":0,"method":"none","peer":"'${host}'"}\n'
        echoContent yellow " ---> 通用vmess(ws+tls)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        echo "通用vmess(ws+tls)链接: " > /etc/v2ray-agent/v2ray/usersv2ray.conf
        echo "   vmess://${qrCodeBase64Default}" >> /etc/v2ray-agent/v2ray/usersv2ray.conf
    elif [[ "${type}" = "h2" ]]
    then
        qrCodeBase64Default=`echo -n '{"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","path":'${path}',"net":"h2","add":"'${add}'","allowInsecure":0,"method":"none","peer":""}'|sed 's#/#\\\/#g'|base64`
        qrCodeBase64Default=`echo ${qrCodeBase64Default}|sed 's/ //g'`
        echoContent red "通用json--->"
        echoContent green '    {"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","path":'${path}',"net":"h2","add":"'${add}'","allowInsecure":0,"method":"none","peer":""}\n'
    elif [[ "${type}" = "vlesstcp" ]]
    then
        qrCodeBase64Default=`echo -n '{"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","path":'${path}',"net":"tcp","add":"'${add}'","allowInsecure":0,"method":"none","peer":"'${host}'"}'|sed 's#/#\\\/#g'|base64`
        qrCodeBase64Default=`echo ${qrCodeBase64Default}|sed 's/ //g'`
        echo "通用vmess(VLESS+TCP+TLS)链接: " > /etc/v2ray-agent/v2ray/usersv2ray.conf
        echo "   vmess://${qrCodeBase64Default}" >> /etc/v2ray-agent/v2ray/usersv2ray.conf
        echoContent yellow " ---> 通用json(VLESS+TCP+TLS)"
        echoContent green '    {"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"host":"'${host}'","type":"none","net":"tcp","add":"'${host}'","allowInsecure":0,"method":"none","peer":""}\n'
        echoContent green '    V2Ray v4.27.4+ 目前无通用订阅，需要手动配置，VLESS TCP、XTLS和TCP大部分一样，其余内容不变，请注意手动输入的流控flow类型，v2ray-core v4.32.1之后不支持XTLS，Xray-core支持，建议使用Xray-core\n'

    elif [[ "${type}" = "vmessws" ]]
    then
        qrCodeBase64Default=`echo -n '{"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","path":'${path}',"net":"ws","add":"'${host}'","allowInsecure":0,"method":"none","peer":"'${host}'","sni":"'${host}'"}'|sed 's#/#\\\/#g'|base64`
        qrCodeBase64Default=`echo ${qrCodeBase64Default}|sed 's/ //g'`
        echoContent yellow " ---> 通用json(VMess+WS+TLS)"
        echoContent green '    {"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","path":'${path}',"net":"ws","add":"'${add}'","allowInsecure":0,"method":"none","peer":"'${host}'"}\n'
        echoContent yellow " ---> 通用vmess(VMess+WS+TLS)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        # echoContent yellow " ---> 二维码 vmess(VMess+WS+TLS)"
        # echoContent green "https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vmess://${qrCodeBase64Default}\n"

    elif [[ "${type}" = "vmesstcp" ]]
    then
        qrCodeBase64Default=`echo -n '{"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"http","path":'${path}',"net":"tcp","add":"'${add}'","allowInsecure":0,"method":"none","peer":"'${host}'","obfs":"http","obfsParam":"'${host}'"}'|sed 's#/#\\\/#g'|base64`
        qrCodeBase64Default=`echo ${qrCodeBase64Default}|sed 's/ //g'`
        echoContent yellow " ---> 通用json(VMess+TCP+TLS)"
        echoContent green '    {"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"http","path":'${path}',"net":"tcp","add":"'${add}'","allowInsecure":0,"method":"none","peer":"'${host}'","obfs":"http","obfsParam":"'${host}'"}\n'
        echoContent yellow " ---> 通用vmess(VMess+TCP+TLS)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        echoContent yellow " ---> 二维码 vmess(VMess+TCP+TLS)"
        echoContent green "https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vmess://${qrCodeBase64Default}\n"
    elif [[ "${type}" = "vlessws" ]]
    then
        qrCodeBase64Default=`echo -n '{"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","path":'${path}',"net":"ws","add":"'${add}'","allowInsecure":0,"method":"none","peer":"'${host}'"}'|sed 's#/#\\\/#g'|base64`
        qrCodeBase64Default=`echo ${qrCodeBase64Default}|sed 's/ //g'`
        echoContent yellow " ---> 通用json(VLESS+WS+TLS)"
        echoContent green '    {"port":"'${port}'","ps":"'${ps}'","tls":"tls","id":'"${id}"',"aid":"0","v":"2","host":"'${host}'","type":"none","path":'${path}',"net":"ws","add":"'${add}'","allowInsecure":0,"method":"none","peer":"'${host}'"}\n'
        echoContent yellow " ---> 通用格式(VLESS+WS+TLS)"
        id=${id%"\""} && id=${id#"\""}
        echoContent green "    vless://${id}@${host}:${port}?encryption=none&security=tls&type=ws&host=${host}&sni=${host}&fp=&path=/${currentPath}ws&alpn=http/1.1#${host}_vl_ws\n"
    elif [[ "${type}" = "trojan" ]]
    then
        # URLEncode
        echoContent yellow " ---> Trojan(TLS)"
        echoContent green "    trojan://${id}@${host}:${port}?peer=${host}&sni=${host}\n"
        echoContent yellow " ---> 二维码 Trojan(TLS)"
        echoContent green "https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=trojan%3a%2f%2f${id}%40${host}%3a${port}%3fpeer%3d${host}%26sni%3d${host}%23${host}_trojan\n"

    elif [[ "${type}" = "trojangows" ]]
    then
        # URLEncode
        echoContent yellow " ---> Trojan-Go(WS+TLS) Shadowrocket / v2rayN"
        # echoContent green "    trojan://${id}@${add}:${port}?allowInsecure=0&&peer=${host}&sni=${host}&plugin=obfs-local;obfs=websocket;obfs-host=${host};obfs-uri=${path}#${host}_trojan_ws\n"
        echoContent green "    trojan://${id}@${host}:${port}?allowInsecure=0&peer=${host}&sni=${host}&plugin=obfs-local&type=ws&host=${host}&path=${path}#${host}_tr_ws\n"
        # echoContent yellow " ---> 二维码 Trojan-Go(WS+TLS) Shadowrocket"
        # echoContent green "https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=trojan%3a%2f%2f${id}%40${add}%3a${port}%3fallowInsecure%3d0%26peer%3d${host}%26plugin%3dobfs-local%3bobfs%3dwebsocket%3bobfs-host%3d${host}%3bobfs-uri%3d${path}%23${host}_trojan_ws\n"

        path=`echo ${path}|awk -F "[/]" '{print $2}'`
        echoContent yellow " ---> Trojan-Go(WS+TLS) QV2ray"
        # echoContent green "    trojan-go://${id}@${add}:${port}?sni=${host}&type=ws&host=${host}&path=%2F${path}#${host}_trojan_ws\n"
        echoContent green "    trojan-go://${id}@${currentHost}:${port}?sni=${currentHost}&type=ws&host=${currentHost}&path=%2F${path}#${host}_trg_ws\n"
    fi
}

# 账号
showAccounts(){
    readInstallType
    readConfigHostPathUUID
    readCustomInstallType
    showStatus=
    echoContent skyBlue "\n进度 $1/${totalProgress} : 帐号"


    if [[ "${v2rayAgentInstallType}" = "1" ]]
    then
        showStatus=true
        local configPath=
        if [[ "${coreInstallType}" = "1" ]]
        then
            configPath=${xrayCoreConfigFilePath}
        elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
        then
            configPath=${v2rayCoreConfigFilePath}
        fi
        # VLESS tcp
        local tcp=`cat ${configPath}|jq .inbounds[0]`
        local port=`echo ${tcp}|jq .port`
        local tcpID=`echo ${tcp}|jq .settings.clients[0].id`
        local tcpEmail="`echo ${tcp}|jq .settings.clients[0].email|awk -F '["]' '{print $2}'`"
        local CDNADD=`echo ${tcp}|jq .settings.clients[0].add|awk -F '["]' '{print $2}'`

        # XTLS Direct
        local tcpIDirect=`echo ${tcp}|jq .settings.clients[1].id`
        local tcpDirectEmail="`echo ${tcp}|jq .settings.clients[1].email|awk -F '["]' '{print $2}'`"


         # VLESS ws
        local vlessWS=`cat ${configPath}|jq .inbounds[3]`
        local vlessWSID=`echo ${vlessWS}|jq .settings.clients[0].id`
        local vlessWSEmail="`echo ${vlessWS}|jq .settings.clients[0].email|awk -F '["]' '{print $2}'`"
        local vlessWSPath=`echo ${vlessWS}|jq .streamSettings.wsSettings.path`

        # Vmess ws
        local ws=`cat ${configPath}|jq .inbounds[1]`
        local wsID=`echo ${ws}|jq .settings.clients[0].id`
        local wsEmail="`echo ${ws}|jq .settings.clients[0].email|awk -F '["]' '{print $2}'`"
        local wsPath=`echo ${ws}|jq .streamSettings.wsSettings.path`

        # Vmess tcp
        local vmessTCP=`cat ${configPath}|jq .inbounds[2]`
        local vmessTCPID=`echo ${vmessTCP}|jq .settings.clients[0].id`
        local vmessTCPEmail="`echo ${vmessTCP}|jq .settings.clients[0].email|awk -F '["]' '{print $2}'`"
        local vmessTCPath=`echo ${vmessTCP}|jq .streamSettings.tcpSettings.header.request.path[0]`

        # if [[ "${coreInstallType}" = "3" || "${coreInstallType}" = "1" ]]
        # then
            # echoContent skyBlue "\n============================ VLESS TCP TLS/XTLS-origin ==========================="
            # defaultBase64Code vlesstcp ${tcpEmail} "${tcpID}" "${currentHost}:${port}" ${add}

            # echoContent skyBlue "\n============================ VLESS TCP TLS/XTLS-direct ==========================="
            # defaultBase64Code vlesstcp ${tcpDirectEmail} "${tcpIDirect}" "${currentHost}:${port}" ${add}

        # elif [[ "${coreInstallType}" = "2" ]]
        # then
            # echoContent skyBlue "\n============================ VLESS TCP TLS ======================================="
            # defaultBase64Code vlesstcp ${tcpEmail} "${tcpID}" "${currentHost}:${port}" ${add}
        # fi

        echoContent skyBlue "\n================================ VLESS WS TLS CDN ================================"
        defaultBase64Code vlessws ${vlessWSEmail} "${vlessWSID}" "${currentHost}:${port}" "${vlessWSPath}" ${CDNADD}

        echoContent skyBlue "\n================================ VMess WS TLS CDN ================================"
        defaultBase64Code vmessws ${wsEmail} "${wsID}" "${currentHost}:${port}" "${wsPath}" ${CDNADD}

        # echoContent skyBlue "\n================================= VMess TCP TLS  ================================="
        # defaultBase64Code vmesstcp ${vmessTCPEmail} "${vmessTCPID}" "${currentHost}:${port}" "${vmessTCPath}" "${currentHost}"

    elif [[ "${v2rayAgentInstallType}" = "2" ]]
    then
        local configPath=
        if [[ "${coreInstallType}" = "1" ]]
        then
            configPath=${xrayCoreConfigFilePath}
        elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
        then
            configPath=${v2rayCoreConfigFilePath}
        fi

        showStatus=true

        # VLESS tcp
        local tcp=`cat ${configPath}|jq .inbounds[0]`
        local port=`echo ${tcp}|jq .port`
        local tcpID=`echo ${tcp}|jq .settings.clients[0].id`
        local tcpEmail="`echo ${tcp}|jq .settings.clients[0].email|awk -F '["]' '{print $2}'`"

        local CDNADD=`echo ${tcp}|jq .settings.clients[0].add|awk -F '["]' '{print $2}'`
        # XTLS Direct
        local tcpIDirect=`echo ${tcp}|jq .settings.clients[1].id`
        local tcpDirectEmail="`echo ${tcp}|jq .settings.clients[1].email|awk -F '["]' '{print $2}'`"

        if [[ "${coreInstallType}" = "3" || "${coreInstallType}" = "1" ]]
        then
            echoContent skyBlue "\n============================ VLESS TCP TLS/XTLS-origin ==========================="
            defaultBase64Code vlesstcp ${tcpEmail} "${tcpID}" "${currentHost}:${port}" ${add}

            echoContent skyBlue "\n============================ VLESS TCP TLS/XTLS-direct ==========================="
            defaultBase64Code vlesstcp ${tcpDirectEmail} "${tcpIDirect}" "${currentHost}:${port}" ${add}

        elif [[ "${coreInstallType}" = "2" ]]
        then
#            host=`echo ${tcp}|jq .streamSettings.tlsSettings.certificates[0].certificateFile|awk -F '[t][l][s][/]' '{print $2}'|awk -F '["]' '{print $1}'|awk -F '[.][c][r][t]' '{print $1}'`
            echoContent skyBlue "\n============================ VLESS TCP TLS ======================================="
            defaultBase64Code vlesstcp ${tcpEmail} "${tcpID}" "${currentHost}:${port}" ${add}
        fi

        if [[ ! -z "${currentCustomInstallType}" ]]
        then
            local coreType=
            if [[ "${coreInstallType}" = "1" ]]
            then
                coreType=xray
            elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
            then
                coreType=v2ray
            fi

            if [[ ! -z `echo ${currentCustomInstallType}|grep 1` ]]
            then
                # VLESS ws
                local vlessWS=`cat /etc/v2ray-agent/${coreType}/conf/03_VLESS_WS_inbounds.json|jq .inbounds[0]`
                local vlessWSID=`echo ${vlessWS}|jq .settings.clients[0].id`
                local vlessWSAdd=`echo ${tcp}|jq .settings.clients[0].add|awk -F '["]' '{print $2}'`
                local vlessWSEmail="`echo ${vlessWS}|jq .settings.clients[0].email|awk -F '["]' '{print $2}'`"
                local vlessWSPath=`echo ${vlessWS}|jq .streamSettings.wsSettings.path`

                echoContent skyBlue "\n================================ VLESS WS TLS CDN ================================"
                defaultBase64Code vlessws ${vlessWSEmail} "${vlessWSID}" "${currentHost}:${port}" "${vlessWSPath}" ${CDNADD}
            fi
            if [[ ! -z `echo ${currentCustomInstallType}|grep 2` ]]
            then

                local vmessTCP=`cat /etc/v2ray-agent/${coreType}/conf/04_VMess_TCP_inbounds.json|jq .inbounds[0]`
                local vmessTCPID=`echo ${vmessTCP}|jq .settings.clients[0].id`
                local vmessTCPEmail="`echo ${vmessTCP}|jq .settings.clients[0].email|awk -F '["]' '{print $2}'`"
                local vmessTCPath=`echo ${vmessTCP}|jq .streamSettings.tcpSettings.header.request.path[0]`

                echoContent skyBlue "\n================================= VMess TCP TLS  ================================="
                defaultBase64Code vmesstcp ${vmessTCPEmail} "${vmessTCPID}" "${currentHost}:${port}" "${vmessTCPath}" "${currentHost}"
            fi
            if [[ ! -z `echo ${currentCustomInstallType}|grep 3` ]]
            then

                local ws=`cat /etc/v2ray-agent/${coreType}/conf/05_VMess_WS_inbounds.json|jq .inbounds[0]`
                local wsID=`echo ${ws}|jq .settings.clients[0].id`
                local wsEmail="`echo ${ws}|jq .settings.clients[0].email|awk -F '["]' '{print $2}'`"
                local wsPath=`echo ${ws}|jq .streamSettings.wsSettings.path`

                echoContent skyBlue "\n================================ VMess WS TLS CDN ================================"
                defaultBase64Code vmessws ${wsEmail} "${wsID}" "${currentHost}:${port}" "${wsPath}" ${CDNADD}
            fi
        fi
    fi

    if [[ -d "/etc/v2ray-agent/" ]] && [[ -d "/etc/v2ray-agent/trojan/" ]] && [[ -f "/etc/v2ray-agent/trojan/config_full.json" ]]
    then
        showStatus=true
        local trojanUUID=`cat /etc/v2ray-agent/trojan/config_full.json |jq .password[0]|awk -F '["]' '{print $2}'`
        local trojanGoPath=`cat /etc/v2ray-agent/trojan/config_full.json|jq .websocket.path|awk -F '["]' '{print $2}'`
        local trojanGoAdd=`cat /etc/v2ray-agent/trojan/config_full.json|jq .websocket.add|awk -F '["]' '{print $2}'`
        # currentHost=${trojanGoAdd}
        # echoContent skyBlue "\n==================================  Trojan TLS  =================================="
        # defaultBase64Code trojan trojan ${trojanUUID} ${currentHost}

        echoContent skyBlue "\n================================  Trojan WS TLS   ================================"
        # echoContent skyBlue "current host : ${trojanGoAdd}"
        # if [[ -z ${trojanGoAdd} ]]
        # then
            # trojanGoAdd=${currentHost}
        # fi
        defaultBase64Code trojangows trojan "${trojanUUID}" "${currentHost}:${port}" "${trojanGoPath}" ${trojanGoAdd}
    fi
    if [[ -z ${showStatus} ]]
    then
        echoContent red " ---> 未安装"
    fi
}

# 卸载脚本
unInstall(){
    read -p "是否确认卸载安装内容？[y/n]:" unInstallStatus
    if [[ "${unInstallStatus}" != "y" ]]
    then
        echoContent green " ---> 放弃卸载"
        menu
        exit;
    fi

    handleNginx stop
    if [[ -z `ps -ef|grep -v grep|grep nginx` ]]
    then
        echoContent green " ---> 停止Nginx成功"
    fi

    handleV2Ray stop
    handleTrojanGo stop
    rm -rf /etc/systemd/system/v2ray.service
    echoContent green " ---> 删除V2Ray开机自启完成"
    rm -rf /etc/systemd/system/trojan-go.service
    echoContent green " ---> 删除Trojan-Go开机自启完成"
    rm -rf /tmp/v2ray-agent-tls/*
    if [[ -d "/etc/v2ray-agent/tls" ]] && [[ ! -z `find /etc/v2ray-agent/tls/ -name "*.key"` ]] && [[ ! -z `find /etc/v2ray-agent/tls/ -name "*.crt"` ]]
    then
        mv /etc/v2ray-agent/tls /tmp/v2ray-agent-tls
        if [[ ! -z `find /tmp/v2ray-agent-tls -name '*.key'` ]]
        then
            echoContent yellow " ---> 备份证书成功，请注意留存。[/tmp/v2ray-agent-tls]"
        fi
    fi

    rm -rf /etc/v2ray-agent
    rm -rf /etc/nginx/conf.d/alone.conf
    rm -rf /usr/bin/vasma
    rm -rf /usr/sbin/vasma
    echoContent green " ---> 卸载快捷方式完成"
    echoContent green " ---> 卸载v2ray-agent完成"
}

# 修改V2Ray CDN节点
updateV2RayCDN(){
    echoContent skyBlue "\n进度 $1/${totalProgress} : 修改CDN节点"
    if [[ ! -z "${v2rayAgentInstallType}" ]]
    then
        local configPath=
        if [[ "${coreInstallType}" = "1" ]]
        then
            configPath=${xrayCoreConfigFilePath}
        elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
        then
            configPath=${v2rayCoreConfigFilePath}
        fi

        local add=`cat ${configPath}|grep -v grep|grep add`
        if [[ ! -z ${add} ]]
        then
            echoContent red "=============================================================="
            echoContent yellow "1.CNAME www.digitalocean.com"
            echoContent yellow "2.CNAME amp.cloudflare.com"
            echoContent yellow "3.CNAME domain08.qiu4.ml"
            echoContent yellow "4.手动输入"
            echoContent red "=============================================================="
            read -p "请选择:" selectCDNType
            case ${selectCDNType} in
            1)
                setDomain="www.digitalocean.com"
            ;;
            2)
                setDomain="amp.cloudflare.com"
            ;;
            3)
                setDomain="domain08.qiu4.ml"
            ;;
            4)
                read -p "请输入想要自定义CDN IP或者域名:" setDomain
            ;;
            esac
            if [[ ! -z ${setDomain} ]]
            then
                # v2ray
                add=`echo ${add}|awk -F '["]' '{print $4}'`
                if [[ ! -z ${add} ]]
                then
                    sed -i "s/\"${add}\"/\"${setDomain}\"/g"  `grep "${add}" -rl ${configPath}`
                fi

                if [[ `cat ${configPath}|grep -v grep|grep add|awk -F '["]' '{print $4}'` = ${setDomain} ]]
                then
                    echoContent green " ---> V2Ray CDN修改成功"
                    if [[ "${coreInstallType}" = "1" ]]
                    then
                        handleXray stop
                        handleXray start
                    elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
                    then
                        handleV2Ray stop
                        handleV2Ray start
                    fi

                else
                    echoContent red " ---> 修改V2Ray CDN失败"
                fi

                # trojan
                if [[ -d "/etc/v2ray-agent/trojan" ]] && [[ -f "/etc/v2ray-agent/trojan/config_full.json" ]]
                then
                    add=`cat /etc/v2ray-agent/trojan/config_full.json|jq .websocket.add|awk -F '["]' '{print $2}'`
                    if [[ ! -z ${add} ]]
                    then
                        sed -i "s/${add}/${setDomain}/g"  `grep "${add}" -rl /etc/v2ray-agent/trojan/config_full.json`
                    fi
                fi

                if [[ -d "/etc/v2ray-agent/trojan" ]] && [[ -f "/etc/v2ray-agent/trojan/config_full.json" ]] && [[ `cat /etc/v2ray-agent/trojan/config_full.json|jq .websocket.add|awk -F '["]' '{print $2}'` = ${setDomain} ]]
                then
                    echoContent green "\n ---> Trojan CDN修改成功"
                    handleTrojanGo stop
                    handleTrojanGo start
                elif [[ -d "/etc/v2ray-agent/trojan" ]] && [[ -f "/etc/v2ray-agent/trojan/config_full.json" ]]
                then
                    echoContent red " ---> 修改Trojan CDN失败"
                fi
            fi
        else
            echoContent red " ---> 未安装可用类型"
        fi
    else
        echoContent red " ---> 未安装"
    fi
    menu
}

# 重置UUID
resetUUID(){
    echoContent skyBlue "\n进度 $1/${totalProgress} : 重置UUID"
    local resetStatus=false
    if [[ "${coreInstallType}" = "1" ]]
    then
        newUUID=`/etc/v2ray-agent/xray/xray uuid`
        newDirectUUID=`/etc/v2ray-agent/xray/xray uuid`
    elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
    then
        newUUID=`/etc/v2ray-agent/v2ray/v2ctl uuid`
        newDirectUUID=`/etc/v2ray-agent/v2ray/v2ctl uuid`
    fi

    if [[ ! -z "${v2rayAgentInstallType}" ]] && [[ -z "${currentCustomInstallType}" ]]
    then

        if [[ ! -z "${currentUUID}" ]]
        then
            read -p "是否自定义uuid？[y/n]:" customUUIDStatus
            if [[ "${customUUIDStatus}" = "y" ]]
            then
                echo
                read -p "请输入合法的uuid:" newUUID
                echo
            fi
            if [[ "${coreInstallType}" = "1" ]]
            then
                sed -i "s/${currentUUID}/${newUUID}/g"  `grep "${currentUUID}" -rl /etc/v2ray-agent/xray/config_full.json`
            elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
            then
                sed -i "s/${currentUUID}/${newUUID}/g"  `grep "${currentUUID}" -rl /etc/v2ray-agent/v2ray/config_full.json`
            fi
        fi

        if [[  ! -z "${currentUUIDDirect}"  ]]
        then
            echoContent skyBlue "-------------------------------------------------------------"
            read -p "是否自定义 XTLS-direct-uuid？[y/n]:" customUUIDStatus
            if [[ "${customUUIDStatus}" = "y" ]]
            then
                echo
                read -p "请输入合法的uuid:" newDirectUUID
                echo
                if [[ "${newUUID}" = "${newDirectUUID}" ]]
                then
                    echoContent red " ---> 两个uuid不可重复"
                    resetUUID 1
                    # exit 0;
                fi
            fi
            if [[ "${coreInstallType}" = "1" ]]
            then
                sed -i "s/${currentUUIDDirect}/${newDirectUUID}/g"  `grep "${currentUUIDDirect}" -rl /etc/v2ray-agent/xray/config_full.json`
            elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
            then
                sed -i "s/${currentUUIDDirect}/${newDirectUUID}/g"  `grep "${currentUUIDDirect}" -rl /etc/v2ray-agent/v2ray/config_full.json`
            fi

        fi
        if [[ "${coreInstallType}" = "1" ]]
        then
            echoContent green " ---> Xray UUID重置完毕"
            handleXray stop
            handleXray start
        elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
        then
            echoContent green " ---> V2Ray UUID重置完毕"
            handleV2Ray stop
            handleV2Ray start
        fi

        resetStatus=true

    elif [[ ! -z "${v2rayAgentInstallType}" ]] && [[ ! -z "${currentCustomInstallType}" ]]
    then
        read -p "是否自定义uuid？[y/n]:" customUUIDStatus
        if [[ "${customUUIDStatus}" = "y" ]]
        then
            echo
            read -p "请输入合法的uuid:" newUUID
            echo
        fi
        local configPathType=
        if [[ "${coreInstallType}" = "1" ]]
        then
            configPathType=xray
        elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
        then
            configPathType=v2ray
        fi

        uuidCount=0
        ls /etc/v2ray-agent/${configPathType}/conf|grep inbounds|while read row
        do
            cat /etc/v2ray-agent/${configPathType}/conf/${row}|jq .inbounds|jq -c '.[].settings.clients'|jq -c '.[].id'|while read row2
            do
                if [[ "${row}" = "02_VLESS_TCP_inbounds.json" ]]
                then
                    if [[ "${uuidCount}" != "1" ]]
                    then
                        oldUUID=`echo ${row2}|awk -F "[\"]" '{print $2}'`
                        sed -i "s/${oldUUID}/${newUUID}/g"  `grep "${oldUUID}" -rl /etc/v2ray-agent/${configPathType}/conf/${row}`
                    fi
                    if [[ "${row}" = "02_VLESS_TCP_inbounds.json" ]]
                    then
                        uuidCount=1
                    fi
                else
                    oldUUID=`echo ${row2}|awk -F "[\"]" '{print $2}'`
                    sed -i "s/${oldUUID}/${newUUID}/g"  `grep "${oldUUID}" -rl /etc/v2ray-agent/${configPathType}/conf/${row}`
                fi
            done
        done

        if [[ ! -z "${currentUUIDDirect}" ]]
        then
            echoContent skyBlue "-------------------------------------------------------------"
            read -p "是否自定义xtls-direct-uuid？[y/n]:" customUUIDStatus
            if [[ "${customUUIDStatus}" = "y" ]]
            then
                echo
                read -p "请输入合法的uuid:" newDirectUUID
                echo
                if [[ "${newUUID}" = "${newDirectUUID}" ]]
                then
                    echoContent red " ---> 两个uuid不可重复"
                    resetUUID 1
                    # exit 0;
                fi
            fi
            sed -i "s/${currentUUIDDirect}/${newDirectUUID}/g"  `grep "${currentUUIDDirect}" -rl /etc/v2ray-agent/${configPathType}/conf/02_VLESS_TCP_inbounds.json`
        fi

        if [[ "${coreInstallType}" = "1" ]]
        then
            echoContent green " ---> Xray UUID重置完毕"
            handleXray stop
            handleXray start
        elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
        then
            echoContent green " ---> V2Ray UUID重置完毕"
            handleV2Ray stop
            handleV2Ray start
        fi
        resetStatus=true
    else
        echoContent red " ---> 未使用脚本安装V2Ray"
        menu
        exit 0;
    fi

    if [[ -d "/etc/v2ray-agent" ]] && [[ -d "/etc/v2ray-agent/trojan" ]] && [[ -f "/etc/v2ray-agent/trojan/config_full.json" ]]
    then
        cat /etc/v2ray-agent/trojan/config_full.json|jq .password|jq -c '.[]'|while read row
        do
            oldUUID=`echo ${row}|awk -F "[\"]" '{print $2}'`
            sed -i "s/${oldUUID}/${newUUID}/g"  `grep "${oldUUID}" -rl /etc/v2ray-agent/trojan/config_full.json`
        done
        echoContent green " ---> Trojan UUID重置完毕"
        handleTrojanGo stop
        handleTrojanGo start
        resetStatus=true
    else
        echoContent red " ---> 未使用脚本安装Trojan"
    fi
    if [[ "${resetStatus}" = "true" ]]
    then
        readInstallType
        readConfigHostPathUUID
        readCustomInstallType
        showAccounts 1
    fi
}

# 更新脚本
updateV2RayAgent(){
    echoContent skyBlue "\n进度  $1/${totalProgress} : 更新v2ray-agent脚本"
    wget -P /etc/v2ray-agent/ -N --no-check-certificate "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh" && chmod 700 /etc/v2ray-agent/install.sh && vasma
}



# 安装BBR
bbrInstall(){
    echoContent red "\n=============================================================="
    echoContent green "BBR脚本用的[ylx2016]的成熟作品，地址[https://github.com/ylx2016/Linux-NetSpeed]，请熟知"
    echoContent red "   1.安装【推荐原版BBR+FQ】"
    echoContent red "   2.回退主目录"
    echoContent red "=============================================================="
    read -p "请选择：" installBBRStatus
    if [[ "${installBBRStatus}" = "1" ]]
    then
        wget -N --no-check-certificate "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
    else
        menu
    fi
}

# 查看、检查日志
checkLog(){
    echoContent skyBlue "\n功能 $1/${totalProgress} : 查看日志"
    echoContent red "\n=============================================================="
    local coreType=
    if [[ "${coreInstallType}" = "1" ]]
    then
        coreType=xray/xray

    elif [[ "${coreInstallType}" = "2" || "${coreInstallType}" = "3" ]]
    then
        coreType=v2ray/v2ray
    else
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 0;
    fi


    echoContent skyBlue "-------------------------V2Ray/Xray--------------------------------"
    echoContent yellow "1.查看info日志"
    echoContent yellow "2.监听info日志"
    echoContent yellow "3.查看error日志"
    echoContent yellow "4.监听error日志"
    echoContent yellow "5.清空V2Ray日志"
    echoContent skyBlue "-----------------------Trojan-Go------------------------------"
    echoContent yellow "6.查看Trojan-Go日志"
    echoContent yellow "7.监听Trojan-GO日志"
    echoContent yellow "8.清空Trojan-GO日志"
    echoContent skyBlue "-------------------------Nginx--------------------------------"
    echoContent yellow "9.查看Nginx日志"
    echoContent yellow "10.清空Nginx日志"
    echoContent red "=============================================================="


    read -p "请选择：" selectLogType
    case ${selectLogType} in
        1)
            cat /etc/v2ray-agent/${coreType}_access.log
        ;;
        2)
            tail -f /etc/v2ray-agent/${coreType}_access.log
        ;;
        3)
            cat /etc/v2ray-agent/${coreType}_error.log
        ;;
        4)
            tail -f /etc/v2ray-agent/${coreType}_error.log
        ;;
        5)
            echo '' > /etc/v2ray-agent/${coreType}_access.log
            echo '' > /etc/v2ray-agent/${coreType}_error.log
            echoContent green " ---> 清空完毕"
        ;;
        6)
            cat /etc/v2ray-agent/trojan/trojan.log
        ;;
        7)
            tail -f /etc/v2ray-agent/trojan/trojan.log
        ;;
        8)
            echo '' > /etc/v2ray-agent/trojan/trojan.log
            echoContent green " ---> 清空完毕"
        ;;
        9)
            cat /var/log/nginx/access.log
        ;;
        10)
            echo '' > /var/log/nginx/access.log
        ;;
    esac
    sleep 1
    menu
}
# 脚本快捷方式
aliasInstall(){
    if [[ -f "/root/install.sh" ]] && [[ -d "/etc/v2ray-agent" ]] && [[ ! -z `cat /root/install.sh|grep "作者：mack-a"` ]]
    then
        mv /root/install.sh /etc/v2ray-agent/install.sh
        if [[ -d "/usr/bin/" ]] && [[ ! -f "/usr/bin/vasma" ]]
        then
            ln -s /etc/v2ray-agent/install.sh /usr/bin/vasma
            chmod 700 /usr/bin/vasma
            rm -rf /root/install.sh
        elif [[ -d "/usr/sbin" ]] && [[ ! -f "/usr/sbin/vasma" ]]
        then
            ln -s /etc/v2ray-agent/install.sh /usr/sbin/vasma
            chmod 700 /usr/sbin/vasma
            rm -rf /root/install.sh
        fi
        echoContent green "快捷方式创建成功，可执行[vasma]重新打开脚本"
    fi
}

# v2ray-core个性化安装
customV2RayInstall(){
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "VLESS前置，默认安装0，如果只需要安装0，则只选择0即可"
    if [[ "${selectCoreType}" = "2" ]]
    then
        echoContent yellow "0.VLESS+TLS+TCP"
    else
        echoContent yellow "0.VLESS+TLS/XTLS+TCP"
    fi

    echoContent yellow "1.VLESS+TLS+WS[CDN]"
    echoContent yellow "2.VMess+TLS+TCP"
    echoContent yellow "3.VMess+TLS+WS[CDN]"
    echoContent yellow "4.Trojan、Trojan+WS[CDN]"
    read -p "请选择[多选]，[例如:123]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if [[ -z ${selectCustomInstallType} ]]
    then
        echoContent red " ---> 不可为空"
        customV2RayInstall
    elif [[ "${selectCustomInstallType}" =~ ^[0-4]+$ ]]
    then
        cleanUp xrayClean
        totalProgress=17
        installTools 1
        # 申请tls
        initTLSNginxConfig 2
        installTLS 3
        handleNginx stop
        initNginxConfig 4
        # 随机path
        if [[ ! -z `echo ${selectCustomInstallType}|grep 1` ]] || [[ ! -z `echo ${selectCustomInstallType}|grep 3` ]] || [[ ! -z `echo ${selectCustomInstallType}|grep 4` ]]
        then
            randomPathFunction 5
            customCDNIP 6
        fi
        nginxBlog 7
        handleNginx start

        # 安装V2Ray
        installV2Ray 8
        installV2RayService 9
        initV2RayConfig custom 10
        cleanUp xrayDel
        if [[ ! -z `echo ${selectCustomInstallType}|grep 4` ]]
        then
            installTrojanGo 11
            installTrojanService 12
            initTrojanGoConfig 13
            handleTrojanGo stop
            handleTrojanGo start
        else
            # 这里需要删除trojan的服务
            handleTrojanGo stop
            # rm -rf /etc/v2ray-agent/trojan/*
            # rm -rf /etc/systemd/system/trojan-go.service
        fi
        installCronTLS 14
        handleV2Ray stop
        handleV2Ray start
        # 生成账号
        checkGFWStatue 15
        showAccounts 16
    else
        echoContent red " ---> 输入不合法"
        customV2RayInstall
    fi
}

# Xray-core个性化安装
customXrayInstall(){
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "VLESS前置，默认安装0，如果只需要安装0，则只选择0即可"
    echoContent yellow "0.VLESS+TLS/XTLS+TCP"
    echoContent yellow "1.VLESS+TLS+WS[CDN]"
    echoContent yellow "2.VMess+TLS+TCP"
    echoContent yellow "3.VMess+TLS+WS[CDN]"
    echoContent yellow "4.Trojan、Trojan+WS[CDN]"
    read -p "请选择[多选]，[例如:123]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if [[ -z ${selectCustomInstallType} ]]
    then
        echoContent red " ---> 不可为空"
        customXrayInstall
    elif [[ "${selectCustomInstallType}" =~ ^[0-4]+$ ]]
    then
        cleanUp v2rayClean
        totalProgress=17
        installTools 1
        # 申请tls
        initTLSNginxConfig 2
        installTLS 3
        handleNginx stop
        initNginxConfig 4
        # 随机path
        if [[ ! -z `echo ${selectCustomInstallType}|grep 1` ]] || [[ ! -z `echo ${selectCustomInstallType}|grep 3` ]] || [[ ! -z `echo ${selectCustomInstallType}|grep 4` ]]
        then
            randomPathFunction 5
            customCDNIP 6
        fi
        nginxBlog 7
        handleNginx start

        # 安装V2Ray
        installXray 8
        installXrayService 9
        initXrayConfig custom 10
        cleanUp v2rayDel
        if [[ ! -z `echo ${selectCustomInstallType}|grep 4` ]]
        then
            installTrojanGo 11
            installTrojanService 12
            initTrojanGoConfig 13
            handleTrojanGo stop
            handleTrojanGo start
        else
            # 这里需要删除trojan的服务
            handleTrojanGo stop
            # rm -rf /etc/v2ray-agent/trojan/*
            # rm -rf /etc/systemd/system/trojan-go.service
        fi
        installCronTLS 14
        handleXray stop
        handleXray start
        # 生成账号
        checkGFWStatue 15
        showAccounts 16
    else
        echoContent red " ---> 输入不合法"
        customXrayInstall
    fi
}
# 选择核心安装---v2ray-core、xray-core、锁定版本的v2ray-core[xtls]
selectCoreInstall(){
    echoContent skyBlue "\n功能 1/${totalProgress} : 选择核心安装"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Xray-core"
    echoContent yellow "2.v2ray-core"
    # echoContent yellow "3.v2ray-core[XTLS]"
    echoContent red "=============================================================="
    read -p "请选择：" selectCoreType
    case ${selectCoreType} in
        1)

           if [[ "${selectInstallType}" = "2" ]]
            then
                customXrayInstall
            else
                xrayCoreInstall
            fi
        ;;
        2)
            v2rayCoreVersion=
            if [[ "${selectInstallType}" = "2" ]]
            then
                customV2RayInstall
            else
                v2rayCoreInstall
            fi
        ;;
        3)
            v2rayCoreVersion=v4.32.1
            if [[ "${selectInstallType}" = "2" ]]
            then
                customV2RayInstall
            else
                v2rayCoreInstall
            fi
        ;;
        *)
            echoContent red ' ---> 选择错误，重新选择'
            selectCoreInstall
        ;;
    esac
}


# v2ray-core 安装
v2rayCoreInstall(){
    cleanUp xrayClean
    selectCustomInstallType=
    totalProgress=17
    installTools 2
    # 申请tls
    initTLSNginxConfig 3
    
    handleV2Ray stop
    handleNginx start
    
    installTLS 4
    handleNginx stop
    initNginxConfig 5
    randomPathFunction 6
    # 安装V2Ray
    installV2Ray 7
    installV2RayService 8
    installTrojanGo 9
    installTrojanService 10
    customCDNIP 11
    initV2RayConfig all 12
    cleanUp xrayDel
    initTrojanGoConfig 13
    installCronTLS 14
    nginxBlog 15
    handleV2Ray stop
    sleep 2
    handleV2Ray start
    handleNginx start
    handleTrojanGo stop
    sleep 1
    handleTrojanGo start
    # 生成账号
    checkGFWStatue 16
    showAccounts 17
}

# xray-core 安装
xrayCoreInstall(){
    cleanUp v2rayClean
    selectCustomInstallType=

    totalProgress=17
    installTools 2
    # 申请tls
    initTLSNginxConfig 3
    installTLS 4
    handleNginx stop
    initNginxConfig 5
    randomPathFunction 6
    # 安装Xray
    handleV2Ray stop
    installXray 7
    installXrayService 8
    installTrojanGo 9
    installTrojanService 10
    # customCDNIP 11
    initXrayConfig all 12
    cleanUp v2rayDel
    initTrojanGoConfig 13
#    installCronTLS 14
    nginxBlog 15
    # handleXray stop
    # sleep 2
    handleXray start

    handleNginx start
    handleTrojanGo stop
    # sleep 1
    handleTrojanGo start
    # 生成账号
    checkGFWStatue 16
    showAccounts 17
}

# 核心管理
coreVersionManageMenu(){
    read -r -p " 是否更新 sing-box ？[y/N]:" updatesb
    updatesb=$(echo "$updatesb" | xargs)
    [ "${updatesb}" == "y" -o  "${updatesb}" == "Y" ] && updateSb

    if [[ -z "${coreInstallType}" ]]
    then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 0;
    fi
    if [[ "${coreInstallType}" = "1" ]]
    then
        xrayVersionManageMenu 1
    elif [[ "${coreInstallType}" = "2" ]]
    then
        v2rayCoreVersion=
        v2rayVersionManageMenu 1

    elif [[ "${coreInstallType}" = "3" ]]
    then
        v2rayCoreVersion=v4.32.1
        v2rayVersionManageMenu 1
    fi
}

# 更新伪装站
updateNginxBlog() {
    local nginxStaticPath=/usr/share/nginx/html/
    echoContent skyBlue "\n进度 $1/${totalProgress} : 更换伪装站点"
    echoContent red "=============================================================="
    echoContent yellow "# 如需自定义，请手动复制模版文件到 ${nginxStaticPath} \n"
    echoContent yellow "1.新手引导"
    echoContent yellow "2.游戏网站"
    echoContent yellow "3.个人博客01"
    echoContent yellow "4.企业站"
    echoContent yellow "5.解锁加密的音乐文件模版[https://github.com/ix64/unlock-music]"
    echoContent yellow "6.mikutap[https://github.com/HFIProgramming/mikutap]"
    echoContent yellow "7.企业站02"
    echoContent yellow "8.个人博客02"
    echoContent yellow "9.404自动跳转baidu"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectInstallNginxBlogType

    # if [[ "${selectInstallNginxBlogType}" == "10" ]]; then
        # echoContent red "\n=============================================================="
        # echoContent yellow "重定向的优先级更高，配置302之后如果更改伪装站点，根路由下伪装站点将不起作用"
        # echoContent yellow "如想要伪装站点实现作用需删除302重定向配置\n"
        # echoContent yellow "1.添加"
        # echoContent yellow "2.删除"
        # echoContent red "=============================================================="
        # read -r -p "请选择:" redirectStatus

        # if [[ "${redirectStatus}" == "1" ]]; then
            # backupNginxConfig backup
            # read -r -p "请输入要重定向的域名,例如 https://www.baidu.com:" redirectDomain
            # removeNginx302
            # addNginx302 "${redirectDomain}"
            # handleNginx stop
            # handleNginx start
            # if [[ -z $(pgrep -f "nginx") ]]; then
                # backupNginxConfig restoreBackup
                # handleNginx start
                # exit 0
            # fi
            # checkNginx302
            # exit 0
        # fi
        # if [[ "${redirectStatus}" == "2" ]]; then
            # removeNginx302
            # echoContent green " ---> 移除302重定向成功"
            # exit 0
        # fi
    # fi
    if [[ "${selectInstallNginxBlogType}" =~ ^[1-9]$ ]]; then
        rm -rf "${nginxStaticPath}"

        wget -q -P "${nginxStaticPath}" "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${selectInstallNginxBlogType}.zip" >/dev/null

        unzip -o "${nginxStaticPath}html${selectInstallNginxBlogType}.zip" -d "${nginxStaticPath}" >/dev/null
        rm -f "${nginxStaticPath}html${selectInstallNginxBlogType}.zip*"
        echoContent green " ---> 更换伪站成功"
    else
        echoContent red " ---> 选择错误，请重新选择"
        updateNginxBlog
    fi
}

# 主菜单
menu(){
    cd
    echoContent red "\n=============================================================="
    echoContent green "当前版本：v2.1.18.3 - 更新于2023/07/10"
    echoContent green "原作者：Github：https://github.com/mack-a/v2ray-agent"
    echoContent green "描述：七合一共存脚本"
    echoContent red "=============================================================="
    echoContent yellow "1.安装"
    echoContent yellow "2.任意组合安装"
    echoContent skyBlue "-------------------------工具管理-----------------------------"
    echoContent yellow "3.查看账号"
    echoContent yellow "4.自动排错 [已废弃]"
    echoContent yellow "5.更新证书"
    echoContent yellow "6.更换CDN节点"
    echoContent yellow "7.重置uuid"
    echoContent yellow "8.更换伪装站"
    echoContent skyBlue "-------------------------版本管理-----------------------------"
    echoContent yellow "9.core版本管理"
    echoContent yellow "10.升级Trojan-Go"
    echoContent yellow "11.升级脚本"
    echoContent yellow "12.安装BBR"
    echoContent skyBlue "-------------------------脚本管理-----------------------------"
    echoContent yellow "13.查看日志"
    echoContent yellow "14.卸载脚本"
    echoContent red "=============================================================="
    mkdirTools
    aliasInstall
    read -p "请选择:" selectInstallType
     case ${selectInstallType} in
        1)
            selectCoreInstall
        ;;
        2)
#            echoContent red " ---> 暂不开放"
#            exit 0;
            selectCoreInstall
        ;;
        3)
            showAccounts 1
        ;;
        5)
            renewalTLS 1
        ;;
        6)
            updateV2RayCDN 1
        ;;
        7)
            resetUUID 1
        ;;
        8)
            updateNginxBlog 1
        ;;
        9)
            coreVersionManageMenu 1
        ;;
        10)
            updateTrojanGo 1
        ;;
        11)
            updateV2RayAgent 1
        ;;
        12)
            bbrInstall
        ;;
        13)
            checkLog 1
        ;;
        14)
            unInstall 1
        ;;
    esac
}
menu
