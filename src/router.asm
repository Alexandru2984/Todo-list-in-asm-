%include "src/defs.inc"
DEFAULT ABS
extern strlen, strcmp, strncmp, write_all, itoa, parse_uint, valid_utf8
extern append_todo, complete_todo, delete_todo, edit_todo, reopen_todo
extern get_todo_list, load_todos, clear_done_todos, lock_user_file, unlock_user_file
extern request_method, request_path, request_body
extern request_cookie, request_origin, request_host, request_site

global handle_request, current_uid, send_error, copy_string, html_escape, emit_number
extern handle_import, is_import_path
global redirect_app
global authorize_import_headers, send_private_html, res_buf
global decode_value, decode_buf, decode_stripped
extern parse_view, build_view, render_template, view_rows, view_count, format_utc
extern duplicate_todo
extern export_json, export_csv, export_stats_svg
extern reset_properties, parse_property, property_flags, property_task
extern render_properties, render_task_badges
extern undo_workspace, restore_todo, purge_todo, empty_trash
extern view_layout, render_board_start, render_board_end, emit_mutation_prefix
extern change_stage
extern task_ready
section .data
    ok db 'HTTP/1.1 200 OK',13,10,0
    see_other db 'HTTP/1.1 303 See Other',13,10,0
    common_headers db "Cache-Control: no-store, no-transform",13,10
        db "X-Content-Type-Options: nosniff",13,10
        db "Referrer-Policy: strict-origin",13,10
        db "X-Frame-Options: DENY",13,10
        db "Permissions-Policy: camera=(), microphone=(), geolocation=()",13,10
        db "Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'",13,10
        db 'Content-Type: ',0
    content_length db 13,10,'Content-Length: ',0
    header_end db 'Connection: close',13,10,13,10,0
    crlf db 13,10,0
    mime_html db 'text/html; charset=utf-8',0
    mime_text db 'text/plain; charset=utf-8',0
    mime_css db 'text/css; charset=utf-8',0
    mime_js db 'text/javascript; charset=utf-8',0
    mime_xml db 'application/xml; charset=utf-8',0
    mime_svg db 'image/svg+xml',0
    mime_json db 'application/json; charset=utf-8',0
    empty db 0
    private_headers db 'X-Robots-Tag: noindex, nofollow',13,10,0
    method_headers db 'Allow: GET, HEAD, POST',13,10,'X-Robots-Tag: noindex, nofollow',13,10,0
    board_location db 'Location: /app?layout=board',13,10,'X-Robots-Tag: noindex, nofollow',13,10,0
    board_route_prefix db '/board/',0
    start_work_path db '/start-work',0
    to_do_path db '/to-do',0
    app_location db 'Location: /app',13,10,'X-Robots-Tag: noindex, nofollow',13,10,0
    home_location db 'Location: /',13,10,0
    session_prefix db 'Location: /app',13,10,'X-Robots-Tag: noindex, nofollow',13,10,'Set-Cookie: asm_uid=',0
    session_tail db '; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000',13,10,0
    forget_headers db 'Location: /',13,10,'Set-Cookie: asm_uid=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0',13,10,0
    cookie_key db 'asm_uid=',0
    https db 'https://',0
    http db 'http://',0
    same_origin db 'same-origin',0
    fetch_none db 'none',0
    stats_path db '/stats.svg',0
    export_json_path db '/export.json',0
    export_csv_path db '/export.csv',0
    mime_csv db 'text/csv; charset=utf-8',0
    json_headers db 'X-Robots-Tag: noindex, nofollow',13,10,'Content-Disposition: attachment; filename="asm-tasks.json"',13,10,0
    csv_headers db 'X-Robots-Tag: noindex, nofollow',13,10,'Content-Disposition: attachment; filename="asm-tasks.csv"',13,10,0
    social_path db '/social-card.png',0
    mime_png db 'image/png',0
    social: incbin 'web/social-card.png'
    social_len equ $-social
    recovery_path db '/recovery',0
    recovery_headers db 'X-Robots-Tag: noindex, nofollow',13,10,'Content-Disposition: attachment; filename="asm-workspace-key.txt"',13,10,0
    draft_open db '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Draft preserved — ASM TODO</title><link rel="stylesheet" href="/app.css"></head><body><main class="native-action"><h1>Changes could not be saved</h1><p>Saving failed. Your draft is preserved below. Check the workspace before retrying an interrupted change.</p><form method="post" action="',0
    draft_add db '/add',0
    draft_edit db '/edit',0
    draft_id db '"><input type="hidden" name="id" value="',0
    draft_title db '"><label for="new-title">Task title</label><input id="new-title" name="title" required maxlength="110" value="',0
    draft_close db '"><div class="dialog-actions"><a class="secondary-button" href="/app">Check workspace</a><button class="primary-button">Try again</button></div></form></main></body></html>',0
    key_title db 'title',0
    key_id db 'id',0
    key_token db 'token',0
    health db '{"status":"ok"}',10
    health_len equ $-health
    hex_chars db '0123456789abcdef'

    home: incbin 'web/index.html'
    home_len equ $-home
    css: incbin 'web/app.css'
    css_len equ $-css
    js: incbin 'web/app.js'
    js_len equ $-js
    robots: incbin 'web/robots.txt'
    robots_len equ $-robots
    sitemap: incbin 'web/sitemap.xml'
    sitemap_len equ $-sitemap
    favicon: incbin 'web/favicon.svg'
    favicon_len equ $-favicon
    app_head: incbin 'web/app-head.html'
    db 0
    app_foot: incbin 'web/app-foot.html'
    db 0

    li_open db '<li data-id="',0
    li_ts db '" data-ts="',0
    li_active db '" data-done="0"><div class="task-copy"><span class="task-title">',0
    li_trash db '" data-done="2" class="trashed"><div class="task-copy"><span class="task-title">',0
    restore_task_open db '<form method="post" action="/restore-task"><input type="hidden" name="id" value="',0
    restore_task_close db '"><button class="secondary-button">Restore</button></form><a class="delete-button" href="/app?purge=',0
    trash_row_close db '#action-form">Purge</a></div></li>',10,0
    li_done db '" data-done="1" class="done"><div class="task-copy"><span class="task-title">',0
    li_actions db '</div><div class="task-actions">',0
    close_time db '</time>',0
    li_date db '</span><time class="task-date">',0
    menu_open db '<details class="task-menu"><summary aria-label="More task actions">&#8943;</summary><div class="task-menu-items"><a data-edit href="/app?edit=',0
    menu_edit_end db '&amp;layout={{layout}}#action-form">Edit</a>',0
    menu_subtask db '<a href="/app?newparent=',0
    menu_subtask_end db '&amp;layout={{layout}}#new-title">Add subtask</a>',0
    menu_duplicate_start db '<form method="post" action="{{mutation_prefix}}/duplicate"><input type="hidden" name="id" value="',0
    menu_duplicate_end db '"><button>Duplicate</button></form><a class="delete-button" href="/app?delete=',0
    menu_end db '&amp;layout={{layout}}#action-form">Delete</a></div></details></div></li>',10,0
    undo_path db '/undo',0
    redo_path db '/redo',0
    restore_task_path db '/restore-task',0
    purge_path db '/purge',0
    empty_trash_path db '/empty-trash',0
    duplicate_path db '/duplicate',0
    app_query db '/app?',0
    edit_open db '<button type="button" data-edit aria-label="Edit task">Edit</button>',0
    complete_open db '<form method="post" action="{{mutation_prefix}}/complete"><input type="hidden" name="id" value="',0
    reopen_open db '<form method="post" action="{{mutation_prefix}}/reopen"><input type="hidden" name="id" value="',0
    complete_close db '"><button aria-label="Complete task">Done</button></form>',0
    blocked_complete_close db '"><button aria-label="Complete task" disabled title="Complete prerequisites and subtasks first">Blocked</button></form>',0
    reopen_close db '"><button aria-label="Reopen task">Reopen</button></form>',0
    delete_open db '<form method="post" action="/delete"><input type="hidden" name="id" value="',0
    delete_close db '"><button class="delete-button" aria-label="Delete task">Delete</button></form></div></li>',10,0
    status_400 db 'HTTP/1.1 400 Bad Request',13,10,0
    error_400 db 'Invalid or incomplete request.',10
    error_400_len equ $-error_400
    status_401 db 'HTTP/1.1 401 Unauthorized',13,10,0
    error_401 db 'Open or restore a workspace first.',10
    error_401_len equ $-error_401
    status_403 db 'HTTP/1.1 403 Forbidden',13,10,0
    error_403 db 'This request must come from the same origin.',10
    error_403_len equ $-error_403
    status_404 db 'HTTP/1.1 404 Not Found',13,10,0
    error_404 db 'The requested task or page was not found.',10
    error_404_len equ $-error_404
    status_405 db 'HTTP/1.1 405 Method Not Allowed',13,10,0
    error_405 db 'This method is not allowed.',10
    error_405_len equ $-error_405
    status_409 db 'HTTP/1.1 409 Conflict',13,10,0
    error_409 db 'This change conflicts with workspace capacity, task prerequisites, a completed parent or an existing session.',10
    error_409_len equ $-error_409
    status_411 db 'HTTP/1.1 411 Length Required',13,10,0
    error_411 db 'Content-Length is required.',10
    error_411_len equ $-error_411
    status_413 db 'HTTP/1.1 413 Content Too Large',13,10,0
    error_413 db 'Ordinary requests allow 4095 bytes. Imports allow 7 MiB encoded requests and 2 MiB decoded payloads.',10
    error_413_len equ $-error_413
    status_415 db 'HTTP/1.1 415 Unsupported Media Type',13,10,0
    error_415 db 'Use application/x-www-form-urlencoded.',10
    error_415_len equ $-error_415
    status_417 db 'HTTP/1.1 417 Expectation Failed',13,10,0
    error_417 db 'Expect headers are not supported.',10
    error_417_len equ $-error_417
    status_422 db 'HTTP/1.1 422 Unprocessable Content',13,10,0
    error_422 db 'Check the title or import fields. Titles require 1 to 110 UTF-8 bytes; imports must match the supported JSON or CSV schema.',10
    error_422_len equ $-error_422
    status_500 db 'HTTP/1.1 500 Internal Server Error',13,10,0
    error_500 db 'Stored data could not be read safely. Please contact the operator.',10
    error_500_len equ $-error_500
    status_503 db 'HTTP/1.1 503 Service Unavailable',13,10,0
    error_503 db 'The workspace is temporarily unavailable. Please retry.',10
    error_503_len equ $-error_503
    status_507 db 'HTTP/1.1 507 Insufficient Storage',13,10,0
    error_507 db 'Saving failed. Your change was not confirmed; reload before retrying.',10
    error_507_len equ $-error_507
    path_0 db '/',0
    path_1 db '/app',0
    path_2 db '/app.css',0
    path_3 db '/app.js',0
    path_4 db '/robots.txt',0
    path_5 db '/sitemap.xml',0
    path_6 db '/favicon.svg',0
    path_7 db '/healthz',0
    path_8 db '/start',0
    path_9 db '/restore',0
    path_10 db '/forget',0
    path_11 db '/add',0
    path_12 db '/complete',0
    path_13 db '/reopen',0
    path_14 db '/delete',0
    path_15 db '/edit',0
    path_16 db '/clear-done',0
    board_aliases dq path_11,path_12,path_13,path_14,path_15,path_16,duplicate_path,undo_path,redo_path,start_work_path,to_do_path,0
