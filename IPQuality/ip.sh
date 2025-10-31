#!/bin/bash
script_version="v2025-10-31"
check_bash() {
    major=${BASH_VERSINFO[0]}  # Bash 内建数组，直接拿主版本号
    if (( major < 4 )); then
        cat <<EOF
ERROR: Bash version is lower than 4.0!
Tips: Run the following script to automatically upgrade Bash.
bash <(curl -sL https://raw.githubusercontent.com/xykt/IPQuality/main/ref/upgrade_bash.sh)
EOF
        exit 1
    fi
}

check_bash


# ===== 字体 & 颜色 =====
declare -A F=(
    [B]="\033[1m" [D]="\033[2m" [I]="\033[3m" [U]="\033[4m"
    [Black]="\033[30m" [Red]="\033[31m" [Green]="\033[32m"
    [Yellow]="\033[33m" [Blue]="\033[34m" [Purple]="\033[35m"
    [Cyan]="\033[36m" [White]="\033[37m"
    [BackBlack]="\033[40m" [BackRed]="\033[41m" [BackGreen]="\033[42m"
    [BackYellow]="\033[43m" [BackBlue]="\033[44m" [BackPurple]="\033[45m"
    [BackCyan]="\033[46m" [BackWhite]="\033[47m"
    [Suffix]="\033[0m" [LineClear]="\033[2K" [LineUp]="\033[1A"
)

# ===== IP & 网络信息 =====
declare IP="" IPhide fullIP=0 YY="cn"
declare IPV4check=1 IPV6check=1 IPV4work=0 IPV6work=0
declare useNIC="" usePROXY="" CurlARG="" UA_Browser rawgithub
declare Media_Cookie IATA_Database ipjson

# ===== 错误 & 进程 =====
declare ERRORcode=0 ibar=0 bar_pid ibar_step=0 main_pid=$$

# ===== 模式开关 =====
declare mode_no=0 mode_yes=0 mode_lite=0 mode_json=0
declare mode_menu=0 mode_output=0 mode_privacy=0 PADDING=""

# ===== 服务 & API 数据 =====
declare -A services=(
    [maxmind]="" [ipinfo]="" [scamalytics]="" [ipregistry]="" [ipapi]="" 
    [abuseipdb]="" [ip2location]="" [dbip]="" [ipwhois]="" [ipdata]="" 
    [ipqs]="" [tiktok]="" [disney]="" [netflix]="" [youtube]="" 
    [amazon]="" [spotify]="" [chatgpt]=""
)

# ===== 报告相关 =====
declare -A swarn sinfo shead sbasic stype sscore sfactor smedia smail smailstatus stail

# ===== 帮助信息 =====
show_help() {
cat <<'EOF'
IP QUALITY CHECK SCRIPT IP质量体检脚本
Interactive Interface:  bash <(curl -sL https://IP.Check.Place) -EM
交互界面：              bash <(curl -sL https://IP.Check.Place) -M
Parameters 参数运行: bash <(curl -sL https://IP.Check.Place) [-4] [-6] [-f] [-h] [-j] [-i iface] [-l language] [-n] [-x proxy] [-y] [-E] [-M]
    -4                             Test IPv4                                  测试IPv4
    -6                             Test IPv6                                  测试IPv6
    -f                             Show full IP on reports                    报告展示完整IP地址
    -h                             Help information                           帮助信息
    -j                             JSON output                                JSON输出
    -i eth0                        Specify network interface                  指定检测网卡
       ipaddress                   Specify outbound IP Address                指定检测出口IP
    -l cn|en|jp|es|de|fr|ru|pt     Specify script language                    指定报告语言
    -n                             No OS or dependencies check                跳过系统检测及依赖安装
    -o /path/to/file.ansi          Output ANSI report to file                 输出ANSI报告至文件
       /path/to/file.json          Output JSON result to file                 输出JSON结果至文件
       /path/to/file.anyother      Output plain text report to file           输出纯文本报告至文件
    -p                             Privacy mode - no generate report link     隐私模式：不生成报告链接
    -x http://usr:pwd@proxyurl:p   Specify http proxy                         指定http代理
       https://usr:pwd@proxyurl:p  Specify https proxy                        指定https代理
       socks5://usr:pwd@proxyurl:p Specify socks5 proxy                       指定socks5代理
    -y                             Install dependencies without interupt      自动安装依赖
    -E                             Specify English Output                     指定英文输出
    -M                             Run with Interactive Interface             交互界面方式运行
EOF
}

set_language() {
    case "$YY" in
        en|jp|es|de|fr|ru|pt)
            # ⚠️ 错误提示
            swarn=(
                [1]="ERROR: Unsupported parameters!"
                [2]="ERROR: IP address format error!"
                [3]="ERROR: Dependent programs are missing. Please run as root or install sudo!"
                [4]="ERROR: Parameter -4 conflicts with -i or -6!"
                [6]="ERROR: Parameter -6 conflicts with -i or -4!"
                [7]="ERROR: The specified network interface or outbound IP is invalid or does not exist!"
                [8]="ERROR: The specified proxy parameter is invalid or not working!"
                [10]="ERROR: Output file already exist!"
                [11]="ERROR: Output file is not writable!"
                [40]="ERROR: IPv4 is not available!"
                [60]="ERROR: IPv6 is not available!"
            )

            # ℹ️ 信息提示
            sinfo=(
                [database]="Checking IP database "
                [media]="Checking stream media "
                [ai]="Checking AI provider "
                [mail]="Connecting Email server "
                [dnsbl]="Checking Blacklist database "
                [ldatabase]=21
                [lmedia]=22
                [lai]=21
                [lmail]=24
                [ldnsbl]=28
            )

            # 📄 报告头
            shead=(
                [title]="IP QUALITY CHECK REPORT: "
                [title_lite]="IP QUALITY CHECK REPORT(LITE): "
                [ver]="Version: $script_version"
                [bash]="bash <(curl -sL https://Check.Place) -EI"
                [git]="https://github.com/xykt/IPQuality"
                [time]=$(date -u +"Report Time: %Y-%m-%d %H:%M:%S UTC")
                [ltitle]=25
                [ltitle_lite]=31
                [ptime]=$(printf '%7s' '')
            )
            ;;
        cn)
            swarn=(
                [1]="错误：不支持的参数！"
                [2]="错误：IP地址格式错误！"
                [3]="错误：未安装依赖程序，请以root执行此脚本，或者安装sudo命令！"
                [4]="错误：参数-4与-i/-6冲突！"
                [6]="错误：参数-6与-i/-4冲突！"
                [7]="错误：指定的网卡或出口IP不存在！"
                [8]="错误：指定的代理服务器不可用！"
                [10]="错误：输出文件已存在！"
                [11]="错误：输出文件不可写！"
                [40]="错误：IPV4不可用！"
                [60]="错误：IPV6不可用！"
            )

            sinfo=(
                [database]="正在检测IP数据库 "
                [media]="正在检测流媒体服务商 "
                [ai]="正在检测AI服务商 "
                [mail]="正在连接邮件服务商 "
                [dnsbl]="正在检测黑名单数据库 "
                [ldatabase]=17
                [lmedia]=21
                [lai]=17
                [lmail]=19
                [ldnsbl]=21
            )

            shead=(
                [title]="IP质量体检报告："
                [title_lite]="IP质量体检报告(Lite)："
                [ver]="脚本版本：$script_version"
                [bash]="bash <(curl -sL https://Check.Place) -I"
                [git]="https://github.com/xykt/IPQuality"
                [time]=$(TZ="Asia/Shanghai" date +"报告时间：%Y-%m-%d %H:%M:%S CST")
                [ltitle]=16
                [ltitle_lite]=22
                [ptime]=$(printf '%8s' '')
            )
            ;;
        *)
            echo -ne "ERROR: Language not supported!"
            ;;
    esac
}

# 🔹 获取运行次数
countRunTimes() {
    local RunTimes
    RunTimes=$(curl $CurlARG -s --max-time 10 "https://hits.xykt.de/ip?action=hit" 2>&1)
    stail[today]=$(echo "$RunTimes" | jq '.daily')
    stail[total]=$(echo "$RunTimes" | jq '.total')
}

# 🔹 显示进度条（接口）
show_progress_bar() {
    show_progress_bar_ "$@" 1>&2
}

# 🔹 内部进度条逻辑
show_progress_bar_() {
    local bar="\u280B\u2819\u2839\u2838\u283C\u2834\u2826\u2827\u2807\u280F"
    local n=${#bar}
    local ibar=0
    local main_pid=${main_pid:-$$}  # 如果没有设置，默认当前脚本PID
    while sleep 0.1; do
        # 如果主进程不存在就退出
        if ! kill -0 "$main_pid" 2>/dev/null; then
            echo -ne ""
            exit
        fi
        # 打印进度条
        echo -ne "\r$Font_Cyan$Font_B[$IP]# $1$Font_Cyan$Font_B$(printf '%*s' "$2" '' | tr ' ' '.') ${bar:ibar++*6%n:6} $(printf '%02d%%' $ibar_step) $Font_Suffix"
    done
}

# 🔹 停止进度条
kill_progress_bar() {
    kill "$bar_pid" 2>/dev/null
    echo -ne "\r"
}

install_dependencies() {
    local missing=(jq curl bc nc dig)
    local detected_pm=""
    local install_cmd=""

    # 包管理器映射表
    declare -A pm_cmds=(
        [apt]="apt-get install -y"
        [dnf]="dnf install -y"
        [yum]="yum install -y"
        [pacman]="pacman -S --noconfirm"
        [apk]="apk add"
        [zypper]="zypper install -y"
        [brew]="brew install"
        [xbps-install]="xbps-install -Sy"
    )

    # 包名差异映射
    declare -A pkg_map_apt=( [nc]="netcat-openbsd" [dig]="dnsutils" [iproute]="iproute2" )
    declare -A pkg_map_pacman=( [nc]="gnu-netcat" [dig]="bind-tools" [iproute]="iproute2" )
    declare -A pkg_map_dnf=( [nc]="nmap-ncat" [dig]="bind-utils" [iproute]="iproute" )
    declare -A pkg_map_yum=( [nc]="nmap-ncat" [dig]="bind-utils" [iproute]="iproute" )
    declare -A pkg_map_apk=( [nc]="netcat-openbsd" [dig]="bind-tools" [iproute]="iproute2" )

    # 查找可用包管理器
    for pm in "${!pm_cmds[@]}"; do
        if command -v "$pm" >/dev/null 2>&1; then
            detected_pm="$pm"
            install_cmd="${pm_cmds[$pm]}"
            break
        fi
    done

    if [ -z "$detected_pm" ]; then
        echo "No supported package manager found."
        exit 1
    fi

    # 替换不同包管理器的包名
    case "$detected_pm" in
        apt) for i in "${!missing[@]}"; do missing[$i]=${pkg_map_apt[${missing[$i]}]:-${missing[$i]}}; done ;;
        pacman) for i in "${!missing[@]}"; do missing[$i]=${pkg_map_pacman[${missing[$i]}]:-${missing[$i]}}; done ;;
        dnf) for i in "${!missing[@]}"; do missing[$i]=${pkg_map_dnf[${missing[$i]}]:-${missing[$i]}}; done ;;
        yum) for i in "${!missing[@]}"; do missing[$i]=${pkg_map_yum[${missing[$i]}]:-${missing[$i]}}; done ;;
        apk) for i in "${!missing[@]}"; do missing[$i]=${pkg_map_apk[${missing[$i]}]:-${missing[$i]}}; done ;;
    esac

    # sudo 检测
    local usesudo=""
    if [ $(id -u) -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        usesudo="sudo"
    fi

    # 提示用户确认
    if [[ $mode_yes -eq 0 ]]; then
        read -p "Lacking dependencies: ${missing[*]}. Install using $detected_pm? (y/n): " choice
        case "$choice" in y|Y) echo "Installing...";; *) echo "Script exited."; exit 0;; esac
    else
        echo "Detected -y, installing dependencies..."
    fi

    # 执行安装
    $usesudo $install_cmd "${missing[@]}"
}

