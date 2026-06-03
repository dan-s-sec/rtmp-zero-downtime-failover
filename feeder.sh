#!/bin/bash
PIPE="/tmp/stream_pipe"
BRB_FILE="/opt/stream-assets/brb_clone.ts"
LIVE_SOURCE="rtsp://127.0.0.1:8554/obs_ingest/live"

[[ ! -p $PIPE ]] && mkfifo $PIPE
exec 3<> "$PIPE"

while true; do
    echo "[$(date)] Connecting to Live..."

    # Tries to copy OBS stream directly to the pipe
    ffmpeg -rtsp_transport tcp \
        -analyzeduration 5000000 -probesize 5000000 \
        -i "$LIVE_SOURCE" \
        -bsf:v h264_mp4toannexb \
        -c copy -ignore_unknown -mss 4096 -f mpegts pipe:1 > "$PIPE" 2>/dev/null

    echo "[$(date)] Live Lost. Starting BRB Loop..."

    # Start BRB video in background
    ffmpeg -re -stream_loop -1 -i "$BRB_FILE" \
        -c copy -f mpegts pipe:1 > "$PIPE" 2>/dev/null &
    BRB_PID=$!

    # Checks if OBS is connected to Port 1935 (RTMP)
    while kill -0 $BRB_PID 2>/dev/null; do
        sleep 1

        # Check for ESTABLISHED connection on Port 1935
        if ss -tn state established sport = :1935 | grep -q ":1935"; then
            echo "[$(date)] OBS Detected! Switching..."
            sleep 2 # Short buffer to let RTSP stabilize
            kill $BRB_PID
            wait $BRB_PID 2>/dev/null
            break
        fi
    done

    kill $BRB_PID 2>/dev/null
done