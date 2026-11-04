; Native backup admission, immutable transport, independent readback and health.
; rclone only encrypts/transports bytes; no shell or interpreter is executed.
%include "src/defs.inc"
DEFAULT ABS
extern strcmp, strlen, parse_uint, itoa, write_all
global _start
%define OPENAT 257
%define UNLINKAT 263
%define RENAMEAT2 316
%define FCHOWN 93
%define FCHMOD 91
%define BLOCK 65536
%define AGE 93600
section .data
    stage_arg db '--stage',0
    ship_arg db '--ship',0
    status_arg db '--status',0
    verify_arg db '--verify',0
    backup_name db 'backup',0
    archive_prefix db 'asm-todo-',0
    remote_scope db 'asm-todo',0
    backup_lock db '.backup.lock',0
    spool_lock db '.offsite.lock',0
    log_name db 'transport.log',0
    success_name db 'last-success',0
    success_tmp db '.last-success.tmp',0
    download_name db '.restore-check.tar',0
    part_suffix db '.part',0
    status_prefix db '#asm-offsite=1',10,'verified=',0
    status_archive db 10,'archive=',0
    type_key db 'type',0
    crypt_value db 'crypt',0
    no_data_key db 'no_data_encryption',0
    false_value db 'false',0
    filename_key db 'filename_encryption',0
    standard_value db 'standard',0
    directory_key db 'directory_name_encryption',0
    true_value db 'true',0
    environment db 'GOMAXPROCS=2',0
    envp dq environment,0
    copy_arg db 'copyto',0
    config_arg db '--config',0
    immutable_arg db '--immutable',0
    existing_arg db '--ignore-existing',0
    inplace_arg db '--inplace',0
    retries_arg db '--retries=2',0
    low_retries_arg db '--low-level-retries=2',0
    connect_arg db '--contimeout=15s',0
    timeout_arg db '--timeout=2m',0
    duration_arg db '--max-duration=15m',0
    checks_arg db '--checkers=2',0
    transfers_arg db '--transfers=1',0
    buffer_arg db '--buffer-size=1M',0
    quiet_arg db '--log-level=ERROR',0
    stats_arg db '--stats=0',0
    prompt_arg db '--ask-password=false',0
    args times 24 dq 0
    usage db 'Usage: offsite --stage ARCHIVES SPOOL | --ship SPOOL CONFIG CRYPT:asm-todo RCLONE | --status SPOOL MAX_AGE_SECONDS',10,0
    bad db 'ASM offsite failed; inspect private transport.log and the backup runbook.',10,0
    staged db 'ASM offsite: latest fresh native archive staged and verified.',10,0
    shipped db 'ASM offsite: encrypted copy downloaded, byte-compared and natively verified.',10,0
    healthy db 'ASM offsite: latest recorded archive and readback are fresh.',10,0
    mode dq 0
    source_fd dq -1
    spool_fd dq -1
    log_fd dq -1
    first_fd dq -1
    second_fd dq -1
    max_age dq AGE
section .bss
    source resq 1
    spool resq 1
    config resq 1
    remote resq 1
    rclone resq 1
    owner_uid resd 1
    owner_gid resd 1
    now resq 1
    epoch resq 1
    verified_at resq 1
    latest resb 96
    name_tmp resb 100
    old_latest resb 96
    expected_section resb 130
    backup_binary resb 2048
    source_path resb 2048
    stage_path resb 2048
    download_path resb 2048
    remote_path resb 2048
    config_buf resb BLOCK+1
    status_buf resb 256
    buffer_a resb BLOCK
    buffer_b resb BLOCK
    entries resb 32768
    stat_buf resb 144
    wait_status resd 1
section .text
_start:
    mov r15,rsp
    mov eax,157
    mov edi,4 ; PR_SET_DUMPABLE
    xor esi,esi
    syscall
    test rax,rax
    js fail
    mov eax,95
    mov edi,0077o
    syscall
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    test rax,rax
    jle fail
    mov [now],rax
    ; Resolve the sibling native verifier without a PATH search.
    mov rsi,[r15+8]
    mov rdi,backup_binary
    call bounded_copy
    mov rdi,backup_binary
    call strlen
    test rax,rax
    jz fail