section .bss
    current_uid resb 64
    res_buf resb RESPONSE_MAX
    hdr_buf resb 2048
    extra_buf resb 512
    number_buf resb 24
    row_date resb 24
    random_buf resb 16
    form_title resb TITLE_MAX+1
    form_token resb 64
    form_id resq 1
    decode_stripped resq 1
    return_board resq 1
    form_flags resq 1
    decode_buf resb REQUEST_MAX+1
section .text

; Copy static NUL-terminated strings, return updated rdi.
copy_string:
.loop:
    lodsb
    test al,al
    jz .done
    stosb
    jmp .loop
.done:
    ret

; fd, body, length, status, MIME, extra headers. Explicit lengths throughout.
respond:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push r9
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    mov rdi,hdr_buf
    mov rsi,r14
    call copy_string
    mov rsi,common_headers
    call copy_string
    mov rsi,r15
    call copy_string
    mov rsi,content_length
    call copy_string
    mov rsi,rdi
    mov rdi,r13
    call itoa
    lea rdi,[rsi+rax]
    mov rsi,crlf
    call copy_string
    pop rsi
    call copy_string
    mov rsi,header_end
    call copy_string
    mov rdx,rdi
    sub rdx,hdr_buf
    mov rsi,hdr_buf
    mov rdi,rbx
    call write_all
    cmp qword [request_method],3
    je .done
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call write_all
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

