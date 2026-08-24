
# TWRP Device Tree for OnePlus Turbo 6V

The TWRP (Team Win Recovery Project) device tree repository for the **OnePlus Turbo 6V (codename: OP64D3L1)**.  
This device uses **a dedicated recovery partition** – it has a separate `/recovery` partition. TWRP is built as a `recovery.img` and flashed to the recovery partition.

## Device Specifications

| Feature | Details |
| ---- | ---- |
| Codename | OP64D3L1 |
| Model | OnePlus Turbo 6V |
| Chipset | Qualcomm Snapdragon 7s Gen 4 (SM7635-AC) |
| CPU Architecture | ARM64‑v8A (Octa‑core: 1×2.7GHz A720 + 3×2.4GHz A720 + 4×1.8GHz A520) |
| Kernel Version | Linux 6.1 (stock) |
| RAM | 8GB / 12GB |
| Storage | 128GB / 256GB / 512GB UFS |
| Battery | 8760mAh (rated) / 9000mAh (typical) Li‑Po |
| Display | 6.78 inches, AMOLED, 2772×1272 pixels, 144Hz |
| Rear Camera | 50MP + 2MP |
| Front Camera | 16MP |
| Platform | Qualcomm SM7635 |
| Android Version | 16 (ColorOS 16.0) |

## Compatibility
- This device tree is built for **TWRP 16.0** (Android 16.0 base)
- Compatible with OnePlus Turbo 6V (OP64D3L1/PLY110) variants
- Supports stock firmware based on Android 16

## Important Notes about Recovery Partition
The device **has** a dedicated `/recovery` partition. Normal boot and recovery boot are independent:

- Normal boot: uses the normal `boot` partition
- Recovery boot: uses the separate `recovery` partition

## Features
### Working
- ✅ ADB access
- ✅ MTP
- ✅ Decryption (with proper crypto support)
- ✅ Touchscreen
- ✅ Internal storage / USB-OTG mount
- ✅ Backup & Restore
- ✅ Flashing ZIP/IMG files
- ✅ Reboot to system/recovery/bootloader
- ✅ Vibration

### Not Working
- ✅ None (Full functional TWRP)

---

## Build Instructions

### 1. Initialize TWRP Source (branch twrp-16.0)
```bash
mkdir twrp && cd twrp
repo init --depth=1 -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git -b twrp-16.0
```

### 2. Sync Source
```bash
repo sync -j$(nproc --all) --force-sync
```

### 3. Clone Device Tree
```bash
git clone https://github.com/rtyutechstudio/android_device_OnePlus_OP64D3L1-twrp ./device/oneplus/OP64D3L1
```

### 4. No Source Modifications Needed
Unlike MTK/SPRD recovery-as-boot devices, this device does **not** require any TWRP core source changes.  
The `twrpfastboot=1` flag is not appended because we do not use `BOARD_USES_RECOVERY_AS_BOOT`.  
You can skip this step entirely.


### 5. Set Up Build Environment
```bash
source build/envsetup.sh
lunch twrp_OP64D3L1-eng
```

### 6. Build Recovery Image (not boot!)
```bash
mka recoveryimage -j$(nproc --all)
```

The output image will be located at:
```
out/target/product/OP64D3L1/recovery.img
```


---

## Installation Instructions

### Prerequisites
- Unlocked bootloader
- Fastboot installed on PC
- USB debugging enabled

### Flash via Fastboot (recovery partition)
```bash
fastboot flash recovery recovery.img
fastboot reboot recovery
```

To enter recovery after flashing, press the **Volume Down + Power** (or the key combination specific to your device) during boot, or use:
```bash
adb reboot recovery
```

---

## Notes
- This device tree is **only for OP64D3L1** (OnePlus Turbo 6V, PLY110)
- Do **not** flash on any other OnePlus/Qualcomm devices
- Backup all data before flashing custom recovery
- Because this replaces the **recovery** partition, ensure your stock recovery image is backed up in case you need to revert
- **SELinux**: Enforcing is recommended for production; permissive is allowed for debugging

## Credits
- TWRP Team for recovery source
- github@rtyutechstudio (coolapk@cuoxianxu)
- Contributors to Qualcomm device development
- Special thanks to the community for clarifying partition structures and build flags

---

**Use this software at your own risk. The authors are not responsible for bricked devices or data loss.**

---

