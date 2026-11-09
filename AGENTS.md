# 集群运维中控规范 (AGENTS.md)

> 本工作区运行在 **A 服务器（中控机 / 堡垒机）** 上，用于集中管理和运维 B、C、D、E、F 五台下游服务器。
> AI Agent 在执行任何远程运维任务前，**必须先阅读并严格遵守本文档中的所有拓扑定义与安全红线**。

---

## 1. 服务器拓扑清单 (Server Inventory)

所有受管服务器均已在 `~/.ssh/config` 和 [`inventory/hosts.yml`](file:///home/antigravity/ops-workspace/inventory/hosts.yml) 中配置好免密登录别名，**请直接使用 SSH 别名或 Ansible 组名进行操作，不要硬编码 IP**：

| 节点代号 | SSH 别名 (`Host`) | Ansible 分组 | 核心角色 / 运行服务 | 关键目录 | 风险等级 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **A (本机)** | `localhost` | `control` | 运维中控机、Ansible 控制节点 | `~/ops-workspace` | 中 |
| **B 服务器** | `node-b` | `gateway` | Nginx 反向代理 / 网关入口 / SSL 证书 | `/etc/nginx`, `/var/log/nginx` | 高 |
| **C 服务器** | `node-c` | `app_servers` | 业务应用节点 1 (Web / API 容器) | `/opt/app`, `/var/log/app` | 中 |
| **D 服务器** | `node-d` | `app_servers` | 业务应用节点 2 (Web / API 容器) | `/opt/app`, `/var/log/app` | 中 |
| **E 服务器** | `node-e` | `databases` | 主数据库 / Redis 缓存节点 | `/var/lib/postgresql`, `/var/lib/mysql` | **极高** |
| **F 服务器** | `node-f` | `workers` | 异步任务 / 定时任务 / 备份存储节点 | `/opt/workers`, `/data/backups` | 低 |

*(注：请根据实际业务情况修改上表中的角色与关键目录)*

---

## 2. 运维安全红线 (Safety Guardrails)

### 🟢 允许直接执行的操作（只读与诊断）
以下操作无需反复询问，可直接通过 `ssh <alias> "<cmd>"` 或 Ansible 执行：
- 查看系统负载、内存、磁盘空间：`uptime`, `free -h`, `df -h`, `top -bn1`
- 查看服务与容器状态：`systemctl status <service>`, `docker ps`, `docker stats --no-stream`
- 查看与检索日志：`journalctl -u <service> -n 100 --no-pager`, `tail -n 100`, `grep`
- 查看网络与端口监听：`ss -tulpn`, `ping`, `curl -I`
- Ansible 干跑模式检查：`ansible-playbook <playbook.yml> --check --diff`

### 🟡 必须先备份或干跑预览的操作（变更类）
- **修改任何配置文件前**（如 Nginx、systemd、环境变量）：
  1. 必须在远端或本地保留带时间戳的备份（例如 `cp nginx.conf nginx.conf.bak.$(date +%F_%H%M%S)`）。
  2. 修改 Nginx / Caddy 等网关配置后，**必须先执行语法检查**（如 `nginx -t`），确认无误后优先使用平滑重载（`systemctl reload nginx`），而非直接 `restart`。
- **批量操作多台机器时**：优先使用 `playbooks/` 下的 Ansible Playbook，并先执行 `--check --diff` 展示变更内容。

### 🔴 绝对禁止未经用户明确确认的操作（高危红线）
以下操作**必须先在对话中向用户说明影响范围，获得明确指令后才能执行**：
1. **禁止在 E 服务器（数据库节点）** 执行重启数据库服务、`DROP` / `TRUNCATE` / 无条件 `DELETE`、或修改数据目录权限。
2. **禁止修改 SSH 服务端配置**（`/etc/ssh/sshd_config`）、`~/.ssh/authorized_keys` 或防火墙的 22 端口规则（防止把自己锁在门外）。
3. **禁止执行破坏性删除命令**：如 `rm -rf`、清理未确认的 Docker 数据卷（`docker volume prune` / `docker system prune -a --volumes`）。
4. **禁止在远程命令中运行交互式或无上限输出命令**：如不带参数的 `top`、`htop`、`tail -f`、`less`、`vim`（会导致 SSH 会话挂起卡死）。

---

## 3. 推荐运维工作流与硬性执行规范 (Standard Workflow)

1. **单机快速排查（必须加 `timeout` 防远端僵死）**：
   SSH 的 `ConnectTimeout` 仅限制握手时间。为防止远端因 IO/NFS 卡死导致会话永久挂起，执行单机 SSH 命令时**必须在最前面加上 `timeout 30s`**：
   ```bash
   timeout 30s ssh node-b "sudo nginx -t && sudo systemctl status nginx --no-pager"
   ```
2. **多机批量巡检（自带超时与审计日志）**：
   运行内置的只读巡检 Playbook（所有执行记录会自动写入 `ansible.log`）：
   ```bash
   ansible-playbook playbooks/ping-and-status.yml
   ```
3. **操作系统级权限边界（OS-Level Enforcement）**：
   受管节点 B~F 的 `ops` 用户已通过 `/etc/sudoers.d/ops`（参考 [`sudoers_ops.example`](file:///home/antigravity/ops-workspace/sudoers_ops.example)）实施最小权限白名单控制。若执行某个 `sudo` 命令返回权限拒绝，说明已触及系统级安全边界，**严禁尝试绕过或提权**，请立即向用户汇报。
4. **新增运维脚本或配置**：
   所有新编写的脚本请放入 `scripts/`，Ansible 剧本放入 `playbooks/`，并在测试通过后提交 Git 记录，确保所有运维动作可追溯、可回滚。
