#!/bin/bash
# MoFox部署脚本 2525.10.25
set -euo pipefail

get_script_dir() {
    local source="${BASH_SOURCE[0]}"

    # 检查是否来自进程替换（如 bash <(curl ...)）
    if [[ "$source" == /dev/fd/* ]] || [[ ! -f "$source" ]]; then
        # 无法定位真实脚本文件，使用当前工作目录
        pwd
    else
        # 正常情况：解析脚本真实路径
        (cd "$(dirname "$source")" && pwd)
    fi
}

SCRIPT_DIR="$(get_script_dir)"
DEPLOY_DIR="$SCRIPT_DIR"

LOCAL_BIN="$HOME/.local/bin"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "DEPLOY_DIR: $DEPLOY_DIR"

# 检查是否为异常目录（如 /dev/fd、/proc/self/fd 等）
if [[ "$DEPLOY_DIR" == /dev/fd/* ]] || [[ "$DEPLOY_DIR" == /proc/self/fd/* ]] || [[ ! -d "$DEPLOY_DIR" ]]; then
    echo -e "\e[31m警告：检测到部署目录异常！可能因使用 'bash <(curl ...)' 导致路径错误。\e[0m"
    echo -e "\e[33m建议：将脚本下载到本地后运行，或确保当前目录可写。\e[0m"
else
    echo -e "\e[32m目录正常，可安全部署。\e[0m"
fi

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1 # 检查命令是否存在
}

# =============================================================================
# 日志函数
# =============================================================================
# 定义颜色
RESET='\033[0m'   # 重置颜色
BOLD='\033[1m'    # 加粗
RED='\033[31m'    # 红色
GREEN='\033[32m'  # 绿色
YELLOW='\033[33m' # 黄色
BLUE='\033[34m'   # 蓝色
CYAN='\033[36m'   # 青色

# 信息日志
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }

# 成功日志
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }

# 警告日志
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }

# 错误日志
err() {
    echo -e "${RED}[ERROR]${RESET} $1"
    exit 1
}

# 打印标题
print_title() { echo -e "${BOLD}${CYAN}=== $1 ===${RESET}"; }

download_with_retry() {  #定义函数
    local url="$1"       #获取参数
    local output="$2"    #获取参数
    local max_attempts=3 #最大尝试次数
    local attempt=1      #当前尝试次数

    while [[ $attempt -le $max_attempts ]]; do               #循环直到达到最大尝试次数
        info "下载尝试 $attempt/$max_attempts: $url"             #打印信息日志
        if command_exists wget; then                         #如果 wget 存在
            if wget -O "$output" "$url" 2>/dev/null; then    #使用 wget 下载
                ok "下载成功: $output"                           #打印日志
                return 0                                     #成功返回
            fi                                               #结束条件判断
        elif command_exists curl; then                       #如果 curl 存在
            if curl -L -o "$output" "$url" 2>/dev/null; then #使用 curl 下载
                ok "下载成功: $output"                           #打印日志
                return 0                                     #成功返回
            fi                                               #结束条件判断
        fi                                                   #结束条件判断
        warn "第 $attempt 次下载失败"                              #打印警告日志
        if [[ $attempt -lt $max_attempts ]]; then            #如果还没到最大尝试次数
            info "5秒后重试..."                                  #打印信息日志
            sleep 5                                          #等待 5 秒
        fi                                                   #结束条件判断
        ((attempt++))                                        #增加尝试次数
    done                                                     #结束循环
    err "所有下载尝试都失败了"                                         #打印错误日志并退出
}                                                            #结束函数定义

select_github_proxy() {
    print_title "选择 GitHub 代理"
    echo "请根据您的网络环境选择一个合适的下载代理："
    echo

    select proxy_choice in "ghfast.top 镜像 (推荐)" "ghproxy.net 镜像" "不使用代理" "自定义代理"; do
        case $proxy_choice in
        "ghfast.top 镜像 (推荐)")
            GITHUB_PROXY="https://ghfast.top/"
            ok "已选择: ghfast.top 镜像"
            break
            ;;
        "ghproxy.net 镜像")
            GITHUB_PROXY="https://ghproxy.net/"
            ok "已选择: ghproxy.net 镜像"
            break
            ;;
        "不使用代理")
            GITHUB_PROXY=""
            ok "已选择: 不使用代理"
            break
            ;;
        "自定义代理")
            read -rp "请输入自定义 GitHub 代理 URL (如 ghfast.top/ 或 https://ghfast.top/, 必须以斜杠 / 结尾): " custom_proxy

            # 自动加 https://（如果没有写协议）
            if [[ "$custom_proxy" != http*://* ]]; then
                custom_proxy="https://$custom_proxy"
                warn "代理 URL 没有写协议，已自动加 https://"
            fi

            # 自动添加结尾斜杠
            if [[ "$custom_proxy" != */ ]]; then
                custom_proxy="${custom_proxy}/"
                warn "代理 URL 没有以斜杠结尾，已自动添加斜杠"
            fi

            GITHUB_PROXY="$custom_proxy"
            ok "已选择: 自定义代理 - $GITHUB_PROXY"
            break
            ;;
        *)
            warn "无效输入，使用默认代理"
            GITHUB_PROXY="https://ghfast.top/"
            ok "已选择: ghfast.top 镜像 (默认)"
            break
            ;;
        esac
    done
}

