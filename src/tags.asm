%include "src/defs.inc"
DEFAULT ABS
extern unicode_compare, strlen

global normalize_tags, tag_contains
section .bss
    tag_name resb 25
    search_name resb TAGS_MAX+1
section .text
; Match one exact simple-folded UTF-8 tag in a comma-separated list.
; rdi=list, rsi=query. Returns boolean. Input storage is bounded to 64 bytes.
tag_contains:
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
.next:
    mov rdi,search_name
.copy:
    mov al,[rbx]
    cmp al,','
    je .delimiter
    test al,al
    jz .delimiter
    stosb
    inc rbx
    jmp .copy
.delimiter:
    mov byte [rdi],0
    mov rdi,search_name
    mov rsi,r12
    call unicode_compare
    test rax,rax
    jz .yes
    cmp byte [rbx],0
    je .no
    inc rbx
    jmp .next
.yes:
    mov eax,1
    jmp .done
.no:
    xor eax,eax
.done:
    pop r12
    pop rbx
    ret

; rdi=source, rsi=destination. Canonicalize trim/commas, reject empty tags,
; >8 tags, >24 bytes/tag, >64 input bytes and folded duplicates. 0 or -400.
normalize_tags:
    push rbx
    push r12
    push r13
    push r14
    mov rbx,rdi
    mov r12,rsi
    mov r13,rsi
    xor r14d,r14d
    mov byte [r12],0
    call strlen
    cmp rax,TAGS_MAX
    ja .bad
    test rax,rax
    jz .ok
.tag:
    cmp byte [rbx],' '
    jne .start
    inc rbx
    jmp .tag
.start:
    cmp byte [rbx],0
    jne .token
    test r14,r14
    jz .ok
    jmp .bad
.token:
    xor ecx,ecx
.read:
    mov al,[rbx]
    test al,al
    jz .trim
    cmp al,','
    je .trim
    cmp ecx,24
    jae .bad
    mov [tag_name+rcx],al
    inc ecx
    inc rbx
    jmp .read
.trim:
    test ecx,ecx
    jz .bad
    cmp byte [tag_name+rcx-1],' '
    jne .name
    dec ecx
    jmp .trim
.name:
    mov byte [tag_name+rcx],0
    inc r14
    cmp r14,8
    ja .bad
    mov rdi,r13
    mov rsi,tag_name
    call tag_contains
    test rax,rax
    jnz .bad
    cmp r12,r13
    je .append
    mov byte [r12],','
    inc r12
.append:
    mov rsi,tag_name
.copy:
    lodsb
    test al,al
    jz .appended
    mov [r12],al
    inc r12
    jmp .copy
.appended:
    mov byte [r12],0
    cmp byte [rbx],0
    je .ok
    inc rbx
    cmp byte [rbx],0
    je .bad
    jmp .tag
.ok:
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
