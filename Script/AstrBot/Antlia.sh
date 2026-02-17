#!/bin/bash
# AstrBot Shell部署脚本
# 版本: 2025/11/09

set -euo pipefail

DEPLOY_DIR=""
FORCE_CLONE=0
GITHUB_PROXY=""
CI_MODE=0
UV_PROXY=""
PIP_PROXY=""
print_help() {
  cat <<EOF
AstrBot Shell部署脚本

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
LOG_FILE="$SCRIPT_DIR/astrbot_install_log_$(date '+%Y%m%d_%H%M%S').log"
LOCAL_BIN="$HOME/.local/bin"

exec > >(tee -a "$LOG_FILE") 2>&1
# 检查目录异常
if [[ "$DEPLOY_DIR" == /dev/fd/* ]] || [[ "$DEPLOY_DIR" == /proc/self/fd/* ]] || [[ ! -d "$DEPLOY_DIR" ]]; then
  echo -e "\e[31m警告：部署目录异常，建议下载到本地再运行\e[0m"
else
  echo -e "\e[32m目录正常，可安全部署\e[0m"
fi

# 日志函数
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() {
  echo -e "${RED}[ERROR]${RESET} $1"
  exit 1
}
print_title() { echo -e "${BOLD}${CYAN}--- $1 ---${RESET}"; }

main() {

  info "CI_MODE=$CI_MODE"
  if [[ $EUID -eq 0 ]]; then
    warn "请知悉 当前以 root 或 sudo 权限运行"
  else
    info "当前以普通用户权限运行"
  fi

  astrbot_art
  print_title "AstrBot Shell部署脚本"
  info "版本: 2026/2/16"
  if [[ -z "$GITHUB_PROXY" ]]; then
    base_choice_proxy "选择Github代理" "https://ghfast.top/" "https://ghproxy.net/" GITHUB_PROXY
  else
    ok "使用命令行指定的 GitHub 代理: $GITHUB_PROXY"
  fi
  base_choice_proxy "选择uv的CPython代理" "https://mirrors.huaweicloud.com/python-build-standalone/" "https://mirrors.tuna.tsinghua.edu.cn/python-build-standalone/" UV_PROXY
  base_choice_proxy "选择pip代理" "https://mirrors.aliyun.com/pypi/simple/" "https://pypi.tuna.tsinghua.edu.cn/simple/" PIP_PROXY
  export UV_PYTHON_INSTALL_MIRROR="$UV_PROXY"
  export UV_INDEX_URL="$PIP_PROXY"
  detect_package_manager
  detect_system
  install_system_dependencies
  install_uv_environment
  clone_astrbot
  install_python_dependencies
  download-script
  check_tmux_directory

  print_title "🎉 部署完成! 🎉"
  echo "系统信息: $DISTRO ($PKG_MANAGER)"
  echo "运行 './astrbot.sh' 启动 AstrBot"

  if [[ $CI_MODE -ne 1 ]]; then
    read -rp "是否删除日志文件? (y/N): " del_choice
    if [[ "$del_choice" =~ ^[Yy]$ ]]; then
      rm -f "$LOG_FILE"
      echo "日志文件已删除"
    else
      echo "日志文件保留在: $LOG_FILE"
    fi
  fi
}

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

command_exists() { command -v "$1" >/dev/null 2>&1; }

download_with_retry() {
  local url="$1" output="$2" max_attempts=3 attempt=1
  while [[ $attempt -le $max_attempts ]]; do
    info "下载尝试 $attempt/$max_attempts: $url"
    if command_exists curl; then
      if curl -sL -o "$output" -# "$url"; then
        ok "下载成功: $output"
        return 0
      fi
    elif command_exists wget; then
      if wget -O "$output" "$url"; then
        ok "下载成功: $output"
        return 0
      fi
    else
      err "未检测到 curl 或 wget"
    fi
    warn "第 $attempt 次下载失败"
    ((attempt++))
    sleep 5
  done
  err "所有下载尝试失败"
}

check_tmux_directory() {
  local tmux_dir="/run/tmux"
  [[ ! -d "$tmux_dir" ]] && $SUDO mkdir -p "$tmux_dir"
  [[ "$(stat -c '%a' "$tmux_dir")" -ne 1777 ]] && $SUDO chmod 1777 "$tmux_dir"
  ok "tmux 目录检查通过"
}

base_choice_proxy() {
  local print_choice_ttile="$1"
  local choice1="$2"
  local choice2="$3"
  local -n variable="$4"
  local PS3="请输入序号: "
  if [[ $CI_MODE -eq 1 ]]; then
    return 0 # CI 模式不弹选择
  fi
  print_title "$print_choice_ttile"
  select proxy_choice in "$choice1" "$choice2" "不使用代理" "自定义"; do
    case $proxy_choice in
    "$choice1")
      variable="$choice1"
      break
      ;;
    "$choice2")
      variable="$choice2"
      break
      ;;
    "不使用代理")
      variable=""
      break
      ;;
    "自定义")
      read -rp "输入自定义代理 URL: " custom_proxy
      # 确保URL格式正确
      [[ "$custom_proxy" != http*://* ]] && custom_proxy="https://$custom_proxy"
      [[ "$custom_proxy" != */ ]] && custom_proxy="${custom_proxy}/"
      variable="$custom_proxy"
      break
      ;;
    *)
      warn "无效输入，使用默认"
      variable="$choice1"
      break
      ;;
    esac
  done
  ok "已选择代理: ${variable:-'空'}"
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
    $SUDO apt-get update -qq || true
    $SUDO apt-get install -y "$package"
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

