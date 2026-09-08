# AFC03（RK3576）AIC8800 无线驱动离线安装实录

> 适用实测环境：MLK-AFH03-AFC03、Debian 12、AArch64、Linux `6.1.99`。  
> 预编译 `.ko` 只允许在 `uname -r` 与模块 `vermagic` 第一项完全一致时使用。本文不包含相机、MIPI、RKNN 或视觉模型内容。

## 1. 这次遇到的问题

1. U 盘已被系统识别，但挂载命令写错：`mkdir -p/mnt/usb` 少了空格，`/ESD-USB` 又把卷标误当成设备路径。
2. 板卡本地终端与 Vim 不方便复制粘贴，长命令容易输错。
3. 无线模块是预编译内核模块，不能不检查版本就加载。
4. 两个模块实际加载成功，但旧脚本只检查 `wlan0`；板卡真实接口叫 `wlx<MAC>`，因此被误报为失败。
5. `depmod` 因 BSP 缺少 `modules.order`、`modules.builtin` 等文件产生警告，需要结合模块依赖、`dmesg` 和接口状态判断。
6. 联网后板卡浏览器仍无法使用，但 SSH 服务可以独立启用，所以改用 Windows VS Code Remote-SSH 调试。

最终结果：AIC8800 模块加载成功，真实无线接口出现，板卡取得地址并能联网，Windows 通过 SSH/VS Code 连接成功。

## 2. 离线包结构

发布候选包只包含无线驱动相关内容：

```text
afc03-aic8800-offline-kernel-6.1.99-aarch64-vX.Y.Z/
├─ README.md
├─ AFC03_AIC8800_COMMANDS.txt
├─ install_aic8800_wifi.sh
├─ RELEASE_STATUS.txt
├─ SHA256SUMS.txt
├─ LICENSES/
│  ├─ INSTALLER_LICENSE.txt
│  └─ THIRD_PARTY_STATUS.md
└─ wifi/
   ├─ modules/
   │  ├─ aic_load_fw.ko
   │  └─ aic8800_fdrv.ko
   ├─ firmware/
   └─ source/
```

其中 `source/` 是随板资料中的驱动源文件副本，构建生成的 `.o`、`.ko`、`.a`、`.mod` 和 `modules.order` 不重复收录。

## 3. U 盘挂载与校验

先确认设备名：

```bash
lsblk -f
```

假设本次仍显示 U 盘分区为 `/dev/sda1`：

```bash
sudo mkdir -p /mnt/usb
sudo mount -o ro /dev/sda1 /mnt/usb
findmnt /mnt/usb
ls -lah /mnt/usb
```

把包复制到用户目录。将下面的目录名替换为实际版本：

```bash
cp -a /mnt/usb/afc03-aic8800-offline-kernel-6.1.99-aarch64-vX.Y.Z "$HOME/afc03-aic8800"
sync
cd "$HOME/afc03-aic8800"
sha256sum -c SHA256SUMS.txt
```

必须全部显示 `OK`。有任何 `FAILED` 都不要继续安装。

## 4. 只读检查

先看运行环境：

```bash
uname -rm
cat /etc/os-release
```

再执行安装器的只读模式：

```bash
cd "$HOME/afc03-aic8800"
sudo bash ./install_aic8800_wifi.sh --check ./wifi
```

脚本会读取：

- 当前 `uname -r`；
- `aic_load_fw.ko` 的 `vermagic`；
- `aic8800_fdrv.ko` 的 `vermagic`；
- 固件文件数量。

只有明确出现：

```text
CHECK PASSED: files match the running kernel; no changes made.
```

才允许继续。若版本不一致，必须使用与当前 BSP 完全匹配的源码、配置和交叉工具链重新编译，禁止 `insmod -f`。

## 5. 临时安装和加载

```bash
cd "$HOME/afc03-aic8800"
sudo bash ./install_aic8800_wifi.sh --install ./wifi
```

安装器会：

