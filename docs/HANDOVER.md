# 交接文档：LeEco Le Max 2 (x2) → Nura 主线移植

> 生成时间：2026-11-02 23:35 (Asia/Shanghai)
> 交接原因：临时更换 agent
> **请先完整读完本文档再动手**，尤其第 5 节「当前卡点」和第 7 节「踩过的坑」。

---

## 1. 项目目标

给 **乐视 Le Max 2（代号 `x2`，型号 LEX820）** 移植 **Nura**（原 postmarketOS，2026-09-27 改名），
要求使用**主线内核**（不是厂商 3.18 下游kernel）。

- Nura 官网：https://nura.eco
- 内核基线：`gitlab.com/msm8996-mainline/linux`，tag `v6.19.5-msm8996`
- 主要产出仓库：**https://github.com/minghao680/leeco-x2-nura**（本地在 `G:\LeEco-Max2\leeco-x2-nura`）

---

## 2. 环境与工具

| 项目 | 值 |
|---|---|
| 工作目录 | `G:\LeEco-Max2` |
| 移植仓库 | `G:\LeEco-Max2\leeco-x2-nura` |
| 备份目录 | `G:\LeEco-Max2\backup\x2-partitions-20261102\`（59 分区，721.8 MiB，全部校验通过） |
| 研究资料 | `G:\LeEco-Max2\research\`（3 份调研报告 + `_msm8996-linux` 内核源码稀疏检出） |
| 设备序列号 | `33470699`（列表里还有一台小米平板 `38d4fdf`，**别碰**） |
| adb / fastboot | `C:\Windows\adb.exe`、`C:\Windows\fastboot.exe` |
| GitHub 账号 | `minghao680`（gh 已登录，有 repo + workflow 权限） |
| Python | `C:\Users\HH0113\AppData\Local\Programs\Python\Python311\python.exe` |

### ⚠️ Git 推送问题（重要）

`git config` 里写死了失效代理 `192.168.1.197:7890`，**git push 会失败**。两种绕过方式：

```bash
# 方式一：单次绕过代理
git -c http.proxy= -c https.proxy= push

# 方式二：若 github.com 整体不通，用 Contents API 改单个文件
gh api repos/minghao680/leeco-x2-nura/contents/<路径> -X PUT \
  --input payload.json --jq '.commit.sha'
# payload.json 需要: {"message":"...","content":"<base64>","sha":"<文件当前sha>","branch":"main"}
```

`gh` 命令本身**走的是另一条通道，通常可用**（即使 git 直连不通）。

---

## 3. 本地仓库状态（注意！）

**本地 HEAD 落后远程 2 个提交**——这两个提交是通过 API 推的，本地没同步：

```
远程 main = ad49318  dts: move ramoops to 0x91500000 where TWRP can read it
            8030890  docs: hardware test #1 - lk2nd boots and identifies x2 correctly