send_error:
    mov r10,rdi
    mov rdi,rsi
    cmp r10,400
    je .e400
    cmp r10,401
    je .e401
    cmp r10,403
    je .e403
    cmp r10,404
    je .e404
    cmp r10,405
    je .e405
    cmp r10,409
    je .e409
    cmp r10,411
    je .e411
    cmp r10,413
    je .e413
    cmp r10,415
    je .e415
    cmp r10,417
    je .e417
    cmp r10,422
    je .e422
    cmp r10,500
    je .e500
    cmp r10,503
    je .e503
    cmp r10,507
    je .e507
    jmp .e500
.e400:
    mov rsi,error_400
    mov edx,error_400_len
    mov rcx,status_400
    jmp .send
.e401:
    mov rsi,error_401
    mov edx,error_401_len
    mov rcx,status_401
    jmp .send
.e403:
    mov rsi,error_403
    mov edx,error_403_len
    mov rcx,status_403
    jmp .send
.e404:
    mov rsi,error_404
    mov edx,error_404_len
    mov rcx,status_404
    jmp .send
.e405:
    mov rsi,error_405
    mov edx,error_405_len
    mov rcx,status_405
    mov r8,mime_text
    mov r9,method_headers
    jmp respond
.e409:
    mov rsi,error_409
    mov edx,error_409_len
    mov rcx,status_409
    jmp .send
.e411:
    mov rsi,error_411
    mov edx,error_411_len
    mov rcx,status_411
    jmp .send
.e413:
    mov rsi,error_413
    mov edx,error_413_len
    mov rcx,status_413
    jmp .send
.e415:
    mov rsi,error_415
    mov edx,error_415_len
    mov rcx,status_415
    jmp .send
.e417:
    mov rsi,error_417
    mov edx,error_417_len
    mov rcx,status_417
    jmp .send
.e422:
    mov rsi,error_422
    mov edx,error_422_len
    mov rcx,status_422
    jmp .send
.e500:
    mov rsi,error_500
    mov edx,error_500_len
    mov rcx,status_500
    jmp .send
.e503:
    mov rsi,error_503
    mov edx,error_503_len
    mov rcx,status_503
    jmp .send
.e507:
    mov rsi,error_507
    mov edx,error_507_len
    mov rcx,status_507
    jmp .send
.send:
    mov r8,mime_text
    mov r9,private_headers
    jmp respond

; rdi -> exact 32 lowercase hex chars; copy to current_uid or return -400.
copy_uid:
    xor ecx,ecx
.loop:
    mov al,[rdi+rcx]
    cmp al,'0'
    jb .bad
    cmp al,'9'
    jbe .digit
    cmp al,'a'
    jb .bad
    cmp al,'f'
    ja .bad
.digit:
    inc ecx
    cmp ecx,32
    jb .loop
    cmp byte [rdi+32],0
    jne .bad
    mov rsi,rdi
    mov rdi,current_uid
    mov ecx,32
    rep movsb
    mov byte [rdi],0
    xor eax,eax
    ret
.bad:
    mov rax,-400
    ret

; Cookie parser matches only semicolon-delimited asm_uid, rejects duplicates.
parse_cookie:
    mov byte [current_uid],0
    mov r8,request_cookie
    xor r9d,r9d
.next:
    cmp byte [r8],0
    je .ok
    cmp byte [r8],' '
    je .skip
    cmp byte [r8],';'
    je .skip
    mov r10,r8
.end:
    cmp byte [r10],0
    je .match
    cmp byte [r10],';'
    je .match
    inc r10
    jmp .end
.match:
    mov rdi,r8
    mov rsi,cookie_key
    mov edx,8
    call strncmp
    test rax,rax
    jnz .advance
    inc r9
    cmp r9,1
    ja .bad
    mov rax,r10
    sub rax,r8
    cmp rax,40
    jne .bad
    mov r11b,[r10]
    mov byte [r10],0
    push r10
    push r11
    lea rdi,[r8+8]
    call copy_uid
    pop r11
    pop r10
    mov [r10],r11b
    test rax,rax
    js .bad
.advance:
    mov r8,r10
    cmp byte [r8],0
    je .ok
.skip:
    inc r8
    jmp .next
.ok:
    xor eax,eax
    ret
.bad:
    mov rax,-400
    ret

