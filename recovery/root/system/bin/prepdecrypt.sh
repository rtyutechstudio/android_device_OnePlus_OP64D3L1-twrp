#!/system/bin/sh
# For android 13+ decrypt
setprop crypto.ready 1 >/dev/null 2>&1
if [ "$(getprop crypto.ready 2>/dev/null)" = "1" ]; then
    logi "crypto.ready=1"
else
    logi "failed to set crypto.ready=1"
fi
exit 0
