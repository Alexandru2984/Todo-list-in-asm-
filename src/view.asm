%include "src/defs.inc"
DEFAULT ABS
extern strcmp, strlen, parse_uint, decode_value, decode_buf, decode_stripped
extern get_todo_list, find_todo

global parse_view, build_view, view_rows, view_count, view_total, view_done
 global view_active, view_percent, view_filter, view_sort, view_query, view_action
 global view_id, view_target, unicode_compare
section .data
    key_filter db 'f',0
    key_sort db 'sort',0
    key_query db 'q',0
    key_edit db 'edit',0
    key_delete db 'delete',0
    key_confirm db 'confirm',0
    filter_all db 'all',0
    filter_active db 'active',0
    filter_done db 'done',0
    sort_newest db 'newest',0
    sort_oldest db 'oldest',0
    sort_az db 'az',0
    sort_active db 'active',0
    confirm_clear db 'clear',0
    confirm_forget db 'forget',0
section .bss
    view_filter resq 1
    view_sort resq 1
    view_query resb TITLE_MAX+1
    view_action resq 1 ; 0 list, 1 edit, 2 confirm delete, 3 clear, 4 forget
    view_id resq 1
    view_target resq 1
    view_flags resq 1
    view_rows resq TASK_MAX
    merge_rows resq TASK_MAX
    view_count resq 1
    view_total resq 1
    view_done resq 1
    view_active resq 1
    view_percent resq 1
section .text
; Parse only known, unique query fields. rdi=NULL means defaults.
parse_view:
    push rbx
    push r12
    push r13
    mov qword [view_filter],0
    mov qword [view_sort],0
    mov qword [view_action],0
    mov qword [view_id],0
    mov qword [view_target],0
    mov qword [view_flags],0
    mov byte [view_query],0
    mov rbx,rdi
    test rbx,rbx
    jz .ok
.field:
    cmp byte [rbx],0
    je .ok
    mov r12,rbx
.end_scan:
    cmp byte [r12],0
    je .end
    cmp byte [r12],'&'
    je .end
    inc r12
    jmp .end_scan
.end:
    mov r13,r12
    cmp byte [r12],0
    je .split
    inc r13
    cmp byte [r13],0
    je .bad
    mov byte [r12],0
.split:
    mov rdi,rbx
.eq_scan:
    cmp byte [rdi],0
    je .bad
    cmp byte [rdi],'='
    je .decode
    inc rdi
    jmp .eq_scan
.decode:
    mov byte [rdi],0
    inc rdi
    call decode_value
    test rax,rax
    js .done
    cmp qword [decode_stripped],0
    jne .bad
    mov rdi,rbx
    mov rsi,key_filter
    call strcmp
    test rax,rax
    jz .filter
    mov rdi,rbx
    mov rsi,key_sort
    call strcmp
    test rax,rax
    jz .sort
    mov rdi,rbx
    mov rsi,key_query
    call strcmp
    test rax,rax
    jz .query
    mov rdi,rbx
    mov rsi,key_edit
    call strcmp
    test rax,rax
    jz .edit
    mov rdi,rbx
    mov rsi,key_delete
    call strcmp
    test rax,rax
    jz .delete
    mov rdi,rbx
    mov rsi,key_confirm
    call strcmp
    test rax,rax
    jnz .bad
    test qword [view_flags],8
    jnz .bad
    or qword [view_flags],8
    mov rdi,decode_buf
    mov rsi,confirm_clear
    call strcmp
    test rax,rax
    jz .clear
    mov rdi,decode_buf
    mov rsi,confirm_forget
    call strcmp
    test rax,rax
    jnz .bad
    mov qword [view_action],4
    jmp .next
.clear:
    mov qword [view_action],3
    jmp .next
.edit:
    mov qword [view_action],1
    jmp .id
.delete:
    mov qword [view_action],2
.id:
    test qword [view_flags],8
    jnz .bad
    or qword [view_flags],8
    mov rdi,decode_buf
    call parse_uint
    test rax,rax
    jle .bad
    mov [view_id],rax
    jmp .next
