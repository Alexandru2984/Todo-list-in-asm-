%include "src/defs.inc"
DEFAULT ABS
extern metrics, copy_string, emit_number, format_utc

global export_stats_svg, render_insights
section .data
    panel_open db '<section class="insights-panel" aria-labelledby="insights-heading"><h2 id="insights-heading">Your momentum</h2><div class="insight-grid"><div><strong data-insight="week">',0
    week_close db '</strong><span>Completed in 7 days</span></div><div><strong data-insight="month">',0
    month_close db '</strong><span>Completed in 30 days</span></div><div><strong data-insight="streak">',0
    streak_close db '</strong><span>Current streak · days</span></div></div>',0
    empty_activity db '<p class="query-hint">Complete your first task to start a private activity chart. Dates and streaks use UTC.</p></section>',0
    chart_close db '<img class="activity-chart" src="/stats.svg" width="620" height="150" alt="Daily task completions over the last thirty UTC days"><p class="query-hint">Workspace activity in UTC. Undo reverses its completion count; reopening keeps past activity. A streak can end today or yesterday.</p></section>',0
    svg_open db '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 620 150" role="img" aria-labelledby="chart-title"><title id="chart-title">Task completions over thirty UTC days</title><path d="M5 131H615" stroke="#729254"/><g fill="#729254">',0
    rect_open db '<rect x="',0
    rect_y db '" y="',0
    rect_height db '" width="14" height="',0
    rect_day db '" data-day="',0
    rect_count db '" data-completions="',0
    rect_title db '"><title>',0
    title_count db ': ',0
    rect_close db ' completions</title></rect>',0
    svg_close db '</g></svg>',10,0
section .bss
    today resq 1
    total_week resq 1
    total_month resq 1
    current_streak resq 1
    max_count resq 1
    counts resq 30
    date_buf resb 24
section .text
; rdi=UTC day -> rax=count. Explicit ring day prevents stale bucket reuse.
day_count:
    mov r8,rdi
    mov rax,rdi
    xor edx,edx
    mov ecx,90
    div rcx
    shl rdx,4
    xor eax,eax
    cmp [metrics+rdx],r8
    jne .done
    mov rax,[metrics+rdx+8]
.done:
    ret

compute_insights:
    push rbx
    push r12
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    xor edx,edx
    mov ecx,86400
    div rcx
    mov [today],rax
    mov qword [total_week],0
    mov qword [total_month],0
    mov qword [current_streak],0
    mov qword [max_count],1
    xor ebx,ebx
.day:
    mov rdi,[today]
    sub rdi,29
    add rdi,rbx
    call day_count
    mov [counts+rbx*8],rax
    add [total_month],rax
    cmp rbx,23
    jb .max
    add [total_week],rax
.max:
    cmp rax,[max_count]
    jbe .next
    mov [max_count],rax
.next:
    inc rbx
    cmp rbx,30
    jb .day
    mov r12,[today]
    mov rdi,r12
    call day_count
    test rax,rax
    jnz .streak
    dec r12
.streak:
    mov rdi,r12
    call day_count
    test rax,rax
    jz .done
    inc qword [current_streak]
    dec r12
    cmp qword [current_streak],90
    jb .streak
.done:
    pop r12
    pop rbx
    ret

render_insights:
    push rdi
    call compute_insights
    pop rdi
    mov rsi,panel_open
    call copy_string
    mov rax,[total_week]
    call emit_number
    mov rsi,week_close
    call copy_string
    mov rax,[total_month]
    call emit_number
    mov rsi,month_close
    call copy_string
    mov rax,[current_streak]
    call emit_number
    mov rsi,streak_close
    call copy_string
    mov rsi,empty_activity
    cmp qword [total_month],0
    je .emit
    mov rsi,chart_close
.emit:
    jmp copy_string

export_stats_svg:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    push rdi
    call compute_insights
    pop rdi
    mov rsi,svg_open
    call copy_string
    xor ebx,ebx
.bar:
    mov rax,[counts+rbx*8]
    imul rax,110
    xor edx,edx
    div qword [max_count]
    mov r13,rax ; height
    mov rsi,rect_open
    call copy_string
    imul rax,rbx,20
    add rax,10
    call emit_number
    mov rsi,rect_y
    call copy_string
    mov eax,130
    sub rax,r13
    call emit_number
    mov rsi,rect_height
    call copy_string
    mov rax,r13
    call emit_number
    mov rsi,rect_day
    call copy_string
    push rdi
    mov rdi,[today]
    sub rdi,29
    add rdi,rbx
    imul rdi,86400
    mov rsi,date_buf
    call format_utc
    pop rdi
    mov byte [date_buf+10],0
    mov rsi,date_buf
    call copy_string
    mov rsi,rect_count
    call copy_string
    mov rax,[counts+rbx*8]
    call emit_number
    mov rsi,rect_title
    call copy_string
    mov rsi,date_buf
    call copy_string
    mov rsi,title_count
    call copy_string
    mov rax,[counts+rbx*8]
    call emit_number
    mov rsi,rect_close
    call copy_string
    inc rbx
    cmp rbx,30
    jb .bar
    mov rsi,svg_close
    call copy_string
    mov rax,rdi
    sub rax,r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