.parent:
    dec rax
    js fail
    cmp byte [backup_binary+rax],'/'
    jne .parent
    lea rdi,[backup_binary+rax+1]
    mov rsi,backup_name
    call copy_string
    cmp qword [r15],4
    je .short
    cmp qword [r15],6
    jne .usage
    mov rdi,[r15+16]
    mov rsi,ship_arg
    call strcmp
    test rax,rax
    jnz .usage
    mov qword [mode],2
    mov rax,[r15+24]
    mov [spool],rax
    mov rax,[r15+32]
    mov [config],rax
    mov rax,[r15+40]
    mov [remote],rax
    mov rax,[r15+48]
    mov [rclone],rax
    jmp .open_spool
.short:
    mov rdi,[r15+16]
    mov rsi,stage_arg
    call strcmp
    test rax,rax
    jnz .status
    mov qword [mode],1
    mov rax,[r15+24]
    mov [source],rax
    mov rax,[r15+32]
    mov [spool],rax
    jmp .open_spool
.status:
    mov rdi,[r15+16]
    mov rsi,status_arg
    call strcmp
    test rax,rax
    jnz .usage
    mov rdi,[r15+32]
    call parse_uint
    cmp rax,600
    jb fail
    cmp rax,604800
    ja fail
    mov [max_age],rax
    mov rax,[r15+24]
    mov [spool],rax
.open_spool:
    mov rdi,[spool]
    call open_directory
    mov [spool_fd],rax
    mov rdi,rax
    call get_stat
    ; Linux x86_64 stat: uid=28, gid=32, mode=24.
    mov eax,[stat_buf+28]
    test eax,eax
    jz fail
    mov [owner_uid],eax
    mov eax,[stat_buf+32]
    mov [owner_gid],eax
    test dword [stat_buf+24],0077o
    jnz fail
    cmp qword [mode],0
    je health
    mov rdi,[spool_fd]
    mov rsi,spool_lock
    mov edx,O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK
    call open_at
    mov rbx,rax
    mov rdi,rax
    call regular
    mov eax,FCHOWN
    mov rdi,rbx
    mov esi,[owner_uid]
    mov edx,[owner_gid]
    syscall
    test rax,rax
    js fail
    mov eax,SYS_FLOCK
    mov rdi,rbx
    mov esi,LOCK_EX|4
    syscall
    test rax,rax
    js fail
    ; Serialize through this stable descriptor until process exit.
    mov rdi,[spool_fd]
    mov rsi,log_name
    mov edx,O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK
    call open_at
    mov [log_fd],rax
    mov rdi,rax
    call regular
    mov eax,SYS_FTRUNCATE
    mov rdi,[log_fd]
    xor esi,esi
    syscall
    test rax,rax
    js fail
    mov eax,FCHOWN
    mov rdi,[log_fd]
    mov esi,[owner_uid]
    mov edx,[owner_gid]
    syscall
    test rax,rax
    js fail
    cmp qword [mode],1
    je stage
    jmp ship
.usage:
    mov rsi,usage
    jmp print_fail

; All supplied paths/arguments are bounded before concatenation.
copy_string:
    lodsb
    test al,al
    jz .done
    stosb
    jmp copy_string
.done:
    mov byte [rdi],0
    ret

bounded_copy:
    push rdi
    push rsi
    mov rdi,rsi
    call strlen
    pop rsi
    pop rdi
    cmp rax,1023
    ja fail
    test rax,rax
    jz fail
    jmp copy_string

; rdi=output, rsi=base, rdx=bounded leaf; append one slash.
join:
    push rdx
    call bounded_copy
    mov byte [rdi],'/'
    inc rdi
    pop rsi
    jmp bounded_copy

open_directory:
    mov eax,SYS_OPEN
    mov esi,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js fail
    ret

open_at:
    mov eax,OPENAT
    mov r10d,0600o
    syscall
    test rax,rax
    js fail
    ret

get_stat:
    mov eax,SYS_FSTAT
    mov rsi,stat_buf
    syscall
    test rax,rax
    js fail
    ret

regular:
    call get_stat
    mov eax,[stat_buf+24]
    and eax,0170000o
    cmp eax,0100000o
    jne fail
    cmp qword [stat_buf+16],1
    jne fail
    test dword [stat_buf+24],0077o
    jnz fail
    ret

fresh:
    test rax,rax
    jle fail
    mov rdx,[now]
    add rdx,60
    cmp rax,rdx
    ja fail
    mov rdx,[now]
    sub rdx,rax
    js .ok
    cmp rdx,[max_age]
    ja fail