declare -A browsers=(
    [Chrome]="139.0.7258.128 139.0.7258.67 138.0.7204.185 138.0.7204.170 138.0.7204.159 138.0.7204.102 138.0.7204.100 138.0.7204.51 138.0.7204.49 137.0.7151.122 138.0.7204.35 137.0.7151.121 137.0.7151.105 137.0.7151.104 137.0.7151.57 137.0.7151.55 136.0.7103.116 137.0.7151.40 136.0.7103.113 136.0.7103.92 135.0.7049.117 136.0.7103.48 135.0.7049.114 135.0.7049.86 135.0.7049.42 135.0.7049.41 134.0.6998.167 134.0.6998.119 134.0.6998.117 134.0.6998.37 134.0.6998.35 133.0.6943.128 133.0.6943.100 133.0.6943.59 133.0.6943.53 132.0.6834.162 133.0.6943.35 132.0.6834.160 132.0.6834.112 132.0.6834.110 131.0.6778.267 132.0.6834.83 131.0.6778.264 131.0.6778.204 131.0.6778.139 131.0.6778.109 131.0.6778.71 131.0.6778.69 130.0.6723.119 131.0.6778.33 130.0.6723.116 130.0.6723.71 130.0.6723.60 130.0.6723.58 129.0.6668.103 130.0.6723.44 129.0.6668.100 129.0.6668.72 129.0.6668.60 129.0.6668.42 128.0.6613.122 128.0.6613.121 128.0.6613.115 128.0.6613.113 127.0.6533.122 128.0.6613.36 127.0.6533.119 127.0.6533.100 127.0.6533.74 127.0.6533.72 126.0.6478.185 127.0.6533.57 126.0.6478.183 126.0.6478.128 126.0.6478.116 126.0.6478.114 126.0.6478.61 125.0.6422.176 126.0.6478.56 125.0.6422.144 126.0.6478.36 125.0.6422.142 125.0.6422.114 125.0.6422.77 125.0.6422.76 124.0.6367.210 125.0.6422.60 124.0.6367.208 124.0.6367.201 124.0.6367.156 125.0.6422.41 124.0.6367.155 124.0.6367.119 124.0.6367.92 124.0.6367.63 124.0.6367.61 123.0.6312.124 124.0.6367.60 123.0.6312.122 123.0.6312.106 123.0.6312.105 123.0.6312.60 123.0.6312.58 122.0.6261.131 123.0.6312.46 122.0.6261.129 122.0.6261.128 122.0.6261.112 122.0.6261.111 122.0.6261.71 122.0.6261.69 121.0.6167.189 122.0.6261.57 121.0.6167.187 121.0.6167.186 121.0.6167.162 121.0.6167.160 121.0.6167.140 121.0.6167.86 121.0.6167.85 120.0.6099.227 120.0.6099.225 121.0.6167.75 120.0.6099.224 120.0.6099.218 120.0.6099.216 120.0.6099.200 120.0.6099.199 120.0.6099.129 120.0.6099.110 120.0.6099.109 120.0.6099.62 120.0.6099.56"
    [Firefox]="132.0 131.0 130.0 129.0 128.0 127.0 126.0 125.0 124.0 123.0 122.0 121.0 120.0")

generate_random_user_agent() {
    local keys=("${!browsers[@]}")
    local browser="${keys[RANDOM % ${#keys[@]}]}"
    local versions=(${browsers[$browser]})
    local version="${versions[RANDOM % ${#versions[@]}]}"

    case $browser in
        Chrome)
            UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$version Safari/537.36"
            ;;
        Firefox)
            UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:$version) Gecko/20100101 Firefox/$version"
            ;;
        *)
            UA_Browser="Mozilla/5.0"
            ;;
    esac
}

adapt_locale() {
    # 检测 Unicode 支持，如果宽字符长度大于 1 就认为支持
    [[ $(printf '\u2800' | wc -c) -gt 1 ]] && export LC_CTYPE=en_US.UTF-8
}

