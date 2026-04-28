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

global handle_request

section .data
    http_200 db "HTTP/1.1 200 OK", 13, 10, "Content-Type: text/html", 13, 10, "Connection: close", 13, 10, 13, 10, 0
    http_303 db "HTTP/1.1 303 See Other", 13, 10, "Location: /", 13, 10, "Connection: close", 13, 10, 13, 10, 0
    http_404 db "HTTP/1.1 404 Not Found", 13, 10, "Content-Length: 9", 13, 10, "Connection: close", 13, 10, 13, 10, "Not Found", 0

    html_header db "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'>", 10
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
                db "</style></head><body><div class='wrap'>", 10
                db "<h1>ASM TODO</h1>", 10
                db "<form class='af' method='POST' action='/add'>", 10
                db "<input type='text' name='title' placeholder='New task...' required>", 10
                db "<button type='submit'>Add</button>", 10
                db "</form>", 10
                db "<p class='st' id='stats'></p>", 10
                db "<div class='fi'>", 10
                db "<button class='on' data-f='all'>All</button>", 10
                db "<button data-f='active'>Active</button>", 10
                db "<button data-f='done'>Done</button>", 10
                db "</div>", 10
                db "<ul id='tl'>", 10, 0

    html_footer db "</ul></div>", 10
                db "<script>", 10
                db "function fmtDate(ts){if(!ts)return '';return new Date(ts*1000).toLocaleString();}", 10
                db "function filter(t,btn){document.querySelectorAll('.fi button').forEach(function(b){b.classList.remove('on');});btn.classList.add('on');document.querySelectorAll('#tl li').forEach(function(li){if(t==='all')li.style.display='';else if(t==='active')li.style.display=li.dataset.done==='0'?'':'none';else li.style.display=li.dataset.done==='1'?'':'none';});}", 10
                db "function stats(){var items=document.querySelectorAll('#tl li');var n=0;items.forEach(function(li){if(li.dataset.done==='1')n++;});var el=document.getElementById('stats');if(el)el.textContent=items.length+' task'+(items.length!==1?'s':'')+', '+n+' done';}", 10
                db "window.onload=function(){document.querySelectorAll('#tl li .ts').forEach(function(el){var ts=parseInt(el.closest('li').dataset.ts);el.textContent=fmtDate(ts);});stats();document.querySelectorAll('.fi button').forEach(function(b){b.onclick=function(){filter(b.getAttribute('data-f'),b);};});};", 10
                db "</script>", 10
                db "</body></html>", 10, 0

    li_active_1 db "<li data-ts='", 0
    li_active_2 db "' data-done='0'><div class='ti'><span class='tt'>", 0
    li_done_1   db "<li class='done' data-ts='", 0
    li_done_2   db "' data-done='1'><div class='ti'><span class='tt'>", 0
    li_mid      db "</span><span class='ts'></span></div><div class='ta'>", 0

    form_complete_1 db "<form method='POST' action='/complete'><input type='hidden' name='id' value='", 0
    form_complete_2 db "'><button class='bd'>&#10003;</button></form>", 0
    form_delete_1   db "<form method='POST' action='/delete'><input type='hidden' name='id' value='", 0
    form_delete_2   db "'><button class='bx'>&#10007;</button></form></div></li>", 10, 0

    get_root db "GET / ", 0
    post_add db "POST /add ", 0
    post_complete db "POST /complete ", 0
    post_delete db "POST /delete ", 0

    rnrn db 13, 10, 13, 10, 0

section .bss
    res_buf resb 65536
    id_str resb 32

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

    ; Route matching
    mov rdi, rbx
    mov rsi, get_root
    mov rdx, 6
    call strncmp
    test rax, rax
    jz .do_get_root

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
    call send_html
    jmp .done

.do_post_add:
    call extract_body
    test rax, rax
    jz .redirect
    ; rax points to body
    ; look for title=
    mov rdi, rax
    call find_title
    test rax, rax
    jz .redirect
    mov rdi, rax
    call url_decode
    mov rdi, rax
    call append_todo
    jmp .redirect

