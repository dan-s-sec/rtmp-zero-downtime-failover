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

## Asset Generation (The Fallback Payload)

To achieve zero-latency switching via `FFmpeg`'s stream copy (`-c copy`), the fallback video must be pre-encoded to perfectly mirror the live OBS ingest parameters. Using a standard `.mp4` will corrupt the transport stream.

The fallback asset must be packaged as an MPEG Transport Stream (`.ts`) with a forced Keyframe Interval (e.g., 120 frames for 60fps) and an exact audio sample rate match (e.g., 48kHz). 

The following command forces the required H.264 Annex B byte stream format and generates the compliant fallback asset:

```bash
ffmpeg -i brb_raw.mp4 \
-c:v libx264 -preset medium -b:v 6000k -maxrate 6000k -bufsize 12000k \
-pix_fmt yuv420p -r 60 -g 120 -keyint_min 120 \
-profile:v high -level 4.1 \
-c:a aac -b:a 160k -ar 48000 -ac 2 \
-bsf:v h264_mp4toannexb \
-y brb_clone.ts
```

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

## System Limitations & Threat Model

While this infrastructure achieves sub-second failover latency by bypassing application-layer handlers, the bare-metal approach introduces specific architectural constraints:

* **Transport-Layer Blindness (TCP vs. RTMP):** The `feeder.sh` logic relies on the Linux `iproute2` suite (`ss`) to monitor the TCP `ESTABLISHED` state on port 1935. Because it operates at the Transport Layer (Layer 4) rather than the Application Layer (Layer 7), it cannot detect protocol-level anomalies. If the client connects but transmits a corrupted or empty RTMP payload, the failover will not trigger as long as the TCP handshake remains valid.
* **Strict Codec & Framerate Coupling:** Because the system utilizes FFmpeg's stream copy (`-c copy`) to bypass CPU-intensive re-encoding, the live ingest and the fallback video must be perfectly uniform. Any deviation in audio sample rate (e.g., 44.1kHz vs 48kHz), resolution, or Keyframe Interval (GOP size) between the two feeds will corrupt the transport stream during multiplexing, causing player desync or visual datamoshing.
* **FIFO Blocking (Backpressure):** The architecture utilizes a single Linux Named Pipe (`/tmp/stream_pipe`). If the destination server (Twitch/YouTube) throttles the connection or the `consumer.sh` process hangs, the named pipe will block. This introduces backpressure that will eventually crash the `feeder.sh` ingest process. 
* **Single Node Point-of-Failure:** This implementation provides high availability against client-side network drops, but the Ubuntu Droplet itself remains a single point of failure. It lacks BGP Anycast routing or DNS-level failover; if the datacenter experiences an outage, the broadcast drops.
