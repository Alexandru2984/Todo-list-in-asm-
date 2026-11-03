%include "src/defs.inc"
%include "src/import.inc"
DEFAULT ABS
extern todos, lookup_array, todo_count, next_id, save_snapshot
extern parse_uint, strlen, strcmp, unicode_compare, parse_date, valid_utf8
extern copy_metadata_text, normalize_tags, parse_dependencies, recurrence_anchor
extern priority_names, recurrence_names, format_metadata, parse_metadata
extern validate_metadata_graph, history_prepare

global import_tasks, import_count, import_live, import_trash, import_reset
 global import_set_text, import_validate_task, import_validate, import_apply
 global import_capacity
global import_parse_timestamp
section .data
    lit_true db 'true',0
    lit_false db 'false',0
    todo db 'todo',0
    doing db 'doing',0
    done db 'done',0
    stages dq todo,doing,done
    setters dq set_id,set_title,set_completed,set_created,set_priority,set_due
            dq set_completed_at,set_project,set_tags,set_parent,set_deps,set_repeat
            dq set_anchor,set_stage,set_deleted,set_previous,set_escape,set_workflow
section .bss
    import_tasks resb SLOT_MAX*TASK_SIZE
    import_count resq 1
    import_live resq 1
    import_trash resq 1
    date_buf resb 16
    tags_buf resb TAGS_MAX+1
    meta_buf resb 1024
section .text
import_reset:
    mov rdi,import_tasks
    xor eax,eax
    mov ecx,SLOT_MAX*TASK_SIZE/8
    rep stosq
    mov qword [import_count],0
    mov qword [import_live],0
    mov qword [import_trash],0
    mov qword [lookup_array],import_tasks
    ret

; rdi=slot, esi=field number, rdx=decoded validated text. No silent truncation.
import_set_text:
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rdx
    cmp rsi,18
    jae .bad
    call [setters+rsi*8]
    test rax,rax
    jns .done
.bad:
    mov rax,-422
.done:
    pop r12
    pop rbx
    ret
set_id:
    mov rdi,r12
    call parse_uint
    test rax,rax
    jle field_bad
    mov rdx,9223372036854775807
    cmp rax,rdx
    je field_bad
    mov [rbx],rax
    jmp field_ok
set_title:
    mov rdi,r12
    call strlen
    test rax,rax
    jz field_bad
    mov rdi,r12
.space:
    cmp byte [rdi],' '
    jne .text
    inc rdi
    jmp .space
.text:
    cmp byte [rdi],0
    je field_bad
    mov rdi,r12
    lea rsi,[rbx+17]
    mov edx,TITLE_MAX
    jmp copy_metadata_text
set_completed:
    call parse_bool
    test rax,rax
    js field_bad
    mov [rbx+8],al
    jmp field_ok
set_previous:
    xor eax,eax
    cmp byte [r12],0
    je .store
    call parse_bool
    test rax,rax
    js field_bad
 .store:
    mov [rbx+T_PREVIOUS],rax
    jmp field_ok
parse_bool:
    mov rdi,r12
    mov rsi,lit_true
    call unicode_compare
    test rax,rax
    jz .true
    mov rdi,r12
    mov rsi,lit_false
    call unicode_compare
    test rax,rax
    jnz field_bad
    xor eax,eax
    ret
.true:
    mov eax,1
    ret
set_created:
    mov rax,9223372036854775807 ; unknown creation time, exported as null
    cmp byte [r12],0
    je .store
    mov rdi,r12
    call import_parse_timestamp
    test rax,rax
    js field_bad
.store:
    mov [rbx+9],rax
    jmp field_ok
set_due:
    xor eax,eax
    cmp byte [r12],0
    je .store
    mov rdi,r12
    call parse_date
    test rax,rax
    jle field_bad
.store:
    mov [rbx+T_DUE],rax
    jmp field_ok
set_completed_at:
    call optional_time
    test rax,rax
    js field_bad
    mov [rbx+T_COMPLETED],rax
    jmp field_ok
set_deleted:
    call optional_time
    test rax,rax
    js field_bad
    mov [rbx+T_DELETED],rax
    jmp field_ok
optional_time:
    xor eax,eax
    cmp byte [r12],0
    je .done
    mov rdi,r12
    call import_parse_timestamp
    test rax,rax
    jle field_bad
.done:
    ret
set_project:
    mov rdi,r12
    lea rsi,[rbx+T_PROJECT]
    mov edx,PROJECT_MAX
    jmp copy_metadata_text
set_tags:
    mov rdi,r12
    lea rsi,[rbx+T_TAGS]
    mov edx,TAGS_MAX
    jmp copy_metadata_text
set_parent:
    xor eax,eax
    cmp byte [r12],0
    je .store
    mov rdi,r12
    call parse_uint
    test rax,rax
    js field_bad
.store:
    mov [rbx+T_PARENT],rax
    jmp field_ok
set_deps:
    mov rdi,r12
    mov rsi,rbx
    jmp parse_dependencies
set_anchor:
    cmp byte [r12],0
    jne .value
    and qword [rbx+I_FIELDS],~(1<<12)
    jmp field_ok
