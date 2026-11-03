%include "src/defs.inc"
DEFAULT ABS
extern copy_string, html_escape, emit_number, strcmp, format_utc
extern view_total, view_done, view_active, view_percent, view_count
extern render_properties, property_task
extern view_project, view_tag
extern view_filter, view_sort, view_query, view_action, view_id, view_target

global render_template
section .data
    name_total db 'total',0
    name_done db 'done',0
    name_active db 'active',0
    name_visible db 'visible',0
    name_percent db 'percent',0
    name_q db 'q',0
    name_q_url db 'q_url',0
    name_f db 'f',0
    name_sort db 'sort',0
    name_all_current db 'all_current',0
    name_active_current db 'active_current',0
    name_done_current db 'done_current',0
    name_all_pressed db 'all_pressed',0
    name_active_pressed db 'active_pressed',0
    name_done_pressed db 'done_pressed',0
    name_sort_newest db 'sort_newest',0
    name_sort_oldest db 'sort_oldest',0
    name_sort_az db 'sort_az',0
    name_sort_active db 'sort_active',0
    name_empty_hidden db 'empty_hidden',0
    name_clear_hidden db 'clear_hidden',0
    name_empty_title db 'empty_title',0
    name_empty_description db 'empty_description',0
    name_action_form db 'action_form',0
    name_today db 'today',0
    name_view_name db 'view_name',0
    name_today_current db 'today_current',0
    name_upcoming_current db 'upcoming_current',0
    name_overdue_current db 'overdue_current',0
    name_sort_priority db 'sort_priority',0
    name_sort_due db 'sort_due',0
    name_add_properties db 'add_properties',0
    name_project db 'project',0
    name_tag db 'tag',0
    name_project_url db 'project_url',0
    name_tag_url db 'tag_url',0
    name_blocked_current db 'blocked_current',0
    markers:
        dq name_total,emit_counter,view_total,0
        dq name_done,emit_counter,view_done,0
        dq name_active,emit_counter,view_active,0
        dq name_visible,emit_counter,view_count,0
        dq name_percent,emit_counter,view_percent,0
        dq name_q,emit_query,0,0
        dq name_q_url,emit_url,0,0
        dq name_f,emit_filter,0,0
        dq name_sort,emit_sort,0,0
        dq name_all_current,emit_current,view_filter,0
        dq name_active_current,emit_current,view_filter,1
        dq name_done_current,emit_current,view_filter,2
        dq name_all_pressed,emit_pressed,view_filter,0
        dq name_active_pressed,emit_pressed,view_filter,1
        dq name_done_pressed,emit_pressed,view_filter,2
        dq name_sort_newest,emit_selected,view_sort,0
        dq name_sort_oldest,emit_selected,view_sort,1
        dq name_sort_az,emit_selected,view_sort,2
        dq name_sort_active,emit_selected,view_sort,3
        dq name_empty_hidden,emit_hidden_positive,view_count,0
        dq name_clear_hidden,emit_hidden_zero,view_done,0
        dq name_empty_title,emit_empty_title,0,0
        dq name_empty_description,emit_empty_description,0,0
        dq name_action_form,emit_action,0,0
        dq name_today,emit_today,0,0
        dq name_view_name,emit_view_name,0,0
        dq name_today_current,emit_current,view_filter,3
        dq name_upcoming_current,emit_current,view_filter,4
        dq name_overdue_current,emit_current,view_filter,5
        dq name_sort_priority,emit_selected,view_sort,4
        dq name_sort_due,emit_selected,view_sort,5
        dq name_add_properties,emit_add_properties,0,0
        dq name_project,emit_project,0,0
        dq name_tag,emit_tag,0,0
        dq name_project_url,emit_project_url,0,0
        dq name_tag_url,emit_tag_url,0,0
        dq name_blocked_current,emit_current,view_filter,6
        dq 0,0,0,0
    lit_page db 'page',0
    lit_false db 'false',0
    lit_true db 'true',0
    lit_selected db 'selected',0
    lit_hidden db 'hidden',0
    lit_all db 'all',0
    lit_active db 'active',0
    lit_done db 'done',0
    lit_today db 'today',0
    lit_upcoming db 'upcoming',0
    lit_overdue db 'overdue',0
    lit_blocked db 'blocked',0
    filter_names dq lit_all,lit_active,lit_done,lit_today,lit_upcoming,lit_overdue,lit_blocked
    view_all db 'All tasks',0
    view_active_name db 'In progress',0
    view_done_name db 'Completed',0
    view_today_name db 'Today',0
    view_upcoming_name db 'Next 7 days',0
    view_overdue_name db 'Overdue',0
    view_blocked_name db 'Blocked',0
    view_names dq view_all,view_active_name,view_done_name,view_today_name,view_upcoming_name,view_overdue_name,view_blocked_name
    lit_newest db 'newest',0
    lit_oldest db 'oldest',0
    lit_az db 'az',0
    lit_priority db 'priority',0
    lit_due db 'due',0
    sort_names dq lit_newest,lit_oldest,lit_az,lit_active,lit_priority,lit_due
    hex db '0123456789ABCDEF'
    fresh_title db 'A little space for your next big thing.',0
    filtered_title db 'A little breathing room.',0
    fresh_description db 'Add your first task above. Every good day starts with one small step.',0
    filtered_description db 'No tasks match this view. Try another filter or a different search.',0
    action_open db '<section class="native-action" id="action-form" aria-labelledby="action-heading">',0
    edit_open db '<h2 id="action-heading">A fresh way to put it.</h2><form action="/edit" method="post"><input type="hidden" name="id" value="',0
    edit_title db '"><label for="edit-title">Task title</label><input id="edit-title" name="title" required maxlength="110" value="',0
    edit_close db '"><p class="input-hint">Up to 110 UTF-8 bytes.</p><div class="dialog-actions"><a href="/app" class="secondary-button">Cancel</a><button class="primary-button">Save changes</button></div></form></section>',0
    delete_open db '<h2 id="action-heading">Let this one go?</h2><p>Move this task and its subtasks to trash:</p><p class="confirm-task">',0
    delete_form db '</p><form action="/delete" method="post"><input type="hidden" name="id" value="',0
    delete_close db '"><div class="dialog-actions"><a href="/app" class="secondary-button">Keep it</a><button class="danger-button">Delete task</button></div></form></section>',0
    clear_form db '<h2 id="action-heading">Make room for what comes next?</h2><p>Completed tasks to delete: ',0
    clear_close db '. Active tasks stay on your list.</p><form action="/clear-done" method="post"><div class="dialog-actions"><a href="/app" class="secondary-button">Keep them</a><button class="danger-button">Clear completed</button></div></form></section>',0
    forget_form db '<h2 id="action-heading">Leave this workspace?</h2><p>Save your recovery key first. Without it, you cannot return after this browser forgets your workspace.</p><p><a href="/recovery" download>Save recovery key</a></p><form action="/forget" method="post"><div class="dialog-actions"><a href="/app" class="secondary-button">Stay here</a><button class="danger-button">Forget workspace</button></div></form></section>',0
