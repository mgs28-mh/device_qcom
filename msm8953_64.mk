ALLOW_MISSING_DEPENDENCIES=true

ifneq ($(wildcard kernel/msm-4.19),)
    TARGET_KERNEL_VERSION := 4.19
    $(warning "Build with 4.19 kernel.")
else ifneq ($(wildcard kernel/msm-4.9),)
    TARGET_KERNEL_VERSION := 4.9
    $(warning "Build with 4.9 kernel")
else
    $(warning "Unknown kernel")
endif

# Retain the earlier default behavior i.e. ota config (dynamic partition was disabled if not set explicitly), so set
# SHIPPING_API_LEVEL to 28 if it was not set earlier (this is generally set earlier via build.sh per-target)
ifeq ($(TARGET_KERNEL_VERSION), 4.9)
  SHIPPING_API_LEVEL := 28
else
  SHIPPING_API_LEVEL := 29
endif

#### Turning BOARD_DYNAMIC_PARTITION_ENABLE flag to TRUE will enable dynamic partition/super image creation.
# Enable Dynamic partitions only for Q new launch devices and beyond.
ifeq (true,$(call math_gt_or_eq,$(SHIPPING_API_LEVEL),29))
  ENABLE_AB ?= true
  BOARD_DYNAMIC_PARTITION_ENABLE ?= true
  PRODUCT_SHIPPING_API_LEVEL := $(SHIPPING_API_LEVEL)
else
  ENABLE_AB ?= false
  BOARD_DYNAMIC_PARTITION_ENABLE ?= false
  $(call inherit-product, build/make/target/product/product_launched_with_p.mk)
endif

ifeq (true,$(call math_gt_or_eq,$(SHIPPING_API_LEVEL),29))
 # f2fs utilities
 PRODUCT_PACKAGES += \
     sg_write_buffer \
     f2fs_io \
     check_f2fs

 # Userdata checkpoint
 PRODUCT_PACKAGES += \
     checkpoint_gc

 ifeq ($(ENABLE_AB), true)
 AB_OTA_POSTINSTALL_CONFIG += \
     RUN_POSTINSTALL_vendor=true \
     POSTINSTALL_PATH_vendor=bin/checkpoint_gc \
     FILESYSTEM_TYPE_vendor=ext4 \
     POSTINSTALL_OPTIONAL_vendor=true
 endif
endif

ifeq ($(strip $(BOARD_DYNAMIC_PARTITION_ENABLE)),true)
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_PACKAGES += fastbootd
# Add default implementation of fastboot HAL.
PRODUCT_PACKAGES += android.hardware.fastboot@1.0-impl-mock
  ifeq ($(TARGET_KERNEL_VERSION), 4.9)
    ifeq ($(ENABLE_AB), true)
      PRODUCT_COPY_FILES += $(LOCAL_PATH)/fstabs-4.9/fstab_AB_dynamic_partition_variant.qti:$(TARGET_COPY_OUT_RAMDISK)/fstab.qcom
    else
      PRODUCT_COPY_FILES += $(LOCAL_PATH)/fstabs-4.9/fstab_non_AB_dynamic_partition_variant.qti:$(TARGET_COPY_OUT_RAMDISK)/fstab.qcom
    endif
  else
    ifeq ($(ENABLE_AB), true)
      PRODUCT_COPY_FILES += $(LOCAL_PATH)/fstabs-4.19/fstab_AB_dynamic_partition_variant.qti:$(TARGET_COPY_OUT_RAMDISK)/fstab.qcom
    else
      PRODUCT_COPY_FILES += $(LOCAL_PATH)/fstabs-4.19/fstab_non_AB_dynamic_partition_variant.qti:$(TARGET_COPY_OUT_RAMDISK)/fstab.qcom
    endif
  endif
endif

# Enable AVB 2.0
BOARD_AVB_ENABLE := true
ifeq ($(strip $(BOARD_DYNAMIC_PARTITION_ENABLE)),true)
# Enable product partition
PRODUCT_BUILD_PRODUCT_IMAGE := true
# enable vbmeta_system
BOARD_AVB_VBMETA_SYSTEM := system product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 2
$(call inherit-product, build/make/target/product/gsi_keys.mk)
endif

TARGET_USES_AOSP := false
TARGET_USES_AOSP_FOR_AUDIO := false
TARGET_USES_QCOM_BSP := false

TARGET_SYSTEM_PROP := device/qcom/msm8953_64/system.prop

