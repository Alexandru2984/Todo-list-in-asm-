%include "src/defs.inc"
%include "src/import.inc"
DEFAULT ABS
extern json_begin, json_next, json_text, json_number
extern import_reset, import_tasks, import_count, import_set_text
extern import_validate_task, import_validate, import_parse_timestamp
extern todos, lookup_array, strcmp, parse_uint, itoa

global import_json, import_field_index, import_schema
section .data
    root_version db 'version',0
    root_exported db 'exportedAt',0
    root_tasks db 'tasks',0
    root_trash db 'trash',0
    root_names dq root_version,root_exported,root_tasks,root_trash
    field_id db 'id',0
    field_title db 'title',0
    field_completed db 'completed',0
    field_created db 'createdAt',0
    field_priority db 'priority',0
    field_due db 'dueDate',0
    field_completed_at db 'completedAt',0
    field_project db 'project',0
    field_tags db 'tags',0
    field_parent db 'parentId',0
    field_deps db 'dependencies',0
    field_repeat db 'recurrence',0
    field_anchor db 'recurrenceAnchor',0
    field_stage db 'stage',0
    field_deleted db 'deletedAt',0
    field_previous db 'previousCompleted',0
    field_escape db 'escapeFlags',0
    field_workflow db 'workflowStage',0
    names dq field_id,field_title,field_completed,field_created,field_priority
          dq field_due,field_completed_at,field_project,field_tags,field_parent
          dq field_deps,field_repeat,field_anchor,field_stage,field_deleted
          dq field_previous,field_escape,field_workflow
    lit_true db 'true',0
    lit_false db 'false',0
    empty db 0
section .bss
    import_schema resq 1
    root_flags resq 1
    metadata_seen resq 1
    integer_text resb 24
section .text
import_field_index:
    push rbx
    push r12
    mov r12,rdi
    xor ebx,ebx
.loop:
    mov rdi,r12
    mov rsi,[names+rbx*8]
    call strcmp
    test rax,rax
    jz .found
    inc ebx
    cmp ebx,18
    jb .loop
    mov rax,-422
    jmp .done
.found:
    mov rax,rbx
.done:
    pop r12
    pop rbx
    ret

import_json:
    push rbx
    push r12
    push r13
    push rdi
    call import_reset
    pop rdi
    mov qword [import_schema],0
    mov qword [root_flags],0
    mov qword [metadata_seen],0
    call json_begin
    call json_next
    cmp eax,'{'
    jne .bad
    call json_next
    cmp eax,'}'
    je .finish
.key:
    cmp eax,JSON_STRING
    jne .bad
    xor r13d,r13d
.find:
    mov rdi,[json_text]
    mov rsi,[root_names+r13*8]
    call strcmp
    test rax,rax
    jz .known
    inc r13
    cmp r13,4
    jb .find
    jmp .bad
.known:
    mov ecx,r13d
    mov eax,1
    shl rax,cl
    test [root_flags],rax
    jnz .bad
    or [root_flags],rax
    call json_next
    cmp eax,':'
    jne .bad
    cmp r13,0
    je .version
    cmp r13,1
    je .exported
    xor edi,edi
    cmp r13,3
    sete dil
    call parse_array
    test rax,rax
    js .bad
    jmp .separator
.version:
    call json_next
    cmp eax,JSON_NUMBER
    jne .bad
    mov rax,[json_number]
    cmp rax,1
    jb .bad
    cmp rax,2
    ja .bad
    mov [import_schema],rax
    jmp .separator
.exported:
    call json_next
    cmp eax,JSON_STRING
    jne .bad
    mov rdi,[json_text]
    call import_parse_timestamp
    test rax,rax
    js .bad
.separator:
    call json_next
    cmp eax,'}'
    je .finish
    cmp eax,','
    jne .bad
    call json_next
    jmp .key
.finish:
    call json_next
    test eax,eax
    jnz .bad
    mov rax,[root_flags]
    and eax,5
    cmp eax,5
    jne .bad
    cmp qword [import_schema],1
    jne .validate
    test qword [root_flags],8
    jnz .bad
    mov rax,[metadata_seen]
    and rax,~15
    jnz .bad
