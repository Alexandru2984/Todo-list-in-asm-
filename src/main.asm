%include "src/defs.inc"

extern init_storage
extern load_todos
extern handle_request
extern print
extern itoa
extern strlen

global _start

section .data
    msg_starting db "Starting ASM TODO server...", 10, 0
    msg_port db "Listening on port: ", 0
    msg_nl db 10, 0
    msg_req db "Received request", 10, 0
    
    sockaddr:
        dw AF_INET      ; sin_family
        dw 0            ; sin_port (network byte order)
        dd 0            ; sin_addr (INADDR_ANY)
        dq 0            ; sin_zero

    current_port dq 34624

section .bss
    sock_fd resq 1
    client_fd resq 1
    req_buf resb 4096
    port_str resb 16

section .text

; -----------------------------------------------------------------------------
; htons - Host to Network Short
; rdi = port
; -----------------------------------------------------------------------------
htons:
    mov rax, rdi
    xchg al, ah
    ret

; -----------------------------------------------------------------------------
; main entry point
; -----------------------------------------------------------------------------
_start:
    ; Ignore SIGPIPE — prevents crash when client closes connection mid-write
    sub rsp, 40
    mov qword [rsp],    1   ; sa_handler = SIG_IGN
    mov qword [rsp+8],  0   ; sa_flags
    mov qword [rsp+16], 0   ; sa_restorer
    mov qword [rsp+24], 0   ; sa_mask lo
    mov qword [rsp+32], 0   ; sa_mask hi
    mov rax, 13             ; SYS_RT_SIGACTION
    mov rdi, 13             ; SIGPIPE
    mov rsi, rsp
    xor rdx, rdx
    mov r10, 8              ; sigsetsize
    syscall
    add rsp, 40

    ; Print startup
    mov rdi, msg_starting
    call print

    ; Init storage
    call init_storage
    call load_todos

.port_scan:
    ; Convert port to network byte order
    mov rdi, [current_port]
    call htons
    mov [sockaddr + 2], ax

    ; Create socket
    mov rax, SYS_SOCKET
    mov rdi, AF_INET
    mov rsi, SOCK_STREAM
    mov rdx, 0
    syscall
    cmp rax, 0
    jl .fatal_error
    mov [sock_fd], rax

    ; Set SO_REUSEADDR (optional, but good practice)
    ; sys_setsockopt is 54
    ; level SOL_SOCKET = 1, optname SO_REUSEADDR = 2
    push 1
    mov rax, 54
    mov rdi, [sock_fd]
    mov rsi, 1
    mov rdx, 2
    mov r10, rsp ; optval
    mov r8, 4    ; optlen
    syscall
    pop rax

    ; Bind socket
    mov rax, SYS_BIND
    mov rdi, [sock_fd]
    mov rsi, sockaddr
    mov rdx, 16
    syscall

    cmp rax, -98 ; EADDRINUSE
    je .try_next_port
    cmp rax, 0
    jl .fatal_error

    ; Listen
    mov rax, SYS_LISTEN
    mov rdi, [sock_fd]
    mov rsi, 10 ; backlog
    syscall
    cmp rax, 0
    jl .fatal_error

    ; Print port
    mov rdi, msg_port
    call print
    
    mov rdi, [current_port]
    mov rsi, port_str
    call itoa
    
    mov rdi, port_str
    call print
    
    mov rdi, msg_nl
    call print

.accept_loop:
    ; Accept
    mov rax, SYS_ACCEPT
    mov rdi, [sock_fd]
    mov rsi, 0
    mov rdx, 0
    syscall
    cmp rax, 0
    jl .accept_loop
    mov [client_fd], rax

    ; Set 5s receive timeout — prevents slow-read DoS
    sub rsp, 16
    mov qword [rsp], 5      ; tv_sec
    mov qword [rsp+8], 0    ; tv_usec
    mov rax, 54             ; SYS_SETSOCKOPT
    mov rdi, [client_fd]
    mov rsi, 1              ; SOL_SOCKET
    mov rdx, 20             ; SO_RCVTIMEO
    mov r10, rsp
    mov r8, 16
    syscall
    add rsp, 16

    ; Set 10s send timeout — prevents slow-write DoS
    sub rsp, 16
    mov qword [rsp], 10     ; tv_sec
    mov qword [rsp+8], 0    ; tv_usec
    mov rax, 54
    mov rdi, [client_fd]
    mov rsi, 1              ; SOL_SOCKET
    mov rdx, 21             ; SO_SNDTIMEO
    mov r10, rsp
    mov r8, 16
    syscall
    add rsp, 16

    ; Read request
    mov rax, SYS_READ
    mov rdi, [client_fd]
    mov rsi, req_buf
    mov rdx, 4095
    syscall
    
    cmp rax, 0
    jle .close_client

    ; Null-terminate buffer
    mov byte [req_buf + rax], 0

    ; Print request log
    mov rdi, msg_req
    call print

    ; Handle request
    mov rdi, req_buf
    mov rsi, [client_fd]
    call handle_request

.close_client:
    ; Close client
    mov rax, SYS_CLOSE
    mov rdi, [client_fd]
    syscall
    
    jmp .accept_loop

.try_next_port:
    ; Close failed socket
    mov rax, SYS_CLOSE
    mov rdi, [sock_fd]
    syscall
    
    ; Increment port and retry
    mov rax, [current_port]
    inc rax
    mov [current_port], rax
    jmp .port_scan

.fatal_error:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall
