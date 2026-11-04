%include "src/defs.inc"
DEFAULT ABS
extern sha256, strlen, copy_string, parse_uint, itoa, write_all, check_regular
extern current_uid, session_key, session_key_length, request_method, storage_version
extern save_snapshot, history_event, guard_required, guard_restore_floor

global auth_storage_reset, auth_parse, auth_validate, auth_write
 global auth_probe, auth_read_at, auth_candidate, auth_rotate, auth_required
 global auth_merge_policy
global owner_hash, owner_epoch, probe_hash, probe_epoch, probe_revision
section .data
    prefix db 'data/todos-',0
    key_prefix db '#key=',0
    epoch_prefix db '#keyepoch=',0
    revision_prefix db '#revision=',0
    v5 db '#asm=5',10
    hex db '0123456789abcdef'
    material db 'ASM TODO active key v1',0
    key_material times 65 db 0
    material_prefix_len equ key_material-material
section .bss
    owner_hash resb 65
    owner_epoch resq 1
    owner_stage resq 1
    digest resb 32
    computed resb 65
    probe_hash resb 65
    probe_epoch resq 1
    probe_revision resq 1
    merge_name resb 43
    probe_path resb 64
    header resb 257
    header_size resq 1
    random resb 16
    record resb 128
section .text
hex64:
    xor ecx,ecx
.loop:
    mov al,[rdi+rcx]
    cmp al,'0'
    jb .bad
    cmp al,'9'
    jbe .next
    cmp al,'a'
    jb .bad
    cmp al,'f'
    ja .bad
.next:
    inc ecx
    cmp ecx,64
    jb .loop
    cmp byte [rdi+64],0
    jne .bad
    xor eax,eax
    ret
.bad:
    mov rax,-500
    ret

; Domain-separated hash of the exact presented credential. Never persist raw keys.
hash_key:
    mov rsi,rdi
    mov rdi,key_material
    xor ecx,ecx
.copy:
    mov al,[rsi+rcx]
    mov [rdi+rcx],al
    test al,al
    jz .hash
    inc ecx
    cmp ecx,64
    jbe .copy
    mov rax,-400
    ret
.hash:
    lea rsi,[rcx+material_prefix_len]
    mov rdi,material
    mov rdx,digest
    call sha256
    mov rdi,computed
    xor ecx,ecx
.encode:
    movzx eax,byte [digest+rcx]
    mov edx,eax
    shr eax,4
    mov al,[hex+rax]
    stosb
    mov eax,edx
    and eax,15
    mov al,[hex+rax]
    stosb
    inc ecx
    cmp ecx,32
    jb .encode
    mov byte [rdi],0
    xor eax,eax
    ret

; Compare exactly 64 ASCII hash bytes without a data-dependent early exit.
compare_hash:
    xor eax,eax
    xor ecx,ecx
.loop:
    mov dl,[rdi+rcx]
    xor dl,[rsi+rcx]
    or al,dl
    inc ecx
    cmp ecx,64
    jb .loop
    test al,al
    jnz .revoked
    xor eax,eax
    ret
.revoked:
    mov rax,-410
    ret

auth_storage_reset:
    mov qword [owner_epoch],0
    mov qword [owner_stage],0
    mov byte [owner_hash],0
    ret

; V5 headers are canonical: #next, #key, #keyepoch, then V4 guards/history.
auth_parse:
    push rbx
    mov rbx,rdi
    cmp dword [rdi],'#key'
    jne .other
    cmp byte [rdi+4],'='
    jne .epoch
    cmp qword [owner_stage],0
    jne .bad
    add rdi,5
    call hex64
    test rax,rax
    js .bad
    mov rsi,rdi
    mov rdi,owner_hash
    mov ecx,65
    rep movsb
    mov qword [owner_stage],1
    jmp .known
.epoch:
    mov rsi,epoch_prefix
    mov ecx,10
    repe cmpsb
    jne .bad
    cmp qword [owner_stage],1
    jne .bad
    push rdi
    call strlen
    pop rdi
    cmp rax,19
    ja .bad
    call parse_uint
    test rax,rax
    jle .bad
    mov [owner_epoch],rax
    mov qword [owner_stage],2
.known:
    mov eax,1
    jmp .done
.other:
    cmp qword [owner_stage],2
    je .unknown
    cmp qword [owner_stage],0
    jne .bad
    cmp dword [rbx],'#nex'
    jne .bad
.unknown:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop rbx
    ret

auth_validate:
    cmp qword [storage_version],5
    jb .legacy
    cmp qword [owner_stage],2
    jne .bad
    cmp qword [request_method],0
    je .ok ; offline preflight/conversion has no browser credential
    mov rdi,session_key
    call hash_key
    mov rdi,computed
    mov rsi,owner_hash
    jmp compare_hash