.ok:
    ret

; Exact native namespace -> epoch, otherwise zero. No unbounded parse/read.
archive_epoch:
    push rbx
    mov rbx,rdi
    call strlen
    cmp rax,31
    jb .no
    cmp rax,49
    ja .no
    add rbx,rax ; exact bounded end before any fixed-width extension access
    mov rsi,archive_prefix
    mov ecx,9
    repe cmpsb
    jne .no
    cmp byte [rdi],'0'
    je .no
    mov r8,rdi
    xor ecx,ecx
.digits:
    mov al,[rdi+rcx]
    cmp al,'0'
    jb .end_digits
    cmp al,'9'
    ja .end_digits
    inc ecx
    cmp ecx,19
    jbe .digits
    jmp .no
.end_digits:
    test ecx,ecx
    jz .no
    cmp al,'-'
    jne .no
    lea r9,[rdi+rcx]
    mov byte [r9],0
    push r9
    call parse_uint
    pop r9
    mov byte [r9],'-'
    test rax,rax
    jle .no
    lea rdx,[r9+21]
    cmp rdx,rbx
    jne .no
    push rax
    lea rdi,[r9+1]
    xor ecx,ecx
.hex:
    mov al,[rdi+rcx]
    cmp al,'0'
    jb .hex_no
    cmp al,'9'
    jbe .next
    cmp al,'a'
    jb .hex_no
    cmp al,'f'
    ja .hex_no
.next:
    inc ecx
    cmp ecx,16
    jb .hex
    cmp dword [rdi+16],'.tar'
    jne .hex_no
    cmp byte [rdi+20],0
    jne .hex_no
    pop rax
    jmp .done
.hex_no:
    pop rax
.no:
    xor eax,eax
.done:
    pop rbx
    ret

; Pin a directory, choose latest canonical timestamp + name. Never fall back
; from a corrupt newest archive to a misleading older "successful" backup.
scan_latest:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov byte [latest],0
    mov qword [epoch],0
.read:
    mov eax,217
    mov rdi,r12
    mov rsi,entries
    mov edx,32768
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js fail
    jz .done
    mov r13,rax
    xor ebx,ebx
.entry:
    lea r14,[entries+rbx]
    movzx eax,word [r14+16]
    cmp eax,20
    jb fail
    lea r15,[rbx+rax]
    cmp r15,r13
    ja fail
    lea rdi,[r14+19]
    mov ecx,eax
    sub ecx,19
    xor eax,eax
    repne scasb
    jne fail
    lea rdi,[r14+19]
    call archive_epoch
    test rax,rax
    jz .next
    cmp rax,[epoch]
    jb .next
    ja .choose
    lea rdi,[r14+19]
    mov rsi,latest
    call strcmp
    test rax,rax
    jle .next
    lea rdi,[r14+19]
    call archive_epoch
.choose:
    mov [epoch],rax
    mov rdi,latest
    lea rsi,[r14+19]
    call copy_string
.next:
    mov rbx,r15
    cmp rbx,r13
    jb .entry
    jmp .read
.done:
    mov rax,[epoch]
    call fresh
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

stage:
    mov rdi,[source]
    call open_directory
    mov [source_fd],rax
    mov rdi,rax
    mov rsi,backup_lock
    mov edx,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK
    call open_at
    mov rbx,rax
    mov rdi,rax
    call regular
    mov eax,SYS_FLOCK
    mov rdi,rbx
    mov esi,LOCK_SH|4
    syscall
    test rax,rax
    js fail
    mov rdi,[source_fd]
    call scan_latest
    mov rdi,source_path
    mov rsi,[source]
    mov rdx,latest
    call join
    mov rdi,source_path
    call verify
    mov rdi,stage_path
    mov rsi,[spool]
    mov rdx,latest
    call join
    mov eax,OPENAT
    mov rdi,[spool_fd]
    mov rsi,latest
    mov edx,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    syscall
    cmp rax,-2
    je .copy
    test rax,rax
    js fail
    mov rdi,rax
    call regular
    mov eax,SYS_CLOSE
    syscall
    mov rdi,source_path
    mov rsi,stage_path
    call compare
    jmp .complete
