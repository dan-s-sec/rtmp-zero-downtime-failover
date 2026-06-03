#!/bin/bash
PIPE="/tmp/stream_pipe"
# Set to your Twitch ingest server (e.g., lhr03 for London, jfk03 for NY, or auto)
RTMP_URL="rtmp://lhr03.contribute.live-video.net/app/YOUR_TWITCH_KEY_HERE"

[[ ! -p $PIPE ]] && mkfifo $PIPE

echo "[$(date)] Starting Consumer..."
# High queue size for stability
ffmpeg -y -thread_queue_size 4096 -f mpegts -i "$PIPE" \
    -c copy -use_wallclock_as_timestamps 1 -fflags +genpts \
    -f flv "$RTMP_URL"