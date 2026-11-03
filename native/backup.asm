%include "src/defs.inc"
DEFAULT ABS
extern strcmp, strlen, itoa, parse_uint, write_all, sha256
global _start
%define FSTAT 5
%define FCHMOD 91
%define UMASK 95
%define GETDENTS64 217
%define OPENAT 257
%define UNLINKAT 263
%define RENAMEAT2 316
%define FILE_MAX 262144
%define MANIFEST_MAX 16777216
%define RECORD_MAX 100000
%define RECORD_LEN 109 ; 64 hex, two spaces, 42 filename bytes, LF
section .data
    usage db 'Usage: backup DATA_DIR OUTPUT_DIR | --verify ARCHIVE.tar | --hash FILE',10,0
    failure db 'Native backup failed: invalid input, unsafe file, I/O or integrity error',10,0
    created db 'Native backup verified and created: ',0
    verified db 'Native backup verification passed. Workspaces: ',0
    newline db 10,0
    mode_verify db '--verify',0
    mode_hash db '--hash',0
    manifest_name db 'SHA256SUMS',0
    lock_name db '.backup.lock',0
    prefix db 'asm-todo-',0
    tmp_prefix db '.snapshot-',0
    extension db '.tar',0
    tmp_extension db '.tmp',0
    hex db '0123456789abcdef'
    source_fd dq -1
    output_fd dq -1
    archive_fd dq -1
    temporary_created dq 0
section .bss
    directory_buf resb 32768
    stat_buf resb 144
    data_buf resb FILE_MAX+512
    header resb 512
    zeros resb 1024
    digest resb 32
    hash_text resb 66
    computed resb MANIFEST_MAX
    expected resb MANIFEST_MAX
    names_seen resq 131072
    manifest_len resq 1
    record_count resq 1
    member_len resq 1
    now resq 1
    source_name resb 43
    random_bytes resb 8
    unique_suffix resb 64
    final_name resb 96
    temporary_name resb 96
    number resb 32
section .text
_start:
    cmp qword [rsp],3
    jne .usage
    mov r12,[rsp+16]
    mov r13,[rsp+24]
    mov eax,157 ; prctl(PR_SET_DUMPABLE, 0): never dump private backup buffers
    mov edi,4
    xor esi,esi
    syscall
    test rax,rax
    js fail
    mov eax,UMASK
    mov edi,0077o
    syscall
    mov rdi,r12
    mov rsi,mode_hash
    call strcmp
    test rax,rax
    jz .hash
    mov rdi,r12
    mov rsi,mode_verify
    call strcmp
    test rax,rax
    jz .verify
    mov eax,SYS_OPEN
    mov rdi,r12
    mov esi,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js fail
    mov [source_fd],rax
    mov eax,SYS_MKDIR
    mov rdi,r13
    mov esi,0700o
    syscall
    test rax,rax
    jns .open_output
    cmp rax,-17
    jne fail
.open_output:
    mov eax,SYS_OPEN
    mov rdi,r13
    mov esi,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js fail
    mov [output_fd],rax
    mov rdi,rax
    mov eax,FCHMOD
    mov esi,0700o
    syscall
    test rax,rax
    js fail
    mov eax,OPENAT
    mov rdi,[output_fd]
    mov rsi,lock_name
    mov edx,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC
    mov r10d,0600o
    syscall
    test rax,rax
    js fail
    mov rdi,rax ; fd intentionally stays open until exit, serializes retention too
    mov eax,SYS_FLOCK
    mov esi,LOCK_EX|4 ; LOCK_NB
    syscall
    test rax,rax
    js fail
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    test rax,rax
    js fail
    mov [now],rax
    mov rdi,rax
    mov rsi,unique_suffix
    call itoa
    lea rdi,[unique_suffix+rax]
    mov byte [rdi],'-'
    lea r12,[rdi+1]
    xor r9d,r9d
