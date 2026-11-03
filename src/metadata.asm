%include "src/defs.inc"
DEFAULT ABS
extern parse_uint, valid_utf8, itoa, split_field, find_any_todo

global copy_metadata_text
global parse_metadata, format_metadata, validate_metadata_graph
section .data
    ; On disk: A|id|priority|due|completed|parent|repeat|project|tags|deps|
    ; stage|deleted|previous|anchor. Exactly thirteen fields after A|.
    numeric_offsets dq T_PRIORITY,T_DUE,T_COMPLETED,T_PARENT,T_REPEAT
                    dq T_STAGE,T_DELETED,T_PREVIOUS,T_ANCHOR
section .bss
    fields resq 13
    number resb 24
section .text
; rdi=source, rsi=destination, edx=max bytes. UTF-8, no format/control bytes.
copy_metadata_text:
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
    xor ecx,ecx
.loop:
    mov al,[rbx+rcx]
    test al,al
    jz .utf8
    cmp al,32
    jb .bad
    cmp al,127
    je .bad
    cmp al,'|'
    je .bad
    inc ecx
    cmp ecx,edx
    ja .bad
    jmp .loop
.utf8:
    call valid_utf8
    test rax,rax
    js .bad
    mov rdi,r12
    mov rsi,rbx
.copy:
    lodsb
    stosb
    test al,al
    jnz .copy
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r12
    pop rbx
    ret

parse_metadata:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    xor r12d,r12d
.split:
    mov [fields+r12*8],rbx
    cmp r12,12
    je .last
    mov rdi,rbx
    mov dl,'|'
    call split_field
    test rax,rax
    jz .bad
    mov rbx,rax
    inc r12
    jmp .split
.last:
    mov rdi,rbx
.no_extra:
    cmp byte [rdi],0
    je .id
    cmp byte [rdi],'|'
    je .bad
    inc rdi
    jmp .no_extra
.id:
    mov rdi,[fields]
    call parse_uint
    test rax,rax
    jle .bad
    mov rdi,rax
    call find_any_todo
    test rax,rax
    jz .bad
    mov r13,rax
    cmp byte [r13+T_META],0
    jne .bad
    xor r12d,r12d
.numbers:
    mov rax,r12
    cmp r12,5
    jb .index
    add rax,3 ; skip project, tags, dependency string
.index:
    mov rdi,[fields+8+rax*8]
    call parse_uint
    test rax,rax
    js .bad
    mov rdx,[numeric_offsets+r12*8]
    mov [r13+rdx],rax
    inc r12
    cmp r12,9
    jb .numbers
    mov rdi,[fields+6*8]
    lea rsi,[r13+T_PROJECT]
    mov edx,PROJECT_MAX
    call copy_metadata_text
    test rax,rax
    js .bad
    mov rdi,[fields+7*8]
    lea rsi,[r13+T_TAGS]
    mov edx,TAGS_MAX
    call copy_metadata_text
    test rax,rax
    js .bad
    mov rbx,[fields+8*8]
    xor r12d,r12d
    cmp byte [rbx],0
    je .validate
.dep:
    cmp r12,DEP_MAX
    jae .bad
    mov rdi,rbx
    mov dl,','
    call split_field
    push rax
    mov rdi,rbx
    call parse_uint
    mov rbx,rax
    pop rdx
    test rbx,rbx
    jle .bad
    mov [r13+T_DEPS+r12*8],rbx
    inc r12
    test rdx,rdx
    jz .validate
    mov rbx,rdx
    cmp byte [rbx],0
    je .bad
    jmp .dep
.validate:
    mov [r13+T_DEP_COUNT],r12
    cmp qword [r13+T_PRIORITY],3
    ja .bad
    mov rax,[r13+T_DUE]
    mov rdx,253402214400
    cmp rax,rdx
    ja .bad
    xor edx,edx
    mov ecx,86400
    div rcx
    test rdx,rdx
    jnz .bad
    mov rax,253402300799
    cmp [r13+T_COMPLETED],rax
    ja .bad
    cmp [r13+T_DELETED],rax
    ja .bad
    cmp qword [r13+T_REPEAT],5
    ja .bad
    cmp qword [r13+T_STAGE],1
    ja .bad
    cmp qword [r13+T_PREVIOUS],1
    ja .bad
    cmp byte [r13+8],0
    jne .deleted
    cmp qword [r13+T_COMPLETED],0
    jne .bad
.deleted:
    cmp byte [r13+8],2
    jne .live
    cmp qword [r13+T_DELETED],0
    je .bad
    jmp .repeat
.live:
    cmp qword [r13+T_DELETED],0
    jne .bad
.repeat:
    cmp qword [r13+T_REPEAT],0
    je .zero_anchor
    cmp qword [r13+T_DUE],0
    je .bad
    cmp qword [r13+T_REPEAT],4
    jb .zero_anchor
    mov rax,[r13+T_ANCHOR]
    cmp qword [r13+T_REPEAT],5
    je .year_anchor
    test rax,rax
    jz .bad
    cmp rax,31
    ja .bad
    jmp .ok
.year_anchor:
    xor edx,edx
    mov ecx,100
    div rcx
    test rax,rax
    jz .bad
    cmp rax,12
    ja .bad
    test rdx,rdx
    jz .bad
    mov ecx,31
    cmp rax,2
    jne .thirty
    mov ecx,29 ; allow leap-day anchor
    jmp .day
