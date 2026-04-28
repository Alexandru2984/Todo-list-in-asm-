%include "src/defs.inc"

extern atoi
extern strlen
extern current_uid      ; defined in router.asm (global resb 64)

global init_storage
global load_todos
global append_todo
global complete_todo
global delete_todo
global get_todo_list
global get_todo_count
global clear_done_todos

section .data
    todos_prefix db "data/todos-", 0
    todos_suffix db ".txt", 0
    next_id dq 1

section .bss
    ; 1000 tasks, each 128 bytes
    ; [0-7] id (qword)
    ; [8] completed (0=active, 1=done, 2=deleted)
    ; [9-16] timestamp (qword, unaligned)
    ; [17-127] title (null-terminated)
    todos resb 128000
    file_buf resb 65536
    todo_count resq 1
    current_time resq 1
    todo_path resb 128

section .text

; -----------------------------------------------------------------------------
; build_path - builds "data/todos-{uid}.txt" into todo_path
; Returns rax=1 if path built, rax=0 if current_uid is empty
; Clobbers: rdi, rsi, al
; -----------------------------------------------------------------------------
build_path:
    cmp byte [current_uid], 0
    je .empty
    mov rdi, todo_path
    mov rsi, todos_prefix
.cp1:
    mov al, [rsi]
    test al, al
    jz .cp2
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .cp1
.cp2:
    mov rsi, current_uid
.cp3:
    mov al, [rsi]
    test al, al
    jz .cp4
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .cp3
.cp4:
    mov rsi, todos_suffix
.cp5:
    mov al, [rsi]
    mov [rdi], al   ; copies null terminator too
    test al, al
    jz .ok
    inc rsi
    inc rdi
    jmp .cp5
.ok:
    mov rax, 1
    ret
.empty:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; init_storage - no-op (data/ directory created by Makefile)
; -----------------------------------------------------------------------------
init_storage:
    ret

; -----------------------------------------------------------------------------
; load_todos - Read user's file and populate todos array
; Always zeroes array first; does nothing more if current_uid is empty
; -----------------------------------------------------------------------------
load_todos:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Always clear todos array first (prevents cross-user data leaks)
    mov rdi, todos
    mov rcx, 128000
    xor al, al
    rep stosb
    mov qword [todo_count], 0
    mov qword [next_id], 1

    ; Build path — bail out early if no uid
    call build_path
    test rax, rax
    jz .done

    ; Open todo_path
    mov rax, SYS_OPEN
    mov rdi, todo_path
    mov rsi, O_RDONLY
    mov rdx, 0
    syscall
    cmp rax, 0
    jl .done
    mov rbx, rax ; fd

    ; Read into file_buf
    mov rax, SYS_READ
    mov rdi, rbx
    mov rsi, file_buf
    mov rdx, 65536
    syscall
    mov r12, rax ; bytes read

    ; Close file
    mov rax, SYS_CLOSE
    mov rdi, rbx
    syscall

    test r12, r12
    jle .done

    ; Parse buffer
    mov rsi, file_buf
    mov r13, 0 ; offset in buffer

.parse_loop:
    cmp r13, r12
    jge .done

    ; We are at start of a line: id|completed|timestamp|title\n
    ; Find '|' for id
    mov rdi, rsi
    add rdi, r13
    mov r14, rdi ; ptr to id str
.find_pipe1:
    cmp byte [rdi], '|'
    je .found_pipe1
    cmp byte [rdi], 0
    je .done
    cmp byte [rdi], 10 ; newline
    je .skip_line
    inc rdi
    jmp .find_pipe1
.found_pipe1:
    mov byte [rdi], 0 ; null terminate id
    inc rdi
    mov r15, rdi ; ptr to completed str

    ; Parse id
    push rdi
    push rsi
    mov rdi, r14
    call atoi
    mov r8, rax ; id
    pop rsi
    pop rdi

    ; Find '|' for completed
.find_pipe2:
    cmp byte [rdi], '|'
    je .found_pipe2
    cmp byte [rdi], 0
    je .skip_line
    cmp byte [rdi], 10
    je .skip_line
    inc rdi
    jmp .find_pipe2
.found_pipe2:
    mov byte [rdi], 0
    inc rdi
    mov r9, rdi ; ptr to timestamp

    ; Parse completed
    push rdi
    push rsi
    mov rdi, r15
    call atoi
    mov r15, rax ; completed
    pop rsi
    pop rdi

    ; Find '|' for timestamp
.find_pipe3:
    cmp byte [rdi], '|'
    je .found_pipe3
    cmp byte [rdi], 0
    je .skip_line
    cmp byte [rdi], 10
    je .skip_line
    inc rdi
    jmp .find_pipe3
.found_pipe3:
    mov byte [rdi], 0
    inc rdi
    mov r10, rdi ; ptr to title

    ; Parse timestamp
    push rdi
    push rsi
    mov rdi, r9
    call atoi
    mov r9, rax ; timestamp
    pop rsi
    pop rdi

    ; Find '\n' for title
.find_nl:
    cmp byte [rdi], 10
    je .found_nl
    cmp byte [rdi], 0
    je .found_nl
    inc rdi
    jmp .find_nl
.found_nl:
    mov byte [rdi], 0
    mov r11, rdi ; end of line
    inc r11      ; next line start

    ; Now we have: r8=id, r15=completed, r9=timestamp, r10=title_ptr
    ; Find task in array or create new
    ; Since array is small, just scan for matching id, or empty slot
    mov rcx, 1000
    mov rbx, todos