.random:
    mov eax,SYS_GETRANDOM
    lea rdi,[random_bytes+r9]
    mov esi,8
    sub rsi,r9
    xor edx,edx
    syscall
    cmp rax,-4
    je .random
    test rax,rax
    jle fail
    add r9,rax
    cmp r9,8
    jb .random
    xor ecx,ecx
.hex:
    movzx eax,byte [random_bytes+rcx]
    mov edx,eax
    shr eax,4
    and edx,15
    mov al,[hex+rax]
    mov dl,[hex+rdx]
    mov [r12+rcx*2],al
    mov [r12+rcx*2+1],dl
    inc ecx
    cmp ecx,8
    jb .hex
    mov byte [r12+16],0
    mov rdi,final_name
    mov rsi,prefix
    call copy_z
    mov rsi,unique_suffix
    call copy_z
    mov rsi,extension
    call copy_z
    mov rdi,temporary_name
    mov rsi,tmp_prefix
    call copy_z
    mov rsi,unique_suffix
    call copy_z
    mov rsi,tmp_extension
    call copy_z
    mov eax,OPENAT
    mov rdi,[output_fd]
    mov rsi,temporary_name
    mov edx,O_WRONLY|O_CREAT|128|O_NOFOLLOW|O_CLOEXEC ; O_EXCL
    mov r10d,0600o
    syscall
    test rax,rax
    js fail
    mov [archive_fd],rax
    mov qword [temporary_created],1
    call reset_manifest
    mov rdi,[source_fd]
    mov rsi,backup_file
    call walk_directory
    mov rdi,manifest_name
    mov rsi,[manifest_len]
    call write_header
    mov rsi,computed
    mov rdx,[manifest_len]
    call archive_write
    mov rax,[manifest_len]
    call write_padding
    mov rsi,zeros
    mov edx,1024
    call archive_write
    mov eax,SYS_FSYNC
    mov rdi,[archive_fd]
    syscall
    test rax,rax
    js fail
    mov eax,SYS_CLOSE
    mov rdi,[archive_fd]
    syscall
    test rax,rax
    js fail
    mov eax,OPENAT
    mov rdi,[output_fd]
    mov rsi,temporary_name
    mov edx,O_RDONLY|O_NOFOLLOW|O_CLOEXEC
    xor r10d,r10d
    syscall
    test rax,rax
    js fail
    mov [archive_fd],rax
    call verify_archive
    mov eax,RENAMEAT2
    mov rdi,[output_fd]
    mov rsi,temporary_name
    mov rdx,rdi
    mov r10,final_name
    mov r8d,1 ; RENAME_NOREPLACE
    syscall
    test rax,rax
    js fail
    mov qword [temporary_created],0
    mov eax,SYS_FSYNC
    mov rdi,[output_fd]
    syscall
    test rax,rax
    js fail
    mov rdi,[output_fd]
    mov rsi,prune_file
    call walk_directory
    mov eax,SYS_FSYNC
    mov rdi,[output_fd]
    syscall
    test rax,rax
    js fail
    mov rdi,created
    call print_text
    mov rdi,final_name
    call print_text
    mov rdi,newline
    call print_text
    jmp success
.verify:
    mov eax,SYS_OPEN
    mov rdi,r13
    mov esi,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|2048
    xor edx,edx
    syscall
    test rax,rax
    js fail
    mov [archive_fd],rax
    call verify_archive
    mov rdi,verified
    call print_text
    mov rdi,[record_count]
    mov rsi,number
    call itoa
    mov rdi,number
    call print_text
    mov rdi,newline
    call print_text
    jmp success
.hash:
    mov eax,SYS_OPEN
    mov rdi,r13
    mov esi,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|2048
    xor edx,edx
    syscall
    test rax,rax
    js fail
    mov rdi,rax
    call read_data
    mov rdi,data_buf
    mov rsi,[member_len]
    mov rdx,digest
    call sha256
    call encode_digest
    mov byte [hash_text+64],10
    mov edi,STDOUT
    mov rsi,hash_text
    mov edx,65
    call write_all
    test rax,rax
    js fail
    jmp success
