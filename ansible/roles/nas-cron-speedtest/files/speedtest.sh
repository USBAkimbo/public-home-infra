SPEEDTEST_PATH="/mnt/ssd/speedtest"
cd $SPEEDTEST_PATH

./librespeed-cli --simple > speedtest-temp 2>&1

cat speedtest-temp | awk '/Download rate/ {print $3}' > last-download-test # Echo download speed to file (Mbps)
cat speedtest-temp | awk '/Upload rate/ {print $3}' > last-upload-test # Echo upload speed to file (Mbps)
cat speedtest-temp | awk '/Ping/ {print $2}' > last-ping-test # Echo ping to file (ms)
cat speedtest-temp | awk '/Jitter/ {print $5}' > last-jitter-test # Echo jitter to file (ms)

rm $SPEEDTEST_PATH/speedtest-temp
chmod 755 $SPEEDTEST_PATH/*-test
