# 乐视 Le Max 2 (x2 / LEX820) → Nura (原 postmarketOS) 主线内核移植计划

> 目标设备：LeEco Le Max 2，代号 `x2`，型号 LEX820，SoC **MSM8996 v3**（骁龙 820，非 8996Pro）
> 目标系统：**Nura**（postmarketOS 于 2026-09-27 正式更名，见 [改名公告](https://nura.eco/blog/2026/09/27/nura-rename/)）
> 目标内核：**主线 6.19.x**（`gitlab.com/msm8996-mainline/linux`，Nura 官方内核包在用）
> 计划制定：2026-11-02，全部结论经本机实测 + 上游源码取证
> 现状：LineageOS 18.1 + SukiSU root，bootloader 已解锁（`verifiedbootstate=orange`），adb 可用

---

## 0. 先回答你最关心的三件事

### ① 改名情况

postmarketOS **已更名为 Nura**（2026-09-27 公布）。对应变化：

| 旧 | 新 |
|---|---|
| `postmarketos.org` | `nura.eco` |
| `wiki.postmarketos.org` | `wiki.nura.eco`（有 Anubis 反爬） |
| `docs.postmarketos.org` | `docs.nura.eco` |
| `gitlab.postmarketos.org` | `gitlab.nura.eco`（旧域名 308 跳转） |
| `pkgs.postmarketos.org` | `pkgs.nura.eco` |

**但代码层面的命名几乎没变**，这很重要：
- 包名仍是 `postmarketos-base`、`linux-postmarketos-qcom-msm8996`、`device-*`
- 工具仍是 **pmbootstrap**（未改名），`pmaports.cfg` 实测 `version=7`、`pmbootstrap_min_version=3.11.0`
- 仓库仍是 `nura/pmaports`（GitLab project id **226**，分支 **main**）
- 设备族目录 `device/` 下仍用 `postmarketos` 前缀

所以：**搜资料时两套关键词都要用**，但真正要 clone/依赖的标识符还是 `postmarketos`。

### ② 主线内核可行吗？——可行，但属于"从零新增机型"

**结论：技术上可行，无硬性拦路虎；工作量大，约 8–13 人周（不含相机/指纹）。**

关键验证结果（全部经源码取证，非推测）：

| 关键点 | 结论 | 证据 |
|---|---|---|
| bonded dual-DSI | ✅ **主线原生支持** | `dsi_manager.c` 有完整 `is_bonded_dsi` / `IS_BONDED_DSI()` 实现 |
| `qcom,dual-dsi-mode` 绑定 | ✅ 支持 | `dsi_manager.c:55-62` 读取该属性 |
| MDP5 双链路源分割 | ✅ 支持 | `MDP_CAP_SRC_SPLIT` + `mdp5_crtc.c` 左右 mixer 分配 |
| 8996 平台基础 | ✅ 完整 | `msm8996.dtsi` + `msm8996-v3.0.dtsi` + `pmi8996.dtsi` |
| UFS 存储 | ✅ 支持 | `compatible = "qcom,msm8996-ufshc", "qcom,ufshc"` |
| 触摸 Atmel mXT | ✅ 支持 | `CONFIG_TOUCHSCREEN_ATMEL_MXT=m` 已启用 |
| WiFi QCA6174 | ✅ 支持 | `ath10k_pci`，三星/一加同款 |
| 音频 WCD9335 + TFA9890 | ✅ 支持 | `wcd9335.c` + `tfa989x.c` 都在树里 |
| 充电 PMI8996 SMBCHG | ✅ 支持 | `qcom-smbchg.c`（匹配 `qcom,pmi8996-smbchg`） |
| 加速度计 BMI160 | ✅ 支持 | `drivers/iio/imu/bmi160/` |
| 磁力计 AK09911 | ✅ 支持 | `ak8975.c` 内含 `AK09911` 兼容串 |
| **x2 面板驱动** | ❌ **需从零写** | 树里只有 JDI R63452 / LGPhilips SW43101，无 Sharp 双 DSI QHD |
| **x2 的 DTS** | ❌ **需从零写** | 全树 92232 文件，LeEco/Letv/x2 **零命中** |
| **指纹 QBT1000** | ❌ **无驱动** | 无主线驱动，接受功能缺失 |
| **相机** | ❌ 无驱动 | 接受功能缺失 |

### ③ 最大的三个坑

1. **面板驱动要从零写**（2–4 人周）—— x2 是 Sharp 双 DSI QHD，`pingpong-split` 模式，4 家屏厂变体。
   好消息：主线 `panel-samsung-s6e3ha2.c` 正好是 **1440×2560 video mode**，与 x2 规格完全一致，可作基底。
2. **充电/电量计**（1–2 人周）—— `qcom-smbchg.c` 是 fork 私有驱动（上游没有），
   且 x2 额外有 `smb1351` 并联充电 IC，主线无驱动。
3. **调制解调器**—— MSS/ADSP/SLPI 框架齐全，但 x2 的 `mba.mbn`/`modem.mbn` 需从真机 dump。

---

## 1. 真机硬件基线（已实测，可直接用）

> 完整数据见 [`research/research-device-hardware.md`](research/research-device-hardware.md)（884 行）

| 项目 | 实测值 |
|---|---|
| SoC | **MSM8996 v3**（soc_id=246, rev 3.1），非 Pro；CPU 1.59+2.15GHz，Adreno 530 @624MHz |
| PMIC | **PMI8996**（不是 PM8994） |
| 面板 | Sharp `le_x2_mdss_dsi_sharp_qhd_dualdsi_cmd`，单链路 720×2560 → 合成 **1440×2560@60Hz**，`dsi_video_mode`，`hw-config=split_dsi`，`split-mode=pingpong-split` |
| 触摸 | **Atmel mXT T100**，I2C `12-0x4A`，16 点（Synaptics 节点存在但未启用） |
| WiFi | **QCA6174**，PCI `168c:003e` → 主线 `ath10k_pci` |
| 蓝牙 | QCA Rome / QCA6164，UART `ttyHS0` → 主线 `hci_qca` |
| 基带 | MSM8996 内置，`M8996FAAAANAZM`，双卡 DSDS |
| 存储 | Samsung `KLUCG4J1CB-B0B1` UFS 2.0，6 LUN |
| 传感器 | BMI160（加速度/陀螺）+ AK09915（磁力）+ PA22A（光感/距离） |
| 音频 | WCD9335 + **TFA9890** 功放（**无 ESS DAC**，那是 Le Max/Max Plus） |
| 指纹 | QBT1000（主线无驱动） |

**引导链关键参数（写 DTS 必须用）：**

```
qcom,msm-id   = <0xf6 0x30001>      →  即 <246 0x30001>
qcom,board-id = <8 0x2e>
qcom,pmic-id  = <0x20009 0x10013 0x00 0x00>
```

**分区/boot.img 事实（影响刷机流程）：**

- boot 分区 **64 MiB**（`/dev/block/sde18`），当前镜像 25.8 MB → 余量充足
- **A-only**，无 slot、无 `dtbo`、无 `vbmeta`，boot.img 为 **header v0**
- 实测 header：`kernel_size=24943843`、`kernel_addr=0x80008000`、`ramdisk_addr=0x81000000`、`tags_addr=0x80000100`、`page_size=4096`、**`dtb_size=0`**
- ⚠️ 现有 boot.img 里 **33 个 DTB 是拼在 kernel 之后的 QCDT 风格布局**，不是我最初以为的 dtbo 分区；
  其中有 **3 个 DTB 共用 board-id 0x2e**（#3 Pro+PMI8996、#16 v3+PMI8994、#22 v3+PMI8996），实机启动的是 **#22**
- ⚠️ **本地 `boot-backup-before-sukisu.img` 已过期**（与设备实时 dump 的 SHA256 不符），备份需重做

---

## 2. 路线选择（先做这个决定）

主线移植有两条路，**建议先走 A，把 B 作为长期目标**：

| | 路线 A：主线 + lk2nd（推荐起点） | 路线 B：纯主线 + 原生 boot.img |
|---|---|---|
| 引导方式 | `fastboot flash boot lk2nd.img`，由 lk2nd 加载主线 | 直接把主线内核打进 boot.img |
| DTB 选择 | lk2nd 用 `msm-id`+`board-id` 选，**绕开 QCDT 打包难题** | 需自己解决 33-DTB QCDT 打包 |
| 回滚 | 重新刷回 Android boot.img 即可 | 同左 |
| 成熟度 | lk2nd `target/msm8996` 已存在，9 个机型在用 | 无 8996 先例 |

**为什么推荐 A**：x2 的 boot.img 里 DTB 是 QCDT 风格拼装，自己复现这套打包很容易出错（选错 DTB → PMIC 节点全错 → 不开机）。lk2nd 直接按 board-id 匹配，把这层风险消掉了。

---

## 3. 分阶段执行计划

### 阶段 0：备份与准备（半天）

**必须先做，否则 brick 风险不可控。**

```bash
# 1. 重新 dump 全部分区（本地旧备份已过期！）
adb -s 33470699 shell su -c "dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot.img"
adb -s 33470699 shell su -c "dd if=/dev/block/bootdevice/by-name/recovery of=/sdcard/recovery.img"
adb -s 33470699 shell su -c "dd if=/dev/block/bootdevice/by-name/modem of=/sdcard/modem.img"
adb -s 33470699 shell su -c "dd if=/dev/block/bootdevice/by-name/persist of=/sdcard/persist.img"
# 关键：modemst1/modemst2/fsg 含基带校准，丢了没信号
adb -s 33470699 shell su -c "dd if=/dev/block/bootdevice/by-name/modemst1 of=/sdcard/modemst1.img"
adb -s 33470699 shell su -c "dd if=/dev/block/bootdevice/by-name/modemst2 of=/sdcard/modemst2.img"
adb -s 33470699 shell su -c "dd if=/dev/block/bootdevice/by-name/fsg of=/sdcard/fsg.img"
adb pull /sdcard/boot.img ./backup/
```

**验收**：`sha256sum` 对比设备端与本地，确认一致；备份文件存两处。

**同时准备**：
- pmbootstrap ≥ 3.11.0
- `git clone --depth 1 https://gitlab.nura.eco/nura/pmaports.git`（⚠️ 别用 archive.tar.gz，3.8MB 处会截断）
- 内核源：`git clone https://gitlab.com/msm8996-mainline/linux -b msm8996-stable-6.19.y`

---

### 阶段 1：拿到"能开机"的最小主线（3–5 人周）

**目标：能启动到 initramfs / SSH，屏幕可以不亮。**

这一步只做最小 DTS，把"能不能活"验证掉。

#### 1.1 写基础 DTS

新建 `arch/arm64/boot/dts/qcom/msm8996-leeco-x2.dts`，**以 ZTE Axon 7 为模板**（`msm8996-zte-axon7.dtsi`）：
它是唯一 1440×2560 + bonded dual-DSI 的 8996 先例，且与 x2 共用 `nxp,tfa9890` 和 `qca6174-bt`。

最小可用集合：

```dts
/dts-v1/;
#include "msm8996-v3.0.dtsi"      /* v3 用这个，不是 msm8996pro.dtsi */
#include "pm8994.dtsi"
#include "pmi8996.dtsi"           /* x2 是 PMI8996 */

/ {
    model = "LeEco Le Max 2";
    compatible = "leeco,x2", "qcom,msm8996";
    chassis-type = "handset";
    qcom,msm-id = <246 0x30001>;
    qcom,board-id = <0x08 0x2e>;
    qcom,pmic-id = <0x20009 0x10013 0x00 0x00>;
};
```

然后逐块加：`&ufshc`（存储，**最先要做，否则起不来**）、`&usb3`/`&dwc3`、`&tlmm`、`&blsp1_uart2`（串口调试）。

#### 1.2 加 lk2nd 支持（2 处改动）

```bash
# 1. 新建 lk2nd/device/dts/msm8996/msm8996-leeco-x2.dts
#    内容抄 msm8996-oneplus3.dts，改 model/compatible/board-id
# 2. 在 lk2nd/device/dts/msm8996/rules.mk 的 ADTBS += 加：
#    $(LOCAL_DIR)/msm8996-leeco-x2.dtb
```

```dts
/dts-v1/;
#include <skeleton64.dtsi>
#include <lk2nd.dtsi>

/ {
    qcom,msm-id = <246 0x30001>;
    qcom,board-id = <0x08 0x2e>;
    qcom,pmic-id = <0x20009 0x10013 0x00 0x00>;
};

&lk2nd {
    model = "LeEco Le Max 2";
    compatible = "leeco,x2";
    gpio-keys { /* 音量键，抄 oneplus3 */ };
};
```

**验收（阶段 1 里程碑）**：
- `lk2nd` 能显示自己的菜单（说明 board-id 匹配成功）
- 主线内核能启动、能进 initramfs、`dmesg` 无致命 panic
- UFS 被识别（`/dev/sda*` 出现）
- USB 网络可用（能 `ssh` 进去）

---

### 阶段 2：显示（最大工作量，2–4 人周）

**目标：屏幕点亮，能显示画面。**

x2 面板驱动不存在，需要新写 `drivers/gpu/drm/panel/panel-sharp-le-x2.c`。

**基底选 `panel-samsung-s6e3ha2.c`**，理由：
- 它的 mode 就是 `hdisplay = 1440, vdisplay = 2560` —— 与 x2 **完全一致**
- 它是 `MIPI_DSI_MODE_VIDEO_*`，x2 也是 `dsi_video_mode`
- 同目录同风格，改起来最省事

**双链路写法参考** `panel-novatek-nt36523.c` 的 `is_dual_dsi` / `mipi_dsi_dual_dcs_write_seq_multi()`。

**DTS 侧（关键，抄 Axon 7 结构）：**

```dts
&mdss_dsi0 {
    status = "okay";
    qcom,dual-dsi-mode;
    qcom,master-dsi;          /* dsi0 是主 */
    qcom,sync-dual-dsi;
    vddio-supply = <&vreg_l14a_1p8>;
    vdda-supply  = <&vreg_l2a_1p25>;
};

&mdss_dsi1 {
    status = "okay";
    qcom,dual-dsi-mode;
    qcom,sync-dual-dsi;       /* 从机不写 master-dsi */
    vddio-supply = <&vreg_l14a_1p8>;
    vdda-supply  = <&vreg_l2a_1p25>;
};

&mdss_dsi0_out {  remote-endpoint = <&panel_in>; };
&mdss_dsi1_out {  remote-endpoint = <&panel_in>; };   /* 两条链路同一个面板 */
```

**x2 面板参数（从 Android DTS 实测，直接拿来用）：**

```
分辨率：单链路 720×2560，双链路合成 1440×2560 @60Hz
type  ：dsi_video_mode
时序  ：hfp=154  hbp=100  hpw=10
        vbp=7    vfp=8    vpw=1
t-clk ：pre=0x30  post=0x0d
```

⚠️ **4 家屏厂陷阱**：x2 同板有 sharp / truly / boe / ofilm 四个供应商，
**truly 是 cmd_mode，sharp 是 video_mode**。不能只看 DTS 就假定，要靠面板 ID 读取判断。
PVT 量产机实测用 sharp。

**验收**：屏幕点亮、分辨率正确、无花屏/撕裂、背光可调。

---

### 阶段 3：外设（3–5 人周）

按优先级做，每块独立可验收：

| 顺序 | 模块 | 驱动 | 备注 |
|---|---|---|---|
| 1 | 触摸 | `atmel_mxt_ts` | 已启用，只需 DTS 节点（I2C 12-0x4A） |
| 2 | 按键/音量 | `gpio-keys` | 抄 oneplus3 |
| 3 | 电池/充电 | `qcom-smbchg` + `qcom_fg` | ⚠️ smb1351 并联 IC 无驱动，可能需 hack |
| 4 | WiFi | `ath10k_pci` | 需从 `/vendor/firmware/wlan/qca_cld/wlan_mac.bin` 提校准 |
| 5 | 蓝牙 | `hci_qca` | UART ttyHS0，需 `btfw32.tlv`+`btnv32.bin` |
| 6 | 音频 | `wcd9335` + `tfa989x` | 与 oneplus3 同构，最容易 |
| 7 | 传感器 | `bmi160` + `ak8975`(AK09911) | 注意 x2 走 SSC/SLIMbus，需改 I2C |
| 8 | GPU | `msm` (a5xx) | `mesa-egl`，Nura 包已含 |
| 9 | 调制解调器 | `qcom_q6v5_mss` | 需 dump `mba.mbn`/`modem.mbn`，最难 |
| — | 指纹 | ❌ 无驱动 | QBT1000，放弃 |
| — | 相机 | ❌ 无驱动 | 放弃 |

---

### 阶段 4：打包进 Nura（1–2 人周）

#### 4.1 建 device 包

抄 `device/testing/device-xiaomi-scorpio`（**唯一未归档的 8996 设备**），7 个文件：

```
device/testing/device-leeco-x2/
├── APKBUILD
├── deviceinfo
├── modules-initfs
├── 30-gpu-firmware.files
├── device-leeco-x2-openrc.post-install
├── pointercal
└── phoc.ini
```

`deviceinfo` 初稿（flash 偏移经实测确认）：

```sh
deviceinfo_format_version="0"
deviceinfo_name="LeEco Le Max 2"
deviceinfo_manufacturer="LeEco"
deviceinfo_codename="leeco-x2"
deviceinfo_year="2016"
deviceinfo_dtb="qcom/msm8996-leeco-x2"
deviceinfo_append_dtb="true"
deviceinfo_arch="aarch64"
deviceinfo_flash_kernel_on_update="true"

deviceinfo_drm="true"
deviceinfo_chassis="handset"
deviceinfo_screen_width="1440"
deviceinfo_screen_height="2560"
deviceinfo_rootfs_image_sector_size="4096"

deviceinfo_flash_method="fastboot"
deviceinfo_generate_bootimg="true"
deviceinfo_flash_offset_base="0x80000000"
deviceinfo_flash_offset_kernel="0x00008000"
deviceinfo_flash_offset_ramdisk="0x01000000"
deviceinfo_flash_offset_second="0x00f00000"
deviceinfo_flash_offset_tags="0x00000100"
deviceinfo_flash_pagesize="4096"
deviceinfo_flash_sparse="true"
```

⚠️ **注意**：`deviceinfo_kernel_cmdline` 在 Nura **已废弃**，改用设备包内独立的 `kernel-cmdline.conf`。

#### 4.2 内核包

主线内核包 `linux-postmarketos-qcom-msm8996` 已存在（6.19.5），
需要：
1. 把 x2 的 DTS + 面板驱动提交到 `msm8996-mainline/linux`（或本地 patch）
2. 在 `config-postmarketos-qcom-msm8996.aarch64` 加 `CONFIG_DRM_PANEL_SHARP_LE_X2=m`
3. 确认 `CONFIG_TOUCHSCREEN_ATMEL_MXT=y`、`CONFIG_BMI160_I2C=y` 等（当前是 `m` 或未设）

#### 4.3 固件包

`firmware-leeco-x2`：从 `/vendor/firmware/` 和 `modem` 分区提取
（`wlan_mac.bin`、`btfw32.tlv`、`btnv32.bin`、`mba.mbn`、`modem.mbn`、a5xx `a530_pm4.fw` 等）。

**验收（阶段 4 里程碑）**：
- `pmbootstrap install` 能出镜像
- 能刷入并开机进入 Phosh/GNOME
- WiFi 可连、触摸可用、电量显示正常

---

## 4. 风险与对策

| 风险 | 概率 | 影响 | 对策 |
|---|---|---|---|
| 面板驱动写不出来 / 花屏 | 中 | 高 | 先验证 `s6e3ha2` 基底能否点亮；退路：只跑 cmdline/SSH |
| 双链路时序不对齐 | 中 | 高 | `qcom,sync-dual-dsi` 已支持；参考 Axon7 |
| 4 家屏厂变体混 | 中 | 中 | 面板 ID 探测；先只支持 sharp（PVT 实测） |
| 充电 IC smb1351 无驱动 | 高 | 中 | 先只做基本充电；或 fork 驱动 |
| 调制解调器起不来 | 高 | 中 | 先接受无通话；后期 dump mbn 攻坚 |
| DTB 选错导致不开机 | 低 | 高 | 用 lk2nd 绕开 QCDT；有完整备份可回滚 |
| boot.img 超 64MiB | 低 | 中 | 当前 25.8MB，余量大；必要时 `create_initfs_extra` |
| 刷机变砖 | 低 | 极高 | **阶段 0 全分区备份**，尤其 modemst1/2 |

**回滚方案**（任何时候都能救回）：
```bash
adb reboot bootloader
fastboot flash boot backup/boot.img
fastboot reboot
```

---

## 5. 时间与决策建议

**总工作量：约 8–13 人周（不含相机/指纹）；全功能 12–20 人周。**

关键是**先做阶段 1 的最小可用验证**（3–5 人周），它能回答"这台机器到底能不能跑主线"。
如果阶段 1 通了，后面都是工程量；如果阶段 1 卡死（UFS 起不来 / lk2nd 不认），
及时止损回退到"Android 侧继续折腾"更划算。

**如果目标是"日常可用"**：建议先留在 LineageOS 18.1，主线作为长期项目慢慢推。
**如果目标是"学习 + 长期可维护"**：走这条路，先把 Axon7 的 `s6e3ha3` 悬空 compatible 补上（对社区也有贡献）。

---

## 6. 立即可做的下一步

1. **今晚就能做**：阶段 0 的全分区备份（尤其 `modemst1`/`modemst2`/`fsg`）
2. **本周**：clone 三个仓库，跑通 `pmbootstrap init`，确认工具链可用
3. **接着**：写最小 DTS + lk2nd dts，验证能进 lk2nd 菜单

---

## 附：参考资料

| 内容 | 路径/链接 |
|---|---|
| 真机硬件采集报告 | [`research/research-device-hardware.md`](research/research-device-hardware.md) |
| 主线内核调研 | [`research/research-mainline-kernel.md`](research/research-mainline-kernel.md) |
| Nura/pmaports 调研 | [`research/research-nura-pmaports.md`](research/research-nura-pmaports.md) |
| Nura 改名公告 | https://nura.eco/blog/2026/09/27/nura-rename/ |
| pmaports | https://gitlab.nura.eco/nura/pmaports |
| msm8996 主线内核 | https://gitlab.com/msm8996-mainline/linux |
| lk2nd | https://github.com/msm8916-mainline/lk2nd |
| 最接近模板 | `device/testing/device-xiaomi-scorpio` |
| 面板基底 | `panel-samsung-s6e3ha2.c`（1440×2560） |
| 双链路参考 | `msm8996-zte-axon7.dtsi`、`panel-novatek-nt36523.c` |
| Android 侧 DTS 参考 | `android_kernel_leeco_msm8996/arch/arm/boot/dts/qcom/leeco/` |
