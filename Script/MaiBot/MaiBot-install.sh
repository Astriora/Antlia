#!/bin/bash
# MaiBot Shell 部署脚本
# 版本: 2025/11/11

set -euo pipefail

DEPLOY_DIR=""
FORCE_CLONE=0
GITHUB_PROXY=""
CI_MODE=0
LOCAL_BIN="$HOME/.local/bin"
TARGET_PATH="$LOCAL_BIN/maibot"
print_help() {
	cat <<EOF
MaiBot Shell 部署脚本

用法: bash $0 [选项]

选项:
  --ci                启用 CI 模式，日志默认显示
  --GITHUB-URL <url>  自定义 GitHub 代理/镜像 URL
  --force             强制克隆项目，即使目录存在也覆盖
  --path <dir>        自定义部署路径，默认使用脚本所在目录
  -h, --help          显示本帮助信息

示例:
  bash $0 --force --path /home/zhende1113/ --GITHUB-URL https://ghproxy.net/
EOF
}
# 参数解析
while [[ $# -gt 0 ]]; do
	case $1 in
	--ci | -ci)
		CI_MODE=1
		FORCE_CLONE=1 # CI 默认强制覆盖
		shift
		;;
	--GITHUB-URL)
		GITHUB_PROXY="$2"
		shift 2
		;;
	--force)
		FORCE_CLONE=1
		shift
		;;
	--path)
		DEPLOY_DIR="$2"
		shift 2
		;;
	-h | --help)
		print_help
		exit 0
		;;
	*)
		echo "未知参数: $1"
		print_help
		exit 1
		;;
	esac
done

get_script_dir() {
	local source="${BASH_SOURCE[0]}"
	if [[ "$source" == /dev/fd/* ]] || [[ ! -f "$source" ]]; then
		pwd
	else
		(cd "$(dirname "$source")" && pwd)
	fi
}

SCRIPT_DIR="$(get_script_dir)"
DEPLOY_DIR="${DEPLOY_DIR:-$SCRIPT_DIR}"
SUDO=$([[ $EUID -eq 0 || ! $(command -v sudo) ]] && echo "" || echo "sudo")
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
LOG_FILE="$SCRIPT_DIR/maibot_install_log_$(date '+%Y%m%d_%H%M%S').log"
exec > >(tee -a "$LOG_FILE") 2>&1
# 检查目录异常
if [[ "$DEPLOY_DIR" == /dev/fd/* ]] || [[ "$DEPLOY_DIR" == /proc/self/fd/* ]] || [[ ! -d "$DEPLOY_DIR" ]]; then
	echo -e "\e[31m警告：部署目录异常，建议下载到本地再运行\e[0m"
else
	echo -e "\e[32m目录正常，可安全部署\e[0m"
fi

main() {
    print_title "MaiBot 部署脚本"
    detect_system
    detect_package_manager
    select_github_proxy
    install_system_dependencies
    install_uv_environment
    clone_maibot
    install_python_dependencies
    update_shell_config
    download-script
    ok "MaiBot 部署完成！ 执行: 
    source  ~/.bashrc
    maibot
    来启动"
}

# 日志函数
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() {
	echo -e "${RED}[ERROR]${RESET} $1"
	exit 1
}
print_title() { echo -e "${BOLD}${CYAN}--- $1 ---${RESET}"; }
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 带重试的下载函数
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        info "下载文件 (尝试 $attempt/$max_attempts): $url"
        
        if curl -L -o "$output" "$url" 2>/dev/null; then
            ok "下载成功: $output"
            return 0
        elif wget -q -O "$output" "$url" 2>/dev/null; then
            ok "下载成功: $output"
            return 0
        else
            warn "下载失败，尝试 $attempt/$max_attempts"
            if [ $attempt -lt $max_attempts ]; then
                sleep 5
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    err "下载失败: $url"
}

select_github_proxy() {
	if [[ $CI_MODE -eq 1 ]]; then
		return 0 # CI 模式不弹选择
	fi
	print_title "选择 GitHub 代理"
	select proxy_choice in "ghfast.top (推荐)" "ghproxy.net" "不使用代理" "自定义"; do
		case $proxy_choice in
		"ghfast.top (推荐)")
			GITHUB_PROXY="https://ghfast.top/"
			break
			;;
		"ghproxy.net")
			GITHUB_PROXY="https://ghproxy.net/"
			break
			;;
		"不使用代理")
			GITHUB_PROXY=""
			break
			;;
		"自定义")
			read -rp "输入自定义代理 URL: " custom_proxy
			# 确保URL格式正确
			[[ "$custom_proxy" != http*://* ]] && custom_proxy="https://$custom_proxy"
			[[ "$custom_proxy" != */ ]] && custom_proxy="${custom_proxy}/"
			GITHUB_PROXY="$custom_proxy"
			break
			;;
		*)
			warn "无效输入，使用默认"
			GITHUB_PROXY="https://ghfast.top/"
			break
			;;
		esac
	done
	ok "已选择代理: $GITHUB_PROXY"
}

