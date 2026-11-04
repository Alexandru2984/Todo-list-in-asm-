%include "src/defs.inc"
%include "src/import.inc"
DEFAULT ABS
extern init_storage, parse_uint, validate_request, handle_request, send_error
extern request_cap
extern print, itoa
extern strcmp, downgrade_storage, downgrade_v3, check_storage

global _start
section .data
    starting db 'ASM TODO listening on 127.0.0.1:',0
    newline db 10,0
    failure db 'ASM TODO: startup failed (storage, port or socket)',10,0
    check_arg db '--check-storage',0
    check_ok db 'ASM TODO: storage check passed',10,0
    check_bad db 'ASM TODO: storage check failed; no workspace was rewritten',10,0
    version_arg db '--storage-version',0
    version_text db '4',10,0
    downgrade_v3_arg db '--downgrade-v3',0
    downgrade_arg db '--downgrade',0
    overload_delay dq 0,100000000
    downgrade_ok db 'ASM TODO: offline downgrade completed',10,0
    downgrade_bad db 'ASM TODO: offline downgrade failed; retain the compatible planner binary and restore the private copy',10,0
    sockaddr: dw AF_INET,0
              dd 0x0100007f
              dq 0
    port dq 34624
section .bss
    sock_fd resq 1
    client_fd resq 1
    req_buf resb IMPORT_REQUEST_MAX+8 ; terminator and bounded lookahead padding
    port_str resb 24
section .text
_start:
    cmp qword [rsp], 1
    je .signals
    cmp qword [rsp], 2
    jne .fatal
    mov rdi, [rsp+16]
    mov rsi,check_arg
    call strcmp
    test rax,rax
    jz .check
    mov rdi, [rsp+16]
    mov rsi,version_arg
    call strcmp
    test rax,rax
    jz .version
    mov rdi, [rsp+16]
    mov rsi,downgrade_v3_arg
    call strcmp
    test rax,rax
    jz .downgrade_v3
    mov rdi, [rsp+16]
    mov rsi,downgrade_arg
    call strcmp
    test rax,rax
    jz .downgrade
    mov rdi, [rsp+16]
    call parse_uint
    test rax, rax
    jle .fatal
    cmp rax, 65535
    ja .fatal
    mov [port], rax
.signals:
    sub rsp, 32
    mov qword [rsp],1
    mov qword [rsp+8],0
    mov qword [rsp+16],0
    mov qword [rsp+24],0
    mov eax,13
    mov edi,SIGPIPE
    mov rsi,rsp
    xor edx,edx
    mov r10d,8
    syscall
    mov eax,13
    mov edi,SIGCHLD
    syscall
    add rsp,32
    call init_storage
    test rax,rax
    js .fatal
    mov eax,SYS_SOCKET
    mov edi,AF_INET
    mov esi,SOCK_STREAM
    xor edx,edx
    syscall
    test rax,rax
    js .fatal
    mov [sock_fd],rax
    push 1
    mov eax,54
    mov rdi,[sock_fd]
    mov esi,1
    mov edx,2
    mov r10,rsp
    mov r8d,4
    syscall
    pop rax
    mov rax,[port]
    xchg al,ah
    mov [sockaddr+2],ax
    mov eax,SYS_BIND
    mov rdi,[sock_fd]
    mov rsi,sockaddr
    mov edx,16
    syscall
    test rax,rax
    js .fatal
    mov eax,SYS_LISTEN
    mov rdi,[sock_fd]
    mov esi,64
    syscall
    test rax,rax
    js .fatal
    mov rdi,starting
    call print
    mov rdi,[port]
    mov rsi,port_str
    call itoa
    mov rdi,port_str
    call print
    mov rdi,newline
    call print
.accept:
    mov eax,SYS_ACCEPT
    mov rdi,[sock_fd]
    xor esi,esi
    xor edx,edx
    syscall
    test rax,rax
    js .accept_error
    mov [client_fd],rax
    mov eax,SYS_FORK
    syscall
    test rax,rax
    jz .child
    js .fork_error
    mov eax,SYS_CLOSE
    mov rdi,[client_fd]
    syscall
    jmp .accept
.accept_error:
    cmp rax,-4 ; EINTR has no resource pressure
    je .accept
    cmp rax,-9 ; invalid listening descriptor/type/state cannot recover in a loop
    je .fatal
    cmp rax,-22
    je .fatal
    cmp rax,-88
    je .fatal
    call main_backoff
    jmp .accept
.fork_error:
    mov eax,SYS_CLOSE
    mov rdi,[client_fd]
    syscall
    call main_backoff
    jmp .accept
.child:
    mov eax,SYS_CLOSE
    mov rdi,[sock_fd]
    syscall
    ; Absolute lifetime bounds drip feeding and lock waits, not just each read.
    mov eax,SYS_ALARM
    mov edi,15
    syscall
    sub rsp,16
    mov qword [rsp],5
    mov qword [rsp+8],0
    mov eax,54
    mov rdi,[client_fd]
    mov esi,1
    mov edx,20
    mov r10,rsp
    mov r8d,16
    syscall
    mov eax,54
    mov edx,21
    syscall
    add rsp,16
    xor r13d,r13d
.read:
    mov rdx,[request_cap]
    sub rdx,r13
    jz .too_large
    mov eax,SYS_READ
    mov rdi,[client_fd]
    lea rsi,[req_buf+r13]
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    jle .incomplete
    add r13,rax
    mov byte [req_buf+r13],0
    mov rdi,req_buf
    mov rsi,r13
    call validate_request
    test rax,rax
    js .protocol_error
    jz .read
    mov rdi,[client_fd]
    call handle_request
    jmp .close
.incomplete:
    test r13,r13
    jz .close
    mov edi,400
    jmp .error
.too_large:
    mov edi,413
    jmp .error
.protocol_error:
    neg rax
    mov rdi,rax
.error:
    mov rsi,[client_fd]
    call send_error
.close:
    mov eax,SYS_CLOSE
    mov rdi,[client_fd]
    syscall
    mov eax,SYS_EXIT
    xor edi,edi
    syscall
.fatal:
    mov rdi,failure
    call print
    mov eax,SYS_EXIT
    mov edi,1
    syscall

.downgrade_v3:
    call downgrade_v3
    jmp .downgrade_result
.downgrade:
    call downgrade_storage
.downgrade_result:
    test rax,rax
    js .downgrade_failed
    mov rdi,downgrade_ok
    call print
    mov eax,SYS_EXIT
    xor edi,edi
    syscall
.downgrade_failed:
    mov rdi,downgrade_bad
    call print
    mov eax,SYS_EXIT
    mov edi,1
    syscall

.version:
    mov rdi,version_text
    call print
    mov eax,SYS_EXIT
    xor edi,edi
    syscall

.check:
    call check_storage
    test rax,rax
    js .check_failed
    mov rdi,check_ok
    call print
    mov eax,SYS_EXIT
    xor edi,edi
    syscall
.check_failed:
    mov rdi,check_bad
    call print
    mov eax,SYS_EXIT
    mov edi,1
    syscall

; Bound retry CPU under EMFILE/ENFILE/ENOMEM/EAGAIN. No worker-pool claim.
main_backoff:
    mov eax,35 ; nanosleep
    mov rdi,overload_delay
    xor esi,esi
    syscall
    ret