.filter:
    test qword [view_flags],1
    jnz .bad
    or qword [view_flags],1
    mov rdi,decode_buf
    mov rsi,filter_all
    call strcmp
    test rax,rax
    jz .next
    mov rdi,decode_buf
    mov rsi,filter_active
    call strcmp
    test rax,rax
    jz .active_filter
    mov rdi,decode_buf
    mov rsi,filter_done
    call strcmp
    test rax,rax
    jnz .bad
    mov qword [view_filter],2
    jmp .next
.active_filter:
    mov qword [view_filter],1
    jmp .next
.sort:
    test qword [view_flags],2
    jnz .bad
    or qword [view_flags],2
    mov rdi,decode_buf
    mov rsi,sort_newest
    call strcmp
    test rax,rax
    jz .next
    mov rdi,decode_buf
    mov rsi,sort_oldest
    call strcmp
    test rax,rax
    jz .oldest
    mov rdi,decode_buf
    mov rsi,sort_az
    call strcmp
    test rax,rax
    jz .az
    mov rdi,decode_buf
    mov rsi,sort_active
    call strcmp
    test rax,rax
    jnz .bad
    mov qword [view_sort],3
    jmp .next
.oldest:
    mov qword [view_sort],1
    jmp .next
.az:
    mov qword [view_sort],2
    jmp .next
.query:
    test qword [view_flags],4
    jnz .bad
    or qword [view_flags],4
    mov rdi,decode_buf
    call strlen
    cmp rax,TITLE_MAX
    ja .bad
    lea rcx,[rax+1]
    mov rsi,decode_buf
    mov rdi,view_query
    rep movsb
.next:
    mov rbx,r13
    jmp .field
.ok:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Validated UTF-8 -> codepoint with ASCII, Latin-1 and Romanian simple folding.
; rdi advances. Only rax,rcx,rdx are clobbered.
fold_next:
    movzx eax,byte [rdi]
    test eax,eax
    jz .return
    inc rdi
    cmp eax,128
    jb .fold
    cmp eax,0xe0
    jb .two
    cmp eax,0xf0
    jb .three
    and eax,7
    mov ecx,3
    jmp .decode
.three:
    and eax,15
    mov ecx,2
    jmp .decode
.two:
    and eax,31
    mov ecx,1
.decode:
    shl eax,6
    movzx edx,byte [rdi]
    and edx,63
    or eax,edx
    inc rdi
    dec ecx
    jnz .decode
.fold:
    cmp eax,'A'
    jb .return
    cmp eax,'Z'
    jbe .plus32
    cmp eax,0xc0
    jb .romanian
    cmp eax,0xd6
    jbe .plus32
    cmp eax,0xd8
    jb .romanian
    cmp eax,0xde
    jbe .plus32
.romanian:
    cmp eax,0x102
    je .plus1
    cmp eax,0x218
    je .plus1
    cmp eax,0x21a
    je .plus1
    cmp eax,0x178
    jne .return
    mov eax,0xff
    ret
.plus1:
    inc eax
    ret
.plus32:
    add eax,32
.return:
    ret

; Lexicographic simple-folded Unicode comparison; deterministic across browsers.
unicode_compare:
    mov r8,rdi
    mov r9,rsi
.loop:
    mov rdi,r8
    call fold_next
    mov r8,rdi
    mov r11d,eax
    mov rdi,r9
    call fold_next
    mov r9,rdi
    sub r11d,eax
    jnz .different
    test eax,eax
    jnz .loop
    xor eax,eax
    ret
.different:
    movsxd rax,r11d
    ret

contains:
    push rbx
    push r12
    push r13
    push r14
    mov rbx,rdi
    mov r12,rsi
.candidate:
    mov r13,rbx
    mov r14,r12
.match:
    mov rdi,r14
    call fold_next
    mov r14,rdi
    test eax,eax
    jz .yes
    mov r10d,eax
    mov rdi,r13
    call fold_next
    mov r13,rdi
    cmp eax,r10d
    jne .advance
    test eax,eax
    jnz .match
