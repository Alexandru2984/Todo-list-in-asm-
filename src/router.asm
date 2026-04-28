%include "src/defs.inc"

extern strlen
extern strncmp
extern print
extern itoa
extern atoi
extern append_todo
extern complete_todo
extern delete_todo
extern get_todo_list
extern load_todos
extern clear_done_todos

global handle_request
global current_uid

section .data
    http_200 db "HTTP/1.1 200 OK", 13, 10, "Content-Type: text/html", 13, 10, "Connection: close", 13, 10, 13, 10, 0
    http_303_prefix db "HTTP/1.1 303 See Other", 13, 10, "Location: /?uid=", 0
    http_404 db "HTTP/1.1 404 Not Found", 13, 10, "Content-Length: 9", 13, 10, "Connection: close", 13, 10, 13, 10, "Not Found", 0

    html_header_1 db "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'>", 10
                  db "<meta name='viewport' content='width=device-width,initial-scale=1'>", 10
                  db "<title>ASM TODO</title><style>", 10
                  db "*{box-sizing:border-box;margin:0;padding:0}", 10
                  db "body{font:16px/1.5 system-ui,sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh;padding:2rem 1rem}", 10
                  db ".wrap{max-width:640px;margin:auto}", 10
                  db "h1{text-align:center;font-size:2rem;background:linear-gradient(135deg,#58a6ff,#bc8cff);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:1.5rem}", 10
                  db ".af{display:flex;gap:.5rem;margin-bottom:1rem}", 10
                  db ".af input{flex:1;padding:.6rem .8rem;background:#161b22;border:1px solid #30363d;border-radius:6px;color:#c9d1d9;font-size:1rem;outline:none}", 10
                  db ".af input:focus{border-color:#58a6ff}", 10
                  db ".af button{padding:.6rem 1.2rem;background:#238636;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:1rem;font-weight:600}", 10
                  db ".af button:hover{background:#2ea043}", 10
                  db ".st{color:#8b949e;font-size:.875rem;margin-bottom:.5rem}", 10
                  db ".fi{display:flex;gap:.5rem;margin-bottom:1rem}", 10
                  db ".fi button{padding:.3rem .8rem;border:1px solid #30363d;border-radius:6px;background:transparent;color:#8b949e;cursor:pointer;font-size:.875rem}", 10
                  db ".fi button.on{background:#238636;color:#fff;border-color:#238636}", 10
                  db "ul{list-style:none}", 10
                  db "li{background:#161b22;border:1px solid #30363d;border-radius:6px;padding:.75rem 1rem;margin-bottom:.5rem;display:flex;align-items:center;gap:1rem}", 10
                  db "li.done .tt{text-decoration:line-through;color:#8b949e}", 10
                  db ".ti{flex:1;min-width:0}", 10
                  db ".tt{display:block;word-break:break-word}", 10
                  db ".ts{display:block;font-size:.75rem;color:#8b949e;margin-top:.2rem}", 10
                  db ".ta{display:flex;gap:.4rem;flex-shrink:0}", 10
                  db "form{display:inline}", 10
                  db ".bd{padding:.3rem .5rem;background:#238636;color:#fff;border:none;border-radius:4px;cursor:pointer;font-size:.875rem}", 10
                  db ".bd:hover{background:#2ea043}", 10
                  db ".bx{padding:.3rem .5rem;background:#da3633;color:#fff;border:none;border-radius:4px;cursor:pointer;font-size:.875rem}", 10
                  db ".bx:hover{background:#f85149}", 10
                  db "</style>", 10
                  db "<script>(function(){var p=new URLSearchParams(window.location.search);var u=p.get('uid');if(!u){u=localStorage.getItem('asm_uid');if(!u){u=crypto.randomUUID().replace(/-/g,'');localStorage.setItem('asm_uid',u);}window.location.replace('/?uid='+u);}else{localStorage.setItem('asm_uid',u);}})();</script>", 10
                  db "</head><body><div class='wrap'>", 10
                  db "<h1>ASM TODO</h1>", 10
                  db "<form class='af' method='POST' action='/add'>", 10
                  db "<input type='hidden' name='uid' value='", 0

    html_header_2 db "'><input type='text' name='title' placeholder='New task...' required>", 10
                  db "<button type='submit'>Add</button>", 10
                  db "</form>", 10
                  db "<p class='st' id='stats'></p>", 10
                  db "<div class='fi'>", 10
                  db "<button class='on' data-f='all'>All</button>", 10
                  db "<button data-f='active'>Active</button>", 10
                  db "<button data-f='done'>Done</button>", 10
                  db "</div>", 10
                  db "<ul id='tl'>", 10, 0

    html_footer_1 db "</ul>", 10, 0

    html_footer_2 db "</div>", 10
                  db "<script>", 10
                  db "function fmtDate(ts){if(!ts)return '';return new Date(ts*1000).toLocaleString();}", 10
                  db "function filter(t,btn){document.querySelectorAll('.fi button').forEach(function(b){b.classList.remove('on');});btn.classList.add('on');document.querySelectorAll('#tl li').forEach(function(li){if(t==='all')li.style.display='';else if(t==='active')li.style.display=li.dataset.done==='0'?'':'none';else li.style.display=li.dataset.done==='1'?'':'none';});}", 10
                  db "function stats(){var items=document.querySelectorAll('#tl li');var n=0;items.forEach(function(li){if(li.dataset.done==='1')n++;});var el=document.getElementById('stats');if(el)el.textContent=items.length+' task'+(items.length!==1?'s':'')+', '+n+' done';}", 10
                  db "window.onload=function(){", 10
                  db "document.querySelectorAll('#tl li .ts').forEach(function(el){var ts=parseInt(el.closest('li').dataset.ts);el.textContent=fmtDate(ts);});", 10
                  db "stats();", 10
                  db "document.querySelectorAll('.fi button').forEach(function(b){b.onclick=function(){filter(b.getAttribute('data-f'),b);};});", 10
                  db "var hasDone=Array.from(document.querySelectorAll('#tl li')).some(function(li){return li.dataset.done==='1';});", 10
                  db "var cdf=document.getElementById('cdf');if(cdf&&hasDone)cdf.style.display='block';", 10
                  db "};", 10
                  db "</script>", 10
                  db "</body></html>", 10, 0

    li_active_1 db "<li data-ts='", 0
    li_active_2 db "' data-done='0'><div class='ti'><span class='tt'>", 0
    li_done_1   db "<li class='done' data-ts='", 0
    li_done_2   db "' data-done='1'><div class='ti'><span class='tt'>", 0
    li_mid      db "</span><span class='ts'></span></div><div class='ta'>", 0

    form_complete_open db "<form method='POST' action='/complete'><input type='hidden' name='uid' value='", 0
    form_delete_open   db "<form method='POST' action='/delete'><input type='hidden' name='uid' value='", 0
    form_uid_id_bridge db "'><input type='hidden' name='id' value='", 0
    form_complete_2    db "'><button class='bd'>&#10003;</button></form>", 0
    form_delete_2      db "'><button class='bx'>&#10007;</button></form></div></li>", 10, 0

    get_root db "GET /", 0
    post_add db "POST /add ", 0
    post_complete db "POST /complete ", 0
    post_delete db "POST /delete ", 0
    post_clear_done db "POST /clear-done ", 0

    html_clear_done_open db "<form method='POST' action='/clear-done' id='cdf' style='display:none;margin-bottom:1rem'><input type='hidden' name='uid' value='", 0
    html_clear_done_close db "'><button class='bx' style='width:100%'>&#10003; Clear done</button></form>", 10, 0

    rnrn db 13, 10, 13, 10, 0