; Reject sibling-site and cross-site writes; Origin must exactly match Host.
check_origin:
    cmp byte [request_site],0
    je .origin
    mov rdi,request_site
    mov rsi,same_origin
    call strcmp
    test rax,rax
    jz .origin
    mov rdi,request_site
    mov rsi,fetch_none
    call strcmp
    test rax,rax
    jnz .bad
.origin:
    cmp byte [request_origin],0
    je .ok
    mov rdi,extra_buf
    mov rsi,https
    call copy_string
    mov rsi,request_host
    call copy_string
    mov byte [rdi],0
    mov rdi,extra_buf
    mov rsi,request_origin
    call strcmp
    test rax,rax
    jz .ok
    ; Plain HTTP is for isolated loopback development only.
    mov rdi,request_host
    cmp dword [rdi],'127.'
    jne .localhost
    cmp dword [rdi+4],'0.0.'
    jne .bad
    cmp word [rdi+8],'1:'
    je .local
    cmp word [rdi+8],'1'
    je .local
    jmp .bad
.localhost:
    mov rax,'localhos'
    cmp [rdi],rax
    jne .bad
    cmp byte [rdi+8],'t'
    jne .bad
    cmp byte [rdi+9],0
    je .local
    cmp byte [rdi+9],':'
    jne .bad
.local:
    mov rdi,extra_buf
    mov rsi,http
    call copy_string
    mov rsi,request_host
    call copy_string
    mov byte [rdi],0
    mov rdi,extra_buf
    mov rsi,request_origin
    call strcmp
    test rax,rax
    jnz .bad
.ok:
    xor eax,eax
    ret
.bad:
    mov rax,-403
    ret

; Decode a bounded form value into decode_buf, validating %XX and UTF-8.
; Strip storage delimiters and controls. rdi=input, rax=status.
decode_value:
    mov qword [decode_stripped],0
    mov rsi,rdi
    mov rdi,decode_buf
.loop:
    lodsb
    test al,al
    jz .end
    cmp al,'+'
    jne .percent
    mov al,' '
    jmp .put
.percent:
    cmp al,'%'
    jne .put
    lodsb
    call hex_value
    test eax,eax
    js .bad
    mov r8d,eax
    shl r8d,4
    lodsb
    call hex_value
    test eax,eax
    js .bad
    or eax,r8d
.put:
    cmp al,32
    jb .strip
    cmp al,127
    je .strip
    cmp al,'|'
    je .strip
    stosb
    jmp .loop
.strip:
    mov qword [decode_stripped],1
    jmp .loop
.end:
    mov byte [rdi],0
    mov rdi,decode_buf
    call valid_utf8
    test rax,rax
    js .bad
    xor eax,eax
    ret
.bad:
    mov rax,-400
    ret
hex_value:
    movzx eax,al
    cmp al,'0'
    jb .bad
    cmp al,'9'
    jbe .digit
    or al,32
    cmp al,'a'
    jb .bad
    cmp al,'f'
    ja .bad
    sub eax,87
    ret
.digit:
    sub eax,'0'
    ret
.bad:
    mov rax,-1
    ret

; Exact field names, reject duplicate/unknown fields and invalid decimal IDs.
parse_form:
    push rbx
    push r12
    push r13
    call reset_properties
    mov qword [form_flags],0
    mov byte [form_title],0
    mov byte [form_token],0
    mov qword [form_id],0
    mov rbx,[request_body]
.field:
    cmp byte [rbx],0
    je .ok
    mov r12,rbx
.find_end:
    cmp byte [r12],0
    je .end_field
    cmp byte [r12],'&'
    je .end_field
    inc r12
    jmp .find_end
.end_field:
    mov r13,r12
    cmp byte [r12],0
    je .terminated
    inc r13
    cmp byte [r13],0
    je .bad
    mov byte [r12],0
.terminated:
    mov rdi,rbx
.find_eq:
    cmp byte [rdi],0
    je .bad
    cmp byte [rdi],'='
    je .eq
    inc rdi
    jmp .find_eq
.eq:
    mov byte [rdi],0
    inc rdi
    call decode_value
    test rax,rax
    js .done
    mov rdi,rbx
    mov rsi,key_title
    call strcmp
    test rax,rax
    jz .title
    mov rdi,rbx
    mov rsi,key_id
    call strcmp
    test rax,rax
    jz .id
    mov rdi,rbx
    mov rsi,key_token
    call strcmp
    test rax,rax
    jnz .property
    cmp qword [decode_stripped],0
    jne .bad
    test qword [form_flags],4
    jnz .bad
    or qword [form_flags],4
    mov rdi,decode_buf
    call strlen
    cmp rax,32
    jne .bad
    mov rsi,decode_buf
    mov rdi,form_token
    mov ecx,33
    rep movsb
    jmp .next
.property:
    cmp qword [decode_stripped],0
    jne .bad
    mov rdi,rbx
    mov rsi,decode_buf
    call parse_property
    test rax,rax
    js .done
    jz .bad
    jmp .next
.id:
    cmp qword [decode_stripped],0
    jne .bad
    test qword [form_flags],2
    jnz .bad
    or qword [form_flags],2
    mov rdi,decode_buf
    call parse_uint
    test rax,rax
    jle .bad
    mov [form_id],rax
    jmp .next
.title:
    test qword [form_flags],1
    jnz .bad
    or qword [form_flags],1
    mov rbx,decode_buf
.trim_start:
    cmp byte [rbx],' '
    jne .trim_end
    inc rbx
    jmp .trim_start
.trim_end:
    mov rdi,rbx
    call strlen
    test rax,rax
    jz .invalid_title
    lea rdi,[rbx+rax]
.trim_loop:
    cmp byte [rdi-1],' '
    jne .trim_done
    dec rdi
    dec rax
    jz .invalid_title
    jmp .trim_loop