.legacy:
    cmp qword [request_method],0
    je .ok
    cmp qword [session_key_length],64
    je .revoked ; prepared modern key is inactive until V5 commit
.ok:
    xor eax,eax
    ret
.revoked:
    mov rax,-410
    ret
.bad:
    mov rax,-500
    ret

auth_write:
    push r12
    mov r12,rdi
    mov rdi,record
    mov rsi,key_prefix
    call copy_string
    mov rsi,owner_hash
    call copy_string
    mov byte [rdi],10
    lea rdx,[rdi+1]
    sub rdx,record
    mov rdi,r12
    mov rsi,record
    call write_all
    test rax,rax
    js .done
    mov rdi,record
    mov rsi,epoch_prefix
    call copy_string
    mov rsi,rdi
    mov rdi,[owner_epoch]
    call itoa
    add rsi,rax
    mov byte [rsi],10
    lea rdx,[rsi+1]
    sub rdx,record
    mov rdi,r12
    mov rsi,record
    call write_all
.done:
    pop r12
    ret

; Complete bounded header line -> NUL, next line pointer or zero.
next_line:
    mov rax,rdi
.loop:
    mov rdx,rax
    sub rdx,header
    cmp rdx,[header_size]
    jae .bad
    cmp byte [rax],10
    je .found
    cmp byte [rax],0
    je .bad
    inc rax
    jmp .loop
.found:
    mov byte [rax],0
    inc rax
    ret
.bad:
    xor eax,eax
    ret

; Read regular file's canonical policy header without changing loaded task state.
; fd=rdi, caller closes. Returns 5 V5, 0 legacy, -500 malformed/unsafe.
auth_read_at:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    mov qword [probe_epoch],0
    mov qword [probe_revision],0
    call check_regular
    test rax,rax
    js .bad
    xor r12d,r12d
.read:
    mov eax,SYS_READ
    mov rdi,rbx
    lea rsi,[header+r12]
    mov edx,256
    sub rdx,r12
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js .bad
    jz .parsed
    add r12,rax
    cmp r12,256
    jb .read
.parsed:
    mov [header_size],r12
    mov byte [header+r12],0
    cmp r12,7
    jb .legacy
    mov rdi,header
    mov rsi,v5
    mov ecx,7
    repe cmpsb
    jne .legacy
    mov rdi,header+7
    call next_line
    test rax,rax
    jz .bad
    mov r12,rax
    sub rax,header+7
    cmp rax,26
    ja .bad
    mov rdi,header+7
    cmp dword [rdi],'#nex'
    jne .bad
    cmp word [rdi+4],'t='
    jne .bad
    add rdi,6
    call parse_uint
    test rax,rax
    jle .bad
    mov rdi,r12
    call next_line
    test rax,rax
    jz .bad
    mov r13,rax
    mov rdi,r12
    cmp dword [rdi],'#key'
    jne .bad
    cmp byte [rdi+4],'='
    jne .bad
    add rdi,5
    call hex64
    test rax,rax
    js .bad
    mov rsi,rdi
    mov rdi,probe_hash
    mov ecx,65
    rep movsb
    mov rdi,r13
    call next_line
    test rax,rax
    jz .bad
    mov r12,rax
    mov rdi,r13
    mov rsi,epoch_prefix
    mov ecx,10
    repe cmpsb
    jne .bad
    push rdi
    call strlen
    pop rdi
    cmp rax,19
    ja .bad
    call parse_uint
    test rax,rax
    jle .bad
    mov [probe_epoch],rax
    mov rdi,r12
    call next_line
    test rax,rax
    jz .bad
    mov rdi,r12
    mov rsi,revision_prefix
    mov ecx,10
    repe cmpsb
    jne .bad
    push rdi
    call strlen
    pop rdi
    cmp rax,19
    ja .bad
    call parse_uint
    test rax,rax
    jle .bad
    mov [probe_revision],rax
    mov eax,5
    jmp .done
.legacy:
    cmp dword [header],'#asm'
    jne .scan_legacy
    cmp qword [header_size],7
    jb .bad
    cmp byte [header+4],'='
    jne .bad
    cmp byte [header+5],'2'
    jb .bad
    cmp byte [header+5],'4'
    ja .bad
    cmp byte [header+6],10
    jne .bad
.scan_legacy:
    xor ecx,ecx
.legacy_line:
    lea rax,[rcx+4]
    cmp rax,[header_size]
    ja .legacy_ok
    test rcx,rcx
    jz .legacy_prefix
    cmp byte [header+rcx-1],10
    jne .legacy_next
.legacy_prefix:
    cmp dword [header+rcx],'#key'
    je .bad