section .bss
    res_buf resb 65536
    id_str resb 32
    current_uid resb 64

section .text

; -----------------------------------------------------------------------------
; handle_request
; rdi = request string
; rsi = socket fd
; -----------------------------------------------------------------------------
handle_request:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi ; req
    mov r12, rsi ; fd

    ; Clear current_uid for this request
    mov byte [current_uid], 0

    ; Route matching — GET /  or  GET /?uid=...
    mov rdi, rbx
    mov rsi, get_root
    mov rdx, 5
    call strncmp
    test rax, rax
    jnz .check_post_add
    ; Byte at [rbx+5] must be ' ' or '?'
    mov al, byte [rbx+5]
    cmp al, ' '
    je .do_get_root
    cmp al, '?'
    je .do_get_root

.check_post_add:
    mov rdi, rbx
    mov rsi, post_add
    mov rdx, 10
    call strncmp
    test rax, rax
    jz .do_post_add

    mov rdi, rbx
    mov rsi, post_complete
    mov rdx, 15
    call strncmp
    test rax, rax
    jz .do_post_complete

    mov rdi, rbx
    mov rsi, post_delete
    mov rdx, 13
    call strncmp
    test rax, rax
    jz .do_post_delete

    mov rdi, rbx
    mov rsi, post_clear_done
    mov rdx, 17
    call strncmp
    test rax, rax
    jz .do_post_clear_done

    ; 404
    mov rdi, http_404
    call strlen
    mov rdx, rax
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, http_404
    syscall
    jmp .done