.usage:
    mov rdi,usage
    call print_text
    mov eax,SYS_EXIT
    mov edi,64
    syscall
success:
    mov eax,SYS_EXIT
    xor edi,edi
    syscall
fail:
    cmp qword [temporary_created],0
    je .message
    mov eax,UNLINKAT
    mov rdi,[output_fd]
    mov rsi,temporary_name
    xor edx,edx
    syscall
.message:
    mov rdi,failure
    call strlen
    mov rdx,rax
    mov edi,STDERR
    mov rsi,failure
    call write_all
    mov eax,SYS_EXIT
    mov edi,1
    syscall

copy_z:
    lodsb
    stosb
    test al,al
    jnz copy_z
    dec rdi
    ret
print_text:
    push rdi
    call strlen
    mov rdx,rax
    pop rsi
    mov edi,STDOUT
    call write_all
    test rax,rax
    js fail
    ret
archive_write:
    mov rdi,[archive_fd]
    call write_all
    test rax,rax
    js fail
    ret
read_exact:
.loop:
    test rdx,rdx
    jz .done
    xor eax,eax
    syscall
    cmp rax,-4
    je .loop
    test rax,rax
    jle fail
    add rsi,rax
    sub rdx,rax
    jmp .loop
.done:
    ret

; Pin one immutable source inode; no symlink, FIFO, device or hard-link reads.
read_data:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    mov eax,FSTAT
    mov rsi,stat_buf
    syscall
    test rax,rax
    js fail
    mov eax,[stat_buf+24]
    and eax,0170000o
    cmp eax,0100000o
    jne fail
    cmp qword [stat_buf+16],1
    ja fail ; nlink=0 is valid when an atomic replacement unlinks our pinned inode
    mov r12,[stat_buf+48]
    cmp r12,FILE_MAX
    ja fail
    xor r13d,r13d
.loop:
    xor eax,eax
    mov rdi,rbx
    lea rsi,[data_buf+r13]
    mov edx,FILE_MAX+1
    sub rdx,r13
    syscall
    cmp rax,-4
    je .loop
    test rax,rax
    js fail
    jz .done
    add r13,rax
    cmp r13,FILE_MAX
    ja fail
    jmp .loop
.done:
    cmp r13,r12
    jne fail
    mov [member_len],r13
    mov eax,SYS_CLOSE
    mov rdi,rbx
    syscall
    test rax,rax
    js fail
    pop r13
    pop r12
    pop rbx
    ret

; rdi directory fd, rsi callback(name). Validate kernel record bounds.
walk_directory:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx,rdi
    mov r14,rsi
.read:
    mov eax,GETDENTS64
    mov rdi,rbx
    mov rsi,directory_buf
    mov edx,32768
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js fail
    jz .done
    mov r12,rax
    xor r13d,r13d
.entry:
    lea r8,[directory_buf+r13]
    lea rax,[r13+19]
    cmp rax,r12
    ja fail
    movzx r15d,word [r8+16]
    cmp r15,20
    jb fail
    lea rax,[r13+r15]
    cmp rax,r12
    ja fail
    lea rdi,[r8+19]
    mov rcx,r15
    sub rcx,19
    mov rdx,rdi
.nul:
    cmp byte [rdx],0
    je .callback
    inc rdx
    dec rcx
    jnz .nul
    jmp fail
.callback:
    call r14
    add r13,r15
    cmp r13,r12
    jb .entry
    jmp .read
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
is_task_name:
    cmp dword [rdi],'todo'
    jne .no
    cmp word [rdi+4],'s-'
    jne .no
    mov ecx,6
.loop:
    mov al,[rdi+rcx]
    cmp al,'0'
    jb .no
    cmp al,'9'
    jbe .next
    cmp al,'a'
    jb .no
    cmp al,'f'
    ja .no
.next:
    inc ecx
    cmp ecx,38
    jb .loop
    cmp dword [rdi+38],'.txt'
    jne .no
    cmp byte [rdi+42],0
    jne .no
    mov eax,1
    ret
