# LeEco Le Max 2 (x2 / LEX820) → Nura (原 postmarketOS) 主线移植

把乐视 Le Max 2 移植到 [Nura](https://nura.eco)（postmarketOS 于 2026-09-27 更名为 Nura），使用**主线内核**。

> 本文档与 `PMOS-PORTING-PLAN.md`（移植计划）配套。计划文档在工作区上级目录，本仓库是**实际代码**。

## 设备规格

| 项目 | 值 |
|---|---|
| 代号 | `x2`（内核）/ 拟用 pmaports codename `leeco-x2` |
| 型号 | LEX820 |
| SoC | **MSM8996 v3**（骁龙 820，非 8996Pro） |
| PMIC | PMI8996 |
| 屏幕 | Sharp 5.7" **1440×2560** dual-DSI（单链路 720×2560），video mode @60Hz |
| 触摸 | Atmel mXT T100（I2C 12-0x4A） |
| WiFi/BT | QCA6174（ath10k）+ QCA Rome（hci_qca） |
| 存储 | Samsung KLUCG4J1CB-B0B1 UFS 2.0 |
| 传感器 | BMI160 + AK09915 + PA22A |
| 音频 | WCD9335 + TFA9890（**无 ESS DAC**） |
| 指纹 | QBT1000（主线无驱动，功能缺失） |

## 引导链关键参数

写 DTS / lk2nd 必须用这些值（已从真机 `/proc/device-tree` 实测）：

```
qcom,msm-id   = <246 0x30001>          # = <0xf6 0x30001>
qcom,board-id = <0x08 0x2e>
qcom,pmic-id  = <0x20009 0x10013 0x00 0x00>
```

boot.img 关键偏移（header v0）：

```
kernel_addr = 0x80008000
ramdisk_addr= 0x81000000
tags_addr   = 0x80000100
page_size   = 4096
```

## 为什么用 GitHub Actions 编译

主线内核编译大约需要 **4–8 GB 内存 + 数十 GB 磁盘**，本地机器（15.7 GB / 空闲 2.3 GB）跑不动。
GitHub Actions 的 `ubuntu-latest` runner 提供 4 核 / 16 GB / 14 GB SSD（+ 可清理出 ~100 GB），足够。

**CI 不做的事**：不刷机。产物下载后由本地 `fastboot` 刷入。

## 仓库结构

```
device/leeco-x2/          # pmaports 设备包（提交给 nura/pmaports 的内容）
kernel/patches/           # 内核补丁（DTS + 面板驱动），可 rebase 到新版本
lk2nd/                    # lk2nd 设备支持（提交给 msm8916-mainline/lk2nd）
.github/workflows/        # CI：内核编译 / 设备包构建 / 镜像打包
scripts/                  # 本地辅助脚本
```

## 当前进度

- [x] 设备硬件基线采集（见计划文档）
- [x] 全分区备份
- [x] 仓库骨架
- [ ] 阶段 1：最小 DTS + lk2nd，验证能启动
- [ ] 阶段 2：显示（面板驱动）
- [ ] 阶段 3：外设
- [ ] 阶段 4：打包进 pmaports

## 上游参考

| 用途 | 链接 |
|---|---|
| Nura 官网 | https://nura.eco |
| pmaports | https://gitlab.nura.eco/nura/pmaports |
| 主线内核（msm8996） | https://gitlab.com/msm8996-mainline/linux |
| lk2nd | https://github.com/msm8916-mainline/lk2nd |
| 最接近的模板设备 | `device/testing/device-xiaomi-scorpio` (小米 Note 2) |
| dual-DSI dts 先例 | `msm8996-zte-axon7.dtsi` |
| 面板驱动基底 | `panel-samsung-s6e3ha2.c` (1440×2560 video mode) |

## 免责声明

刷机有风险。请先备份全部分区（尤其 `modemst1`/`modemst2`/`fsg`/`persist`），这些数据不可再生。
本仓库代码目前处于**早期开发阶段，未经验证**。
