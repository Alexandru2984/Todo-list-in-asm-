%include "src/defs.inc"
DEFAULT ABS
extern current_uid, parse_uint, itoa, strlen, write_all

global init_storage, load_todos, append_todo, complete_todo, delete_todo
 global edit_todo, get_todo_list, get_todo_count, clear_done_todos
 global lock_user_file, unlock_user_file, reopen_todo
section .data
    data_dir db 'data',0
    prefix db 'data/todos-',0
    seq_prefix db '#next=',0
    next_id dq 1
    lock_fd dq -1
section .bss
    todos resb TASK_MAX*128
    file_buf resb 262145+8
    todo_count resq 1
    todo_path resb 128
    tmp_path resb 136
    lock_path resb 136
    line_buf resb 256
section .text
init_storage:
    mov eax,SYS_MKDIR
    mov rdi,data_dir
    mov esi,0700o
    syscall
    test rax,rax
    jns .ok
    cmp rax,-17 ; EEXIST
    jne .bad
.ok:
    mov eax,SYS_OPEN
    mov rdi,data_dir
    mov esi,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js .bad
    mov rdi,rax
    mov eax,SYS_CLOSE
    syscall
    ret
.bad:
    mov rax,-500
    ret

; Fixed-size validated UID from router; every path stays inside private data/.
build_path:
    mov rdi,todo_path
    mov rsi,prefix
    mov ecx,11
    rep movsb
    mov rsi,current_uid
    mov ecx,32
    rep movsb
    mov dword [rdi],'.txt'
    mov byte [rdi+4],0
    ret

lock_user_file:
    call build_path
    mov qword [lock_fd],-1
    mov rsi,todo_path
    mov rdi,lock_path
    mov ecx,47
    rep movsb
    mov dword [rdi],'.loc'
    mov word [rdi+4],'k'
    mov eax,SYS_OPEN
    mov rdi,lock_path
    mov esi,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC
    mov edx,0600o
    syscall
    test rax,rax
    js .bad
    mov [lock_fd],rax
.retry:
    mov rdi,[lock_fd]
    mov eax,SYS_FLOCK
    mov esi,LOCK_EX
    syscall
    cmp rax,-4
    je .retry
    test rax,rax
    js .close_bad
    xor eax,eax
    ret
.close_bad:
    call unlock_user_file
.bad:
    mov rax,-503
    ret

unlock_user_file:
    mov rdi,[lock_fd]
    cmp rdi,0
    jl .ok
    mov qword [lock_fd],-1
    mov eax,SYS_CLOSE
    syscall
.ok:
    xor eax,eax
    ret

; Find delimiter in a bounded, NUL-terminated line. Null terminates field.
; rdi=start, dl=delimiter; rax=next field or zero.
split_field:
    mov rax,rdi
.loop:
    cmp byte [rax],0
    je .bad
    cmp byte [rax],dl
    je .found
    inc rax
    jmp .loop
.found:
    mov byte [rax],0
    inc rax
    ret
.bad:
    xor eax,eax
    ret

; Read/replay legacy records, then compact on every successful mutation.
; Invalid or oversized files are errors, never silently overwritten.
load_todos:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi,todos
    mov ecx,TASK_MAX*128
    xor eax,eax
    rep stosb
    mov qword [todo_count],0
    mov qword [next_id],1
    call build_path
    mov eax,SYS_OPEN
    mov rdi,todo_path
    mov esi,O_RDONLY|O_NOFOLLOW|O_CLOEXEC
    xor edx,edx
    syscall
    cmp rax,-2
    je .ok
    test rax,rax
    js .bad
    mov rbx,rax
    xor r12d,r12d
.read:
    mov eax,SYS_READ
    mov rdi,rbx
    lea rsi,[file_buf+r12]
    mov edx,262145
    sub rdx,r12
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js .close_bad
    jz .read_done
    add r12,rax
    cmp r12,262144
    ja .close_bad
    jmp .read
.read_done:
    mov eax,SYS_CLOSE
    mov rdi,rbx
    syscall
    mov byte [file_buf+r12],0
    xor r13d,r13d
.record:
    cmp r13,r12
    jae .count
    lea r14,[file_buf+r13]
    mov r15,r14
