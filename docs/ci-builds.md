# 在 GitHub Actions 上编译

## 为什么用 CI

主线内核编译需要 **4–8 GB 内存 + 数十 GB 磁盘**。本机 15.7 GB 总内存、空闲约 2 GB，
跑 `make -j16 Image.gz` 会因 OOM 失败。GitHub Actions 的 `ubuntu-24.04` runner 提供：

| 资源 | 规格 |
|---|---|
| CPU | 4 核 |
| 内存 | **16 GB** |
| 磁盘 | 14 GB SSD，清理预装目录后可释放 ~40–100 GB |
| 单次时限 | 6 小时（本仓库限制 120 分钟） |

结论：**完全够用**。已验证同一账号下的仓库跑过 5 小时的任务。

## 工作流

### `kernel.yml` — 内核 + DTB（当前主力）

手动触发，或 `kernel/` 目录有改动时自动跑。做的事：

1. 清理磁盘、装 `clang/lld/llvm/dtc`
2. `git clone --depth 1 --branch v6.19.5-msm8996` 拉主线 msm8996 内核
3. 把 `kernel/patches/0001-arm64-dts-qcom-add-LeEco-Le-Max-2.dts` 拷成
   `arch/arm64/boot/dts/qcom/msm8996-leeco-x2.dts`
4. 在 `Makefile` 里注册这个 dtb
5. `make defconfig` + 强制打开关键选项（UFS / DRM / 触摸 / pinctrl / WiFi）
6. `make Image.gz modules dtbs`
7. 用 `dtc` 反编译验证 dtb 里确实带 `qcom,msm-id` / `qcom,board-id`
8. 上传 `Image.gz` + `msm8996-leeco-x2.dtb` + SHA256

**产物怎么用**：下载 artifact，本地解压后拿到 `Image.gz` 和 `.dtb`。

### `nura-image.yml` — 完整 Nura 镜像（未验证）

用 pmbootstrap 在 privileged 容器里构建 rootfs。

⚠️ **这个还不能用**，原因：
- 需要内核包先提供 `qcom/msm8996-leeco-x2.dtb`（即 `kernel.yml` 的产物要先合入内核包）
- pmbootstrap 的 CLI 参数在不同版本间有变化，脚本里的写法**未经验证**
- 脚本里调用 `pmbootstrap init --help` 把真实用法打进日志，第一次跑请先看日志再改

## 触发方式

```bash
# 内核编译（默认参数）
gh workflow run kernel.yml --repo minghao680/leeco-x2-nura

# 指定内核版本
gh workflow run kernel.yml --repo minghao680/leeco-x2-nura \
  -f kernel_ref=v6.19.5-msm8996

# 看进度
gh run list --repo minghao680/leeco-x2-nura
gh run watch --repo minghao680/leeco-x2-nura
```

## 拉到本地刷机

```bash
gh run download --repo minghao680/leeco-x2-nura -n kernel-x2-<run_number> -D ./out
cd out && sha256sum -c SHA256SUMS

# 只测内核启动（不写 boot 分区，最安全）
adb reboot bootloader
fastboot boot Image.gz-dtb        # 需要先拼 Image.gz + dtb

# 正式刷入 lk2nd 后再由 lk2nd 加载
fastboot flash boot lk2nd.img
```

## 磁盘不够时的处理

`kernel.yml` 里已清理 `/usr/share/dotnet`、`/usr/local/lib/android`、
`/opt/ghc`、`/opt/hostedtoolcache/CodeQL` 等。如果 `df` 显示仍不足，
可以再加 `sudo rm -rf /opt/az /usr/local/share/powershell /usr/share/swift`。

内核源码本身约 1.5 GB（浅克隆），编译产物约 2–3 GB，14 GB 原始盘够用。