.trim_done:
    cmp rax,TITLE_MAX
    ja .invalid_title
    mov byte [rdi],0
    mov rcx,rax
    inc rcx
    mov rsi,rbx
    mov rdi,form_title
    rep movsb
.next:
    mov rbx,r13
    jmp .field
.ok:
    xor eax,eax
    jmp .done
.invalid_title:
    mov rax,-422
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r13
    pop r12
    pop rbx
    ret

new_session:
    xor r10d,r10d
.random:
    mov eax,SYS_GETRANDOM
    lea rdi,[random_buf+r10]
    mov esi,16
    sub rsi,r10
    xor edx,edx
    syscall
    cmp rax,-4
    je .random
    test rax,rax
    jle .bad
    add r10,rax
    cmp r10,16
    jb .random
    xor ecx,ecx
.hex:
    movzx eax,byte [random_buf+rcx]
    mov edx,eax
    shr eax,4
    and edx,15
    mov al,[hex_chars+rax]
    mov dl,[hex_chars+rdx]
    mov [current_uid+rcx*2],al
    mov [current_uid+rcx*2+1],dl
    inc ecx
    cmp ecx,16
    jb .hex
    mov byte [current_uid+32],0
    xor eax,eax
    ret
.bad:
    mov rax,-503
    ret

session_redirect:
    mov rdi,extra_buf
    mov rsi,session_prefix
    call copy_string
    mov rsi,current_uid
    call copy_string
    mov rsi,session_tail
    call copy_string
    mov byte [rdi],0
    mov r9,extra_buf
    jmp redirect
redirect_app:
    mov r9,app_location
    cmp qword [return_board],0
    je redirect
    mov r9,board_location
redirect:
    mov rdi,r12
    mov rsi,empty
    xor edx,edx
    mov rcx,see_other
    mov r8,mime_text
    jmp respond

handle_request:
    push rbx
    push r12
    push r13
    mov r12,rdi
    call parse_cookie
    test rax,rax
    js .error
    call normalize_board_path
    test rax,rax
    js .error
    cmp qword [request_method],2
    je .write
    cmp qword [request_method],1
    je .read
    cmp qword [request_method],3
    jne .method
.read:
    mov rdi,request_path
    mov rsi,app_query
    mov edx,5
    call strncmp
    test rax,rax
    jz .get_app
    mov rdi,request_path
    mov rsi,duplicate_path
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    call is_import_path
    test rax,rax
    jnz .method
    mov rdi,request_path
    mov rsi,stats_path
    call strcmp
    test rax,rax
    jz .get_stats
    mov rdi,request_path
    mov rsi,export_json_path
    call strcmp
    test rax,rax
    jz .get_export_json
    mov rdi,request_path
    mov rsi,export_csv_path
    call strcmp
    test rax,rax
    jz .get_export_csv
    mov rdi,request_path
    mov rsi,social_path
    call strcmp
    test rax,rax
    jz .get_social
    mov rdi,request_path
    mov rsi,recovery_path
    call strcmp
    test rax,rax
    jz .get_recovery
    mov rdi,request_path
    mov rsi,path_0
    call strcmp
    test rax,rax
    jz .get_home
    mov rdi,request_path
    mov rsi,path_1
    call strcmp
    test rax,rax
    jz .get_app
    mov rdi,request_path
    mov rsi,path_2
    call strcmp
    test rax,rax
    jz .get_css
    mov rdi,request_path
    mov rsi,path_3
    call strcmp
    test rax,rax
    jz .get_js
    mov rdi,request_path
    mov rsi,path_4
    call strcmp
    test rax,rax
    jz .get_robots
    mov rdi,request_path
    mov rsi,path_5
    call strcmp
    test rax,rax
    jz .get_sitemap
    mov rdi,request_path
    mov rsi,path_6
    call strcmp
    test rax,rax
    jz .get_favicon
    mov rdi,request_path
    mov rsi,path_7
    call strcmp
    test rax,rax
    jz .get_health
    mov rdi,request_path
    mov rsi,legacy_prefix
    mov edx,6
    call strncmp
    test rax,rax
    jz .legacy
    mov rdi,request_path
    mov rsi,start_work_path
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,to_do_path
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,undo_path
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,redo_path
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,restore_task_path
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,purge_path
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,empty_trash_path
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,path_8
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,path_9
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,path_10
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,path_11
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,path_12
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,path_13
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,path_14
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,path_15
    call strcmp
    test rax,rax
    jz .method
    mov rdi,request_path
    mov rsi,path_16
    call strcmp
    test rax,rax
    jz .method
    jmp .missing
.write:
    call check_origin
    test rax,rax
    js .error
    mov rdi,request_path
    call is_import_path
    test rax,rax
    jnz .post_import
    call parse_form
    test rax,rax
    js .error
    cmp qword [property_flags],0
    je .form_ready
    mov rdi,request_path
    mov rsi,path_11
    call strcmp
    test rax,rax
    jz .form_ready
    mov rdi,request_path
    mov rsi,path_15
    call strcmp
    test rax,rax
    jnz .bad