.thirty:
    cmp rax,4
    je .short
    cmp rax,6
    je .short
    cmp rax,9
    je .short
    cmp rax,11
    jne .day
.short:
    mov ecx,30
.day:
    cmp rdx,rcx
    ja .bad
    jmp .ok
.zero_anchor:
    cmp qword [r13+T_ANCHOR],0
    jne .bad
.ok:
    mov byte [r13+T_META],1
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Append nonnegative integer to output rdi, advance rdi.
emit_decimal:
    push rdi
    mov rdi,rax
    mov rsi,number
    call itoa
    pop rdi
    mov rsi,number
.copy:
    lodsb
    test al,al
    jz .done
    stosb
    jmp .copy
.done:
    ret
emit_text:
    lodsb
    test al,al
    jz .done
    stosb
    jmp emit_text
.done:
    ret

; rdi=slot, rsi=output (1024 bytes); rax=length, newline included.
format_metadata:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    mov rdi,rsi
    mov r13,rsi
    mov word [rdi],'A|'
    add rdi,2
    mov rax,[rbx]
    call emit_decimal
    xor r12d,r12d
.number:
    mov byte [rdi],'|'
    inc rdi
    mov rdx,[numeric_offsets+r12*8]
    mov rax,[rbx+rdx]
    call emit_decimal
    inc r12
    cmp r12,5
    jb .number
    mov byte [rdi],'|'
    inc rdi
    lea rsi,[rbx+T_PROJECT]
    call emit_text
    mov byte [rdi],'|'
    inc rdi
    lea rsi,[rbx+T_TAGS]
    call emit_text
    mov byte [rdi],'|'
    inc rdi
    xor r12d,r12d
.deps:
    cmp r12,[rbx+T_DEP_COUNT]
    jae .rest
    test r12,r12
    jz .dep_number
    mov byte [rdi],','
    inc rdi
.dep_number:
    mov rax,[rbx+T_DEPS+r12*8]
    call emit_decimal
    inc r12
    jmp .deps
.rest:
    mov r12d,5
.rest_loop:
    mov byte [rdi],'|'
    inc rdi
    mov rdx,[numeric_offsets+r12*8]
    mov rax,[rbx+rdx]
    call emit_decimal
    inc r12
    cmp r12,9
    jb .rest_loop
    mov byte [rdi],10
    lea rax,[rdi+1]
    sub rax,r13
    pop r13
    pop r12
    pop rbx
    ret

; Graph edges are task -> prerequisites and parent -> children. Checking their
; union prevents a dependency/parent combination from deadlocking completion.
; All fields have already passed scalar/text bounds. Recursion <= SLOT_MAX.
validate_metadata_graph:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    mov r12,rdi
    mov r13d,SLOT_MAX
.clear:
    mov byte [r12+T_COLOR],0
    cmp qword [r12],0
    je .next_clear
    cmp byte [r12+T_META],1
    jne .bad
    mov rdi,[r12+T_PARENT]
    test rdi,rdi
    jz .deps
    cmp rdi,[r12]
    je .bad
    call find_any_todo
    test rax,rax
    jz .bad
.deps:
    xor r8d,r8d
.dep:
    cmp r8,[r12+T_DEP_COUNT]
    jae .next_clear
    mov rdi,[r12+T_DEPS+r8*8]
    cmp rdi,[r12]
    je .bad
    call find_any_todo
    test rax,rax
    jz .bad
    xor r9d,r9d
.unique:
    cmp r9,r8
    jae .unique_ok
    mov rax,[r12+T_DEPS+r9*8]
    cmp rax,[r12+T_DEPS+r8*8]
    je .bad
    inc r9
    jmp .unique
.unique_ok:
    inc r8
    jmp .dep
.next_clear:
    add r12,TASK_SIZE
    dec r13
    jnz .clear
    mov r12,rbx
    mov r13d,SLOT_MAX
.roots:
    cmp qword [r12],0
    je .next_root
    mov rdi,r12
    call visit
    test rax,rax
    js .bad
.next_root:
    add r12,TASK_SIZE
    dec r13
    jnz .roots
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r13
    pop r12
    pop rbx
    ret

visit:
    cmp byte [rdi+T_COLOR],2
    je .visited
    cmp byte [rdi+T_COLOR],1
    je .cycle
    push rbx
    push r12
    push r13
    mov rbx,rdi
    mov byte [rbx+T_COLOR],1
    xor r12d,r12d
.deps:
    cmp r12,[rbx+T_DEP_COUNT]
    jae .children
    mov rdi,[rbx+T_DEPS+r12*8]
    call find_any_todo
    mov rdi,rax
    call visit
    test rax,rax
    js .bad
    inc r12
    jmp .deps
.children:
    ; find_any_todo(0) returns the array base for internal traversal.
    xor edi,edi
    call find_any_todo
    mov r12,rax
    mov r13d,SLOT_MAX
.child:
    cmp qword [r12],0
    je .next
    mov rax,[rbx]
    cmp [r12+T_PARENT],rax
    jne .next
    mov rdi,r12
    call visit
    test rax,rax
    js .bad
.next:
    add r12,TASK_SIZE
    dec r13
    jnz .child
    mov byte [rbx+T_COLOR],2
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r13
    pop r12
    pop rbx
    ret
.visited:
    xor eax,eax
    ret
.cycle:
    mov rax,-500
    ret