section .bss
    marker_buf resb 32
    date_buf resb 24
section .text
; Static templates with explicit, bounded marker names. Unknown markers fail.
; rdi=output, rsi=template. Returns rax=0/-500 and advances rdi.
render_template:
    push rbx
    push r12
    push r13
    mov rbx,rsi
.loop:
    mov al,[rbx]
    test al,al
    jz .ok
    cmp word [rbx],'{{'
    je .marker
    stosb
    inc rbx
    jmp .loop
.marker:
    add rbx,2
    xor ecx,ecx
.name:
    cmp word [rbx],'}}'
    je .lookup
    cmp byte [rbx],0
    je .bad
    cmp ecx,31
    jae .bad
    mov al,[rbx]
    mov [marker_buf+rcx],al
    inc rbx
    inc ecx
    jmp .name
.lookup:
    mov byte [marker_buf+rcx],0
    add rbx,2
    mov r13,markers
.find:
    cmp qword [r13],0
    je .bad
    push rdi
    mov rdi,marker_buf
    mov rsi,[r13]
    call strcmp
    pop rdi
    test rax,rax
    jz .emit
    add r13,32
    jmp .find
.emit:
    mov rsi,[r13+16]
    mov rdx,[r13+24]
    call [r13+8]
    jmp .loop
.ok:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r13
    pop r12
    pop rbx
    ret
emit_counter:
    mov rax,[rsi]
    jmp emit_number
emit_query:
    mov rsi,view_query
    jmp html_escape
emit_url:
    mov rsi,view_query
    jmp emit_url_text
