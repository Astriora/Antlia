#!/bin/bash
# utils 2525.10.25
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

download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        info "下载尝试 $attempt/$max_attempts: $url"

        if command_exists curl; then
            # 使用 curl 下载，带进度条
            if curl -sL -o "$output" -# "$url"; then
                ok "下载成功: $output"
                return 0
            fi
        elif command_exists wget; then
            # fallback: wget
            if wget -O "$output" "$url"; then
                ok "下载成功: $output"
                return 0
            fi
        else
            err "未检测到 curl 或 wget，请先安装下载工具"
        fi

        warn "第 $attempt 次下载失败"
        if [[ $attempt -lt $max_attempts ]]; then
            info "5秒后重试..."
            sleep 5
        fi
        ((attempt++))
    done

    err "所有下载尝试都失败了"
}




# 检查系统和架构
detect_system() {
    # 系统架构
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|aarch64|arm64)
            ok "系统架构: $ARCH (支持)"
            ;;
        *)
            warn "架构 $ARCH 可能不被完全支持"
            ;;
    esac

    # 系统发行版
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO_NAME="$NAME"
        DISTRO_ID="$ID"
        ok "检测到系统: $DISTRO_NAME ($DISTRO_ID)"
    else
        warn "无法检测系统发行版"
        DISTRO_NAME="Unknown"
        DISTRO_ID="unknown"
    fi

    # 检查包管理器
    detect_pkg_manager
}

# 检测包管理器
detect_pkg_manager() {
    local managers=("apt:Debian/Ubuntu" "pacman:Arch" "dnf:Fedora" "yum:RHEL" "zypper:openSUSE" "apk:Alpine" "brew:macOS")
    for m in "${managers[@]}"; do
        local mgr="${m%%:*}" distro="${m##*:}"
        if command_exists "$mgr"; then
            PKG_MANAGER="$mgr"
            DISTRO="$distro"
            ok "检测到包管理器: $PKG_MANAGER ($DISTRO)"
            return
        fi
    done
    warn "未检测到支持的包管理器，请手动安装 git/curl/wget/python3"
}

# 安装包
install_pkg() {
    local pkg="$1"
    info "安装 $pkg ..."
    case "$PKG_MANAGER" in
        pacman) $SUDO pacman -S --noconfirm "$pkg" ;;
        apt) $SUDO apt update -qq && $SUDO apt install -y "$pkg" ;;
        dnf) $SUDO dnf install -y "$pkg" ;;
        yum) $SUDO yum install -y "$pkg" ;;
        zypper) $SUDO zypper install -y "$pkg" ;;
        apk) $SUDO apk add "$pkg" ;;
        brew) $SUDO brew install "$pkg" ;;
        *) warn "未知包管理器 $PKG_MANAGER，请手动安装 $pkg" ;;
    esac
}

enable_epel() {
    if [[ "$PKG_MANAGER" != "dnf" && "$PKG_MANAGER" != "yum" ]]; then
        return 0
    fi

    if $PKG_MANAGER repolist enabled | grep -q epel; then
        ok "EPEL 仓库已启用"
        return 0
    fi

    info "正在启用 EPEL 仓库..."
    $SUDO $PKG_MANAGER install -y epel-release || warn "EPEL 仓库启用失败"
    ok "EPEL 仓库启用完成"
}


install_uv() {
    print_title "安装和配置 uv 环境"

    if command_exists uv; then
        ok "uv 已安装"
    else
        info "安装 uv..."
        bash <(curl -sSL "${GITHUB_PROXY}https://github.com/Astriora/Antlia/raw/refs/heads/main/Script/UV/uv_install.sh") --GITHUB-URL "$GITHUB_PROXY"
    fi
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
}

clone_git_repo() {
    local repo_url="$1"        # 仓库地址
    local target_dir="$2"      # 克隆到的目录（可选）
    target_dir="${target_dir:-$(basename "$repo_url" .git)}"

    if [ -d "$target_dir" ]; then
        warn "检测到目录 $target_dir 已存在，是否删除重新克隆？(y/n)"
        read -rp "请输入选择 (y/n, 默认n): " del_choice
        del_choice=${del_choice:-n}
        if [[ "$del_choice" =~ ^[Yy]$ ]]; then
            rm -rf "$target_dir"
            ok "已删除 $target_dir"
        else
            warn "跳过克隆 $repo_url"
            return
        fi
    fi

    info "正在克隆仓库 $repo_url 到 $target_dir"
    git clone --depth 1 "$repo_url" "$target_dir" || err "克隆失败"
}


uv_sync() {
    local project_dir="$1"           # 项目目录
    local uv_index="${2:-https://mirrors.ustc.edu.cn/pypi/simple/}"  # uv 镜像源，默认中科大

    if [[ ! -d "$project_dir" ]]; then
        err "目录 $project_dir 不存在"
    fi

    print_title "安装 Python 依赖"

    # 配置 uv 镜像源
    export UV_INDEX_URL="$uv_index"
    mkdir -p ~/.cache/uv
    chown -R "$(whoami):$(whoami)" ~/.cache/uv

    # 同步依赖
    cd "$project_dir" || err "无法进入 $project_dir"
    info "同步依赖..."

    local attempt=1
    local max_attempts=3
    while [[ $attempt -le $max_attempts ]]; do
        if uv sync --index-url "$UV_INDEX_URL"; then
            ok "uv sync 成功"
            break
        else
            warn "uv sync 失败, 重试 $attempt/$max_attempts"
            ((attempt++))
            sleep 5
        fi
    done

    if [[ $attempt -gt $max_attempts ]]; then
        err "uv sync 多次失败"
    fi
}





info "工具函数已加载"