.validate:
    call import_validate
    jmp .done
.bad:
    mov rax,-422
.done:
    mov qword [lookup_array],todos
    pop r13
    pop r12
    pop rbx
    ret

parse_array:
    push rbx
    mov rbx,rdi ; live/trash container
    call json_next
    cmp eax,'['
    jne .bad
    call json_next
    cmp eax,']'
    je .ok
.task:
    cmp eax,'{'
    jne .bad
    mov rax,[import_count]
    cmp rax,SLOT_MAX
    jae .bad
    shl rax,9
    lea rdi,[import_tasks+rax]
    mov rsi,rbx
    call parse_task
    test rax,rax
    js .bad
    inc qword [import_count]
    call json_next
    cmp eax,']'
    je .ok
    cmp eax,','
    jne .bad
    call json_next
    jmp .task
.ok:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-422
.done:
    pop rbx
    ret

parse_task:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    mov [rbx+I_TRASH],rsi
    call json_next
    cmp eax,'}'
    je .finish
.key:
    cmp eax,JSON_STRING
    jne .bad
    mov rdi,[json_text]
    call import_field_index
    test rax,rax
    js .bad
    cmp rax,16 ; CSV-only spreadsheet escape bitmask
    je .bad
    mov r13,rax
    mov ecx,eax
    mov eax,1
    shl rax,cl
    test [rbx+I_FIELDS],rax
    jnz .bad
    or [rbx+I_FIELDS],rax
    call json_next
    cmp eax,':'
    jne .bad
    call json_next
    cmp r13,10
    je .dependencies
    cmp r13,2
    je .boolean
    cmp r13,15
    je .boolean
    cmp r13,12
    je .integer
    cmp eax,JSON_STRING
    je .string
    cmp eax,JSON_NULL
    jne .bad
    cmp r13,3
    je .null
    cmp r13,5
    je .null
    cmp r13,6
    je .null
    cmp r13,9
    je .null
    cmp r13,14
    jne .bad
.null:
    mov rdx,empty
    jmp .set
.string:
    mov rdx,[json_text]
    jmp .set
.boolean:
    mov rdx,lit_true
    cmp eax,JSON_TRUE
    je .set
    mov rdx,lit_false
    cmp eax,JSON_FALSE
    jne .bad
    jmp .set
.integer:
    cmp eax,JSON_NUMBER
    jne .bad
    mov rdi,[json_number]
    mov rsi,integer_text
    call itoa
    mov rdx,integer_text
.set:
    mov rdi,rbx
    mov rsi,r13
    call import_set_text
    test rax,rax
    js .bad
    jmp .separator
.dependencies:
    cmp eax,'['
    jne .bad
    call json_next
    cmp eax,']'
    je .separator
.dep:
    cmp eax,JSON_STRING
    jne .bad
    mov rdi,[json_text]
    call parse_uint
    test rax,rax
    jle .bad
    mov rcx,[rbx+T_DEP_COUNT]
    cmp rcx,DEP_MAX
    jae .bad
    xor edx,edx
.unique:
    cmp rdx,rcx
    jae .store_dep
    cmp [rbx+T_DEPS+rdx*8],rax
    je .bad
    inc rdx
    jmp .unique
.store_dep:
    mov [rbx+T_DEPS+rcx*8],rax
    inc qword [rbx+T_DEP_COUNT]
    call json_next
    cmp eax,']'
    je .separator
    cmp eax,','
    jne .bad
    call json_next
    jmp .dep
.separator:
    call json_next
    cmp eax,'}'
    je .finish
    cmp eax,','
    jne .bad
    call json_next
    jmp .key
.finish:
    mov rax,[rbx+I_FIELDS]
    or [metadata_seen],rax
    mov rdi,rbx
    call import_validate_task
    jmp .done
.bad:
    mov rax,-422
.done:
    pop r13
    pop r12
    pop rbx
    ret
