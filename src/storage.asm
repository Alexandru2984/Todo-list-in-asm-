%include "src/defs.inc"
DEFAULT ABS
extern current_uid, parse_uint, itoa, strlen, write_all, valid_utf8
extern parse_metadata, format_metadata, validate_metadata_graph
extern apply_properties, property_task, property_flags
extern next_occurrence
extern history_reset, history_parse, history_validate, history_write, undo_todos, undo_mode
extern history_prepare, history_complete
extern task_ready
extern guard_storage_reset, guard_hash_state, guard_parse, guard_validate, guard_check
extern guard_presave, guard_write

global check_regular
global next_id
global todos, todo_count, lookup_array, save_snapshot, format_line, line_buf
global find_todo, duplicate_todo
global find_any_todo, split_field, storage_version, save_legacy_snapshot, save_v3_snapshot
global init_storage, load_todos, append_todo, complete_todo, delete_todo
 global edit_todo, get_todo_list, get_todo_count, clear_done_todos
 global lock_user_file, unlock_user_file, reopen_todo
section .data
    data_dir db 'data',0
    prefix db 'data/todos-',0
    seq_prefix db '#next=',0
    v4_header db '#asm=4',10
    v2_header db '#asm=3',10
    v2_header_len equ $-v2_header
    lookup_array dq todos
    next_id dq 1
    lock_fd dq -1
section .bss
    todos resb SLOT_MAX*TASK_SIZE
    file_buf resb STORAGE_MAX+9
    todo_count resq 1
    todo_path resb 128
    tmp_path resb 136
    lock_path resb 136
    line_buf resb 1024
    storage_version resq 1
    sequence_seen resq 1
    write_legacy resq 1
    stat_buffer resb 144
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
    mov ecx,SLOT_MAX*TASK_SIZE
    xor eax,eax
    rep stosb
    mov qword [todo_count],0
    mov qword [next_id],1
    mov qword [storage_version],1
    mov qword [sequence_seen],0
    mov qword [write_legacy],0
    mov qword [lookup_array],todos
    call history_reset
    call guard_storage_reset
    mov rdi,file_buf
    xor esi,esi
    call guard_hash_state
    call build_path
    mov eax,SYS_OPEN
    mov rdi,todo_path
    mov esi,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK
    xor edx,edx
    syscall
    cmp rax,-2
    je .ok
    test rax,rax
    js .bad
    mov rbx,rax
    mov rdi,rbx
    call check_regular
    test rax,rax
    js .close_bad
    xor r12d,r12d
.read:
    mov eax,SYS_READ
    mov rdi,rbx
    lea rsi,[file_buf+r12]
    mov edx,STORAGE_MAX+1
    sub rdx,r12
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js .close_bad
    jz .read_done
    add r12,rax
    cmp r12,STORAGE_MAX
    ja .close_bad
    jmp .read
.read_done:
    mov eax,SYS_CLOSE
    mov rdi,rbx
    syscall
    mov byte [file_buf+r12],0
    mov rdi,file_buf
    mov rsi,r12
    call guard_hash_state
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
    cmp dword [r14],'#asm'
    jne .sequence
    test r13,r13
    jnz .bad
    cmp dword [r14+3],'m=2'
    je .v2
    cmp dword [r14+3],'m=4'
    jne .check_v3
    mov qword [storage_version],4
    jmp .next
.check_v3:
    cmp dword [r14+3],'m=3'
    jne .bad
    mov qword [storage_version],3
    jmp .next
.v2:
    mov qword [storage_version],2
    jmp .next
.sequence:
    cmp qword [storage_version],4
    jne .history
    mov rdi,r14
    call guard_parse
    test rax,rax
    js .bad
    jnz .next
.history:
    cmp qword [storage_version],3
    jb .metadata
    cmp word [r14],'U|'
    je .previous_base
    cmp word [r14],'V|'
    je .previous_metadata
    mov rdi,r14
    call history_parse
    test rax,rax
    js .bad
    jnz .next
    jmp .metadata
.previous_base:
    cmp qword [undo_mode],0
    je .bad
    mov qword [lookup_array],undo_todos
    add r14,2
    jmp .fields
.previous_metadata:
    cmp qword [undo_mode],0
    je .bad
    mov qword [lookup_array],undo_todos
    jmp .parse_metadata
.metadata:
    cmp word [r14],'A|'
    jne .sequence_number
    cmp qword [storage_version],2
    jb .bad
.parse_metadata:
    lea rdi,[r14+2]
    call parse_metadata
    test rax,rax
    js .bad
    jmp .next
.sequence_number:
    cmp dword [r14],'#nex'
    jne .fields
    cmp word [r14+4],'t='
    jne .bad
    cmp qword [storage_version],2
    jb .read_sequence
    cmp qword [sequence_seen],0
    jne .bad
    cmp r13,7 ; V2 sequence header follows the version header
    jne .bad
