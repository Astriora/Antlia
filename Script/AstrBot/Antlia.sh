#!/bin/bash

# AstrBot Shell部署脚本
# 版本: 2025/10/19

set -euo pipefail

# =============================================================================
# 路径与常量定义
# =============================================================================

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
GITHUB_PROXY="" # GitHub 代理URL
PKG_MANAGER=""  # 包管理器
DISTRO=""
SUDO=""

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "DEPLOY_DIR: $DEPLOY_DIR"

# 检查是否为异常目录（如 /dev/fd、/proc/self/fd 等）
if [[ "$DEPLOY_DIR" == /dev/fd/* ]] || [[ "$DEPLOY_DIR" == /proc/self/fd/* ]] || [[ ! -d "$DEPLOY_DIR" ]]; then
	echo -e "\e[31m警告：检测到部署目录异常！可能因使用 'bash <(curl ...)' 导致路径错误。\e[0m"
	echo -e "\e[33m建议：将脚本下载到本地后运行，或确保当前目录可写。\e[0m"
else
	echo -e "\e[32m目录正常，可安全部署。\e[0m"
fi

#------------------------------------------------------------------------------

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
print_title() { echo -e "${BOLD}${CYAN}--- $1 ---${RESET}"; }

astrbot_art() {
	echo -e "${CYAN}"
	cat <<'EOF'
   _        _        ____        _   
  / \   ___| |_ _ __| __ )  ___ | |_ 
 / _ \ / __| __| '__|  _ \ / _ \| __|
/ ___ \\__ \ |_| |  | |_) | (_) | |_ 
/_/   \_\___/\__|_|  |____/ \___/ \__|
EOF
	echo -e "${RESET}"
}

#------------------------------------------------------------------------------

# =============================================================================
# 工具函数
# =============================================================================
command_exists() {               #定义函数
	command -v "$1" >/dev/null 2>&1 #检查命令是否存在
}                                #结束函数定义

download_with_retry() { #定义函数
	local url="$1"         #获取参数
	local output="$2"      #获取参数
	local max_attempts=3   #最大尝试次数
	local attempt=1        #当前尝试次数

	while [[ $attempt -le $max_attempts ]]; do         #循环直到达到最大尝试次数
		info "下载尝试 $attempt/$max_attempts: $url"          #打印信息日志
		if command_exists wget; then                      #如果 wget 存在
			if wget -O "$output" "$url" 2>/dev/null; then    #使用 wget 下载
				ok "下载成功: $output"                              #打印日志
				return 0                                        #成功返回
			fi                                               #结束条件判断
		elif command_exists curl; then                    #如果 curl 存在
			if curl -L -o "$output" "$url" 2>/dev/null; then #使用 curl 下载
				ok "下载成功: $output"                              #打印日志
				return 0                                        #成功返回
			fi                                               #结束条件判断
		fi                                                #结束条件判断
		warn "第 $attempt 次下载失败"                           #打印警告日志
		if [[ $attempt -lt $max_attempts ]]; then         #如果还没到最大尝试次数
			info "5秒后重试..."                                  #打印信息日志
			sleep 5                                          #等待 5 秒
		fi                                                #结束条件判断
		((attempt++))                                     #增加尝试次数
	done                                               #结束循环
	err "所有下载尝试都失败了"                                   #打印错误日志并退出
}                                                   #结束函数定义

# 检测并创建 /run/tmux/ 目录
check_tmux_directory() {
	local tmux_dir="/run/tmux"
	info "开始检查 tmux 文件与权限"
	# 检查目录是否存在
	if [ ! -d "$tmux_dir" ]; then
		info "目录 $tmux_dir 不存在，正在创建..."
		$SUDO mkdir -p "$tmux_dir"
	fi

	# 检查目录权限
	if [ "$(stat -c '%a' "$tmux_dir")" -ne 1777 ]; then
		info "目录权限不正确，正在修复权限..."
		$SUDO chmod 1777 "$tmux_dir"
	fi

	ok " $tmux_dir 目录检查通过"
}

#------------------------------------------------------------------------------

check_root_or_sudo() {
	# 场景1：通过 sudo 运行（普通用户提权）
	if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
		warn "检测到您通过 sudo 运行此脚本（用户: ${SUDO_USER}）。"
		read -rp "是否确认以管理员权限继续？请输入 'yes'： " confirm
		[[ "$confirm" != "yes" ]] && {
			info "操作已取消。"
			exit 0
		}
		return 0
	fi

	# 直接以 root 身份运行
	if [[ $EUID -eq 0 ]]; then
		warn "root 用户运行"
		return 0
	fi

	# 普通用户运行
	if sudo -v >/dev/null 2>&1; then
		info "普通用户运行 sudo权限可用。"
	else
		info "普通用户运行 无sudo权限。"
	fi

}

# =============================================================================
# GitHub 代理选择
# =============================================================================

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


#------------------------------------------------------------------------------

# =============================================================================
# 一次性检查sudo可用性
# =============================================================================
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
# 包管理器检测
# =============================================================================
detect_package_manager() { #定义函数
	info "检测包管理器..."          #打印信息日志

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
		local manager="${manager_info%%:*}"     #提取包管理器名称
		local distro="${manager_info##*:}"      #提取发行版名称

		if command_exists "$manager"; then    #如果包管理器存在
			PKG_MANAGER="$manager"               #设置全局变量
			DISTRO="$distro"                     #设置全局变量
			ok "检测到包管理器: $PKG_MANAGER ($DISTRO)" #打印信息日志
			return 0                             #成功返回
		fi                                    #结束条件判断
	done                                   #结束循环

	err "未检测到支持的包管理器，请手动安装 git、curl/wget 和 python3" #打印错误日志并退出
}                                                #结束函数定义

#------------------------------------------------------------------------------

# =============================================================================
# 系统检测
# =============================================================================
detect_system() {     #定义函数
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
		source /etc/os-release           #加载文件
		ok "检测到系统: $NAME"                #打印信息
	else                              # 否则
		warn "无法检测具体系统版本"                #打印警告
	fi                                #结束条件判断

	# 检测包管理器
	check_sudo
	detect_package_manager
} #结束函数定义

#------------------------------------------------------------------------------

# =============================================================================
# 通用包安装函数
# =============================================================================
install_package() { #定义函数
	local package="$1" #获取参数

	info "安装 $package..." #打印信息日志
	case $PKG_MANAGER in  #根据包管理器选择安装命令
	pacman)
		$SUDO pacman -Sy --noconfirm "$package" #安装包
		;;
	apt)
		$SUDO apt update -qq 2>/dev/null || true #更新包列表
		$SUDO apt install -y "$package"          #安装包
		;;
	dnf)
		$SUDO dnf install -y "$package" #安装包
		;;
	yum)
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
}     #结束函数定义

#------------------------------------------------------------------------------

# =============================================================================
# 系统依赖安装
# =============================================================================
install_system_dependencies() { #定义函数
	print_title "安装系统依赖"           #打印标题

	local packages=("git" "python3" "tmux" "tar" "findutils" "gzip") #定义必需包数组

	# 检查下载工具
	if ! command_exists curl && ! command_exists wget; then #如果 curl 和 wget 都不存在
		packages+=("curl")                                     #添加 curl 到数组
	fi                                                      #结束条件判断

	# Arch 系统特殊处理：添加 uv 到必需包数组
	if [[ "$ID" == "arch" ]]; then
		# 只有 Arch 才用包管理器安装 uv
		packages+=("uv")
		info "已将 uv 添加到 Arch 的必需安装包列表"
	fi

	# 检查 pip
	if ! command_exists pip3 && ! command_exists pip; then #如果 pip3 和 pip 都不存在
		case $PKG_MANAGER in                                  #根据包管理器选择 pip 包名称
		apt) packages+=("python3-pip") ;;                     # apt
		pacman) packages+=("python-pip") ;;                   # pacman
		dnf | yum) packages+=("python3-pip") ;;               # dnf 和 yum
		zypper) packages+=("python3-pip") ;;                  # zypper
		apk) packages+=("py3-pip") ;;                         # apk
		brew) packages+=("pip3") ;;                           # brew
		*) packages+=("python3-pip") ;;                       #默认
		esac                                                  #结束条件判断
	fi                                                     #结束条件判断

	info "安装必需的系统包..."                                     #打印信息日志
	for package in "${packages[@]}"; do                    #循环遍历包数组
		if command_exists "${package/python3-pip/pip3}"; then #如果包已安装
			ok "$package 已安装"                                    #打印信息日志
		else                                                  #否则
			install_package "$package"                           #安装包
		fi                                                    #结束条件判断
	done                                                   #结束循环

	ok "系统依赖安装完成" #打印成功日志
}              #结束函数定义

# =============================================================================
# uv 环境安装
# =============================================================================

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
# =============================================================================
# 项目克隆
# =============================================================================
clone_astrbot() {            #定义函数
	print_title "克隆 AstrBot 项目" #打印标题

	info "目录 $SCRIPT_DIR"
	info "目录 $DEPLOY_DIR"
	cd "$DEPLOY_DIR" || exit #进入部署目录
	# 如果目录已存在，提示用户选择是否删除

	if [[ -d "AstrBot" ]]; then                    #如果目录存在
		warn "检测到 AstrBot 文件夹已存在"                     #打印警告
		read -rp "是否删除并重新克隆? (y/n, 默认n): " del_choice #读取用户输入
		if [[ "$del_choice" =~ ^[Yy]$ ]]; then        #如果用户选择删除
			rm -rf "AstrBot"                             #删除目录
			ok "已删除旧的 AstrBot 文件夹"                       #打印信息
		else                                          #否则
			warn "跳过 AstrBot 仓库克隆"                       #打印警告
			#跳过克隆
			return
		fi #结束条件判断
	fi  #结束条件判断

	# 克隆项目

	local repo_url="${GITHUB_PROXY}https://github.com/AstrBotDevs/AstrBot.git" #设置仓库URL
	#克隆项目
	info "开始克隆 AstrBot 仓库..." #打印信息日志

	if ! git clone --depth 1 "$repo_url" AstrBot; then #尝试克隆仓库
		err "项目克隆失败，请检查网络或代理设置"                           #打印错误日志并退出
	fi                                                 #结束条件判断

	ok "AstrBot 项目克隆完成" #打印成功日志
}                    #结束函数定义

#------------------------------------------------------------------------------

# =============================================================================
# Python 依赖安装
# =============================================================================
install_python_dependencies() { # 定义函数
	print_title "安装 Python 依赖"     # 打印标题

	# 进入项目目录
	cd "$DEPLOY_DIR/AstrBot" || err "无法进入 AstrBot 目录" # 进入目录

	# 设置环境变量使 uv 使用 pip 镜像配置
	export UV_INDEX_URL="https://mirrors.ustc.edu.cn/pypi/simple/"
	mkdir -p ~/.cache/uv
	chown -R "$(whoami):$(whoami)" ~/.cache/uv
	# 使用 uv sync 安装依赖
	attempt=1
	while [[ $attempt -le 3 ]]; do
		if uv sync --index-url https://mirrors.ustc.edu.cn/pypi/simple/; then
			ok "uv sync 成功"
			break
		else
			warn "uv sync 失败，重试 $attempt/3"
			((attempt++))
			sleep 5
		fi
	done

	# 如果 uv sync失败退出脚本
	if [[ $attempt -gt 3 ]]; then
		err "uv sync 失败 脚本将停止"
	fi
	ok "Python 依赖安装完成" # 打印成功日志
}                   # 结束函数定义

#------------------------------------------------------------------------------

generate_start_script() {                                                                                               #定义函数
	local start_script_url="${GITHUB_PROXY}https://github.com/Astriora/Antlia/raw/refs/heads/main/Script/AstrBot/start.sh" #下载链接
	#下载启动脚本
	cd "$DEPLOY_DIR" || err "无法进入部署目录" #进入部署目录
	download_with_retry "$start_script_url" "astrbot.sh"

	info "下载astrbot.sh ing..." #打印信息日志
	chmod +x astrbot.sh        #赋予执行权限

} #结束函数定义

#------------------------------------------------------------------------------

# =============================================================================
# 主函数
# =============================================================================
main() { #定义主函数
	# 调用检查函数
	check_root_or_sudo
	astrbot_art
	print_title "AstrBot Shell部署脚本" #打印标题

	info "脚本版本: 2025/10/19" #打印版本信息

	# 执行部署步骤
	select_github_proxy         #选择 GitHub 代理
	detect_system               #检测系统
	install_system_dependencies #安装系统依赖
	# 安装uv
	install_uv_environment

	clone_astrbot               #克隆项目
	install_python_dependencies #安装 Python 依赖
	generate_start_script       #生成启动脚本
	check_tmux_directory        #检查tmux目录防止 在启动的时候 couldn't create directory /run/tmux/0 (No such file or directory)

	print_title "🎉 部署完成! 🎉"
	echo "系统信息: $DISTRO ($PKG_MANAGER)"
	echo
	echo "下一步: 运行 './astrbot.sh' 来启动和管理 AstrBot"

}

# 执行主函数
main
