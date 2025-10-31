#!/bin/bash

# AstrBot 部署脚本
# 版本: 2025.10.31

set -euo pipefail
check_download_tool() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_TOOL="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_TOOL="wget"
    else
        echo "错误: 未检测到 curl 或 wget"
        echo "请先手动安装其中一个再重新运行脚本"
        case "$PKG_MANAGER" in
            apt) echo "安装命令: sudo apt install curl -y" ;;
            pacman) echo "安装命令: sudo pacman -S curl --noconfirm" ;;
            dnf|yum) echo "安装命令: sudo dnf install curl -y" ;;
            zypper) echo "安装命令: sudo zypper install curl -y" ;;
            apk) echo "安装命令: apk add curl" ;;
        esac
        exit 1
    fi
}
download_and_source_utils() {
    local utils_url="${GITHUB_PROXY}https://raw.githubusercontent.com/Astriora/Antlia/refs/heads/main/utils.sh"
    local utils_file="/tmp/utils.sh"

    echo "检查下载工具..."
    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_TOOL="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_TOOL="wget"
    else
        echo "错误: 未检测到 curl 或 wget"
        echo "请先手动安装其中一个再重新运行脚本"
        exit 1
    fi

    echo "下载 utils.sh 中..."
    local attempt=1 max_attempts=3
    while [[ $attempt -le $max_attempts ]]; do
        if [[ "$DOWNLOAD_TOOL" == "curl" ]]; then
            curl -fsSL "$utils_url" -o "$utils_file" && break
        else
            wget -qO "$utils_file" "$utils_url" && break
        fi
        echo "下载失败 (第 $attempt 次)，重试中..."
        ((attempt++))
        sleep 3
    done

    if [[ ! -s "$utils_file" ]]; then
        echo "utils.sh 下载失败，请检查网络或代理: $utils_url"
        exit 1
    fi

    echo "utils.sh 下载完成，正在加载..."
    # shellcheck disable=SC1090
    source "$utils_file"
}

GITHUB_PROXY=""
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

select_github_proxy() {
    echo "选择 GitHub 代理"
    echo "请根据您的网络环境选择一个合适的下载代理："
    echo

    select proxy_choice in "ghfast.top 镜像 (推荐)" "ghproxy.net 镜像" "不使用代理" "自定义代理"; do
        case $proxy_choice in
        "ghfast.top 镜像 (推荐)")
            GITHUB_PROXY="https://ghfast.top/"
            echo "已选择: ghfast.top 镜像"
            break
            ;;
        "ghproxy.net 镜像")
            GITHUB_PROXY="https://ghproxy.net/"
            echo "已选择: ghproxy.net 镜像"
            break
            ;;
        "不使用代理")
            GITHUB_PROXY=""
            echo "已选择: 不使用代理"
            break
            ;;
        "自定义代理")
            read -rp "请输入自定义 GitHub 代理 URL (如 ghfast.top/ 或 https://ghfast.top/, 必须以斜杠 / 结尾): " custom_proxy

            # 自动加 https://（如果没有写协议）
            if [[ "$custom_proxy" != http*://* ]]; then
                custom_proxy="https://$custom_proxy"
                echo "代理 URL 没有写协议，已自动加 https://"
            fi

            # 自动添加结尾斜杠
            if [[ "$custom_proxy" != */ ]]; then
                custom_proxy="${custom_proxy}/"
                echo "代理 URL 没有以斜杠结尾，已自动添加斜杠"
            fi

            GITHUB_PROXY="$custom_proxy"
            echo "已选择: 自定义代理 - $GITHUB_PROXY"
            break
            ;;
        *)
            echo "无效输入，使用默认代理"
            GITHUB_PROXY="https://ghfast.top/"
            echo "已选择: ghfast.top 镜像 (默认)"
            break
            ;;
        esac
    done
}


# 系统依赖安装
install_system_dependencies() {
    print_title "安装系统依赖"

    # 基础必需包
    local packages=("git" "python3" "tmux" "tar" "findutils" "gzip")

    # 检查下载工具
    if ! command_exists curl && ! command_exists wget; then
        packages+=("curl")
    fi

    # 检查 pip
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

    # Arch 系统特殊处理：添加 uv
    [[ "$ID" == "arch" ]] && packages+=("uv") && info "已将 uv 添加到 Arch 的必需安装包列表"

    info "开始安装系统依赖..."
    for pkg in "${packages[@]}"; do
        local cmd_name="${pkg/python3-pip/pip3}"  # pip3 包名映射
        if command_exists "$cmd_name"; then
            ok "$pkg 已安装"
        else
            install_pkg "$pkg"
        fi
    done

    ok "系统依赖安装完成"
}


generate_start_script() {
	local start_script_url="${GITHUB_PROXY}https://raw.githubusercontent.com/Astriora/Antlia/refs/heads/main/Script/AstrBot/start.sh"
	#下载启动脚本
	cd "$DEPLOY_DIR" || err "无法进入部署目录"
	download_with_retry "$start_script_url" "astrbot.sh"

	info "下载astrbot.sh ing..."
	chmod +x astrbot.sh

} 


# 主函数
main() { 
	# 调用检查函数
	check_download_tool
    download_and_source_utils
	
	astrbot_art
	print_title "AstrBot 部署脚本" #打印标题
    check_root_or_sudo
	info "脚本版本: 2025/10.31" #打印版本信息

	# 执行部署步骤
	select_github_proxy         #选择 GitHub 代理
	detect_system               #检测系统
	install_system_dependencies #安装系统依赖
	# 安装uv
	install_uv

	local clone_url="${GITHUB_PROXY}https://github.com/AstrBotDevs/AstrBot.git"
	git clone --depth 1 "$clone_url" "AstrBot" #克隆项目
	uv_sync AstrBot #安装 Python 依赖
	generate_start_script       #生成启动脚本
	check_tmux_directory        #检查tmux目录防止 在启动的时候 couldn't create directory /run/tmux/0 (No such file or directory)

	print_title "🎉 部署完成! 🎉"
	echo "系统信息: $DISTRO ($PKG_MANAGER)"
	echo
	echo "下一步: 运行 './astrbot.sh' 来启动和管理 AstrBot"

}

# 执行主函数
main
