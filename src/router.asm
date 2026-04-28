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
    
    html_header db "<!DOCTYPE html><html><head><title>ASM TODO</title>", 10
                db "<style>", 10
                db "body{font-family:sans-serif;max-width:600px;margin:2rem auto;background:#111;color:#eee;}", 10
                db "h1{text-align:center;}", 10
                db "ul{list-style:none;padding:0;}", 10
                db "li{background:#222;margin-bottom:.5rem;padding:1rem;border-radius:4px;display:flex;justify-content:space-between;}", 10
                db ".done{text-decoration:line-through;color:#888;}", 10
                db "input[type=text]{width:70%;padding:.5rem;}", 10
                db "input[type=submit],button{padding:.5rem;background:#007bff;color:#fff;border:none;cursor:pointer;border-radius:4px;}", 10
                db ".btn-del{background:#dc3545;}", 10
                db ".btn-done{background:#28a745;}", 10
                db "form{display:inline;}", 10
                db "</style></head><body>", 10
                db "<h1>ASM TODO</h1>", 10
                db "<form method='POST' action='/add'>", 10
                db "<input type='text' name='title' placeholder='New task...' required>", 10
                db "<input type='submit' value='Add'>", 10
                db "</form><ul>", 10, 0

    html_footer db "</ul></body></html>", 10, 0
    
    li_open db "<li>", 0
    li_open_done db "<li class='done'>", 0
    span_open db "<span>", 0
    span_close db "</span>", 0
    li_close db "</li>", 10, 0

    form_complete_1 db "<div><form method='POST' action='/complete'><input type='hidden' name='id' value='", 0
    form_complete_2 db "'><button class='btn-done'>Done</button></form>", 0
    form_delete_1 db "<form method='POST' action='/delete'><input type='hidden' name='id' value='", 0
    form_delete_2 db "'><button class='btn-del'>Del</button></form></div>", 0

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
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, http_404
    mov rdx, 58 ; approx
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
    mov rax, [rbx] ; id
    test rax, rax
    jz .next_todo
    
    mov cl, [rbx+8] ; completed
    cmp cl, 2 ; deleted
    je .next_todo
    
    ; start li
    cmp cl, 1
    je .li_done
    mov rsi, li_open
    call strcpy_fwd
    jmp .li_cont
.li_done:
    mov rsi, li_open_done
    call strcpy_fwd
.li_cont:
    
    mov rsi, span_open
    call strcpy_fwd

    ; title
    mov rsi, rbx
    add rsi, 17
    call strcpy_fwd

    mov rsi, span_close
    call strcpy_fwd

    ; if not completed, show done btn
    mov cl, [rbx+8]
    cmp cl, 1
    je .skip_done_btn
    mov rsi, form_complete_1
    call strcpy_fwd
    
    push rdi
    mov rdi, [rbx] ; id
    mov rsi, id_str
    call itoa
    pop rdi
    mov rsi, id_str
    call strcpy_fwd

    mov rsi, form_complete_2
    call strcpy_fwd
.skip_done_btn:

    ; del btn
    mov rsi, form_delete_1
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

    mov rsi, li_close
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