.find_slot:
    mov rax, [rbx] ; read id
    cmp rax, r8
    je .update_slot
    test rax, rax
    jz .new_slot
    add rbx, 128
    dec rcx
    jnz .find_slot
    jmp .next_line ; array full

.new_slot:
    inc qword [todo_count]
.update_slot:
    mov [rbx], r8 ; id
    mov [rbx+8], r15b ; completed
    mov [rbx+9], r9 ; timestamp
    
    ; copy title (use r10 directly to avoid clobbering rsi = file_buf base)
    mov rdi, rbx
    add rdi, 17
.copy_title:
    mov al, [r10]
    mov [rdi], al
    test al, al
    jz .title_done
    inc r10
    inc rdi
    jmp .copy_title
.title_done:

    ; update next_id
    mov rax, r8
    inc rax
    cmp rax, [next_id]
    jle .next_line
    mov [next_id], rax

.next_line:
    mov rax, r11
    sub rax, file_buf
    mov r13, rax
    jmp .parse_loop

.skip_line:
    mov rax, rdi
    sub rax, file_buf
    inc rax
    mov r13, rax
    jmp .parse_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; append_todo - Write to file
; rdi: ptr to string to append
; -----------------------------------------------------------------------------
append_todo_file:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi    ; save string ptr before build_path clobbers rdi

    call build_path
    test rax, rax
    jz .done        ; no uid — refuse to write

    mov rax, SYS_OPEN
    mov rdi, todo_path
    mov rsi, O_WRONLY | O_APPEND | O_CREAT
    mov rdx, 0644o
    syscall
    cmp rax, 0
    jl .done
    mov r12, rax ; fd

    mov rdi, rbx
    call strlen
    mov rdx, rax ; len

    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, rbx
    syscall

    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; We need a buffer to format lines
section .bss
    line_buf resb 512

section .text
extern itoa

; rdi = id, rsi = completed, rdx = timestamp, rcx = title
format_and_append:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi ; id
    mov r13, rsi ; completed
    mov r14, rdx ; timestamp
    mov r15, rcx ; title

    mov rdi, r12
    mov rsi, line_buf
    call itoa
    
    ; find end
    mov rdi, line_buf
    call strlen
    mov rbx, line_buf
    add rbx, rax
    mov byte [rbx], '|'
    inc rbx

    mov rdi, r13
    mov rsi, rbx
    call itoa
    mov rdi, rbx
    call strlen
    add rbx, rax
    mov byte [rbx], '|'
    inc rbx

    mov rdi, r14
    mov rsi, rbx
    call itoa
    mov rdi, rbx
    call strlen
    add rbx, rax
    mov byte [rbx], '|'
    inc rbx

    ; copy title
    mov rsi, r15
.copy:
    mov al, [rsi]
    mov [rbx], al
    test al, al
    jz .done_copy
    inc rsi
    inc rbx
    jmp .copy
.done_copy:
    mov byte [rbx], 10
    mov byte [rbx+1], 0

    mov rdi, line_buf
    call append_todo_file

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; rdi = title
append_todo:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi ; title

    ; get time
    mov rax, SYS_TIME
    mov rdi, current_time
    syscall
    mov rdx, [current_time]

    mov rdi, [next_id]
    mov rsi, 0
    mov rcx, rbx
    call format_and_append

    call load_todos

    pop rbx
    pop rbp
    ret

; rdi = id
complete_todo:
    push rbp
    mov rbp, rsp
    push rbx
    mov rbx, rdi
    
    ; find title from memory
    mov rcx, 1000
    mov rsi, todos
.find:
    mov rax, [rsi]
    cmp rax, rbx
    je .found
    add rsi, 128
    dec rcx
    jnz .find
    jmp .done

.found:
    mov rdi, rbx ; id
    mov r8, 1 ; completed
    mov rdx, [rsi+9] ; timestamp
    add rsi, 17 ; title
    mov rcx, rsi
    mov rsi, r8
    call format_and_append
    call load_todos

.done:
    pop rbx
    pop rbp
    ret

; rdi = id
delete_todo:
    push rbp
    mov rbp, rsp
    push rbx
    mov rbx, rdi
    
    ; find title
    mov rcx, 1000
    mov rsi, todos
.find:
    mov rax, [rsi]
    cmp rax, rbx
    je .found
    add rsi, 128
    dec rcx
    jnz .find
    jmp .done

.found:
    mov rdi, rbx ; id
    mov r8, 2 ; deleted
    mov rdx, [rsi+9] ; timestamp
    add rsi, 17 ; title
    mov rcx, rsi
    mov rsi, r8
    call format_and_append
    call load_todos

.done:
    pop rbx
    pop rbp
    ret

get_todo_list:
    mov rax, todos
    ret

get_todo_count:
    mov rax, [todo_count]
    ret

; -----------------------------------------------------------------------------
; clear_done_todos - append delete records for all completed todos, then reload
; -----------------------------------------------------------------------------
clear_done_todos:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, todos
    mov r12, 1000

.loop:
    mov rax, [rbx]      ; id
    test rax, rax
    jz .next

    mov cl, [rbx+8]
    cmp cl, 1           ; only completed (not already deleted)
    jne .next

    mov rdi, [rbx]      ; id
    mov rsi, 2          ; mark deleted
    mov rdx, [rbx+9]    ; timestamp (unaligned read ok on x86-64)
    lea rcx, [rbx+17]   ; title ptr
    call format_and_append  ; writes to file, does NOT call load_todos

.next:
    add rbx, 128
    dec r12
    jnz .loop

    call load_todos     ; single reload after all deletes

    pop r12
    pop rbx
    pop rbp
    ret