.copy:
    mov rdi,name_tmp
    mov rsi,latest
    call copy_string
    mov rsi,part_suffix
    call copy_string
    mov rsi,name_tmp
    call remove_private
    mov rdi,[source_fd]
    mov rsi,latest
    mov edx,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    call open_at
    mov [first_fd],rax
    mov rdi,rax
    call regular
    mov rdi,[spool_fd]
    mov rsi,name_tmp
    mov edx,O_WRONLY|O_CREAT|128|O_NOFOLLOW|O_CLOEXEC
    call open_at
    mov [second_fd],rax
    mov rdi,rax
    call regular
    mov eax,FCHOWN
    mov rdi,[second_fd]
    mov esi,[owner_uid]
    mov edx,[owner_gid]
    syscall
    test rax,rax
    js fail
.bytes:
    mov eax,SYS_READ
    mov rdi,[first_fd]
    mov rsi,buffer_a
    mov edx,BLOCK
    syscall
    cmp rax,-4
    je .bytes
    test rax,rax
    js fail
    jz .publish
    mov rdx,rax
    mov rdi,[second_fd]
    mov rsi,buffer_a
    call write_all
    test rax,rax
    js fail
    jmp .bytes
.publish:
    mov rdi,[second_fd]
    call sync_close
    mov eax,SYS_CLOSE
    mov rdi,[first_fd]
    syscall
    mov eax,RENAMEAT2
    mov rdi,[spool_fd]
    mov rsi,name_tmp
    mov rdx,rdi
    mov r10,latest
    mov r8d,1
    syscall
    test rax,rax
    js fail
    mov rdi,[spool_fd]
    call sync_fd
.complete:
    ; Retain at most the latest staged archive; source/remote history is untouched.
    mov eax,SYS_LSEEK
    mov rdi,[spool_fd]
    xor esi,esi
    xor edx,edx
    syscall
    test rax,rax
    js fail
    call prune_spool
    mov rsi,staged
    jmp success

; Only regular private files in this dedicated directory may be removed.
remove_private:
    push rbx
    mov rbx,rsi
    mov eax,OPENAT
    mov rdi,[spool_fd]
    mov edx,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC
    syscall
    cmp rax,-2
    je .done
    test rax,rax
    js fail
    mov rdi,rax
    call regular
    mov eax,SYS_CLOSE
    syscall
    mov eax,UNLINKAT
    mov rdi,[spool_fd]
    mov rsi,rbx
    xor edx,edx
    syscall
    test rax,rax
    js fail
.done:
    pop rbx
    ret

prune_spool:
    mov eax,217
    mov rdi,[spool_fd]
    mov rsi,entries
    mov edx,32768
    syscall
    cmp rax,-4
    je prune_spool
    test rax,rax
    js fail
    jz .done
    mov r12,rax
    xor ebx,ebx
.entry:
    lea r13,[entries+rbx]
    movzx r14d,word [r13+16]
    cmp r14d,20
    jb fail
    lea rax,[rbx+r14]
    cmp rax,r12
    ja fail
    lea rdi,[r13+19]
    mov ecx,r14d
    sub ecx,19
    xor eax,eax
    repne scasb
    jne fail
    lea rdi,[r13+19]
    mov rsi,latest
    call strcmp
    test rax,rax
    jz .next
    lea rdi,[r13+19]
    call archive_epoch
    test rax,rax
    jz .next
    lea rsi,[r13+19]
    call remove_private
.next:
    add rbx,r14
    cmp rbx,r12
    jb .entry
    jmp prune_spool
.done:
    mov rdi,[spool_fd]
    jmp sync_fd

ship:
    mov rdi,[spool_fd]
    call scan_latest
    mov rdi,stage_path
    mov rsi,[spool]
    mov rdx,latest
    call join
    call guard_config
    mov rdi,stage_path
    call verify
    mov rdi,remote_path
    mov rsi,[remote]
    mov rdx,latest
    call join
    mov rdi,stage_path
    mov rsi,remote_path
    call transport
    mov rsi,download_name
    call remove_private
    mov rdi,download_path
    mov rsi,[spool]
    mov rdx,download_name
    call join
    mov rdi,remote_path
    mov rsi,download_path
    call transport
    mov rdi,stage_path
    mov rsi,download_path
    call compare
    mov rdi,download_path
    call verify
    mov rsi,download_name
    call remove_private
    ; Recheck time after transport; an old archive never becomes fresh by upload.
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    mov [now],rax
    mov rax,[epoch]
    call fresh
    call record_success
    mov rsi,shipped
    jmp success

