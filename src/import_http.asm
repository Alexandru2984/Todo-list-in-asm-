%include "src/defs.inc"
%include "src/import.inc"
DEFAULT ABS
extern request_body, strcmp, copy_string, html_escape, emit_number, format_utc
extern import_json, import_csv, import_lines, import_count, import_live, import_trash, import_tasks
extern import_apply, import_capacity, lock_user_file, unlock_user_file, load_todos
extern todo_count, res_buf, send_private_html, redirect_app, priority_names

global handle_import
section .data
    key_payload db 'payload',0
    key_format db 'format',0
    key_mode db 'mode',0
    key_confirmed db 'confirmed',0
    auto db 'auto',0
    json db 'json',0
    csv db 'csv',0
    lines db 'lines',0
    formats dq auto,json,csv,lines
    merge db 'merge',0
    replace db 'replace',0
    modes dq merge,replace
    preview_head db '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><meta name="color-scheme" content="light dark"><title>Review import — ASM TODO</title><link rel="stylesheet" href="/app.css"><script src="/app.js" defer></script></head><body data-page="import"><main class="native-import"><a href="/app#import-panel">Back to workspace</a><h1>Review your import</h1>',0
    capacity_notice db '<p class="notice" role="alert">This workspace cannot fit the import or has exhausted its task IDs. Adjust the file or workspace, then preview again. Your payload is preserved below.</p>',0
    storage_notice db '<p class="notice" role="alert">Saving was not confirmed. Check your workspace before retrying: importing twice can create duplicates. Your payload is preserved below.</p>',0
    summary_open db '<p><strong data-import-live="',0
    summary_live db '">',0
    summary_trash db '</strong> live tasks and <strong data-import-trash="',0
    summary_end db '</strong> trash entries. Preview shows the first 20 items. New task IDs are assigned and relationships remapped within this file.</p><p>Workspace loaded for this preview: <strong>',0
    summary_current db '</strong> live tasks. Merge keeps existing tasks; replace removes the current task set. The confirmed import is one reversible undo step.</p><ol class="import-preview-list">',0
    item_open db '<li><strong>',0
    item_meta db '</strong><span>',0
    item_done db 'Done · ',0
    item_active db 'Active · ',0
    item_trash db 'Trash · ',0
    item_due db ' · due ',0
    item_close db '</span></li>',0
    form_open db '</ol><form action="/import" method="post"><input type="hidden" name="confirmed" value="1"><input type="hidden" name="format" value="',0
    form_mode db '"><input type="hidden" name="mode" value="',0
    form_payload db '"><label for="import-review-payload">Reviewed payload</label><textarea id="import-review-payload" name="payload" readonly rows="10" spellcheck="false">',0
    form_confirm db '</textarea><p>Mode: <strong>',0
    form_close db '</strong>. Confirming revalidates this payload under the write lock before publishing one atomic snapshot.</p><div class="dialog-actions"><a class="secondary-button" href="/app">Return to workspace</a><button class="primary-button">Confirm import</button></div></form></main></body></html>',0
section .bss
    original resb IMPORT_MAX+9
    scratch resb IMPORT_MAX+9
    payload_length resq 1
    selected_format resq 1
    detected_format resq 1
    selected_mode resq 1
    form_flags resq 1
    small_value resb 32
    date_buf resb 24
section .text
; Lossless form decoder. JSON/CSV separators, whitespace and escaped controls
; remain visible to the format parser; NUL and malformed escapes fail closed.
; rdi=input, rsi=output, rdx=byte cap -> rax=length or -400/-413.
decode_import_value:
    mov r8,rdi
    mov r9,rsi
    mov r10,rsi
    mov r11,rdx
.loop:
    mov al,[r8]
    inc r8
    test al,al
    jz .end
    cmp al,'+'
    jne .percent
    mov al,' '
    jmp .put
.percent:
    cmp al,'%'
    jne .put
    mov al,[r8]
    inc r8
    call hex
    test eax,eax
    js .bad
    mov edx,eax
    shl edx,4
    mov al,[r8]
    inc r8
    call hex
    test eax,eax
    js .bad
    or eax,edx
.put:
    test al,al
    jz .bad
    mov rcx,r9
    sub rcx,r10
    cmp rcx,r11
    jae .large
    mov [r9],al
    inc r9
    jmp .loop
