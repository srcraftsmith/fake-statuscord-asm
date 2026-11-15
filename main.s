.intel_syntax noprefix
.global _start

# ==============================================================================
# Linux x86_64 Syscalls
# ==============================================================================
.equ SYS_READ,          0
.equ SYS_WRITE,         1
.equ SYS_CLOSE,         3
.equ SYS_GETPID,        39
.equ SYS_SOCKET,        41
.equ SYS_CONNECT,       42
.equ SYS_EXIT,          60
.equ SYS_CLOCK_GETTIME, 228

# ==============================================================================
# Constants
# ==============================================================================
.equ AF_UNIX,           1
.equ SOCK_STREAM,       1
.equ CLOCK_REALTIME,    0

# Fake offset: 128 hours and 40 minutes in milliseconds
# (128 * 60 + 40) * 60 * 1000 = 463,200,000 ms
.equ FAKE_OFFSET_MS,    463200000

# Discord IPC Opcodes
.equ IPC_HANDSHAKE,     0
.equ IPC_FRAME,         1

# ==============================================================================
# Read-Only Data
# ==============================================================================
.section .rodata
str_xdg:
    .ascii "XDG_RUNTIME_DIR="

suffix_flatpak:
    .asciz "/app/com.discordapp.Discord/discord-ipc-0"

suffix_native:
    .asciz "/discord-ipc-0"

# Static fallbacks
fallback_path1:
    .asciz "/run/user/1000/app/com.discordapp.Discord/discord-ipc-0"
fallback_path2:
    .asciz "/run/user/1000/discord-ipc-0"
fallback_path3:
    .asciz "/tmp/discord-ipc-0"

# Discord Handshake JSON payload
handshake_payload:
    .ascii "{\"v\":1,\"client_id\":\"1570013529204068403\"}"
handshake_payload_len = . - handshake_payload

# Activity JSON payload parts
act_part1:
    .ascii "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"pid\":"
act_part1_len = . - act_part1

act_part2:
    .ascii ",\"activity\":{\"details\":\"i'm using arch btw\",\"state\":\"\xf0\x9f\x8e\xae Gaming \xe2\x80\xa2 \xf0\x9f\x92\xbb Coding\",\"timestamps\":{\"start\":"
act_part2_len = . - act_part2

act_part3:
    .ascii "},\"assets\":{\"large_image\":\"arch\",\"large_text\":\"Arch Linux\"}}},\"nonce\":\"1\"}"
act_part3_len = . - act_part3

# Messages
msg_presence_set:
    .ascii "Presence set\n"
msg_presence_set_len = . - msg_presence_set

msg_err_connect:
    .ascii "Error: Could not connect to Discord IPC socket. Is Discord running?\n"
msg_err_connect_len = . - msg_err_connect

# ==============================================================================
# BSS (Uninitialized Data)
# ==============================================================================
.section .bss
.align 8
dyn_path1:
    .skip 256
dyn_path2:
    .skip 256
sockaddr:
    .skip 128
timespec:
    .skip 16
read_buf:
    .skip 2048
packet_buf:
    .skip 2048

# Array of candidate socket path pointers
sock_candidates:
    .skip 48                        # 6 pointers (8 bytes each)

# ==============================================================================
# Text (Code) Section
# ==============================================================================
.section .text
_start:
    # --------------------------------------------------------------------------
    # 1. Parse envp from initial stack to find XDG_RUNTIME_DIR
    # Initial stack layout on Linux x86_64:
    # [rsp]         = argc
    # [rsp + 8]     = argv[0] ...
    # [rsp + 8*argc + 8]  = NULL (end of argv)
    # [rsp + 8*argc + 16] = envp[0]
    # --------------------------------------------------------------------------
    mov rcx, [rsp]                  # rcx = argc
    lea rbx, [rsp + 8 + rcx*8 + 8]  # rbx = &envp[0]
    xor r13, r13                    # r13 will hold pointer to XDG_RUNTIME_DIR value (if found)

.L_find_env_loop:
    mov rsi, [rbx]
    test rsi, rsi
    jz .L_build_candidates          # end of environment variables

    # Compare first 16 characters with "XDG_RUNTIME_DIR="
    lea rdi, [rip + str_xdg]
    mov rcx, 16
    repe cmpsb
    je .L_found_xdg

    add rbx, 8
    jmp .L_find_env_loop