.legacy_next:
    inc rcx
    jmp .legacy_line
.legacy_ok:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Header-only check for restore/recovery/session responses and import body gate.
auth_probe:
    push rbx
    mov rdi,probe_path
    mov rsi,prefix
    mov ecx,11
    rep movsb
    mov rsi,current_uid
    mov ecx,32
    rep movsb
    mov dword [rdi],'.txt'
    mov byte [rdi+4],0
    mov eax,SYS_OPEN
    mov rdi,probe_path
    mov esi,O_RDONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK
    xor edx,edx
    syscall
    cmp rax,-2
    je .legacy
    test rax,rax
    js .bad
    mov rbx,rax
    mov rdi,rax
    call auth_read_at
    push rax
    mov eax,SYS_CLOSE
    mov rdi,rbx
    syscall
    pop rax
    test rax,rax
    js .done
    jz .legacy
    mov rdi,session_key
    call hash_key
    mov rdi,computed
    mov rsi,probe_hash
    call compare_hash
    jmp .done
.legacy:
    cmp qword [session_key_length],32
    jne .revoked
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
    jmp .done
.revoked:
    mov rax,-410
.done:
    pop rbx
    ret

auth_candidate:
    push rbx
    push r12
    mov r12,rdi
    mov rsi,current_uid
    mov ecx,32
    rep movsb
    xor ebx,ebx
.random:
    mov eax,SYS_GETRANDOM
    lea rdi,[random+rbx]
    mov esi,16
    sub rsi,rbx
    xor edx,edx
    syscall
    cmp rax,-4
    je .random
    test rax,rax
    jle .bad
    add rbx,rax
    cmp rbx,16
    jb .random
    lea rdi,[r12+32]
    xor ecx,ecx
.hex:
    movzx eax,byte [random+rcx]
    mov edx,eax
    shr eax,4
    mov al,[hex+rax]
    stosb
    mov eax,edx
    and eax,15
    mov al,[hex+rax]
    stosb
    inc ecx
    cmp ecx,16
    jb .hex
    mov byte [rdi],0
    xor eax,eax
    jmp .done
.bad:
    mov rax,-503
.done:
    pop r12
    pop rbx
    ret

auth_required:
    jmp guard_required

; Caller owns canonical workspace lock and has just loaded/authenticated it.
auth_rotate:
    push rbx
    mov rbx,rdi
    mov rax,9223372036854775807
    cmp [owner_epoch],rax
    jae .full
    call hash_key
    test rax,rax
    js .done
    mov rdi,owner_hash
    mov rsi,computed
    mov ecx,65
    rep movsb
    inc qword [owner_epoch]
    mov qword [owner_stage],2
    mov qword [storage_version],5
    mov edi,13
    xor esi,esi
    call history_event
    call save_snapshot
    jmp .done
.full:
    mov rax,-507
.done:
    pop rbx
    ret

; Offline restore only. rdi=retained-current data directory fd. The current
; target is already loaded under its lock. Higher key epoch wins; equal epoch
; with different fingerprints is an ambiguous branch and fails closed.
auth_merge_policy:
    push rbx
    push r12
    mov r12,rdi
    mov rdi,merge_name
    mov dword [rdi],'todo'
    mov word [rdi+4],'s-'
    add rdi,6
    mov rsi,current_uid
    mov ecx,32
    rep movsb
    mov dword [rdi],'.txt'
    mov byte [rdi+4],0
    mov eax,257 ; openat, offline command is outside HTTP syscall sandbox
    mov rdi,r12
    mov rsi,merge_name
    mov edx,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    xor r10d,r10d
    syscall
    test rax,rax
    js .bad
    mov rbx,rax
    mov rdi,rax
    call auth_read_at
    push rax
    mov eax,SYS_CLOSE
    mov rdi,rbx
    syscall
    pop rax
    test rax,rax
    js .bad
    mov rax,[probe_epoch]
    cmp rax,[owner_epoch]
    ja .newer
    jb .policy
    test rax,rax
    jz .legacy
    mov rdi,probe_hash
    mov rsi,owner_hash
    call compare_hash
    test rax,rax
    js .bad
    jmp .policy
.newer:
    mov [owner_epoch],rax
    mov rdi,owner_hash
    mov rsi,probe_hash
    mov ecx,65
    rep movsb
.policy:
    cmp qword [owner_epoch],0
    je .legacy
    mov qword [owner_stage],2
    mov qword [storage_version],5
    mov rdi,[probe_revision]
    call guard_restore_floor
    test rax,rax
    js .bad
    mov eax,1 ; refresh generation/receipts and revision even for same policy
    jmp .done
.legacy:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r12
    pop rbx
    ret
