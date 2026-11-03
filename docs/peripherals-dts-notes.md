# 外围设备 DTS 证据与集成说明

> 2026-11-03 · 由外围调研代理产出，集成进板级 DTS 的证据存档
> 所有 file:line 均基于 vendor 树 `android_kernel_leeco_msm8996`（arm64 qcom dts）
> 与主线 `msm8996-mainline/linux` HEAD。

## BLSP 映射（vendor → 主线节点名）

| vendor | 主线 | 引脚 | 用途 |
|---|---|---|---|
| i2c_6@757a000 | blsp1_i2c6 | - | CC 控制器（暂不启用） |
| i2c_8@75b6000 | **blsp2_i2c2** | gpio6/7 | TFA9890 功放 |
| i2c_9@75b7000 | **blsp2_i2c3** | gpio51/52 | DRV2604L 振动 |
| i2c_12@75ba000 | **blsp2_i2c6** | gpio87/88 | Atmel 触摸 @0x4a |
| uart@7570000 (blsp1_uart2) | **blsp1_uart2** | gpio41-44 | **蓝牙** QCA Rome |
| uart@75b0000 (blsp2_uart2) | **blsp2_uart2** | gpio4/5 | 调试串口（console） |

## 已启用节点与证据

| 节点 | 关键参数 | vendor 证据 |
|---|---|---|
| 触摸 mXT @0x4a | IRQ=GPIO125 低电平, RESET=GPIO89, AVDD=l22 3.3V, VDD_IO=l14 1.8V | letv-tp-atmel_mxt_ts-le_x2-dvt1.1.dtsi:3-13; pinctrl msm8996-pinctrl.dtsi:737-761 |
| 蓝牙 qca6174 | BT_EN=PM8994 gpio19, 睡眠时钟=pm8994 gpio18 func2 32.768k | mtp-le-common.dtsi:16-26, gpio@d100 |
| WiFi QCA6174 | WLAN_EN=pm8994 gpio8（startup 70ms）, PERST=35/CLKREQ=36/WAKE=37, Rome 3.3V=pm8994 gpio9 常高 | mtp-le-common.dtsi:796-815; pinctrl:1228-1294 |
| 振动 DRV2604L | @0x5a, EN=GPIO38, LRA, 1600/2600mV | le_x2-dvt1.dtsi:387-401 |
| 功放 TFA9890 | @0x34（主线驱动不需要 IRQ122/RESET90/供电） | le_x2-dvt1.dtsi:356-364 |
| 音频 WCD9335 | slim217,1a0 reg<1,0>, 复位=GPIO64, intr1=GPIO54, 全供电=s4 1.8V, MCLK=pm8994 gpio15 func1 | vendor msm8996.dtsi:931-1005, 923-925, 851-859 |
| USB | HS-only（vendor 未接 QMP SS 路径），VBUS 由 CCG2 硬件管理，peripheral 模式 | le-common.dtsi:329-332; qusb 供电 l12/l24 |
| 新增电压轨 | l14 1.8V / l22 3.3V / l24 3.075V | msm8996-regulator.dtsi:228/325/345 |

## 尚无法启用（主线无驱动）

- **充电 + 电量计**：smbcharger / smb1351 / BMS —— USB 电流与充电类型检测不可用
- **USB Type-C CC**：Cypress CCG2 @0x08 —— 无角色切换/extcon（因此 periph-only）
- **NFC**：nq-nci @0x28（主线有 pn544 但芯片代次未证实，需固件）—— 暂缓
- **红外**：qcom,ir-remote（MAXQ616）—— vendor 驱动 only
- **传感器/IMU**：vendor DT 里就没有节点（跑在 SLPI 上），无从移植
- **指纹**：任何 x2 dts 均无指纹节点（见 docs/fingerprint-qbt1000-analysis.md）
- **扬声器出声**：TFA9890 有 DAI 但 apq8096-sndcard 尚未接线，耳机路径先行
- 音频整体依赖 **adsp 固件**（qcom/msm8996/adsp.mbn），无固件则 Q6 dai 不出现

## 与 gpio-reserved-ranges 的交互

- GPIO81-84：81 是 CC 逻辑 p-on 脚，vendor 特意保留 → 保留范围正确
- GPIO0-3：BLSP1 SPI1 引脚，x2 未用 → 保留安全（但会挡未来 SPI 指纹）
- 本片段新引用的所有引脚均在两个保留区之外；PM8994 GPIO 是独立控制器不受影响

## 电源键

主线 pm8994.dtsi 的 pon@800 默认启用 pwrkey（KEY_POWER）——无需改动。
