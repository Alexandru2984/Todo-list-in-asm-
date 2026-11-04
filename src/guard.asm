%include "src/defs.inc"
DEFAULT ABS
extern sha256, strlen, strcmp, copy_string, write_all, parse_uint, itoa
extern request_method, request_path, request_body, current_uid
extern storage_version, lock_user_file, unlock_user_file, load_todos, save_snapshot

global guard_begin, guard_field, guard_fields_finish, guard_preview
 global guard_storage_reset, guard_hash_state, guard_parse, guard_validate, guard_check
 global guard_presave, guard_write, guard_finish, guard_html, guard_json, guard_required, guard_restore_floor
section .data
    state_key db '_state',0
    request_key db '_request',0
    hex db '0123456789abcdef'
    generation_prefix db '#generation=',0
    input_start db '<input type="hidden" name="_state" value="',0
    input_request db '"><input type="hidden" name="_request" value="',0
    input_end db '">',0
    revision_prefix db '#revision=',0
    preview_path db '/import-preview',0
    json_head db '{"revision":"',0
    json_state db '","state":"',0
    json_request db '","operationId":"',0
    json_end db '"}',10,0
    empty db 0
    method_post db 'method="post"'
section .bss
    state_hash resb 65
    expected_state resb 65
    request_key_value resb 33
    request_hash resb 65
    state_material resb 65
    hash_bytes resb 32
    request_material resb PATH_MAX+40
    field_flags resq 1
    mode resq 1 ; 0 legacy API/read, 1 mutation, 2 preview
    pending resq 1
    finished resq 1
    state_ready resq 1
    generation resb 33
    generation_seen resq 1
    revision resq 1
    revision_seen resq 1
    receipt_count resq 1
    receipts resb 16*96 ; 32 hex request key, 64 hex request fingerprint
    random_bytes resb 16
    record resb 128
    inputs resb 256
    input_length resq 1
    positions resq 8192
section .text
; ASCII lowercase hex only, exact length ecx. rdi preserved.
valid_hex:
    xor edx,edx
.loop:
    mov al,[rdi+rdx]
    cmp al,'0'
    jb .bad
    cmp al,'9'
    jbe .next
    cmp al,'a'
    jb .bad
    cmp al,'f'
    ja .bad
.next:
    inc edx
    cmp edx,ecx
    jb .loop
    cmp byte [rdi+rdx],0
    jne .bad
    xor eax,eax
    ret
.bad:
    mov rax,-400
    ret

; rsi=binary, ecx=length, rdi=hex output; advance and NUL terminate.
to_hex:
    mov r8d,ecx
.loop:
    movzx eax,byte [rsi]
    inc rsi
    mov edx,eax
    shr eax,4
    mov al,[hex+rax]
    stosb
    mov eax,edx
    and eax,15
    mov al,[hex+rax]
    stosb
    dec r8d
    jnz .loop
    mov byte [rdi],0
    ret

; Hash exact raw body and raw route before destructive form parsing/aliases.
guard_begin:
    mov qword [state_ready],0
    mov qword [field_flags],0
    mov qword [mode],0
    mov qword [pending],0
    mov qword [finished],0
    cmp qword [request_method],2
    jne .done
    mov rdi,[request_body]
    call strlen
    mov rsi,rax
    mov rdi,[request_body]
    mov rdx,hash_bytes
    call sha256
    mov rdi,request_material
    mov rsi,request_path
    call copy_string
    inc rdi ; include fixed NUL delimiter before binary body digest
    mov rsi,hash_bytes
    mov ecx,32
    rep movsb
    mov rsi,rdi
    sub rsi,request_material
    mov rdi,request_material
    mov rdx,hash_bytes
    call sha256
    mov rsi,hash_bytes
    mov rdi,request_hash
    mov ecx,32
    call to_hex
.done:
    xor eax,eax
    ret

; Decoded field name/value. Returns 1 known, 0 other, -400 malformed.
guard_field:
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
    mov rsi,state_key
    call strcmp
    test rax,rax
    jz .state
    mov rdi,rbx
    mov rsi,request_key
    call strcmp
    test rax,rax
    jnz .unknown
    test qword [field_flags],2
    jnz .bad
    or qword [field_flags],2
    mov rdi,r12
    mov ecx,32
    call valid_hex
    test rax,rax
    js .bad
    mov rdi,request_key_value
    mov rsi,r12
    mov ecx,33
    rep movsb
    jmp .known
