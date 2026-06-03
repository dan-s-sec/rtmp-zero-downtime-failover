@echo off
ssh -o BatchMode=yes root@YOUR_DROPLET_IP "systemctl stop stream-consumer stream-feeder"
echo Stream Killed.
pause