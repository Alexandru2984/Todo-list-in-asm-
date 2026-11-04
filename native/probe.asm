; Read-only operational checks. HTTP/TLS transport uses curl; all acceptance
; decisions, bounds and filesystem accounting are native Linux x86_64 syscalls.
%include "src/defs.inc"
DEFAULT ABS
extern strcmp, strlen, parse_uint, itoa, write_all
global _start
section .data
    http_arg db '--http',0
    file_arg db '--health-file',0
    space_arg db '--space',0
    curl_binary db '/usr/bin/curl',0
    disable_arg db '--disable',0
    proto_arg db '--proto',0
    protocols db '=http,https',0
    noproxy_arg db '--noproxy',0
    star db '*',0
    fail_arg db '--fail',0
    silent_arg db '--silent',0
    show_arg db '--show-error',0
    connect_arg db '--connect-timeout=2',0
    timeout_arg db '--max-time=5',0
    retry_arg db '--retry=1',0
    retry_all_arg db '--retry-all-errors',0
    retry_delay_arg db '--retry-delay=1',0
    retry_time_arg db '--retry-max-time=12',0
    size_arg db '--max-filesize=1024',0
    write_arg db '--write-out',0
    write_format db 10,'%{http_code}',0
    url_arg db '--url',0
    argv dq curl_binary,disable_arg,proto_arg,protocols,noproxy_arg,star
         dq fail_arg,silent_arg,show_arg,connect_arg,timeout_arg,retry_arg
         dq retry_all_arg,retry_delay_arg,retry_time_arg,size_arg
         dq write_arg,write_format,url_arg,0,0
    empty_env dq 0
    health db '{"status":"ok"}',10
    health_len equ $-health
    transport_health db '{"status":"ok"}',10,10,'200'
    transport_len equ $-transport_health
    usage db 'Usage: probe --http URL | --health-file FILE | --space DIRECTORY MIN_BYTES MIN_SPACE_PERCENT MIN_INODE_PERCENT',10,0
    invalid db 'ASM probe: invalid input, unsafe inode or unavailable filesystem accounting.',10,0
    bad_health db 'ASM probe: unexpected health response; body omitted.',10,0
    bad_http db 'ASM probe: HTTP/TLS transport failed; response body omitted.',10,0
    low_space db 'ASM probe: filesystem free space is below the configured threshold.',10,0
    low_inodes db 'ASM probe: filesystem free inodes are below the configured threshold.',10,0
    ok db 'ASM probe: exact healthy response verified.',10,0
    capacity_start db 'ASM capacity healthy: available_bytes=',0
    block_label db ' block_free_percent=',0
    inode_label db ' inode_free_percent=',0
    newline db 10,0
section .bss
    stat_buf resb 144
    response resb transport_len+1
    output resb 256
    pipe_fds resd 2
    child_status resd 1
    child_pid resq 1
    response_len resq 1
    min_bytes resq 1
    min_blocks resq 1
    min_inodes resq 1
    available resq 1
    block_percent resq 1
    inode_percent resq 1
section .text
_start:
    mov r15,rsp
    mov eax,157
    mov edi,4
    xor esi,esi
    syscall
    test rax,rax
    js input_error
    cmp qword [r15],3
    je .short
    cmp qword [r15],6
    jne .usage
    mov rdi,[r15+16]
    mov rsi,space_arg
    call strcmp
    test rax,rax
    jnz .usage
    mov rdi,[r15+32]
    call parse_uint
    test rax,rax
    js input_error
    mov [min_bytes],rax
    mov rdi,[r15+40]
    call parse_uint
    cmp rax,100
    ja input_error
    mov [min_blocks],rax
    mov rdi,[r15+48]
    call parse_uint
    cmp rax,100
    ja input_error
    mov [min_inodes],rax
    jmp space_check
.short:
    mov rdi,[r15+16]
    mov rsi,http_arg
    call strcmp
    test rax,rax
    jz http_check
    mov rdi,[r15+16]
    mov rsi,file_arg
    call strcmp
    test rax,rax
    jz file_check
.usage:
    mov rsi,usage
    mov edi,2
    jmp message

file_check:
    mov eax,SYS_OPEN
    mov rdi,[r15+24]
    mov esi,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js input_error
    mov rbx,rax
    mov eax,SYS_FSTAT
    mov rdi,rbx
    mov rsi,stat_buf
    syscall
    test rax,rax
    js input_error
    mov eax,[stat_buf+24]
    and eax,0170000o
    cmp eax,0100000o
    jne input_error
    cmp qword [stat_buf+16],1
    jne input_error
    cmp qword [stat_buf+48],health_len
    jne health_error
    mov rdi,rbx
    mov edx,health_len+1
    call read_bounded
    cmp rax,health_len
    jne health_error
    mov rdi,response
    mov rsi,health
    mov ecx,health_len
    repe cmpsb
    jne health_error
    jmp healthy

http_check:
    mov rdi,[r15+24]
    call strlen
    cmp rax,1024
    ja input_error
    cmp rax,8
    jb input_error
    mov rdi,[r15+24]
    cmp dword [rdi],'http'
    jne input_error
    cmp dword [rdi+4],'s://'
    je .url
    cmp word [rdi+4],':/'
    jne input_error
    cmp byte [rdi+6],'/'
    jne input_error
