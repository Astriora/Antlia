#!/bin/bash

set -o pipefail

setup_uv_environment() {

  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

  if ! command -v uv >/dev/null 2>&1; then
    err "uv 未找到，请检查安装或重新运行部署脚本"
    return 1
  fi
  return 0
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR"
TMUX_SESSION_ASTRBOT="Astrbot"
CURRENT_USER=$(whoami)
PATH_CONFIG_FILE="$SCRIPT_DIR/path.conf"

# 定义颜色
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
MAGENTA='\033[35m'

info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1" >&2; }
print_title() { echo -e "${BOLD}${CYAN}\n=== $1 ===${RESET}"; }
print_warning() { echo -e "${MAGENTA}[WARNING]${RESET} $1"; }

# 分割线
hr() { echo -e "${CYAN}================================================${RESET}"; }

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

#检查tmux会话是否存在
tmux_session_exists() {
  tmux has-session -t "$1" 2>/dev/null
}

#用于检查关键命令是否存在
check_command() {
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then
      err "关键命令 '$cmd' 未找到"
      return 1
    fi
  done
}

# 停止 AstrBot
stop_service() {
  info "正在停止 '$TMUX_SESSION_ASTRBOT' 相关进程和会话..."
  tmux kill-session -t "$TMUX_SESSION_ASTRBOT" 2>/dev/null
  ok "'$TMUX_SESSION_ASTRBOT' 清理完成"
}

# 后台启动 AstrBot
start_service_background() {
  tmux new-session -d -s "$TMUX_SESSION_ASTRBOT" \
    "cd '$DEPLOY_DIR/AstrBot' && uv run python main.py"
  sleep 1
  ok "AstrBot 已在后台启动"
}

# 前台启动 AstrBot
start_astrbot_interactive() {
  cd "$DEPLOY_DIR/AstrBot" || exit
  uv run python "$DEPLOY_DIR/AstrBot/main.py"
}

# 菜单界面
main_menu() {
  while true; do
    clear
    print_title "AstrBot 管理面板"
    echo -e "${CYAN}用户: ${GREEN}$CURRENT_USER${RESET} | ${CYAN}时间: ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    hr
    astrbot_art
    echo -e "${BOLD}主菜单:${RESET}"
    echo -e "  ${GREEN}1.${RESET} 启动 AstrBot (后台运行)"
    echo -e "  ${GREEN}2.${RESET} 启动 AstrBot (前台运行)"
    echo -e "  ${GREEN}3.${RESET} 附加到 AstrBot 会话"
    hr
    echo -e "  ${RED}4.${RESET} 停止所有服务"
    hr
    echo -e "  ${MAGENTA}q.${RESET} 退出脚本"

    read -rp "请输入您的选择: " choice

    case $choice in
    1)
      if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
        stop_service
      fi
      start_service_background
      echo -e "${GREEN}AstrBot 已启动 ${RESET}"
      read -rp "按 Enter 键返回..."
      ;;
    2)
      clear
      if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
        stop_service
      fi
      start_astrbot_interactive
      echo -e "${GREEN}AstrBot 已停止 ${RESET}"
      read -rp "按 Enter 键返回..."
      ;;
    3)
      if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
        tmux attach -t "$TMUX_SESSION_ASTRBOT"
      else
        print_warning "AstrBot 会话不存在，无法附加"
      fi
      read -rp "按 Enter 键返回..."
      ;;
    4)
      stop_service
      echo -e "${RED}所有服务已停止${RESET}"
      read -rp "按 Enter 键返回..."
      ;;
    q | 0)
      echo -e "${CYAN}退出脚本...${RESET}"
      exit 0
      ;;
    *)
      warn "无效输入，请重试"
      sleep 1
      ;;
    esac
  done
}

# 脚本入口
main() {
  setup_uv_environment
  # 检查必需命令
  if ! check_command tmux uv; then
    exit 1
  fi

  # 参数模式
  if [[ $# -ge 1 ]]; then
    MODE="$1"
    case "$MODE" in
    start)
      if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
        stop_service
      fi
      start_service_background
      ;;
    run)
      if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
        stop_service
      fi
      start_astrbot_interactive
      ;;
    attach)
      if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
        tmux attach -t "$TMUX_SESSION_ASTRBOT"
      else
        print_warning "AstrBot 会话不存在，无法附加"
      fi
      ;;
    stop)
      stop_service
      ;;
    help | -h | --help)
      echo -e "${CYAN}AstrBot 脚本参数帮助:${RESET}"
      echo "  start     - 后台启动 AstrBot (tmux)"
      echo "  run       - 前台运行 AstrBot"
      echo "  attach    - 附加到后台 tmux 会话"
      echo "  stop      - 停止后台 AstrBot"
      echo "  help,-h   - 显示此帮助"
      exit 0
      ;;
    *)
      warn "无效参数: $MODE"
      echo "可用参数: start, run, attach, stop, help"
      exit 1
      ;;
    esac
    exit 0
  fi

  # 无参数进入菜单
  main_menu
}

# 执行主函数
main "$@"
