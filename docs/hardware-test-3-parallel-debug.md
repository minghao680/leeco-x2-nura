# 真机验证记录 #3：并行调试与新工具链

> 2026-11-03 凌晨 · LeEco Le Max 2 (x2 / LEX820)
> 全程 `fastboot boot` 内存加载，**未写入任何分区**

## 本轮最重要的两个发现

### 1. lk2nd 的 DTB 匹配在 x2 上全盘失灵（单 DTB 靠兜底通过）

`msm8916-mainline/lk2nd` 的 `dev_tree_appended()`（platform/msm_shared/dev_tree.c:1357）
有一个特殊分支：**镜像里只有 1 个追加 DTB 时，无论匹配检查是否通过都强制选用**。

实测证据：
- `boot-nodtb.img`（kernel_size 内无任何 DTB）→ `FAILED (remote: 'dtb not found')`
  → lk2nd 和原厂 LK 一样**要求** kernel 段内有 DTB，「让 lk2nd 自己提供 DTB」不成立。
- **stock boot.img（33 个 DTB，其中 #23 的 msm-id/board-id/pmic-id 与本机完全一致）也
  被拒** → 说明 `dev_tree_compatible()` 对所有 stock DTB 都返回不匹配 → 33 个时无兜底
  → 拒绝。我们的单 DTB 之前能过 "Booting OKAY"，几乎肯定走的是强制兜底分支。
- 结论：lk2nd 从 SMEM 读到的板级信息（platform/variant/subtype/pmic）与实际值对不上
  （hardware-test-1 里 "variant: MTP eMMC" 的怪象同源）。lk2nd 在 x2 上**从未成功
  引导过任何内核**，其 crash 不能全归咎于内核。

### 2. ramoops 布局必须与 3.18 逐字节一致，否则日志不可读

