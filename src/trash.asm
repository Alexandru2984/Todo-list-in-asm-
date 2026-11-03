%include "src/defs.inc"
DEFAULT ABS
extern todos, todo_count, find_any_todo, save_snapshot
extern history_prepare, history_clear_undo, history_event

global restore_todo, purge_todo, empty_trash
section .text
; Mark exactly the trashed subtree. Scratch colors are never serialized.
mark_subtree:
    push rbx
    push r12
    push r13
    push r14
    mov rbx,rdi
    mov rdi,todos
    mov ecx,SLOT_MAX
.clear:
    mov byte [rdi+T_COLOR],0
    add rdi,TASK_SIZE
    loop .clear
    mov byte [rbx+T_COLOR],1
    mov r12d,1
.again:
    xor r14d,r14d
    mov rbx,todos
    mov r13d,SLOT_MAX
.scan:
    cmp qword [rbx],0
    je .next
    cmp byte [rbx+8],2
    jne .next
    cmp byte [rbx+T_COLOR],1
    je .next
    mov rdi,[rbx+T_PARENT]
    test rdi,rdi
    jz .next
    call find_any_todo
    test rax,rax
    jz .next
    cmp byte [rax+T_COLOR],1
    jne .next
    mov byte [rbx+T_COLOR],1
    inc r12
    inc r14
.next:
    add rbx,TASK_SIZE
    dec r13
    jnz .scan
    test r14,r14
    jnz .again
    mov rax,r12
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

restore_todo:
    push rbx
    push r12
    call find_any_todo
    test rax,rax
    jz .missing
    cmp byte [rax+8],2
    jne .missing
    mov rbx,rax
    mov rdi,rax
    call mark_subtree
    add rax,[todo_count]
    cmp rax,TASK_MAX
    ja .conflict
    xor r12d,r12d ; detach root if its parent is still in trash
    mov rdi,[rbx+T_PARENT]
    test rdi,rdi
    jz .prepare
    call find_any_todo
    test rax,rax
    jz .detach
    cmp byte [rax+8],2
    je .detach
    cmp byte [rax+8],1
    jne .prepare
    cmp qword [rbx+T_PREVIOUS],0
    je .conflict
    jmp .prepare
.detach:
    mov r12d,1
.prepare:
    mov edi,7
    mov rsi,[rbx]
    call history_prepare
    test r12,r12
    jz .restore
    mov qword [rbx+T_PARENT],0
.restore:
    mov rdi,todos
    mov ecx,SLOT_MAX
.scan:
    cmp byte [rdi+T_COLOR],1
    jne .next
    mov rax,[rdi+T_PREVIOUS]
    mov [rdi+8],al
    mov qword [rdi+T_DELETED],0
    mov qword [rdi+T_PREVIOUS],0
.next:
    add rdi,TASK_SIZE
    loop .scan
    call save_snapshot
    jmp .done
.missing:
    mov rax,-404
    jmp .done
.conflict:
    mov rax,-409
.done:
    pop r12
    pop rbx
    ret

; Remove references to an ID before the slot disappears. No calls/clobber of
; callee-saved registers, allowing bounded bulk purge to reuse this helper.
detach_references:
    mov r8,todos
    mov ecx,SLOT_MAX
.task:
    cmp [r8+T_PARENT],rdi
    jne .deps
    mov qword [r8+T_PARENT],0
.deps:
    xor r9d,r9d
    xor r10d,r10d
.dep:
    cmp r9,[r8+T_DEP_COUNT]
    jae .dep_end
    mov rax,[r8+T_DEPS+r9*8]
    inc r9
    cmp rax,rdi
    je .dep
    mov [r8+T_DEPS+r10*8],rax
    inc r10
    jmp .dep
.dep_end:
    mov [r8+T_DEP_COUNT],r10
    add r8,TASK_SIZE
    loop .task
    ret

purge_todo:
    call find_any_todo
    test rax,rax
    jz .missing
    cmp byte [rax+8],2
    jne .missing
    push rbx
    push r12
    mov r12,[rax]
    mov rdi,rax
    call mark_subtree
    jmp purge_marked
.missing:
    mov rax,-404
    ret
empty_trash:
    push rbx
    push r12
    xor r12d,r12d
    mov rdi,todos
    mov ecx,SLOT_MAX
.mark:
    cmp byte [rdi+8],2
    sete byte [rdi+T_COLOR]
    add rdi,TASK_SIZE
    loop .mark
purge_marked:
    call history_clear_undo
    mov rbx,todos
.purge:
    cmp byte [rbx+T_COLOR],1
    jne .next
    mov rdi,[rbx]
    call detach_references
    mov rdi,rbx
    xor eax,eax
    mov ecx,TASK_SIZE/8
    rep stosq
.next:
    add rbx,TASK_SIZE
    cmp rbx,todos+SLOT_MAX*TASK_SIZE
    jb .purge
    mov edi,8
    mov rsi,r12
    call history_event
    call save_snapshot
    pop r12
    pop rbx
    ret
