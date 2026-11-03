%include "src/defs.inc"
%include "src/import.inc"
DEFAULT ABS
extern import_reset, import_tasks, import_count, import_set_text
extern import_validate_task, import_validate, todos, lookup_array

global import_lines
section .text
; Explicit quick capture: one literal title per LF/CRLF line. Trim outer ASCII
; spaces/tabs, ignore blank lines, reject bare CR and invalid/oversized titles.
; Reuse the bounded native import transaction; source IDs are local 1..1000.
import_lines:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    call import_reset
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    test rax,rax
    js .bad
    mov r13,rax
    cmp word [r12],0xbbef
    jne .line
    cmp byte [r12+2],0xbf
    jne .line
    add r12,3
.line:
    cmp byte [r12],0
    je .validate
    mov r14,r12
.scan:
    mov al,[r12]
    test al,al
    jz .end_line
    cmp al,10
    je .lf
    cmp al,13
    je .crlf
    inc r12
    jmp .scan
.crlf:
    cmp byte [r12+1],10
    jne .bad
    mov r15,r12
    add r12,2
    jmp .trim
.lf:
    mov r15,r12
    inc r12
    jmp .trim
.end_line:
    mov r15,r12
.trim:
    cmp r14,r15
    jae .line
    cmp byte [r14],' '
    je .left
    cmp byte [r14],9
    jne .right
.left:
    inc r14
    jmp .trim
.right:
    cmp r14,r15
    jae .line
    cmp byte [r15-1],' '
    je .shorten
    cmp byte [r15-1],9
    jne .task
.shorten:
    dec r15
    jmp .right
.task:
    mov byte [r15],0
    mov rax,[import_count]
    cmp rax,TASK_MAX
    jae .bad
    mov rbx,rax
    shl rbx,9
    add rbx,import_tasks
    inc rax
    mov [rbx],rax
    mov [rbx+9],r13
    mov qword [rbx+I_FIELDS],15
    mov rdi,rbx
    mov esi,1
    mov rdx,r14
    call import_set_text
    test rax,rax
    js .bad
    mov rdi,rbx
    call import_validate_task
    test rax,rax
    js .bad
    inc qword [import_count]
    jmp .line
.validate:
    cmp qword [import_count],0
    je .bad
    call import_validate
    jmp .done
.bad:
    mov rax,-422
.done:
    mov qword [lookup_array],todos
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