.no:
    xor eax,eax
    ret
backup_file:
    push rbx
    call is_task_name
    test eax,eax
    jz .done
    mov rsi,rdi
    mov rdi,source_name
    mov ecx,43
    rep movsb
    mov eax,OPENAT
    mov rdi,[source_fd]
    mov rsi,source_name
    mov edx,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|2048 ; O_NONBLOCK prevents FIFO blocking
    xor r10d,r10d
    syscall
    test rax,rax
    js fail
    mov rdi,rax
    call read_data
    mov rdi,data_buf
    mov rsi,[member_len]
    mov rdx,digest
    call sha256
    call add_manifest
    mov rdi,source_name
    mov rsi,[member_len]
    call write_header
    mov rsi,data_buf
    mov rdx,[member_len]
    call archive_write
    mov rax,[member_len]
    call write_padding
.done:
    pop rbx
    ret

; Write fixed-width octal + NUL. rax=value, rdi=field, ecx=field bytes.
write_octal:
    dec ecx
    mov byte [rdi+rcx],0
.loop:
    dec ecx
    mov rdx,rax
    and edx,7
    add dl,'0'
    mov [rdi+rcx],dl
    shr rax,3
    test ecx,ecx
    jnz .loop
    test rax,rax
    jnz fail
    ret
write_header:
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
    mov rdi,header
    xor eax,eax
    mov ecx,512
    rep stosb
    mov rdi,header
    mov rsi,rbx
    call copy_z
    mov eax,0600o
    mov rdi,header+100
    mov ecx,8
    call write_octal
    xor eax,eax
    mov rdi,header+108
    mov ecx,8
    call write_octal
    xor eax,eax
    mov rdi,header+116
    mov ecx,8
    call write_octal
    mov rax,r12
    mov rdi,header+124
    mov ecx,12
    call write_octal
    mov rax,[now]
    mov rdi,header+136
    mov ecx,12
    call write_octal
    mov rax,0x2020202020202020
    mov [header+148],rax
    mov byte [header+156],'0'
    mov dword [header+257],'usta'
    mov word [header+261],'r'
    mov word [header+263],'00'
    xor eax,eax
    xor ecx,ecx
.checksum:
    movzx edx,byte [header+rcx]
    add eax,edx
    inc ecx
    cmp ecx,512
    jb .checksum
    mov rdi,header+148
    mov ecx,8
    call write_octal
    mov rsi,header
    mov edx,512
    call archive_write
    pop r12
    pop rbx
    ret
write_padding:
    neg rax
    and eax,511
    mov rdx,rax
    mov rsi,zeros
    jmp archive_write
reset_manifest:
    mov qword [manifest_len],0
    mov qword [record_count],0
    mov rdi,names_seen
    mov ecx,131072
    xor eax,eax
    rep stosq
    ret
encode_digest:
    xor ecx,ecx
.loop:
    movzx eax,byte [digest+rcx]
    mov edx,eax
    shr eax,4
    and edx,15
    mov al,[hex+rax]
    mov dl,[hex+rdx]
    mov [hash_text+rcx*2],al
    mov [hash_text+rcx*2+1],dl
    inc ecx
    cmp ecx,32
    jb .loop
    ret
add_manifest:
    push rbx
    push r12
    cmp qword [record_count],RECORD_MAX
    jae fail
    ; Open-addressed set catches duplicate member names in linear expected time.
    mov rax,14695981039346656037
    mov rdx,1099511628211
    xor ecx,ecx
.hash:
    movzx ebx,byte [source_name+rcx]
    xor rax,rbx
    imul rax,rdx
    inc ecx
    cmp ecx,42
    jb .hash
    mov r12,rax
.probe:
    and r12d,131071
    mov rax,[names_seen+r12*8]
    test rax,rax
    jz .insert
    dec rax
    imul rax,RECORD_LEN
    lea rdi,[computed+rax+66]
    mov rsi,source_name
    mov ecx,42
    repe cmpsb
    je fail
    inc r12
    jmp .probe