; No shell, PATH resolution, inherited credentials or RCLONE_* overrides.
spawn:
    mov r12,rdi
    mov eax,SYS_FORK
    syscall
    test rax,rax
    js fail
    jz .child
    mov r13,rax
.wait:
    mov eax,61
    mov rdi,r13
    mov rsi,wait_status
    xor edx,edx
    xor r10d,r10d
    syscall
    cmp rax,-4
    je .wait
    cmp rax,r13
    jne fail
    cmp dword [wait_status],0
    jne fail
    ret
.child:
    mov eax,33
    mov rdi,[log_fd]
    mov esi,1
    syscall
    test rax,rax
    js .child_fail
    mov eax,33
    mov esi,2
    syscall
    test rax,rax
    js .child_fail
    mov eax,59
    mov rdi,[r12]
    mov rsi,r12
    mov rdx,envp
    syscall
.child_fail:
    mov eax,SYS_EXIT
    mov edi,127
    syscall

verify:
    mov [args+16],rdi
    mov qword [args],backup_binary
    mov qword [args+8],verify_arg
    mov qword [args+24],0
    mov rdi,args
    jmp spawn

transport:
    mov [args+16],rdi
    mov [args+24],rsi
    mov rax,[rclone]
    mov [args],rax
    mov qword [args+8],copy_arg
    mov qword [args+32],config_arg
    mov rax,[config]
    mov [args+40],rax
    mov qword [args+48],immutable_arg
    mov qword [args+56],inplace_arg
    mov qword [args+64],retries_arg
    mov qword [args+72],low_retries_arg
    mov qword [args+80],connect_arg
    mov qword [args+88],timeout_arg
    mov qword [args+96],duration_arg
    mov qword [args+104],checks_arg
    mov qword [args+112],transfers_arg
    mov qword [args+120],buffer_arg
    mov qword [args+128],quiet_arg
    mov qword [args+136],stats_arg
    mov qword [args+144],prompt_arg
    mov qword [args+152],existing_arg
    mov qword [args+160],0
    mov rdi,args
    jmp spawn

; Compare complete byte streams with fixed memory, including short read/EINTR.
compare:
    push rsi
    mov eax,SYS_OPEN
    mov esi,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js fail
    mov [first_fd],rax
    mov rdi,rax
    call regular
    pop rdi
    mov eax,SYS_OPEN
    mov esi,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js fail
    mov [second_fd],rax
    mov rdi,rax
    call regular
.loop:
    mov rdi,[first_fd]
    mov rsi,buffer_a
    call fill
    mov r14,rax
    mov rdi,[second_fd]
    mov rsi,buffer_b
    call fill
    cmp rax,r14
    jne fail
    test rax,rax
    jz .done
    mov rcx,rax
    mov rdi,buffer_a
    mov rsi,buffer_b
    repe cmpsb
    jne fail
    jmp .loop
.done:
    mov eax,SYS_CLOSE
    mov rdi,[first_fd]
    syscall
    mov eax,SYS_CLOSE
    mov rdi,[second_fd]
    syscall
    ret

fill:
    xor r8d,r8d
    mov r9,rsi
.read:
    mov eax,SYS_READ
    lea rsi,[r9+r8]
    mov edx,BLOCK
    sub rdx,r8
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js fail
    jz .done
    add r8,rax
    cmp r8,BLOCK
    jb .read
.done:
    mov rax,r8
    ret

sync_close:
    push rdi
    call sync_fd
    pop rdi
    mov eax,SYS_CLOSE
    syscall
    test rax,rax
    js fail
    ret
sync_fd:
    mov eax,SYS_FSYNC
    syscall
    test rax,rax
    js fail
    ret