.end:
    mov byte [r9],0
    mov rax,r9
    sub rax,r10
    ret
.bad:
    mov rax,-400
    ret
.large:
    mov rax,-413
    ret
hex:
    movzx eax,al
    sub eax,'0'
    cmp eax,9
    jbe .done
    add eax,'0'
    or al,32
    sub eax,'a'
    cmp eax,5
    ja .bad
    add eax,10
.done:
    ret
.bad:
    mov rax,-1
    ret

parse_import_form:
    push rbx
    push r12
    push r13
    push r14
    mov qword [form_flags],0
    mov qword [selected_format],0
    mov qword [selected_mode],0
    mov qword [payload_length],0
    mov byte [original],0
    mov rbx,[request_body]
.field:
    cmp byte [rbx],0
    je .finish
    mov r12,rbx
.end_scan:
    cmp byte [r12],0
    je .end_field
    cmp byte [r12],'&'
    je .end_field
    inc r12
    jmp .end_scan
.end_field:
    mov r13,r12
    cmp byte [r12],0
    je .split
    inc r13
    cmp byte [r13],0
    je .bad
    mov byte [r12],0
.split:
    mov r14,rbx
.eq:
    cmp byte [r14],0
    je .bad
    cmp byte [r14],'='
    je .value
    inc r14
    jmp .eq
.value:
    mov byte [r14],0
    inc r14
    mov rdi,rbx
    mov rsi,key_payload
    call strcmp
    test rax,rax
    jz .payload
    mov rdi,rbx
    mov rsi,key_format
    call strcmp
    test rax,rax
    jz .format
    mov rdi,rbx
    mov rsi,key_mode
    call strcmp
    test rax,rax
    jz .mode
    mov rdi,rbx
    mov rsi,key_confirmed
    call strcmp
    test rax,rax
    jnz .bad
    test qword [form_flags],8
    jnz .bad
    or qword [form_flags],8
    call .decode_small
    test rax,rax
    js .done
    cmp word [small_value],'1'
    jne .bad
    jmp .next
.payload:
    test qword [form_flags],1
    jnz .bad
    or qword [form_flags],1
    mov rdi,r14
    mov rsi,original
    mov edx,IMPORT_MAX
    call decode_import_value
    test rax,rax
    js .done
    mov [payload_length],rax
    jmp .next
.format:
    test qword [form_flags],2
    jnz .bad
    or qword [form_flags],2
    call .decode_small
    test rax,rax
    js .done
    xor r14d,r14d
.format_loop:
    mov rdi,small_value
    mov rsi,[formats+r14*8]
    call strcmp
    test rax,rax
    jz .format_value
    inc r14
    cmp r14,4
    jb .format_loop
    jmp .bad
.format_value:
    mov [selected_format],r14
    jmp .next
.mode:
    test qword [form_flags],4
    jnz .bad
    or qword [form_flags],4
    call .decode_small
    test rax,rax
    js .done
    xor r14d,r14d
.mode_loop:
    mov rdi,small_value
    mov rsi,[modes+r14*8]
    call strcmp
    test rax,rax
    jz .mode_value
    inc r14
    cmp r14,2
    jb .mode_loop
    jmp .bad
.mode_value:
    mov [selected_mode],r14
.next:
    mov rbx,r13
    jmp .field
.finish:
    test qword [form_flags],1
    jz .bad
    cmp qword [selected_format],3
    jne .valid
    cmp qword [selected_mode],0
    jne .bad
.valid:
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
.decode_small:
    mov rdi,r14
    mov rsi,small_value
    mov edx,31
    jmp decode_import_value

parse_payload:
    mov rdi,scratch
    mov rsi,original
    mov rcx,[payload_length]
    inc rcx
    rep movsb
    mov rax,[selected_format]
    test rax,rax
    jnz .detected
    mov rdi,scratch
    cmp word [rdi],0xbbef
    jne .space
    cmp byte [rdi+2],0xbf
    jne .space
    add rdi,3
.space:
    mov al,[rdi]
    cmp al,' '
    je .skip
    cmp al,9
    je .skip
    cmp al,10
    je .skip
    cmp al,13
    jne .guess
.skip:
    inc rdi
    jmp .space
.guess:
    mov eax,2
    cmp byte [rdi],'{'
    jne .detected
    mov eax,1