.insert:
    mov rax,[record_count]
    inc rax
    mov [names_seen+r12*8],rax
    call encode_digest
    mov rdi,computed
    add rdi,[manifest_len]
    mov rsi,hash_text
    mov ecx,64
    rep movsb
    mov word [rdi],'  '
    add rdi,2
    mov rsi,source_name
    mov ecx,42
    rep movsb
    mov byte [rdi],10
    add qword [manifest_len],RECORD_LEN
    inc qword [record_count]
    pop r12
    pop rbx
    ret

; Strict nonnegative octal field, decimal return; trailing NUL/space only.
read_octal:
    xor eax,eax
    xor r8d,r8d
.loop:
    movzx edx,byte [rdi]
    inc rdi
    test edx,edx
    jz .tail
    cmp edx,' '
    je .tail
    sub edx,'0'
    cmp edx,7
    ja fail
    shl rax,3
    add rax,rdx
    inc r8
    dec ecx
    jnz .loop
    jmp .end
.tail:
    dec ecx
    jz .end
.trailing:
    mov dl,[rdi]
    inc rdi
    test dl,dl
    jz .next
    cmp dl,' '
    jne fail
.next:
    dec ecx
    jnz .trailing
.end:
    test r8,r8
    jz fail
    ret
verify_archive:
    push rbx
    push r12
    mov eax,FSTAT
    mov rdi,[archive_fd]
    mov rsi,stat_buf
    syscall
    test rax,rax
    js fail
    mov eax,[stat_buf+24]
    and eax,0170000o
    cmp eax,0100000o
    jne fail
    cmp qword [stat_buf+16],1
    ja fail ; nlink=0 is valid when an atomic replacement unlinks our pinned inode
    call reset_manifest
.header:
    mov rdi,[archive_fd]
    mov rsi,header
    mov edx,512
    call read_exact
    ; File headers cannot be zero until the required manifest has been read.
    cmp byte [header],0
    je fail
    cmp dword [header+257],'usta'
    jne fail
    cmp word [header+261],'r'
    jne fail
    cmp word [header+263],'00'
    jne fail
    cmp byte [header+156],'0'
    jne fail
    mov rdi,header+148
    mov ecx,8
    call read_octal
    mov rbx,rax
    xor eax,eax
    xor ecx,ecx
.sum:
    movzx edx,byte [header+rcx]
    cmp ecx,148
    jb .sum_byte
    cmp ecx,156
    jae .sum_byte
    mov edx,32
.sum_byte:
    add eax,edx
    inc ecx
    cmp ecx,512
    jb .sum
    cmp rax,rbx
    jne fail
    mov rdi,header+100
    mov ecx,8
    call read_octal
    cmp rax,0600o
    jne fail
    mov rdi,header+108
    mov ecx,8
    call read_octal
    test rax,rax
    jnz fail
    mov rdi,header+116
    mov ecx,8
    call read_octal
    test rax,rax
    jnz fail
    ; Root-safe extraction: no link target, path prefix, extensions or padding names.
    mov rdi,header+157
    mov ecx,100
    xor eax,eax
    repe scasb
    jne fail
    mov rdi,header+345
    mov ecx,167
    repe scasb
    jne fail
    mov rdi,header+124
    mov ecx,12
    call read_octal
    mov r12,rax
    mov rdi,header
    mov rsi,manifest_name
    call strcmp
    test rax,rax
    jz .manifest
    mov rdi,header
    call is_task_name
    test eax,eax
    jz fail
    mov rdi,header+43
    mov ecx,57
    xor eax,eax
    repe scasb
    jne fail
    cmp r12,FILE_MAX
    ja fail
    mov rsi,header
    mov rdi,source_name
    mov ecx,43
    rep movsb
    mov rdi,[archive_fd]
    mov rsi,data_buf
    mov rdx,r12
    call read_exact
    mov rdi,data_buf
    mov rsi,r12
    mov rdx,digest
    call sha256
    call add_manifest
    mov rax,r12
    call verify_padding
    jmp .header
