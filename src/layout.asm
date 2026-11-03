%include "src/defs.inc"
DEFAULT ABS
extern strcmp, strlen, parse_date, date_epoch, format_utc
extern copy_string, emit_number, render_template, emit_filter, emit_sort, emit_url_text
extern view_filter, query_status, view_rows, view_count, view_query, view_project, view_tag

global init_layout, parse_layout_field, prepare_layout
 global view_layout, view_month, view_day, month_start, month_end
 global render_calendar_panel, render_board_start, render_board_end
 global emit_mutation_prefix, emit_layout, emit_list_class
section .data
    key_layout db 'layout',0
    key_month db 'month',0
    key_day db 'day',0
    list db 'list',0
    board db 'board',0
    calendar db 'calendar',0
    layout_names dq list,board,calendar
    task_list db 'task-list',0
    board_list db 'task-list board-root',0
    board_prefix db '/board',0
    board_open db '<li class="board-column"><h3>',0
    board_tasks db '</h3><ul class="task-list">',0
    board_close db '</ul></li>',0
    todo db 'To do',0
    doing db 'In progress',0
    done db 'Done',0
    stage_names dq todo,doing,done
    panel_open db '<section class="calendar-panel" aria-labelledby="calendar-heading"><div class="calendar-heading"><h2 id="calendar-heading">Due calendar · ',0
    panel_nav db '</h2><nav aria-label="Month navigation">',0
    prev_open db '<a class="secondary-button" href="/app?layout=calendar&amp;month=',0
    prev_close db '">Previous</a>',0
    next_open db '<a class="secondary-button" href="/app?layout=calendar&amp;month=',0
    next_close db '">Next</a>',0
    month_form db '</nav></div><form class="month-form" method="get" action="/app"><input type="hidden" name="layout" value="calendar"><input type="hidden" name="f" value="{{f}}"><input type="hidden" name="sort" value="{{sort}}"><input type="hidden" name="q" value="{{q}}"><input type="hidden" name="project" value="{{project}}"><input type="hidden" name="tag" value="{{tag}}"><label>Calendar month<input type="month" name="month" min="1970-01" max="9999-12" value="{{month}}"></label><button class="secondary-button">Open month</button></form><div class="calendar-weekdays" aria-hidden="true"><span>Mon</span><span>Tue</span><span>Wed</span><span>Thu</span><span>Fri</span><span>Sat</span><span>Sun</span></div><div class="calendar-grid">',0
    blank db '<span class="calendar-blank" aria-hidden="true"></span>',0
    cell_open db '<a class="calendar-day" data-day="',0
    cell_count db '" data-due-count="',0
    cell_href db '" href="/app?layout=list&amp;day=',0
    cell_title db '"><span>',0
    cell_number db '</span><small>',0
    cell_close db '</small></a>',0
    epoch_cell db '<span class="calendar-day"><span>1</span><small>0</small></span>',0
    panel_close db '</div><p class="query-hint">Counts follow current filters. Select a date to see its tasks. Dates use UTC.</p></section>',0
    f_prefix db '&amp;f=',0
    sort_prefix db '&amp;sort=',0
    q_prefix db '&amp;q=',0
    project_prefix db '&amp;project=',0
    tag_prefix db '&amp;tag=',0
section .bss
    view_layout resq 1
    view_day resq 1
    view_month resb 8
    month_start resq 1
    month_end resq 1
    layout_flags resq 1
    date_buf resb 24
    month_date resb 16
    cell_total resq 1
section .text
init_layout:
    mov qword [view_layout],0
    mov qword [view_day],0
    mov qword [layout_flags],0
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    mov rdi,rax
    mov rsi,date_buf
    call format_utc
    mov rdi,view_month
    mov rsi,date_buf
    mov ecx,7
    rep movsb
    mov byte [rdi],0
    ret

parse_layout_field:
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
    mov rsi,key_layout
    call strcmp
    test rax,rax
    jz .layout
    mov rdi,rbx
    mov rsi,key_month
    call strcmp
    test rax,rax
    jz .month
    mov rdi,rbx
    mov rsi,key_day
    call strcmp
    test rax,rax
    jz .day
    xor eax,eax
    jmp .done
.layout:
    test qword [layout_flags],1
    jnz .bad
    or qword [layout_flags],1
    xor ebx,ebx
.layout_loop:
    mov rdi,r12
    mov rsi,[layout_names+rbx*8]
    call strcmp
    test rax,rax
    jz .layout_value
    inc ebx
    cmp ebx,3
    jb .layout_loop
    jmp .bad
.layout_value:
    mov [view_layout],rbx
    jmp .ok
.month:
    test qword [layout_flags],2
    jnz .bad
    or qword [layout_flags],2
    mov rdi,r12
    call strlen
    cmp rax,7
    jne .bad
    mov rdi,month_date
    mov rsi,r12
    mov ecx,7
    rep movsb
    mov dword [rdi],'-01'
    mov rdi,month_date
    call parse_date
    test rax,rax
    js .bad
    mov rdi,view_month
    mov rsi,r12
    mov ecx,8
    rep movsb
    jmp .ok
.day:
    test qword [layout_flags],4
    jnz .bad
    or qword [layout_flags],4
    xor eax,eax
    cmp byte [r12],0
    je .day_value
    mov rdi,r12
    call parse_date
    test rax,rax
    jle .bad
.day_value:
    mov [view_day],rax
.ok:
    mov eax,1
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r12
    pop rbx
    ret