.detected:
    mov [detected_format],rax
    mov rdi,scratch
    cmp rax,1
    je import_json
    cmp rax,3
    je import_lines
    jmp import_csv

; fd=rdi, apply flag=rsi. Negative status returns to the main error handler.
handle_import:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13,rsi
    call parse_import_form
    test rax,rax
    js .done
    test r13,r13
    jz .preview_confirmation
    test qword [form_flags],8
    jz .bad
    jmp .parse
.preview_confirmation:
    test qword [form_flags],8
    jnz .bad
.parse:
    call parse_payload
    test rax,rax
    js .done
    call lock_user_file
    test rax,rax
    js .done
    call load_todos
    test rax,rax
    js .unlock
    mov rdi,[selected_mode]
    test r13,r13
    jz .capacity
    call import_apply
    jmp .result
.capacity:
    call import_capacity
.result:
    mov r14,rax
    call unlock_user_file
    test r14,r14
    js .retry
    test r13,r13
    jz .preview
    call redirect_app
    xor eax,eax
    jmp .done
.preview:
    mov edi,200
    call render_preview
    xor eax,eax
    jmp .done
.retry:
    cmp r14,-409
    je .retry_preview
    cmp r14,-507
    jne .return_error
.retry_preview:
    mov rdi,r14
    neg rdi
    call render_preview
    xor eax,eax
    jmp .done
.return_error:
    mov rax,r14
    jmp .done
.unlock:
    push rax
    call unlock_user_file
    pop rax
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

render_preview:
    mov r15,rdi
    mov rdi,res_buf
    mov rsi,preview_head
    call copy_string
    cmp r15,409
    je .capacity
    cmp r15,507
    jne .summary
    mov rsi,storage_notice
    call copy_string
    jmp .summary
.capacity:
    mov rsi,capacity_notice
    call copy_string
.summary:
    mov rsi,summary_open
    call copy_string
    mov rax,[import_live]
    call emit_number
    mov rsi,summary_live
    call copy_string
    mov rax,[import_live]
    call emit_number
    mov rsi,summary_trash
    call copy_string
    mov rax,[import_trash]
    call emit_number
    mov rsi,summary_live
    call copy_string
    mov rax,[import_trash]
    call emit_number
    mov rsi,summary_end
    call copy_string
    mov rax,[todo_count]
    call emit_number
    mov rsi,summary_current
    call copy_string
    mov rbx,import_tasks
    mov r14,[import_count]
    cmp r14,20
    jbe .rows
    mov r14d,20
.rows:
    test r14,r14
    jz .form
    mov rsi,item_open
    call copy_string
    lea rsi,[rbx+17]
    call html_escape
    mov rsi,item_meta
    call copy_string
    mov rsi,item_active
    cmp byte [rbx+8],0
    je .status
    mov rsi,item_done
    cmp byte [rbx+8],1
    je .status
    mov rsi,item_trash
.status:
    call copy_string
    mov rax,[rbx+T_PRIORITY]
    mov rsi,[priority_names+rax*8]
    call copy_string
    cmp qword [rbx+T_DUE],0
    je .row_end
    mov rsi,item_due
    call copy_string
    push rdi
    mov rdi,[rbx+T_DUE]
    mov rsi,date_buf
    call format_utc
    pop rdi
    mov byte [date_buf+10],0
    mov rsi,date_buf
    call copy_string
.row_end:
    mov rsi,item_close
    call copy_string
    add rbx,TASK_SIZE
    dec r14
    jmp .rows
.form:
    mov rsi,form_open
    call copy_string
    mov rax,[detected_format]
    mov rsi,[formats+rax*8]
    call copy_string
    mov rsi,form_mode
    call copy_string
    mov rax,[selected_mode]
    mov rsi,[modes+rax*8]
    call copy_string
    mov rsi,form_payload
    call copy_string
    mov rsi,original
    call html_escape
    mov rsi,form_confirm
    call copy_string
    mov rax,[selected_mode]
    mov rsi,[modes+rax*8]
    call copy_string
    mov rsi,form_close
    call copy_string
    mov rdx,rdi
    sub rdx,res_buf
    mov rdi,r12
    mov rsi,res_buf
    mov rcx,r15
    call send_private_html
    ret