.state:
    test qword [field_flags],1
    jnz .bad
    or qword [field_flags],1
    mov rdi,r12
    mov ecx,64
    call valid_hex
    test rax,rax
    js .bad
    mov rdi,expected_state
    mov rsi,r12
    mov ecx,65
    rep movsb
.known:
    mov eax,1
    jmp .done
.unknown:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-400
.done:
    pop r12
    pop rbx
    ret

guard_fields_finish:
    cmp qword [field_flags],0
    je .ok
    cmp qword [field_flags],3
    jne .bad
    mov qword [mode],1
    mov rdi,state_hash
    mov rsi,expected_state
    mov ecx,65
    rep movsb
    mov qword [state_ready],1
.ok:
    xor eax,eax
    ret
.bad:
    mov rax,-400
    ret

guard_preview:
    cmp qword [mode],0
    je .done
    mov qword [mode],2
.done:
    ret

; Reset only persisted state, never request fields/digest across a reload.
guard_storage_reset:
    mov qword [generation_seen],0
    mov qword [revision],0
    mov qword [revision_seen],0
    mov qword [receipt_count],0
    mov qword [state_ready],0
    ret

; Exact snapshot bytes before line parser modifies them; empty missing file too.
guard_hash_state:
    mov rdx,hash_bytes
    call sha256
    mov rdi,state_material
    mov rsi,current_uid
    mov ecx,32
    rep movsb
    mov byte [rdi],0
    inc rdi
    mov rsi,hash_bytes
    mov ecx,32
    rep movsb
    mov rdi,state_material
    mov esi,65
    mov rdx,hash_bytes
    call sha256
    mov rsi,hash_bytes
    mov rdi,state_hash
    mov ecx,32
    call to_hex
    mov qword [state_ready],1
    ret

; V4-only generation/receipt record. 1 known, 0 other, -500 malformed.
guard_parse:
    push rbx
    push r12
    mov rbx,rdi
    cmp dword [rbx],'#rev'
    jne .generation
    mov rsi,revision_prefix
    mov ecx,10
    repe cmpsb
    jne .bad
    cmp qword [revision_seen],0
    jne .bad
    cmp qword [storage_version],5
    jb .revision_number
    push rdi
    call strlen
    pop rdi
    cmp rax,19
    ja .bad
.revision_number:
    call parse_uint
    test rax,rax
    jle .bad
    mov [revision],rax
    mov qword [revision_seen],1
    jmp .known
.generation:
    cmp dword [rbx],'#gen'
    jne .receipt
    mov rsi,generation_prefix
    mov ecx,12
    repe cmpsb
    jne .bad
    cmp qword [generation_seen],0
    jne .bad
    mov ecx,32
    call valid_hex
    test rax,rax
    js .bad
    mov rsi,rdi
    mov rdi,generation
    mov ecx,33
    rep movsb
    mov qword [generation_seen],1
    jmp .known
.receipt:
    cmp word [rbx],'R|'
    jne .unknown
    cmp qword [receipt_count],16
    jae .bad
    cmp byte [rbx+34],'|'
    jne .bad
    mov byte [rbx+34],0
    lea rdi,[rbx+2]
    mov ecx,32
    call valid_hex
    test rax,rax
    js .bad
    lea rdi,[rbx+35]
    mov ecx,64
    call valid_hex
    test rax,rax
    js .bad
    xor r12d,r12d
.duplicate:
    cmp r12,[receipt_count]
    jae .append
    imul rax,r12,96
    lea rdi,[receipts+rax]
    lea rsi,[rbx+2]
    mov ecx,32
    repe cmpsb
    je .bad
    inc r12
    jmp .duplicate
.append:
    imul rax,r12,96
    lea rdi,[receipts+rax]
    lea rsi,[rbx+2]
    mov ecx,32
    rep movsb
    lea rsi,[rbx+35]
    mov ecx,64
    rep movsb
    inc qword [receipt_count]
.known:
    mov eax,1
    jmp .done
.unknown:
    xor eax,eax
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r12
    pop rbx
    ret

guard_validate:
    cmp qword [storage_version],4
    jb .ok
    cmp qword [generation_seen],1
    jne .bad
    cmp qword [revision_seen],1
    jne .bad