.find_nl:
    mov rax,r15
    sub rax,file_buf
    cmp rax,r12
    jae .bad ; a torn final record is not safe to overwrite
    cmp byte [r15],0
    je .bad
    cmp byte [r15],10
    je .line
    inc r15
    jmp .find_nl
.line:
    mov byte [r15],0
    inc r15
    cmp dword [r14],'#nex'
    jne .fields
    cmp word [r14+4],'t='
    jne .bad
    lea rdi,[r14+6]
    call parse_uint
    test rax,rax
    jle .bad
    cmp rax,[next_id]
    jbe .next
    mov [next_id],rax
    jmp .next
.fields:
    mov rdi,r14
    mov dl,'|'
    call split_field
    test rax,rax
    jz .bad
    mov rbx,rax
    mov rdi,r14
    call parse_uint
    test rax,rax
    jle .bad
    mov rdx,9223372036854775807
    cmp rax,rdx
    je .bad ; no representable next ID; refuse to commit corrupt metadata
    mov r8,rax
    mov rdi,rbx
    mov dl,'|'
    call split_field
    test rax,rax
    jz .bad
    mov r14,rax
    mov rdi,rbx
    call parse_uint
    cmp rax,2
    ja .bad
    mov r9,rax
    mov rdi,r14
    mov dl,'|'
    call split_field
    test rax,rax
    jz .bad
    mov rbx,rax
    mov rdi,r14
    call parse_uint
    test rax,rax
    js .bad
    mov r10,rax
    ; Reject format/control injection in stored records and overlong titles.
    xor ecx,ecx
.validate_title:
    mov al,[rbx+rcx]
    test al,al
    jz .valid_title
    cmp al,32
    jb .bad
    cmp al,127
    je .bad
    cmp al,'|'
    je .bad
    inc ecx
    cmp ecx,TITLE_MAX
    ja .bad
    jmp .validate_title
.valid_title:
    mov rax,r8
    inc rax
    cmp rax,[next_id]
    jbe .slot
    mov [next_id],rax
.slot:
    mov rdi,todos
    mov ecx,TASK_MAX
.find_slot:
    cmp [rdi],r8
    je .update
    cmp qword [rdi],0
    je .update
    add rdi,128
    dec ecx
    jnz .find_slot
    jmp .bad ; legacy overflow must be recovered explicitly, never discarded
.update:
    mov [rdi],r8
    mov [rdi+8],r9b
    mov [rdi+9],r10
    add rdi,17
    mov rsi,rbx
.copy:
    lodsb
    stosb
    test al,al
    jnz .copy
.next:
    mov r13,r15
    sub r13,file_buf
    jmp .record
.count:
    mov rdi,todos
    mov ecx,TASK_MAX
.count_loop:
    cmp qword [rdi],0
    je .count_next
    cmp byte [rdi+8],2
    je .count_next
    inc qword [todo_count]
.count_next:
    add rdi,128
    dec ecx
    jnz .count_loop
.ok:
    xor eax,eax
    jmp .done
.close_bad:
    mov eax,SYS_CLOSE
    mov rdi,rbx
    syscall
.bad:
    mov rax,-500
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Format one in-memory slot (rdi) into line_buf. rax=length.
format_line:
    push rbx
    mov rbx,rdi
    mov rdi,[rbx]
    mov rsi,line_buf
    call itoa
    lea rsi,[line_buf+rax]
    mov byte [rsi],'|'
    inc rsi
    movzx edi,byte [rbx+8]
    call itoa
    add rsi,rax
    mov byte [rsi],'|'
    inc rsi
    mov rdi,[rbx+9]
    call itoa
    add rsi,rax
    mov byte [rsi],'|'
    lea rdi,[rsi+1]
    lea rsi,[rbx+17]
.copy:
    lodsb
    test al,al
    jz .end
    stosb
    jmp .copy
.end:
    mov byte [rdi],10
    lea rax,[rdi+1]
    sub rax,line_buf
    pop rbx
    ret

