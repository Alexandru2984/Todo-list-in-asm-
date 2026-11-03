%include "src/defs.inc"
DEFAULT ABS
extern valid_utf8

global csv_begin, csv_next, csv_text, csv_endrow
section .bss
    cursor resq 1
    pending resq 1
    csv_text resq 1
    csv_endrow resq 1
section .text
csv_begin:
    cmp word [rdi],0xbbef
    jne .start
    cmp byte [rdi+2],0xbf
    jne .start
    add rdi,3
.start:
    mov [cursor],rdi
    mov qword [pending],0
    ret

; RFC-style quoted fields decode in place. CRLF and LF records are accepted;
; embedded newlines are lexed, then rejected by bounded task-field validation.
; Returns 1 field / 0 EOF / -422 malformed, csv_endrow indicates row boundary.
csv_next:
    push rbx
    push r12
    push r13
    mov rbx,[cursor]
    mov qword [csv_endrow],0
    cmp byte [rbx],0
    jne .field
    cmp qword [pending],0
    je .eof
.field:
    mov r12,rbx
    mov r13,rbx
    cmp byte [rbx],'"'
    jne .plain
    inc rbx
    mov r12,rbx
    mov r13,rbx
.quoted:
    mov al,[rbx]
    test al,al
    jz .bad
    inc rbx
    cmp al,'"'
    jne .quoted_put
    cmp byte [rbx],'"'
    jne .delimiter
    inc rbx
.quoted_put:
    mov [r13],al
    inc r13
    jmp .quoted
.plain:
    mov al,[rbx]
    test al,al
    jz .delimiter
    cmp al,','
    je .delimiter
    cmp al,13
    je .delimiter
    cmp al,10
    je .delimiter
    cmp al,'"'
    je .bad
    mov [r13],al
    inc r13
    inc rbx
    jmp .plain
.delimiter:
    mov al,[rbx]
    cmp al,','
    je .comma
    cmp al,13
    je .crlf
    cmp al,10
    je .lf
    test al,al
    jnz .bad
    jmp .row_end
.comma:
    inc rbx
    mov qword [pending],1
    jmp .finish
.crlf:
    cmp byte [rbx+1],10
    jne .bad
    inc rbx
.lf:
    inc rbx
.row_end:
    mov qword [pending],0
    mov qword [csv_endrow],1
.finish:
    mov byte [r13],0
    mov [cursor],rbx
    mov [csv_text],r12
    mov rdi,r12
    call valid_utf8
    test rax,rax
    js .bad
    mov eax,1
    jmp .done
.eof:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-422
.done:
    pop r13
    pop r12
    pop rbx
    ret