check_connectivity() {
    local url="https://www.google.com/generate_204"
    local timeout=2
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" "$url" 2>/dev/null)
    if [[ "$code" == "204" ]]; then
        rawgithub="https://github.com/xykt/IPQuality/raw/"
        return 0
    else
        rawgithub="https://testingcf.jsdelivr.net/gh/xykt/IPQuality@"
        return 1
    fi
}

is_valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            (( octet > 255 )) && return 1
        done
        return 0
    fi
    return 1
}

is_private_ipv4() {
    local ip=$1
    case $ip in
        10.*|192.168.*|127.*|0.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|224.*|23[0-9].*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

get_ipv4() {
    local apis=("myip.check.place" "ip.sb" "ping0.cc" "icanhazip.com" "api64.ipify.org" "ifconfig.co" "ident.me")
    for api in "${apis[@]}"; do
        local ip
        ip=$(curl $CurlARG -s4 --fail --max-time 2 "$api") || continue
        if [[ -n $ip && $(is_valid_ipv4 "$ip" && echo 1 || echo 0) -eq 1 ]]; then
            IPV4="$ip"
            break
        fi
    done
}

hide_ipv4() {
    local ip=$1
    if [[ -n $ip ]]; then
        IFS='.' read -r -a parts <<< "$ip"
        IPhide="${parts[0]}.${parts[1]}.*.*"
    else
        IPhide=""
    fi
}

hide_ipv6() {
    local ip=$1
    if [[ -n $ip ]]; then
        # 用数组处理，支持 :: 缩写
        local -a parts
        IFS=':' read -r -a parts <<< "$(python3 -c "import ipaddress; print(ipaddress.IPv6Address('$ip').exploded)")"
        IPhide="${parts[0]}:${parts[1]}:${parts[2]}:*:*:*:*:*"
    else
        IPhide=""
    fi
}

is_valid_ipv6() {
    local ip=$1
    python3 -c "import ipaddress; ipaddress.IPv6Address('$ip')" >/dev/null 2>&1
    IPV6work=$?
    return $IPV6work
}

is_private_ipv6() {
    local ip=$1
    case $ip in
        fe80:*|fc00:*|fd00:*|2001:db8:*|::1|::ffff:*|2002:*|2001:*) return 0 ;;
        *) return 1 ;;
    esac
}

get_ipv6() {
    IPV6=""
    local apis=("myip.check.place" "ip.sb" "ping0.cc" "icanhazip.com" "api64.ipify.org" "ifconfig.co" "ident.me")
    for api in "${apis[@]}"; do
        local ip=$(curl $CurlARG -s6k --fail --max-time 2 "$api") || continue
        is_valid_ipv6 "$ip" && { IPV6="$ip"; break; }
    done
}

generate_dms() {
    local lat=$1 lon=$2
    [[ -z $lat || $lat == "null" || -z $lon || $lon == "null" ]] && echo "" && return

    convert_single() {
        local coord=$1 dir=$2
        (( coord < 0 )) && coord=$(( -coord )) 
        local deg=${coord%.*}
        local min_frac=$(echo "($coord - $deg) * 60" | bc -l)
        local min=${min_frac%.*}
        local sec=$(printf "%.0f" "$(echo "($min_frac - $min) * 60" | bc -l)")
        echo "${deg}°${min}′${sec}″$dir"
    }

    local lat_dir='N' lon_dir='E'
    (( $(echo "$lat < 0" | bc -l) )) && lat_dir='S'
    (( $(echo "$lon < 0" | bc -l) )) && lon_dir='W'

    echo "$(convert_single $lat $lat_dir), $(convert_single $lon $lon_dir)"
}

generate_map_url() {
    local lat=$1
    local lon=$2
    local radius=$3
    local marker=${4:-0}  # 默认不加标记

    [[ -z $lat || $lat == "null" || -z $lon || $lon == "null" ]] && echo "" && return

    # 选择 zoom
    local zoom=15
    if [[ -n $radius ]]; then
        if (( radius > 1000 )); then zoom=12
        elif (( radius > 500 )); then zoom=13
        elif (( radius > 250 )); then zoom=14
        fi
    fi

    if (( marker )); then
        echo "https://www.google.com/maps/place/${lat},${lon}/@${lat},${lon},${zoom}z"
    else
        echo "https://www.google.com/maps/@${lat},${lon},${zoom}z"
    fi
}


# 进度条
show_db_progress() {
    local name="$1"
    ((ibar_step += 3))
    show_progress_bar "$name" $((40 - 8 - ${sinfo[ldatabase]})) &
    bar_pid="$!" && disown "$bar_pid"
    trap "kill_progress_bar" RETURN
}

# 安全 jq 获取字段
get_field() {
    local RESPONSE="$1"
    local jq_path="$2"
    local default="${3:-null}"
    local val
    val=$(echo "$RESPONSE" | jq -r "$jq_path" 2>/dev/null || echo "$default")
    echo "$val"
}

# stype 映射
map_stype() {
    local val="$1"
    shopt -s nocasematch
    case $val in
        business|isp|hosting|education|government|banking|organization|military|library|cdn|lineisp|mobile|spider|reserved)
            echo "${stype[$val]}" ;;
        *) echo "${stype[other]}" ;;
    esac
    shopt -u nocasematch
}

# 风险等级判定
map_score() {
    local score="$1"
    if (( score < 20 )); then
        echo "${sscore[low]}"
    elif (( score < 60 )); then
        echo "${sscore[medium]}"
    elif (( score < 90 )); then
        echo "${sscore[high]}"
    else
        echo "${sscore[veryhigh]}"
    fi
}

# 通用 curl 获取 JSON
fetch_json() {
    local url="$1"
    local method="${2:-GET}"
    local RESPONSE
    RESPONSE=$(curl $CurlARG -sL -$method -m 10 "$url")
    echo "$RESPONSE" | jq . >/dev/null 2>&1 || RESPONSE=""
    echo "$RESPONSE"
}


# IP 数据源模块

db_maxmind() {
    show_db_progress "Maxmind"
    local RESPONSE
    RESPONSE=$(fetch_json "https://ipinfo.check.place/$IP?lang=$YY")
    
    maxmind=()
    maxmind[asn]=$(get_field "$RESPONSE" '.ASN.AutonomousSystemNumber')
    maxmind[org]=$(get_field "$RESPONSE" '.ASN.AutonomousSystemOrganization')
    maxmind[city]=$(get_field "$RESPONSE" '.City.Name')
    maxmind[region]=$(get_field "$RESPONSE" '.Subdivision[0].Name')
    maxmind[country]=$(get_field "$RESPONSE" '.Country.Name')
    maxmind[latitude]=$(get_field "$RESPONSE" '.Location.Latitude')
    maxmind[longitude]=$(get_field "$RESPONSE" '.Location.Longitude')
    maxmind[stype]=$(map_stype "$(get_field "$RESPONSE" '.Type')")
    maxmind[score]=$(map_score "$(get_field "$RESPONSE" '.Risk.Score')")

    if [[ ${maxmind[latitude]} != "null" && ${maxmind[longitude]} != "null" ]]; then
        maxmind[dms]=$(generate_dms "${maxmind[latitude]}" "${maxmind[longitude]}")
        maxmind[map]=$(generate_googlemap_url "${maxmind[latitude]}" "${maxmind[longitude]}" "${maxmind[rad]}")
    else
        maxmind[dms]="null"
        maxmind[map]="null"
    fi
}

db_ipinfo() {
    show_db_progress "IPinfo"
    local RESPONSE
    RESPONSE=$(fetch_json "https://ipinfo.io/widget/demo/$IP")

    ipinfo=()
    ipinfo[asn]=$(get_field "$RESPONSE" '.asn.number')
    ipinfo[org]=$(get_field "$RESPONSE" '.org')
    ipinfo[city]=$(get_field "$RESPONSE" '.city')
    ipinfo[region]=$(get_field "$RESPONSE" '.region')
    ipinfo[country]=$(get_field "$RESPONSE" '.country')
    ipinfo[latitude]=$(get_field "$RESPONSE" '.loc' | cut -d',' -f1)
    ipinfo[longitude]=$(get_field "$RESPONSE" '.loc' | cut -d',' -f2)
    ipinfo[stype]=$(map_stype "$(get_field "$RESPONSE" '.type')")
    ipinfo[score]=$(map_score "$(get_field "$RESPONSE" '.risk')")

    if [[ ${ipinfo[latitude]} != "null" && ${ipinfo[longitude]} != "null" ]]; then
        ipinfo[dms]=$(generate_dms "${ipinfo[latitude]}" "${ipinfo[longitude]}")
        ipinfo[map]=$(generate_googlemap_url "${ipinfo[latitude]}" "${ipinfo[longitude]}" "${ipinfo[rad]}")
    else
        ipinfo[dms]="null"
        ipinfo[map]="null"
    fi
}