; Commit a bounded full snapshot. Never replace valid data after write/fsync error.
; Directory fsync makes the rename durable. 507 indicates failure, not success.
save_snapshot:
    push rbx
    push r12
    push r13
    call build_path
    mov rsi,todo_path
    mov rdi,tmp_path
    mov ecx,47
    rep movsb
    mov dword [rdi],'.tmp'
    mov byte [rdi+4],0
    mov eax,SYS_OPEN
    mov rdi,tmp_path
    mov esi,O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW|O_CLOEXEC
    mov edx,0600o
    syscall
    test rax,rax
    js .bad
    mov r12,rax
    mov rdi,line_buf
    mov rsi,seq_prefix
    mov ecx,6
    rep movsb
    mov rsi,rdi
    mov rdi,[next_id]
    call itoa
    add rsi,rax
    mov byte [rsi],10
    lea rdx,[rsi+1]
    sub rdx,line_buf
    mov rsi,line_buf
    mov rdi,r12
    call write_all
    test rax,rax
    js .close_bad
    mov rbx,todos
    mov r13d,TASK_MAX
.loop:
    cmp qword [rbx],0
    je .next
    cmp byte [rbx+8],2
    je .next
    mov rdi,rbx
    call format_line
    mov rdx,rax
    mov rsi,line_buf
    mov rdi,r12
    call write_all
    test rax,rax
    js .close_bad
.next:
    add rbx,128
    dec r13
    jnz .loop
    mov eax,SYS_FSYNC
    mov rdi,r12
    syscall
    test rax,rax
    js .close_bad
    mov eax,SYS_CLOSE
    mov rdi,r12
    syscall
    test rax,rax
    js .bad
    mov eax,SYS_RENAME
    mov rdi,tmp_path
    mov rsi,todo_path
    syscall
    test rax,rax
    js .bad
    mov eax,SYS_OPEN
    mov rdi,data_dir
    mov esi,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC
    xor edx,edx
    syscall
    test rax,rax
    js .bad
    mov r12,rax
    mov eax,SYS_FSYNC
    mov rdi,r12
    syscall
    mov rbx,rax
    mov eax,SYS_CLOSE
    mov rdi,r12
    syscall
    test rbx,rbx
    js .bad
    xor eax,eax
    jmp .done
.close_bad:
    mov eax,SYS_CLOSE
    mov rdi,r12
    syscall
.bad:
    mov rax,-507
.done:
    pop r13
    pop r12
    pop rbx
    ret

append_todo:
    push rbx
    mov rbx,rdi
    cmp qword [todo_count],TASK_MAX
    jae .full
    mov rax,9223372036854775807
    cmp [next_id],rax
    jae .full
    mov r8,todos
    mov ecx,TASK_MAX
.find:
    cmp qword [r8],0
    je .found
    cmp byte [r8+8],2
    je .found
    add r8,128
    dec ecx
    jnz .find
    jmp .full
.found:
    mov rax,[next_id]
    mov [r8],rax
    inc qword [next_id]
    mov byte [r8+8],0
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    mov [r8+9],rax
    lea rdi,[r8+17]
    mov rsi,rbx
.copy:
    lodsb
    stosb
    test al,al
    jnz .copy
    call save_snapshot
    pop rbx
    ret
.full:
    mov rax,-409
    pop rbx
    ret

; rdi=id -> rax=slot, or zero. Preserves rsi (edit title).
find_todo:
    test rdi,rdi
    jz .missing
    mov rax,todos
    mov ecx,TASK_MAX
.loop:
    cmp [rax],rdi
    je .found
    add rax,128
    dec ecx
    jnz .loop
.missing:
    xor eax,eax
    ret
.found:
    cmp byte [rax+8],2
    je .missing
    ret

complete_todo:
    call find_todo
    test rax,rax
    jz missing_todo
    mov byte [rax+8],1
    jmp save_snapshot
reopen_todo:
    call find_todo
    test rax,rax
    jz missing_todo
    mov byte [rax+8],0
    jmp save_snapshot
delete_todo:
    call find_todo
    test rax,rax
    jz missing_todo
    mov byte [rax+8],2
    jmp save_snapshot
edit_todo:
    push rsi
    call find_todo
    pop rsi
    test rax,rax
    jz missing_todo
    lea rdi,[rax+17]
.copy:
    lodsb
    stosb
    test al,al
    jnz .copy
    jmp save_snapshot
missing_todo:
    mov rax,-404
    ret
clear_done_todos:
    mov rdi,todos
    mov ecx,TASK_MAX
.loop:
    cmp byte [rdi+8],1
    jne .next
    mov byte [rdi+8],2
.next:
    add rdi,128
    dec ecx
    jnz .loop
    jmp save_snapshot
get_todo_list:
    mov rax,todos
    ret
get_todo_count:
    mov rax,[todo_count]
    ret