.do_post_complete:
    call extract_body
    test rax, rax
    jz .redirect
    mov rdi, rax
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
    mov rdi, rax
    call find_id
    test rax, rax
    jz .redirect
    mov rdi, rax
    call atoi
    mov rdi, rax
    call delete_todo
    jmp .redirect

.redirect:
    mov rdi, http_303
    call strlen
    mov rdx, rax
    mov rdi, r12
    mov rsi, http_303
    mov rax, SYS_WRITE
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

; Finds "id=" in string rdi
find_id:
    mov rsi, rdi
.loop:
    cmp byte [rsi], 0
    je .not_found
    cmp word [rsi], 0x6469 ; "id"
    jne .next
    cmp byte [rsi+2], '='
    jne .next
    add rsi, 3
    mov rax, rsi
    ret
.next:
    inc rsi
    jmp .loop
.not_found:
    xor rax, rax
    ret

; In-place URL decode (+ to space, ignore % for simplicity or do basic replace)
url_decode:
    mov rsi, rdi
    mov rax, rdi
.loop:
    mov cl, [rsi]
    test cl, cl
    jz .done
    cmp cl, '+'
    jne .check_pct
    mov byte [rsi], ' '
    jmp .next
.check_pct:
    cmp cl, '&' ; End of param
    je .end_param
.next:
    inc rsi
    jmp .loop
.end_param:
    mov byte [rsi], 0
.done:
    ret

; Render HTML and send to r12 (fd)
send_html:
    push rbp
    mov rbp, rsp
    push rbx
    push r13

    ; We'll build response in res_buf to avoid many small syscalls
    mov rdi, res_buf
    
    ; Copy 200 OK
    mov rsi, http_200
    call strcpy_fwd
    
    ; Copy header
    mov rsi, html_header
    call strcpy_fwd

    ; Loop todos
    push rdi ; save buffer pointer
    call get_todo_list
    mov rbx, rax ; todos array
    pop rdi
    mov r13, 1000

.todo_loop:
    mov rax, [rbx]       ; id
    test rax, rax
    jz .next_todo

    mov cl, [rbx+8]      ; completed flag
    cmp cl, 2            ; deleted?
    je .next_todo

    ; Emit opening <li> tag with timestamp data attribute
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
    mov rdi, [rbx+9]     ; timestamp (unaligned qword, fine on x86-64)
    mov rsi, id_str
    call itoa
    pop rdi
    mov rsi, id_str
    call strcpy_fwd

    ; itoa clobbered rcx — reload completed flag
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
    call strcpy_fwd

    mov rsi, li_mid
    call strcpy_fwd

    ; Complete button only for active items
    mov cl, [rbx+8]
    cmp cl, 1
    je .skip_done_btn

    mov rsi, form_complete_1
    call strcpy_fwd

    push rdi
    mov rdi, [rbx]       ; id
    mov rsi, id_str
    call itoa
    pop rdi
    mov rsi, id_str
    call strcpy_fwd

    mov rsi, form_complete_2
    call strcpy_fwd

.skip_done_btn:
    mov rsi, form_delete_1
    call strcpy_fwd

    push rdi
    mov rdi, [rbx]       ; id
    mov rsi, id_str
    call itoa
    pop rdi
    mov rsi, id_str
    call strcpy_fwd

    mov rsi, form_delete_2  ; closes </form></div></li>
    call strcpy_fwd

.next_todo:
    add rbx, 128
    dec r13
    jnz .todo_loop

    mov rsi, html_footer
    call strcpy_fwd

    ; write buffer
    mov rsi, res_buf
    mov rdx, rdi
    sub rdx, res_buf ; len
    
    mov rax, SYS_WRITE
    mov rdi, r12
    syscall

    pop r13
    pop rbx
    pop rbp
    ret

; strcpy_fwd: copy rsi to rdi, update rdi to end
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