db_scamalytics() {
    show_db_progress "Scamalytics"
    local RESPONSE
    RESPONSE=$(fetch_json "https://ipinfo.check.place/$IP?db=scamalytics")

    scamalytics=()
    scamalytics[asn]=$(get_field "$RESPONSE" '.asn')
    scamalytics[org]=$(get_field "$RESPONSE" '.org')
    scamalytics[city]=$(get_field "$RESPONSE" '.city')
    scamalytics[region]=$(get_field "$RESPONSE" '.region')
    scamalytics[country]=$(get_field "$RESPONSE" '.country')
    scamalytics[stype]=$(map_stype "$(get_field "$RESPONSE" '.type')")
    scamalytics[score]=$(map_score "$(get_field "$RESPONSE" '.risk_score')")
}

db_ipregistry() {
    show_db_progress "IPregistry"
    local RESPONSE
    RESPONSE=$(fetch_json "https://ipinfo.check.place/$IP?db=ipregistry")

    ipregistry=()
    ipregistry[asn]=$(get_field "$RESPONSE" '.asn.number')
    ipregistry[org]=$(get_field "$RESPONSE" '.asn.org')
    ipregistry[city]=$(get_field "$RESPONSE" '.location.city')
    ipregistry[region]=$(get_field "$RESPONSE" '.location.region.name')
    ipregistry[country]=$(get_field "$RESPONSE" '.location.country.name')
    ipregistry[stype]=$(map_stype "$(get_field "$RESPONSE" '.type')")
    ipregistry[score]=$(map_score "$(get_field "$RESPONSE" '.risk.score')")
}



# 检查 IPv4 或 IPv6 是否合法
function check_ip_valid() {
    local ip="$1"
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # IPv4 每段 <=255
        for octet in ${ip//./ }; do
            (( octet >=0 && octet <=255 )) || return 1
        done
        return 0
    elif [[ $ip =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        # 简单 IPv6 验证
        return 0
    else
        return 1
    fi
}

# 计算 IPv4 网络地址
function calc_ip_net() {
    local ip="$1"
    local mask="$2"
    check_ip_valid "$ip" || { echo ""; return 1; }

    IFS=. read -r i1 i2 i3 i4 <<< "$ip"
    IFS=. read -r m1 m2 m3 m4 <<< "$mask"

    echo "$((i1 & m1)).$((i2 & m2)).$((i3 & m3)).$((i4 & m4))"
}

# 判断 DNS IP 是否公网可用
function check_dns_ip() {
    local ip="$1"
    local local_ip="$2"

    check_ip_valid "$ip" || { echo 0; return; }

    if [[ "$ip" == *.* ]]; then
        # IPv4
        case "$(calc_ip_net $ip 255.0.0.0)" in
            10.0.0.0) echo 0; return;;
        esac
        case "$(calc_ip_net $ip 255.240.0.0)" in
            172.16.0.0) echo 0; return;;
        esac
        case "$(calc_ip_net $ip 255.255.0.0)" in
            192.168.0.0|169.254.0.0) echo 0; return;;
        esac
        # 判断同网段
        if [[ "$(calc_ip_net $ip 255.255.255.0)" == "$(calc_ip_net $local_ip 255.255.255.0)" ]]; then
            echo 0
            return
        fi
        echo 1
    elif [[ "$ip" == *:* ]]; then
        # IPv6
        local ip_lc="${ip,,}"  # 转小写
        case "$ip_lc" in
            fe8*|fc*|fd*|ff*) echo 0; return;;
            *) echo 1;;
        esac
    else
        echo 0
    fi
}

