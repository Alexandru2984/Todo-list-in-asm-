%include "src/defs.inc"
DEFAULT ABS
extern strcmp, parse_date, copy_string, format_utc, html_escape
extern recurrence_names, recurrence_anchor
extern normalize_tags, strlen

global reset_properties, parse_property, apply_properties, render_properties
 global property_flags, property_task, priority_names, render_task_badges
section .data
    priority_key db 'priority',0
    due_key db 'due',0
    repeat_key db 'repeat',0
    project_key db 'project',0
    tags_key db 'tags',0
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
    form_close db '></label><label>Repeat<select name="repeat"',0
    repeat_close db '</select></label>',0
    project_open db '<label>Project<input name="project" maxlength="32" value="',0
    tags_open db '<label>Tags (comma separated)<input name="tags" maxlength="64" value="',0
    input_close db '></label>',0
    properties_close db '</div><p class="input-hint">Repeat requires a due date. Up to 8 unique tags, 24 UTF-8 bytes each; 64 bytes total.</p>',0
    badges_open db '<div class="task-badges">',0
    priority_open db '<span class="priority-badge" data-priority="',0
    priority_close db ' priority</span>',0
    badge_due db '<time class="due-badge">Due ',0
    time_close db '</time>',0
    div_close db '</div>',0
    badge_repeat db '<span class="repeat-badge">Repeats ',0
    span_close db '</span>',0
    badge_project db '<span class="project-badge">Project: ',0
    badge_tags db '<span class="tags-badge">Tags: ',0
section .bss
    property_flags resq 1 ; 1 priority, 2 due, 4 repeat
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
    mov rdi,rbx
    mov rsi,repeat_key
    call strcmp
    test rax,rax
    jz .repeat
    mov rdi,rbx
    mov rsi,project_key
    call strcmp
    test rax,rax
    jz .project
    mov rdi,rbx
    mov rsi,tags_key
    call strcmp
    test rax,rax
    jz .tags
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
    jmp .ok
.repeat:
    test qword [property_flags],4
    jnz .bad
    or qword [property_flags],4
    xor ebx,ebx
.repeat_loop:
    mov rdi,r12
    mov rsi,[recurrence_names+rbx*8]
    call strcmp
    test rax,rax
    jz .repeat_value
    inc ebx
    cmp ebx,6
    jb .repeat_loop
    jmp .bad
.repeat_value:
    mov [property_task+T_REPEAT],rbx
    jmp .ok
.project:
    test qword [property_flags],8
    jnz .bad
    or qword [property_flags],8
    mov rdi,r12
    mov rsi,property_task+T_PROJECT
    mov edx,PROJECT_MAX
    call trim_property_text
    test rax,rax
    js .bad
    jmp .ok
.tags:
    test qword [property_flags],16
    jnz .bad
    or qword [property_flags],16
    mov rdi,r12
    mov rsi,property_task+T_TAGS
    call normalize_tags
    test rax,rax
    js .bad
.ok:
    mov eax,1
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r12
    pop rbx
    ret

; Validated decoded source, ASCII whitespace trimmed, bounded UTF-8 bytes.
trim_property_text:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
.leading:
    cmp byte [rbx],' '
    jne .length
    inc rbx
    jmp .leading
.length:
    mov rdi,rbx
    call strlen
.trailing:
    test rax,rax
    jz .copy
    cmp byte [rbx+rax-1],' '
    jne .copy
    dec rax
    jmp .trailing
.copy:
    cmp rax,r13
    ja .bad
    mov rcx,rax
    mov rsi,rbx
    mov rdi,r12
    rep movsb
    mov byte [rdi],0
    xor eax,eax
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r13
    pop r12
    pop rbx
    ret

apply_properties:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    mov r12,[rdi+T_DUE]
    mov r13,[rdi+T_REPEAT]
    test qword [property_flags],1
    jz .due
    mov rax,[property_task+T_PRIORITY]
    mov [rdi+T_PRIORITY],rax
.due:
    test qword [property_flags],2
    jz .repeat
    mov rax,[property_task+T_DUE]
    mov [rdi+T_DUE],rax
    test rax,rax
    jnz .repeat
    mov qword [rdi+T_REPEAT],0
    mov qword [rdi+T_ANCHOR],0
.repeat:
    test qword [property_flags],4
    jz .validate
    mov rax,[property_task+T_REPEAT]
    mov [rdi+T_REPEAT],rax
.validate:
    cmp qword [rdi+T_REPEAT],0
    je .no_repeat
    cmp qword [rdi+T_DUE],0
    je .bad
    cmp r12,[rdi+T_DUE]
    jne .anchor
    cmp r13,[rdi+T_REPEAT]
    jne .anchor
    cmp qword [rdi+T_ANCHOR],0
    jne .ok
.anchor:
    call recurrence_anchor
    mov [rbx+T_ANCHOR],rax
    jmp .ok
.no_repeat:
    mov qword [rdi+T_ANCHOR],0
.ok:
    test qword [property_flags],8
    jz .tags
    lea rdi,[rbx+T_PROJECT]
    mov rsi,property_task+T_PROJECT
    mov ecx,PROJECT_MAX+1
    rep movsb
.tags:
    test qword [property_flags],16
    jz .success
    lea rdi,[rbx+T_TAGS]
    mov rsi,property_task+T_TAGS
    mov ecx,TAGS_MAX+1
    rep movsb
.success:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r13
    pop r12
    pop rbx
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
    call .external
    mov byte [rdi],'>'
    inc rdi
    xor r13d,r13d
.repeat_option:
    mov rsi,option_open
    call copy_string
    mov rsi,[recurrence_names+r13*8]
    call copy_string
    mov byte [rdi],'"'
    inc rdi
    cmp [rbx+T_REPEAT],r13
    jne .repeat_label
    mov rsi,selected
    call copy_string
.repeat_label:
    mov byte [rdi],'>'
    inc rdi
    mov rsi,[recurrence_names+r13*8]
    call copy_string
    mov rsi,option_end
    call copy_string
    inc r13
    cmp r13,6
    jb .repeat_option
    mov rsi,repeat_close
    call copy_string
    mov rsi,project_open
    call copy_string
    lea rsi,[rbx+T_PROJECT]
    call html_escape
    mov byte [rdi],'"'
    inc rdi
    call .external
    mov rsi,input_close
    call copy_string
    mov rsi,tags_open
    call copy_string
    lea rsi,[rbx+T_TAGS]
    call html_escape
    mov byte [rdi],'"'
    inc rdi
    call .external
    mov rsi,input_close
    call copy_string
    mov rsi,properties_close
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
    cmp qword [rbx+T_REPEAT],0
    je .end
    mov rsi,badge_repeat
    call copy_string
    mov rax,[rbx+T_REPEAT]
    mov rsi,[recurrence_names+rax*8]
    call copy_string
    mov rsi,span_close
    call copy_string
.end:
    cmp byte [rbx+T_PROJECT],0
    je .tags
    mov rsi,badge_project
    call copy_string
    lea rsi,[rbx+T_PROJECT]
    call html_escape
    mov rsi,span_close
    call copy_string
.tags:
    cmp byte [rbx+T_TAGS],0
    je .badges_end
    mov rsi,badge_tags
    call copy_string
    lea rsi,[rbx+T_TAGS]
    call html_escape
    mov rsi,span_close
    call copy_string
.badges_end:
    mov rsi,div_close
    call copy_string
    pop rbx
    ret