ifeq ($(TARGET_USES_AOSP),true)
TARGET_DISABLE_DASH := true
endif

ifeq ($(TARGET_KERNEL_VERSION), 4.19)
#Enable llvm support for kernel
KERNEL_LLVM_SUPPORT := true

#Enable sd-llvm support for kernel
KERNEL_SD_LLVM_SUPPORT := true

#Enable libion support
LIBION_PATH_INCLUDES := true
endif

DEVICE_PACKAGE_OVERLAYS := device/qcom/msm8953_64/overlay

TARGET_USES_NQ_NFC := false

ifeq ($(TARGET_USES_NQ_NFC),true)
PRODUCT_COPY_FILES += \
    device/qcom/common/nfc/libnfc-brcm.conf:$(TARGET_COPY_OUT_VENDOR)/etc/libnfc-nci.conf
endif

TARGET_ENABLE_QC_AV_ENHANCEMENTS := true

# Default vendor configuration.
ifeq ($(ENABLE_VENDOR_IMAGE),)
ENABLE_VENDOR_IMAGE := true
endif

# Disable QTIC until it's brought up in split system/vendor
# configuration to avoid compilation breakage.
ifeq ($(ENABLE_VENDOR_IMAGE), true)
#TARGET_USES_QTIC := false
endif

# Enable features in video HAL that can compile only on this platform
TARGET_USES_MEDIA_EXTENSIONS := true

-include $(QCPATH)/common/config/qtic-config.mk

# media_profiles and media_codecs xmls for msm8953
ifeq ($(TARGET_ENABLE_QC_AV_ENHANCEMENTS), true)
PRODUCT_COPY_FILES += \
    device/qcom/msm8953_32/media/media_profiles_8953.xml:system/etc/media_profiles.xml \
    device/qcom/msm8953_32/media/media_profiles_8953.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_vendor.xml \
    device/qcom/msm8953_32/media/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml \
    device/qcom/msm8953_32/media/media_codecs_vendor.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_vendor.xml \
    device/qcom/msm8953_32/media/media_codecs_8953.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_8953.xml \
    device/qcom/msm8953_32/media/media_codecs_performance_8953.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_performance.xml \
    device/qcom/msm8953_32/media/media_codecs_performance_8953.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_performance_8953.xml \
    device/qcom/msm8953_32/media/media_profiles_8953_v1.xml:system/etc/media_profiles_8953_v1.xml \
    device/qcom/msm8953_32/media/media_profiles_8953_v1.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_8953_v1.xml \
    device/qcom/msm8953_32/media/media_codecs_8953_v1.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_vendor_v1.xml \
    device/qcom/msm8953_32/media/media_codecs_performance_8953_v1.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_performance_v1.xml \
    device/qcom/msm8953_32/media/media_codecs_vendor_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_vendor_audio.xml \
    device/qcom/common/media/media_profiles.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_V1_0.xml

# Vendor property overrides
  PRODUCT_PROPERTY_OVERRIDES += debug.stagefright.omx_default_rank=0
endif
# video seccomp policy files
# copy to system/vendor as well (since some devices may symlink to system/vendor and not create an actual partition for vendor)
PRODUCT_COPY_FILES += \
    device/qcom/msm8953_32/seccomp/mediacodec-seccomp.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediacodec.policy \
    device/qcom/msm8953_32/seccomp/mediaextractor-seccomp.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediaextractor.policy

PRODUCT_PROPERTY_OVERRIDES += \
           dalvik.vm.heapminfree=4m \
           dalvik.vm.heapstartsize=16m \
           vendor.vidc.disable.split.mode=1
$(call inherit-product, frameworks/native/build/phone-xhdpi-2048-dalvik-heap.mk)
$(call inherit-product, device/qcom/common/common64.mk)

PRODUCT_NAME := msm8953_64
PRODUCT_DEVICE := msm8953_64
PRODUCT_BRAND := qti
PRODUCT_MODEL := msm8953 for arm64

PRODUCT_BOOT_JARS += tcmiface

# Kernel modules install path
KERNEL_MODULES_INSTALL := dlkm
KERNEL_MODULES_OUT := out/target/product/$(PRODUCT_NAME)/$(KERNEL_MODULES_INSTALL)/lib/modules

ifneq ($(strip $(QCPATH)),)
PRODUCT_BOOT_JARS += WfdCommon
#PRODUCT_BOOT_JARS += com.qti.dpmframework
#PRODUCT_BOOT_JARS += dpmapi
#PRODUCT_BOOT_JARS += com.qti.location.sdk
#Android oem shutdown hook
#PRODUCT_BOOT_JARS += oem-services
endif

DEVICE_MANIFEST_FILE := device/qcom/msm8953_64/manifest.xml
ifeq ($(ENABLE_AB), true)
DEVICE_MANIFEST_FILE += device/qcom/msm8953_64/manifest_ab.xml
endif

ifeq ($(SHIPPING_API_LEVEL),29)
    DEVICE_MANIFEST_FILE += device/qcom/msm8953_64/manifest_target_level_4.xml
else
    DEVICE_MANIFEST_FILE += device/qcom/msm8953_64/manifest_target_level_3.xml
endif

DEVICE_MATRIX_FILE   := device/qcom/common/compatibility_matrix.xml
DEVICE_FRAMEWORK_MANIFEST_FILE := device/qcom/msm8953_64/framework_manifest.xml
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := \
    vendor/qcom/opensource/core-utils/vendor_framework_compatibility_matrix.xml

# default is nosdcard, S/W button enabled in resource
PRODUCT_CHARACTERISTICS := nosdcard

# When can normal compile this module,  need module owner enable below commands
# font rendering engine feature switch
#-include $(QCPATH)/common/config/rendering-engine.mk
#ifneq (,$(strip $(wildcard $(PRODUCT_RENDERING_ENGINE_REVLIB))))
#    MULTI_LANG_ENGINE := REVERIE
#    MULTI_LANG_ZAWGYI := REVERIE
#endif

ifneq ($(TARGET_DISABLE_DASH), true)
#    PRODUCT_BOOT_JARS += qcmediaplayer
endif

#
# system prop for opengles version
#
# 196608 is decimal for 0x30000 to report major/minor versions as 3/0
# 196609 is decimal for 0x30001 to report major/minor versions as 3/1
# 196610 is decimal for 0x30002 to report major/minor versions as 3/2
PRODUCT_PROPERTY_OVERRIDES += \
     ro.opengles.version=196610

#FEATURE_OPENGLES_EXTENSION_PACK support string config file
PRODUCT_COPY_FILES += \
        frameworks/native/data/etc/android.hardware.opengles.aep.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.opengles.aep.xml

#Android EGL implementation
PRODUCT_PACKAGES += libGLES_android

# Audio configuration file
-include $(TOPDIR)hardware/qcom/audio/configs/msm8953/msm8953.mk
-include $(TOPDIR)vendor/qcom/opensource/audio-hal/primary-hal/configs/msm8953/msm8953.mk

USE_LIB_PROCESS_GROUP := true

#Audio DLKM
AUDIO_DLKM := audio_apr.ko
AUDIO_DLKM += audio_q6_notifier.ko
AUDIO_DLKM += audio_adsp_loader.ko
AUDIO_DLKM += audio_q6.ko
AUDIO_DLKM += audio_usf.ko
AUDIO_DLKM += audio_pinctrl_wcd.ko
AUDIO_DLKM += audio_swr.ko
AUDIO_DLKM += audio_wcd_core.ko
AUDIO_DLKM += audio_swr_ctrl.ko
AUDIO_DLKM += audio_wsa881x.ko
AUDIO_DLKM += audio_wsa881x_analog.ko
AUDIO_DLKM += audio_platform.ko
AUDIO_DLKM += audio_cpe_lsm.ko
AUDIO_DLKM += audio_hdmi.ko
AUDIO_DLKM += audio_stub.ko
AUDIO_DLKM += audio_wcd9xxx.ko
AUDIO_DLKM += audio_mbhc.ko
AUDIO_DLKM += audio_wcd9335.ko
AUDIO_DLKM += audio_wcd_cpe.ko
AUDIO_DLKM += audio_digital_cdc.ko
AUDIO_DLKM += audio_analog_cdc.ko
AUDIO_DLKM += audio_native.ko
AUDIO_DLKM += audio_machine_sdm450.ko
AUDIO_DLKM += audio_machine_ext_sdm450.ko
AUDIO_DLKM += mpq-adapter.ko
AUDIO_DLKM += mpq-dmx-hw-plugin.ko
PRODUCT_PACKAGES += $(AUDIO_DLKM)

# MIDI feature
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.software.midi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.midi.xml

PRODUCT_PACKAGES += android.hardware.media.omx@1.0-impl

