%include "src/defs.inc"
DEFAULT ABS
extern init_storage, parse_uint, validate_request, handle_request, send_error
extern print, itoa
extern strcmp, downgrade_storage

global _start
section .data
    starting db 'ASM TODO listening on 127.0.0.1:',0
    newline db 10,0
    failure db 'ASM TODO: startup failed (storage, port or socket)',10,0
    version_arg db '--storage-version',0
    version_text db '3',10,0
    downgrade_arg db '--downgrade',0
    downgrade_ok db 'ASM TODO: offline downgrade completed',10,0
    downgrade_bad db 'ASM TODO: offline downgrade failed; retain the compatible planner binary and restore the private copy',10,0
    sockaddr: dw AF_INET,0
              dd 0x0100007f
              dq 0
    port dq 34624
section .bss
    sock_fd resq 1
    client_fd resq 1
    req_buf resb REQUEST_MAX+8 ; terminator and bounded lookahead padding
    port_str resb 24
section .text
_start:
    cmp qword [rsp], 1
    je .signals
    cmp qword [rsp], 2
    jne .fatal
    mov rdi, [rsp+16]
    mov rsi,version_arg
    call strcmp
    test rax,rax
    jz .version
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
    js .accept
    mov [client_fd],rax
    mov eax,SYS_FORK
    syscall
    test rax,rax
    jz .child
    mov eax,SYS_CLOSE
    mov rdi,[client_fd]
    syscall
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
    mov edx,REQUEST_MAX
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

.downgrade:
    call downgrade_storage
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