.form_ready:
    mov rdi,request_path
    mov rsi,path_8
    call strcmp
    test rax,rax
    jz .post_start
    mov rdi,request_path
    mov rsi,path_9
    call strcmp
    test rax,rax
    jz .post_restore
    mov rdi,request_path
    mov rsi,path_10
    call strcmp
    test rax,rax
    jz .post_forget
    cmp byte [current_uid],0
    je .unauthorized
    mov rdi,request_path
    mov rsi,start_work_path
    call strcmp
    test rax,rax
    jz .post_start_work
    mov rdi,request_path
    mov rsi,to_do_path
    call strcmp
    test rax,rax
    jz .post_to_do
    mov rdi,request_path
    mov rsi,undo_path
    call strcmp
    test rax,rax
    jz .post_undo
    mov rdi,request_path
    mov rsi,redo_path
    call strcmp
    test rax,rax
    jz .post_redo
    mov rdi,request_path
    mov rsi,restore_task_path
    call strcmp
    test rax,rax
    jz .post_restore_task
    mov rdi,request_path
    mov rsi,purge_path
    call strcmp
    test rax,rax
    jz .post_purge
    mov rdi,request_path
    mov rsi,empty_trash_path
    call strcmp
    test rax,rax
    jz .post_empty_trash
    mov rdi,request_path
    mov rsi,duplicate_path
    call strcmp
    test rax,rax
    jz .post_duplicate
    mov rdi,request_path
    mov rsi,path_11
    call strcmp
    test rax,rax
    jz .post_add
    mov rdi,request_path
    mov rsi,path_12
    call strcmp
    test rax,rax
    jz .post_complete
    mov rdi,request_path
    mov rsi,path_13
    call strcmp
    test rax,rax
    jz .post_reopen
    mov rdi,request_path
    mov rsi,path_14
    call strcmp
    test rax,rax
    jz .post_delete
    mov rdi,request_path
    mov rsi,path_15
    call strcmp
    test rax,rax
    jz .post_edit
    mov rdi,request_path
    mov rsi,path_16
    call strcmp
    test rax,rax
    jz .post_clear
    jmp .missing
.get_stats:
    mov r13,export_stats_svg
    jmp .get_export
.get_export_json:
    mov r13,export_json
    jmp .get_export
.get_export_csv:
    mov r13,export_csv
.get_export:
    cmp byte [current_uid],0
    je .unauthorized
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    push rax
    call unlock_user_file
    pop rax
    test rax,rax
    js .error
    mov rdi,res_buf
    call r13
    mov rdx,rax
    mov rdi,r12
    mov rsi,res_buf
    mov rcx,ok
    mov r8,mime_json
    mov r9,json_headers
    cmp r13,export_json
    je .export_send
    mov r8,mime_svg
    mov r9,private_headers
    cmp r13,export_stats_svg
    je .export_send
    mov r8,mime_csv
    mov r9,csv_headers
.export_send:
    call respond
    jmp .done
.get_social:
    mov rdi,r12
    mov rsi,social
    mov edx,social_len
    mov rcx,ok
    mov r8,mime_png
    mov r9,empty
    call respond
    jmp .done
.get_recovery:
    cmp byte [current_uid],0
    je .unauthorized
    mov byte [current_uid+32],10
    mov rdi,r12
    mov rsi,current_uid
    mov edx,33
    mov rcx,ok
    mov r8,mime_text
    mov r9,recovery_headers
    call respond
    jmp .done
.get_app:
    cmp byte [current_uid],0
    jne .load_app
    mov r9,home_location
    call redirect
    jmp .done
.load_app:
    xor edi,edi
    cmp byte [request_path+4],'?'
    jne .parse_view
    mov rdi,request_path+5
.parse_view:
    call parse_view
    test rax,rax
    js .error
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    push rax
    call unlock_user_file
    pop rax
    test rax,rax
    js .error
    call build_view
    test rax,rax
    js .error
    call render_app
    jmp .done
.legacy:
    ; Migration only: never silently replace a browser's existing workspace.
    cmp byte [current_uid],0
    jne .conflict
    mov rdi,request_path+6
    call copy_uid
    test rax,rax
    js .error
    cmp qword [request_method],3
    je .method
    call session_redirect
    jmp .done
.post_start:
    cmp qword [form_flags],0
    jne .bad
    cmp byte [current_uid],0
    jne .start_ready
    call new_session
    test rax,rax
    js .error
.start_ready:
    call session_redirect
    jmp .done
.post_restore:
    cmp qword [form_flags],4
    jne .bad
    mov rdi,form_token
    call copy_uid
    test rax,rax
    js .error
    call session_redirect
    jmp .done
.post_forget:
    cmp qword [form_flags],0
    jne .bad
    mov r9,forget_headers
    call redirect
    jmp .done
.post_duplicate:
    cmp qword [form_flags],2
    jne .bad
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    mov rdi,[form_id]
    call duplicate_todo
    test rax,rax
    js .unlock_error
    call unlock_user_file
    call redirect_app
    jmp .done
.post_import:
    cmp byte [current_uid],0
    je .unauthorized
    mov rdi,r12
    xor esi,esi
    cmp byte [request_path+7],0 ; /import is seven bytes, preview is longer
    sete sil
    call handle_import
    test rax,rax
    js .error
    jmp .done
.post_start_work:
    mov r13d,1
    jmp .post_workflow
.post_to_do:
    xor r13d,r13d
.post_workflow:
    cmp qword [form_flags],2
    jne .bad
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    mov rdi,[form_id]
    mov rsi,r13
    call change_stage
    jmp .finish_mutation
.post_undo:
    mov r13d,1
    jmp .post_history
.post_redo:
    mov r13d,2
.post_history:
    cmp qword [form_flags],0
    jne .bad
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    mov rdi,r13
    call undo_workspace
    jmp .finish_mutation
.post_restore_task:
    mov r13,restore_todo
    jmp .post_trash
.post_purge:
    mov r13,purge_todo
.post_trash:
    cmp qword [form_flags],2
    jne .bad
    jmp .trash_mutation
.post_empty_trash:
    cmp qword [form_flags],0
    jne .bad
    mov r13,empty_trash
.trash_mutation:
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    mov rdi,[form_id]
    call r13
.finish_mutation:
    test rax,rax
    js .unlock_error
    call unlock_user_file
    call redirect_app
    jmp .done
