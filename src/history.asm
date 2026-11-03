%include "src/defs.inc"
DEFAULT ABS
extern todos, todo_count, lookup_array, save_snapshot, format_line, line_buf
extern format_metadata, validate_metadata_graph, split_field, parse_uint
extern itoa, write_all, copy_string, emit_number, format_utc

global history_reset, history_prepare, history_parse, history_validate, history_write
 global history_complete, history_clear_undo, undo_workspace, history_event
 global undo_todos, undo_mode, metrics, undo_metrics, render_history
section .data
    undo_prefix db '#undo=',0
    previous_prefix db 'U|'
    op_add db 'Added',0
    op_edit db 'Edited',0
    op_complete db 'Completed',0
    op_reopen db 'Reopened',0
    op_trash db 'Moved to trash',0
    op_clear db 'Cleared completed tasks',0
    op_restore db 'Restored from trash',0
    op_purge db 'Permanently removed trash',0
    op_import db 'Imported tasks',0
    op_stage db 'Changed workflow stage',0
    op_undo db 'Undid the last change',0
    op_redo db 'Redid the last change',0
    op_names dq op_add,op_edit,op_complete,op_reopen,op_trash,op_clear
             dq op_restore,op_purge,op_import,op_stage,op_undo,op_redo
    history_open db '<section class="workspace-tools history-panel" aria-labelledby="history-heading"><h2 id="history-heading">Recent changes</h2><div class="export-actions">',0
    undo_form db '<form method="post" action="/undo"><button class="secondary-button"',0
    redo_form db '<form method="post" action="/redo"><button class="secondary-button"',0
    disabled db ' disabled',0
    undo_close db '>Undo last change</button></form>',0
    redo_close db '>Redo last change</button></form>',0
    activity_open db '</div><p>One reversible workspace change. Permanent purge clears undo.</p><ol class="activity-list">',0
    activity_row db '<li><time>',0
    activity_op db '</time> <span>',0
    activity_id db ' · task #',0
    activity_close db '</span></li>',0
    history_close db '</ol></section>',0
section .bss
    undo_todos resb SLOT_MAX*TASK_SIZE
    metrics resq 90*2 ; day/count, indexed by day modulo 90
    undo_metrics resq 90*2
    events resq 20*3 ; epoch/op/id, oldest first
    event_count resq 1
    undo_mode resq 1 ; 0 unavailable, 1 undo, 2 redo
    undo_seen resq 1
    parse_fields resq 3
    history_buffer resb 1024
    history_stamp resb 24
section .text
history_reset:
    mov rdi,undo_todos
    mov ecx,SLOT_MAX*TASK_SIZE
    xor eax,eax
    rep stosb
    mov rdi,metrics
    mov ecx,(90*2*2+20*3+3)*8
    rep stosb ; contiguous metrics, undo metrics, events and counters
    ret

; Preserve caller's in-flight slot/title registers while capturing prior state.
history_prepare:
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    push r9
    push r10
    push r11
    push rbx
    mov rbx,rdi ; opcode
    mov r8,rsi ; affected ID
    mov rsi,todos
    mov rdi,undo_todos
    mov ecx,SLOT_MAX*TASK_SIZE/8
    rep movsq
    mov rsi,metrics
    mov rdi,undo_metrics
    mov ecx,90*2
    rep movsq
    mov qword [undo_mode],1
    mov rdi,rbx
    mov rsi,r8
    call history_event
    pop rbx
    pop r11
    pop r10
    pop r9
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    xor eax,eax
    ret

; rdi=opcode, rsi=ID (zero for bulk actions). Only bounded numeric data persists.
history_event:
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
    cmp qword [event_count],20
    jb .append
    mov rsi,events+24
    mov rdi,events
    mov ecx,19*3
    rep movsq
    mov qword [event_count],19
.append:
    mov rax,[event_count]
    imul rax,24
    lea r8,[events+rax]
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    mov [r8],rax
    mov [r8+8],rbx
    mov [r8+16],r12
    inc qword [event_count]
    pop r12
    pop rbx
    ret

history_complete:
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    xor edx,edx
    mov ecx,86400
    div rcx
    mov r8,rax
    xor edx,edx
    mov ecx,90
    div rcx
    shl rdx,4
    lea rdi,[metrics+rdx]
    cmp [rdi],r8
    je .increment
    mov [rdi],r8
    mov qword [rdi+8],0
.increment:
    cmp qword [rdi+8],1000000000
    jae .done
    inc qword [rdi+8]
.done:
    ret

history_clear_undo:
    mov qword [undo_mode],0
    mov rdi,undo_todos
    xor eax,eax
    mov ecx,SLOT_MAX*TASK_SIZE/8
    rep stosq
    mov rdi,undo_metrics
    mov ecx,90*2
    rep stosq
    ret