.L_found_xdg:
    # rsi now points to the path value after '='
    mov r13, rsi

    # Build dyn_path1: <XDG_RUNTIME_DIR>/app/com.discordapp.Discord/discord-ipc-0
    lea rdi, [rip + dyn_path1]
    mov rsi, r13
    call str_copy                   # copies rsi to rdi, rdi ends at trailing null

    lea rsi, [rip + suffix_flatpak]
    call str_copy

    # Build dyn_path2: <XDG_RUNTIME_DIR>/discord-ipc-0
    lea rdi, [rip + dyn_path2]
    mov rsi, r13
    call str_copy

    lea rsi, [rip + suffix_native]
    call str_copy

.L_build_candidates:
    lea rdi, [rip + sock_candidates]
    test r13, r13
    jz .L_fill_static_only

    # If XDG_RUNTIME_DIR was found, prepend dyn_path1 and dyn_path2
    lea rax, [rip + dyn_path1]
    mov [rdi], rax
    add rdi, 8
    lea rax, [rip + dyn_path2]
    mov [rdi], rax
    add rdi, 8

.L_fill_static_only:
    lea rax, [rip + fallback_path1]
    mov [rdi], rax
    add rdi, 8
    lea rax, [rip + fallback_path2]
    mov [rdi], rax
    add rdi, 8
    lea rax, [rip + fallback_path3]
    mov [rdi], rax
    add rdi, 8
    mov qword ptr [rdi], 0          # NULL terminator for candidate list

    # --------------------------------------------------------------------------
    # 2. Iterate through socket candidates and connect
    # --------------------------------------------------------------------------
    lea r14, [rip + sock_candidates]

.L_try_next_socket:
    mov rdi, [r14]
    test rdi, rdi
    jz .L_connect_fail

    # Setup sockaddr_un struct:
    #   sun_family = AF_UNIX (2 bytes)
    #   sun_path   = path string (null-terminated)
    lea rsi, [rip + sockaddr]
    mov word ptr [rsi], AF_UNIX
    add rsi, 2                      # rsi points to sockaddr.sun_path

    # Copy candidate path to sockaddr.sun_path
.L_copy_sockpath:
    mov al, [rdi]
    mov [rsi], al
    inc rdi
    inc rsi
    test al, al
    jnz .L_copy_sockpath

    # Syscall: socket(AF_UNIX, SOCK_STREAM, 0)
    mov rax, SYS_SOCKET
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    xor rdx, rdx
    syscall

    test rax, rax
    js .L_advance_candidate
    mov r12, rax                    # r12 = socket fd

    # Syscall: connect(fd, &sockaddr, 110)
    mov rax, SYS_CONNECT
    mov rdi, r12
    lea rsi, [rip + sockaddr]
    mov rdx, 110                    # sizeof(struct sockaddr_un)
    syscall

    test rax, rax
    jz .L_connected                 # Connection succeeded!

    # Failed on this path; close socket fd and try next candidate
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

.L_advance_candidate:
    add r14, 8
    jmp .L_try_next_socket