prepare_layout:
    push rbx
    push r12
    cmp qword [view_filter],7
    je .list
    cmp qword [query_status],3
    jne .month
.list:
    mov qword [view_layout],0
.month:
    mov rdi,month_date
    mov rsi,view_month
    mov ecx,7
    rep movsb
    mov dword [rdi],'-01'
    mov rdi,month_date
    call parse_date
    test rax,rax
    js .bad
    mov [month_start],rax
    xor ebx,ebx
    xor ecx,ecx
.year:
    imul ebx,10
    movzx eax,byte [view_month+rcx]
    sub eax,'0'
    add ebx,eax
    inc ecx
    cmp ecx,4
    jb .year
    movzx r12d,byte [view_month+5]
    sub r12d,'0'
    imul r12d,10
    movzx eax,byte [view_month+6]
    sub eax,'0'
    add r12d,eax
    inc r12
    cmp r12,13
    jne .next_month
    mov r12d,1
    inc rbx
.next_month:
    mov rax,253402300800
    cmp rbx,10000
    je .end
    mov rdi,rbx
    mov rsi,r12
    mov edx,1
    call date_epoch
.end:
    mov [month_end],rax
    xor eax,eax
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r12
    pop rbx
    ret

emit_layout:
    mov rax,[view_layout]
    mov rsi,[layout_names+rax*8]
    jmp copy_string
emit_list_class:
    mov rsi,task_list
    cmp qword [view_layout],1
    jne .emit
    mov rsi,board_list
.emit:
    jmp copy_string
emit_mutation_prefix:
    cmp qword [view_layout],1
    jne .done
    mov rsi,board_prefix
    jmp copy_string
.done:
    ret
render_board_start:
    push rsi
    mov rsi,board_open
    call copy_string
    pop rax
    mov rsi,[stage_names+rax*8]
    call copy_string
    mov rsi,board_tasks
    jmp copy_string
render_board_end:
    mov rsi,board_close
    jmp copy_string

append_filters:
    mov rsi,f_prefix
    call copy_string
    call emit_filter
    mov rsi,sort_prefix
    call copy_string
    call emit_sort
    mov rsi,q_prefix
    call copy_string
    mov rsi,view_query
    call emit_url_text
    mov rsi,project_prefix
    call copy_string
    mov rsi,view_project
    call emit_url_text
    mov rsi,tag_prefix
    call copy_string
    mov rsi,view_tag
    jmp emit_url_text

render_calendar_panel:
    cmp qword [view_layout],2
    je .render
    ret
.render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rsi,panel_open
    call copy_string
    mov rsi,view_month
    call copy_string
    mov rsi,panel_nav
    call copy_string
    cmp qword [month_start],0
    je .next_link
    mov rsi,prev_open
    call copy_string
    push rdi
    mov rdi,[month_start]
    sub rdi,86400
    mov rsi,date_buf
    call format_utc
    pop rdi
    mov byte [date_buf+7],0
    mov rsi,date_buf
    call copy_string
    call append_filters
    mov rsi,prev_close
    call copy_string
.next_link:
    mov rax,253402214400
    cmp [month_end],rax
    ja .grid
    mov rsi,next_open
    call copy_string
    push rdi
    mov rdi,[month_end]
    mov rsi,date_buf
    call format_utc
    pop rdi
    mov byte [date_buf+7],0
    mov rsi,date_buf
    call copy_string
    call append_filters
    mov rsi,next_close
    call copy_string
.grid:
    mov rsi,month_form
    call render_template
    mov rax,[month_start]
    xor edx,edx
    mov ecx,86400
    div rcx
    add rax,3
    xor edx,edx
    mov ecx,7
    div rcx
    mov r12,rdx ; Monday-based first weekday
    mov rax,[month_end]
    sub rax,[month_start]
    xor edx,edx
    mov ecx,86400
    div rcx
    mov r13,rax ; days in month
    xor r14d,r14d
.cell:
    mov rbx,r14
    sub rbx,r12
    js .blank
    cmp rbx,r13
    jae .blank
    imul r15,rbx,86400
    add r15,[month_start]
    inc rbx
    test r15,r15
    jz .epoch
    xor r9d,r9d
    mov r8,view_rows
    mov rcx,[view_count]
.count:
    test rcx,rcx
    jz .cell_start
    mov rax,[r8]
    cmp [rax+T_DUE],r15
    jne .next_task
    inc r9
.next_task:
    add r8,8
    dec rcx
    jmp .count
.cell_start:
    mov [cell_total],r9
    push rdi
    mov rdi,r15
    mov rsi,date_buf
    call format_utc
    pop rdi
    mov byte [date_buf+10],0
    mov rsi,cell_open
    call copy_string
    mov rsi,date_buf
    call copy_string
    mov rsi,cell_count
    call copy_string
    mov rax,[cell_total]
    call emit_number
    mov rsi,cell_href
    call copy_string
    mov rsi,date_buf
    call copy_string
    call append_filters
    mov rsi,cell_title
    call copy_string
    mov rax,rbx
    call emit_number
    mov rsi,cell_number
    call copy_string
    mov rax,[cell_total]
    call emit_number
    mov rsi,cell_close
    call copy_string
    jmp .next_cell
.epoch:
    mov rsi,epoch_cell
    call copy_string
    jmp .next_cell
.blank:
    mov rsi,blank
    call copy_string
.next_cell:
    inc r14
    cmp r14,42
    jb .cell
    mov rsi,panel_close
    call copy_string
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