; rdi=line. 1 known valid, 0 unknown, -500 malformed.
history_parse:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    cmp dword [rbx],'#und'
    jne .record
    cmp word [rbx+4],'o='
    jne .bad
    cmp qword [undo_seen],0
    jne .bad
    lea rdi,[rbx+6]
    call parse_uint
    cmp rax,2
    ja .bad
    mov [undo_mode],rax
    mov qword [undo_seen],1
    jmp .ok
.record:
    cmp qword [undo_seen],1
    jne .unknown
    cmp byte [rbx+1],'|'
    jne .unknown
    movzx r12d,byte [rbx]
    cmp r12b,'E'
    je .fields
    cmp r12b,'M'
    je .fields
    cmp r12b,'N'
    jne .unknown
    cmp qword [undo_mode],0
    je .bad
.fields:
    lea rbx,[rbx+2]
    mov [parse_fields],rbx
    mov rdi,rbx
    mov dl,'|'
    call split_field
    test rax,rax
    jz .bad
    mov [parse_fields+8],rax
    cmp r12b,'E'
    jne .two
    mov rdi,rax
    mov dl,'|'
    call split_field
    test rax,rax
    jz .bad
    mov [parse_fields+16],rax
    mov r13d,3
    jmp .numbers
.two:
    mov r13d,2
.numbers:
    xor ebx,ebx
.number:
    mov rdi,[parse_fields+rbx*8]
    call parse_uint
    test rax,rax
    js .bad
    mov [parse_fields+rbx*8],rax
    inc ebx
    cmp rbx,r13
    jb .number
    cmp r12b,'E'
    jne .metric
    cmp qword [event_count],20
    jae .bad
    mov rax,253402300799
    cmp [parse_fields],rax
    ja .bad
    mov rax,[parse_fields+8]
    test rax,rax
    jz .bad
    cmp rax,12
    ja .bad
    mov rax,[parse_fields+16]
    mov rdx,9223372036854775807
    cmp rax,rdx
    jae .bad
    mov rax,[event_count]
    imul rax,24
    lea rdi,[events+rax]
    mov rsi,parse_fields
    mov ecx,3
    rep movsq
    inc qword [event_count]
    jmp .ok
.metric:
    mov rax,[parse_fields]
    cmp rax,2932896
    ja .bad
    cmp qword [parse_fields+8],0
    je .bad
    cmp qword [parse_fields+8],1000000000
    ja .bad
    xor edx,edx
    mov ecx,90
    div rcx
    shl rdx,4
    lea rdi,[metrics+rdx]
    cmp r12b,'N'
    jne .metric_slot
    lea rdi,[undo_metrics+rdx]
.metric_slot:
    cmp qword [rdi+8],0
    jne .bad
    mov rax,[parse_fields]
    mov [rdi],rax
    mov rax,[parse_fields+8]
    mov [rdi+8],rax
.ok:
    mov eax,1
    jmp .done
.unknown:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r13
    pop r12
    pop rbx
    ret

history_validate:
    push rbx
    push r12
    cmp qword [undo_seen],1
    jne .bad
    mov rbx,undo_todos
    mov ecx,SLOT_MAX
    xor r8d,r8d
    xor r9d,r9d
.count:
    cmp qword [rbx],0
    je .next
    cmp qword [undo_mode],0
    je .bad
    cmp byte [rbx+8],2
    je .trash
    inc r8
    jmp .next
.trash:
    inc r9
.next:
    add rbx,TASK_SIZE
    dec ecx
    jnz .count
    cmp r8,TASK_MAX
    ja .bad
    cmp r9,200
    ja .bad
    mov qword [lookup_array],undo_todos
    mov rdi,undo_todos
    call validate_metadata_graph
    mov qword [lookup_array],todos
    test rax,rax
    js .bad
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r12
    pop rbx
    ret

; Small checked numeric line writer used for headers/events/metric buckets.
; fd=r12; prefix byte=al, count=ecx, qword vector=rsi.
write_numbers:
    push rbx
    push r13
    push r14
    mov rbx,rsi
    mov r13,rcx
    mov rdi,history_buffer
    stosb
    mov byte [rdi],'|'
    inc rdi
    xor r14d,r14d
.number:
    push rdi
    mov rsi,rdi
    mov rdi,[rbx+r14*8]
    call itoa
    pop rdi
    add rdi,rax
    inc r14
    cmp r14,r13
    jae .end
    mov byte [rdi],'|'
    inc rdi
    jmp .number
.end:
    mov byte [rdi],10
    lea rdx,[rdi+1]
    sub rdx,history_buffer
    mov rdi,r12
    mov rsi,history_buffer
    call write_all
    pop r14
    pop r13
    pop rbx
    ret