.value:
    mov rdi,r12
    call parse_uint
    test rax,rax
    js field_bad
    mov [rbx+T_ANCHOR],rax
    jmp field_ok
set_escape:
    xor eax,eax
    cmp byte [r12],0
    je .store
    mov rdi,r12
    call parse_uint
    cmp rax,7
    ja field_bad
.store:
    mov [rbx+I_ESCAPE],rax
    jmp field_ok
set_priority:
    xor eax,eax
    cmp byte [r12],0
    je .store
    mov rsi,priority_names
    mov edx,4
    call lookup_enum
    test rax,rax
    js field_bad
 .store:
    mov [rbx+T_PRIORITY],rax
    jmp field_ok
set_repeat:
    xor eax,eax
    cmp byte [r12],0
    je .store
    mov rsi,recurrence_names
    mov edx,6
    call lookup_enum
    test rax,rax
    js field_bad
 .store:
    mov [rbx+T_REPEAT],rax
    jmp field_ok
set_stage:
    cmp byte [r12],0
    jne .value
    and qword [rbx+I_FIELDS],~(1<<13)
    jmp field_ok
.value:
    mov rsi,stages
    mov edx,3
    call lookup_enum
    test rax,rax
    js field_bad
    mov [rbx+I_STAGE],rax
    jmp field_ok
set_workflow:
    cmp byte [r12],0
    jne .value
    and qword [rbx+I_FIELDS],~(1<<17)
    jmp field_ok
.value:
    mov rsi,stages
    mov edx,2
    call lookup_enum
    test rax,rax
    js field_bad
    mov [rbx+T_STAGE],rax
    jmp field_ok
lookup_enum:
    push r13
    push r14
    push r15
    mov r13,rsi
    mov r14,rdx
    xor r15d,r15d
.loop:
    mov rdi,r12
    mov rsi,[r13+r15*8]
    call unicode_compare
    test rax,rax
    jz .found
    inc r15
    cmp r15,r14
    jb .loop
    mov rax,-422
    jmp .done
.found:
    mov rax,r15
.done:
    pop r15
    pop r14
    pop r13
    ret
field_ok:
    xor eax,eax
    ret
field_bad:
    mov rax,-422
    ret

; Strict ISO-8601 UTC timestamp, seconds precision, no locale or libc.
import_parse_timestamp:
    push rbx
    push r12
    mov rbx,rdi
    call strlen
    cmp rax,20
    jne .bad
    cmp byte [rbx+10],'T'
    jne .bad
    cmp byte [rbx+13],':'
    jne .bad
    cmp byte [rbx+16],':'
    jne .bad
    cmp byte [rbx+19],'Z'
    jne .bad
    mov rsi,rbx
    mov rdi,date_buf
    mov ecx,10
    rep movsb
    mov byte [rdi],0
    mov rdi,date_buf
    call parse_date
    test rax,rax
    js .bad
    mov r12,rax
    lea rdi,[rbx+11]
    call pair
    cmp rax,23
    ja .bad
    imul rax,3600
    add r12,rax
    lea rdi,[rbx+14]
    call pair
    cmp rax,59
    ja .bad
    imul rax,60
    add r12,rax
    lea rdi,[rbx+17]
    call pair
    cmp rax,59
    ja .bad
    add rax,r12
    jmp .done
.bad:
    mov rax,-422
.done:
    pop r12
    pop rbx
    ret
pair:
    movzx eax,byte [rdi]
    sub eax,'0'
    cmp eax,9
    ja field_bad
    imul eax,10
    movzx edx,byte [rdi+1]
    sub edx,'0'
    cmp edx,9
    ja field_bad
    add eax,edx
    ret

; rdi=fully parsed slot. Scalar validation reuses the native metadata codec.
import_validate_task:
    push rbx
    mov rbx,rdi
    mov rax,[rbx+I_FIELDS]
    and eax,15
    cmp eax,15
    jne .bad
    test qword [rbx+I_FIELDS],1<<13
    jz .workflow
    mov rax,[rbx+I_STAGE]
    cmp byte [rbx+8],1
    jne .active_stage
    cmp rax,2
    jne .bad
    jmp .workflow
.active_stage:
    cmp rax,2
    je .bad
    test qword [rbx+I_FIELDS],1<<17
    jz .use_stage
    cmp rax,[rbx+T_STAGE]
    jne .bad
    jmp .workflow
.use_stage:
    mov [rbx+T_STAGE],rax
.workflow:
    cmp qword [rbx+I_TRASH],0
    je .live
    cmp byte [rbx+8],0
    jne .bad
    cmp qword [rbx+T_DELETED],0
    je .bad
    cmp qword [rbx+T_PREVIOUS],0
    jne .trash
    cmp qword [rbx+T_COMPLETED],0
    jne .bad
.trash:
    mov byte [rbx+8],2
    jmp .tags
.live:
    cmp qword [rbx+T_DELETED],0
    jne .bad
    cmp qword [rbx+T_PREVIOUS],0
    jne .bad
