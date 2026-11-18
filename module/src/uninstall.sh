#!/system/bin/sh

export TMP_PATH=@WORK_DIRECTORY@

rm -rf $TMP_PATH
# Staging dir used by earlier KazeZygisk builds and by upstream NyaZygisk.
rm -rf /data/adb/kazezygisk
rm -rf /data/adb/nyazygisk
