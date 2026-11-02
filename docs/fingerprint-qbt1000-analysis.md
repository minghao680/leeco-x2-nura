# 指纹驱动逆向分析：QBT1000（Le Max 2 指纹方案）

> 2026-11-03 · 基于 vendor 内核源码静态分析
> 结论先行：**主线移植不可行，维持"放弃"决定**——但有三个可回收的副产品（按键事件、
> 休眠唤醒、供电上电时序），详见文末。

## 1. 硬件与连接方式

- 方案名：QBT1000（Qualcomm 指纹平台方案的代号）
- **传感器挂在 SSC（Snapdragon Sensor Core）专用的 SPI 总线上**，而不是 AP 直接控制：

```
arch/arm/boot/dts/qcom/msm8996.dtsi:2596
qcom,qbt1000 {
    compatible = "qcom,qbt1000";
    qcom,fingerprint-sensor-ssc-spi-conn {
        qcom,spi-port-id = <2>;            /* BLSP SPI 端口 2 */
        qcom,spi-port-slave-index = <0>;
        qcom,tz-subsys-id = <1>;           /* TZ 子系统 */
        qcom,ssc-subsys-id = <5>;          /* SSC 子系统 */
        clock-frequency = <15000000>;      /* 15 MHz */
    };
};
```

- 注意 DTS 里**没有**传感器的 GPIO/中断/供电描述——因为 AP 根本不直接碰硬件。

## 2. 内核驱动的真实角色（drivers/soc/qcom/qbt1000.c，1435 行）

内核只是个**消息搬运工**，四条链路：

| 链路 | 机制 | 用途 |
|---|---|---|
| 用户态 ↔ 内核 | char 设备 `qbt1000`，ioctl 100/101/102（LOAD_APP / UNLOAD_APP / SEND_TZCMD），UAPI 见 `include/uapi/linux/qbt1000.h` | fingerprintd 加载/驱动 TZ 应用 |
| 内核 ↔ TrustZone | QSEECom（`qseecom_kernel.h`），加载名为 **"fingerpr"** 的专有 TZ 应用（缓冲 256KB） | 指纹识别算法/传感器固件全在 TZ 应用里 |
| 内核 ↔ SSC | QMI service 0x138（sns_common_v01.idl） | 通过传感器核心代理 SPI 事务 |
| 内核 ↔ TZ | SCM 调用 `TZ_BLSP_MODIFY_OWNERSHIP`（svc 4 / func 3，资源锁服务） | 把 SPI 总线所有权在 SSC ↔ APPS 之间切换 |

- 事件回传：TZ 应用 → 内核 input 设备 `qbt1000_key_input`（Home 键/手势），由
  fingerprintd 上报。
- 用户态组件（Android 侧 fingerprintd + 厂商 HAL + TZ 应用二进制）全部闭源，
  内核源码树里没有。

## 3. 主线移植可行性

**不可行**，原因按致命程度排序：

1. **识别逻辑在 TZ 专有应用 "fingerpr" 里**：主线内核没有 QSEECom 加载接口，
   加载 TZ 应用本身需要 QSEE 的签名/会话机制。
2. **SPI 总线默认所有权在 SSC/TZ**：AP 想直接访问传感器必须先通过 SCM 切换所有权
   （主线理论上可以发这个 SCM 调用，但接下来…）
3. **不知道传感器 IC 型号和寄存器协议**：DT 没有任何器件信息，一切封装在 TZ 应用里。
   没有协议文档就写不出驱动。
4. **缺少 SSC 固件栈**：即便走 SSC 路径，主线也没有对应的消息框架实现。

> 现实定位：x2 的指纹在主线/Nura 上只能走"电源键 + 密码"。
> 若未来要硬啃：需要先从固件分区提取 fingerpr TZ 应用并逆向其 SPI 协议
> （工作量大、且涉及签名校验），或用逻辑分析仪在真机上抓 SSC↔传感器总线波形。

## 4. 可回收的三个副产品

1. **Home 键事件**：`qbt1000_key_input` 在 vendor 上承担"按压=Home"的输入事件。
   主线下用户失去指纹 Home 键的"按键"功能——检查 x2 的 Home 是否有独立 GPIO：
   vendor dt 里没有独立 gpio-key → **Home 按键大概率也走传感器**（触摸即按键），
   主线侧无解，UI 交互需完全依赖屏幕导航。
2. **休眠唤醒**：指纹唤醒（Gesture/wakeup）由 TZ 应用经内核 input 层注入。
   主线下不可用；唤醒源只剩电源键/充电插拔。
3. **若某天传感器被确认是 FPC 系 IC**：FPC1020/1155 系在别的设备有主线驱动
   （spi + irq + cdev），届时可尝试：SCM 切 BLSP 所有权 → 按对应 FPC 驱动试探。
   前提是先确认 IC 型号（拆机看丝印，或从 fingerpr 应用字符串里找线索）。

## 5. 证据文件清单

- `drivers/soc/qcom/qbt1000.c` — 驱动主体（probe:1256，时钟/所有权/QMI 逻辑）
- `include/uapi/linux/qbt1000.h` — ioctl 三命令与结构体
- `arch/arm/boot/dts/qcom/msm8996.dtsi:2596-2606` — SSC-SPI 连接描述
- `include/soc/qcom/scm.h` + `qseecom_kernel.h` — SCM/QSEECom 接口
