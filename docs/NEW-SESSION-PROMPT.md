# 新会话启动提示词（直接复制粘贴）

> 用法：新建会话后，把下面 `===` 之间的全部内容原样粘贴给新 agent。

===

继续推进「乐视 Le Max 2 (x2 / LEX820) → Nura 主线内核移植」项目。

## 先读这些（按顺序）

1. **https://github.com/minghao680/leeco-x2-nura/blob/main/docs/HANDOVER.md** ← 交接主文档，必读
2. `docs/hardware-test-2-kernel-boot.md` ← 当前卡点的详细记录
3. `docs/hardware-test-1-lk2nd.md` ← 已跨过的里程碑

本地仓库：`G:\LeEco-Max2\leeco-x2-nura`
工作目录：`G:\LeEco-Max2`
GitHub 账号：`minghao680`（gh 已登录）

## 项目目标

给 LeEco Le Max 2（代号 `x2`，型号 LEX820，MSM8996 v3 + PMI8996）移植
**Nura**（原 postmarketOS，2026-09 改名），要求使用**主线内核**
（`gitlab.com/msm8996-mainline/linux`，tag `v6.19.5-msm8996`）。

## 当前状态（2026-11-02 夜）

**已完成并验证：**
- 全分区备份：`G:\LeEco-Max2\backup\x2-partitions-20261102\`（59 分区，SHA256 全部校验）
- 四条 CI 构建链路全绿：内核 Image.gz（14.3MB）、dtb、lk2nd.img、面板驱动
- **lk2nd 已在真机成功运行**：`fastboot boot lk2nd.img` 后 `product` 变成 `lk2nd-msm8996`，
  说明 msm-id/board-id 匹配正确，板子被识别了

**当前卡点：**
内核从 lk2nd 引导后启动失败。流程是 `fastboot boot lk2nd.img`（lk2nd 接管，OK）
→ `fastboot boot boot-mainline.img`（`Booting OKAY`）→ 等待 20-60 秒 → 设备重启回原厂 LK。
`/sys/fs/pstore/console-ramoops` 里**没有任何主线内核痕迹**（只有 3.18 旧日志），
说明内核在 ramoops 驱动初始化之前就挂了。

**最高优先级的假设（先去验证这个）：**
lk2nd 的设计目的就是"提供正确的设备树"，它内部已内嵌 `msm8996-leeco-x2.dtb`
（已 grep 验证 `lk2nd.img` 含 "LeEco" 字符串）。而我们的 `boot-mainline.img` 又拼了一个 dtb，
**可能冲突**。所以应该做一个**只含 kernel、不带 dtb** 的 boot.img 再试一次。

参考脚本 `scripts/make-bootimg.py` 需要加一个 `--no-dtb` 模式
（`kernel_size = len(kernel)`，不 append dtb）。

## 环境坑（会浪费你时间，先记住）

1. **Git push 会失败**：`git config` 里有失效代理 `192.168.1.197:7890`。
   用 `git -c http.proxy= -c https.proxy= push` 绕过；若 github.com 整体不通，
   改用 `gh api repos/minghao680/leeco-x2-nura/contents/<路径> -X PUT` 走 Contents API
   （需要 base64 content + 文件当前 sha + branch）。`gh` 命令本身通常可用。
2. **本地仓库可能落后远程**：之前有提交是通过 API 推的，本地没同步。
   第一步先 `git -c http.proxy= -c https.proxy= fetch origin main && git reset --hard origin/main`
3. **本地内核树是稀疏检出**（`research/_msm8996-linux`）：文件不存在 ≠ 上游没有，
   要用 `git ls-files` 核实。
4. **adb 里有两台设备**：`33470699` 是本次的 Le Max 2，`38d4fdf` 是小米平板，
   **所有命令都要带 `-s 33470699`**，别碰平板。
5. **lk2nd 只在内存**：`fastboot reboot` 后就没了，下次要重新 `fastboot boot lk2nd.img`。
   正确流程永远是「先 boot lk2nd → 再在 lk2nd 的 fastboot 里 boot 内核」。

## 关键实测数据（别重新猜）

```
qcom,msm-id   = <0xf6 0x30001>      # = <246 0x30001>
qcom,board-id = <0x08 0x2e>
qcom,pmic-id  = <0x20009 0x10013 0x00 0x00>

屏幕：Sharp 1440x2560 dual-DSI，单链路 720x2560，dsi_video_mode 60Hz
      reset-gpio = tlmm 24，TE-gpio = tlmm 97
      同板有 sharp/truly/boe/ofilm 四家，PVT 实测用 sharp
触摸：Atmel mXT T100，I2C 12-0x4A
WiFi：QCA6174 → ath10k_pci     蓝牙：QCA Rome → hci_qca
存储：Samsung KLUCG4J1CB-B0B1 UFS 2.0
音频：WCD9335 + TFA9890（无 ESS DAC）
指纹：QBT1000（主线无驱动，已放弃）

boot 分区 63.5 MiB，A-only，无 slot/dtbo/vbmeta，header v0
kernel_addr=0x80008000  ramdisk_addr=0x81000000  tags_addr=0x80000100  page_size=4096
原厂 boot.img 里 33 个 DTB 直接拼在 kernel 段内部（dt_size=0）
ramoops 必须在 0x91500000（原厂 3.18 和 TWRP 都从这里读）
```

## 安全规则

- 备份完整，任何时候可回滚：
  ```powershell
  adb -s 33470699 reboot bootloader
  fastboot flash boot G:\LeEco-Max2\backup\x2-partitions-20261102\pmos-backup\boot.img
  fastboot reboot
  ```
- 优先用 `fastboot boot`（内存加载，零风险），**不要轻易 flash**
- 需要写入分区前，先跟我确认
- 到目前为止只做过 `fastboot boot`，从未写过任何分区（除了我自己装的 fastboot 驱动）

## 请从这里开始

1. 先读 `docs/HANDOVER.md`，然后同步本地仓库
2. 检查设备状态（`adb devices`、`getprop sys.boot_completed`）
3. 给 `scripts/make-bootimg.py` 加 `--no-dtb` 模式
4. 用现有产物造一个不含 dtb 的 boot.img
5. 按「先 boot lk2nd，再 boot 内核」的流程测试
6. 报告结果：`fastboot getvar product` 是 `lk2nd-msm8996`（内核在跑）还是
   `MSM8996`（崩溃重启）

如果这个假设不成立，`docs/hardware-test-2-kernel-boot.md` 里还有另外两个排查方向
（极早期崩溃需要 UART、boot.img 参数与 lk2nd 不一致）。

===