- 3.18 实际参数（/sys/module/ramoops/parameters/*）：mem=0x91500000/1MB，
  **console_size=0x40000, pmsg_size=0x20000, record_size=0x10000**，ecc=0，
  缓冲区顺序 dmesg-records → console → pmsg。
- 而 out/ 里的 DTB 产物是**旧版**（ramoops 还在 0xBFF00000，CI 构建早于
  ad49318 "move ramoops to 0x91500000"），DTS 源码现值 console-size=0x60000 也与
  3.18 的 0x40000 不符 → 即便内核写到 ramoops，Android 侧也解析不出 console-ramoops。
- 修复：对旧 DTB 做二进制补丁（同长度替换，见
  `out/kernel/kernel-x2-8/msm8996-leeco-x2-ramoops-fixed.dtb`）：
  节点名 `ramoops@bff00000`→`ramoops@91500000`、reg 0xbff00000→0x91500000、
  record-size 0x20000→0x10000、ftrace-size 0x20000→0。
  DTS 源码同步修正（console 0x40000 / 去掉 ftrace）后待提交。

## 实验矩阵（本轮）

| # | 镜像 | Loader | 结果 | 结论 |
|---|---|---|---|---|
| E1 | boot-nodtb.img（无 DTB） | lk2nd | `dtb not found` 被拒 | 段内 DTB 必需 |
| E2 | stock boot.img（33 DTB） | lk2nd | `dtb not found` 被拒 | 匹配逻辑失灵实锤 |
| E3 | boot-mainline.img（旧 DTB） | 原厂 LK | Booting OKAY → 挂死 3.5min+，需强制断电 | 原厂 LK 可接受镜像；内核疑似未启动（地址未对齐 2MB） |
| E4 | boot-ramoops.img（补丁 DTB + panic=15） | 原厂 LK | 同样挂死，panic=15 未触发 | 内核未跑到 panic，甚至可能没启动 |
| E5 | boot-ramoops.img | lk2nd | ≤10s 崩溃重启回原厂 LK；console-ramoops 仍无 6.19 内容 | lk2nd 路径内核活 <5s，未到 ramoops |
| E6 | boot-addr8008.img（kernel_addr=0x80080000） | 原厂 LK | 挂死（同 E3/E4） | 原厂 LK 无视 header 地址（或内部强制），**该路径放弃** |

console-ramoops 全程只含 3.18 旧日志（止于每次进入 bootloader 前的重boot），
并可见零星位翻转（无 ECC，属正常老化）。

## 当前结论与分工

- **lk2nd 路径是唯一活路**：内核在 lk2nd 下有短暂生命（会崩溃重启），stock LK 下
  疑似根本没启动（挂死）。
- 死因在 ramoops 初始化（device_initcall 级，~2-4s）之前：候选 = DTB 被 lk2nd
  patch 出错、安全内存/TZ 区域冲突、内核极早期崩溃。
- 并行调查（子代理）：
  A. lk2nd 引导链审计 + `fastboot oem` 调试命令清单（若有日志转储命令可免引导直接看 lk2nd 决策）
  B. DTS/保留内存/安全内存审计（vendor vs mainline）
  C. pmOS msm8996 已知好参数（deviceinfo/cmdline/config/lk2nd 用法）

## 工具链变更（已落地）

- `scripts/make-bootimg.py`：
  - `--no-dtb` 模式（实验用，实测会被 lk2nd/原厂 LK 拒绝，保留作对照）
  - `--addr <hex>` 覆盖 kernel_addr（E6 用，实测无效）
  - 默认 cmdline 加 `panic=15`（panic 自动重启，便于观察崩溃 vs 挂死）

## 设备状态

- 全程未写入分区；备份完好
- 设备 4 次挂死均由人工强制断电恢复（长按电源 10-15s），重启回 Android 正常

## 追加（2026-11-03 02:0x）：PSTORE_RAM=m —— "无日志"的真正元凶之一

对比 pmOS 内核配置（agent 调研）与 fork 的 defconfig：

- fork defconfig：`CONFIG_PSTORE_RAM=m`（模块！）
- pmOS 配置：`CONFIG_PSTORE_RAM=y`、`PSTORE_CONSOLE=y`、`PANIC_TIMEOUT=0`

我们的设备**没有 rootfs、不加载模块** → ramoops 驱动永远不 probe →
**即使内核完全正常地活着，console-ramoops 也不会出现**。
此前"内核死在 ramoops 初始化之前"的所有推断都被这个发现污染，修正为：
内核实际存活时间未知，lk2nd 路径 ≤10s 的崩溃重启仍然真实，但死因位置不明。

已修复（CI 9dc3cdc）：force-enable `PSTORE/PSTORE_RAM/PSTORE_CONSOLE/PSTORE_PMSG=y`。

## 追加 2：pmOS 参考参数带来的其他修正

1. **cmdline 换成 pmOS 风格**：`earlycon panic=15 lk2nd.pass-ramoops=zap`
   （无 console=，stdout-path 解析；panic 自动重启；lk2nd 注入 ramoops 节点，
   崩溃后 `fastboot oem ramoops` 可直接读日志，无需启动 Android）
2. **`lk2nd.pass-ramoops=zap`**：lk2nd 会把自己的 ramoops reserved-memory
   注入 OS 的 DTB——独立于我们 DTS 的第三个日志通道（lk2nd issue #431）。
3. **Mi Note 2 的前车之鉴**：8996 上 MDP SMMU probe 曾导致秒级崩溃，
   若新内核仍早死，下一步把 mdss/SMMU 节点 disable 做最小化引导。
4. pmOS 全量配置已入仓：`kernel/config-pmos-msm8996.aarch64`，
   kernel.yml 支持 `config_file` 输入一键切换。

## 给用户的醒来操作清单（设备现状：黑匣子实验后挂死）

1. **长按电源 10-15 秒强制重启**（黑匣子 v2 的 DTB 转储数据就在 RAM 里！）
2. 回到系统后告诉我一声，或直接等我处理——我会自动：
   a. 读 `/sys/fs/pstore/console-ramoops`（应为 LKPROBE1 记录：lk2nd 实际传给内核的 DTB + cmdline）
   b. 等 CI 构建完（PSTORE_RAM=y 的新内核），组装新 boot.img
   c. 用「lk2nd → boot 内核 → 崩溃 → fastboot oem ramoops」新回路读首批 6.19 日志

## 黑匣子时间线（记录）

- v1（原始）：`dtb not found` 被拒 → 原因：非 gzip 内核走 decompress 路径失败，
  dtb_offset=0，扫描从偏移 0 开始 → 修复：gzip 打包
- v2（gzip 版）：`Booting OKAY` 后设备挂死（PSCI 复位未生效）→ 数据预计已写入
  0x915A0000，等强制重启读回。已给 v3 加 KPSS 看门狗自恢复（5s 必复位）。

---

## 2026-11-03 下午：彻底突破与真正的根因链

### 最终确认的 9 个 lk2nd 根因（全部已在 lk2nd-patches/ 修复）

1. LPAE `platform_get_phys_to_virt_mapping()` 反查页表 → 内核装到 0x40008000（lk2nd 自身）
2. 低 512MB 映射为 device/XN → 关 MMU 后取指失败
3. **DDR 窗口（0x80000000+）完全没有映射** → tags/ramdisk/kernel 写入静默失败
4. **tags_addr(0x82500000) 落在内核镜像范围内** → 内核 memmove 覆盖 DTB
5. `copy_dtb()` 在 dt_size==0 时返回"成功" → 跳过 appended-DTB 路径
6. `decompress()` 的 pos 比真实 gzip 结尾少 2 字节
7. DTB 反向扫描步长 4 错过未对齐的 DTB（实际偏移 14992613 不是 4 的倍数）
8. 单 DTB 兜底分支用 blob 末尾算 size → 复制几十 MB 垃圾
9. volume-up 映射到 pm8994 gpio3（应为 gpio2）→ 每次开机误进 recovery

### 屏幕诊断（无 UART 时的唯一观测手段）

lk2nd 在 boot_linux 各阶段把状态画到面板底部（`x2_screen_line`/`x2_screen_hex`）。
实测显示：
```
x2: boot_linux entered
arm64 kernel
platform uninit done
elr: 80000000
x0: 83000000
```
→ 参数完全正确，但随后**卡在 `smc #0`**：LeEco 的 TZ 不接受 lk2nd 的
`MILESTONE_32_64`（svc 0x1 / cmd 0xf）调用，收下后既不返回也不跳转。

### 原厂 aboot 逆向（aboot.img 是 ELF32/EM_ARM，入口 0x91600000）

反汇编确认原厂 SCM wrapper（0x9161be84）与 lk2nd `scm_call_a32` 完全一致：
```asm
push {r4,r5,r6,fp,lr}; ...; mov r6,#0; smc #0; cmp r0,#1; beq retry
```
即 SCM 通道本身没问题，差异在 milestone 参数/TZ 实现。

### 决定性转向：改用原厂 LK 直接引导内核

原厂 LK 每天都在引导 64 位 3.18 内核，它的 32→64 切换是验证过的。
用修好的 DTB（console=serial@75b0000、ramoops@91500000）在**原厂 LK** 上
`fastboot boot` 的结果：`Booting OKAY`，180 秒无复位 —— 但屏幕仍停在原厂
LK 界面，说明内核未接手（不是崩溃）。

### 新发现的关键配置 bug

fork 的 defconfig 里 **`CONFIG_USB_CONFIGFS=m`**：
- 设备没有 rootfs → 模块永不加载 → USB gadget 永不出现
- initramfs 设计的 USB ACM shell 因此完全没机会工作
- 已在 kernel.yml / initramfs.yml 强制 `USB_DWC3/USB_CONFIGFS/ACM/DEVTMPFS/INITRD` 全 `=y`