.post_add:
    cmp qword [form_flags],1
    jne .bad
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    mov rdi,form_title
    call append_todo
    test rax,rax
    js .unlock_error
    call unlock_user_file
    call redirect_app
    jmp .done
.post_complete:
    cmp qword [form_flags],2
    jne .bad
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    mov rdi,[form_id]
    mov rsi,form_title
    call complete_todo
    test rax,rax
    js .unlock_error
    call unlock_user_file
    call redirect_app
    jmp .done
.post_reopen:
    cmp qword [form_flags],2
    jne .bad
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    mov rdi,[form_id]
    mov rsi,form_title
    call reopen_todo
    test rax,rax
    js .unlock_error
    call unlock_user_file
    call redirect_app
    jmp .done
.post_delete:
    cmp qword [form_flags],2
    jne .bad
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    mov rdi,[form_id]
    mov rsi,form_title
    call delete_todo
    test rax,rax
    js .unlock_error
    call unlock_user_file
    call redirect_app
    jmp .done
.post_edit:
    cmp qword [form_flags],3
    jne .bad
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    mov rdi,[form_id]
    mov rsi,form_title
    call edit_todo
    test rax,rax
    js .unlock_error
    call unlock_user_file
    call redirect_app
    jmp .done
.post_clear:
    cmp qword [form_flags],0
    jne .bad
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    test rax,rax
    js .unlock_error
    call clear_done_todos
    test rax,rax
    js .unlock_error
    call unlock_user_file
    call redirect_app
    jmp .done
.get_home:
    mov rdi,r12
    mov rsi,home
    mov edx,home_len
    mov rcx,ok
    mov r8,mime_html
    mov r9,empty
    call respond
    jmp .done
.get_css:
    mov rdi,r12
    mov rsi,css
    mov edx,css_len
    mov rcx,ok
    mov r8,mime_css
    mov r9,empty
    call respond
    jmp .done
.get_js:
    mov rdi,r12
    mov rsi,js
    mov edx,js_len
    mov rcx,ok
    mov r8,mime_js
    mov r9,empty
    call respond
    jmp .done
.get_robots:
    mov rdi,r12
    mov rsi,robots
    mov edx,robots_len
    mov rcx,ok
    mov r8,mime_text
    mov r9,empty
    call respond
    jmp .done
.get_sitemap:
    mov rdi,r12
    mov rsi,sitemap
    mov edx,sitemap_len
    mov rcx,ok
    mov r8,mime_xml
    mov r9,empty
    call respond
    jmp .done
.get_favicon:
    mov rdi,r12
    mov rsi,favicon
    mov edx,favicon_len
    mov rcx,ok
    mov r8,mime_svg
    mov r9,empty
    call respond
    jmp .done
.get_health:
    mov rdi,r12
    mov rsi,health
    mov edx,health_len
    mov rcx,ok
    mov r8,mime_json
    mov r9,empty
    call respond
    jmp .done
.unlock_error:
    push rax
    call unlock_user_file
    pop rax
    jmp .error
.bad:
    mov rax,-400
    jmp .error
.unauthorized:
    mov rax,-401
    jmp .error
.missing:
    mov rax,-404
    jmp .error
.method:
    mov rax,-405
    jmp .error
.conflict:
    mov rax,-409
.error:
    cmp qword [request_method],2
    jne .plain_error
    test qword [form_flags],1
    jz .plain_error
    cmp rax,-507
    je .draft
    cmp rax,-409
    jne .plain_error
.draft:
    push rax
    mov rdi,res_buf
    mov rsi,draft_open
    call copy_string
    call emit_mutation_prefix
    mov rsi,draft_add
    cmp qword [form_flags],3
    jne .draft_action
    mov rsi,draft_edit
.draft_action:
    call copy_string
    cmp qword [form_flags],3
    jne .draft_field
    mov rsi,draft_id
    call copy_string
    mov rax,[form_id]
    call emit_number
.draft_field:
    mov rsi,draft_title
    call copy_string
    mov rsi,form_title
    call html_escape
    mov word [rdi],'">'
    add rdi,2
    mov rsi,property_task
    xor edx,edx
    call render_properties
    mov rsi,draft_close+2
    call copy_string
    mov rdx,rdi
    sub rdx,res_buf
    pop rax
    mov rcx,status_507
    cmp rax,-409
    jne .draft_send
    mov rcx,status_409
.draft_send:
    mov rdi,r12
    mov rsi,res_buf
    mov r8,mime_html
    mov r9,private_headers
    call respond
    jmp .done
.plain_error:
    neg rax
    mov rdi,rax
    mov rsi,r12
    call send_error
.done:
    pop r13
    pop r12
    pop rbx
    ret

; User text appears only in an HTML text node, never executable attributes.
html_escape:
.loop:
    lodsb
    test al,al
    jz .done
    cmp al,'&'
    je .amp
    cmp al,'<'
    je .lt
    cmp al,'>'
    je .gt
    cmp al,'"'
    je .quot
    stosb
    jmp .loop
.amp:
    mov dword [rdi],'&amp'
    mov byte [rdi+4],';'
    add rdi,5
    jmp .loop
.lt:
    mov dword [rdi],'&lt;'
    add rdi,4
    jmp .loop
.gt:
    mov dword [rdi],'&gt;'
    add rdi,4
    jmp .loop
.quot:
    mov dword [rdi],'&#34'
    mov byte [rdi+4],';'
    add rdi,5
    jmp .loop
.done:
    ret
emit_number:
    push rdi
    mov rdi,rax
    mov rsi,number_buf
    call itoa
    pop rdi
    mov rsi,number_buf
    jmp copy_string

render_app:
    push rbx
    push r13
    push r14
    push r15
    mov rdi,res_buf
    mov rsi,app_head
    call render_template
    test rax,rax
    js .template_error
    xor r15d,r15d