.advance:
    mov rdi,rbx
    call fold_next
    mov rbx,rdi
    test eax,eax
    jnz .candidate
    xor eax,eax
    jmp .done
.yes:
    mov eax,1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

compare_rows:
    cmp qword [view_sort],1
    je .oldest
    cmp qword [view_sort],2
    je .title
    cmp qword [view_sort],3
    jne .newest
    movzx eax,byte [rdi+8]
    movzx edx,byte [rsi+8]
    sub eax,edx
    jnz .status
.newest:
    mov rax,[rsi]
    sub rax,[rdi]
    ret
.status:
    cdqe
    ret
.oldest:
    mov rax,[rdi]
    sub rax,[rsi]
    ret
.title:
    push rdi
    push rsi
    add rdi,17
    add rsi,17
    call unicode_compare
    pop rsi
    pop rdi
    test rax,rax
    jz .newest
    ret

; Count and filter once, then stable bottom-up merge sort, O(n log n).
build_view:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,16
    mov qword [view_total],0
    mov qword [view_done],0
    mov qword [view_count],0
    cmp qword [view_action],1
    je .find_target
    cmp qword [view_action],2
    jne .scan_start
.find_target:
    mov rdi,[view_id]
    call find_todo
    test rax,rax
    jz .missing
    mov [view_target],rax
.scan_start:
    call get_todo_list
    mov rbx,rax
    mov r12d,SLOT_MAX
.scan:
    cmp qword [rbx],0
    je .next
    cmp byte [rbx+8],2
    je .next
    inc qword [view_total]
    cmp byte [rbx+8],1
    jne .filter
    inc qword [view_done]
.filter:
    cmp qword [view_filter],0
    je .query
    mov rax,[view_filter]
    dec rax
    cmp [rbx+8],al
    jne .next
.query:
    lea rdi,[rbx+17]
    mov rsi,view_query
    call contains
    test eax,eax
    jz .next
    mov rax,[view_count]
    mov [view_rows+rax*8],rbx
    inc qword [view_count]
.next:
    add rbx,TASK_SIZE
    dec r12
    jnz .scan
    mov rax,[view_total]
    sub rax,[view_done]
    mov [view_active],rax
    xor eax,eax
    cmp qword [view_total],0
    je .percent
    mov rax,[view_total]
    shr rax,1
    imul rdx,[view_done],100
    add rax,rdx
    xor edx,edx
    div qword [view_total]
.percent:
    mov [view_percent],rax
    mov r12d,1 ; merge run width
.width:
    cmp r12,[view_count]
    jae .ok
    xor r13d,r13d
    mov qword [rsp+8],0 ; output cursor
.run:
    cmp r13,[view_count]
    jae .copy_back
    mov r14,r13 ; left cursor
    lea r15,[r13+r12] ; left end/right start
    cmp r15,[view_count]
    cmova r15,[view_count]
    mov rbx,r15 ; right cursor
    lea rax,[r15+r12]
    cmp rax,[view_count]
    cmova rax,[view_count]
    mov [rsp],rax ; right end
.merge:
    cmp r14,r15
    jae .right_only
    cmp rbx,[rsp]
    jae .left
    mov rdi,[view_rows+r14*8]
    mov rsi,[view_rows+rbx*8]
    call compare_rows
    test rax,rax
    jle .left
.right:
    mov rax,[view_rows+rbx*8]
    inc rbx
    jmp .store
.right_only:
    cmp rbx,[rsp]
    jb .right
    mov r13,[rsp]
    jmp .run
.left:
    mov rax,[view_rows+r14*8]
    inc r14
.store:
    mov rdx,[rsp+8]
    mov [merge_rows+rdx*8],rax
    inc qword [rsp+8]
    jmp .merge
.copy_back:
    mov rsi,merge_rows
    mov rdi,view_rows
    mov rcx,[view_count]
    rep movsq
    shl r12,1
    jmp .width
.ok:
    xor eax,eax
    jmp .done
.missing:
    mov rax,-404
.done:
    add rsp,16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
