# A 服务器（中控机）运维架构与安全落地指南 (README.md)

本目录是部署在 **A 服务器（Bastion / Control Node）** 上的集中运维工作区，配合 AGY CLI 与 Ansible 管理下游 **B、C、D、E、F** 服务器。

为了确保 AI Agent 运维的**高安全性、防卡死、可审计**，本方案在架构层面落实了以下 **3 项 SRE 核心安全机制**：

---

## 🛡️ 核心安全架构（必读）

### 1. 操作系统级权限硬隔离（拒绝仅靠 Prompt 软约束）
[`AGENTS.md`](file:///home/antigravity/ops-workspace/AGENTS.md) 中的安全红线是对 AI 的“提示词约束”，但在生产环境中，**绝不能只依赖大模型自觉**。
- **落地方法**：在 B~F 服务器上创建普通用户 `ops`，并使用本仓库提供的 [`sudoers_ops.example`](file:///home/antigravity/ops-workspace/sudoers_ops.example) 配置 `/etc/sudoers.d/ops`：
  ```bash
  # 在 B~F 服务器上以 root 执行：
  visudo -f /etc/sudoers.d/ops
  ```
- **效果**：
  - 所有节点允许免密执行只读诊断命令（如 `systemctl status`、`journalctl`、`docker ps/logs`），避免因提示输入密码导致 Agent 卡死。
  - 按节点角色精细放行变更权限（如仅 B 节点允许 `nginx -t` 和 `systemctl reload nginx`）。
  - 在 **E 服务器（核心数据库）** 上，从 Linux 内核层面剥夺 `ops` 重启数据库或删除数据的 `sudo` 权限，彻底杜绝 AI 误操作删库或重启生产库。

### 2. A 服务器私钥防静态泄露（Passphrase + `ssh-agent` 限时解锁）
A 服务器集中存放了 B~F 的私钥，若存放无密码明文私钥，一旦 A 被攻破将导致全集群沦陷。
- **落地方法**：
  1. 生成 B~F 的 SSH 密钥对时，**务必设置强密码（Passphrase）**：
     ```bash
     ssh-keygen -t ed25519 -f ~/.ssh/keys/id_ed25519_node_b -C "ops@node-b"
     ```
  2. 平时硬盘上的私钥处于加密锁死状态。当你登录 A 服务器准备启动 AGY CLI 进行运维时，开启 `ssh-agent` 并设置 **1 小时内存限时解锁**：
     ```bash
     eval "$(ssh-agent -s)"
     ssh-add -t 3600 ~/.ssh/keys/id_ed25519_*
     ```
  3. 运维结束后可随时手动销毁内存密钥：`ssh-add -D`（或满 1 小时自动失效）。

### 3. 远端命令超时熔断与全量操作审计
- **防僵死熔断**：SSH 的 `ConnectTimeout 10` 仅管控 TCP 握手。为防止远端因磁盘/NFS 故障导致命令挂起，已在 [`AGENTS.md`](file:///home/antigravity/ops-workspace/AGENTS.md) 与初始化脚本中强制规范使用 `timeout 30s ssh <node> "<cmd>"`，并在 [`ansible.cfg`](file:///home/antigravity/ops-workspace/ansible.cfg) 中配置全局超时。
- **黑匣子审计**：[`ansible.cfg`](file:///home/antigravity/ops-workspace/ansible.cfg) 已默认开启 `log_path = ./ansible.log`，Agent 执行的所有批量剧本均留存本地时间戳日志。

---

## 🚀 快速部署步骤

1. **初始化 A 服务器环境**：
   ```bash
   cd ~/ops-workspace
   bash scripts/init-control-node.sh
   ```
2. **填入真实 IP 与私钥**：
   - 将加密后的私钥放入 `~/.ssh/keys/`
   - 编辑 `~/.ssh/config`（模板已由脚本自动从 [`ssh_config.example`](file:///home/antigravity/ops-workspace/ssh_config.example) 复制）填入 B~F 的真实内网/公网 IP。
3. **测试全集群连通性与健康巡检**：
   ```bash
   ansible-playbook playbooks/ping-and-status.yml
   ```