.read_sequence:
    mov qword [sequence_seen],1
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
    mov rdi,rbx
    call valid_utf8
    test rax,rax
    js .bad
    mov rax,r8
    inc rax
    cmp rax,[next_id]
    jbe .slot
    mov [next_id],rax
.slot:
    mov rdi,[lookup_array]
    mov ecx,SLOT_MAX
.find_slot:
    cmp [rdi],r8
    je .existing
    cmp qword [rdi],0
    je .update
    add rdi,TASK_SIZE
    dec ecx
    jnz .find_slot
    jmp .bad ; legacy overflow must be recovered explicitly, never discarded
.existing:
    cmp qword [storage_version],2
    jae .bad ; Versioned snapshots cannot contain replay/duplicate records
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
    mov qword [lookup_array],todos
    mov r13,r15
    sub r13,file_buf
    jmp .record
.count:
    cmp qword [storage_version],2
    jb .legacy_count
    cmp qword [sequence_seen],1
    jne .bad
    mov rdi,todos
    call validate_metadata_graph
    test rax,rax
    js .bad
.legacy_count:
    cmp qword [storage_version],3
    jb .count_current
    call history_validate
    test rax,rax
    js .bad
.count_current:
    mov rdi,todos
    mov ecx,SLOT_MAX
    xor r8d,r8d
.count_loop:
    cmp qword [rdi],0
    je .count_next
    cmp byte [rdi+8],2
    jne .live_count
    cmp qword [storage_version],2
    jb .drop_legacy
    inc r8
    jmp .count_next
.drop_legacy:
    ; Legacy tombstones do not carry recoverable trash metadata.
    mov qword [rdi],0
    jmp .count_next
.live_count:
    mov byte [rdi+T_META],1
    inc qword [todo_count]
.count_next:
    add rdi,TASK_SIZE
    dec ecx
    jnz .count_loop
    cmp qword [todo_count],TASK_MAX
    ja .bad
    cmp r8,200
    ja .bad
.ok:
    call guard_validate
    test rax,rax
    js .bad
    call guard_check
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
    cmp qword [write_legacy],0
    jne .prepared
    call guard_presave
    test rax,rax
    js .bad
.prepared:
    call build_path
    mov rsi,todo_path
    mov rdi,tmp_path
    mov ecx,47
    rep movsb
    mov dword [rdi],'.tmp'
    mov byte [rdi+4],0
    mov eax,SYS_OPEN
    mov rdi,tmp_path
    mov esi,O_WRONLY|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK
    mov edx,0600o
    syscall
    test rax,rax
    js .bad
    mov r12,rax
    mov rdi,r12
    call check_regular
    test rax,rax
    js .close_bad
    mov eax,SYS_FTRUNCATE
    mov rdi,r12
    xor esi,esi
    syscall
    test rax,rax
    js .close_bad
    cmp qword [write_legacy],0
    jne .sequence
    mov rdi,r12
    mov rsi,v2_header
    cmp qword [storage_version],4
    jne .header_ready
    mov rsi,v4_header
.header_ready:
    mov edx,v2_header_len
    call write_all
    test rax,rax
    js .close_bad
.sequence:
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
    cmp qword [write_legacy],0
    jne .records
    cmp qword [storage_version],4
    jne .records
    mov rdi,r12
    call guard_write
    test rax,rax
    js .close_bad
.records:
    mov rbx,todos
    mov r13d,SLOT_MAX
.loop:
    cmp qword [rbx],0
    je .next
    cmp byte [rbx+8],2
    jne .write
    cmp qword [write_legacy],0
    jne .next
.write:
    mov rdi,rbx
    call format_line
    mov rdx,rax
    mov rsi,line_buf
    mov rdi,r12
    call write_all
    test rax,rax
    js .close_bad
    cmp qword [write_legacy],0
    jne .next
    mov rdi,rbx
    mov rsi,line_buf
    call format_metadata
    mov rdx,rax
    mov rdi,r12
    mov rsi,line_buf
    call write_all
    test rax,rax
    js .close_bad
.next:
    add rbx,TASK_SIZE
    dec r13
    jnz .loop
    cmp qword [write_legacy],0
    jne .sync
    mov rdi,r12
    call history_write
    test rax,rax
    js .close_bad
.sync:
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

; fstat the opened inode before reading or truncating it. A concurrently
; replaced snapshot can have nlink=0; linked aliases and special files fail.
check_regular:
    mov eax,SYS_FSTAT
    mov rsi,stat_buffer
    syscall
    test rax,rax
    js .done
    mov eax,[stat_buffer+24]
    and eax,0170000o
    cmp eax,0100000o
    jne .bad
    cmp qword [stat_buffer+16],1
    ja .bad
    xor eax,eax
    ret