.column:
    cmp qword [view_layout],1
    jne .rows
    mov rsi,r15
    call render_board_start
.rows:
    mov r14,view_rows
    mov r13,[view_count]
.loop:
    test r13,r13
    jz .column_end
    mov rbx,[r14]
    cmp qword [view_layout],1
    jne .row
    mov rax,[rbx+T_STAGE]
    cmp byte [rbx+8],1
    jne .stage
    mov eax,2
.stage:
    cmp rax,r15
    jne .next_row
.row:
    mov rsi,li_open
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,li_ts
    call copy_string
    mov rax,[rbx+9]
    call emit_number
    mov rsi,li_trash
    cmp byte [rbx+8],2
    je .title
    mov rsi,li_active
    cmp byte [rbx+8],1
    jne .title
    mov rsi,li_done
.title:
    call copy_string
    lea rsi,[rbx+17]
    call html_escape
    mov rsi,li_date
    call copy_string
    push rdi
    mov rdi,[rbx+9]
    mov rsi,row_date
    call format_utc
    pop rdi
    test rax,rax
    jz .date_done
    mov byte [row_date+10],0
    mov rsi,row_date
    call copy_string
.date_done:
    mov rsi,close_time
    call copy_string
    mov rsi,rbx
    call render_task_badges
    mov rsi,li_actions
    call copy_string
    cmp byte [rbx+8],2
    je .trash_actions
    mov rsi,complete_open
    cmp byte [rbx+8],1
    jne .action
    mov rsi,reopen_open
.action:
    call render_template
    mov rax,[rbx]
    call emit_number
    mov rsi,complete_close
    cmp byte [rbx+8],1
    jne .ready_action
    mov rsi,reopen_close
    jmp .close_action
.ready_action:
    push rdi
    mov rdi,rbx
    call task_ready
    pop rdi
    mov rsi,complete_close
    test rax,rax
    jnz .close_action
    mov rsi,blocked_complete_close
.close_action:
    call copy_string
    mov rsi,menu_open
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,menu_edit_end
    call render_template
    cmp byte [rbx+8],1
    je .duplicate_action
    mov rsi,menu_subtask
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,menu_subtask_end
    call render_template
.duplicate_action:
    cmp qword [view_layout],1
    jne .duplicate_form
    cmp byte [rbx+8],0
    jne .duplicate_form
    mov rsi,work_start_open
    cmp qword [rbx+T_STAGE],0
    je .work_open
    mov rsi,work_todo_open
.work_open:
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,work_start_close
    cmp qword [rbx+T_STAGE],0
    je .work_close
    mov rsi,work_todo_close
.work_close:
    call copy_string
.duplicate_form:
    mov rsi,menu_duplicate_start
    call render_template
    mov rax,[rbx]
    call emit_number
    mov rsi,menu_duplicate_end
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,menu_end
    call render_template
    jmp .next_row
.trash_actions:
    mov rsi,restore_task_open
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,restore_task_close
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,trash_row_close
    call copy_string
.next_row:
    add r14,8
    dec r13
    jmp .loop
.column_end:
    cmp qword [view_layout],1
    jne .footer
    call render_board_end
    inc r15
    cmp r15,3
    jb .column
.footer:
    mov rsi,app_foot
    call render_template
    test rax,rax
    js .template_error
    mov rdx,rdi
    sub rdx,res_buf
    mov rdi,r12
    mov rsi,res_buf
    mov rcx,ok
    mov r8,mime_html
    mov r9,private_headers
    call respond
    jmp .done
.template_error:
    mov edi,500
    mov rsi,r12
    call send_error
.done:
    pop r15
    pop r14
    pop r13
    pop rbx
    ret

section .data
    legacy_prefix db '/?uid=',0

section .data
    work_start_open db '<form method="post" action="/board/start-work"><input type="hidden" name="id" value="',0
    work_todo_open db '<form method="post" action="/board/to-do"><input type="hidden" name="id" value="',0
    work_start_close db '"><button>Start work</button></form>',0
    work_todo_close db '"><button>Move to To do</button></form>',0
section .text
; Explicit board aliases keep native mutation responses in the board. Unknown
; paths remain unknown; session, export and import paths have no board alias.
normalize_board_path:
    push rbx
    push r12
    mov qword [return_board],0
    mov rdi,request_path
    mov rsi,board_route_prefix
    mov edx,7
    call strncmp
    test rax,rax
    jnz .ok
    mov rbx,board_aliases
.find:
    cmp qword [rbx],0
    je .ok
    mov rdi,request_path+6
    mov rsi,[rbx]
    call strcmp
    test rax,rax
    jz .found
    add rbx,8
    jmp .find
.found:
    cmp qword [request_method],2
    jne .method
    mov rdi,request_path+6
    call strlen
    lea rcx,[rax+1]
    mov rsi,request_path+6
    mov rdi,request_path
    rep movsb
    mov qword [return_board],1
    mov qword [view_layout],1
.ok:
    xor eax,eax
    jmp .done
.method:
    mov rax,-405
.done:
    pop r12
    pop rbx
    ret

section .text
; Header-only authorization for the import receive gate. It performs no writes.
authorize_import_headers:
    call parse_cookie
    test rax,rax
    js .done
    cmp byte [current_uid],0
    je .unauthorized
    call check_origin
.done:
    ret
.unauthorized:
    mov rax,-401
    ret

; fd/body/length plus numeric 200/409/507 status for a bounded native preview.
send_private_html:
    cmp rcx,409
    je .conflict
    cmp rcx,507
    je .storage
    mov rcx,ok
    jmp .send
.conflict:
    mov rcx,status_409
    jmp .send
.storage:
    mov rcx,status_507
.send:
    mov r8,mime_html
    mov r9,private_headers
    jmp respond
