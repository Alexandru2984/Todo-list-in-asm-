%include "src/defs.inc"
DEFAULT ABS
extern today_epoch, format_utc, date_epoch

global next_occurrence, recurrence_anchor
section .bss
    stamp resb 24
section .text
; rdi=epoch -> rax=year, rdx=month, rcx=day. Date already validated.
components:
    push rbx
    mov rsi,stamp
    call format_utc
    xor eax,eax
    xor ebx,ebx
.year:
    imul eax,10
    movzx edx,byte [stamp+rbx]
    sub edx,'0'
    add eax,edx
    inc ebx
    cmp ebx,4
    jb .year
    movzx edx,byte [stamp+5]
    sub edx,'0'
    imul edx,10
    movzx ecx,byte [stamp+6]
    sub ecx,'0'
    add edx,ecx
    movzx ecx,byte [stamp+8]
    sub ecx,'0'
    imul ecx,10
    movzx ebx,byte [stamp+9]
    sub ebx,'0'
    add ecx,ebx
    pop rbx
    ret

; Initialize month/day anchor only when due date or recurrence actually changes.
recurrence_anchor:
    push rbx
    mov rbx,[rdi+T_REPEAT]
    cmp rbx,4
    jb .zero
    mov rdi,[rdi+T_DUE]
    call components
    mov rax,rcx
    cmp rbx,5
    jne .done
    imul rdx,100
    add rax,rdx
.done:
    pop rbx
    ret
.zero:
    xor eax,eax
    pop rbx
    ret

; rdi=slot. Next due date strictly after both today and the current due date.
; -409 means the calendar cannot represent another occurrence. No mutation.
next_occurrence:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx,rdi
    call today_epoch
    cmp rax,[rbx+T_DUE]
    cmovb rax,[rbx+T_DUE]
    mov r12,rax ; threshold
    mov r13,[rbx+T_REPEAT]
    cmp r13,1
    je .daily
    cmp r13,2
    je .daily
    cmp r13,3
    je .weekly
    cmp r13,4
    je .calendar
    cmp r13,5
    jne .bad
.calendar:
    mov rdi,r12
    call components
    mov r14,rax ; target year
    mov r15,rdx ; target month
    cmp r13,5
    jne .month_candidate
    mov rax,[rbx+T_ANCHOR]
    xor edx,edx
    mov ecx,100
    div rcx
    mov r15,rax
    mov r13,rdx ; yearly day anchor
    jmp .year_candidate
.month_candidate:
    mov r13,[rbx+T_ANCHOR]
.year_candidate:
    ; Try the anchor, clipping to the last valid day of a short month.
    mov r8,r13
.try_day:
    push r8
    mov rdi,r14
    mov rsi,r15
    mov rdx,r8
    call date_epoch
    pop r8
    test rax,rax
    jns .candidate
    cmp r14,9999
    ja .bad
    dec r8
    cmp r8,27
    jae .try_day
    jmp .bad
.candidate:
    cmp rax,r12
    ja .check
    cmp qword [rbx+T_REPEAT],5
    je .next_year
    inc r15
    cmp r15,12
    jbe .year_candidate
    mov r15d,1
.next_year:
    inc r14
    cmp r14,9999
    ja .bad
    jmp .year_candidate
.daily:
    lea rax,[r12+86400]
    cmp r13,2
    jne .check
.weekday:
    push rax
    xor edx,edx
    mov ecx,86400
    div rcx
    add rax,3
    xor edx,edx
    mov ecx,7
    div rcx
    pop rax
    cmp edx,5
    jb .check
    add rax,86400
    jmp .weekday
.weekly:
    mov rax,r12
    sub rax,[rbx+T_DUE]
    xor edx,edx
    mov ecx,7*86400
    div rcx
    inc rax
    imul rax,7*86400
    add rax,[rbx+T_DUE]
.check:
    mov rdx,253402214400
    cmp rax,rdx
    ja .bad
    jmp .done
.bad:
    mov rax,-409
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