emit_url_text:
.loop:
    lodsb
    test al,al
    jz .done
    cmp al,'a'
    jb .upper
    cmp al,'z'
    jbe .plain
.upper:
    cmp al,'A'
    jb .digit
    cmp al,'Z'
    jbe .plain
.digit:
    cmp al,'0'
    jb .symbol
    cmp al,'9'
    jbe .plain
.symbol:
    cmp al,'-'
    je .plain
    cmp al,'_'
    je .plain
    cmp al,'.'
    je .plain
    cmp al,'~'
    je .plain
    mov byte [rdi],'%'
    inc rdi
    movzx edx,al
    shr edx,4
    and eax,15
    mov cl,[hex+rdx]
    mov [rdi],cl
    mov cl,[hex+rax]
    mov [rdi+1],cl
    add rdi,2
    jmp .loop
.plain:
    stosb
    jmp .loop
.done:
    ret
emit_current:
    mov rax,[rsi]
    mov rsi,lit_false
    cmp rax,rdx
    jne .emit
    mov rsi,lit_page
.emit:
    jmp copy_string
emit_pressed:
    mov rax,[rsi]
    mov rsi,lit_false
    cmp rax,rdx
    jne .emit
    mov rsi,lit_true
.emit:
    jmp copy_string
emit_selected:
    cmp [rsi],rdx
    jne emit_nothing
    mov rsi,lit_selected
    jmp copy_string
emit_hidden_positive:
    cmp qword [rsi],0
    je emit_nothing
    mov rsi,lit_hidden
    jmp copy_string
emit_hidden_zero:
    cmp qword [rsi],0
    jne emit_nothing
    mov rsi,lit_hidden
    jmp copy_string
emit_nothing:
    ret
emit_filter:
    mov rax,[view_filter]
    mov rsi,[filter_names+rax*8]
    jmp copy_string
emit_sort:
    mov rax,[view_sort]
    mov rsi,[sort_names+rax*8]
    jmp copy_string
emit_view_name:
    mov rax,[view_filter]
    mov rsi,[view_names+rax*8]
    jmp copy_string
emit_empty_title:
    mov rsi,fresh_title
    cmp qword [view_total],0
    je .emit
    mov rsi,filtered_title
.emit:
    jmp copy_string
emit_empty_description:
    mov rsi,fresh_description
    cmp qword [view_total],0
    je .emit
    mov rsi,filtered_description
.emit:
    jmp copy_string
emit_today:
    push rdi
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    mov rdi,rax
    mov rsi,date_buf
    call format_utc
    pop rdi
    mov byte [date_buf+10],0
    mov rsi,date_buf
    jmp copy_string
emit_action:
    push rbx
    cmp qword [view_action],0
    je .done
    mov rsi,action_open
    call copy_string
    cmp qword [view_action],1
    je .edit
    cmp qword [view_action],2
    je .delete
    cmp qword [view_action],3
    je .clear
    mov rsi,forget_form
    call copy_string
    jmp .done
.edit:
    mov rbx,[view_target]
    mov rsi,edit_open
    call copy_string
    mov rax,[view_id]
    call emit_number
    mov rsi,edit_title
    call copy_string
    lea rsi,[rbx+17]
    call html_escape
    mov word [rdi],'">'
    add rdi,2
    mov rsi,rbx
    xor edx,edx
    call render_properties
    mov rsi,edit_close+2
    call copy_string
    jmp .done
.delete:
    mov rbx,[view_target]
    mov rsi,delete_open
    call copy_string
    lea rsi,[rbx+17]
    call html_escape
    mov rsi,delete_form
    call copy_string
    mov rax,[view_id]
    call emit_number
    mov rsi,delete_close
    call copy_string
    jmp .done
.clear:
    mov rsi,clear_form
    call copy_string
    mov rax,[view_done]
    call emit_number
    mov rsi,clear_close
    call copy_string
.done:
    pop rbx
    ret

emit_add_properties:
    mov rsi,property_task
    mov edx,1
    jmp render_properties

emit_project:
    mov rsi,view_project
    jmp html_escape
emit_tag:
    mov rsi,view_tag
    jmp html_escape
emit_project_url:
    mov rsi,view_project
    jmp emit_url_text
emit_tag_url:
    mov rsi,view_tag
    jmp emit_url_text
