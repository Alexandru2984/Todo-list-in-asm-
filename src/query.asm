%include "src/defs.inc"
DEFAULT ABS
extern strncmp, strcmp, strlen, unicode_compare, unicode_contains
extern parse_date, priority_names, tag_contains, task_ready

global compile_query, query_matches, query_status
section .data
    p_priority db 'priority:',0
    p_status db 'status:',0
    p_before db 'before:',0
    p_after db 'after:',0
    p_on db 'on:',0
    p_project db 'project:',0
    p_tag db 'tag:',0
    prefixes dq p_priority,p_status,p_before,p_after,p_on,p_project,p_tag
    lengths dq 9,7,7,6,3,8,4
    active db 'active',0
    done db 'done',0
    trash db 'trash',0
    blocked db 'blocked',0
    status_names dq active,done,trash,blocked
section .bss
    query_mask resq 1
    query_status resq 1 ; 0 none, 1 active, 2 done, 3 trash, 4 blocked
    query_priority resq 1
    query_before resq 1
    query_after resq 1
    query_on resq 1
    query_project resq 1
    query_tags resq 8
    query_tag_count resq 1
    query_words resq 64
    query_word_count resq 1
    token_arena resb 2*(QUERY_MAX+1)
section .text
; rdi=input, rsi=output, edx=operator boolean.
; rax=output end, rdx=next input or rax=-400. Quoted phrases support \" and \\.
read_token:
    mov r8,rdi
    mov r9,rsi
    mov r10,rdx
    cmp byte [r8],'"'
    jne .plain
    ; A bare unmatched quote remains a literal free-text character.
    test r10,r10
    jnz .quoted
    lea rax,[r8+1]
.lookahead:
    cmp byte [rax],0
    je .plain
    cmp byte [rax],'"'
    je .found_quote
    cmp byte [rax],92
    jne .advance_quote
    cmp byte [rax+1],0
    je .plain
    inc rax
.advance_quote:
    inc rax
    jmp .lookahead
.found_quote:
    cmp byte [rax+1],0
    je .quoted
    cmp byte [rax+1],' '
    jne .plain
.quoted:
    inc r8
.quoted_loop:
    mov al,[r8]
    test al,al
    jz .bad
    inc r8
    cmp al,'"'
    je .quoted_end
    cmp al,92
    jne .quoted_put
    mov al,[r8]
    cmp al,'"'
    je .escape
    cmp al,92
    je .escape
    mov al,92
    jmp .quoted_put
.escape:
    inc r8
.quoted_put:
    mov [r9],al
    inc r9
    jmp .quoted_loop
.quoted_end:
    cmp byte [r8],0
    je .end
    cmp byte [r8],' '
    jne .bad
    jmp .end
.plain:
    mov al,[r8]
    test al,al
    jz .end
    cmp al,' '
    je .end
    mov [r9],al
    inc r9
    inc r8
    jmp .plain
.end:
    mov byte [r9],0
    lea rax,[r9+1]
    mov rdx,r8
    ret
.bad:
    mov rax,-400
    ret

compile_query:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx,rdi
    mov rdi,query_mask
    xor eax,eax
    mov ecx,(token_arena-query_mask)/8
    rep stosq
    mov r12,token_arena
.next:
    cmp byte [rbx],' '
    jne .token
    inc rbx
    jmp .next
.token:
    cmp byte [rbx],0
    je .ok
    mov r14,-1
    xor r15d,r15d
    cmp byte [rbx],'#'
    jne .prefix
    cmp byte [rbx+1],0
    je .literal
    cmp byte [rbx+1],' '
    je .literal
    mov r14d,6
    inc rbx
    jmp .read
.prefix:
    mov rdi,rbx
    mov rsi,[prefixes+r15*8]
    mov rdx,[lengths+r15*8]
    call strncmp
    test rax,rax
    jz .operator
    inc r15
    cmp r15,7
    jb .prefix
.literal:
    xor edx,edx
    jmp .read_value
.operator:
    mov r14,r15
    add rbx,[lengths+r15*8]
.read:
    mov edx,1