# 检测包管理器
detect_package_manager() {
	info "检测包管理器..."
	local managers=(
		"pacman:Arch Linux"
		"apt:Debian/Ubuntu"
		"dnf:Fedora/RHEL/CentOS"
		"yum:RHEL/CentOS"
		"zypper:openSUSE"
		"apk:Alpine Linux"
		"brew:macOS/Linux"
	)

	for m in "${managers[@]}"; do
		local name="${m%%:*}"
		local distro="${m##*:}"
		if command_exists "$name"; then
			PKG_MANAGER="$name"
			DISTRO="$distro"
			ok "检测到: $PKG_MANAGER ($DISTRO)"
			return
		fi
	done
	err "未检测到支持的包管理器"
}

# 系统检测
detect_system() {
	print_title "检测系统环境"
	ARCH=$(uname -m)
	if [[ $ARCH =~ ^(x86_64|aarch64|arm64)$ ]]; then
		ok "架构: $ARCH"
	else
		warn "架构 $ARCH 可能不被完全支持"
	fi

	if [[ -f /etc/os-release ]]; then
		source /etc/os-release
		ok "系统: $NAME"
	else
		warn "无法检测具体系统"
	fi
}

# 通用包安装函数
install_package() {
	local package="$1"
	info "安装 $package..."
	case $PKG_MANAGER in
	pacman)
		$SUDO pacman -Sy --noconfirm "$package"
		;;
	apt)
		$SUDO apt update -qq || true
		$SUDO apt install -y "$package"
		;;
	dnf)
		$SUDO dnf install -y "$package"
		;;
	yum)
		$SUDO yum install -y "$package"
		;;
	zypper)
		$SUDO zypper install -y "$package"
		;;
	apk)
		$SUDO apk add gcc musl-dev linux-headers "$package"
		;;
	brew)
		$SUDO brew install "$package"
		;;
	*)
		warn "未知包管理器，请手动安装 $package"
		;;
	esac
}

#系统依赖安装
install_system_dependencies() { 
    print_title "安装系统依赖"
    
    local packages=("git" "python3" "screen" "tar" "findutils" "zip")
    
    if ! command_exists curl && ! command_exists wget; then
        packages+=("curl")
    fi
    
    if [[ "$ID" == "arch" ]]; then
        packages+=("uv")
    fi
    
    if ! command_exists pip3 && ! command_exists pip; then
        case $PKG_MANAGER in
            apt) packages+=("python3-pip") ;;
            pacman) packages+=("python-pip") ;;
            dnf|yum) packages+=("python3-pip") ;;
            zypper) packages+=("python3-pip") ;;
            apk) packages+=("py3-pip") ;;
            brew) packages+=("pip3") ;;
            *) packages+=("python3-pip") ;;
        esac
    fi
    
    if ! command_exists python3-config; then
        case $PKG_MANAGER in
            apt) packages+=("python3-dev") ;;
            pacman) packages+=("python") ;;
            dnf|yum) packages+=("python3-devel") ;;
            zypper) packages+=("python3-devel") ;;
            apk) packages+=("python3-dev") ;;
            brew) ;; 
            *) packages+=("python3-dev") ;;
        esac
    fi
    
    if ! command_exists gcc || ! command_exists g++; then
        case $PKG_MANAGER in
            apt) packages+=("build-essential") ;;
            pacman) packages+=("base-devel") ;;
            dnf|yum) packages+=("gcc" "gcc-c++" "make") ;;
            zypper) packages+=("gcc" "gcc-c++" "make") ;;
            apk) packages+=("build-base") ;;
            brew) packages+=("gcc") ;;
            *) echo "未知包管理器，请手动安装 gcc/g++" ;;
        esac
    fi

    info "安装必需的系统包..."
    for package in "${packages[@]}"; do
        if command_exists "${package/python3-pip/pip3}"; then
            ok "$package 已安装"
        else
            install_package "$package"
        fi
    done
    
    ok "系统依赖安装完成"
}

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