check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        # 已经是root，不需要sudo
        SUDO=""
        ok "当前是 root 用户"
    elif command_exists sudo; then
        # 有sudo命令
        SUDO="sudo"
        ok "检测到 sudo 命令"
    else
        # 没有sudo
        SUDO=""
        warn "系统没有 sudo "
    fi
}

# =============================================================================
# 系统检测
# =============================================================================
detect_system() {        #定义函数
    print_title "检测系统环境" #打印标题
    ID="${ID:-}"
    # 检测架构
    ARCH=$(uname -m) #获取系统架构
    case $ARCH in    # 根据架构打印信息
    x86_64 | aarch64 | arm64)
        ok "系统架构: $ARCH (支持)" #打印信息
        ;;
    *)
        warn "架构 $ARCH 可能不被完全支持，继续尝试..." #打印警告
        ;;
    esac

    # 检测操作系统
    if [[ -f /etc/os-release ]]; then #如果文件存在
        source /etc/os-release        #加载文件
        ok "检测到系统: $NAME"             #打印信息
    else                              # 否则
        warn "无法检测具体系统版本"             #打印警告
    fi                                #结束条件判断

    # 检测包管理器
    check_sudo
    detect_package_manager
} #结束函数定义

# =============================================================================
# 包管理器检测
# =============================================================================
detect_package_manager() { #定义函数
    info "检测包管理器..."       #打印信息日志

    local managers=( #定义包管理器数组
        "apt:Debian/Ubuntu"
        "pacman:Arch Linux"
        "dnf:Fedora/RHEL/CentOS"
        "yum:RHEL/CentOS (老版本)"
        "zypper:openSUSE"
        "apk:Alpine Linux"
        "brew:macOS/Linux (Homebrew)"
    ) #结束数组定义

    for manager_info in "${managers[@]}"; do #循环遍历数组
        local manager="${manager_info%%:*}"  #提取包管理器名称
        local distro="${manager_info##*:}"   #提取发行版名称

        if command_exists "$manager"; then       #如果包管理器存在
            PKG_MANAGER="$manager"               #设置全局变量
            DISTRO="$distro"                     #设置全局变量
            ok "检测到包管理器: $PKG_MANAGER ($DISTRO)" #打印信息日志
            return 0                             #成功返回
        fi                                       #结束条件判断
    done                                         #结束循环

    err "未检测到支持的包管理器，请手动安装 git、curl/wget 和 python3" #打印错误日志并退出
}                                                   #结束函数定义

install_package() {    #定义函数
    local package="$1" #获取参数

    info "安装 $package..." #打印信息日志
    case $PKG_MANAGER in  #根据包管理器选择安装命令
    pacman)
        $SUDO pacman -S --noconfirm "$package" #安装包
        ;;
    apt)
        $SUDO apt update -qq 2>/dev/null || true #更新包列表
        $SUDO apt install -y "$package"          #安装包
        ;;
    dnf)
        # 如果是安装 screen，先确保 EPEL 已启用
        if [[ "$package" == "screen" ]]; then
            if ! dnf repolist enabled | grep -q epel; then
                info "启用 EPEL 仓库以安装 screen..."
                $SUDO dnf install -y epel-release 2>/dev/null || true
            fi
        fi
        $SUDO dnf install -y "$package" #安装包
        ;;
    yum)
        # 如果是安装 screen，先确保 EPEL 已启用
        if [[ "$package" == "screen" ]]; then
            if ! yum repolist enabled | grep -q epel; then
                info "启用 EPEL 仓库以安装 screen..."
                $SUDO yum install -y epel-release 2>/dev/null || true
            fi
        fi
        $SUDO yum install -y "$package" #安装包
        ;;
    zypper)
        $SUDO zypper install -y "$package" #安装包
        ;;
    apk)
        $SUDO apk add gcc musl-dev linux-headers "$package" #安装包
        ;;
    brew)
        $SUDO install "$package" #安装包
        ;;
    *)
        warn "未知包管理器 $PKG_MANAGER，请手动安装 $package" #打印警告
        ;;
    esac #结束条件判断
}        #结束函数定义

