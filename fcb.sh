#!/usr/bin/env bash
# ============================================================
# FileCodeBox 管理菜单 (aucrazy-p/fcb-deploy)
# 上游项目: https://github.com/vastsa/FileCodeBox
# 端口仅绑定 127.0.0.1, 公网访问走 1panel 反代, 无需放行端口
# ============================================================

BASE_DIR="/opt/filecodebox-deploy"
DATA_ROOT="/opt/filecodebox"
DATA_DIR="$DATA_ROOT/data"
BACKUP_DIR="$BASE_DIR/backups"
ENV_FILE="$BASE_DIR/.env"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
IMAGE="lanol/filecodebox:latest"
NETWORK="1panel-network"
BIN="/usr/local/bin/fcb"

C_G="\033[32m"; C_Y="\033[33m"; C_R="\033[31m"; C_C="\033[36m"; C_0="\033[0m"
info(){ echo -e "${C_G}[INFO]${C_0} $*"; }
warn(){ echo -e "${C_Y}[WARN]${C_0} $*"; }
err(){ echo -e "${C_R}[ERR ]${C_0} $*"; }

# ---- compose 命令封装 (优先 v2 插件, 回退 v1) ----
if docker compose version >/dev/null 2>&1; then
  dc(){ docker compose -p filecodebox -f "$COMPOSE_FILE" "$@"; }
else
  dc(){ docker-compose -p filecodebox -f "$COMPOSE_FILE" "$@"; }
fi

get_port() {
  local p=""
  [ -f "$ENV_FILE" ] && p=$(grep '^HOST_PORT=' "$ENV_FILE" | head -n1 | cut -d= -f2- | tr -d ' \r')
  echo "${p:-12345}"
}

gen_compose() {
  local port; port=$(get_port)
  {
    echo "name: filecodebox"
    echo ""
    echo "services:"
    echo "  filecodebox:"
    echo "    image: $IMAGE"
    echo "    container_name: filecodebox"
    echo "    restart: unless-stopped"
    echo "    ports:"
    echo "      - \"127.0.0.1:${port}:12345\""
    echo "    volumes:"
    echo "      - ${DATA_DIR}:/app/data"
    echo "    environment:"
    echo "      - APP_ENV=production"
    echo "      - WORKERS=1"
    echo "      - LOG_LEVEL=warning"
    echo "      - ACCESS_LOG=false"
    echo "    logging:"
    echo "      driver: json-file"
    echo "      options:"
    echo "        max-size: \"10m\""
    echo "        max-file: \"3\""
  } > "$COMPOSE_FILE"
  # 1panel 网络存在时自动加入, 供 OpenResty 用容器名反代
  if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    {
      echo ""
      echo "    networks:"
      echo "      - $NETWORK"
      echo ""
      echo "networks:"
      echo "  $NETWORK:"
      echo "    external: true"
    } >> "$COMPOSE_FILE"
    info "已加入 docker 网络 $NETWORK (1panel OpenResty 可用容器名反代)"
  else
    warn "未检测到 $NETWORK 网络, 仅绑定 127.0.0.1:${port}"
  fi
}

probe() {
  local port; port=$(get_port)
  local code
  for _ in $(seq 1 10); do
    code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://127.0.0.1:${port}/" 2>/dev/null)
    if [ -n "$code" ] && [ "$code" != "000" ]; then echo "$code"; return 0; fi
    sleep 1
  done
  echo "000"
}

container_status() {
  docker inspect -f '{{.State.Status}}' filecodebox 2>/dev/null || echo "not-found"
}

# ---------- 安装完成后打印关键信息 ----------
print_key_info() {
  local port; port=$(get_port)
  echo ""
  echo -e "${C_C}================== 关键信息 ==================${C_0}"
  echo -e " 访问地址(本机) : ${C_G}http://127.0.0.1:${port}${C_0}"
  echo -e " 首次部署       : 浏览器访问站点, 完成初始化并设置管理员密码"
  echo -e " 上传限制       : 默认单文件 ${C_Y}10MB${C_0}, 管理面板 /#/admin -> 系统设置"
  echo -e "                  upload_size(字节) / enable_chunk(分片上传,大文件建议开)"
  echo -e " 1panel 反代    : 网站类型选反向代理, 地址 ${C_G}http://filecodebox:12345${C_0}"
  echo -e "                  (需与容器同网络); conf 中 client_max_body_size 与"
  echo -e "                  upload_size 保持一致或更大, 防止 413"
  echo -e " 数据目录       : $DATA_DIR"
  echo -e " 备份目录       : $BACKUP_DIR (菜单 9 备份, 保留最近 10 份)"
  echo -e " 管理命令       : ${C_G}fcb${C_0}  (等价: bash $BASE_DIR/fcb.sh)"
  echo -e " 防火墙         : 无需放行 ${port}, 端口仅绑定 127.0.0.1"
  echo -e "${C_C}==============================================${C_0}"
}