function Check_DNS_1() {
    local resultdns=$(nslookup $1)
    local resultinlines=(${resultdns//$'\n'/ })
    for i in ${resultinlines[*]}; do
        if [[ $i == "Name:" ]]; then
            local resultdnsindex=$((resultindex + 3))
            break
        fi
        local resultindex=$((resultindex + 1))
    done
    echo $(Check_DNS_IP ${resultinlines[$resultdnsindex]} ${resultinlines[1]})
}
function Check_DNS_2() {
    local resultdnstext=$(dig $1 | grep "ANSWER:")
    local resultdnstext=${resultdnstext#*"ANSWER: "}
    local resultdnstext=${resultdnstext%", AUTHORITY:"*}
    if [ "$resultdnstext" == "0" ] || [ "$resultdnstext" == "1" ] || [ "$resultdnstext" == "2" ]; then
        echo 0
    else
        echo 1
    fi
}
function Check_DNS_3() {
    local resultdnstext=$(dig "test$RANDOM$RANDOM.$1" | grep "ANSWER:")
    echo "test$RANDOM$RANDOM.$1"
    local resultdnstext=${resultdnstext#*"ANSWER: "}
    local resultdnstext=${resultdnstext%", AUTHORITY:"*}
    if [ "$resultdnstext" == "0" ]; then
        echo 1
    else
        echo 0
    fi
}
function Get_Unlock_Type() {
    while [ $# -ne 0 ]; do
        if [ "$1" = "0" ]; then
            echo "${smedia[dns]}"
            return
        fi
        shift
    done
    echo "${smedia[native]}"
}

# 通用媒体解锁检测模板
function MediaUnlockTest_Template() {
    local service="$1"          # 服务名，如 TikTok
    local url="$2"              # 检测 URL
    local curl_method="${3:-GET}"   # 请求方式，默认 GET
    local extra_curl_args="${4:-}"  # curl 额外参数
    local parse_region_cmd="$5"     # 用于解析区域的命令（awk/grep/jq 等）
    local media_array_name="${6}"   # 存放结果的数组名

    local temp_info="$Font_Cyan$Font_B${sinfo[media]}${Font_I}$service $Font_Suffix"
    ((ibar_step += 3))
    show_progress_bar "$temp_info" $((40 - 8 - ${sinfo[lmedia]})) &
    bar_pid="$!" && disown "$bar_pid"
    trap "kill_progress_bar" RETURN

    # 初始化数组
    eval "$media_array_name=()"

    # DNS 检测
    local result1=$(Check_DNS_1 "$url")
    local result2=$(Check_DNS_2 "$url")
    local result3=$(Check_DNS_3 "$url")
    local unlock_type=$(Get_Unlock_Type "$result1" "$result2" "$result3")

    # curl 请求
    local tmpresult=$(curl $CurlARG -$curl_method --user-agent "$UA_Browser" -sSL --max-time 10 $extra_curl_args "$url" 2>&1)

    # 检查 curl 是否失败
    if [[ $tmpresult == "curl"* ]]; then
        eval "$media_array_name[ustatus]='${smedia[bad]}'"
        eval "$media_array_name[uregion]='${smedia[nodata]}'"
        eval "$media_array_name[utype]='${smedia[nodata]}'"
        return
    fi

    # 解析区域信息
    local region=""
    if [ -n "$parse_region_cmd" ]; then
        region=$(eval "$parse_region_cmd")
    fi

    # 设置解锁状态
    if [ -n "$region" ]; then
        eval "$media_array_name[ustatus]='${smedia[yes]}'"
        eval "$media_array_name[uregion]='  [$region]   '"
        eval "$media_array_name[utype]='$unlock_type'"
    else
        eval "$media_array_name[ustatus]='${smedia[no]}'"
        eval "$media_array_name[uregion]='${smedia[nodata]}'"
        eval "$media_array_name[utype]='${smedia[nodata]}'"
    fi
}




OpenAITest() {
    local temp_info="$Font_Cyan$Font_B${sinfo[ai]}${Font_I}ChatGPT $Font_Suffix"
    ((ibar_step += 3))
    show_progress_bar "$temp_info" $((40 - 8 - ${sinfo[lai]})) &
    local bar_pid="$!" && disown "$bar_pid"
    trap "kill_progress_bar" RETURN

    chatgpt=()

    # 并发 DNS 检测
    dns_hosts=( "chat.openai.com" "ios.chat.openai.com" "api.openai.com" )
    declare -A dns_results
    for host in "${dns_hosts[@]}"; do
        {
            r1=$(Check_DNS_1 $host)
            r2=$(Check_DNS_2 $host)
            r3=$(Check_DNS_3 $host)
            echo "$host|$r1|$r2|$r3"
        } &
    done | while IFS='|' read -r h r1 r2 r3; do
        dns_results[$h]="$r1 $r2 $r3"
    done
    wait

    # 并发 curl 请求
    declare -A curl_results
    {
        tmp1=$(curl $CurlARG -$1 -sS --max-time 10 'https://api.openai.com/compliance/cookie_requirements' \
            -H 'authorization: Bearer null' ... 2>&1)
        echo "api.openai.com|$tmp1"
    } &
    {
        tmp2=$(curl $CurlARG -$1 -sS --max-time 10 'https://ios.chat.openai.com/' ... 2>&1)
        echo "ios.chat.openai.com|$tmp2"
    } &
    wait | while IFS='|' read -r host val; do
        curl_results[$host]="$val"
    done

    # 获取国家码
    countryCode="$(curl $CurlARG --max-time 10 -sS https://chat.openai.com/cdn-cgi/trace 2>&1 | grep "loc=" | awk -F= '{print $2}')"

    # 判断解锁状态函数
    determine_status() {
        local tmp1=$1 tmp2=$2 country=$3 unlock_type=$4
        local ustatus uregion utype
        if [[ -z "$tmp1" && -z "$tmp2" ]]; then
            ustatus="${smedia[yes]}"
            uregion="  [$country]   "
            utype="$unlock_type"
        elif [[ -n "$tmp1" && -n "$tmp2" ]]; then
            ustatus="${smedia[no]}"
            uregion="${smedia[nodata]}"
            utype="${smedia[nodata]}"
        elif [[ -z "$tmp1" && -n "$tmp2" ]]; then
            ustatus="${smedia[web]}"
            uregion="  [$country]   "
            utype="$unlock_type"
        else
            ustatus="${smedia[app]}"
            uregion="  [$country]   "
            utype="$unlock_type"
        fi
        echo "$ustatus|$uregion|$utype"
    }

    # 得到 unlock_type
    local resultunlocktype
    resultunlocktype=$(Get_Unlock_Type \
        ${dns_results["chat.openai.com"]} \
        ${dns_results["ios.chat.openai.com"]} \
        ${dns_results["api.openai.com"]})

    # 状态判断
    local tmp1="${curl_results["api.openai.com"]}"
    local tmp2="${curl_results["ios.chat.openai.com"]}"
    IFS='|' read -r ustatus uregion utype <<< "$(determine_status "$tmp1" "$tmp2" "$countryCode" "$resultunlocktype")"

    chatgpt[ustatus]="$ustatus"
    chatgpt[uregion]="$uregion"
    chatgpt[utype]="$utype"
}

check_email_service_parallel() {
    local services=( "Gmail" "Outlook" "Yahoo" "Apple" "MailRU" "AOL" "GMX" "MailCOM" "163" "Sohu" "Sina" "QQ" )
    local port=25
    local expected_response="220"
    smail[remote]=0

    for service in "${services[@]}"; do
        (
            local domain host response success="false"
            case $service in
            "Gmail") domain="gmail.com" ;;
            "Outlook") domain="outlook.com" ;;
            "Yahoo") domain="yahoo.com" ;;
            "Apple") domain="me.com" ;;
            "MailRU") domain="mail.ru" ;;
            "AOL") domain="aol.com" ;;
            "GMX") domain="gmx.com" ;;
            "MailCOM") domain="mail.com" ;;
            "163") domain="163.com" ;;
            "Sohu") domain="sohu.com" ;;
            "Sina") domain="sina.com" ;;
            "QQ") domain="qq.com" ;;
            *) return ;;
            esac

            local mx_hosts=($(dig +short MX $domain | sort -n | awk '{print $2}'))
            for host in "${mx_hosts[@]}"; do
                response=$(timeout 5 bash -c "echo -e 'QUIT\r\n' | nc -s $IP -w4 $host $port 2>&1")
                smail_response[$service]=$response
                if [[ $response == *"$expected_response"* ]]; then
                    success="true"
                    smail[$service]="$Font_Black+$Font_Suffix$Back_Green$Font_White$Font_B$service$Font_Suffix"
                    smailstatus[$service]="true"
                    smail[remote]=1
                    break
                fi
            done

            if [[ $success == "false" ]]; then
                smail[$service]="$Font_Black-$Font_Suffix$Back_Red$Font_White$Font_B$service$Font_Suffix"
                smailstatus[$service]="false"
            fi
        ) &
    done
    wait
}


check_mail() {
    # 本地 SMTP 检查
    ss -tano | grep -q ":25\b" && smail[local]=2 || smail[local]=0
    if [[ ${smail[local]} -ne 2 && -z $usePROXY ]]; then
        local response=$(timeout 10 bash -c "echo -e 'QUIT\r\n' | nc -s $IP -p25 -w9 smtp.mailgun.org 25 2>&1")
        [[ $response == *"220"* ]] && smail[local]=1
    fi
    [[ -n $usePROXY ]] && smail[local]=0

    # 远程邮件服务检查
    smail[remote]=0
    services=("Gmail" "Outlook" "Yahoo" "Apple" "QQ" "MailRU" "AOL" "GMX" "MailCOM" "163" "Sohu" "Sina")
    local tmp_file=$(mktemp)

    check_one_service() {
        local service=$1
        check_email_service "$service"
        echo "$service" >> "$tmp_file"
    }

    local parallel_jobs=5
    local count=0
    for service in "${services[@]}"; do
        check_one_service "$service" &
        ((count++))
        if (( count % parallel_jobs == 0 )); then
            wait
        fi
    done
    wait
    smail[remote]=$(wc -l < "$tmp_file")
    rm -f "$tmp_file"

    # 统一进度条显示
    show_progress_bar "$Font_Cyan$Font_B${sinfo[mail]}$Font_Suffix Done" 40
}


