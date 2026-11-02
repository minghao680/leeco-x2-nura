# 真机验证记录 #2：主线内核启动失败

> 2026-11-02 23:0x–23:3x · LeEco Le Max 2 (x2 / LEX820)
> 方式：`fastboot boot lk2nd.img` → lk2nd 接管 → `fastboot boot boot-mainline.img`
> （全程内存加载，**未写入任何分区**）

## 结论：❌ 失败（但无损失）

内核被 lk2nd 接受并开始加载（`Booting OKAY [0.589s]`），但随后设备重启回原厂 LK，
没有任何内核日志留下。

## 时间线（正确流程）

| 步骤 | 命令 | 结果 |
|---|---|---|
| 1 | `adb reboot bootloader` | 进入原厂 LK |
| 2 | `fastboot boot lk2nd.img` | OKAY，`product: lk2nd-msm8996` ✅ |
| 3 | `fastboot boot boot-mainline.img` | `Booting OKAY [0.589s]` |
| 4 | 等待 20–60 秒 | 设备回到 `product: MSM8996`（原厂 LK） |
| 5 | `fastboot reboot` | 正常回到 Android |

第 4 步说明：内核启动后崩溃，设备发生重启，又回到了原厂 bootloader。

## 已排除的原因

| 怀疑项 | 排除依据 |
|---|---|
| `dtb not found` | 那是**在原厂 LK 上直接 boot** 时的错误；已通过「dtb 拼进 kernel 段」解决 |
| board-id / msm-id 不匹配 | lk2nd 能识别设备（`product: lk2nd-msm8996`） |
| fastboot 驱动/通信问题 | 两次 `fastboot boot` 都返回 OKAY，无 USB 错误 |
| dtb 语法/链接错误 | `dtb-check` 工作流每次通过，board id 反编译核对一致 |
| ramoops 地址错导致「看不到日志」 | 已修正到 `0x91500000`（原厂位置）后重试，**仍然没日志** |

## 关键观察：完全没有内核输出

回到 Android 后检查：

```
/sys/fs/pstore/console-ramoops  → 只有 3.18.140 的旧日志，无任何 6.19 痕迹
```

这说明内核在 **ramoops/pstore 驱动初始化之前**就挂了，或者根本没执行到内核主流程。
这类极早期崩溃通常只有 UART 串口能观察到。

## 最可疑的方向

### 方向 1：lk2nd 会自己 append DTB，与镜像内的 DTB 冲突（可能性最高）

lk2nd 的核心设计就是「提供正确的设备树」——它的 `lk2nd.img` 里已经内嵌了
`msm8996-leeco-x2.dtb`（已用 grep 验证 `lk2nd.img` 内含 "LeEco" 字符串）。

而我们的 `boot-mainline.img` **又**在 kernel 段尾部拼了一个 dtb。
两者可能冲突，或导致内核拿到的 DTB 指针不对。

**建议实验**：做只含 kernel（不带 dtb）的 boot.img，让 lk2nd 自己 append：

```python
# make-bootimg.py 需要加一个 --no-dtb 模式
kernel_size = len(kernel)   # 不含 dtb
dt_size     = 0
# 输出只写 header + kernel
```

### 方向 2：内核在极早期崩溃（解压后、驱动 probe 前）

可能原因：
- `Image.gz` 的解压目标地址与 lk2nd 加载位置冲突
- 内核缺 `CONFIG_ARM64_VA_BITS` 之类的平台必需项
- PSCI / CPU 启动方式不对

排查手段：接 UART 串口（需要拆机，暂不具备）、或降低内核复杂度做最小 config 试验。

### 方向 3：boot.img 的 kernel_addr 等参数不适合 lk2nd

我们用的是原厂 LK 的参数（`kernel_addr=0x80008000`）。
lk2nd 可能对加载地址有不同要求，可对比 `lk2nd.img` 自身的 header：

```
lk2nd.img: kernel_size=364324, kernel_addr=0x8000,
           ramdisk_size=1, ramdisk_addr=0x1000000, tags_addr=0x100
```

注意 lk2nd 用的是 `0x8000` 而不是 `0x80008000`，差异值得深究。

## 设备状态

- 已 `fastboot reboot` 回到 Android，`sys.boot_completed=1`，工作正常
- **boot 分区全程未被写入**
- 备份完好：`backup/x2-partitions-20261102/pmos-backup/boot.img`

## 附带发现：kernellog 分区无用

x2 有个 10 MiB 的 `kernellog` 分区，但读出来是**厂商 3.18 内核的旧日志**
（包含 Letv jenkins 编译路径、`Hardware name: Letv Technologies... LE_X2-PVT`），
与我们的启动尝试无关，后续不要再浪费时间。

## 下一步

见 `docs/HANDOVER.md` 第 6 节。优先做「不含 dtb 的 boot.img」实验。