.bad:
    mov rax,-1
.done:
    ret

; Maintenance-only: caller has stopped the HTTP service and holds the file lock.
save_v3_snapshot:
    mov qword [storage_version],3
    jmp save_snapshot

save_legacy_snapshot:
    mov qword [write_legacy],1
    call save_snapshot
    mov qword [write_legacy],0
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
    mov ecx,SLOT_MAX
.find:
    cmp qword [r8],0
    je .found
    add r8,TASK_SIZE
    dec ecx
    jnz .find
    jmp .full
.found:
    mov edi,1
    mov rsi,[next_id]
    call history_prepare
    push r8
    mov rdi,r8
    xor eax,eax
    mov ecx,TASK_SIZE/8
    rep stosq
    pop r8
    mov rax,[next_id]
    mov [r8],rax
    inc qword [next_id]
    mov byte [r8+8],0
    mov byte [r8+T_META],1
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
    mov rdi,r8
    call apply_properties
    test rax,rax
    js .property_error
    call save_snapshot
.property_error:
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
    call find_any_todo
    test rax,rax
    jz .missing
    cmp byte [rax+8],2
    je .missing
    ret
.missing:
    xor eax,eax
    ret

; ID zero exposes the array base to the bounded native graph walker.
find_any_todo:
    mov rax,[lookup_array]
    test rdi,rdi
    jz .found
    mov ecx,SLOT_MAX
.loop:
    cmp [rax],rdi
    je .found
    add rax,TASK_SIZE
    dec ecx
    jnz .loop
.missing:
    xor eax,eax
    ret
.found:
    ret

complete_todo:
    push rbx
    push r12
    push r13
    call find_todo
    test rax,rax
    jz .missing
    mov rbx,rax
    cmp byte [rbx+8],1
    je .already_done
    mov rdi,rbx
    call task_ready
    test rax,rax
    jz .full
    xor r13d,r13d ; next occurrence slot, if any
    cmp qword [rbx+T_REPEAT],0
    je .complete
    cmp qword [todo_count],TASK_MAX
    jae .full
    mov rax,9223372036854775807
    cmp [next_id],rax
    jae .full
    mov rdi,rbx
    call next_occurrence
    test rax,rax
    js .done
    mov r12,rax
    mov edi,3
    mov rsi,[rbx]
    call history_prepare
    mov r13,todos
    mov ecx,SLOT_MAX
.find_next:
    cmp qword [r13],0
    je .next_found
    add r13,TASK_SIZE
    dec ecx
    jnz .find_next
    jmp .full
.next_found:
    mov rsi,rbx
    mov rdi,r13
    mov ecx,TASK_SIZE/8
    rep movsq
    mov rax,[next_id]
    mov [r13],rax
    inc qword [next_id]
    mov byte [r13+8],0
    mov [r13+T_DUE],r12
    mov qword [r13+T_COMPLETED],0
    mov qword [r13+T_PARENT],0
    mov qword [r13+T_DELETED],0
    mov qword [r13+T_PREVIOUS],0
    mov qword [r13+T_STAGE],0
.complete:
    test r13,r13
    jnz .mark_complete
    mov edi,3
    mov rsi,[rbx]
    call history_prepare
.mark_complete:
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    mov [rbx+T_COMPLETED],rax
    mov byte [rbx+8],1
    test r13,r13
    jz .save
    mov [r13+9],rax
.save:
    call history_complete
    call save_snapshot
    jmp .done
.missing:
    mov rax,-404
    jmp .done
.full:
    mov rax,-409
    jmp .done
.already_done:
    xor eax,eax
.done:
    pop r13
    pop r12
    pop rbx
    ret
reopen_todo:
    call find_todo
    test rax,rax
    jz missing_todo
    cmp byte [rax+8],0
    je .unchanged
    mov r8,rax
    mov rdi,[rax+T_PARENT]
    test rdi,rdi
    jz .reopen
    call find_any_todo
    test rax,rax
    jz .conflict
    cmp byte [rax+8],0
    jne .conflict
.reopen:
    mov edi,4
    mov rsi,[r8]
    call history_prepare
    mov rax,r8
    mov byte [rax+8],0
    mov qword [rax+T_COMPLETED],0
    jmp save_snapshot
.conflict:
    mov rax,-409
    ret
.unchanged:
    xor eax,eax
    ret
delete_todo:
    call find_todo
    test rax,rax
    jz missing_todo
    mov r8,rax
    mov edi,5
    mov rsi,[r8]
    call history_prepare
    mov rdi,r8
    call trash_slot
    jmp commit_trash
edit_todo:
    push rsi
    call find_todo
    pop rsi
    test rax,rax
    jz missing_todo
    push rax
    push rsi
    mov edi,2
    mov rsi,[rax]
    call history_prepare
    pop rsi
    pop rax
    push rax
    lea rdi,[rax+17]
