%include "src/defs.inc"
%include "src/import.inc"
DEFAULT ABS
extern csv_begin, csv_next, csv_text, csv_endrow, csv_formula
extern import_reset, import_tasks, import_count, import_schema
extern import_set_text, import_validate_task, import_validate, import_field_index
extern todos, lookup_array

global import_csv
section .bss
    header_mask resq 1
    column_count resq 1
    columns resq 18
    values resq 18
section .text
import_csv:
    push rbx
    push r12
    push r13
    push r14
    push rdi
    call import_reset
    pop rdi
    call csv_begin
    mov qword [header_mask],0
    mov qword [column_count],0
    mov qword [import_schema],1
.header:
    call csv_next
    cmp rax,1
    jne .bad
    mov rdi,[csv_text]
    call import_field_index
    test rax,rax
    js .bad
    mov r12,rax
    mov ecx,eax
    mov edx,1
    shl rdx,cl
    test [header_mask],rdx
    jnz .bad
    or [header_mask],rdx
    mov rax,[column_count]
    cmp rax,18
    jae .bad
    mov [columns+rax*8],r12
    inc qword [column_count]
    cmp r12,4
    jb .header_end
    mov qword [import_schema],2
.header_end:
    cmp qword [csv_endrow],0
    je .header
    mov rax,[header_mask]
    and eax,15
    cmp eax,15
    jne .bad
.row:
    call csv_next
    test rax,rax
    jz .validate
    js .bad
    mov rax,[import_count]
    cmp rax,SLOT_MAX
    jae .bad
    shl rax,9
    lea rbx,[import_tasks+rax]
    mov rdi,values
    xor eax,eax
    mov ecx,18
    rep stosq
    xor r13d,r13d
.field:
    cmp r13,[column_count]
    jae .bad
    mov rax,[columns+r13*8]
    mov rdx,[csv_text]
    mov [values+rax*8],rdx
    inc r13
    cmp qword [csv_endrow],0
    jne .row_end
    cmp r13,[column_count]
    jae .bad
    call csv_next
    cmp rax,1
    jne .bad
    jmp .field
.row_end:
    cmp r13,[column_count]
    jne .bad
    mov rax,[header_mask]
    mov [rbx+I_FIELDS],rax
    test rax,1<<16
    jz .unescape
    mov rdi,rbx
    mov esi,16
    mov rdx,[values+16*8]
    call import_set_text
    test rax,rax
    js .bad
.unescape:
    mov r13d,1
    mov r14d,1
    call remove_escape
    test rax,rax
    js .bad
    mov r13d,7
    mov r14d,2
    call remove_escape
    test rax,rax
    js .bad
    mov r13d,8
    mov r14d,4
    call remove_escape
    test rax,rax
    js .bad
    xor r13d,r13d
.set:
    mov ecx,r13d
    mov eax,1
    shl rax,cl
    test [header_mask],rax
    jz .next_field
    mov rdi,rbx
    mov rsi,r13
    mov rdx,[values+r13*8]
    call import_set_text
    test rax,rax
    js .bad
.next_field:
    inc r13
    cmp r13,18
    jb .set
    cmp qword [rbx+T_DELETED],0
    setne al
    movzx eax,al
    mov [rbx+I_TRASH],rax
    mov rdi,rbx
    call import_validate_task
    test rax,rax
    js .bad
    inc qword [import_count]
    jmp .row
.validate:
    call import_validate
    jmp .done
.bad:
    mov rax,-422
.done:
    mov qword [lookup_array],todos
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

remove_escape:
    test [rbx+I_ESCAPE],r14
    jz .ok
    mov rsi,[values+r13*8]
    test rsi,rsi
    jz .bad
    cmp byte [rsi],39
    jne .bad
    inc rsi
    call csv_formula
    test rax,rax
    jz .bad
    mov [values+r13*8],rsi
.ok:
    xor eax,eax
    ret
.bad:
    mov rax,-422
    ret
