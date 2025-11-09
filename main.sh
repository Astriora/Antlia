#!/bin/bash
# main.sh - Antlia 仓库脚本入口
# 版本: 2025/11/09

set -euo pipefail
BLUE='\033[34m'
RESET='\033[0m'
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
print_help() {
	cat <<EOF
用法: bash $0 <项目名> [分支] [脚本名] [选项]

参数:
  <项目名>       项目名，例如 AstrBot、Protect
  [分支]         分支名，默认 main
  [脚本名]       脚本名称，例如 AstrBot.sh，默认同项目名加 .sh

选项:
  --GITHUB-URL <url>  自定义 GitHub 代理/镜像 URL
  --ci                CI 模式，自动化部署
  --force             强制覆盖已有目录
  -h, --help          显示帮助
EOF
}

check_curl() {
	if ! command -v curl >/dev/null 2>&1; then
		echo "[ERROR] curl 未安装，请先安装 curl"
		exit 1
	fi
}

# ------------------ 参数解析 ------------------
if [[ $# -lt 1 ]]; then
	print_help
	exit 1
fi

PROJECT="$1"
BRANCH="${2:-main}"
SCRIPT_NAME="${3:-${PROJECT}.sh}"
shift 3 || true

GITHUB_URL=""
CI_MODE=0
FORCE=0
PASS_ARGS=()

while [[ $# -gt 0 ]]; do
	case $1 in
	--GITHUB-URL)
		GITHUB_URL="$2"
		shift 2
		;;
	--ci)
		CI_MODE=1
		shift
		;;
	--force)
		FORCE=1
		shift
		;;
	-h | --help)
		print_help
		exit 0
		;;
	*)
		PASS_ARGS+=("$1")
		shift
		;;
	esac
done

check_curl

# 默认代理
[[ -z "$GITHUB_URL" ]] && GITHUB_URL=""

# 构造 raw 链接
RAW_URL="${GITHUB_URL}https://raw.githubusercontent.com/Astriora/Antlia/refs/heads/${BRANCH}/Script/${PROJECT}/${SCRIPT_NAME}"

info "项目: $PROJECT"
info "分支: $BRANCH"
info "脚本: $SCRIPT_NAME"
info "GitHub URL: $GITHUB_URL"
info "CI_MODE: $CI_MODE"
info "FORCE: $FORCE"
info "脚本下载链接: $RAW_URL"
if [[ $CI_MODE -eq 1 || $FORCE -eq 1 ]]; then
	echo "[INFO] 自动化模式执行脚本..."
	bash <(curl -sSL "$RAW_URL") "${PASS_ARGS[@]}" --force
else
	read -rp "确认下载并执行 $PROJECT 脚本? (y/N): " confirm
	if [[ "$confirm" =~ ^[Yy]$ ]]; then
		bash <(curl -sSL "$RAW_URL") "${PASS_ARGS[@]}"
	else
		echo "已取消"
		exit 0
	fi
fi