.manifest:
    mov rdi,header+11
    mov ecx,89
    xor eax,eax
    repe scasb
    jne fail
    cmp r12,[manifest_len]
    jne fail
    cmp r12,MANIFEST_MAX
    ja fail
    mov rdi,[archive_fd]
    mov rsi,expected
    mov rdx,r12
    call read_exact
    mov rdi,expected
    mov rsi,computed
    mov rcx,r12
    repe cmpsb
    jne fail
    mov rax,r12
    call verify_padding
    mov rdi,[archive_fd]
    mov rsi,header
    mov edx,512
    call read_exact
    mov rdi,header
    mov ecx,512
    xor eax,eax
    repe scasb
    jne fail
    mov rdi,[archive_fd]
    mov rsi,header
    mov edx,512
    call read_exact
    mov rdi,header
    mov ecx,512
    xor eax,eax
    repe scasb
    jne fail
.eof:
    xor eax,eax
    mov rdi,[archive_fd]
    mov rsi,header
    mov edx,1
    syscall
    cmp rax,-4
    je .eof
    test rax,rax
    jnz fail
    mov eax,SYS_CLOSE
    mov rdi,[archive_fd]
    syscall
    test rax,rax
    js fail
    pop r12
    pop rbx
    ret
verify_padding:
    neg rax
    and eax,511
    push rax
    mov rdi,[archive_fd]
    mov rsi,header
    mov rdx,rax
    call read_exact
    pop rcx
    mov rdi,header
    xor eax,eax
    test rcx,rcx
    jz .done
    repe scasb
    jne fail
.done:
    ret

; Only prune this utility's native .tar namespace, never legacy .tar.gz archives.
prune_file:
    push rbx
    mov rbx,rdi
    cmp dword [rdi],'asm-'
    jne .done
    cmp dword [rdi+4],'todo'
    jne .done
    cmp byte [rdi+8],'-'
    jne .done
    lea rsi,[rdi+9]
    xor ecx,ecx
.number:
    mov al,[rsi+rcx]
    cmp al,'-'
    je .number_end
    cmp al,'0'
    jb .done
    cmp al,'9'
    ja .done
    cmp ecx,19
    jae .done
    mov [number+rcx],al
    inc ecx
    jmp .number
.number_end:
    test ecx,ecx
    jz .done
    mov byte [number+rcx],0
    lea r8,[rsi+rcx+1]
    xor ecx,ecx
.random:
    mov al,[r8+rcx]
    cmp al,'0'
    jb .done
    cmp al,'9'
    jbe .digit
    cmp al,'a'
    jb .done
    cmp al,'f'
    ja .done
.digit:
    inc ecx
    cmp ecx,16
    jb .random
    cmp dword [r8+16],'.tar'
    jne .done
    cmp byte [r8+20],0
    jne .done
    mov rdi,number
    call parse_uint
    test rax,rax
    js .done
    cmp rax,[now]
    ja .done
    mov rdx,[now]
    sub rdx,rax
    cmp rdx,1209600 ; 14 days
    jbe .done
    ; No-follow/nonblocking regular-file check before unlinking only this entry.
    mov eax,OPENAT
    mov rdi,[output_fd]
    mov rsi,rbx
    mov edx,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|2048
    xor r10d,r10d
    syscall
    test rax,rax
    js .done
    push rax
    mov rdi,rax
    mov eax,FSTAT
    mov rsi,stat_buf
    syscall
    mov r9,rax
    pop rdi
    mov eax,SYS_CLOSE
    syscall
    test r9,r9
    js .done
    mov eax,[stat_buf+24]
    and eax,0170000o
    cmp eax,0100000o
    jne .done
    mov eax,UNLINKAT
    mov rdi,[output_fd]
    mov rsi,rbx
    xor edx,edx
    syscall
    test rax,rax
    js fail
.done:
    pop rbx
    ret