# pip 安装检查
check_pip_package() {
  local pkg_manager="$1"
  case $pkg_manager in
  apt) echo "python3-pip" ;;
  pacman) echo "python-pip" ;;
  dnf | yum | zypper) echo "python3-pip" ;;
  apk) echo "py3-pip" ;;
  *) echo "python3-pip" ;;
  esac
}

install_system_dependencies() {
  print_title "安装系统依赖"
  local packages=("git" "python3" "tmux" "tar" "findutils" "gzip")

  # 检查下载工具
  ! command_exists curl && packages+=("curl")

  # Arch 特殊处理：添加 uv
  [[ "$ID" == "arch" ]] && packages+=("uv")

  # 检查 pip
  if ! command_exists pip3 && ! command_exists pip; then
    packages+=("$(check_pip_package "$PKG_MANAGER")")
  fi

  # 安装包
  for pkg in "${packages[@]}"; do
    local actual_pkg="${pkg/python3-pip/pip3}"
    if command_exists "$actual_pkg"; then
      ok "$pkg 已安装"
    else
      install_package "$pkg"
    fi
  done

  ok "系统依赖安装完成"
}

install_uv_environment() {
  print_title "安装 uv"

  if command_exists uv; then
    ok "uv 已安装"
    return
  fi

  # uv 未安装则下载并安装
  local uv_script_url="${GITHUB_PROXY}https://github.com/Astriora/Antlia/raw/refs/heads/main/Script/UV/uv_install.sh"
  info "uv 未检测到，开始安装..."
  bash <(curl -sSL "$uv_script_url") --GITHUB-URL "$GITHUB_PROXY"

  # 添加 uv 路径
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  ok "uv 安装完成"
}

clone_astrbot() {
  print_title "克隆 AstrBot"
  cd "$DEPLOY_DIR" || err "无法进入部署目录"

  if [[ -d "AstrBot" ]]; then
    if [[ $CI_MODE -eq 1 || $FORCE_CLONE -eq 1 ]]; then
      info "CI/Force 模式，删除旧目录 AstrBot"
      rm -rf "AstrBot"
    else
      read -rp "删除并重新克隆? (y/n, 默认n): " del_choice
      if [[ ! "$del_choice" =~ ^[Yy]$ ]]; then
        warn "用户取消克隆操作"
        return 0
      fi
      rm -rf "AstrBot"
    fi
  fi

  local repo_url="${GITHUB_PROXY}https://github.com/AstrBotDevs/AstrBot.git"
  info "克隆项目..."
  git clone --depth 1 "$repo_url" AstrBot || err "克隆失败"
  ok "克隆完成"
}

install_python_dependencies() {
  print_title "安装 Python 依赖"
  cd "$DEPLOY_DIR/AstrBot" || err "无法进入项目目录"

  # 设置镜像源
  mkdir -p ~/.cache/uv
  chown -R "$(whoami):$(whoami)" ~/.cache/uv

  # 重试安装
  local attempt=1
  while [[ $attempt -le 3 ]]; do
    if uv sync; then
      break
    fi
    warn "uv sync 失败，重试 $attempt/3"
    ((attempt++))
    sleep 5
  done

  [[ $attempt -gt 3 ]] && err "uv sync 失败"
  ok "Python 依赖安装完成"
}

download-script() {
  local DOWNLOAD_URL="${GITHUB_PROXY}https://github.com/Astriora/Antlia/raw/refs/heads/main/Script/AstrBot/start.sh"
  local TARGET_DIR="$LOCAL_BIN"          # 目录
  local TARGET_FILE="$TARGET_DIR/astrbot" # 文件路径

  mkdir -p "$TARGET_DIR"

  # 下载 start 文件到 TARGET_FILE
  download_with_retry "$DOWNLOAD_URL" "$TARGET_FILE"
  chmod +x "$TARGET_FILE"
  ok " 启动脚本已下载到 $TARGET_FILE"

  #  初始化
  if [[ -f "$TARGET_FILE" ]]; then
    "$TARGET_FILE" --init="$DEPLOY_DIR"
    ok "astrbot 已初始化到 $DEPLOY_DIR"
  else
    err "脚本下载失败，初始化中止"
  fi

}

main "$@"
