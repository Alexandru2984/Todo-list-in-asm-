%include "src/defs.inc"

extern init_storage
extern load_todos
extern handle_request
extern print
extern itoa
extern atoi
extern strlen

global _start

section .data
    msg_starting db "Starting ASM TODO server...", 10, 0
    msg_port db "Listening on port: ", 0
    msg_nl db 10, 0
    msg_req db "Received request", 10, 0
    cl_lit db "content-length:", 0
    
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
; find_hdr_end - find "\r\n\r\n" in null-terminated buffer
; rdi = buffer
; Returns rax = ptr past the terminator, or 0 if not found
; -----------------------------------------------------------------------------
find_hdr_end:
    mov rsi, rdi
.loop:
    cmp byte [rsi], 0
    je .not_found
    cmp dword [rsi], 0x0a0d0a0d
    je .found
    inc rsi
    jmp .loop
.found:
    lea rax, [rsi+4]
    ret
.not_found:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; get_content_length - parse "Content-Length:" header, case-insensitive
; rdi = request buffer (null-terminated); scan stops at end of headers
; Returns rax = declared body length, or 0 if header absent
; -----------------------------------------------------------------------------
get_content_length:
    push rbx
    mov rsi, rdi
.scan:
    cmp byte [rsi], 0
    je .absent
    cmp dword [rsi], 0x0a0d0a0d     ; reached end of headers
    je .absent
    xor rcx, rcx
.cmp_loop:
    cmp rcx, 15
    je .matched
    mov al, [rsi + rcx]
    test al, al
    jz .absent
    cmp al, 'A'                     ; lowercase A-Z before comparing
    jb .low_done
    cmp al, 'Z'
    ja .low_done
    add al, 32
.low_done:
    mov rbx, cl_lit
    cmp al, [rbx + rcx]
    jne .next
    inc rcx
    jmp .cmp_loop
.next:
    inc rsi
    jmp .scan
.matched:
    add rsi, 15
.skip_sp:
    cmp byte [rsi], ' '
    jne .parse
    inc rsi
    jmp .skip_sp
.parse:
    mov rdi, rsi
    call atoi
    pop rbx
    ret
.absent:
    xor rax, rax
    pop rbx
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

    ; Read request: loop until headers complete + Content-Length body received.
    ; A browser/proxy may deliver headers and body in separate packets; a
    ; single read() would silently drop the body.
    xor r13, r13            ; total bytes received
.read_loop:
    mov rdx, 4095
    sub rdx, r13            ; remaining buffer space
    jz .read_complete       ; buffer full — process what we have
    mov rax, SYS_READ
    mov rdi, [client_fd]
    lea rsi, [req_buf + r13]
    syscall
    cmp rax, 0
    jle .read_eof
    add r13, rax
    mov byte [req_buf + r13], 0

    ; Headers complete? (need \r\n\r\n)
    mov rdi, req_buf
    call find_hdr_end
    test rax, rax
    jz .read_loop           ; still inside headers
    mov r14, rax            ; ptr past \r\n\r\n = body start

    ; Body received so far
    lea rax, [req_buf + r13]
    sub rax, r14            ; body bytes present
    mov r15, rax

    ; Need Content-Length more?
    mov rdi, req_buf
    call get_content_length ; rax = declared body length (0 if absent)
    cmp r15, rax
    jl .read_loop           ; body incomplete — keep reading
    jmp .read_complete

.read_eof:
    test r13, r13
    jz .close_client        ; nothing received at all

.read_complete:
    mov byte [req_buf + r13], 0

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