# Display/Graphics
PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.mapper@2.0-impl-2.1 \
    android.hardware.graphics.composer@2.1-impl \
    android.hardware.graphics.composer@2.1-service \
    android.hardware.memtrack@1.0-impl \
    android.hardware.memtrack@1.0-service \
    android.hardware.light@2.0-impl \
    android.hardware.light@2.0-service \
    android.hardware.configstore@1.0-service

PRODUCT_PACKAGES += wcnss_service

# SF properties
ifeq ($(call math_gt,$(SHIPPING_API_LEVEL),29),true)
PRODUCT_PROPERTY_OVERRIDES += \
    ro.surface_flinger.force_hwc_copy_for_virtual_displays=true \
    ro.surface_flinger.max_frame_buffer_acquired_buffers=3 \
    ro.surface_flinger.max_virtual_display_dimension=4096
endif

# FBE support
PRODUCT_COPY_FILES += \
	device/qcom/msm8953_64/init.qti.qseecomd.sh:$(TARGET_COPY_OUT_VENDOR)/bin/init.qti.qseecomd.sh

# VB xml
PRODUCT_COPY_FILES += \
        frameworks/native/data/etc/android.software.verified_boot.xml:system/etc/permissions/android.software.verified_boot.xml

# MSM IRQ Balancer configuration file
PRODUCT_COPY_FILES += \
    device/qcom/msm8953_64/msm_irqbalance.conf:$(TARGET_COPY_OUT_VENDOR)/etc/msm_irqbalance.conf \
    device/qcom/msm8953_64/msm_irqbalance_little_big.conf:$(TARGET_COPY_OUT_VENDOR)/etc/msm_irqbalance_little_big.conf
#wlan driver
PRODUCT_COPY_FILES += \
    device/qcom/msm8953_64/WCNSS_qcom_cfg.ini:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/WCNSS_qcom_cfg.ini \
    device/qcom/msm8953_32/WCNSS_wlan_dictionary.dat:persist/WCNSS_wlan_dictionary.dat \
    device/qcom/msm8953_64/WCNSS_qcom_wlan_nv.bin:persist/WCNSS_qcom_wlan_nv.bin

PRODUCT_PACKAGES += \
    wpa_supplicant_overlay.conf \
    p2p_supplicant_overlay.conf

#for wlan
PRODUCT_PACKAGES += \
    wificond \
    wifilogd
# Feature definition files for msm8953
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.gyroscope.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/android.hardware.sensor.barometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.barometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.stepcounter.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.stepcounter.xml \
    frameworks/native/data/etc/android.hardware.sensor.stepdetector.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.stepdetector.xml

PRODUCT_PACKAGES += telephony-ext
PRODUCT_BOOT_JARS += telephony-ext

# Defined the locales
PRODUCT_LOCALES += th_TH vi_VN tl_PH hi_IN ar_EG ru_RU tr_TR pt_BR bn_IN mr_IN ta_IN te_IN zh_HK \
        in_ID my_MM km_KH sw_KE uk_UA pl_PL sr_RS sl_SI fa_IR kn_IN ml_IN ur_IN gu_IN or_IN

# When can normal compile this module, need module owner enable below commands
# Add the overlay path
#PRODUCT_PACKAGE_OVERLAYS := $(QCPATH)/qrdplus/Extension/res \
#        $(QCPATH)/qrdplus/globalization/multi-language/res-overlay \
#        $(PRODUCT_PACKAGE_OVERLAYS)
#PRODUCT_PACKAGE_OVERLAYS := $(QCPATH)/qrdplus/Extension/res \
        $(PRODUCT_PACKAGE_OVERLAYS)

# Powerhint configuration file
PRODUCT_COPY_FILES += \
     device/qcom/msm8953_64/powerhint.xml:system/etc/powerhint.xml

#Healthd packages
PRODUCT_PACKAGES += android.hardware.health@2.0-impl \
                   android.hardware.health@2.0-service \
                   libhealthd.msm

PRODUCT_FULL_TREBLE_OVERRIDE := true

PRODUCT_VENDOR_MOVE_ENABLED := true

#for android_filesystem_config.h
PRODUCT_PACKAGES += \
    fs_config_files

# Sensor HAL conf file
 PRODUCT_COPY_FILES += \
     device/qcom/msm8953_64/sensors/hals.conf:$(TARGET_COPY_OUT_VENDOR)/etc/sensors/hals.conf

