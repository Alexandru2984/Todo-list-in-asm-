%include "src/defs.inc"
DEFAULT ABS
extern copy_string, emit_number, json_string, json_date, format_utc
extern csv_title, csv_formula, priority_names

global export_json_metadata, export_csv_metadata, recurrence_names
section .data
    p_priority db ',"priority":',0
    p_due db ',"dueDate":',0
    p_completed db ',"completedAt":',0
    p_project db ',"project":',0
    p_tags db ',"tags":',0
    p_parent db ',"parentId":',0
    p_deps db ',"dependencies":[',0
    p_repeat db ',"recurrence":',0
    p_anchor db ',"recurrenceAnchor":',0
    p_stage db ',"stage":',0
    p_workflow db ',"workflowStage":',0
    p_deleted db ',"deletedAt":',0
    p_previous db ',"previousCompleted":',0
    none db 'none',0
    daily db 'daily',0
    weekdays db 'weekdays',0
    weekly db 'weekly',0
    monthly db 'monthly',0
    yearly db 'yearly',0
    recurrence_names dq none,daily,weekdays,weekly,monthly,yearly
    todo db 'todo',0
    doing db 'doing',0
    done db 'done',0
    stages dq todo,doing,done
    lit_null db 'null',0
    lit_false db 'false',0
    lit_true db 'true',0
section .bss
    stamp resb 24
section .text
json_optional_time:
    test rax,rax
    jnz json_date
    mov rsi,lit_null
    jmp copy_string

; Due dates use a date string; timestamps use the full UTC representation.
json_due:
    test rax,rax
    jz .null
    call format_due
    mov rsi,stamp
    jmp json_string
.null:
    mov rsi,lit_null
    jmp copy_string
format_due:
    push rdi
    mov rdi,rax
    mov rsi,stamp
    call format_utc
    pop rdi
    mov byte [stamp+10],0
    ret

export_json_metadata:
    push rbx
    push r12
    mov rbx,rsi
    mov rsi,p_priority
    call copy_string
    mov rax,[rbx+T_PRIORITY]
    mov rsi,[priority_names+rax*8]
    call json_string
    mov rsi,p_due
    call copy_string
    mov rax,[rbx+T_DUE]
    call json_due
    mov rsi,p_completed
    call copy_string
    mov rax,[rbx+T_COMPLETED]
    call json_optional_time
    mov rsi,p_project
    call copy_string
    lea rsi,[rbx+T_PROJECT]
    call json_string
    mov rsi,p_tags
    call copy_string
    lea rsi,[rbx+T_TAGS]
    call json_string
    mov rsi,p_parent
    call copy_string
    mov rax,[rbx+T_PARENT]
    test rax,rax
    jz .no_parent
    mov byte [rdi],'"'
    inc rdi
    call emit_number
    mov byte [rdi],'"'
    inc rdi
    jmp .deps
.no_parent:
    mov rsi,lit_null
    call copy_string
.deps:
    mov rsi,p_deps
    call copy_string
    xor r12d,r12d
.dep:
    cmp r12,[rbx+T_DEP_COUNT]
    jae .repeat
    test r12,r12
    jz .dep_id
    mov byte [rdi],','
    inc rdi
.dep_id:
    mov byte [rdi],'"'
    inc rdi
    mov rax,[rbx+T_DEPS+r12*8]
    call emit_number
    mov byte [rdi],'"'
    inc rdi
    inc r12
    jmp .dep
.repeat:
    mov byte [rdi],']'
    inc rdi
    mov rsi,p_repeat
    call copy_string
    mov rax,[rbx+T_REPEAT]
    mov rsi,[recurrence_names+rax*8]
    call json_string
    mov rsi,p_anchor
    call copy_string
    mov rax,[rbx+T_ANCHOR]
    call emit_number
    mov rsi,p_stage
    call copy_string
    mov rax,[rbx+T_STAGE]
    cmp byte [rbx+8],1
    jne .stage
    mov eax,2
.stage:
    mov rsi,[stages+rax*8]
    call json_string
    mov rsi,p_workflow
    call copy_string
    mov rax,[rbx+T_STAGE]
    mov rsi,[stages+rax*8]
    call json_string
    mov rsi,p_deleted
    call copy_string
    mov rax,[rbx+T_DELETED]
    call json_optional_time
    mov rsi,p_previous
    call copy_string
    mov rsi,lit_false
    cmp qword [rbx+T_PREVIOUS],0
    je .previous
    mov rsi,lit_true
.previous:
    call copy_string
    pop r12
    pop rbx
    ret

; Append a comma and one spreadsheet-safe quoted field.
csv_field:
    mov byte [rdi],','
    inc rdi
    jmp csv_title
csv_date:
    mov word [rdi],',"'
    add rdi,2
    test rax,rax
    jz .close
    call format_due
    mov rsi,stamp
    call copy_string
.close:
    mov byte [rdi],'"'
    inc rdi
    ret
csv_optional_time:
    mov word [rdi],',"'
    add rdi,2
    test rax,rax
    jz .close
    push rdi
    mov rdi,rax
    mov rsi,stamp
    call format_utc
    pop rdi
    mov rsi,stamp
    call copy_string
.close:
    mov byte [rdi],'"'
    inc rdi
    ret
csv_number:
    mov word [rdi],',"'
    add rdi,2
    call emit_number
    mov byte [rdi],'"'
    inc rdi
    ret
export_csv_metadata:
    push rbx
    push r12
    push r13
    mov rbx,rsi
    mov rax,[rbx+T_PRIORITY]
    mov rsi,[priority_names+rax*8]
    call csv_field
    mov rax,[rbx+T_DUE]
    call csv_date
    mov rax,[rbx+T_COMPLETED]
    call csv_optional_time
    lea rsi,[rbx+T_PROJECT]
    call csv_field
    lea rsi,[rbx+T_TAGS]
    call csv_field
    mov rax,[rbx+T_PARENT]
    call csv_number
    mov word [rdi],',"'
    add rdi,2
    xor r12d,r12d
.dep:
    cmp r12,[rbx+T_DEP_COUNT]
    jae .repeat
    test r12,r12
    jz .dep_id
    mov byte [rdi],','
    inc rdi
.dep_id:
    mov rax,[rbx+T_DEPS+r12*8]
    call emit_number
    inc r12
    jmp .dep
.repeat:
    mov byte [rdi],'"'
    inc rdi
    mov rax,[rbx+T_REPEAT]
    mov rsi,[recurrence_names+rax*8]
    call csv_field
    mov rax,[rbx+T_ANCHOR]
    call csv_number
    mov rax,[rbx+T_STAGE]
    cmp byte [rbx+8],1
    jne .stage
    mov eax,2
.stage:
    mov rsi,[stages+rax*8]
    call csv_field
    mov rax,[rbx+T_DELETED]
    call csv_optional_time
    mov rsi,lit_false
    cmp qword [rbx+T_PREVIOUS],0
    je .previous
    mov rsi,lit_true
.previous:
    call csv_field
    xor r13d,r13d
    lea rsi,[rbx+17]
    call csv_formula
    or r13,rax
    lea rsi,[rbx+T_PROJECT]
    call csv_formula
    shl rax,1
    or r13,rax
    lea rsi,[rbx+T_TAGS]
    call csv_formula
    shl rax,2
    or r13,rax
    mov rax,r13
    call csv_number
    mov rax,[rbx+T_STAGE]
    mov rsi,[stages+rax*8]
    call csv_field
    pop r13
    pop r12
    pop rbx
    ret
