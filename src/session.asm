%include "src/defs.inc"
DEFAULT ABS
extern current_uid, request_cookie, strncmp, strlen

global copy_uid, copy_session_key, parse_cookie, session_key, session_key_length
section .data
    cookie_key db 'asm_uid=',0
section .bss
    session_key resb 65
    session_key_length resq 1
section .text
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
    jmp copy_session_key
.bad:
    mov rax,-400
    ret

; Strict legacy or rotated credential. The first half is only the storage ID.
copy_session_key:
    push r8
    push r9
    push r10
    push rbx
    mov rbx,rdi
    call strlen
    cmp rax,32
    je .length
    cmp rax,64
    jne .bad
.length:
    mov r10,rax
    xor ecx,ecx
.hex:
    mov al,[rbx+rcx]
    cmp al,'0'
    jb .bad
    cmp al,'9'
    jbe .next
    cmp al,'a'
    jb .bad
    cmp al,'f'
    ja .bad
.next:
    inc rcx
    cmp rcx,r10
    jb .hex
    mov [session_key_length],r10
    mov rdi,session_key
    mov rsi,rbx
    lea rcx,[r10+1]
    rep movsb
    mov rsi,session_key
    mov rdi,current_uid
    mov ecx,32
    rep movsb
    mov byte [rdi],0
    xor eax,eax
    pop rbx
    pop r10
    pop r9
    pop r8
    ret
.bad:
    mov rax,-400
    pop rbx
    pop r10
    pop r9
    pop r8
    ret

; Cookie parser matches only semicolon-delimited asm_uid, rejects duplicates.
parse_cookie:
    mov byte [current_uid],0
    mov byte [session_key],0
    mov qword [session_key_length],0
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
    je .length_ok
    cmp rax,72
    jne .bad
.length_ok:
    mov r11b,[r10]
    mov byte [r10],0
    push r10
    push r11
    lea rdi,[r8+8]
    call copy_session_key
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

