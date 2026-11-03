%include "src/defs.inc"
DEFAULT ABS
extern get_todo_list, itoa, format_utc, copy_string

extern export_json_metadata, export_csv_metadata
global export_json, export_csv, json_string, json_date, csv_title, csv_formula
section .data
    json_open db '{"version":2,"exportedAt":',0
    json_tasks db ',"tasks":[',0
    json_trash db '],"trash":[',0
    json_id db '{"id":"',0
    json_title db '","title":',0
    json_done db ',"completed":',0
    json_created db ',"createdAt":',0
    lit_true db 'true',0
    lit_false db 'false',0
    lit_null db 'null',0
    csv_header db 0xef,0xbb,0xbf,'"id","title","completed","createdAt","priority","dueDate","completedAt","project","tags","parentId","dependencies","recurrence","recurrenceAnchor","stage","deletedAt","previousCompleted","escapeFlags"',13,10,0
section .bss
    stamp resb 24
    decimal resb 24
section .text

; JSON string writer. Input is validated UTF-8; escapes JSON syntax.
; rdi=output, rsi=input; rdi advances. No untrusted text enters HTML here.
json_string:
    mov byte [rdi],'"'
    inc rdi
.loop:
    lodsb
    test al,al
    jz .end
    cmp al,'"'
    je .escape
    cmp al,92
    je .escape
    stosb
    jmp .loop
.escape:
    mov byte [rdi],92
    inc rdi
    stosb
    jmp .loop
.end:
    mov byte [rdi],'"'
    inc rdi
    ret

; rax=epoch seconds; append ISO-8601 UTC string or null.
json_date:
    push rdi
    mov rdi,rax
    mov rsi,stamp
    call format_utc
    pop rdi
    test rax,rax
    jz .null
    mov rsi,stamp
    jmp json_string
.null:
    mov rsi,lit_null
    jmp copy_string

; Caller provides 2 MiB output, more than the bounded 1000 records require.
export_json:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r15d,r15d
    mov r12,rdi
    mov rsi,json_open
    call copy_string
    push rdi
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    pop rdi
    call json_date
    mov rsi,json_tasks
    call copy_string
    push rdi
    call get_todo_list
    mov rbx,rax
    pop rdi
    mov r13d,SLOT_MAX
    xor r14d,r14d
.loop:
    cmp qword [rbx],0
    je .next
    cmp byte [rbx+8],2
    sete al
    movzx eax,al
    cmp rax,r15
    jne .next
    test r14,r14
    jz .record
    mov byte [rdi],','
    inc rdi
.record:
    inc r14
    mov rsi,json_id
    call copy_string
    push rdi
    mov rdi,[rbx]
    mov rsi,decimal
    call itoa
    pop rdi
    mov rsi,decimal
    call copy_string
    mov rsi,json_title
    call copy_string
    lea rsi,[rbx+17]
    call json_string
    mov rsi,json_done
    call copy_string
    mov rsi,lit_true
    cmp byte [rbx+8],1
    je .boolean
    mov rsi,lit_false
.boolean:
    call copy_string
    mov rsi,json_created
    call copy_string
    mov rax,[rbx+9]
    call json_date
    mov rsi,rbx
    call export_json_metadata
    mov byte [rdi],'}'
    inc rdi
.next:
    add rbx,TASK_SIZE
    dec r13
    jnz .loop
    test r15,r15
    jnz .finish
    inc r15
    mov rsi,json_trash
    call copy_string
    push rdi
    call get_todo_list
    mov rbx,rax
    pop rdi
    mov r13d,SLOT_MAX
    xor r14d,r14d
    jmp .loop
.finish:
    mov word [rdi],']}'
    mov byte [rdi+2],10
    lea rax,[rdi+3]
    sub rax,r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Detect spreadsheet formula prefixes even after Unicode whitespace.
; rsi=title; preserves rsi/rdi. UTF-8 whitespace sequences are bounded by NUL.
csv_formula:
    push rsi
.loop:
    movzx eax,byte [rsi]
    cmp al,' '
    je .one
    cmp al,0xc2
    jne .three
    cmp byte [rsi+1],0xa0
    jne .formula
    add rsi,2
    jmp .loop
.three:
    cmp al,0xe1
    jne .e2
    cmp byte [rsi+1],0x9a
    jne .formula
    cmp byte [rsi+2],0x80
    je .skip_three
    jmp .formula
.e2:
    cmp al,0xe2
    jne .e3
    cmp byte [rsi+1],0x80
    jne .e2_81
    mov al,[rsi+2]
    cmp al,0x80
    jb .formula
    cmp al,0x8a
    jbe .skip_three
    cmp al,0xa8
    je .skip_three
    cmp al,0xa9
    je .skip_three
    cmp al,0xaf
    je .skip_three
    jmp .formula
.e2_81:
    cmp byte [rsi+1],0x81
    jne .formula
    cmp byte [rsi+2],0x9f
    je .skip_three
    jmp .formula
.e3:
    cmp al,0xe3
    jne .bom
    cmp byte [rsi+1],0x80
    jne .formula
    cmp byte [rsi+2],0x80
    je .skip_three
    jmp .formula
.bom:
    cmp al,0xef
    jne .formula
    cmp byte [rsi+1],0xbb
    jne .formula
    cmp byte [rsi+2],0xbf
    je .skip_three
    jmp .formula
.skip_three:
    add rsi,3
    jmp .loop
.one:
    inc rsi
    jmp .loop
.formula:
    mov al,[rsi]
    cmp al,'='
    je .yes
    cmp al,'+'
    je .yes
    cmp al,'-'
    je .yes
    cmp al,'@'
    je .yes
    xor eax,eax
    pop rsi
    ret
.yes:
    mov eax,1
    pop rsi
    ret

csv_title:
    mov byte [rdi],'"'
    inc rdi
    call csv_formula
    test eax,eax
    jz .loop
    mov byte [rdi],39
    inc rdi
.loop:
    lodsb
    test al,al
    jz .end
    cmp al,'"'
    jne .put
    stosb
.put:
    stosb
    jmp .loop
.end:
    mov byte [rdi],'"'
    inc rdi
    ret

export_csv:
    push rbx
    push r12
    push r13
    mov r12,rdi
    mov rsi,csv_header
    call copy_string
    push rdi
    call get_todo_list
    mov rbx,rax
    pop rdi
    mov r13d,SLOT_MAX
.loop:
    cmp qword [rbx],0
    je .next

    mov byte [rdi],'"'
    inc rdi
    push rdi
    mov rdi,[rbx]
    mov rsi,decimal
    call itoa
    pop rdi
    mov rsi,decimal
    call copy_string
    mov word [rdi],'",'
    add rdi,2
    lea rsi,[rbx+17]
    call csv_title
    mov word [rdi],',"'
    add rdi,2
    mov rsi,lit_true
    cmp byte [rbx+8],1
    je .boolean
    mov rsi,lit_false
.boolean:
    call copy_string
    mov dword [rdi],'","'
    add rdi,3
    push rdi
    mov rdi,[rbx+9]
    mov rsi,stamp
    call format_utc
    pop rdi
    test rax,rax
    jz .end_record
    mov rsi,stamp
    call copy_string
.end_record:
    mov byte [rdi],'"'
    inc rdi
    mov rsi,rbx
    call export_csv_metadata
    mov word [rdi],0x0a0d
    add rdi,2
.next:
    add rbx,TASK_SIZE
    dec r13
    jnz .loop
    mov rax,rdi
    sub rax,r12
    pop r13
    pop r12
    pop rbx
    ret