.tags:
    lea rdi,[rbx+T_TAGS]
    mov rsi,tags_buf
    call normalize_tags
    test rax,rax
    js .bad
    lea rdi,[rbx+T_TAGS]
    mov rsi,tags_buf
    call strcmp
    test rax,rax
    jnz .bad
    test qword [rbx+I_FIELDS],1<<12
    jnz .metadata
    mov rdi,rbx
    call recurrence_anchor
    mov [rbx+T_ANCHOR],rax
.metadata:
    mov byte [rbx+T_META],0
    mov rdi,rbx
    mov rsi,meta_buf
    call format_metadata
    mov byte [meta_buf+rax-1],0
    mov rdi,meta_buf+2
    call parse_metadata
    test rax,rax
    js .bad
    cmp byte [rbx+8],2
    je .count_trash
    inc qword [import_live]
    jmp .ok
.count_trash:
    inc qword [import_trash]
.ok:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-422
.done:
    pop rbx
    ret

import_validate:
    cmp qword [import_live],TASK_MAX
    ja .bad
    cmp qword [import_trash],200
    ja .bad
    mov rdi,import_tasks
    call validate_metadata_graph
    test rax,rax
    js .bad
    xor eax,eax
    ret
.bad:
    mov rax,-422
    ret

; Source IDs remain intact until every reference has been remapped.
map_source:
    mov r8,import_tasks
    mov rcx,[import_count]
.loop:
    test rcx,rcx
    jz .bad
    cmp [r8],rdi
    je .found
    add r8,TASK_SIZE
    dec rcx
    jmp .loop
.found:
    mov rax,[r8+I_NEWID]
    ret
.bad:
    xor eax,eax
    ret

; Caller holds the workspace lock and has reloaded the current workspace.
; rdi=0 merge / 1 replace. Both modes assign fresh monotonic IDs.
import_apply:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14,rdi
    call import_capacity
    test rax,rax
    js .done
    test r14,r14
    jnz .prepare
    cmp qword [import_count],0
    je .unchanged
.prepare:
    mov edi,9
    xor esi,esi
    call history_prepare
    test r14,r14
    jz .allocate
    mov rdi,todos
    xor eax,eax
    mov ecx,SLOT_MAX*TASK_SIZE/8
    rep stosq
.allocate:
    mov r12,[next_id]
    mov rbx,import_tasks
    mov rcx,[import_count]
.assign:
    test rcx,rcx
    jz .references
    mov [rbx+I_NEWID],r12
    inc r12
    add rbx,TASK_SIZE
    dec rcx
    jmp .assign
.references:
    mov rbx,import_tasks
    mov r13,[import_count]
.task:
    test r13,r13
    jz .copy
    mov rdi,[rbx+T_PARENT]
    test rdi,rdi
    jz .deps
    call map_source
    test rax,rax
    jz .bad
    mov [rbx+T_PARENT],rax
.deps:
    xor r15d,r15d
.dep:
    cmp r15,[rbx+T_DEP_COUNT]
    jae .next_task
    mov rdi,[rbx+T_DEPS+r15*8]
    call map_source
    test rax,rax
    jz .bad
    mov [rbx+T_DEPS+r15*8],rax
    inc r15
    jmp .dep
.next_task:
    add rbx,TASK_SIZE
    dec r13
    jmp .task
.copy:
    mov rbx,import_tasks
    mov r13,[import_count]
    mov r8,todos
.copy_task:
    test r13,r13
    jz .save
    mov rax,[rbx+I_NEWID]
    mov [rbx],rax
.find_empty:
    cmp r8,todos+SLOT_MAX*TASK_SIZE
    jae .full
    cmp qword [r8],0
    je .copy_slot
    add r8,TASK_SIZE
    jmp .find_empty
.copy_slot:
    mov rdi,r8
    mov rsi,rbx
    mov ecx,TASK_SIZE/8
    rep movsq
    add r8,TASK_SIZE
    add rbx,TASK_SIZE
    dec r13
    jmp .copy_task
.save:
    mov [next_id],r12
    call save_snapshot
    jmp .done
.full:
    mov rax,-409
    jmp .done
.bad:
    mov rax,-422
    jmp .done
.unchanged:
    xor eax,eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Read-only capacity/ID check shared by preview and the locked apply operation.
import_capacity:
    cmp rdi,1
    ja .bad
    test rdi,rdi
    jnz .ids
    mov rax,[todo_count]
    add rax,[import_live]
    cmp rax,TASK_MAX
    ja .full
    mov r8,todos
    mov ecx,SLOT_MAX
    xor edx,edx
.count:
    cmp qword [r8],0
    je .next
    cmp byte [r8+8],2
    jne .next
    inc rdx
.next:
    add r8,TASK_SIZE
    loop .count
    add rdx,[import_trash]
    cmp rdx,200
    ja .full
.ids:
    mov rax,9223372036854775807
    sub rax,[import_count]
    cmp [next_id],rax
    ja .full
    xor eax,eax
    ret
.full:
    mov rax,-409
    ret
.bad:
    mov rax,-422
    ret
