%include "src/defs.inc"
DEFAULT ABS
extern parse_uint, split_field, find_todo, find_any_todo, validate_metadata_graph
extern copy_string, emit_number

global parse_dependencies, task_ready, validate_relation_change
 global render_relation_fields, render_relation_badges
section .data
    parent_open db '<label>Parent task ID (0 for none)<input type="number" name="parent" min="0" max="9223372036854775806" value="',0
    deps_open db '<label>Prerequisite IDs (comma separated)<input name="deps" maxlength="167" value="',0
    external_form db ' form="add-form"',0
    field_close db '></label>',0
    reference_open db '<span class="task-reference">Task #',0
    parent_badge db '<span class="task-reference">Subtask of #',0
    deps_badge db '<span class="task-reference">Needs #',0
    blocked db '<span class="blocked-badge">Waiting for prerequisites or subtasks</span>',0
    span_close db '</span>',0
section .text
parse_dependencies:
    push rbx
    push r12
    push r13
    push r14
    mov rbx,rdi
    mov r12,rsi
    xor r13d,r13d
    mov qword [r12+T_DEP_COUNT],0
    cmp byte [rbx],0
    je .ok
.token:
    cmp r13,DEP_MAX
    jae .bad
    mov rdi,rbx
    mov dl,','
    call split_field
    mov r14,rax
.leading:
    cmp byte [rbx],' '
    jne .length
    inc rbx
    jmp .leading
.length:
    mov rdi,rbx
.end:
    cmp byte [rdi],0
    je .trim
    inc rdi
    jmp .end
.trim:
    cmp rdi,rbx
    je .bad
    cmp byte [rdi-1],' '
    jne .number
    dec rdi
    mov byte [rdi],0
    jmp .trim
.number:
    mov rdi,rbx
    call parse_uint
    test rax,rax
    jle .bad
    xor ecx,ecx
.unique:
    cmp rcx,r13
    jae .store
    cmp [r12+T_DEPS+rcx*8],rax
    je .bad
    inc ecx
    jmp .unique
.store:
    mov [r12+T_DEPS+r13*8],rax
    inc r13
    test r14,r14
    jz .ok
    mov rbx,r14
    jmp .token
.ok:
    mov [r12+T_DEP_COUNT],r13
    xor eax,eax
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; True iff all prerequisites are done and all live children are done.
task_ready:
    push rbx
    push r12
    mov rbx,rdi
    xor r12d,r12d
.dep:
    cmp r12,[rbx+T_DEP_COUNT]
    jae .children
    mov rdi,[rbx+T_DEPS+r12*8]
    call find_any_todo
    test rax,rax
    jz .blocked
    cmp byte [rax+8],1
    jne .blocked
    inc r12
    jmp .dep
.children:
    xor edi,edi
    call find_any_todo
    mov rdi,rax
    mov ecx,SLOT_MAX
.child:
    cmp qword [rdi],0
    je .next
    cmp byte [rdi+8],0
    jne .next
    mov rax,[rbx]
    cmp [rdi+T_PARENT],rax
    je .blocked
.next:
    add rdi,TASK_SIZE
    dec ecx
    jnz .child
    mov eax,1
    jmp .done
.blocked:
    xor eax,eax
.done:
    pop r12
    pop rbx
    ret

; New references must resolve to live tasks. Persisted dependencies on trashed
; tasks remain valid and block completion until restored or detached by purge.
validate_relation_change:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    mov r13,rsi
    test r13,32
    jz .deps
    mov rdi,[rbx+T_PARENT]
    test rdi,rdi
    jz .deps
    call find_todo
    test rax,rax
    jz .bad
    cmp byte [rax+8],1
    jne .deps
    cmp byte [rbx+8],0
    je .conflict ; reopen a completed parent before adding active children
.deps:
    test r13,64
    jz .graph
    xor r12d,r12d
.dep:
    cmp r12,[rbx+T_DEP_COUNT]
    jae .graph
    mov rdi,[rbx+T_DEPS+r12*8]
    call find_todo
    test rax,rax
    jz .bad
    inc r12
    jmp .dep
.graph:
    xor edi,edi
    call find_any_todo
    mov rdi,rax
    call validate_metadata_graph
    test rax,rax
    js .bad
    cmp byte [rbx+8],1
    jne .ok
    mov rdi,rbx
    call task_ready
    test rax,rax
    jz .conflict
.ok:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-400
    jmp .done
.conflict:
    mov rax,-409
.done:
    pop r13
    pop r12
    pop rbx
    ret

render_relation_fields:
    push rbx
    push r12
    push r13
    mov rbx,rsi
    mov r12,rdx
    mov rsi,parent_open
    call copy_string
    mov rax,[rbx+T_PARENT]
    call emit_number
    call .close
    mov rsi,deps_open
    call copy_string
    xor r13d,r13d
.dep:
    cmp r13,[rbx+T_DEP_COUNT]
    jae .deps_end
    test r13,r13
    jz .number
    mov byte [rdi],','
    inc rdi
.number:
    mov rax,[rbx+T_DEPS+r13*8]
    call emit_number
    inc r13
    jmp .dep
.deps_end:
    call .close
    pop r13
    pop r12
    pop rbx
    ret
.close:
    mov byte [rdi],'"'
    inc rdi
    test r12,r12
    jz .close_field
    mov rsi,external_form
    call copy_string
.close_field:
    mov rsi,field_close
    jmp copy_string

render_relation_badges:
    push rbx
    push r12
    mov rbx,rsi
    mov rsi,reference_open
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,span_close
    call copy_string
    cmp qword [rbx+T_PARENT],0
    je .deps
    mov rsi,parent_badge
    call copy_string
    mov rax,[rbx+T_PARENT]
    call emit_number
    mov rsi,span_close
    call copy_string
.deps:
    cmp qword [rbx+T_DEP_COUNT],0
    je .ready
    mov rsi,deps_badge
    call copy_string
    xor r12d,r12d
.dep:
    test r12,r12
    jz .number
    mov word [rdi],', '
    add rdi,2
.number:
    mov rax,[rbx+T_DEPS+r12*8]
    call emit_number
    inc r12
    cmp r12,[rbx+T_DEP_COUNT]
    jb .dep
    mov rsi,span_close
    call copy_string
.ready:
    cmp byte [rbx+8],0
    jne .done
    push rdi
    mov rdi,rbx
    call task_ready
    pop rdi
    test rax,rax
    jnz .done
    mov rsi,blocked
    call copy_string
.done:
    pop r12
    pop rbx
    ret