# ---------- 1) 安装 / 更新 ----------
do_install() {
  if [ ! -f "$ENV_FILE" ]; then
    read -rp "请设置宿主机端口 [默认 12345]: " p
    p=${p:-12345}
    if ! [[ "$p" =~ ^[0-9]+$ ]] || [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
      err "端口不合法: $p"; return 1
    fi
    mkdir -p "$BASE_DIR" "$DATA_DIR" "$BACKUP_DIR"
    echo "HOST_PORT=$p" > "$ENV_FILE"
    info "端口已设为 $p (仅绑定 127.0.0.1)"
  else
    info "已存在配置, 端口 $(get_port), 执行更新..."
  fi
  gen_compose
  info "拉取镜像 $IMAGE ..."
  if ! docker pull "$IMAGE"; then
    err "镜像拉取失败, 请检查网络或为 Docker 配置镜像加速后重试"
    return 1
  fi
  dc up -d || { err "容器启动失败, 可用菜单 6 查看日志"; return 1; }
  local port code; port=$(get_port); code=$(probe)
  if [ "$code" != "000" ]; then
    info "服务已就绪 (HTTP $code)"
  else
    warn "容器已启动但本机探活未通过, 稍后可用菜单 2 查看"
  fi
  print_key_info
}

# ---------- 2) 状态 ----------
do_status() {
  local st; st=$(container_status)
  local port; port=$(get_port)
  echo -e "${C_C}---------------- 状态 ----------------${C_0}"
  if [ "$st" = "running" ]; then
    echo -e " 容器: ${C_G}运行中${C_0}"
  elif [ "$st" = "not-found" ]; then
    echo -e " 容器: ${C_R}未安装${C_0}"
  else
    echo -e " 容器: ${C_Y}$st${C_0}"
  fi
  echo " 端口: 127.0.0.1:${port} (仅本机)"
  echo " 数据: $DATA_DIR"
  [ -d "$DATA_DIR" ] && echo " 占用: $(du -sh "$DATA_DIR" | cut -f1)"
  if [ "$st" = "running" ]; then
    local code; code=$(probe)
    if [ "$code" != "000" ]; then
      echo -e " 探活: ${C_G}HTTP $code OK${C_0}"
    else
      echo -e " 探活: ${C_R}失败${C_0} (可用菜单 6 查日志)"
    fi
  fi
  echo -e "${C_C}--------------------------------------${C_0}"
}

# ---------- 7) 更改端口 ----------
do_change_port() {
  local old; old=$(get_port)
  read -rp "当前端口 $old, 输入新端口: " np
  if ! [[ "$np" =~ ^[0-9]+$ ]] || [ "$np" -lt 1 ] || [ "$np" -gt 65535 ]; then
    err "端口不合法"; return 1
  fi
  [ "$np" = "$old" ] && { warn "端口未变化"; return 0; }
  if command -v ss >/dev/null 2>&1 && ss -tln | grep -q ":${np} "; then
    err "端口 $np 已被占用"; return 1
  fi
  sed -i "s/^HOST_PORT=.*/HOST_PORT=$np/" "$ENV_FILE"
  gen_compose
  dc up -d && info "端口已切换为 $np (127.0.0.1), 记得同步更新 1panel 反代地址"
}

# ---------- 8) 重置后台密码 ----------
do_passwd() {
  local db="$DATA_DIR/filecodebox.db"
  if [ ! -f "$db" ]; then
    warn "未找到数据库, 站点可能尚未初始化, 浏览器直接访问即可设置密码"
    return 0
  fi
  warn "官方未提供忘记密码后的直接重置命令(admin_token 为哈希存储)。"
  warn "本操作通过移除数据库让站点重新进入初始化向导:"
  warn "  - 所有系统配置与分享记录将丢失(文件本体保留在磁盘)"
  warn "  - 旧数据库会自动备份, 可事后找回"
  read -rp "输入 YES 确认重置: " c
  [ "$c" = "YES" ] || { info "已取消"; return 0; }
  local ts; ts=$(date +%Y%m%d%H%M%S)
  dc stop
  local s
  for s in "" "-wal" "-shm"; do
    [ -f "${db}${s}" ] && mv "${db}${s}" "${db}${s}.bak-$ts"
  done
  dc up -d
  info "已重置, 浏览器访问站点重新设置管理员密码"
  info "旧数据库备份: ${db}.bak-$ts (找回数据时可换回文件名)"
}

# ---------- 9) 备份数据 ----------
do_backup() {
  mkdir -p "$BACKUP_DIR"
  local stop=0 a
  read -rp "备份时暂停容器以保证数据一致? [Y/n]: " a
  case ${a:-Y} in [Yy]*) dc stop; stop=1 ;; esac
  local ts f
  ts=$(date +%Y%m%d-%H%M%S)
  f="$BACKUP_DIR/fcb-backup-$ts.tar.gz"
  if tar -czf "$f" -C "$DATA_ROOT" data; then
    info "备份完成: $f ($(du -sh "$f" | cut -f1))"
  else
    err "备份失败"
  fi
  [ "$stop" = 1 ] && dc up -d
  # 保留最近 10 份
  ls -1t "$BACKUP_DIR"/fcb-backup-*.tar.gz 2>/dev/null | tail -n +11 | while read -r old; do
    rm -f "$old"
  done
}

