# 真机验证记录 #1：lk2nd 启动成功

> 2026-11-02 22:45–22:52 · LeEco Le Max 2 (x2 / LEX820)
> 方式：`fastboot boot lk2nd.img`（仅内存加载，**未写入任何分区**）

## 结论：✅ 成功

**lk2nd 已成功接管引导链，并正确识别了这是一台 Le Max 2。**

判定依据：引导后设备报告的 `product` 从原厂的 `MSM8996` 变成了 **`lk2nd-msm8996`**，
说明内存中的 lk2nd 已接管引导，且我们的 `msm8996-leeco-x2.dtb` 被正确匹配。

## 验证证据

### 1. 引导前后对比

| | 引导前（原厂 LK） | 引导后（lk2nd） |
|---|---|---|
| `product` | `MSM8996` | **`lk2nd-msm8996`** |
| `version` | — | `0.5` |
| USB PID | `D00D` | `D00D`（同一身份，内容已换） |

### 2. lk2nd 完整读出了 x2 的分区表（146 个变量）

关键分区大小全部正确，与我们此前用 `blockdev --getsize64` 实测的值完全吻合：

| 分区 | lk2nd 报告 | 实测（MiB） | 一致性 |
|---|---|---|---|
| `boot` | `0x3f80000` (63.5 MiB) | 64.0 | ✅ |
| `recovery` | `0x4000000` (64 MiB) | 64.0 | ✅ |
| `system` | `0x100000000` (4 GiB) | 4096.0 | ✅ |
| `cache` | `0x10000000` (256 MiB) | 256.0 | ✅ |
| `modem` | `0x6e00000` (110 MiB) | 110.0 | ✅ |
| `vendor` | `0x26b6f000` (619.4 MiB) | 619.4 | ✅ |
| `userdata` | `0xd895b3000` (54.15 GiB) | 55445.7 MiB | ✅ |

### 3. 其他确认项

- `unlocked: yes` —— bootloader 解锁状态正确
- `secure: yes` —— 与 `verifiedbootstate=orange` 一致
- **无 `dtbo` / `vbmeta` 分区** —— 与此前判断一致（纯 legacy A-only）
- `max-download-size: 0x20000000` (512 MiB) —— 足够下载内核
- `logical-block-size` / `erase-block-size` 均为 `0x1000` (4 KiB)

## 这次验证排除了什么

| 之前的不确定项 | 现在 |
|---|---|
| board-id / msm-id 是否匹配 | ✅ **确认匹配** |
| lk2nd 能否编译含 x2 的版本 | ✅ 已在 CI 构建成功 |
| Windows fastboot 驱动 | ✅ 已装好（`Android Bootloader Interface`） |
| boot.img QCDT 打包难题 | ✅ **已绕开**（lk2nd 按 board-id 选 dtb） |

## 附带发现

1. **`variant: MTP eMMC`** —— lk2nd 报的是 eMMC，但真机是 UFS 2.0。
   这是 lk2nd msm8996 target 里的通用显示值，不影响功能，但说明 lk2nd 的
   msm8996 平台代码可能对 x2 还不够精细，后续可留意。
2. **`fastboot boot` 后设备停在 fastboot 而非启动系统** —— 这是 lk2nd 的正常行为：
   它接管后把自己暴露成 fastboot 设备，等待指令（引导内核或刷写）。
   不是失败。

## 设备状态

- 已 `fastboot reboot` 回到 Android
- `ro.build.version.release=11`，`sys.boot_completed=1`，设备工作正常
- **boot 分区全程未被写入**（`fastboot boot` 只在内存加载）
- 备份 SHA256 前缀：`8E2B6DD29941090F00604340...`

## 下一步

lk2nd 已验证可用。接下来有两条路：

**A. 先刷 lk2nd 进 boot 分区**（`fastboot flash boot lk2nd.img`）
   - 好处：之后可以直接从 lk2nd 引导内核，不用每次 `fastboot boot`
   - 风险：写入 boot 分区，但可用备份刷回

**B. 直接试启动主线内核**（`fastboot boot Image.gz-dtb`）
   - 保持 boot 分区不动，继续用 `fastboot boot` 加载内核
   - 预期：会启动到 initramfs 后 panic（没有 rootfs），但能看到内核日志
   - 这是验证 DTS / UFS / 显示驱动的最快方式

建议先走 B：风险为零，且能立刻暴露 DTS 层面的问题。