# Power
PRODUCT_PACKAGES += \
    android.hardware.power@1.0-service \
    android.hardware.power@1.0-impl

# Camera configuration file. Shared by passthrough/binderized camera HAL
PRODUCT_PACKAGES += camera.device@3.2-impl
PRODUCT_PACKAGES += camera.device@1.0-impl
PRODUCT_PACKAGES += android.hardware.camera.provider@2.4-impl
# Enable binderized camera HAL
PRODUCT_PACKAGES += android.hardware.camera.provider@2.4-service


PRODUCT_PACKAGES += \
    vendor.display.color@1.0-service \
    vendor.display.color@1.0-impl

PRODUCT_PACKAGES += \
    libandroid_net \
    libandroid_net_32

#Enable Lights Impl HAL Compilation
PRODUCT_PACKAGES += android.hardware.light@2.0-impl

TARGET_SUPPORT_SOTER := true

#set KMGK_USE_QTI_SERVICE to true to enable QTI KEYMASTER and GATEKEEPER HIDLs
ifeq ($(ENABLE_VENDOR_IMAGE), true)
KMGK_USE_QTI_SERVICE := true
endif

#Enable AOSP KEYMASTER and GATEKEEPER HIDLs
ifneq ($(KMGK_USE_QTI_SERVICE), true)
PRODUCT_PACKAGES += android.hardware.gatekeeper@1.0-impl \
                    android.hardware.gatekeeper@1.0-service \
                    android.hardware.keymaster@3.0-impl \
                    android.hardware.keymaster@3.0-service
endif

#Enable KEYMASTER 4.0 for Android P not for OTA's
ENABLE_KM_4_0 := true

ifeq ($(ENABLE_KM_4_0), true)
    DEVICE_MANIFEST_FILE += device/qcom/msm8953_64/keymaster.xml
else
    DEVICE_MANIFEST_FILE += device/qcom/msm8953_64/keymaster_ota.xml
endif

PRODUCT_PROPERTY_OVERRIDES += rild.libpath=/vendor/lib64/libril-qc-qmi-1.so
PRODUCT_PROPERTY_OVERRIDES += vendor.rild.libpath=/vendor/lib64/libril-qc-qmi-1.so

# privapp-permissions whitelisting
PRODUCT_PROPERTY_OVERRIDES += ro.control_privapp_permissions=enforce

ifeq ($(ENABLE_AB),true)
#A/B related packages
PRODUCT_PACKAGES += update_engine \
                   update_engine_client \
                   update_verifier \
                   bootctrl.msm8953 \
                   android.hardware.boot@1.0-impl \
                   android.hardware.boot@1.0-service

PRODUCT_HOST_PACKAGES += \
    brillo_update_payload

#Boot control HAL test app
PRODUCT_PACKAGES_DEBUG += bootctl

PRODUCT_PACKAGES += \
  update_engine_sideload
endif

TARGET_MOUNT_POINTS_SYMLINKS := false

ifeq ($(strip $(TARGET_KERNEL_VERSION)), 3.18)
PRODUCT_HOST_PACKAGES += \
        AWBTestApp
endif

SDM660_DISABLE_MODULE = true
# When AVB 2.0 is enabled, dm-verity is enabled differently,
# below definitions are only required for AVB 1.0
ifeq ($(BOARD_AVB_ENABLE),false)
# dm-verity definitions
  PRODUCT_SUPPORTS_VERITY := true
endif

# Enable vndk-sp Libraries
PRODUCT_PACKAGES += vndk_package
PRODUCT_COMPATIBLE_PROPERTY_OVERRIDE := true
TARGET_USES_MKE2FS := true

#vendor prop to disable advanced network scanning
PRODUCT_PROPERTY_OVERRIDES += \
    persist.vendor.radio.enableadvancedscan=false

# Disable skip validate
PRODUCT_PROPERTY_OVERRIDES += \
    vendor.display.disable_skip_validate=1

# Enable telephpony ims feature
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.telephony.ims.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.ims.xml

PRODUCT_PACKAGES += libnbaio

###################################################################################
# This is the End of target.mk file.
# Now, Pickup other split product.mk files:
###################################################################################
$(call inherit-product-if-exists, vendor/qcom/defs/product-defs/legacy/*.mk)
###################################################################################

# For bringup
WLAN_BRINGUP_NEW_SP := true
DISP_BRINGUP_NEW_SP := true
CAM_BRINGUP_NEW_SP := true
SEC_USERSPACE_BRINGUP_NEW_SP := true
