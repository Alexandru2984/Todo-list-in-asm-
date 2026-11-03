%include "src/defs.inc"
DEFAULT ABS
extern strcmp, check_regular

global is_import_path, import_acquire
section .data
    preview_path db '/import-preview',0
    apply_path db '/import',0
    gate_path db 'data/.import.lock',0
    gate_fd dq -1
section .text
is_import_path:
    push rdi
    mov rsi,preview_path
    call strcmp
    pop rdi
    test rax,rax
    jz .yes
    mov rsi,apply_path
    call strcmp
    test rax,rax
    jz .yes
    xor eax,eax
    ret
.yes:
    mov eax,1
    ret

; One global import child may receive a large body. Acquired after validated
; headers/auth/origin and before lifting the ordinary 4 KiB receive cap.
; Kernel closes the private descriptor when this request's fork exits.
import_acquire:
    cmp qword [gate_fd],0
    jl .open
    xor eax,eax
    ret
.open:
    push rbx
    mov eax,SYS_OPEN
    mov rdi,gate_path
    mov esi,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK
    mov edx,0600o
    syscall
    test rax,rax
    js .bad
    mov rbx,rax
    mov rdi,rbx
    call check_regular
    test rax,rax
    js .close_bad
.lock:
    mov eax,SYS_FLOCK
    mov rdi,rbx
    mov esi,LOCK_EX|4 ; LOCK_NB: no queue of body-sized workers
    syscall
    cmp rax,-4
    je .lock
    test rax,rax
    js .close_bad
    mov [gate_fd],rbx
    xor eax,eax
    jmp .done
.close_bad:
    mov eax,SYS_CLOSE
    mov rdi,rbx
    syscall
.bad:
    mov rax,-503
.done:
    pop rbx
    ret