# ---------- 10) 恢复数据 ----------
do_restore() {
  local list
  list=$(ls -1t "$BACKUP_DIR"/fcb-backup-*.tar.gz 2>/dev/null) || { err "无可用备份"; return 1; }
  echo "可用备份(按时间倒序):"
  echo "$list" | nl -w2 -s') '
  read -rp "选择编号: " n
  local sel; sel=$(echo "$list" | sed -n "${n}p")
  [ -f "$sel" ] || { err "无效选择"; return 1; }
  warn "将用 $sel 覆盖当前数据目录"
  read -rp "输入 YES 确认: " c
  [ "$c" = "YES" ] || { info "已取消"; return 0; }
  local ts; ts=$(date +%Y%m%d%H%M%S)
  dc stop
  [ -d "$DATA_DIR" ] && mv "$DATA_DIR" "${DATA_DIR}.bak-$ts"
  tar -xzf "$sel" -C "$DATA_ROOT"
  dc up -d
  info "恢复完成, 当前数据已另存为 ${DATA_DIR}.bak-$ts"
}

# ---------- 11) 卸载 ----------
do_uninstall() {
  warn "将停止并移除 filecodebox 容器与 compose 项目"
  read -rp "输入 YES 确认: " c
  [ "$c" = "YES" ] || { info "已取消"; return 0; }
  dc down 2>/dev/null || true
  read -rp "删除镜像 $IMAGE? [y/N]: " a
  case ${a:-N} in [Yy]*) docker rmi "$IMAGE" 2>/dev/null || true ;; esac
  read -rp "删除数据目录 $DATA_ROOT? [y/N]: " a
  case ${a:-N} in
    [Yy]*)
      read -rp "数据将不可恢复, 再输入 DELETE 二次确认: " c2
      [ "$c2" = "DELETE" ] && rm -rf "$DATA_ROOT" && info "数据已删除"
      ;;
    *) info "数据保留在 $DATA_ROOT" ;;
  esac
  read -rp "删除管理脚本 $BASE_DIR 与 $BIN? [y/N]: " a
  case ${a:-N} in
    [Yy]*) rm -rf "$BASE_DIR"; rm -f "$BIN"; info "已卸载管理脚本, 菜单退出"; exit 0 ;;
  esac
  info "卸载完成"
}

# ---------- 菜单 ----------
show_menu() {
  clear
  local st port
  st=$(container_status); port=$(get_port)
  echo -e "${C_C}======== FileCodeBox 管理菜单 ========${C_0}"
  if [ "$st" = "running" ]; then
    echo -e " 状态: ${C_G}运行中${C_0}  端口: 127.0.0.1:${port}"
  else
    echo -e " 状态: ${C_R}${st}${C_0}"
  fi
  echo -e "${C_C}======================================${C_0}"
  echo " 1) 安装 / 更新"
  echo " 2) 状态"
  echo " 3) 启动"
  echo " 4) 停止"
  echo " 5) 重启"
  echo " 6) 查看日志"
  echo " 7) 更改端口"
  echo " 8) 重置后台密码(重新初始化)"
  echo " 9) 备份数据"
  echo " 10) 恢复数据"
  echo " 11) 卸载"
  echo " 0) 退出"
  echo -e "${C_C}======================================${C_0}"
}

case_main() {
  case "$1" in
    1) do_install ;;
    2) do_status ;;
    3) dc up -d && info "已启动" ;;
    4) dc stop && info "已停止" ;;
    5) dc restart && info "已重启" ;;
    6) dc logs -f --tail 200 ;;
    7) do_change_port ;;
    8) do_passwd ;;
    9) do_backup ;;
    10) do_restore ;;
    11) do_uninstall ;;
    0) exit 0 ;;
    *) ;;
  esac
}

# ---- 以下顶层逻辑仅在直接执行时生效 (source 时跳过, 便于函数测试) ----
if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then

  # 支持非交互调用: fcb.sh start / fcb.sh status ...
  if [ -n "${1:-}" ] && [ "${1:-}" != "menu" ]; then
    case_main "${1:-}"
    exit $?
  fi

  if [ "$(id -u)" -ne 0 ]; then
    err "请用 root 运行 (sudo fcb)"
    exit 1
  fi

  while true; do
    show_menu
    read -rp "请选择: " c
    case_main "$c"
    [ "$c" = "0" ] && break
    read -rp "回车返回菜单..." _
  done

fi