本地 main = 3c60197  docs: stage 1 report - all four build paths green
```

`git status` 显示的改动其实是**已通过 API 推送过的**（DTS 内容与远程哈希一致，已核对）。

**新 agent 第一步应该：**

```powershell
cd G:\LeEco-Max2\leeco-x2-nura
git -c http.proxy= -c https.proxy= fetch origin main
git reset --hard origin/main
```

注意：`scripts/make-bootimg.py` 是**本地新建、尚未推送**的文件，`reset --hard` 不会删它（它是 untracked），
但记得之后要提交。

---

## 4. 已经完成并**在真机上验证过**的

### 4.1 构建链路（全部绿）

| 工作流 | 作用 | 耗时 | 状态 |
|---|---|---|---|
| `kernel.yml` | 完整内核 Image.gz + dtb | ~67 min | ✅ 成功 |
| `dtb-check.yml` | 只编 dtb（快速迭代用） | ~2-3 min | ✅ 成功 |
| `lk2nd.yml` | lk2nd 引导器 | ~5 min | ✅ 成功 |
| `panel-check.yml` | 面板驱动单独编译 | ~5 min | ✅ 成功（零警告） |

### 4.2 关键实测数据（写代码要用，别再猜）

**板级标识**（从真机 `/proc/device-tree` 读出，已写进 DTS 并反编译核对）：

```
qcom,msm-id   = <0xf6 0x30001>      即 <246 0x30001>
qcom,board-id = <0x08 0x2e>
qcom,pmic-id  = <0x20009 0x10013 0x00 0x00>
```

**硬件**：
- SoC：**MSM8996 v3**（不是 8996Pro！Adreno 530 @624MHz 而非 653）
- PMIC：**PMI8996**（不是 PM8994）
- 屏幕：Sharp 5.7" **1440×2560 dual-DSI**，单链路 720×2560，`dsi_video_mode`，60Hz
  - porch：hfp=120 / hbp=64 / hpw=16，vfp=8 / vbp=4 / vpw=4
  - reset-gpio = **tlmm 24**，TE-gpio = **tlmm 97**（取自厂商 dtsi `msm8996-le_x2-pvt.dtsi`）
  - 同板有 sharp/truly/boe/ofilm 四家变体，**PVT 量产机实测用 sharp**
- 触摸：Atmel mXT T100，I2C `12-0x4A`
- WiFi：QCA6174（`168c:003e`）→ 主线 `ath10k_pci`
- 蓝牙：QCA Rome → `hci_qca`，UART `ttyHS0`
- 存储：Samsung KLUCG4J1CB-B0B1 UFS 2.0
- 音频：WCD9335 + TFA9890（**无 ESS DAC**，那是 Le Max/Max Plus）
- 指纹：QBT1000（主线无驱动，放弃）

**引导/分区**：
- boot 分区 63.5 MiB（`0x3f80000`），**A-only，无 slot，无 dtbo，无 vbmeta**
- boot.img `header v0`，关键偏移：`kernel_addr=0x80008000`、`ramdisk_addr=0x81000000`、`tags_addr=0x80000100`、`page_size=4096`
- 原厂 boot.img 里 **33 个 DTB 是直接拼在 kernel 段内部**（`dt_size=0`），不是 dtbo 分区
- **ramoops 必须在 `0x91500000`**（原厂 3.18 和 TWRP 都从这里读 `console-ramoops`）

### 4.3 lk2nd 已成功在真机运行（重大里程碑）

用 `fastboot boot lk2nd.img`（**仅内存加载，不写分区**）成功后：

- `product` 从 `MSM8996` 变成 **`lk2nd-msm8996`**
- lk2nd 完整读出了 146 个 fastboot 变量，分区大小与实测全部吻合
- 说明 **msm-id / board-id 匹配正确**，板子被识别了

---

## 5. 🔴 当前卡点（最重要，从这里继续）

### 现象

按正确顺序操作：
1. `adb reboot bootloader` → 原厂 LK
2. `fastboot boot lk2nd.img` → lk2nd 接管（`product: lk2nd-msm8996`）✅
3. `fastboot boot boot-mainline.img` → `Booting OKAY [0.589s]`
4. 等待 20~60 秒后：**设备回到原厂 LK 的 fastboot**（`product: MSM8996`），说明内核启动失败并重启
5. 回到 Android 检查 `/sys/fs/pstore/console-ramoops`：**只有 3.18 的旧日志，没有主线内核的任何痕迹**

### 已排除的

- ❌ 不是 `dtb not found`（那是第一次在原厂 LK 上直接 boot 时的错误，已通过把 dtb 拼进 kernel 段解决）
- ❌ 不是 board-id 不匹配（lk2nd 能识别）
- ❌ 不是 USB/驱动问题（`fastboot boot` 两次都返回 OKAY）

### 最可疑的两个方向（按可能性排序）

**方向 1（可能性最大）：lk2nd 会自己 append DTB，我们的镜像里又拼了一个，可能冲突**

lk2nd 的设计目的是「提供正确的设备树」——它内部已经编入了 `msm8996-leeco-x2.dtb`
（已验证 `lk2nd.img` 里能搜到 "LeEco" 字符串）。

**实验建议**：做一个**只含 kernel、不拼 dtb** 的 boot.img 再试：

```python
# 复制 scripts/make-bootimg.py，把 kernel+dtb 那行改成只用 kernel
```

即 `kernel_size = len(kernel)`，`dt_size = 0`，不 append dtb。

**方向 2：崩溃发生在 ramoops 驱动初始化之前**

内核可能在极早期（解压后、驱动 probe 前）就挂了，此时 ramoops 还没起来，
自然抓不到日志。这种情况需要串口才能看到，或者：
- 加 `earlycon`（我们已经加了，但没接串口硬件）
- 用 lk2nd 的显示输出看有没有内核日志（lk2nd 支持 framebuffer）

### 另外注意

- 原厂 LK 上直接 `fastboot boot` 是我们的**操作失误**（lk2nd 只在内存，重启就没了）。
  正确流程永远是：**先 boot lk2nd，再在 lk2nd 的 fastboot 里 boot 内核**。
- `kernellog` 分区（10 MiB）里是厂商 3.18 的旧日志，**没用**，别再花时间。

---

## 6. 下一步建议（按顺序）

### 优先级 1：解决内核启动（用方向 1 的实验）

```powershell
# 1. 造一个不含 dtb 的 boot.img
python scripts\make-bootimg.py <Image.gz> # 改脚本支持无 dtb 模式

# 2. 进 bootloader
adb -s 33470699 reboot bootloader
fastboot devices

# 3. 先 boot lk2nd（关键！）
fastboot boot out\lk2nd\...\lk2nd.img
fastboot getvar product      # 确认变成 lk2nd-msm8996

# 4. 再从 lk2nd boot 内核
fastboot boot out\boot-mainline-nodtb.img