record_success:
    mov rdi,status_buf
    mov rsi,status_prefix
    call copy_string
    mov rsi,rdi
    mov rdi,[now]
    call itoa
    add rsi,rax
    mov rdi,rsi
    mov rsi,status_archive
    call copy_string
    mov rsi,latest
    call copy_string
    mov byte [rdi],10
    inc rdi
    sub rdi,status_buf
    push rdi
    mov rsi,success_tmp
    call remove_private
    mov rdi,[spool_fd]
    mov rsi,success_tmp
    mov edx,O_WRONLY|O_CREAT|128|O_NOFOLLOW|O_CLOEXEC
    call open_at
    mov rbx,rax
    mov rdi,rax
    call regular
    pop rdx
    mov rsi,status_buf
    mov rdi,rbx
    call write_all
    test rax,rax
    js fail
    mov rdi,rbx
    call sync_close
    ; Existing status may be replaced atomically, never followed/truncated.
    mov eax,RENAMEAT2
    mov rdi,[spool_fd]
    mov rsi,success_tmp
    mov rdx,rdi
    mov r10,success_name
    xor r8d,r8d
    syscall
    test rax,rax
    js fail
    mov rdi,[spool_fd]
    jmp sync_fd

health:
    mov rdi,[spool_fd]
    mov rsi,success_name
    mov edx,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC
    call open_at
    mov rbx,rax
    mov rdi,rax
    call regular
    cmp qword [stat_buf+48],255
    ja fail
    mov eax,SYS_READ
    mov rdi,rbx
    mov rsi,status_buf
    mov edx,256
    syscall
    test rax,rax
    jle fail
    cmp rax,256
    jae fail
    mov byte [status_buf+rax],0
    push rax
    mov rdi,status_buf
    call strlen
    pop rdx
    cmp rax,rdx
    jne fail
    mov rdi,status_buf
    mov rsi,status_prefix
    ; Derive prefix length rather than accepting partial or extra fields.
    push rax
    mov rdi,status_prefix
    call strlen
    mov rcx,rax
    mov rsi,status_prefix
    mov rdi,status_buf
    repe cmpsb
    jne fail
    mov rbx,rdi
.number:
    cmp byte [rdi],0
    je fail
    cmp byte [rdi],10
    je .date
    inc rdi
    mov rax,rdi
    sub rax,rbx
    cmp rax,19
    ja fail
    jmp .number
.date:
    mov byte [rdi],0
    push rdi
    mov rdi,rbx
    call parse_uint
    call fresh
    pop rdi
    inc rdi
    mov rax,'archive='
    cmp qword [rdi],rax
    jne fail
    add rdi,8
    mov rbx,rdi
    call strlen
    test rax,rax
    jz fail
    cmp byte [rbx+rax-1],10
    jne fail
    mov byte [rbx+rax-1],0
    mov rdi,rbx
    call archive_epoch
    call fresh
    pop rax
    mov rsi,healthy
    jmp success

; Bounded, fail-closed INI policy: selected remote must be crypt, with content
; encryption and standard name encryption. Child environment cannot override it.
guard_config:
    mov rsi,[remote]
    mov rdi,expected_section
    mov byte [rdi],'['
    inc rdi
    xor ecx,ecx
.alias:
    mov al,[rsi+rcx]
    cmp al,':'
    je .scope
    cmp al,'a'
    jb .alias_other
    cmp al,'z'
    jbe .alias_ok
.alias_other:
    cmp al,'0'
    jb .alias_punct
    cmp al,'9'
    jbe .alias_ok
.alias_punct:
    cmp al,'-'
    je .alias_ok
    cmp al,'_'
    jne fail
.alias_ok:
    mov [rdi+rcx],al
    inc ecx
    cmp ecx,63
    ja fail
    jmp .alias
.scope:
    test ecx,ecx
    jz fail
    mov byte [rdi+rcx],']'
    mov byte [rdi+rcx+1],0
    lea rdi,[rsi+rcx+1]
    mov rsi,remote_scope
    call strcmp
    test rax,rax
    jnz fail
    mov eax,SYS_OPEN
    mov rdi,[config]
    mov esi,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js fail
    mov rbx,rax
    mov rdi,rax
    call regular
    cmp qword [stat_buf+48],BLOCK
    jae fail
    mov rdi,rbx
    mov rsi,config_buf
    call fill
    cmp rax,BLOCK
    jae fail
    mov byte [config_buf+rax],0
    push rax
    mov rdi,config_buf
    call strlen
    pop rdx
    cmp rax,rdx
    jne fail
    mov eax,SYS_CLOSE
    mov rdi,rbx
    syscall
    mov rbx,config_buf
    xor r12d,r12d ; selected section
    xor r13d,r13d ; selected section count
    xor r14d,r14d ; type seen
.line:
    cmp byte [rbx],0
    je .done
    mov r15,rbx
