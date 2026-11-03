%include "src/defs.inc"
DEFAULT ABS
extern find_todo, history_prepare, save_snapshot

global change_stage
section .text
; rdi=id, rsi=0 todo / 1 doing. Reopen done tasks explicitly first.
change_stage:
    push rbx
    push r12
    mov r12,rsi
    cmp r12,1
    ja .bad
    call find_todo
    test rax,rax
    jz .missing
    mov rbx,rax
    cmp byte [rbx+8],0
    jne .conflict
    cmp [rbx+T_STAGE],r12
    je .unchanged
    mov edi,10
    mov rsi,[rbx]
    call history_prepare
    mov [rbx+T_STAGE],r12
    call save_snapshot
    jmp .done
.bad:
    mov rax,-400
    jmp .done
.missing:
    mov rax,-404
    jmp .done
.conflict:
    mov rax,-409
    jmp .done
.unchanged:
    xor eax,eax
.done:
    pop r12
    pop rbx
    ret