#------------------------------------------------------------------------------

# =============================================================================
# 系统依赖安装
# =============================================================================
install_system_dependencies() { #定义函数
    print_title "安装系统依赖"        #打印标题

    local packages=("git" "python3" "screen" "tar" "findutils" "zip") #定义必需包数组

    # 检查下载工具
    if ! command_exists curl && ! command_exists wget; then #如果 curl 和 wget 都不存在
        packages+=("curl")                                  #添加 curl 到数组
    fi                                                      #结束条件判断

    # Arch 系统特殊处理：添加 uv 到必需包数组
    if [[ "$ID" == "arch" ]]; then
        # 只有 Arch 才用包管理器安装 uv
        packages+=("uv")
        info "已将 uv 添加到 Arch 的必需安装包列表"
    fi
    if ! command_exists pip3 && ! command_exists pip; then #如果 pip3 和 pip 都不存在
        case $PKG_MANAGER in                               #根据包管理器选择 pip 包名称
        apt) packages+=("python3-pip") ;;                  # apt
        pacman) packages+=("python-pip") ;;                # pacman
        dnf | yum) packages+=("python3-pip") ;;            # dnf 和 yum
        zypper) packages+=("python3-pip") ;;               # zypper
        apk) packages+=("py3-pip") ;;                      # apk
        brew) packages+=("pip3") ;;                        # brew
        *) packages+=("python3-pip") ;;                    #默认
        esac                                               #结束条件判断
    fi
    # 检查 Python 开发包
    if ! command_exists python3-config; then
        case $PKG_MANAGER in
        apt) packages+=("python3-dev") ;;
        pacman) packages+=("python") ;;
        dnf | yum) packages+=("python3-devel") ;;
        zypper) packages+=("python3-devel") ;;
        apk) packages+=("python3-dev") ;;
        brew) ;;
        *) packages+=("python3-dev") ;;
        esac
    fi
    # 检查 gcc/g++ 是否存在，如果都不存在则安装
    if ! command_exists gcc || ! command_exists g++; then
        case $PKG_MANAGER in
        apt)
            packages+=("build-essential") # 包含 gcc g++ make 等
            ;;
        pacman)
            packages+=("base-devel") # Arch 基础开发包，包含 gcc g++
            ;;
        dnf | yum)
            packages+=("gcc" "gcc-c++" "make")
            ;;
        zypper)
            packages+=("gcc" "gcc-c++" "make")
            ;;
        apk)
            packages+=("build-base") # Alpine 包含 gcc g++ make
            ;;
        brew)
            packages+=("gcc")
            ;;
        *)
            echo "未知包管理器，请手动安装 gcc/g++"
            ;;
        esac
    fi

    info "安装必需的系统包..."                                        #打印信息日志
    for package in "${packages[@]}"; do                       #循环遍历包数组
        if command_exists "${package/python3-pip/pip3}"; then #如果包已安装
            ok "$package 已安装"                                 #打印信息日志
        else                                                  #否则
            install_package "$package"                        #安装包
        fi                                                    #结束条件判断
    done                                                      #结束循环

    ok "系统依赖安装完成" #打印成功日志
}                 #结束函数定义

install_uv_environment() {
    print_title "安装和配置 uv 环境"

    if command_exists uv; then
        ok "uv 已安装"
    else
        info "安装 uv..."
        bash <(curl -sSL "${GITHUB_PROXY}https://github.com/Astriora/Antlia/raw/refs/heads/main/Script/UV/uv_install.sh") --GITHUB-URL "$GITHUB_PROXY"
    fi
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
}

clone_MoFox_Bot() {
    local CLONE_URL="${GITHUB_PROXY}https://github.com/MoFox-Studio/MoFox_Bot.git" # 克隆源
    if [ -d "$DEPLOY_DIR/MoFox_Bot" ]; then                                        # 如果目录已存在
        warn "检测到 MoFox_Bot 文件夹已存在。是否删除重新克隆？(y/n)"                                 # 提示用户是否删除
        read -rp "请输入选择 (y/n, 默认n): " del_choice                                   # 询问用户是否删除
        del_choice=${del_choice:-n}                                                # 默认选择不删除
        if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then                # 如果用户选择删除
            rm -rf "$DEPLOY_DIR/MoFox_Bot"                                         # 删除MoFox_Bot目录
            ok "已删除 MoFox_Bot 文件夹。"                                                # 提示用户已删除
        else                                                                       # 如果用户选择不删除
            warn "跳过 MoFox_Bot 仓库克隆。"                                              # 提示用户跳过克隆
            return                                                                 # 结束函数
        fi                                                                         # 结束删除选择
    fi                                                                             # 如果目录不存在则继续克隆
    info "克隆 MoFox_Bot 仓库"                                                         # 提示用户开始克隆
    git clone --depth 1 "$CLONE_URL"                                               # 克隆仓库
}                                                                                  # 克隆 仓库结束

