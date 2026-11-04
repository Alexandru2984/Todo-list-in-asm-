%include "src/defs.inc"
DEFAULT ABS
extern current_uid, load_todos, lock_user_file, unlock_user_file
extern storage_version, save_legacy_snapshot, save_v3_snapshot

global downgrade_storage, downgrade_v3, check_storage
section .data
    directory db 'data',0
    write_mode dq 0
section .bss
    entries resb 32768
section .text
; Offline maintenance only. Two directory passes validate every source before
; rewriting any file. Caller must stop HTTP traffic and preserve a private copy.
; No contents or capability filenames are printed by the converter.
check_storage:
    xor edi,edi
    jmp maintenance_run
downgrade_storage:
    mov edi,1
    jmp maintenance_run
downgrade_v3:
    mov edi,2
maintenance_run:
    mov [write_mode],rdi
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov eax,SYS_OPEN
    mov rdi,directory
    mov esi,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js .bad
    mov r12,rax
    mov eax,SYS_FLOCK
    mov rdi,r12
    mov esi,LOCK_EX|4 ; LOCK_NB, exclude overlapping maintenance commands
    syscall
    test rax,rax
    js .close_bad
    xor r13d,r13d
.pass:
    mov eax,SYS_LSEEK
    mov rdi,r12
    xor esi,esi
    xor edx,edx
    syscall
    test rax,rax
    js .close_bad
.read:
    mov eax,217 ; getdents64, unavailable inside the HTTP service sandbox
    mov rdi,r12
    mov rsi,entries
    mov edx,32768
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js .close_bad
    jz .end_pass
    mov r14,rax
    xor ebx,ebx
.entry:
    lea r15,[entries+rbx]
    movzx eax,word [r15+16]
    cmp eax,20
    jb .close_bad
    add rax,rbx
    cmp rax,r14
    ja .close_bad
    lea rdi,[r15+19]
    call select_uid
    test rax,rax
    jz .next
    call lock_user_file
    test rax,rax
    js .close_bad
    call load_todos
    test rax,rax
    js .unlock_bad
    test r13,r13
    jz .unlock
    cmp qword [write_mode],2
    jne .legacy
    cmp qword [storage_version],4
    jb .unlock
    call save_v3_snapshot
    jmp .saved
.legacy:
    cmp qword [storage_version],2
    jb .unlock
    call save_legacy_snapshot
.saved:
    test rax,rax
    js .unlock_bad
.unlock:
    call unlock_user_file
.next:
    movzx eax,word [r15+16]
    add rbx,rax
    cmp rbx,r14
    jb .entry
    jmp .read
.end_pass:
    cmp qword [write_mode],0
    je .success
    inc r13
    cmp r13,2
    jb .pass
.success:
    mov eax,SYS_CLOSE
    mov rdi,r12
    syscall
    xor eax,eax
    jmp .done
.unlock_bad:
    call unlock_user_file
.close_bad:
    mov eax,SYS_CLOSE
    mov rdi,r12
    syscall
.bad:
    mov rax,-1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Exact capability filename, bounded by d_reclen. Never follow an arbitrary name.
select_uid:
    movzx eax,word [r15+16]
    cmp eax,19+43
    jb .no
    cmp dword [rdi],'todo'
    jne .no
    cmp word [rdi+4],'s-'
    jne .no
    cmp dword [rdi+38],'.txt'
    jne .no
    cmp byte [rdi+42],0
    jne .no
    xor ecx,ecx
.hex:
    mov al,[rdi+6+rcx]
    cmp al,'0'
    jb .no
    cmp al,'9'
    jbe .valid
    cmp al,'a'
    jb .no
    cmp al,'f'
    ja .no
.valid:
    mov [current_uid+rcx],al
    inc ecx
    cmp ecx,32
    jb .hex
    mov byte [current_uid+32],0
    mov eax,1
    ret
.no:
    xor eax,eax
    ret
