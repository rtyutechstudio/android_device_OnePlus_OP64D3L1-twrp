# Copyright (C) 2026 The TWRP Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_base.mk)

# Inherit some common Twrp stuff.
$(call inherit-product, vendor/twrp/config/common.mk)

# Inherit from OP64D3L1 device
$(call inherit-product, device/oneplus/OP64D3L1/device.mk)
PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE := false


PRODUCT_DEVICE := OP64D3L1
PRODUCT_NAME := twrp_OP64D3L1
PRODUCT_BRAND := oneplus
PRODUCT_MODEL := OP64D3L1
PRODUCT_MANUFACTURER := oneplus
BUILD_FINGERPRINT := oplus/ossi/ossi:14/UKQ1.231108.001/1780037472654:eng/release-keys
