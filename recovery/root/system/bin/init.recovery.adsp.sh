#!/system/bin/sh
sleep 20
insmod /vendor/lib/modules/q6_pdr_dlkm.ko
insmod /vendor/lib/modules/q6_notifier_dlkm.ko
insmod /vendor/lib/modules/snd_event_dlkm.ko
insmod /vendor/lib/modules/gpr_dlkm.ko
insmod /vendor/lib/modules/spf_core_dlkm.ko
insmod /vendor/lib/modules/adsp_loader_dlkm.ko
echo 1 > /sys/kernel/boot_adsp/boot