# fcb-deploy — FileCodeBox 一键部署与管理

为 [vastsa/FileCodeBox](https://github.com/vastsa/FileCodeBox)（文件快递柜——匿名口令分享文本/文件）提供的 VPS 一键部署脚本与管理菜单。

设计目标：

- **一键安装**：裸 Linux VPS 一条命令拉起，无需面板依赖
- **端口安全**：容器端口仅绑定 `127.0.0.1`，防火墙无需放行，公网访问走 1panel/OpenResty 反代
- **菜单管理**：安装/更新/启停/日志/改端口/重置密码/备份/恢复/卸载，全在一个菜单里
- **版本跟随 latest**：官方镜像 `lanol/filecodebox:latest`

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/aucrazy-p/fcb-deploy/main/install.sh | bash
```

- 未安装 docker 时会提示先手动安装：`curl -fsSL https://get.docker.com | sh`
- raw 直连不稳时可换源：

```bash
curl -fsSL https://raw.githubusercontent.com/aucrazy-p/fcb-deploy/main/install.sh | bash -s -- https://cdn.jsdelivr.net/gh/aucrazy-p/fcb-deploy@main/fcb.sh
```

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

## 1panel 反代参考（手动配置）

1. 确认容器已加入 `1panel-network`（fcb.sh 检测到该网络会自动加入）
2. 1panel → 网站 → 创建网站 → **反向代理**，代理地址填 `http://filecodebox:12345`（容器名互访；若不同网络则填宿主机内网 IP:端口）
3. 网站 SSL 页签申请证书并开启强制 HTTPS
4. 网站配置文件（conf）的 server 块加一行，防止大文件 413：

```nginx
client_max_body_size 100m;   # 与 upload_size 保持一致或更大
```

5. 确认反代传递真实 IP（1panel 默认模板已带）：

```nginx
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

## 上传容量与分片上传（管理面板设置）

官方默认**单文件 10MB**，按需在管理面板调整：

1. 访问站点 `/#/admin`，用管理员密码登录
2. 进入「系统设置」：
   - `upload_size`：单文件上限，单位**字节**（100MB = `104857600`）
   - `enable_chunk`：分片上传，设为 `1` 开启（大文件建议开启）
3. 反代侧 `client_max_body_size` 同步放宽（见上节）

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