# 5. 观察 30 秒，然后查
fastboot getvar product      # 还是 lk2nd-msm8996 = 内核在跑；变回 MSM8996 = 崩溃重启
```

### 优先级 2：如果还是崩，考虑

- 检查 lk2nd 是否有控制台输出（连 UART 或看屏幕）
- 用 `lk2nd` 的 `fastboot oem` 命令看有没有调试接口
- 降低内核复杂度：先用極简 config（只保留 UART + UFS）排除驱动问题
- 参考 `msm8996-oneplus3` 的 bootimg 参数是否与我们的完全不同

### 优先级 3（内核能跑起来之后）

- 验证 UFS 是否识别（`/dev/sda`）
- 画面板驱动（`panel-sharp-leeco-x2.c` 已编译通过但未在真机点亮）
- 做 rootfs（pmaports device 包骨架已在 `device/leeco-x2/`）

---

## 7. 踩过的坑（避免重复）

| 坑 | 原因 | 修法（已修） |
|---|---|---|
| dtb 未注册到 Makefile | 格式是「一行一个 dtb」，sed 锚点不存在 | 用 awk 在 oneplus3 行后插入 |
| 错误日志看不到 | 工作流用 `\| tail -60` 把真错误截掉了 | 全量写 build.log，打印首个 error + 上下文 |
| `vreg_*` 标签不存在 | 这些不是 `pm8994.dtsi` 提供的，每块板自己声明 | 在 `&rpm_requests` 下定义所用 6 路轨 |
| 缺 `drm_connector_helper_get_modes_fixed` | 少 include | 加 `<drm/drm_probe_helper.h>` |
| lk2nd `ADTBS` 报错 | ADTBS 是单个续行赋值，追加独立行会变成新语句 | 用 `scripts/lk2nd-add-x2.py` 精确插入 |
| lk2nd 编译 `cortex-a8` 失败 | 用了 aarch64 交叉编译器，但 lk2nd 编 32 位 ARM | 改用 `arm-none-eabi-` |
| GitHub 克隆 URL 报 `protocol ' https'` | YAML 多行续行把空格混进 URL | 改成单行 `run: \|` |
| 本地内核树「缺文件」 | 是**稀疏检出**，文件不存在 ≠ 上游没有 | 用 `git ls-files` 确认真实存在性 |
| Git push 失败 | 失效代理 `192.168.1.197:7890` | `-c http.proxy=` 或走 gh API |
| fastboot 认不到设备 | Windows 缺 fastboot 驱动（代码 28） | 用户已手动装好 `Android Bootloader Interface` |

---

## 8. 命令速查

```powershell
# === 设备状态 ===
adb devices
adb -s 33470699 shell "getprop sys.boot_completed"    # 1 = 正常启动
fastboot devices

# === 回滚（任何时候都能救回来） ===
adb -s 33470699 reboot bootloader
fastboot flash boot G:\LeEco-Max2\backup\x2-partitions-20261102\pmos-backup\boot.img
fastboot reboot

# === 构建 ===
gh workflow run kernel.yml --repo minghao680/leeco-x2-nura        # 完整内核 ~67min
gh workflow run dtb-check.yml --repo minghao680/leeco-x2-nura     # 快速 dtb ~3min
gh workflow run lk2nd.yml --repo minghao680/leeco-x2-nura         # lk2nd ~5min
gh run list --repo minghao680/leeco-x2-nura --limit 5
gh run download <run_id> --repo minghao680/leeco-x2-nura -D <目标目录>

# === 拼接 boot 镜像 ===
python G:\LeEco-Max2\leeco-x2-nura\scripts\make-bootimg.py <Image.gz> <dtb> <输出.img>

# === 抓 pstore（崩溃日志） ===
adb -s 33470699 shell "su -c 'cat /sys/fs/pstore/console-ramoops'"
```

---

## 9. 安全须知

- ✅ **备份完整**：`G:\LeEco-Max2\backup\x2-partitions-20261102\`（59 分区，SHA256 全部校验）
- ⚠️ 到目前为止**只做过 `fastboot boot`（内存加载），从未写过任何分区**（除了用户手动装驱动）
- ⚠️ 设备当前状态：**Android 11 正常运行**（`sys.boot_completed=1`），无损坏
- 💡 任何时候不放心就 `fastboot flash boot <备份的 boot.img>` 回滚

---

## 10. 文档索引

仓库 `docs/` 下：
- `porting-plan.md` —— 完整移植计划（4 阶段，含工作量估算）
- `stage1-report.md` —— 阶段 1 完成报告
- `hardware-test-1-lk2nd.md` —— lk2nd 真机验证记录
- `ci-builds.md` —— CI 使用说明
- `progress.md` —— 进度追踪

工作区 `research/` 下：
- `research-device-hardware.md` —— 884 行硬件采集报告（最详细）
- `research-mainline-kernel.md` —— 主线内核可行性调研
- `research-nura-pmaports.md` —— pmaports 侧调研
- `_msm8996-linux/` —— 内核源码（**稀疏检出**，只有部分目录）

---

## 11. 一句话总结现状

> **构建链路全通、板子能被 lk2nd 正确识别、DTS/面板驱动都编译通过；
> 唯一卡点是内核从 lk2nd 引导后启动失败且抓不到日志。
> 最高优先级的实验是「做一个不含 dtb 的 boot.img」——因为 lk2nd 自己会 append DTB，可能冲突。**