.L_connected:
    # --------------------------------------------------------------------------
    # 3. Send Discord RPC Handshake Packet
    # Header format: [uint32 opcode][uint32 length]
    # --------------------------------------------------------------------------
    lea rdi, [rip + packet_buf]
    mov dword ptr [rdi], IPC_HANDSHAKE
    mov dword ptr [rdi + 4], handshake_payload_len

    # Copy payload into packet_buf + 8
    lea rsi, [rip + handshake_payload]
    add rdi, 8
    mov rcx, handshake_payload_len
    rep movsb

    # Syscall: write(fd, packet_buf, 8 + handshake_payload_len)
    mov rax, SYS_WRITE
    mov rdi, r12
    lea rsi, [rip + packet_buf]
    mov rdx, 8 + handshake_payload_len
    syscall

    # Read handshake response (READY frame from Discord)
    mov rax, SYS_READ
    mov rdi, r12
    lea rsi, [rip + read_buf]
    mov rdx, 2048
    syscall

    # --------------------------------------------------------------------------
    # 4. Calculate start timestamp with fake offset
    # clock_gettime(CLOCK_REALTIME, &timespec)
    # now_ms = (tv_sec * 1000) + (tv_nsec / 1000000)
    # start_time = now_ms - 463,200,000 (128h 40m)
    # --------------------------------------------------------------------------
    mov rax, SYS_CLOCK_GETTIME
    mov rdi, CLOCK_REALTIME
    lea rsi, [rip + timespec]
    syscall

    lea rsi, [rip + timespec]
    mov rax, [rsi]                  # timespec.tv_sec
    imul rax, 1000                  # convert seconds to milliseconds

    mov r8, [rsi + 8]               # timespec.tv_nsec
    mov rcx, 1000000
    push rax
    mov rax, r8
    xor rdx, rdx
    div rcx                         # rax = tv_nsec / 1,000,000
    mov r8, rax
    pop rax
    add rax, r8                     # rax = current time in milliseconds

    # Subtract fake offset (128h 40m)
    sub rax, FAKE_OFFSET_MS
    mov r13, rax                    # r13 = fake startTimestamp

    # --------------------------------------------------------------------------
    # 5. Get current Process ID
    # --------------------------------------------------------------------------
    mov rax, SYS_GETPID
    syscall
    mov r15, rax                    # r15 = pid

    # --------------------------------------------------------------------------
    # 6. Assemble SET_ACTIVITY JSON Frame
    # --------------------------------------------------------------------------
    # Reserve first 8 bytes for packet header
    lea rdi, [rip + packet_buf + 8]

    # Append act_part1
    lea rsi, [rip + act_part1]
    mov rcx, act_part1_len
    rep movsb

    # Format PID to ascii at [rdi]
    mov rax, r15
    call format_u64

    # Append act_part2
    lea rsi, [rip + act_part2]
    mov rcx, act_part2_len
    rep movsb

    # Format startTimestamp to ascii at [rdi]
    mov rax, r13
    call format_u64

    # Append act_part3
    lea rsi, [rip + act_part3]
    mov rcx, act_part3_len
    rep movsb

    # Calculate payload length = current rdi - (packet_buf + 8)
    lea r8, [rip + packet_buf + 8]
    mov rax, rdi
    sub rax, r8                     # rax = payload length

    # Fill in header at packet_buf
    lea r8, [rip + packet_buf]
    mov dword ptr [r8], IPC_FRAME   # Opcode: FRAME (1)
    mov dword ptr [r8 + 4], eax     # Payload length

    # Syscall: write(fd, packet_buf, 8 + payload_length)
    lea rdx, [rax + 8]
    mov rax, SYS_WRITE
    mov rdi, r12
    lea rsi, [rip + packet_buf]
    syscall

    # --------------------------------------------------------------------------
    # 7. Print "Presence set\n" to stdout
    # --------------------------------------------------------------------------
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [rip + msg_presence_set]
    mov rdx, msg_presence_set_len
    syscall

    # --------------------------------------------------------------------------
    # 8. Event loop: keep connection alive until closed by Discord or process killed
    # --------------------------------------------------------------------------
.L_keep_alive_loop:
    mov rax, SYS_READ
    mov rdi, r12
    lea rsi, [rip + read_buf]
    mov rdx, 2048
    syscall

    test rax, rax
    jle .L_exit_clean                # EOF or error, Discord socket closed
    jmp .L_keep_alive_loop

.L_exit_clean:
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

.L_connect_fail:
    mov rax, SYS_WRITE
    mov rdi, 2
    lea rsi, [rip + msg_err_connect]
    mov rdx, msg_err_connect_len
    syscall

    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

# ==============================================================================
# Helper Functions
# ==============================================================================

# Copy null-terminated string from rsi to rdi.
# When done, rdi points to the null terminator byte (allows continuous appending).
str_copy:
.L_str_copy_loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .L_str_copy_done
    inc rsi
    inc rdi
    jmp .L_str_copy_loop
.L_str_copy_done:
    ret

# Format unsigned 64-bit integer in rax to decimal ASCII string at [rdi]
# Advances rdi to the end of the written string (without null terminator).
format_u64:
    push rbx
    push rcx
    push rdx
    push rsi

    mov rbx, rdi                    # rbx = start of number in buffer
    mov rcx, 10
.L_digit_loop:
    xor rdx, rdx
    div rcx                         # rax = rax / 10, dl = remainder
    add dl, '0'
    mov [rdi], dl
    inc rdi
    test rax, rax
    jnz .L_digit_loop

    # Reverse digits from rbx to rdi - 1
    mov rsi, rbx
    lea rdx, [rdi - 1]
.L_rev_loop:
    cmp rsi, rdx
    jge .L_fmt_done
    mov al, [rsi]
    mov cl, [rdx]
    mov [rsi], cl
    mov [rdx], al
    inc rsi
    dec rdx
    jmp .L_rev_loop

.L_fmt_done:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