.do_get_root:
    ; Extract uid from URL query string
    mov rdi, rbx
    call find_uid_in_url
    test rax, rax
    jz .get_load
    mov rdi, rax
    call copy_uid
.get_load:
    call load_todos
    call send_html
    jmp .done

.do_post_add:
    call extract_body
    test rax, rax
    jz .redirect
    mov r13, rax
    mov rdi, r13
    call find_uid
    test rax, rax
    jz .redirect
    mov rdi, rax
    call copy_uid
    cmp byte [current_uid], 0
    je .redirect
    call load_todos
    mov rdi, r13
    call find_title
    test rax, rax
    jz .redirect
    mov rdi, rax
    call url_decode
    ; skip empty title
    cmp byte [rax], 0
    je .redirect
    ; truncate title to max 110 chars (line_buf 512, slot 111 bytes)
    push rax
    mov rdi, rax
    mov ecx, 111
.scan_title:
    dec ecx
    jz .trunc_title
    cmp byte [rdi], 0
    jz .do_append
    inc rdi
    jmp .scan_title
.trunc_title:
    mov byte [rdi], 0
.do_append:
    pop rdi
    call append_todo
    jmp .redirect

.do_post_complete:
    call extract_body
    test rax, rax
    jz .redirect
    mov r13, rax
    mov rdi, r13
    call find_uid
    test rax, rax
    jz .redirect
    mov rdi, rax
    call copy_uid
    cmp byte [current_uid], 0
    je .redirect
    call load_todos
    mov rdi, r13
    call find_id
    test rax, rax
    jz .redirect
    mov rdi, rax
    call atoi
    mov rdi, rax
    call complete_todo
    jmp .redirect

.do_post_delete:
    call extract_body
    test rax, rax
    jz .redirect
    mov r13, rax
    mov rdi, r13
    call find_uid
    test rax, rax
    jz .redirect
    mov rdi, rax
    call copy_uid
    cmp byte [current_uid], 0
    je .redirect
    call load_todos
    mov rdi, r13
    call find_id
    test rax, rax
    jz .redirect
    mov rdi, rax
    call atoi
    mov rdi, rax
    call delete_todo
    jmp .redirect

.do_post_clear_done:
    call extract_body
    test rax, rax
    jz .redirect
    mov r13, rax
    mov rdi, r13
    call find_uid
    test rax, rax
    jz .redirect
    mov rdi, rax
    call copy_uid
    cmp byte [current_uid], 0
    je .redirect
    call load_todos
    call clear_done_todos
    jmp .redirect