- 备份即将替换的文件到 `/root/afc03-backup-时间戳`；
- 安装模块到 `/lib/modules/$(uname -r)/extra/aic8800/`；
- 安装固件到这套 BSP 实际使用的 `/vendor/etc/firmware/`；
- 执行 `depmod -a`；
- 依次加载 `aic_load_fw` 和 `aic8800_fdrv`；
- 自动寻找 `/sys/class/net/*/wireless`，不再写死 `wlan0`。

交叉检查：

```bash
lsmod | grep -E 'aic8800_fdrv|aic_load_fw'
modprobe --show-depends aic8800_fdrv
dmesg | tail -n 150
```

取得真实无线接口：

```bash
WIFI_IF="$(for p in /sys/class/net/*; do [ -d "$p/wireless" ] && basename "$p"; done | head -n 1)"
printf 'Wi-Fi interface: %s\n' "$WIFI_IF"
ip -brief link show dev "$WIFI_IF"
```

如果 `WIFI_IF` 为空，停止，不执行持久化。

## 6. 连接 Wi-Fi

板卡有 NetworkManager 时，最简单的方法是：

```bash
sudo nmtui
```

连接后验证：

```bash
ip -brief address show dev "$WIFI_IF"
ip route
ping -c 4 223.5.5.5
ping -c 4 www.baidu.com
```

四个验收点应分开判断：驱动已加载、接口已出现、已经获得 IP、DNS 可以解析。

不要把 SSID 和密码写进公开脚本。若必须使用 `wpa_supplicant.conf`，文件权限至少设为 `600`，发布截图前遮挡凭据。

## 7. 设置开机加载

只有本次联网稳定后才执行：

```bash
cd "$HOME/afc03-aic8800"
sudo bash ./install_aic8800_wifi.sh --persist ./wifi
cat /etc/modules-load.d/aic8800.conf
```

该模式会再次确认：

- 两个模块已加载；
- 至少存在一个硬件无线接口；
- 已安装模块与离线包逐字节一致；
- 已安装固件与离线包逐字节一致；
- `modprobe` 能解析模块依赖。

然后才创建 `/etc/modules-load.d/aic8800.conf`。最后必须重启回归：

```bash
sudo reboot
```

重启后：

```bash
lsmod | grep -E 'aic8800_fdrv|aic_load_fw'
WIFI_IF="$(for p in /sys/class/net/*; do [ -d "$p/wireless" ] && basename "$p"; done | head -n 1)"
ip -brief address show dev "$WIFI_IF"
ping -c 4 223.5.5.5
```

未完成这次重启测试前，不要在发布说明中声称“开机自动联网已验证”。

## 8. 启用 SSH 远程调试

浏览器打不开并不影响 SSH。板卡执行：

```bash
command -v sshd
sudo systemctl enable --now ssh
sudo systemctl is-active ssh
hostname -I
```

Windows 先测试：

```powershell
ssh linaro@<BOARD_IP>
```

再用 VS Code 的 Remote - SSH 扩展连接。建议尽快改用 SSH 密钥；任何真实密码、SSID、IP、MAC 和私钥都不得放进 GitHub、CSDN、压缩包或截图。

## 9. 卸载与回滚

当前安装器会备份被替换的文件，但没有自动卸载模式。需要回滚时，先找到本次输出的备份目录并人工核对：

```bash
sudo ls -ld /root/afc03-backup-*
```

不要在未确认目录内容时直接复制或删除。发布版增加卸载功能前，应将“自动卸载暂未提供”列为已知限制。

## 10. 发布许可

发布者已经确认随板 AIC8800 驱动、模块和固件允许公开转载。公开包同时提供：

- 未删除版权和 SPDX 声明的驱动源码；
- GPL-2.0 许可证；
- 项目安装器的 AGPL-3.0-or-later 许可证；
- 固件、模块、源码的 SHA-256；
- 来源、板型、架构和精确内核限制。

第三方文件仍保留各自原始权利，本项目只做安装封装，不把它们重新授权为项目自有代码。若收到权利方异议，应立即暂停二进制下载并核实。
