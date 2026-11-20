# fcb-deploy — FileCodeBox 一键部署与管理

为 [vastsa/FileCodeBox](https://github.com/vastsa/FileCodeBox)（文件快递柜——匿名口令分享文本/文件）提供的 VPS 一键部署脚本与管理菜单。

设计目标：

- **一键安装**：裸 Linux VPS 一条命令拉起，无需面板依赖
- **端口安全**：容器端口仅绑定 `127.0.0.1`，防火墙无需放行，公网访问走 1panel/OpenResty 反代
- **菜单管理**：安装/更新/启停/日志/改端口/重置密码/备份/恢复/卸载，全在一个菜单里
- **版本跟随 latest**：官方镜像 `lanol/filecodebox:latest`

## 一键安装

国际网络 / 有代理：

```bash
curl -fsSL https://raw.githubusercontent.com/aucrazy-p/fcb-deploy/main/install.sh | bash
```

国内 VPS（raw 直连不通时，走 jsDelivr CDN）：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/aucrazy-p/fcb-deploy@main/install.sh | bash
```

- 两个入口任选其一；install.sh 内部下载 `fcb.sh` 时自动多源回退（raw 超时 5 秒即切 jsDelivr），国内 VPS 用任一入口都能装完
- 未安装 docker 时会提示先手动安装：`curl -fsSL https://get.docker.com | sh`
- jsDelivr 有 CDN 缓存（最长约 12 小时），更新后如未生效可等缓存刷新或用 raw 入口

安装完成后运行 `fcb` 进入管理菜单（等价 `bash /opt/filecodebox-deploy/fcb.sh`），选 `1) 安装 / 更新`。

## 管理菜单

```
======== FileCodeBox 管理菜单 ========
 1) 安装 / 更新
 2) 状态
 3) 启动            6) 查看日志
 4) 停止            7) 更改端口
 5) 重启            8) 重置后台密码(重新初始化)
 9) 备份数据        10) 恢复数据        11) 卸载
 0) 退出
======================================
```

也支持非交互子命令：`fcb status` / `fcb start` / `fcb stop` / `fcb restart` / `fcb logs`。

安装完成后脚本会打印关键信息：本机访问地址、初始化入口、上传限制修改入口、反代指路、数据/备份目录。

## 目录结构（VPS 上）

| 路径 | 用途 |
|---|---|
| `/opt/filecodebox-deploy/fcb.sh` | 管理菜单脚本（`/usr/local/bin/fcb` 软链） |
| `/opt/filecodebox-deploy/.env` | 配置（`HOST_PORT` 宿主端口） |
| `/opt/filecodebox-deploy/docker-compose.yml` | 实际 compose（由 fcb.sh 生成） |
| `/opt/filecodebox-deploy/backups/` | 备份（保留最近 10 份） |
| `/opt/filecodebox/data/` | 数据目录（挂载到容器 `/app/data`） |

## 1panel 反代参考（手动配置，2026-11-20 实测）

1. 1panel → 网站 → 创建网站 → **反向代理**，代理地址填 **`http://127.0.0.1:12345`**（实测可用：1panel OpenResty 可直达宿主机回环，容器端口只绑 `127.0.0.1` 正好命中）
2. 若 127.0.0.1 不通（OpenResty 容器网络不同时），备选容器名 `http://filecodebox:12345`——前提是容器已加入 `1panel-network`（fcb.sh 检测到该网络会自动加入）
3. 网站 SSL 页签申请证书并开启强制 HTTPS
4. `client_max_body_size` 加在**主配置 server 级**即可（对所有 location 生效，防大文件 413）：

```nginx
client_max_body_size 100m;   # 与 upload_size 保持一致或更大
```

5. 1panel 反代的 `location /` 块不在主配置文件里，在 `include /www/sites/<域名>/proxy/*.conf` 引入的单独 conf 中——**不要**在主配置里再写一个 `location /`（nginx 会报 duplicate location）
6. 确认反代传递真实 IP（1panel 默认模板已带）：

```nginx
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

## 上传容量与分片上传（v3 实测界面）

v3 起**初始化向导可直接设置**大部分参数，后续在管理面板调整：

**初始化向导（首次访问站点时）：**
- 单文件大小限制：直接选数值和单位（如 100 MB）
- 启用分片上传：勾选即开
- 上传频率：默认 10 次/分钟——**开了分片建议调大到 60+**，否则一个 100MB 文件切几十片会被限流卡速

**后续调整（`/#/admin` 管理面板 → 系统设置）：**

| 配置项 | 单位/说明 |
|---|---|
| `upload_size` | 字节（100MB = `104857600`） |
| `enable_chunk` | `1` 开分片 |
| `storage_limit` | 字节，**总磁盘配额**（1GB = `1073741824`），`0` 不限；超限上传返回 HTTP 507，上传前原子预留，并发不超卖 |

**反代侧**：`client_max_body_size` 同步放宽（见上节）；分片开启后单片小，413 风险基本消失。

注意：这些配置存在数据库中，请在面板修改，不要直写数据库。

## 重置后台密码（菜单 8）

官方 `admin_token` 为哈希存储，无"忘记密码"直接重置命令。菜单 8 通过移除数据库（自动备份）让站点重新进入初始化向导：**所有配置与分享记录将丢失，文件本体保留**。

## 备份与恢复（菜单 9 / 10）

- 备份打包整个数据目录（含 SQLite 数据库与文件），默认暂停容器保证一致性，保留最近 10 份
- 恢复前现数据目录自动转 `.bak`，可回退

## 卸载（菜单 11）

容器移除 → 可选删除镜像 / 数据目录 / 管理脚本，均有确认保护。

## 免责声明

本项目仅为部署辅助脚本，上游软件基于 LGPL-3.0 发布。请勿用于违法内容分享，部署者自行承担内容合规责任。