# 克隆 MaiBot 仓库
clone_maibot() {
    local base_url="${GITHUB_PROXY}https://github.com/Mai-with-u"
    local repos=("MaiBot" "MaiBot-Napcat-Adapter")
    
    for repo in "${repos[@]}"; do
        local clone_url="${base_url}/${repo}.git"
        local deploy_path="$DEPLOY_DIR/$repo"
        
        if [ -d "$deploy_path" ]; then
            if [[ $CI_MODE -eq 1 || $FORCE_CLONE -eq 1 ]]; then
                rm -rf "$deploy_path"
                ok "已删除$repo文件夹。"
            else
                read -p "检测到$repo文件夹已存在，删除重新克隆？(y/n, 默认n): " choice
                choice=${choice:-n}
                if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
                    warn "跳过$repo仓库克隆。"
                    continue
                fi
                rm -rf "$deploy_path"
            fi
        fi
        
        info "克隆 $repo 仓库"
        git clone --depth 1 "$clone_url" "$deploy_path"
    done
}

#安装 Python 依赖
install_python_dependencies() {
    print_title "安装 Python 依赖"
    
    export UV_INDEX_URL="https://mirrors.ustc.edu.cn/pypi/simple/"
    mkdir -p ~/.cache/uv && chown -R "$(whoami):$(whoami)" ~/.cache/uv

    # MaiBot 安装
    cd "$DEPLOY_DIR/MaiBot" || err "无法进入 MaiBot 目录"
    for i in 1 2 3; do
        uv sync --index-url "$UV_INDEX_URL" && break || warn "uv sync 失败,重试 $i/3" && sleep 5
    done
    [[ $? -ne 0 ]] && err "uv sync 失败"
    
    mkdir -p config
    cp template/bot_config_template.toml config/bot_config.toml
    cp template/model_config_template.toml config/model_config.toml  
    cp template/template.env .env
    ok "MaiBot 完成"

    # Adapter 安装
    cd "$DEPLOY_DIR/MaiBot-Napcat-Adapter" || err "无法进入 Adapter 目录"
    uv venv .venv
    . .venv/bin/activate
    uv pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    cp template/template_config.toml config.toml
    deactivate
    ok "Python 依赖安装完成"
}

update_shell_config() {
    local path_export='export PATH="$HOME/.local/bin:$PATH"'
    local fish_path_set='set -gx PATH "$HOME/.local/bin" $PATH'

    [[ -f "$HOME/.bashrc" ]] && grep -qF "$path_export" "$HOME/.bashrc" || echo "$path_export" >> "$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] && grep -qF "$path_export" "$HOME/.zshrc" || echo "$path_export" >> "$HOME/.zshrc"
    
    local fish_config="$HOME/.config/fish/config.fish"
    mkdir -p "$(dirname "$fish_config")"
    [[ -f "$fish_config" ]] && grep -qF "$fish_path_set" "$fish_config" || echo "$fish_path_set" >> "$fish_config"
}


download-script() {
    local DOWNLOAD_URL="${GITHUB_PROXY}https://github.com/Astriora/Antlia/raw/refs/heads/main/Script/MaiBot/maibot"
    local TARGET_DIR="$LOCAL_BIN/maibot"        # 目录
    local TARGET_FILE="$TARGET_DIR/maibot"      # 文件路径

    mkdir -p "$TARGET_DIR"

    # 下载 maibot 文件到 TARGET_FILE
    download_with_retry "$DOWNLOAD_URL" "$TARGET_FILE"
    chmod +x "$TARGET_FILE"
    ok "maibot 脚本已下载到 $TARGET_FILE"

    # 调用 maibot 初始化
    if [[ -f "$TARGET_FILE" ]]; then
        "$TARGET_FILE" --init="$DEPLOY_DIR"
        ok "maibot 已初始化到 $DEPLOY_DIR"
    else
        err "maibot 脚本下载失败，初始化中止"
    fi

}

main