.ok:
    xor eax,eax
    ret
.bad:
    mov rax,-500
    ret

; Called after validated load, under stable workspace lock. Replay precedes CAS.
guard_check:
    cmp qword [mode],0
    jne .guarded
    cmp qword [storage_version],4
    jb .ok
    cmp qword [request_method],2
    jne .ok
    mov rdi,request_path
    mov rsi,preview_path
    call strcmp
    test rax,rax
    jz .ok
    mov rax,-428
    ret
.guarded:
    cmp qword [mode],2
    je .state
    xor r8d,r8d
.receipt:
    cmp r8,[receipt_count]
    jae .state
    imul rax,r8,96
    lea rdi,[receipts+rax]
    mov rsi,request_key_value
    mov ecx,32
    repe cmpsb
    jne .next
    ; rdi points just after the 32-byte key
    mov rsi,request_hash
    mov ecx,64
    repe cmpsb
    jne .stale
    mov qword [finished],1
    mov rax,-208 ; internal successful replay, router returns original redirect
    ret
.next:
    inc r8
    jmp .receipt
.state:
    mov rdi,state_hash
    mov rsi,expected_state
    mov ecx,64
    repe cmpsb
    jne .stale
    cmp qword [mode],1
    jne .ok
    mov qword [pending],1
.ok:
    xor eax,eax
    ret
.stale:
    mov rax,-412
    ret

random_hex:
    push rbx
    push r12
    mov r12,rdi
    xor ebx,ebx
.retry:
    mov eax,SYS_GETRANDOM
    lea rdi,[random_bytes+rbx]
    mov esi,16
    sub rsi,rbx
    xor edx,edx
    syscall
    cmp rax,-4
    je .retry
    test rax,rax
    jle .bad
    add rbx,rax
    cmp rbx,16
    jb .retry
    mov rdi,r12
    mov rsi,random_bytes
    mov ecx,16
    call to_hex
    xor eax,eax
    jmp .done
.bad:
    mov rax,-507
.done:
    pop r12
    pop rbx
    ret

; Prepare generation and bounded successful receipt inside the same snapshot.
guard_presave:
    cmp qword [pending],0
    jne .v4
    cmp qword [storage_version],4
    jb .ok
.v4:
    mov rax,9223372036854775807
    cmp [revision],rax
    jae .exhausted
    inc qword [revision]
    mov rdi,generation
    call random_hex
    test rax,rax
    js .done
    cmp qword [storage_version],4
    ja .version_ready
    mov qword [storage_version],4
.version_ready:
    mov qword [generation_seen],1
    cmp qword [pending],0
    je .ok
    cmp qword [receipt_count],16
    jb .append
    mov rdi,receipts
    mov rsi,receipts+96
    mov ecx,15*96
    rep movsb
    mov qword [receipt_count],15
.append:
    imul rax,[receipt_count],96
    lea rdi,[receipts+rax]
    mov rsi,request_key_value
    mov ecx,32
    rep movsb
    mov rsi,request_hash
    mov ecx,64
    rep movsb
    inc qword [receipt_count]
    mov qword [finished],1
.ok:
    xor eax,eax
.done:
    ret
.exhausted:
    mov rax,-507
    ret

; Write before current/history records. rdi=temporary snapshot fd.
guard_write:
    push rbx
    push r12
    mov r12,rdi
    mov rdi,record
    mov rsi,revision_prefix
    call copy_string
    mov rsi,rdi
    mov rdi,[revision]
    call itoa
    add rsi,rax
    mov byte [rsi],10
    lea rdx,[rsi+1]
    sub rdx,record
    mov rsi,record
    mov rdi,r12
    call write_all
    test rax,rax
    js .done
    mov rdi,record
    mov rsi,generation_prefix
    call copy_string
    mov rsi,generation
    call copy_string
    mov byte [rdi],10
    lea rdx,[rdi+1]
    sub rdx,record
    mov rsi,record
    mov rdi,r12
    call write_all
    test rax,rax
    js .done
    xor ebx,ebx