.end:
    cmp byte [r15],0
    je .terminated
    cmp byte [r15],10
    je .lf
    inc r15
    jmp .end
.lf:
    mov byte [r15],0
    inc r15
.terminated:
    mov rdi,rbx
    call trim
    mov rbx,rax
    cmp byte [rbx],'['
    jne .key
    mov rdi,rbx
    call strlen
    cmp rax,3
    jb fail
    cmp byte [rbx+rax-1],']'
    jne fail
    lea rdi,[rbx+1]
.section_char:
    mov al,[rdi]
    cmp al,']'
    je .section_end
    cmp al,'A'
    jb .section_lower
    cmp al,'Z'
    ja .section_lower
    add byte [rdi],32
    add al,32
.section_lower:
    cmp al,'a'
    jb .section_digit
    cmp al,'z'
    jbe .section_next
.section_digit:
    cmp al,'0'
    jb .section_punct
    cmp al,'9'
    jbe .section_next
.section_punct:
    cmp al,'-'
    je .section_next
    cmp al,'_'
    jne fail
.section_next:
    inc rdi
    jmp .section_char
.section_end:
    cmp byte [rdi+1],0
    jne fail
    xor r12d,r12d
    mov rdi,rbx
    mov rsi,expected_section
    call strcmp
    test rax,rax
    jnz .next
    inc r13
    cmp r13,1
    jne fail
    mov r12d,1
    jmp .next
.key:
    test r12,r12
    jz .next
    cmp byte [rbx],0
    je .next
    cmp byte [rbx],'#'
    je .next
    cmp byte [rbx],';'
    je .next
    mov rdi,rbx
.equals:
    mov al,[rdi]
    test al,al
    jz fail
    cmp al,'='
    je .split
    cmp al,'A'
    jb .char
    cmp al,'Z'
    ja .char
    add byte [rdi],32
.char:
    inc rdi
    jmp .equals
.split:
    mov byte [rdi],0
    inc rdi
    call trim
    push rax
    mov rdi,rbx
    call trim
    mov rbx,rax
    pop rdx ; value pointer
    push rdx
    mov rdi,rbx
    mov rsi,type_key
    call strcmp
    test rax,rax
    jnz .no_data
    inc r14
    cmp r14,1
    jne fail
    pop rdi
    mov rsi,crypt_value
    call strcmp
    test rax,rax
    jnz fail
    jmp .next
.no_data:
    mov rdi,rbx
    mov rsi,no_data_key
    call strcmp
    test rax,rax
    jnz .filenames
    pop rdi
    mov rsi,false_value
    call strcmp
    test rax,rax
    jnz fail
    jmp .next
.filenames:
    mov rdi,rbx
    mov rsi,filename_key
    call strcmp
    test rax,rax
    jnz .directories
    pop rdi
    mov rsi,standard_value
    call strcmp
    test rax,rax
    jnz fail
    jmp .next
.directories:
    mov rdi,rbx
    mov rsi,directory_key
    call strcmp
    pop rdi
    test rax,rax
    jnz .next
    mov rsi,true_value
    call strcmp
    test rax,rax
    jnz fail
.next:
    mov rbx,r15
    jmp .line
.done:
    cmp r13,1
    jne fail
    cmp r14,1
    jne fail
    ret

trim:
    cmp byte [rdi],' '
    je .skip
    cmp byte [rdi],9
    jne .start
.skip:
    inc rdi
    jmp trim
.start:
    push rdi
    call strlen
    pop rdi
    lea rdx,[rdi+rax]
.tail:
    cmp rdx,rdi
    je .done
    mov al,[rdx-1]
    cmp al,' '
    je .remove
    cmp al,9
    je .remove
    cmp al,13
    jne .done
.remove:
    dec rdx
    mov byte [rdx],0
    jmp .tail
.done:
    mov rax,rdi
    ret

success:
    mov rdi,1
    push rsi
    mov rdi,rsi
    call strlen
    mov rdx,rax
    pop rsi
    mov edi,1
    call write_all
    mov eax,SYS_EXIT
    xor edi,edi
    syscall
fail:
    mov rsi,bad
print_fail:
    push rsi
    mov rdi,rsi
    call strlen
    mov rdx,rax
    pop rsi
    mov edi,2
    call write_all
    mov eax,SYS_EXIT
    mov edi,1
    syscall
