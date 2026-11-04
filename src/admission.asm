%include "src/defs.inc"
DEFAULT ABS
extern current_uid, check_regular

global admission_open
section .data
    directory db 'data',0
    gate db 'data/.admission.lock',0
section .bss
    entries resb 32768
    identities resb WORKSPACE_MAX*32
    identity_count resq 1
    current_seen resq 1
    record_length resq 1
    result_fd resq 1
section .text
; Reserve a new workspace by creating its stable lock while holding one global
; admission mutex. Existing lock files take the storage fast path instead.
; Count unique IDs across exact data/lock/tmp names, including orphan reservations.
; rdi=lock path -> regular fd or -503. Never removes/expires existing state.
admission_open:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx,rdi
    mov qword [result_fd],-503
    mov qword [identity_count],0
    mov qword [current_seen],0
    mov eax,SYS_OPEN
    mov rdi,gate
    mov esi,O_RDWR|O_CREAT|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    mov edx,0600o
    syscall
    test rax,rax
    js .done
    mov r12,rax
    mov rdi,rax
    call check_regular
    test rax,rax
    js .close_gate
.retry:
    mov eax,SYS_FLOCK
    mov rdi,r12
    mov esi,LOCK_EX|4 ; no queue of new workspaces under overload
    syscall
    cmp rax,-4
    je .retry
    test rax,rax
    js .close_gate
    mov eax,SYS_OPEN
    mov rdi,directory
    mov esi,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js .close_gate
    mov r13,rax
.read:
    mov eax,217 ; getdents64
    mov rdi,r13
    mov rsi,entries
    mov edx,32768
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js .close_directory
    jz .admit
    mov r14,rax
    xor r15d,r15d
.entry:
    lea rdi,[entries+r15]
    movzx eax,word [rdi+16]
    cmp eax,20
    jb .close_directory
    mov [record_length],rax
    add rax,r15
    cmp rax,r14
    ja .close_directory
    mov rsi,[record_length]
    sub rsi,19
    add rdi,19
    call select_identity
    test rax,rax
    jz .next
    ; rax points to 32 validated hex identity bytes in the directory buffer.
    mov r9,rax
    mov rdi,rax
    mov rsi,current_uid
    mov ecx,32
    repe cmpsb
    jne .count
    mov qword [current_seen],1
.count:
    mov r10,[identity_count]
    cmp r10,WORKSPACE_MAX
    jae .next
    xor r8d,r8d
.find:
    cmp r8,r10
    jae .new
    mov rax,r8
    shl rax,5
    lea rdi,[identities+rax]
    mov rsi,r9
    mov ecx,32
    repe cmpsb
    je .next
    inc r8
    jmp .find
.new:
    mov rax,r10
    shl rax,5
    lea rdi,[identities+rax]
    mov rsi,r9
    mov ecx,32
    rep movsb
    inc qword [identity_count]
.next:
    add r15,[record_length]
    cmp r15,r14
    jb .entry
    jmp .read
.admit:
    cmp qword [current_seen],1
    je .create
    cmp qword [identity_count],WORKSPACE_MAX
    jae .close_directory
.create:
    mov eax,SYS_OPEN
    mov rdi,rbx
    mov esi,O_RDWR|O_CREAT|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    mov edx,0600o
    syscall
    test rax,rax
    js .close_directory
    mov r14,rax
    mov rdi,rax
    call check_regular
    test rax,rax
    js .close_result
    mov [result_fd],r14
    jmp .close_directory
.close_result:
    mov eax,SYS_CLOSE
    mov rdi,r14
    syscall
.close_directory:
    mov eax,SYS_CLOSE
    mov rdi,r13
    syscall
.close_gate:
    mov eax,SYS_CLOSE
    mov rdi,r12
    syscall
.done:
    mov rax,[result_fd]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Bounded exact todos-<32 lowercase hex>.txt[.lock|.tmp], return ID pointer/0.
select_identity:
    cmp rsi,43
    jb .no
    cmp dword [rdi],'todo'
    jne .no
    cmp word [rdi+4],'s-'
    jne .no
    cmp dword [rdi+38],'.txt'
    jne .no
    cmp byte [rdi+42],0
    je .hex
    cmp rsi,47
    jb .no
    cmp dword [rdi+42],'.tmp'
    jne .lock
    cmp byte [rdi+46],0
    jne .no
    jmp .hex
.lock:
    cmp rsi,48
    jb .no
    cmp dword [rdi+42],'.loc'
    jne .no
    cmp word [rdi+46],'k'
    jne .no
.hex:
    xor ecx,ecx
.character:
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
    inc ecx
    cmp ecx,32
    jb .character
    lea rax,[rdi+6]
    ret
.no:
    xor eax,eax
    ret
