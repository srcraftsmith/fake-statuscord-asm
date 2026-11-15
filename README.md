# fake-statuscord-asm

> [!NOTE]
> **Disclaimer**: This is a personal fake Discord Rich Presence status project written purely in x86_64 Linux Assembly (GAS Intel syntax). It simulates a long-running activity (custom Arch Linux presence with a fake start time starting from 128 hours and 40 minutes).

---

## Features

- **100% Pure Assembly**: Written in x86_64 assembly with Intel syntax.
- **Zero C Library Dependencies**: Uses direct Linux system calls (`socket`, `connect`, `write`, `read`, `clock_gettime`, `getpid`, `exit`) — built with `-nostdlib -no-pie`.
- **Lightweight**: Compiles to a tiny standalone ELF binary (~11 KB, < 10 KB stripped).
- **Dynamic Socket Detection**: Automatically discovers Discord's IPC UNIX domain socket via `$XDG_RUNTIME_DIR` (supporting both Flatpak and Native Discord installations).
- **Fake Elapsed Time**: Discord displays elapsed time counting up from **128 hrs 40 mins** upon launch.

---

## Prerequisites

You need the standard Arch Linux development tools:

```bash
sudo pacman -S base-devel
```

Ensure your Discord desktop client (native or Flatpak) is running before launching the binary.

---

## Building and Running

### 1. Build
Compile using `make`:

```bash
make
```

### 2. Run
Run the executable in the foreground:

```bash
./fake-statuscord-asm
```

When connected successfully, it outputs:
```
Presence set
```
Press `Ctrl+C` at any time to disconnect and stop the presence.

### 3. Run in Background
To keep it running in the background without keeping a terminal open:

```bash
nohup ./fake-statuscord-asm >/dev/null 2>&1 &
```

To stop the background process later:

```bash
killall fake-statuscord-asm
```

### 4. Clean Build Files
```bash
make clean
```

---

## How to Customize

All configuration is located in [main.s](main.s). After making any edits, re-run `make`.

### 1. Change the Fake Start Time
In [main.s](main.s), find the constant `FAKE_OFFSET_MS`:

```assembly
# Fake offset: 128 hours and 40 minutes in milliseconds
# (128 * 60 + 40) * 60 * 1000 = 463,200,000 ms
.equ FAKE_OFFSET_MS,    463200000
```

- **Formula**: `(hours * 60 + minutes) * 60 * 1000`
- **Examples**:
  - `100 hrs`: `100 * 3600 * 1000 = 360000000`
  - `50 hrs 15 min`: `(50 * 60 + 15) * 60 * 1000 = 180900000`
  - `0 (real elapsed time)`: `.equ FAKE_OFFSET_MS, 0`

### 2. Change Discord Client / Application ID
In [main.s](main.s), look for `handshake_payload`:

```assembly
handshake_payload:
    .ascii "{\"v\":1,\"client_id\":\"1570013529204068403\"}"
handshake_payload_len = . - handshake_payload
```
Replace `1570013529204068403` with your own Discord Developer Portal Application ID.

### 3. Change Details and State Text
In [main.s](main.s), look for `act_part2`:

```assembly
act_part2:
    .ascii ",\"activity\":{\"details\":\"i'm using arch btw\",\"state\":\"\xf0\x9f\x8e\xae Gaming \xe2\x80\xa2 \xf0\x9f\x92\xbb Coding\",\"timestamps\":{\"start\":"
act_part2_len = . - act_part2
```
- **details**: Change `"details":"i'm using arch btw"` to your preferred line.
- **state**: Change `"state":"..."`. Emojis can be pasted directly or hex-escaped in UTF-8 (e.g. `\xf0\x9f\x8e\xae` for 🎮).

### 4. Change Assets (Image and Hover Text)
In [main.s](main.s), look for `act_part3`:

```assembly
act_part3:
    .ascii "},\"assets\":{\"large_image\":\"arch\",\"large_text\":\"Arch Linux\"}}},\"nonce\":\"1\"}"
act_part3_len = . - act_part3
```
- **large_image**: Asset key uploaded in the Discord Developer Portal (e.g., `"arch"`).
- **large_text**: Hover tooltip text (e.g., `"Arch Linux"`).