.copy:
    lodsb
    stosb
    test al,al
    jnz .copy
    pop rdi
    call apply_properties
    test rax,rax
    js .property_error
    jmp save_snapshot
.property_error:
    ret
missing_todo:
    mov rax,-404
    ret
clear_done_todos:
    mov rdi,todos
    mov ecx,SLOT_MAX
.check:
    cmp byte [rdi+8],1
    je .prepare
    add rdi,TASK_SIZE
    loop .check
    xor eax,eax
    ret
.prepare:
    mov edi,6
    xor esi,esi
    call history_prepare
    push rbx
    push r12
    mov rbx,todos
    mov r12d,SLOT_MAX
.loop:
    cmp qword [rbx],0
    je .next
    cmp byte [rbx+8],1
    jne .next
    mov rdi,rbx
    call trash_slot
.next:
    add rbx,TASK_SIZE
    dec r12
    jnz .loop
    pop r12
    pop rbx
    jmp commit_trash

trash_slot:
    movzx eax,byte [rdi+8]
    mov [rdi+T_PREVIOUS],rax
    mov byte [rdi+8],2
    push rdi
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    pop rdi
    mov [rdi+T_DELETED],rax
    ret

; Retain the latest 200 trash entries. A removed task cannot leave dangling
; references. Parent deletion includes descendants, without recursive mutation.
commit_trash:
    push rbx
    push r12
    push r13
.descendants:
    xor r13d,r13d
    mov rbx,todos
    mov r12d,SLOT_MAX
.scan_child:
    cmp qword [rbx],0
    je .next_child
    cmp byte [rbx+8],2
    je .next_child
    mov rdi,[rbx+T_PARENT]
    test rdi,rdi
    jz .next_child
    call find_any_todo
    test rax,rax
    jz .next_child
    cmp byte [rax+8],2
    jne .next_child
    mov rdi,rbx
    call trash_slot
    inc r13
.next_child:
    add rbx,TASK_SIZE
    dec r12
    jnz .scan_child
    test r13,r13
    jnz .descendants
.prune:
    xor r8d,r8d
    xor r9d,r9d ; oldest slot
    mov rbx,todos
    mov ecx,SLOT_MAX
.oldest:
    cmp qword [rbx],0
    je .next_oldest
    cmp byte [rbx+8],2
    jne .next_oldest
    inc r8
    test r9,r9
    jz .choose
    mov rax,[r9+T_DELETED]
    cmp [rbx+T_DELETED],rax
    jae .next_oldest
.choose:
    mov r9,rbx
.next_oldest:
    add rbx,TASK_SIZE
    dec ecx
    jnz .oldest
    cmp r8,200
    jbe .save
    mov r10,[r9]
    mov qword [r9],0
    mov rbx,todos
    mov ecx,SLOT_MAX
.detach:
    cmp [rbx+T_PARENT],r10
    jne .deps
    mov qword [rbx+T_PARENT],0
.deps:
    xor r8d,r8d
    xor r9d,r9d
.dep:
    cmp r8,[rbx+T_DEP_COUNT]
    jae .dep_end
    mov rax,[rbx+T_DEPS+r8*8]
    inc r8
    cmp rax,r10
    je .dep
    mov [rbx+T_DEPS+r9*8],rax
    inc r9
    jmp .dep
.dep_end:
    mov [rbx+T_DEP_COUNT],r9
    add rbx,TASK_SIZE
    dec ecx
    jnz .detach
    jmp .prune
.save:
    call save_snapshot
    pop r13
    pop r12
    pop rbx
    ret
get_todo_list:
    mov rax,todos
    ret
get_todo_count:
    mov rax,[todo_count]
    ret

; Duplicate a live task as a fresh active item; append_todo owns capacity/commit.
duplicate_todo:
    call find_todo
    test rax,rax
    jz missing_todo
    mov rdx,[rax+T_PRIORITY]
    mov [property_task+T_PRIORITY],rdx
    mov rdx,[rax+T_DUE]
    mov [property_task+T_DUE],rdx
    lea rdi,[property_task+T_PROJECT]
    lea rsi,[rax+T_PROJECT]
    mov ecx,PROJECT_MAX+1
    rep movsb
    lea rdi,[property_task+T_TAGS]
    lea rsi,[rax+T_TAGS]
    mov ecx,TAGS_MAX+1
    rep movsb
    mov rdx,[rax+T_PARENT]
    mov [property_task+T_PARENT],rdx
    lea rdi,[property_task+T_DEPS]
    lea rsi,[rax+T_DEPS]
    mov ecx,DEP_MAX+1 ; includes adjacent dependency count
    rep movsq
    mov qword [property_flags],123
    lea rdi,[rax+17]
    jmp append_todo
