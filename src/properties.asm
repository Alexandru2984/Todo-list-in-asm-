%include "src/defs.inc"
DEFAULT ABS
extern strcmp, parse_date, copy_string, format_utc, html_escape

global reset_properties, parse_property, apply_properties, render_properties
 global property_flags, property_task, priority_names, render_task_badges
section .data
    priority_key db 'priority',0
    due_key db 'due',0
    normal db 'normal',0
    low db 'low',0
    high db 'high',0
    urgent db 'urgent',0
    priority_names dq normal,low,high,urgent
    form_open db '<div class="property-grid"><label>Priority<select name="priority"',0
    external_form db ' form="add-form"',0
    option_open db '<option value="',0
    selected db ' selected',0
    option_end db '</option>',0
    due_open db '</select></label><label>Due date (UTC)<input type="date" name="due" min="1970-01-02" max="9999-12-31" value="',0
    form_close db '></label></div>',0
    badges_open db '<div class="task-badges">',0
    priority_open db '<span class="priority-badge" data-priority="',0
    priority_close db ' priority</span>',0
    badge_due db '<time class="due-badge">Due ',0
    time_close db '</time>',0
    div_close db '</div>',0
section .bss
    property_flags resq 1 ; 1 priority, 2 due
    property_task resb TASK_SIZE
    date_buffer resb 24
section .text
reset_properties:
    mov qword [property_flags],0
    mov rdi,property_task
    xor eax,eax
    mov ecx,TASK_SIZE/8
    rep stosq
    ret

; rdi=exact field name, rsi=validated decoded value. 1 recognized, 0 unknown,
; -400 invalid. The router rejects stripped controls before calling this.
parse_property:
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
    mov rsi,priority_key
    call strcmp
    test rax,rax
    jz .priority
    mov rdi,rbx
    mov rsi,due_key
    call strcmp
    test rax,rax
    jz .due
    xor eax,eax
    jmp .done
.priority:
    test qword [property_flags],1
    jnz .bad
    or qword [property_flags],1
    xor ebx,ebx
.priority_loop:
    mov rdi,r12
    mov rsi,[priority_names+rbx*8]
    call strcmp
    test rax,rax
    jz .priority_value
    inc ebx
    cmp ebx,4
    jb .priority_loop
    jmp .bad
.priority_value:
    mov [property_task+T_PRIORITY],rbx
    jmp .ok
.due:
    test qword [property_flags],2
    jnz .bad
    or qword [property_flags],2
    xor eax,eax
    cmp byte [r12],0
    je .due_value
    mov rdi,r12
    call parse_date
    test rax,rax
    jle .bad ; zero is the explicit "no due date" storage sentinel
.due_value:
    mov [property_task+T_DUE],rax
.ok:
    mov eax,1
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r12
    pop rbx
    ret

apply_properties:
    test qword [property_flags],1
    jz .due
    mov rax,[property_task+T_PRIORITY]
    mov [rdi+T_PRIORITY],rax
.due:
    test qword [property_flags],2
    jz .done
    mov rax,[property_task+T_DUE]
    mov [rdi+T_DUE],rax
    test rax,rax
    jnz .done
    mov qword [rdi+T_REPEAT],0
    mov qword [rdi+T_ANCHOR],0
.done:
    ret

; Native add/edit/draft forms. rsi=slot, edx=1 attaches to external add-form.
render_properties:
    push rbx
    push r12
    push r13
    mov rbx,rsi
    mov r12,rdx
    mov rsi,form_open
    call copy_string
    call .external
    mov byte [rdi],'>'
    inc rdi
    xor r13d,r13d
.option:
    mov rsi,option_open
    call copy_string
    mov rsi,[priority_names+r13*8]
    call copy_string
    mov byte [rdi],'"'
    inc rdi
    cmp [rbx+T_PRIORITY],r13
    jne .label
    mov rsi,selected
    call copy_string
.label:
    mov byte [rdi],'>'
    inc rdi
    mov rsi,[priority_names+r13*8]
    call copy_string
    mov rsi,option_end
    call copy_string
    inc r13
    cmp r13,4
    jb .option
    mov rsi,due_open
    call copy_string
    cmp qword [rbx+T_DUE],0
    je .close_date
    push rdi
    mov rdi,[rbx+T_DUE]
    mov rsi,date_buffer
    call format_utc
    pop rdi
    mov byte [date_buffer+10],0
    mov rsi,date_buffer
    call copy_string
.close_date:
    mov byte [rdi],'"'
    inc rdi
    call .external
    mov rsi,form_close
    call copy_string
    pop r13
    pop r12
    pop rbx
    ret
.external:
    test r12,r12
    jz .external_done
    mov rsi,external_form
    call copy_string
.external_done:
    ret

; rsi=slot, output advances. No title/metadata can be interpreted as markup.
render_task_badges:
    push rbx
    mov rbx,rsi
    mov rsi,badges_open
    call copy_string
    cmp qword [rbx+T_PRIORITY],0
    je .due
    mov rsi,priority_open
    call copy_string
    mov rax,[rbx+T_PRIORITY]
    mov rsi,[priority_names+rax*8]
    call copy_string
    mov word [rdi],'">'
    add rdi,2
    mov rax,[rbx+T_PRIORITY]
    mov rsi,[priority_names+rax*8]
    call copy_string
    mov rsi,priority_close
    call copy_string
.due:
    cmp qword [rbx+T_DUE],0
    je .close
    mov rsi,badge_due
    call copy_string
    push rdi
    mov rdi,[rbx+T_DUE]
    mov rsi,date_buffer
    call format_utc
    pop rdi
    mov byte [date_buffer+10],0
    mov rsi,date_buffer
    call copy_string
    mov rsi,time_close
    call copy_string
.close:
    mov rsi,div_close
    call copy_string
    pop rbx
    ret
