#!/usr/bin/env bash
# ============================================================
# FileCodeBox 一键安装入口 (aucrazy-p/fcb-deploy)
# 用法: curl -fsSL https://raw.githubusercontent.com/aucrazy-p/fcb-deploy/main/install.sh | bash
# 或带自定义下载源: ... | bash -s -- https://your-mirror/fcb.sh
# ============================================================
set -e

REPO="aucrazy-p/fcb-deploy"
BRANCH="main"
BASE_DIR="/opt/filecodebox-deploy"
BIN="/usr/local/bin/fcb"

info(){ echo -e "\033[32m[INFO]\033[0m $*"; }
err(){ echo -e "\033[31m[ERR ]\033[0m $*"; }

[ "$(id -u)" -eq 0 ] || { err "请用 root 运行"; exit 1; }

# ---- docker 检测 ----
if ! command -v docker >/dev/null 2>&1; then
  err "未检测到 docker"
  if [ -t 0 ]; then
    read -rp "是否自动安装 docker (get.docker.com)? [Y/n]: " a
    case ${a:-Y} in
      [Yy]*) curl -fsSL https://get.docker.com | sh || { err "docker 安装失败, 请手动安装后重跑"; exit 1; } ;;
      *) exit 1 ;;
    esac
  else
    # curl|bash 管道模式下无法交互, 给出手动命令
    err "请先手动安装 docker 后重跑: curl -fsSL https://get.docker.com | sh"
    exit 1
  fi
fi
info "docker: $(docker --version)"

# docker compose 插件检测
if docker compose version >/dev/null 2>&1; then
  info "compose: $(docker compose version --short)"
elif command -v docker-compose >/dev/null 2>&1; then
  info "compose: docker-compose v1"
else
  err "未检测到 docker compose 插件, 请安装 docker-compose-plugin 后重跑"
  exit 1
fi

# ---- 下载 fcb.sh (多源回退, 下载后语法校验) ----
mkdir -p "$BASE_DIR"
TMP="$BASE_DIR/.fcb.sh.tmp"
CUSTOM="${1:-}"
URLS=(
  "https://raw.githubusercontent.com/${REPO}/${BRANCH}/fcb.sh"
  "https://cdn.jsdelivr.net/gh/${REPO}@${BRANCH}/fcb.sh"
)
[ -n "$CUSTOM" ] && URLS=("$CUSTOM" "${URLS[@]}")

ok=""
for u in "${URLS[@]}"; do
  info "尝试下载: $u"
  if curl -fsSL "$u" -o "$TMP" && bash -n "$TMP" 2>/dev/null; then
    ok="$u"; break
  fi
done
[ -n "$ok" ] || { err "所有下载源均失败, 请检查网络或用参数指定源: install.sh <url>"; exit 1; }

mv "$TMP" "$BASE_DIR/fcb.sh"
chmod +x "$BASE_DIR/fcb.sh"
ln -sf "$BASE_DIR/fcb.sh" "$BIN"

info "脚本已更新: $BASE_DIR/fcb.sh (来源: $ok)"

# ---- 打印关键信息 ----
echo ""
echo -e "\033[36m================== 安装完成 ==================\033[0m"
echo -e " 脚本位置 : $BASE_DIR/fcb.sh"
echo -e " 管理命令 : \033[32mfcb\033[0m   (等价: bash $BASE_DIR/fcb.sh)"
echo -e " 下一步   : 运行 \033[32mfcb\033[0m 进入菜单, 选 1) 安装 / 更新"
echo -e " 说明     : 安装容器后脚本会打印访问地址/上传限制/反代指路等关键信息"
echo -e "\033[36m==============================================\033[0m"
