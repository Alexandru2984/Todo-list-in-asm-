%include "src/defs.inc"
DEFAULT ABS

global parse_date, date_epoch, today_epoch
section .data
    month_days db 31,28,31,30,31,30,31,31,30,31,30,31
section .text
; Exact YYYY-MM-DD, Gregorian, 1970..9999. UTC midnight or -1.
parse_date:
    cmp byte [rdi+4],'-'
    jne .bad
    cmp byte [rdi+7],'-'
    jne .bad
    cmp byte [rdi+10],0
    jne .bad
    xor eax,eax
    xor ecx,ecx
.year:
    movzx edx,byte [rdi+rcx]
    sub edx,'0'
    cmp edx,9
    ja .bad
    imul eax,10
    add eax,edx
    inc ecx
    cmp ecx,4
    jb .year
    push rax
    lea rsi,[rdi+5]
    call two_digits
    test rax,rax
    js .pop_bad
    push rax
    lea rsi,[rdi+8]
    call two_digits
    mov rdx,rax
    pop rsi
    pop rdi
    jmp date_epoch
.pop_bad:
    pop rax
.bad:
    mov rax,-1
    ret

two_digits:
    movzx eax,byte [rsi]
    sub eax,'0'
    cmp eax,9
    ja .bad
    imul eax,10
    movzx edx,byte [rsi+1]
    sub edx,'0'
    cmp edx,9
    ja .bad
    add eax,edx
    ret
.bad:
    mov rax,-1
    ret

; rdi=year, rsi=month, rdx=day. UTC epoch or -1; no locale/runtime.
date_epoch:
    cmp rdi,1970
    jb .bad
    cmp rdi,9999
    ja .bad
    test rsi,rsi
    jz .bad
    cmp rsi,12
    ja .bad
    test rdx,rdx
    jle .bad
    mov r8,rdx
    xor r9d,r9d ; leap flag
    test edi,3
    jnz .month
    mov rax,rdi
    xor edx,edx
    mov ecx,100
    div rcx
    test rdx,rdx
    jnz .leap
    test eax,3 ; centuries divisible by 400
    jnz .month
.leap:
    mov r9d,1
.month:
    movzx ecx,byte [month_days+rsi-1]
    cmp rsi,2
    jne .check_day
    add ecx,r9d
.check_day:
    cmp r8,rcx
    ja .bad
    lea r10,[rdi-1]
    imul r11,r10,365
    mov rax,r10
    shr rax,2
    add r11,rax
    mov rax,r10
    xor edx,edx
    mov ecx,100
    div rcx
    sub r11,rax
    mov rax,r10
    shr rax,4
    xor edx,edx
    mov ecx,25
    div rcx
    add r11,rax ; floor((year-1)/400)
    sub r11,719162 ; days preceding 1970-01-01
    mov ecx,1
.months:
    cmp rcx,rsi
    jae .finish
    movzx eax,byte [month_days+rcx-1]
    add r11,rax
    inc ecx
    jmp .months
.finish:
    cmp rsi,2
    jbe .day
    add r11,r9
.day:
    lea rax,[r11+r8-1]
    imul rax,86400
    ret
.bad:
    mov rax,-1
    ret

today_epoch:
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    xor edx,edx
    mov ecx,86400
    div rcx
    imul rax,86400
    ret