.loop:
    cmp rbx,[receipt_count]
    jae .ok
    mov word [record],'R|'
    mov rdi,record+2
    imul rax,rbx,96
    lea rsi,[receipts+rax]
    mov ecx,32
    rep movsb
    mov byte [rdi],'|'
    inc rdi
    mov ecx,64
    rep movsb
    mov byte [rdi],10
    mov rdi,r12
    mov rsi,record
    mov edx,100
    call write_all
    test rax,rax
    js .done
    inc ebx
    jmp .loop
.ok:
    xor eax,eax
.done:
    pop r12
    pop rbx
    ret

; Successful no-op still consumes its key atomically, without changing undo.
guard_finish:
    cmp qword [mode],1
    jne .ok
    cmp qword [finished],0
    jne .ok
    call lock_user_file
    test rax,rax
    js .done
    call load_todos
    cmp rax,-208
    je .unlock_ok
    test rax,rax
    js .unlock
    call save_snapshot
.unlock:
    push rax
    call unlock_user_file
    pop rax
    ret
.unlock_ok:
    call unlock_user_file
.ok:
    xor eax,eax
.done:
    ret

; Inject fields into our server-rendered POST forms in-place, backwards. Task
; data is HTML-escaped before this pass. No extra response-sized buffer is used.
; rdi=mutable HTML buffer, rsi=length -> rax=new length or negative.
guard_html:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13,rsi
    cmp qword [state_ready],0
    je .unchanged
    mov rdi,inputs
    mov rsi,input_start
    call copy_string
    mov rsi,state_hash
    call copy_string
    mov rsi,input_request
    call copy_string
    push rdi
    call random_hex
    pop rdi
    test rax,rax
    js .done
    add rdi,32
    mov rsi,input_end
    call copy_string
    sub rdi,inputs
    mov [input_length],rdi
    xor ebx,ebx
    xor r14d,r14d
.scan:
    lea rax,[rbx+13]
    cmp rax,r13
    ja .expand
    lea rdi,[r12+rbx]
    mov rsi,method_post
    mov ecx,13
    repe cmpsb
    jne .next
    add rbx,13
.end_tag:
    cmp rbx,r13
    jae .bad
    cmp byte [r12+rbx],'>'
    je .position
    inc rbx
    jmp .end_tag
.position:
    inc rbx
    cmp r14,8192
    jae .bad
    mov [positions+r14*8],rbx
    inc r14
    jmp .scan
.next:
    inc rbx
    jmp .scan
.expand:
    mov r15,r14
    imul r15,[input_length]
    add r15,r13
    cmp r15,RESPONSE_MAX
    jae .bad
    mov byte [r12+r15],0
    mov rax,r15 ; final length, preserved on stack through the move
    push rax
.move:
    test r14,r14
    jz .moved
    dec r14
    mov r8,[positions+r14*8]
.tail:
    cmp r13,r8
    jbe .insert
    dec r13
    dec r15
    mov al,[r12+r13]
    mov [r12+r15],al
    jmp .tail
.insert:
    mov rcx,[input_length]
.field:
    dec rcx
    dec r15
    mov al,[inputs+rcx]
    mov [r12+r15],al
    test rcx,rcx
    jnz .field
    jmp .move
.moved:
    pop rax
    jmp .done
.unchanged:
    mov rax,r13
    jmp .done
.bad:
    mov rax,-500
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Private protocol discovery; exact revision is a string to avoid JS rounding.
guard_json:
    push rbx
    mov rbx,rdi
    mov rsi,json_head
    call copy_string
    mov rsi,rdi
    mov rdi,[revision]
    call itoa
    lea rdi,[rsi+rax]
    mov rsi,json_state
    call copy_string
    mov rsi,state_hash
    call copy_string
    mov rsi,json_request
    call copy_string
    push rdi
    call random_hex
    pop rdi
    test rax,rax
    js .done
    add rdi,32
    mov rsi,json_end
    call copy_string
    mov rax,rdi
    sub rax,rbx
.done:
    pop rbx
    ret

guard_required:
    cmp qword [mode],1
    jne .missing
    xor eax,eax
    ret
.missing:
    mov rax,-428
    ret

guard_restore_floor:
    mov rax,9223372036854775807
    cmp rdi,rax
    jae .full
    cmp [revision],rax
    jae .full
    cmp rdi,[revision]
    jbe .keep
    mov [revision],rdi
.keep:
    mov qword [receipt_count],0
    mov qword [pending],0
    xor eax,eax
    ret
.full:
    mov rax,-507
    ret
