%include "src/defs.inc"
DEFAULT ABS
extern strlen, strcmp, strncmp, write_all, itoa, parse_uint, valid_utf8
extern append_todo, complete_todo, delete_todo, edit_todo, reopen_todo
extern get_todo_list, load_todos, clear_done_todos, lock_user_file, unlock_user_file
extern request_method, request_path, request_body
extern request_cookie, request_origin, request_host, request_site

global handle_request, current_uid, send_error
section .data
    ok db 'HTTP/1.1 200 OK',13,10,0
    see_other db 'HTTP/1.1 303 See Other',13,10,0
    common_headers db "Cache-Control: no-store",13,10
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
    social_path db '/social-card.png',0
    mime_png db 'image/png',0
    social: incbin 'web/social-card.png'
    social_len equ $-social
    recovery_path db '/recovery',0
    recovery_headers db 'X-Robots-Tag: noindex, nofollow',13,10,'Content-Disposition: attachment; filename="asm-workspace-key.txt"',13,10,0
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
    li_done db '" data-done="1" class="done"><div class="task-copy"><span class="task-title">',0
    li_actions db '</span><time class="task-date"></time></div><div class="task-actions">',0
    edit_open db '<button type="button" data-edit aria-label="Edit task">Edit</button>',0
    complete_open db '<form method="post" action="/complete"><input type="hidden" name="id" value="',0
    reopen_open db '<form method="post" action="/reopen"><input type="hidden" name="id" value="',0
    complete_close db '"><button aria-label="Complete task">Done</button></form>',0
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
    error_409 db 'Workspace capacity reached, or a different workspace is already open.',10
    error_409_len equ $-error_409
    status_411 db 'HTTP/1.1 411 Length Required',13,10,0
    error_411 db 'Content-Length is required.',10
    error_411_len equ $-error_411
    status_413 db 'HTTP/1.1 413 Content Too Large',13,10,0
    error_413 db 'The request exceeds the 4095-byte limit.',10
    error_413_len equ $-error_413
    status_415 db 'HTTP/1.1 415 Unsupported Media Type',13,10,0
    error_415 db 'Use application/x-www-form-urlencoded.',10
    error_415_len equ $-error_415
    status_417 db 'HTTP/1.1 417 Expectation Failed',13,10,0
    error_417 db 'Expect headers are not supported.',10
    error_417_len equ $-error_417
    status_422 db 'HTTP/1.1 422 Unprocessable Content',13,10,0
    error_422 db 'Enter a task between 1 and 110 UTF-8 bytes.',10
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
section .bss
    current_uid resb 64
    res_buf resb 2097152
    hdr_buf resb 2048
    extra_buf resb 512
    number_buf resb 24
    random_buf resb 16
    form_title resb TITLE_MAX+1
    form_token resb 64
    form_id resq 1
    decode_stripped resq 1
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
    jnz .bad
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
    cmp qword [request_method],2
    je .write
    cmp qword [request_method],1
    je .read
    cmp qword [request_method],3
    jne .method
.read:
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
    call parse_form
    test rax,rax
    js .error
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
    call lock_user_file
    test rax,rax
    js .error
    call load_todos
    push rax
    call unlock_user_file
    pop rax
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
    mov rdi,res_buf
    mov rsi,app_head
    call copy_string
    push rdi
    call get_todo_list
    mov rbx,rax
    pop rdi
    mov r13d,TASK_MAX
.loop:
    cmp qword [rbx],0
    je .next
    cmp byte [rbx+8],2
    je .next
    mov rsi,li_open
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,li_ts
    call copy_string
    mov rax,[rbx+9]
    call emit_number
    mov rsi,li_active
    cmp byte [rbx+8],1
    jne .title
    mov rsi,li_done
.title:
    call copy_string
    lea rsi,[rbx+17]
    call html_escape
    mov rsi,li_actions
    call copy_string
    mov rsi,edit_open
    call copy_string
    mov rsi,complete_open
    cmp byte [rbx+8],1
    jne .action
    mov rsi,reopen_open
.action:
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,complete_close
    cmp byte [rbx+8],1
    jne .close_action
    mov rsi,reopen_close
.close_action:
    call copy_string
    mov rsi,delete_open
    call copy_string
    mov rax,[rbx]
    call emit_number
    mov rsi,delete_close
    call copy_string
.next:
    add rbx,128
    dec r13
    jnz .loop
    mov rsi,app_foot
    call copy_string
    mov rdx,rdi
    sub rdx,res_buf
    mov rdi,r12
    mov rsi,res_buf
    mov rcx,ok
    mov r8,mime_html
    mov r9,private_headers
    call respond
    pop r14
    pop r13
    pop rbx
    ret
section .data
    legacy_prefix db '/?uid=',0