.read_value:
    mov r13,r12
    mov rdi,rbx
    mov rsi,r12
    call read_token
    test rax,rax
    js .done
    mov r12,rax
    mov rbx,rdx
    cmp r14,-1
    je .word
    cmp r14,5 ; quoted empty project matches unassigned tasks
    je .mask
    cmp byte [r13],0
    je .bad
.mask:
    cmp r14,6
    je .tag
    mov ecx,r14d
    mov eax,1
    shl rax,cl
    test [query_mask],rax
    jnz .bad
    or [query_mask],rax
    cmp r14,0
    je .priority
    cmp r14,1
    je .status
    cmp r14,5
    je .project
    mov rdi,r13
    call parse_date
    test rax,rax
    js .bad
    mov rcx,r14
    sub rcx,2
    mov [query_before+rcx*8],rax
    jmp .next
.priority:
    xor r15d,r15d
.priority_loop:
    mov rdi,r13
    mov rsi,[priority_names+r15*8]
    call unicode_compare
    test rax,rax
    jz .priority_value
    inc r15
    cmp r15,4
    jb .priority_loop
    jmp .bad
.priority_value:
    mov [query_priority],r15
    jmp .next
.status:
    xor r15d,r15d
.status_loop:
    mov rdi,r13
    mov rsi,[status_names+r15*8]
    call unicode_compare
    test rax,rax
    jz .status_value
    inc r15
    cmp r15,4
    jb .status_loop
    jmp .bad
.status_value:
    inc r15
    mov [query_status],r15
    jmp .next
.project:
    mov rdi,r13
    call strlen
    cmp rax,PROJECT_MAX
    ja .bad
    mov [query_project],r13
    jmp .next
.tag:
    mov rdi,r13
    call strlen
    cmp rax,24
    ja .bad
    mov rax,[query_tag_count]
    cmp rax,8
    jae .bad
    mov [query_tags+rax*8],r13
    inc qword [query_tag_count]
    jmp .next
.word:
    cmp byte [r13],0
    je .bad
    mov rax,[query_word_count]
    cmp rax,64
    jae .bad
    mov [query_words+rax*8],r13
    inc qword [query_word_count]
    jmp .next
.ok:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

query_matches:
    push rbx
    push r12
    mov rbx,rdi
    test qword [query_mask],1
    jz .status
    mov rax,[query_priority]
    cmp [rbx+T_PRIORITY],rax
    jne .no
.status:
    mov rax,[query_status]
    test rax,rax
    jz .dates
    cmp rax,4
    je .blocked
    dec rax
    cmp [rbx+8],al
    jne .no
    jmp .dates
.blocked:
    cmp byte [rbx+8],0
    jne .no
    mov rdi,rbx
    call task_ready
    test rax,rax
    jnz .no
.dates:
    test qword [query_mask],4|8|16
    jz .project
    mov rax,[rbx+T_DUE]
    test rax,rax
    jz .no
    test qword [query_mask],4
    jz .after
    cmp rax,[query_before]
    jae .no
.after:
    test qword [query_mask],8
    jz .on
    cmp rax,[query_after]
    jbe .no
.on:
    test qword [query_mask],16
    jz .project
    cmp rax,[query_on]
    jne .no
.project:
    test qword [query_mask],32
    jz .tags
    lea rdi,[rbx+T_PROJECT]
    mov rsi,[query_project]
    call unicode_compare
    test rax,rax
    jnz .no
.tags:
    xor r12d,r12d
.tag:
    cmp r12,[query_tag_count]
    jae .words
    lea rdi,[rbx+T_TAGS]
    mov rsi,[query_tags+r12*8]
    call tag_contains
    test rax,rax
    jz .no
    inc r12
    jmp .tag
.words:
    xor r12d,r12d
.word:
    cmp r12,[query_word_count]
    jae .yes
    lea rdi,[rbx+17]
    mov rsi,[query_words+r12*8]
    call unicode_contains
    test rax,rax
    jz .no
    inc r12
    jmp .word
.yes:
    mov eax,1
    jmp .done
.no:
    xor eax,eax
.done:
    pop r12
    pop rbx
    ret
