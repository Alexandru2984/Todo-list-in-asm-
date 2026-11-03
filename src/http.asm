%include "src/defs.inc"
DEFAULT ABS

global validate_request, request_method, request_path, request_body
 global request_cookie, request_origin, request_host, request_site
section .data
    h_cl db 'content-length',0
    h_te db 'transfer-encoding',0
    h_host db 'host',0
    h_cookie db 'cookie',0
    h_origin db 'origin',0
    h_site db 'sec-fetch-site',0
    h_type db 'content-type',0
    h_expect db 'expect',0
    form_type db 'application/x-www-form-urlencoded',0
section .bss
    request_method resq 1 ; 1 GET, 2 POST, 3 HEAD, 4 other
    request_path resb PATH_MAX
    request_body resq 1
    request_host resb 256
    request_cookie resb 1024
    request_origin resb 256
    request_site resb 32
    request_type resb 128
    header_flags resq 1
    body_length resq 1
    name_end resq 1
section .text

; Compare a bounded ASCII header name to a lowercase literal.
; rdi=name, rdx=name length, rsi=literal; returns 0 if equal.
header_is:
    xor ecx,ecx
.loop:
    cmp rcx,rdx
    je .end
    mov al,[rdi+rcx]
    cmp al,'A'
    jb .lower
    cmp al,'Z'
    ja .lower
    add al,32
.lower:
    cmp al,[rsi+rcx]
    jne .no
    inc rcx
    jmp .loop
.end:
    cmp byte [rsi+rcx],0
    jne .no
    xor eax,eax
    ret
.no:
    mov eax,1
    ret

; rdi=start, rsi=exclusive end. Strict CRLF, no NUL/bare LF/control.
line_end:
    mov rax,rdi
.loop:
    cmp rax,rsi
    jae .bad
    mov dl,[rax]
    cmp dl,13
    je .cr
    cmp dl,9
    je .next
    cmp dl,32
    jb .bad
    cmp dl,127
    je .bad
.next:
    inc rax
    jmp .loop
.cr:
    lea rdx,[rax+1]
    cmp rdx,rsi
    jae .bad
    cmp byte [rax+1],10
    jne .bad
    ret
.bad:
    xor eax,eax
    ret

%macro COPY_HEADER 4
    mov rdi,r14
    mov rsi,%1
    mov rdx,[name_end]
    sub rdx,r14
    call header_is
    test rax,rax
    jnz %%next
    test qword [header_flags],%2
    jnz .bad
    or qword [header_flags],%2
    cmp r8,%4-1
    ja .bad
    mov rdi,%3
    mov rsi,r9
    mov rcx,r8
    rep movsb
    mov byte [rdi],0
    jmp .next_header
%%next:
%endmacro

; Returns 0 while incomplete, total bytes when complete, or negative HTTP status.
; Never mutates input. Rejects request pipelining: exactly one request/connection.
validate_request:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx,rdi
    mov r12,rsi
    cmp r12,4
    jb .incomplete
    mov rcx,r12
    sub rcx,3
    xor edx,edx
.find_end:
    cmp dword [rbx+rdx],0x0a0d0a0d
    je .headers_found
    inc rdx
    cmp rdx,rcx
    jb .find_end
    jmp .incomplete
.headers_found:
    lea r13,[rbx+rdx+4]
    mov qword [header_flags],0
    mov qword [body_length],0
    mov byte [request_host],0
    mov byte [request_cookie],0
    mov byte [request_origin],0
    mov byte [request_site],0
    mov byte [request_type],0
    mov rdi,rbx
    mov rsi,r13
    call line_end
    test rax,rax
    jz .bad
    mov r15,rax
    mov r14,rbx
    mov qword [request_method],4
    cmp dword [r14],'GET '
    jne .post
    mov qword [request_method],1
    add r14,4
    jmp .target
.post:
    cmp dword [r14],'POST'
    jne .head
    cmp byte [r14+4],' '
    jne .other
    mov qword [request_method],2
    add r14,5
    jmp .target
.head:
    cmp dword [r14],'HEAD'
    jne .other
    cmp byte [r14+4],' '
    jne .other
    mov qword [request_method],3
    add r14,5
    jmp .target
.other:
    xor ecx,ecx
.method_loop:
    cmp r14,r15
    jae .bad
    mov al,[r14]
    inc r14
    cmp al,' '
    je .target
    sub al,'A'
    cmp al,25
    ja .bad
    inc ecx
    cmp ecx,16
    ja .bad
    jmp .method_loop
.target:
    cmp byte [r14],'/'
    jne .bad
    xor ecx,ecx
.target_loop:
    cmp r14,r15
    jae .bad
    mov al,[r14]
    inc r14
    cmp al,' '
    je .version
    cmp al,33
    jb .bad
    cmp al,126
    ja .bad
    cmp al,92 ; backslash
    je .bad
    cmp al,'#'
    je .bad
    cmp rcx,PATH_MAX-1
    jae .large
    mov [request_path+rcx],al
    inc rcx
    jmp .target_loop
