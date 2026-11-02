# 阶段 1 完成报告

> 2026-11-02 · LeEco Le Max 2 (x2 / LEX820)

## 结论

**四条构建链路已全部打通**，产物可直接下载用于真机验证。

| 产物 | 大小 | 来源 | 状态 |
|---|---|---|---|
| `Image.gz` | 14.3 MB | kernel.yml run 41451916930 | ✅ |
| `msm8996-leeco-x2.dtb` | 65 KB | 同上 / dtb-check | ✅ |
| `lk2nd.img` | 0.36 MB | lk2nd.yml run 41461950198 | ✅ |
| 面板驱动 `.o` | 261 KB | panel-check run 41454914869 | ✅ 零警告 |

## 已验证的事实

### DTB（关键）

反编译 `msm8996-leeco-x2.dtb` 逐项核对：

```
model          = "LeEco Le Max 2"
compatible     = "leeco,x2", "qcom,msm8996"
qcom,msm-id    = <0xf6 0x30001>       ← 与真机 /proc/device-tree 完全一致
qcom,board-id  = <0x08 0x2e>          ← 同上
qcom,pmic-id   = <0x20009 0x10013 0 0> ← 同上
```

面板节点也已正确写入：

```
compatible = "sharp,leeco-x2-panel"
qcom,dual-dsi-mode / master-dsi / sync-dual-dsi
reset-gpios = <&tlmm 24 GPIO_ACTIVE_LOW>   ← 取自厂商 dtsi msm8996-le_x2-pvt.dtsi
```

### 内核

- 基线：`msm8996-mainline/linux` tag `v6.19.5-msm8996`，rev `1aed438`
- 强制打开的关键选项全部生效：`ARCH_QCOM`、`DRM_MSM`、`SCSI_UFS_QCOM`、`PHY_QCOM_QMP_UFS`、`TOUCHSCREEN_ATMEL_MXT`、`PINCTRL_MSM8996`、`ATH10K_PCI`
- 编译耗时约 67 分钟（4 核 runner）

### 面板驱动

基于主线已有的 `panel-sharp-lq079l1sx01.c`（同样是双链路 Sharp 面板）改写：
- 双链路通过 of-graph `port@1` 找第二个 DSI host
- 1440×2560 模式，porch 用厂商值（hfp 120 / hbp 64 / hpw 16，vfp 8 / vbp 4 / vpw 4）
- 初始化序列取自 `dsi-panel-sharp-dualmipi-cmd.dtsi`
- 用 `mipi_dsi_dual_dcs_write_seq_multi()` 同时向两条链路发命令

**尚未实现**：厂商私有命令（0xb0 / 0xb3 / 0xd6），可能需要才能稳定点亮。

## 踩过的坑（已修复，供参考）

| 问题 | 原因 | 修法 |
|---|---|---|
| dtb 未注册 | Makefile 是「一行一个 dtb」，sed 锚点不存在 | 用 awk 在 oneplus3 行后插入 |
| 报错被截断 | `\| tail -60` 吞掉了真正的 error | 全量写 `build.log`，打印首个 error + 上下文 |
| `vreg_*` 标签不存在 | 这些不是 `pm8994.dtsi` 提供的，每块板自己声明 | 在 `&rpm_requests` 下定义所用到的 6 路轨 |
| 缺 `drm_connector_helper_get_modes_fixed` | 少 include | 加 `<drm/drm_probe_helper.h>` |
| lk2nd `ADTBS` 报错 | ADTBS 是单个续行赋值，追加独立行会变成新语句 | 独立脚本 `scripts/lk2nd-add-x2.py` 精确插入 |
| lk2nd 编译 `cortex-a8` 失败 | 用了 aarch64 交叉编译器，但 lk2nd 编 32 位 ARM | 改用 `arm-none-eabi-` |

## 下一步：真机验证

⚠️ **以下操作会写入设备，请先确认备份完整**（`backup/x2-partitions-20261102/`，59 分区已校验）。

### 第 1 步：刷 lk2nd（可完全回滚）

```bash
adb reboot bootloader
fastboot devices                          # 确认设备在
fastboot flash boot lk2nd.img             # 覆盖 boot 分区
fastboot reboot
```

**预期**：屏幕出现 lk2nd 的菜单/提示文字。

- ✅ 出现了 → 说明 board-id 匹配成功，可以进入第 2 步
- ❌ 黑屏或直接进 Android → board-id 或 dtb 有问题，需调整

**回滚**（任何时候）：

```bash
fastboot flash boot backup/x2-partitions-20261102/pmos-backup/boot.img
fastboot reboot
```

### 第 2 步：启动主线内核

lk2nd 装好后，把内核和 dtb 拼成 boot 镜像：

```bash
cat out/kernel/kernel-x2-*/Image.gz out/kernel/kernel-x2-*/msm8996-leeco-x2.dtb > Image.gz-dtb
# 需要 rootfs，或用 lk2nd 的 fastboot 直接引导：
fastboot boot Image.gz-dtb
```

⚠️ 此时**没有 rootfs**，内核会启动到 initramfs 后因找不到根文件系统而 panic。这仍是有价值的验证——能看到内核日志说明 DTS 基本正确。

### 第 3 步：抓内核日志

如果屏幕不亮，用串口或 `fastboot oem` 方式抓日志。也可以先刷回 Android，用 `pstore`/`ramoops` 读上次崩溃日志（DTS 里已配 `ramoops@bff00000`）。

## 已知风险

1. **面板可能点不亮** —— 驱动未经真机验证，且缺厂商私有命令
2. **UFS 供电轨是推测的** —— 照抄 oneplus3/xiaomi，x2 实际可能不同；若 UFS 起不来，需从 stock DT 读真实 phandle
3. **`gpio-reserved-ranges` 未严格核实** —— 从 Android DT 推测
4. **没有 rootfs** —— 完整系统需要先做 pmaports 内核包 + 镜像构建
