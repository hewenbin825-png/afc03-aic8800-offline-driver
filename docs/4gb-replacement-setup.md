# AFC03 4 GB 换板实录：离线安装 AIC8800、联网与 SSH 准备

记录日期：2026-09-12。板卡为同型号 MLK-AFH03-AFC03 / RK3576，内存由原板的 2 GB 更换为 4 GB。本次流程记录到首次联网成功和 SSH 连接准备阶段。

## 1. 本次实际确认了什么

| 项目 | 本次新板结果 |
|---|---|
| 系统与架构 | Debian 12、Linux、aarch64 |
| 运行内核 | `6.1.99` |
| 芯片 | RK3576 |
| 系统识别的总内存 | `3901 MiB`，符合 4 GB 配置扣除保留内存后的情况 |
| 本地完整迁移包 | `Bundle integrity OK: 323 files.` |
| AIC8800 预检查 | 两个模块与运行内核匹配，检查通过 |
| 无线网络 | 操作者确认已成功连接，并取得局域网地址 |
| SSH | 服务已响应；电脑严格主机校验发现尚无新板的主机密钥记录，等待现场指纹核对后登录 |
| 新板重启自动联网 | 尚未完成本轮断电重启验收 |
| 修改登录密码 | 已整理 `passwd` 操作，未记录为已经修改成功 |
| 新板模型、NPU、相机、VS Code 断点 | 不在本次已通过项目中，需在新板分别验证 |

旧板的 SSH、模型或相机检查记录只代表旧板，不能直接算作新板验收结果。

## 2. 新板需要准备的文件

先确认厂家已交付可以启动的、适配 4 GB 硬件的官方 Debian BSP。本教程在已能进入系统的新板上安装无线驱动，系统恢复镜像应向板卡厂家取得。

公开可下载的无线驱动包：