.version:
    mov byte [request_path+rcx],0
    mov rax,r15
    sub rax,r14
    cmp rax,8
    jne .bad
    mov rax,0x312e312f50545448 ; HTTP/1.1
    cmp [r14],rax
    je .header_start
    mov rax,0x302e312f50545448 ; HTTP/1.0
    cmp [r14],rax
    jne .bad
.header_start:
    lea r14,[r15+2]
.header_loop:
    lea rax,[r13-2]
    cmp r14,rax
    je .headers_done
    ja .bad
    mov rdi,r14
    mov rsi,r13
    call line_end
    test rax,rax
    jz .bad
    mov r15,rax
    mov rdi,r14
.name_loop:
    cmp rdi,r15
    jae .bad
    mov al,[rdi]
    cmp al,':'
    je .colon
    ; Header names used by browsers/proxies: ASCII token without whitespace.
    cmp al,33
    jb .bad
    cmp al,126
    ja .bad
    cmp al,'('
    je .bad
    cmp al,')'
    je .bad
    cmp al,','
    je .bad
    cmp al,';'
    je .bad
    cmp al,'/'
    je .bad
    cmp al,92
    je .bad
    cmp al,'"'
    je .bad
    cmp al,'['
    je .bad
    cmp al,']'
    je .bad
    cmp al,'?'
    je .bad
    cmp al,'='
    je .bad
    cmp al,'{'
    je .bad
    cmp al,'}'
    je .bad
    inc rdi
    jmp .name_loop
.colon:
    cmp rdi,r14
    je .bad
    mov [name_end],rdi
    lea r9,[rdi+1]
    mov r10,r15
.trim_start:
    cmp r9,r10
    jae .trim_done
    cmp byte [r9],' '
    je .trim_inc
    cmp byte [r9],9
    jne .trim_end
.trim_inc:
    inc r9
    jmp .trim_start
.trim_end:
    cmp r10,r9
    jbe .trim_done
    cmp byte [r10-1],' '
    je .trim_dec
    cmp byte [r10-1],9
    jne .trim_done
.trim_dec:
    dec r10
    jmp .trim_end
.trim_done:
    mov r8,r10
    sub r8,r9
    COPY_HEADER h_host,2,request_host,256
    COPY_HEADER h_cookie,4,request_cookie,1024
    COPY_HEADER h_origin,8,request_origin,256
    COPY_HEADER h_site,16,request_site,32
    COPY_HEADER h_type,32,request_type,128
    mov rdi,r14
    mov rsi,h_te
    mov rdx,[name_end]
    sub rdx,r14
    call header_is
    test rax,rax
    jz .bad ; transfer coding is unsupported; never interpret it as Content-Length
    mov rsi,h_expect
    call header_is
    test rax,rax
    jz .expect
    mov rsi,h_cl
    call header_is
    test rax,rax
    jnz .next_header
    test qword [header_flags],1
    jnz .bad
    or qword [header_flags],1
    test r8,r8
    jz .bad
    xor eax,eax
.cl_loop:
    movzx ecx,byte [r9]
    sub ecx,'0'
    cmp ecx,9
    ja .bad
    imul rax,10
    add rax,rcx
    cmp rax,REQUEST_MAX
    ja .large
    inc r9
    cmp r9,r10
    jb .cl_loop
    mov [body_length],rax
.next_header:
    lea r14,[r15+2]
    jmp .header_loop
.headers_done:
    cmp byte [request_host],0
    je .bad
    cmp qword [request_method],2
    jne .no_body
    test qword [header_flags],1
    jz .length_required
    mov rdi,request_type
    mov rsi,form_type
    xor ecx,ecx
.type_loop:
    cmp byte [rsi+rcx],0
    je .type_end
    mov al,[rdi+rcx]
    or al,32
    cmp al,[rsi+rcx]
    jne .media
    inc rcx
    jmp .type_loop
.type_end:
    cmp byte [rdi+rcx],0
    je .framing
    cmp byte [rdi+rcx],';'
    jne .media
    jmp .framing
.no_body:
    cmp qword [body_length],0
    jne .bad
.framing:
    mov rax,r13
    sub rax,rbx
    add rax,[body_length]
    cmp rax,REQUEST_MAX
    ja .large
    cmp r12,rax
    jb .incomplete
    ja .bad
    mov [request_body],r13
    mov rcx,[body_length]
    mov rdi,r13
.body_check:
    test rcx,rcx
    jz .return
    cmp byte [rdi],0
    je .bad
    inc rdi
    dec rcx
    jmp .body_check
.incomplete:
    xor eax,eax
    jmp .return
.bad:
    mov rax,-400
    jmp .return
.large:
    mov rax,-413
    jmp .return
.length_required:
    mov rax,-411
    jmp .return
.media:
    mov rax,-415
    jmp .return
.expect:
    mov rax,-417
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