.redirect:
    ; Build "HTTP/1.1 303 See Other\r\nLocation: /?uid={uid}\r\n\r\n" in res_buf
    mov rdi, res_buf
    mov rsi, http_303_prefix
    call strcpy_fwd
    ; append current_uid (may be empty string — that's fine, redirect to /?uid=)
    mov rsi, current_uid
    call strcpy_fwd
    ; append \r\n\r\n
    mov byte [rdi], 13
    inc rdi
    mov byte [rdi], 10
    inc rdi
    mov byte [rdi], 13
    inc rdi
    mov byte [rdi], 10
    inc rdi

    mov rsi, res_buf
    mov rdx, rdi
    sub rdx, res_buf
    mov rax, SYS_WRITE
    mov rdi, r12
    syscall
    jmp .done

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; Extracts body pointer from rbx (request)
; Returns rax = pointer or 0
extract_body:
    mov rsi, rbx
.loop:
    cmp byte [rsi], 0
    je .not_found
    cmp dword [rsi], 0x0a0d0a0d ; \r\n\r\n
    je .found
    inc rsi
    jmp .loop
.found:
    add rsi, 4
    mov rax, rsi
    ret
.not_found:
    xor rax, rax
    ret

; Finds "title=" in string rdi, returns pointer to value
find_title:
    mov rsi, rdi
.loop:
    cmp byte [rsi], 0
    je .not_found
    cmp dword [rsi], 0x6c746974 ; "titl"
    jne .next
    cmp word [rsi+4], 0x3d65 ; "e="
    jne .next
    add rsi, 6
    mov rax, rsi
    ret
.next:
    inc rsi
    jmp .loop
.not_found:
    xor rax, rax
    ret

; Finds "&id=" or "id=" at start of string
; rdi = body ptr, returns rax = ptr to value or 0
find_id:
    mov rsi, rdi
    ; First check if string starts with "id="
    cmp word [rsi], 0x6469  ; "id"
    jne .scan
    cmp byte [rsi+2], '='
    jne .scan
    add rsi, 3
    mov rax, rsi
    ret
.scan:
.loop:
    cmp byte [rsi], 0
    je .not_found
    ; look for '&' followed by "id="
    cmp byte [rsi], '&'
    jne .next
    cmp word [rsi+1], 0x6469  ; "id"
    jne .next
    cmp byte [rsi+3], '='
    jne .next
    add rsi, 4
    mov rax, rsi
    ret
.next:
    inc rsi
    jmp .loop
.not_found:
    xor rax, rax
    ret

; In-place URL decode: handles +, %XX, stops at & or \0
; rdi = ptr to value; rax = same ptr (decoded in-place)
url_decode:
    mov rsi, rdi    ; read ptr
    ; rdi = write ptr (same start)
    mov rax, rdi    ; return value
.loop:
    mov cl, [rsi]
    test cl, cl
    jz .end
    cmp cl, '&'
    je .end
    cmp cl, '+'
    je .plus
    cmp cl, '%'
    je .pct
    mov [rdi], cl
    inc rsi
    inc rdi
    jmp .loop
.plus:
    mov byte [rdi], ' '
    inc rsi
    inc rdi
    jmp .loop
.pct:
    inc rsi
    movzx ecx, byte [rsi]
    test cl, cl
    jz .end
    call hex_nibble
    shl cl, 4
    mov r9b, cl
    inc rsi
    movzx ecx, byte [rsi]
    test cl, cl
    jz .end
    call hex_nibble
    and cl, 0x0F
    or cl, r9b
    mov [rdi], cl
    inc rsi
    inc rdi
    jmp .loop
.end:
    mov byte [rdi], 0
    ret

; cl = hex char ('0'-'9','a'-'f','A'-'F') → nibble in cl
hex_nibble:
    cmp cl, 'a'
    jb .not_lower
    sub cl, 87      ; 'a'(97) - 10 = 87
    ret
.not_lower:
    cmp cl, 'A'
    jb .is_digit
    sub cl, 55      ; 'A'(65) - 10 = 55
    ret
.is_digit:
    sub cl, '0'
    ret

; strcpy_html_escape: copy from rsi to rdi, escaping <>&" as HTML entities
; updates rdi; clobbers al, rsi
strcpy_html_escape:
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    cmp al, '<'
    je .lt
    cmp al, '>'
    je .gt
    cmp al, '&'
    je .amp
    cmp al, '"'
    je .quot
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .loop
.lt:
    mov byte [rdi],   '&'
    mov byte [rdi+1], 'l'
    mov byte [rdi+2], 't'
    mov byte [rdi+3], ';'
    add rdi, 4
    inc rsi
    jmp .loop
.gt:
    mov byte [rdi],   '&'
    mov byte [rdi+1], 'g'
    mov byte [rdi+2], 't'
    mov byte [rdi+3], ';'
    add rdi, 4
    inc rsi
    jmp .loop
.amp:
    mov byte [rdi],   '&'
    mov byte [rdi+1], 'a'
    mov byte [rdi+2], 'm'
    mov byte [rdi+3], 'p'
    mov byte [rdi+4], ';'
    add rdi, 5
    inc rsi
    jmp .loop
.quot:
    mov byte [rdi],   '&'
    mov byte [rdi+1], '#'
    mov byte [rdi+2], '3'
    mov byte [rdi+3], '4'
    mov byte [rdi+4], ';'
    add rdi, 5
    inc rsi
    jmp .loop
.done:
    ret

; Render HTML and send to r12 (fd)
send_html:
    push rbp
    mov rbp, rsp
    push rbx
    push r13

    ; Build response in res_buf
    mov rdi, res_buf

    mov rsi, http_200
    call strcpy_fwd

    ; Header part 1 (CSS + uid-check script + form open + hidden uid field open)
    mov rsi, html_header_1
    call strcpy_fwd

    ; Inject current_uid into the add form hidden field
    mov rsi, current_uid
    call strcpy_fwd

    ; Header part 2 (rest of form + filter buttons + <ul>)
    mov rsi, html_header_2
    call strcpy_fwd

    ; Loop todos
    push rdi
    call get_todo_list
    mov rbx, rax
    pop rdi
    mov r13, 1000

.todo_loop:
    mov rax, [rbx]
    test rax, rax
    jz .next_todo

    mov cl, [rbx+8]
    cmp cl, 2
    je .next_todo

    cmp cl, 1
    je .li_is_done

    mov rsi, li_active_1
    call strcpy_fwd
    jmp .emit_ts

.li_is_done:
    mov rsi, li_done_1
    call strcpy_fwd

.emit_ts:
    push rdi
    mov rdi, [rbx+9]
    mov rsi, id_str
    call itoa
    pop rdi
    mov rsi, id_str
    call strcpy_fwd

    mov cl, [rbx+8]
    cmp cl, 1
    je .li_part2_done

    mov rsi, li_active_2
    call strcpy_fwd
    jmp .emit_title

.li_part2_done:
    mov rsi, li_done_2
    call strcpy_fwd

.emit_title:
    mov rsi, rbx
    add rsi, 17
    call strcpy_html_escape

    mov rsi, li_mid
    call strcpy_fwd

    ; Complete button (active items only)
    mov cl, [rbx+8]
    cmp cl, 1
    je .skip_done_btn

    mov rsi, form_complete_open
    call strcpy_fwd
    mov rsi, current_uid
    call strcpy_fwd
    mov rsi, form_uid_id_bridge
    call strcpy_fwd

    push rdi
    mov rdi, [rbx]
    mov rsi, id_str
    call itoa
    pop rdi
    mov rsi, id_str
    call strcpy_fwd

    mov rsi, form_complete_2
    call strcpy_fwd

.skip_done_btn:
    mov rsi, form_delete_open
    call strcpy_fwd
    mov rsi, current_uid
    call strcpy_fwd
    mov rsi, form_uid_id_bridge
    call strcpy_fwd

    push rdi
    mov rdi, [rbx]
    mov rsi, id_str
    call itoa
    pop rdi
    mov rsi, id_str
    call strcpy_fwd

    mov rsi, form_delete_2
    call strcpy_fwd

.next_todo:
    add rbx, 128
    dec r13
    jnz .todo_loop

    ; Close the <ul>, then clear-done form (inside .wrap), then close wrap + script
    mov rsi, html_footer_1
    call strcpy_fwd

    mov rsi, html_clear_done_open
    call strcpy_fwd
    mov rsi, current_uid
    call strcpy_fwd
    mov rsi, html_clear_done_close
    call strcpy_fwd

    mov rsi, html_footer_2
    call strcpy_fwd

    mov rsi, res_buf
    mov rdx, rdi
    sub rdx, res_buf

    mov rax, SYS_WRITE
    mov rdi, r12
    syscall

    pop r13
    pop rbx
    pop rbp
    ret

; strcpy_fwd: copy rsi to rdi, update rdi to end (null not written)
strcpy_fwd:
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .loop
.done:
    ret

; -----------------------------------------------------------------------------
; find_uid_in_url - search first line of request (up to \r/\n/\0) for "uid="
; rdi = request buffer
; Returns rax = ptr to uid value, or 0
; -----------------------------------------------------------------------------
find_uid_in_url:
    mov rsi, rdi
.loop:
    mov al, [rsi]
    test al, al
    jz .not_found
    cmp al, 13
    je .not_found
    cmp al, 10
    je .not_found
    cmp dword [rsi], 0x3d646975  ; "uid="
    je .found
    inc rsi
    jmp .loop
.found:
    lea rax, [rsi+4]
    ret
.not_found:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; find_uid - search body (up to \0) for "uid="
; rdi = body ptr
; Returns rax = ptr to uid value, or 0
; -----------------------------------------------------------------------------
find_uid:
    mov rsi, rdi
.loop:
    mov al, [rsi]
    test al, al
    jz .not_found
    cmp dword [rsi], 0x3d646975  ; "uid="
    je .found
    inc rsi
    jmp .loop
.found:
    lea rax, [rsi+4]
    ret
.not_found:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; copy_uid - copies uid from rdi to current_uid (max 32 chars, hex [a-f0-9] only)
; On invalid char: sets current_uid[0]=0 and returns
; -----------------------------------------------------------------------------
copy_uid:
    mov rsi, rdi
    mov rdi, current_uid
    mov rcx, 32
.loop:
    test rcx, rcx
    jz .null_term
    mov al, [rsi]
    ; validate: '0'-'9' or 'a'-'f'
    cmp al, '0'
    jb .invalid
    cmp al, '9'
    jbe .ok_char
    cmp al, 'a'
    jb .invalid
    cmp al, 'f'
    jbe .ok_char
    ; not valid hex
    jmp .invalid
.ok_char:
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .loop
.null_term:
    mov byte [rdi], 0
    ret
.invalid:
    mov byte [current_uid], 0
    ret
