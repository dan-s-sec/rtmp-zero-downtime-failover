# High-Availability RTMP Failover Infrastructure
**Designed for OBS Studio & Twitch/YouTube Broadcasting**

A bare-metal Linux RTMP failover system utilizing FFmpeg, Named Pipes (FIFO), and kernel-level socket monitoring for zero-latency, zero-re-encode stream switching. 

**The Use Case:** If a broadcaster's local internet drops or OBS crashes, Twitch immediately terminates the live broadcast. This infrastructure sits between the broadcaster and the destination server, intercepting the stream. If the local OBS connection dies, the server instantly seamless-switches the broadcast to a local fallback video, keeping the Twitch connection alive and preventing stream downtime. 

## System Architecture

Unlike standard Nginx-RTMP fallback modules that suffer from 8-15 second connection drops during handshakes, this system maintains a persistent, unbroken connection to the destination server using a continuous data pipe.

1. **The Ingest:** OBS broadcasts to a local `MediaMTX` instance via RTMP/RTSP.
2. **The Logic (Feeder):** A daemonized bash script monitors port 1935 using `ss` (Socket Statistics).
   - If an `ESTABLISHED` state is detected, the live feed is piped to `/tmp/stream_pipe`.
   - If the connection drops, a looping H.264 fallback transport stream (`.ts`) is instantly routed into the same pipe.
3. **The Egress (Consumer):** A continuous `FFmpeg` process reads from the named pipe, generating synthetic Presentation Timestamps (`+genpts` and `-use_wallclock_as_timestamps`) to prevent player desync, and pushes the unbroken FLV stream to the destination.

## Core Technologies & Skills Demonstrated

* **Linux Systems Administration:** Configuration of `systemd` services, swap memory allocation for high-availability nodes, and log truncation via `journald` to prevent disk exhaustion during 24/7 uptimes.
* **Network Protocol Monitoring:** Utilizing `iproute2` (`ss`) to query the Linux kernel's network stack for real-time TCP state evaluation, bypassing slower application-layer APIs.
* **Process Manipulation:** Advanced bash scripting using background process IDs (`$!`), sub-shells, and graceful termination signals to manage infinite loops without CPU exhaustion.
* **Stream Multiplexing & Transcoding:** Utilizing `FFmpeg` for transport stream generation, codec copying (`-c copy`), and dynamic PTS/DTS timestamp manipulation across disjointed video inputs.

## Deployment Files

* `mediamtx.yml`: Hooks configuration to trigger daemons upon ingest connection.
* `consumer.sh`: The continuous egress pipeline pushing to the destination server.
* `feeder.sh`: The logic loop handling RTMP socket monitoring and instant source switching.
* `stream-consumer.service` / `stream-feeder.service`: systemd units for daemonization.
* `EndStream.bat`: A remote SSH kill switch to safely terminate the infinite loops and close the broadcast gracefully.

## Technical Requirements
* Ubuntu 22.04 / 24.04
* `ffmpeg`, `iproute2`, `mediamtx`
* Client configuration strictly bound to matching Keyframe Intervals (e.g., 2s) and Audio Sample Rates to prevent transport stream corruption upon switching.