check_dnsbl_parallel() {
    local ip_to_check=$1
    local parallel_jobs=$2
    local reversed_ip=$(echo "$ip_to_check" | awk -F. '{print $4"."$3"."$2"."$1}')

    # 初始化计数
    smail[t]=0
    smail[c]=0
    smail[m]=0
    smail[b]=0

    # 下载 DNSBL 列表
    mapfile -t dnsbl_list < <(curl $CurlARG -sL "${rawgithub}main/ref/dnsbl.list" | sort -u)

    # 创建一个临时文件存放结果
    local tmp_file
    tmp_file=$(mktemp)

    # 并发函数
    check_one() {
        local bl=$1
        local res=$(dig +short "${reversed_ip}.${bl}" A)
        if [[ -z $res ]]; then
            echo "Clean"
        elif [[ $res == 127.0.0.2 ]]; then
            echo "Blacklisted"
        else
            echo "Other"
        fi >> "$tmp_file"
    }

    # 控制并发
    local count=0
    for bl in "${dnsbl_list[@]}"; do
        check_one "$bl" &
        ((count++))
        if ((count % parallel_jobs == 0)); then
            wait
        fi
    done
    wait  # 等待剩下的

    # 汇总结果
    mapfile -t results < "$tmp_file"
    rm -f "$tmp_file"

    smail[t]=${#results[@]}
    smail[c]=$(printf '%s\n' "${results[@]}" | grep -c "^Clean$")
    smail[b]=$(printf '%s\n' "${results[@]}" | grep -c "^Blacklisted$")
    smail[m]=$((smail[t] - smail[c] - smail[b]))

    echo "${smail[t]} ${smail[c]} ${smail[m]} ${smail[b]}"
}


show_head() {
    echo -ne "\r$(printf '%72s' | tr ' ' '#')\n"

    if [ $fullIP -eq 1 ]; then
        calc_padding "$(printf '%*s' "${shead[ltitle]}" '')$IP" 72
        echo -ne "\r$PADDING$Font_B${shead[title]}$Font_Cyan$IP$Font_Suffix\n"
    else
        calc_padding "$(printf '%*s' "${shead[ltitle]}" '')$IPhide" 72
        echo -ne "\r$PADDING$Font_B${shead[title]}$Font_Cyan$IPhide$Font_Suffix\n"
    fi

    calc_padding "${shead[git]}" 72
    echo -ne "\r$PADDING$Font_U${shead[git]}$Font_Suffix\n"

    calc_padding "${shead[bash]}" 72
    echo -ne "\r$PADDING${shead[bash]}\n"

    echo -ne "\r${shead[ptime]}${shead[time]}  ${shead[ver]}\n"
    echo -ne "\r$(printf '%72s' | tr ' ' '#')\n"
}

show_basic() {
    echo -ne "\r${sbasic[title]}\n"

    if [[ -n ${maxmind[asn]} && ${maxmind[asn]} != "null" ]]; then
        echo -ne "\r$Font_Cyan${sbasic[asn]}${Font_Green}AS${maxmind[asn]}$Font_Suffix\n"
        echo -ne "\r$Font_Cyan${sbasic[org]}$Font_Green${maxmind[org]}$Font_Suffix\n"
    else
        echo -ne "\r$Font_Cyan${sbasic[asn]}${sbasic[noasn]}$Font_Suffix\n"
    fi

    if [[ ${maxmind[dms]} != "null" && ${maxmind[map]} != "null" ]]; then
        echo -ne "\r$Font_Cyan${sbasic[location]}$Font_Green${maxmind[dms]}$Font_Suffix\n"
        echo -ne "\r$Font_Cyan${sbasic[map]}$Font_U$Font_Green${maxmind[map]}$Font_Suffix\n"
    fi

    local city_info=""
    [[ -n ${maxmind[sub]} && ${maxmind[sub]} != "null" ]] && city_info+="${maxmind[sub]}"
    [[ -n ${maxmind[city]} && ${maxmind[city]} != "null" ]] && city_info+=", ${maxmind[city]}"
    [[ -n ${maxmind[post]} && ${maxmind[post]} != "null" ]] && city_info+=", ${maxmind[post]}"

    [[ -n $city_info ]] && echo -ne "\r$Font_Cyan${sbasic[city]}$Font_Green$city_info$Font_Suffix\n"

    if [[ -n ${maxmind[countrycode]} && ${maxmind[countrycode]} != "null" ]]; then
        echo -ne "\r$Font_Cyan${sbasic[country]}$Font_Green[${maxmind[countrycode]}]${maxmind[country]}$Font_Suffix"
        [[ -n ${maxmind[continentcode]} && ${maxmind[continentcode]} != "null" ]] && echo -ne "$Font_Green, [${maxmind[continentcode]}]${maxmind[continent]}$Font_Suffix\n" || echo -ne "\n"
    elif [[ -n ${maxmind[continentcode]} && ${maxmind[continentcode]} != "null" ]]; then
        echo -ne "\r$Font_Cyan${sbasic[continent]}$Font_Green[${maxmind[continentcode]}]${maxmind[continent]}$Font_Suffix\n"
    fi

    [[ -n ${maxmind[regcountrycode]} && ${maxmind[regcountrycode]} != "null" ]] && echo -ne "\r$Font_Cyan${sbasic[regcountry]}$Font_Green[${maxmind[regcountrycode]}]${maxmind[regcountry]}$Font_Suffix\n"
    [[ -n ${maxmind[timezone]} && ${maxmind[timezone]} != "null" ]] && echo -ne "\r$Font_Cyan${sbasic[timezone]}$Font_Green${maxmind[timezone]}$Font_Suffix\n"

    if [[ -n ${maxmind[countrycode]} && ${maxmind[countrycode]} != "null" ]]; then
        if [ "${maxmind[countrycode]}" == "${maxmind[regcountrycode]}" ]; then
            echo -ne "\r$Font_Cyan${sbasic[type]}$Back_Green$Font_B$Font_White${sbasic[type0]}$Font_Suffix\n"
        else
            echo -ne "\r$Font_Cyan${sbasic[type]}$Back_Red$Font_B$Font_White${sbasic[type1]}$Font_Suffix\n"
        fi
    fi
}

show_type() {
    echo -ne "\r${stype[title]}\n"
    echo -ne "\r$Font_Cyan${stype[db]}$Font_I   IPinfo    ipregistry    ipapi    IP2Location   AbuseIPDB $Font_Suffix\n"
    echo -ne "\r$Font_Cyan${stype[usetype]}$Font_Suffix${ipinfo[susetype]}${ipregistry[susetype]}${ipapi[susetype]}${ip2location[susetype]}${abuseipdb[susetype]}\n"
    echo -ne "\r$Font_Cyan${stype[comtype]}$Font_Suffix${ipinfo[scomtype]}${ipregistry[scomtype]}${ipapi[scomtype]}${ip2location[scomtype]}\n"
}


show_score() {
    echo -ne "\r${sscore[title]}\n"
    echo -ne "\r${sscore[range]}\n"

    # 定义数据源数组
    local sources=(ip2location scamalytics ipapi)
    [[ $mode_lite -eq 0 ]] && sources+=(abuseipdb ipqs)
    sources+=(dbip)

    for s in "${sources[@]}"; do
        # 跳过空分数或 null
        [[ -z ${!s[score]} || ${!s[score]} == "null" ]] && continue

        # 处理 ipapi 特殊计算
        local score_val=${!s[score]}
        if [[ $s == "ipapi" ]]; then
            score_val=$(echo "${ipapi[scorenum]} * 10000 / 1" | bc)
            sscore_text "${!s[score]}" "$score_val" 85 300 10000 7
        elif [[ $s == "abuseipdb" ]]; then
            sscore_text "${!s[score]}" "${!s[score]}" 25 25 100 11
        elif [[ $s == "ipqs" ]]; then
            sscore_text "${!s[score]}" "${!s[score]}" 75 85 100 6
        else
            sscore_text "${!s[score]}" "${!s[score]}" 33 66 100 13
        fi

        echo -ne "\r${Font_Cyan}${s}${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${!s[risk]}\n"
    done
}


format_factor() {
    local tmp_txt="  "
    local vals=("$@")
    local max=${#vals[@]}

    for ((i=0; i<max; i++)); do
        local v="${vals[i]}"
        if [[ $v == "true" ]]; then
            tmp_txt+="${sfactor[yes]}"
        elif [[ $v == "false" ]]; then
            tmp_txt+="${sfactor[no]}"
        elif [ ${#v} -eq 2 ]; then
            tmp_txt+="$Font_Green[$v]$Font_Suffix"
        else
            tmp_txt+="${sfactor[na]}"
        fi

        # 除了最后一个，每个之间加间隔
        if [[ $i -lt $((max - 1)) ]]; then
            tmp_txt+="    "
        fi
    done

    echo "$tmp_txt"
}


show_factor() {
    local sources=(ip2location ipapi ipregistry ipqs scamalytics ipdata ipinfo ipwhois)
    local factors=(countrycode proxy tor vpn server abuser robot)
    echo -e "${sfactor[title]}"
    echo -e "$Font_Cyan${sfactor[factor]}$Font_I IP2Location ipapi ipregistry IPQS Scamalytics ipdata IPinfo IPWHOIS$Font_Suffix"

    for f in "${factors[@]}"; do
        local tmp=()
        for s in "${sources[@]}"; do
            tmp+=("${!s[$f]}")   # 动态取数组元素
        done
        echo -e "$Font_Cyan${sfactor[$f]}$Font_Suffix$(format_factor "${tmp[@]}")"
    done
}



show_media() {
    local services=("tiktok" "disney" "netflix" "youtube" "amazon" "spotify" "chatgpt")
    echo -e "${smedia[title]}"
    echo -e "$Font_Cyan${smedia[meida]}$Font_I TikTok   Disney+  Netflix Youtube  AmazonPV  Spotify  ChatGPT $Font_Suffix"
    
    for field in status region type; do
        line="$Font_Cyan${smedia[$field]}"
        for svc in "${services[@]}"; do
            line+="${!svc[$field]}"
        done
        line+="$Font_Suffix"
        echo -e "$line"
    done
}

show_mail() {
    echo -e "${smail[title]}"

    case ${smail[local]} in
        1) echo -e "$Font_Cyan${smail[port]}$Font_Suffix${smail[yes]}" ;;
        2) echo -e "$Font_Cyan${smail[port]}$Font_Suffix${smail[occupied]}" ;;
        *) echo -e "$Font_Cyan${smail[port]}$Font_Suffix${smail[no]}" ;;
    esac

    if [ ${smail[remote]} -eq 1 ]; then
        echo -n "$Font_Cyan${smail[provider]}$Font_Suffix"
        for service in "${services[@]}"; do
            echo -n "${smail[$service]}"
        done
        echo
    else
        echo -e "$Font_Cyan${smail[provider]}${smail[blocked]}$Font_Suffix"
    fi

    [[ $1 -eq 4 ]] && echo -e "${smail[sdnsbl]}"
}

show_tail() {
    printf '=%.0s' {1..72}; echo
    echo -e "$Font_I${stail[stoday]}${stail[today]}${stail[stotal]}${stail[total]}${stail[thanks]} $Font_Suffix"
    echo
}

get_opts() {
    while getopts "i:l:o:x:fhjnpyEM46" opt; do
        case $opt in
            4) [[ $IPV4check -ne 0 ]] && IPV6check=0 || ERRORcode=4 ;;
            6) [[ $IPV6check -ne 0 ]] && IPV4check=0 || ERRORcode=6 ;;
            f) fullIP=1 ;;
            h) show_help ;;
            i) 
                iface="$OPTARG"
                useNIC=" --interface $iface"
                CurlARG+="$useNIC"
                get_ipv4
                get_ipv6
                is_valid_ipv4 "$IPV4"
                is_valid_ipv6 "$IPV6"
                [[ $IPV4work -eq 0 && $IPV6work -eq 0 ]] && ERRORcode=7
                ;;
            j) mode_json=1 ;;
            l) YY="${OPTARG,,}" ;;  # 转小写
            n) mode_no=1 ;;
            o) 
                mode_output=1
                outputfile="$OPTARG"
                [[ -z $outputfile ]] && { ERRORcode=1; break; }
                [[ -e $outputfile ]] && { ERRORcode=10; break; }
                touch "$outputfile" 2>/dev/null || { ERRORcode=11; break; }
                ;;
            p) mode_privacy=1 ;;
            x)
                xproxy="$OPTARG"
                usePROXY=" -x $xproxy"
                CurlARG+="$usePROXY"
                get_ipv4
                get_ipv6
                is_valid_ipv4 "$IPV4"
                is_valid_ipv6 "$IPV6"
                [[ $IPV4work -eq 0 && $IPV6work -eq 0 ]] && ERRORcode=8
                ;;
            y) mode_yes=1 ;;
            E) YY="en" ;;
            M) mode_menu=1 ;;
            \?) ERRORcode=1 ;;
        esac
    done

    if [[ $mode_menu -eq 1 ]]; then
        [[ $YY == "cn" ]] && eval "bash <(curl -sL https://Check.Place) -I" \
                             || eval "bash <(curl -sL https://Check.Place) -EI"
        exit 0
    fi

    [[ $IPV4check -eq 1 && $IPV6check -eq 0 && $IPV4work -eq 0 ]] && ERRORcode=40
    [[ $IPV4check -eq 0 && $IPV6check -eq 1 && $IPV6work -eq 0 ]] && ERRORcode=60
    CurlARG="$useNIC$usePROXY"
}