.url:
    mov [argv+19*8],rdi
    mov eax,293 ; pipe2
    mov rdi,pipe_fds
    mov esi,O_CLOEXEC
    syscall
    test rax,rax
    js transport_error
    mov eax,SYS_FORK
    syscall
    test rax,rax
    js transport_error
    jz .child
    mov [child_pid],rax
    mov eax,SYS_CLOSE
    mov edi,[pipe_fds+4]
    syscall
    mov edi,[pipe_fds]
    mov edx,transport_len+1
    call read_bounded
    mov [response_len],rax
    mov eax,SYS_CLOSE
    mov edi,[pipe_fds]
    syscall
    cmp qword [response_len],transport_len
    jbe .wait
    ; A wrong/oversized body must not keep a producer or drip feed alive.
    mov eax,62
    mov rdi,[child_pid]
    mov esi,15
    syscall
.wait:
    mov eax,61
    mov rdi,[child_pid]
    mov rsi,child_status
    xor edx,edx
    xor r10d,r10d
    syscall
    cmp rax,-4
    je .wait
    cmp rax,[child_pid]
    jne transport_error
    cmp dword [child_status],0
    jne transport_error
    cmp qword [response_len],transport_len
    jne health_error
    mov rdi,response
    mov rsi,transport_health
    mov ecx,transport_len
    repe cmpsb
    jne health_error
    jmp healthy
.child:
    mov eax,33
    mov edi,[pipe_fds+4]
    mov esi,1
    syscall
    test rax,rax
    js .child_fail
    mov eax,SYS_CLOSE
    mov edi,[pipe_fds]
    cmp edi,1
    je .write_end
    syscall
.write_end:
    mov eax,SYS_CLOSE
    mov edi,[pipe_fds+4]
    cmp edi,1
    je .exec
    syscall
.exec:
    mov eax,59
    mov rdi,curl_binary
    mov rsi,argv
    mov rdx,empty_env
    syscall
.child_fail:
    mov eax,SYS_EXIT
    mov edi,127
    syscall

; Caller supplies a fixed limit no larger than the response buffer.
read_bounded:
    xor r8d,r8d
    mov r9,rdx
.read:
    mov eax,SYS_READ
    lea rsi,[response+r8]
    mov rdx,r9
    sub rdx,r8
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js .done
    jz .end
    add r8,rax
    cmp r8,r9
    jb .read
.end:
    mov rax,r8
.done:
    ret

space_check:
    mov eax,SYS_OPEN
    mov rdi,[r15+24]
    mov esi,2097152|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC ; O_PATH, no data access
    xor edx,edx
    syscall
    test rax,rax
    js input_error
    mov rdi,rax
    mov eax,138 ; fstatfs on a pinned directory descriptor
    mov rsi,stat_buf
    syscall
    test rax,rax
    js input_error
    ; This unit deliberately sees read-only sandbox mounts. Capacity is global
    ; filesystem accounting, not a claim about another process's write access.
    mov rax,[stat_buf+16] ; f_blocks
    test rax,rax
    jz input_error
    mov rbx,[stat_buf+32] ; f_bavail excludes reserved blocks
    cmp rbx,rax
    ja input_error
    mov rax,rbx
    mov ecx,100
    mul rcx
    div qword [stat_buf+16]
    mov [block_percent],rax
    cmp rax,[min_blocks]
    jb space_error
    mov rax,[stat_buf+72] ; f_frsize, falling back to f_bsize
    test rax,rax
    jnz .size
    mov rax,[stat_buf+8]
.size:
    test rax,rax
    jz input_error
    mul rbx
    test rdx,rdx
    jnz input_error
    mov [available],rax
    cmp rax,[min_bytes]
    jb space_error
    mov rbx,[stat_buf+40] ; total inode count, zero means unavailable
    test rbx,rbx
    jnz .inodes
    cmp qword [min_inodes],0
    jne input_error
    jmp .output
.inodes:
    mov rax,[stat_buf+48]
    cmp rax,rbx
    ja input_error
    mov ecx,100
    mul rcx
    div rbx
    mov [inode_percent],rax
    cmp rax,[min_inodes]
    jb inode_error
.output:
    mov rdi,output
    mov rsi,capacity_start
    call copy_string
    mov rsi,rdi
    mov rdi,[available]
    call itoa
    add rsi,rax
    mov rdi,rsi
    mov rsi,block_label
    call copy_string
    mov rsi,rdi
    mov rdi,[block_percent]
    call itoa
    add rsi,rax
    mov rdi,rsi
    mov rsi,inode_label
    call copy_string
    mov rsi,rdi
    mov rdi,[inode_percent]
    call itoa
    add rsi,rax
    mov rdi,rsi
    mov rsi,newline
    call copy_string
    mov rsi,output
    xor edi,edi
    jmp message

copy_string:
    lodsb
    test al,al
    jz .done
    stosb
    jmp copy_string
.done:
    mov byte [rdi],0
    ret

healthy:
    mov rsi,ok
    xor edi,edi
    jmp message
input_error:
    mov rsi,invalid
    mov edi,2
    jmp message
health_error:
    mov rsi,bad_health
    mov edi,3
    jmp message
space_error:
    mov rsi,low_space
    mov edi,4
    jmp message
inode_error:
    mov rsi,low_inodes
    mov edi,5
    jmp message
transport_error:
    mov rsi,bad_http
    mov edi,6
    jmp message
message:
    push rdi
    push rsi
    mov rdi,rsi
    call strlen
    mov rdx,rax
    pop rsi
    mov edi,1
    cmp qword [rsp],0
    je .write
    mov edi,2
.write:
    call write_all
    pop rdi
    mov eax,SYS_EXIT
    syscall