# 安装 Python 依赖
install_python_dependencies() {
    print_title "安装 Python 依赖"

    # 配置 uv 镜像源
    export UV_INDEX_URL="https://mirrors.ustc.edu.cn/pypi/simple/"
    mkdir -p ~/.cache/uv
    chown -R "$(whoami):$(whoami)" ~/.cache/uv

    # 安装 MoFox_Bot 依赖
    cd "$DEPLOY_DIR/MoFox_Bot" || err "无法进入 MoFox_Bot 目录"
    info "同步 MoFox_Bot 依赖..."

    attempt=1
    while [[ $attempt -le 3 ]]; do
        if uv sync --index-url "$UV_INDEX_URL"; then
            ok "uv sync 成功"
            break
        else
            warn "uv sync 失败,重试 $attempt/3"
            ((attempt++))
            sleep 5
        fi
    done

    if [[ $attempt -gt 3 ]]; then
        err "uv sync 多次失败"
    fi

    # 配置 MoFox_Bot
    info "配置 MoFox_Bot..."
    mkdir -p config
    ok "已创建 config 文件夹"

    # 复制配置文件
    # 复制 .env
    if [[ -f "template/template.env" ]]; then
        cp "template/template.env" ".env"
        # 自动同意 EULA
        sed -i 's/^EULA_CONFIRMED=false/EULA_CONFIRMED=true/' .env
        ok "已复制 .env 并自动同意 EULA"
    else
        warn "未找到 template/template.env"
    fi

    if [[ -f "template/model_config_template.toml" ]]; then
        cp "template/model_config_template.toml" "config/model_config.toml"
        ok "已复制 model_config.toml"
    else
        warn "未找到 template/model_config_template.toml"
    fi

    if [[ -f "template/bot_config_template.toml" ]]; then
        cp "template/bot_config_template.toml" "config/bot_config.toml"
        ok "已复制 bot_config_template.toml"
    else
        warn "未找到 template/bot_config_template.toml"
    fi

    ok "Python 依赖安装完成"
}

download_script() {
    local DOWNLOAD_URL="${GITHUB_PROXY}https://raw.githubusercontent.com/Astriora/Antlia/refs/heads/main/Script/MoFox-Studio/mofox"
    local TARGET_DIR="$LOCAL_BIN/MoFox_Bot"
    local TARGET_FILE="$TARGET_DIR/mofox"

    mkdir -p "$TARGET_DIR"

    download_with_retry "$DOWNLOAD_URL" "$TARGET_FILE" || { err "下载失败"; }
    chmod +x "$TARGET_FILE"
    ok "mofox 脚本已下载到 $TARGET_FILE"

    # 软链到 /usr/local/bin 方便全局调用
    $SUDO ln -sf "$TARGET_FILE" /usr/local/bin/mofox

    # 直接写 path.conf 到用户目录，不用初始化
    echo "$DEPLOY_DIR" >"$TARGET_DIR/path.conf"
    ok "路径配置文件已写入: $TARGET_DIR/path.conf"

    ok "mofox 已准备就绪"
}

show_text() {
    print_title "部署完成"

    ok "MoFox_Bot 部署完成！"
    info "部署路径: $DEPLOY_DIR"
    info "MoFox_Bot 文件夹: $DEPLOY_DIR/MoFox_Bot"

    echo
    warn "请手动修改以下配置文件："
    info " - $DEPLOY_DIR/MoFox_Bot/.env"
    info " - $DEPLOY_DIR/MoFox_Bot/config/bot_config_template.toml"
    info " - $DEPLOY_DIR/MoFox_Bot/config/model_config.toml"

    echo
    ok "完成配置后，可执行以下命令启动："
    echo -e "  ${GREEN}mofox${RESET}"

    echo
}

main() {
    print_title "MoFox 2025.10.25"
    detect_system

    # 选择 GitHub 代理
    select_github_proxy

    # 安装系统依赖
    install_system_dependencies

    # 安装 uv
    install_uv_environment

    # 克隆仓库
    clone_MoFox_Bot

    # 安装 Python 依赖
    install_python_dependencies
    # 下载启动脚本
    download_script
    # 显示文字
    show_text
}

# 执行主函数
main