- [GitHub 仓库](https://github.com/hewenbin825-png/afc03-aic8800-offline-driver)
- [固定版本 v0.2.0](https://github.com/hewenbin825-png/afc03-aic8800-offline-driver/releases/tag/v0.2.0)
- [完整 Wi-Fi 离线 ZIP](https://github.com/hewenbin825-png/afc03-aic8800-offline-driver/releases/download/v0.2.0/afc03-aic8800-offline-kernel-6.1.99-aarch64-v0.2.0.zip)

ZIP SHA256：

```text
1855937ef0c8449875a9d6a501e16bbbdde407edfbae5f64897f171c102d7d01
```

它包含安装器、两个 AIC8800 模块、11 个固件文件、配套源码和许可证。本次现场使用的本地完整迁移包还包含其他部署材料，323 文件校验来自该迁移包。下面的可复现命令使用公开 Wi-Fi ZIP 的 `install_aic8800_wifi.sh`；该 Release 没有完整迁移包的 `start.sh`，也不包含 RKNN 模型或摄像头例程。

## 3. 先解决命令复制

在板卡图形桌面的终端中使用 Vim 查看命令时，可以这样复制到另一个终端：

1. 在 Vim 按 `Esc`，输入下面的命令并回车：

   ```vim
   :set mouse=
   ```

2. 用鼠标左键拖选要执行的一行命令，让终端处理文字选择。
3. 切到同一板卡桌面的另一个终端，在输入区域按一下鼠标滚轮中键。
4. 检查粘贴内容完整后再按回车执行。

这个设置对当前 Vim 会话生效。也可以按住 `Shift` 再拖选，以使用终端本身的选择功能。[Vim 鼠标说明](https://vimhelp.org/term.txt.html)、[Xfce 终端中键粘贴说明](https://docs.xfce.org/apps/terminal/4.14/usage)。

NoMachine 中普通终端复制和粘贴可用 `Ctrl+Shift+C`、`Ctrl+Shift+V`。首次安装尽量逐条执行命令，避免把提示符、行号或报错输出一起粘贴进去。

## 4. 复制、校验并检查新板

通过 U 盘把 ZIP 复制到新板。用文件管理器解压，确认目录内有 `install_aic8800_wifi.sh`、`SHA256SUMS.txt` 和 `wifi/`，再将该目录放到当前用户主目录并命名为 `afc03-aic8800`。

以下在板卡终端执行：

```bash
cd "$HOME/afc03-aic8800"
sha256sum -c SHA256SUMS.txt
uname -rm
cat /etc/os-release
free -m
sudo bash ./install_aic8800_wifi.sh --check ./wifi
```

SHA256 清单应全部显示 `OK`。驱动检查应显示：

```text
CHECK PASSED: files match the running kernel; no changes made.
```

本次新板读取到 `6.1.99`、`aarch64`、Debian 12 和 `3901 MiB`。4 GB 内存本身不是决定模块能否加载的条件；仍需核对板型、BSP 和模块 `vermagic`。若内核不匹配，应取得对应 BSP 的驱动或重新编译，不使用 `insmod -f`。

预检查还出现过：

```text
No hardware-backed wireless interface currently present (modules may not be loaded yet).
```

这表示检查时还没有无线接口。`--check` 只检查文件和内核，没有执行驱动加载；因此这行信息本身不能用来判定网卡硬件损坏。

## 5. 解压提示“时间在未来”怎么处理

本次解压本地 tar 迁移包时，大量文件提示时间在未来。报告目录显示板卡时钟停留在 4 月，而迁移包内文件日期是 9 月；结合包内容 SHA256 全部通过，可判断本次提示来自时钟偏差。

GNU tar 将这类信息归为时间戳警告。排查时先区分时间戳警告和文件内容校验失败。[GNU tar 说明](https://www.gnu.org/s/tar/manual/html_section/warnings.html)

联网后检查时间：

```bash
date
timedatectl status
```

如果系统已提供可用的网络时间同步服务，可以启用并再次查看：

```bash
sudo timedatectl set-ntp true
timedatectl status
```

`set-ntp true` 会启用已有的时间同步服务，不会替系统安装一个缺失的服务；如提示不支持 NTP，应按 BSP 的时间服务配置排查。以上是校时步骤，本次记录尚未取得新板校时完成的结果。[Debian timedatectl 手册](https://manpages.debian.org/bookworm/systemd/timedatectl.1.en.html)

## 6. 安装无线驱动并连接 Wi-Fi

仅在前面的文件和内核检查通过后执行：

```bash
sudo bash ./install_aic8800_wifi.sh --install ./wifi
```

安装器会备份被替换的文件，安装模块和固件，然后依次加载 `aic_load_fw`、`aic8800_fdrv` 并寻找真实无线接口。成功时应看到：

```text
LIVE LOAD PASSED. Connect and test Wi-Fi before running --persist.
```

接口可能叫 `wlx...`，不要固定假设为 `wlan0`。如果没有出现接口，保留安装输出，并查看 `dmesg`；先解决加载或硬件识别问题，再继续连接。

打开 NetworkManager 的交互界面：

```bash
sudo nmtui
```

选择“激活连接”，选择自己的 Wi-Fi，交互输入密码并连接，然后退出。网络密码不用写进命令行。检查结果：

```bash
nmcli device status
hostname -I
ip route
getent hosts www.baidu.com
```

本次操作者在这一阶段确认新板联网成功。接口已连接、取得 IP、默认路由和 DNS 应分别核查；仅看到网卡名称还不足以证明能访问网络。

## 7. 设置自动加载并安排重启验证

当前 Wi-Fi 可用后执行：

```bash
sudo bash ./install_aic8800_wifi.sh --persist ./wifi
cat /etc/modules-load.d/aic8800.conf
```

在 `sudo nmtui` 的“编辑连接”中打开当前 Wi-Fi 配置，确认“自动连接”已勾选并保存。模块自动加载和网络连接自动激活是两个步骤。

保存工作后正常关机，再断电上电，重新检查 `nmcli device status`、IP 和 DNS。首次联网成功不等于已经通过冷启动回归；这块新板的本轮冷启动结果尚未记录。

## 8. 连接 SSH，保留新板独立身份

板卡终端检查并启动已有的 SSH 服务：

```bash
command -v sshd
sudo systemctl enable --now ssh
systemctl is-active ssh
hostname -I
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

最后一行在板卡本地读取 Ed25519 主机公钥的 SHA256 指纹，供电脑首次连接时核对。若系统没有 `sshd`，应先通过该 Debian BSP 的正式软件源准备 OpenSSH Server，再进行下面的连接。

Windows PowerShell 中，将 `<BOARD_IP>` 替换为上一步获得的新板地址后执行：

```powershell
ssh -o HostKeyAlgorithms=ssh-ed25519 linaro@<BOARD_IP>
```

账号以厂家交付为准。首次连接显示的指纹必须与板卡本地输出一致，再接受新主机密钥并登录。

本次电脑的 SSH 配置启用了严格校验；因为还没有新板主机密钥记录，连接在主机校验阶段停止。它说明 SSH 服务已响应，不代表用户名、密码或公钥认证已经通过。换板后不能把旧主机密钥自动当成新板身份，也不要关闭主机校验来跳过这一步。复用旧 IP 时，应先核对新板指纹，再仅更新对应的旧记录。

建议为新板建立独立 SSH 别名，保留原板条目。主机指纹完成核对并保存后，可在电脑 `~/.ssh/config` 添加：

```sshconfig
Host afc03-new
  HostName <BOARD_IP>
  User linaro
  StrictHostKeyChecking yes
  ServerAliveInterval 20
  ServerAliveCountMax 3
```

已配置自己的 SSH 公钥登录时，可在这一节再设置对应的 `IdentityFile` 和 `IdentitiesOnly yes`。私钥留在电脑，板卡只接收公钥。

以后使用 `ssh afc03-new`；VS Code 的 Remote - SSH 扩展也选择该别名。新板工程目录和 Python 环境部署完成后，再选择正确解释器并验证断点。本次记录不把这些后续动作列为已经完成。

## 9. 修改板卡登录密码

在板卡本地终端，或已登录为普通用户的 SSH 终端中执行：

```bash
passwd
```

按提示依次输入当前密码、新密码、再次输入新密码。输入时屏幕不会显示字符，这是正常现象。出现密码更新成功的提示后才算完成。

该命令修改当前 Linux 用户的登录密码。使用同一账号密码登录的远程桌面需要使用新密码，已经配置的 SSH 公钥认证继续使用原有密钥。实际密码由使用者交互输入，不写入教程、脚本或截图。

## 10. 这次流程带来的改进

先在本机保留安装材料，换板后按“系统与内存检查 → 文件校验 → 模块匹配 → 驱动加载 → 联网 → 自动连接配置 → SSH 身份核验”的顺序推进。Vim 中键粘贴减少了长命令手输错误，时间戳警告也有了明确的排查依据。

本次公开更新的是安装流程和注意事项，v0.2.0 驱动 ZIP 及其 SHA256 保持原样。每块新板仍应保留自己的验证记录，并分别确认重启联网、SSH 登录、模型推理和真实相机出帧。