history_write:
    push rbx
    push r12
    push r13
    mov r12,rdi
    mov rdi,history_buffer
    mov rsi,undo_prefix
    call copy_string
    mov rsi,rdi
    mov rdi,[undo_mode]
    call itoa
    add rsi,rax
    mov byte [rsi],10
    lea rdx,[rsi+1]
    sub rdx,history_buffer
    mov rdi,r12
    mov rsi,history_buffer
    call write_all
    test rax,rax
    js .done
    xor r13d,r13d
.events:
    cmp r13,[event_count]
    jae .metrics
    imul rax,r13,24
    lea rsi,[events+rax]
    mov al,'E'
    mov ecx,3
    call write_numbers
    test rax,rax
    js .done
    inc r13
    jmp .events
.metrics:
    mov rbx,metrics
    mov r13d,90
.metric:
    cmp qword [rbx+8],0
    je .next_metric
    mov al,'M'
    mov rsi,rbx
    mov ecx,2
    call write_numbers
    test rax,rax
    js .done
.next_metric:
    add rbx,16
    dec r13
    jnz .metric
    cmp qword [undo_mode],0
    je .ok
    mov rbx,undo_metrics
    mov r13d,90
.undo_metric:
    cmp qword [rbx+8],0
    je .next_undo_metric
    mov al,'N'
    mov rsi,rbx
    mov ecx,2
    call write_numbers
    test rax,rax
    js .done
.next_undo_metric:
    add rbx,16
    dec r13
    jnz .undo_metric
    mov rbx,undo_todos
    mov r13d,SLOT_MAX
.previous:
    cmp qword [rbx],0
    je .next_previous
    mov rdi,r12
    mov rsi,previous_prefix
    mov edx,2
    call write_all
    test rax,rax
    js .done
    mov rdi,rbx
    call format_line
    mov rdx,rax
    mov rsi,line_buf
    mov rdi,r12
    call write_all
    test rax,rax
    js .done
    mov rdi,rbx
    mov rsi,line_buf
    call format_metadata
    mov byte [line_buf],'V'
    mov rdx,rax
    mov rsi,line_buf
    mov rdi,r12
    call write_all
    test rax,rax
    js .done
.next_previous:
    add rbx,TASK_SIZE
    dec r13
    jnz .previous
.ok:
    xor eax,eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

undo_workspace:
    cmp rdi,[undo_mode]
    jne .conflict
    test rdi,rdi
    jz .conflict
    push rbx
    mov rbx,rdi
    mov rsi,todos
    mov rdi,undo_todos
    mov ecx,SLOT_MAX*TASK_SIZE/8
.swap:
    mov rax,[rsi]
    mov rdx,[rdi]
    mov [rsi],rdx
    mov [rdi],rax
    add rsi,8
    add rdi,8
    loop .swap
    mov rsi,metrics
    mov rdi,undo_metrics
    mov ecx,90*2
.swap_metrics:
    mov rax,[rsi]
    mov rdx,[rdi]
    mov [rsi],rdx
    mov [rdi],rax
    add rsi,8
    add rdi,8
    loop .swap_metrics
    mov eax,3
    sub rax,rbx
    mov [undo_mode],rax
    lea rdi,[rbx+10]
    xor esi,esi
    call history_event
    call save_snapshot
    pop rbx
    ret
.conflict:
    mov rax,-409
    ret

render_history:
    push rbx
    mov rsi,history_open
    call copy_string
    mov rsi,undo_form
    call copy_string
    cmp qword [undo_mode],1
    je .undo
    mov rsi,disabled
    call copy_string
.undo:
    mov rsi,undo_close
    call copy_string
    mov rsi,redo_form
    call copy_string
    cmp qword [undo_mode],2
    je .redo
    mov rsi,disabled
    call copy_string
.redo:
    mov rsi,redo_close
    call copy_string
    mov rsi,activity_open
    call copy_string
    mov rbx,[event_count]
.row:
    test rbx,rbx
    jz .close
    dec rbx
    mov rsi,activity_row
    call copy_string
    push rdi
    imul rax,rbx,24
    mov rdi,[events+rax]
    mov rsi,history_stamp
    call format_utc
    pop rdi
    mov rsi,history_stamp
    call copy_string
    mov rsi,activity_op
    call copy_string
    imul rax,rbx,24
    mov rax,[events+rax+8]
    mov rsi,[op_names+rax*8-8]
    call copy_string
    imul rax,rbx,24
    cmp qword [events+rax+16],0
    je .end_row
    mov rsi,activity_id
    call copy_string
    imul rax,rbx,24
    mov rax,[events+rax+16]
    call emit_number
.end_row:
    mov rsi,activity_close
    call copy_string
    jmp .row
.close:
    mov rsi,history_close
    call copy_string
    pop rbx
    ret