show_help() {
    echo -ne "\r$shelp\n"
    exit 0
}

read_ref() {
    # 获取 cookie
    Media_Cookie=$(curl "$CurlARG" -sL --retry 3 --max-time 10 "${rawgithub}main/ref/cookies.txt")
    IATA_Database="${rawgithub}main/ref/iata-icao.csv"
}

clean_ansi() {
    local input="$1"
    # 直接用 bash 的内建替换，减少管道
    input="${input//$'\033'/}"
    # 移除 ANSI 转义序列
    input="${input//$'\e['*[0-9;]*[mK]/}"
    # 去掉首尾空白
    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"
    echo -n "$input"
}

factor_bool() {
    local val="$1" src="$2" key="$3"
    case "$val" in
        true)  echo ".Factor |= map(. * { $key: { $src: true } }) | " ;;
        false) echo ".Factor |= map(. * { $key: { $src: false } }) | " ;;
        ??)    echo ".Factor |= map(. * { $key: { $src: \"$val\" } }) | " ;; # 两字符情况
        *)     echo ".Factor |= map(. * { $key: { $src: null } }) | " ;;
    esac
}


save_json() {
    declare -A sections=(
        [Head]="IP Command GitHub Time Version"
        [Info]="ASN Organization Latitude Longitude DMS Map TimeZone CityName CityPostal CitySubCode CitySubdivisions RegionCode RegionName ContinentCode ContinentName RegisteredRegionCode RegisteredRegionName Type"
        [Type]="IPinfo ipregistry ipapi AbuseIPDB IP2LOCATION CompanyIPinfo Companyipregistry Companyipapi"
        [Score]="IP2LOCATION SCAMALYTICS ipapi AbuseIPDB IPQS DBIP"
        [Factor]="CountryCode Proxy Tor VPN Server Abuser Robot"
        [Media]="TikTok DisneyPlus Netflix Youtube AmazonPrimeVideo Spotify ChatGPT"
        [Mail]="Port25 Services DNSBlacklist"
    )

    # 根据 mode_lite 或 fullIP 设置 IP
    local actual_ip="${fullIP:-0}" 
    actual_ip=$([[ $fullIP -eq 1 ]] && echo "${IP:-null}" || echo "${IPhide:-null}")

    # jq 拼接函数
    jq_set() {
        local section=$1 key=$2 value=$3 type=${4:-string}
        case "$type" in
            string) echo ".${section} |= map(. + { $key: \"${value:-null}\" }) | " ;;
            object) echo ".${section} |= map(. * ${value}) | " ;;
            boolean) echo ".${section} |= map(. + { $key: ${value:-false} }) | " ;;
        esac
    }

    local jq_cmd=""

    # Head
    for key in IP Command GitHub Time Version; do
        case $key in
            IP) jq_cmd+=$(jq_set Head "$key" "$actual_ip") ;;
            Command) jq_cmd+=$(jq_set Head "$key" "${shead[bash]:-null}") ;;
            GitHub) jq_cmd+=$(jq_set Head "$key" "${shead[git]:-null}") ;;
            Time) jq_cmd+=$(jq_set Head "$key" "${shead[time]:-null}") ;;
            Version) jq_cmd+=$(jq_set Head "$key" "${shead[ver]:-null}") ;;
        esac
    done

    # Info
    local info_source
    info_source=$([[ $mode_lite -eq 0 ]] && echo "maxmind" || echo "ipinfo")
    for field in ASN Organization Latitude Longitude DMS Map TimeZone; do
        jq_cmd+=$(jq_set Info "$field" "${!info_source[$field,,]:-null}")  # 通过小写 key 对应数组
    done
    # City / Region / Continent / RegisteredRegion
    jq_cmd+=$(jq_set Info "City" "{ Name: \"${!info_source[city]:-null}\", PostalCode: \"${!info_source[post]:-null}\", SubCode: \"${!info_source[subcode]:-null}\", Subdivisions: \"${!info_source[sub]:-null}\" }" object)
    jq_cmd+=$(jq_set Info "Region" "{ Code: \"${!info_source[countrycode]:-null}\", Name: \"${!info_source[country]:-null}\" }" object)
    jq_cmd+=$(jq_set Info "Continent" "{ Code: \"${!info_source[continentcode]:-null}\", Name: \"${!info_source[continent]:-null}\" }" object)
    jq_cmd+=$(jq_set Info "RegisteredRegion" "{ Code: \"${!info_source[regcountrycode]:-null}\", Name: \"${!info_source[regcountry]:-null}\" }" object)
    # Type
    local type_val="null"
    [[ -n ${!info_source[countrycode]} && ${!info_source[countrycode]} != "null" ]] && \
        type_val=$([[ "${!info_source[countrycode]}" == "${!info_source[regcountrycode]}" ]] && echo "${sbasic[type0]:-null}" || echo "${sbasic[type1]:-null}")
    jq_cmd+=$(jq_set Info "Type" "$type_val")

    # Type Usage / Company
    local type_services=(IPinfo ipregistry ipapi AbuseIPDB IP2LOCATION)
    for svc in "${type_services[@]}"; do
        jq_cmd+=$(jq_set Type "Usage" "$(clean_ansi "${!svc[susetype]:-null}")") 
        jq_cmd+=$(jq_set Type "Company" "$(clean_ansi "${!svc[scomtype]:-null}")")
    done

    # Score
    local score_services=(IP2LOCATION SCAMALYTICS ipapi AbuseIPDB IPQS DBIP)
    for svc in "${score_services[@]}"; do
        jq_cmd+=$(jq_set Score "$svc" "${!svc[score]:-null}")
    done

    # Factor
    local factor_keys=(CountryCode Proxy Tor VPN Server Abuser Robot)
    local factor_sources=(ip2location ipapi ipregistry ipqs scamalytics ipdata ipinfo ipwhois dbip)
    for key in "${factor_keys[@]}"; do
        for src in "${factor_sources[@]}"; do
            jq_cmd+=$(factor_bool "${!src[$key]}" "${src^^}" "$key")
        done
    done

    # Media
    local media_keys=(TikTok DisneyPlus Netflix Youtube AmazonPrimeVideo Spotify ChatGPT)
    for key in "${media_keys[@]}"; do
        jq_cmd+=$(jq_set Media "$key" "{ Status: \"$(clean_ansi "${!key[ustatus]:-null}")\", Region: \"$(clean_ansi "${!key[uregion]//[][]/}")\", Type: \"$(clean_ansi "${!key[utype]:-null}")\" }" object)
    done

    # Mail
    local port25_val=false
    [[ ${smail[local]} -eq 1 ]] && port25_val=true
    [[ ${smail[local]} -eq 2 ]] && port25_val=null
    jq_cmd+=$(jq_set Mail "Port25" "$port25_val" boolean)
    for svc in "${services[@]}"; do
        local val=false
        [[ ${smail[local]} -eq 1 && ${smailstatus[$svc]} == "true" ]] && val=true
        [[ ${smail[local]} -eq 2 ]] && val=null
        jq_cmd+=$(jq_set Mail "$svc" "$val" boolean)
    done
    jq_cmd+=$(jq_set Mail "DNSBlacklist" "{ Total: ${smail[t]:-null}, Clean: ${smail[c]:-null}, Marked: ${smail[m]:-null}, Blacklisted: ${smail[b]:-null} }" object)

    # 最终 jq 执行
    ipjson=$(echo "$ipjson" | jq "$jq_cmd.")
}


check_IP() {
    IP=$1
    ipjson='{
      "Head": [{}],
      "Info": [{}],
      "Type": [{}],
      "Score": [{}],
      "Factor": [{}],
      "Media": [{}],
      "Mail": [{}]
    }'

    [[ $2 -eq 4 ]] && hide_ipv4 $IP
    [[ $2 -eq 6 ]] && hide_ipv6 $IP

    countRunTimes
    db_maxmind $2
    db_ipinfo
    [[ $mode_lite -eq 0 ]] && db_scamalytics $2 || scamalytics=()
    [[ $mode_lite -eq 0 ]] && db_ipregistry $2 || ipregistry=()
    db_ipapi
    [[ $mode_lite -eq 0 ]] && db_abuseipdb $2 || abuseipdb=()
    [[ $mode_lite -eq 0 ]] && db_ip2location $2 || ip2location=()
    db_dbip
    db_ipwhois $2
    [[ $mode_lite -eq 0 ]] && db_ipdata $2 || ipdata=()
    [[ $mode_lite -eq 0 ]] && db_ipqs $2 || ipqs=()
    MediaUnlockTest_Template "tiktok" "https://www.tiktok.com/" "GET" "" "echo \$tmpresult | jq -r '.region'" tiktok
    MediaUnlockTest_Template "disney" "https://disney.api.edge.bamgrid.com/devices" "POST" '{"deviceFamily":"browser"}' "echo \$tmpresult | jq -r '.extensions.sdk.session.location.countryCode'" disney
    MediaUnlockTest_Template "netflix" "https://www.netflix.com/title/81280792" "GET" "" "echo \$tmpresult | grep -o 'data-country=\"[A-Z]*\"' | sed 's/.*=\"\([A-Z]*\)\"/\1/' | head -n1" netflix
    MediaUnlockTest_Template "youtube" "https://www.youtube.com/premium" "GET" "" "echo \$tmpresult | jq -r '.contentRegion'" youtube
    MediaUnlockTest_Template "amazon" "https://www.primevideo.com" "GET" "" "echo \$tmpresult | jq -r '.currentTerritory'" amazon
    MediaUnlockTest_Template "spotify" "https://spclient.wg.spotify.com/signup/public/v1/account" "POST" "birth_day=11&birth_month=11&birth_year=2000..." "echo \$tmpresult | jq -r '.country'" spotify
    OpenAITest $2
    check_mail


    [[ $2 -eq 4 ]] && check_dnsbl "$IP" 50

    # 去掉广告相关逻辑，不再使用 ADLines
    echo -ne "$Font_LineClear" 1>&2

    # 构建报告

    local ip_report=$(
        show_head
        show_basic
        show_type
        show_score
        show_factor
        show_media
        show_mail $2
        show_tail
        )


    local report_link=""
    [[ mode_json -eq 1 || mode_output -eq 1 || mode_privacy -eq 0 ]] && save_json
    [[ $mode_lite -eq 0 && mode_privacy -eq 0 ]] && report_link=$(curl -$2 -s -X POST https://upload.check.place -d "type=ip" --data-urlencode "json=$ipjson" --data-urlencode "content=$ip_report")
    [[ mode_json -eq 0 ]] && echo -ne "\r$ip_report\n"
    [[ mode_json -eq 0 && mode_privacy -eq 0 && $report_link == *"https://Report.Check.Place/"* ]] && echo -ne "\r${stail[link]}$report_link$Font_Suffix\n"
    [[ mode_json -eq 1 ]] && echo -ne "\r$ipjson\n"
    echo -ne "\r\n"

    if [[ mode_output -eq 1 ]]; then
        case "$outputfile" in
        *.[aA][nN][sS][iI])
            echo "$ip_report" >>"$outputfile" 2>/dev/null
            ;;
        *.[jJ][sS][oO][nN])
            echo "$ipjson" >>"$outputfile" 2>/dev/null
            ;;
        *) echo -e "$ip_report" | sed 's/\x1b\[[0-9;]*[mGKHF]//g' >>"$outputfile" 2>/dev/null ;;
        esac
    fi
}


generate_random_user_agent
adapt_locale
check_connectivity
read_ref
get_ipv4
get_ipv6
is_valid_ipv4 $IPV4
is_valid_ipv6 $IPV6
get_opts "$@"
[[ mode_no -eq 0 ]] && install_dependencies
set_language
if [[ $ERRORcode -ne 0 ]]; then
    echo -ne "\r$Font_B$Font_Red${swarn[$ERRORcode]}$Font_Suffix\n"
    exit $ERRORcode
fi
clear

[[ $IPV4work -ne 0 && $IPV4check -ne 0 ]] && check_IP "$IPV4" 4
[[ $IPV6work -ne 0 && $IPV6check -ne 0 ]] && check_IP "$IPV6" 6
