# Le Max 2 移植进度

## 阶段 0：准备 ✅

- [x] 硬件基线采集（分区/面板/触摸/WiFi/基带/传感器）
- [x] 全分区备份（59 个，721.8 MiB，SHA256 全部校验通过）
- [x] 新建仓库 `leeco-x2-nura`

## 阶段 1：最小可启动（进行中）

- [x] 初版 DTS `kernel/patches/0001-...dts`
- [x] lk2nd 设备支持 `lk2nd/msm8996-leeco-x2.dts`
- [x] CI 内核编译工作流
- [x] **DTB 在 CI 上编译通过**（2026-11-02，board id 全部核对无误）
- [ ] lk2nd 编译并确认能识别板子
- [ ] 内核能启动到 initramfs
- [ ] UFS 被识别

### 待验证的风险

1. **DTS 的 regulator 配置是照抄 oneplus3 的**，x2 的实际供电轨可能不同。
   影响：如果 UFS 供电不对，存储起不来。需要从 stock DT 里读真实 phandle 来对照。
2. **`msm8996.dtsi` 的 msm-id 是 `<246 0x30001>`**，与实测一致；但
   `msm8996-v3.0.dtsi` 是 `0x30000`，所以本 DTS 没有 include 后者。这点已在文件头注明。
3. **`gpio-reserved-ranges = <0 4>, <81 4>`** 是从 Android DT 推测的，未严格核实。

## 阶段 2：显示（未开始）

- [ ] 写 `panel-sharp-le-x2.c`（基底 `panel-samsung-s6e3ha2.c`）
- [ ] dual-DSI 双链路 DTS 接线
- [ ] 背光

已知参数（从 Android DTS 实测）：

```
单链路 720x2560 → 合成 1440x2560 @60Hz
type: dsi_video_mode
hfp=154 hbp=100 hpw=10
vbp=7 vfp=8 vpw=1
t-clk-pre=0x30 t-clk-post=0x0d
```

## 阶段 3：外设（未开始）

按优先级：触摸 → 按键 → 电池 → WiFi → 蓝牙 → 音频 → 传感器 → GPU → 调制解调器

## 阶段 4：打包进 pmaports（未开始）

- [x] device 包骨架 `device/leeco-x2/`
- [ ] 内核包补丁（DTS + 面板驱动进 `linux-postmarketos-qcom-msm8996`）
- [ ] 固件包 `firmware-leeco-x2`
- [ ] 上游 MR

## 不做的事

- 指纹（QBT1000 无主线驱动）
- 相机（无驱动）

