%include "src/defs.inc"
DEFAULT ABS
extern get_todo_list, current_uid, sha256, format_utc, copy_string
extern priority_names, recurrence_names

global export_calendar
section .data
    calendar_head db 'BEGIN:VCALENDAR',13,10,'VERSION:2.0',13,10,'PRODID:-//ASM TODO//Task Calendar//EN',13,10,'CALSCALE:GREGORIAN',13,10,0
    calendar_end db 'END:VCALENDAR',13,10,0
    event_head db 'BEGIN:VEVENT',13,10,'CLASS:PRIVATE',13,10,'TRANSP:TRANSPARENT',13,10,'STATUS:CONFIRMED',13,10,0
    event_end db 'END:VEVENT',13,10,0
    uid_prefix db 'UID:',0
    uid_suffix db '@asm.micutu.com',0
    stamp_prefix db 'DTSTAMP:',0
    start_prefix db 'DTSTART;VALUE=DATE:',0
    summary_prefix db 'SUMMARY:',0
    done_prefix db '[Done] ',0
    description_prefix db 'DESCRIPTION:Task status: ',0
    active db 'Active',0
    doing db 'In progress',0
    completed db 'Done',0
    description_priority db 92,'nPriority: ',0
    description_project db 92,'nProject: ',0
    description_tags db 92,'nTags: ',0
    description_repeat db 92,'nRepeats: ',0
    description_snapshot db 92,'nExport snapshot. Changes are not synced.',0
    priority_prefix db 'PRIORITY:',0
    priority_digits db '5931'
    hex_chars db '0123456789abcdef'
    uid_input db 'ASM TODO calendar UID v1',0
    uid_workspace times 32 db 0
    uid_task dq 0
    uid_input_len equ $-uid_input
section .bss
    digest resb 32
    iso_stamp resb 24
    export_stamp resb 17
    line resb 1024
section .text
%macro fixed 1
    mov rdi,r15
    mov rsi,%1
    call copy_string
    mov r15,rdi
%endmacro
%macro begin_line 1
    mov rdi,line
    mov rsi,%1
    call copy_string
%endmacro

; Authenticated snapshot of live tasks with a due date, independent of filters.
; A DATE DTSTART without DTEND/DURATION is a one-day event (RFC 5545 3.6.1).
; Each event is <1 KiB after escaping/folding; <=1000 live tasks fits response cap.
export_calendar:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r15,rdi
    mov eax,SYS_TIME
    xor edi,edi
    syscall
    test rax,rax
    js .bad
    mov rdi,rax
    mov rsi,iso_stamp
    call format_utc
    test rax,rax
    jz .bad
    mov rdi,export_stamp
    mov rsi,iso_stamp
.compact_stamp:
    lodsb
    test al,al
    jz .stamp_done
    cmp al,'-'
    je .compact_stamp
    cmp al,':'
    je .compact_stamp
    stosb
    jmp .compact_stamp
.stamp_done:
    mov byte [rdi],0
    mov rdi,uid_workspace
    mov rsi,current_uid
    mov ecx,32
    rep movsb
    fixed calendar_head
    call get_todo_list
    mov rbx,rax
    mov r14d,SLOT_MAX
.task:
    cmp qword [rbx],0
    je .next
    cmp byte [rbx+8],2
    je .next
    cmp qword [rbx+T_DUE],0
    je .next
    fixed event_head
    mov rax,[rbx]
    mov [uid_task],rax
    mov rdi,uid_input
    mov esi,uid_input_len
    mov rdx,digest
    call sha256
    begin_line uid_prefix
    xor ecx,ecx
.hex:
    movzx eax,byte [digest+rcx]
    mov edx,eax
    shr eax,4
    mov al,[hex_chars+rax]
    stosb
    mov eax,edx
    and eax,15
    mov al,[hex_chars+rax]
    stosb
    inc ecx
    cmp ecx,32
    jb .hex
    mov rsi,uid_suffix
    call copy_string
    call flush_line
    begin_line stamp_prefix
    mov rsi,export_stamp
    call copy_string
    call flush_line
    mov rdi,[rbx+T_DUE]
    mov rsi,iso_stamp
    call format_utc
    test rax,rax
    jz .bad
    begin_line start_prefix
    mov rsi,iso_stamp
    mov ecx,10
.date:
    lodsb
    cmp al,'-'
    je .date_next
    stosb
.date_next:
    loop .date
    call flush_line
    begin_line summary_prefix
    cmp byte [rbx+8],1
    jne .title
    mov rsi,done_prefix
    call copy_string
.title:
    lea rsi,[rbx+17]
    call calendar_text
    call flush_line
    begin_line priority_prefix
    mov rax,[rbx+T_PRIORITY]
    mov al,[priority_digits+rax]
    stosb
    call flush_line
    begin_line description_prefix
    mov rsi,completed
    cmp byte [rbx+8],1
    je .status
    mov rsi,doing
    cmp qword [rbx+T_STAGE],1
    je .status
    mov rsi,active
.status:
    call copy_string
    mov rsi,description_priority
    call copy_string
    mov rax,[rbx+T_PRIORITY]
    mov rsi,[priority_names+rax*8]
    call copy_string
    cmp byte [rbx+T_PROJECT],0
    je .tags
    mov rsi,description_project
    call copy_string
    lea rsi,[rbx+T_PROJECT]
    call calendar_text
.tags:
    cmp byte [rbx+T_TAGS],0
    je .repeat
    mov rsi,description_tags
    call copy_string
    lea rsi,[rbx+T_TAGS]
    call calendar_text
.repeat:
    cmp qword [rbx+T_REPEAT],0
    je .snapshot
    mov rsi,description_repeat
    call copy_string
    mov rax,[rbx+T_REPEAT]
    mov rsi,[recurrence_names+rax*8]
    call copy_string
.snapshot:
    mov rsi,description_snapshot
    call copy_string
    call flush_line
    fixed event_end
.next:
    add rbx,TASK_SIZE
    dec r14
    jnz .task
    fixed calendar_end
    mov rax,r15
    sub rax,r12
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

; TEXT escaping, separate from HTML/JSON/CSV. No task bytes become property names.
calendar_text:
    lodsb
    test al,al
    jz .done
    cmp al,13
    je calendar_text
    cmp al,10
    je .newline
    cmp al,92
    je .escape
    cmp al,','
    je .escape
    cmp al,';'
    je .escape
    stosb
    jmp calendar_text
.newline:
    mov al,'n'
.escape:
    mov byte [rdi],92
    inc rdi
    stosb
    jmp calendar_text
.done:
    ret

; <=75 octets per physical content line; fold before a whole UTF-8 character.
; rdi=line end, r15=response cursor. Scratch line is <512 bytes by field bounds.
flush_line:
    mov byte [rdi],0
    mov rsi,line
    xor r8d,r8d
.character:
    mov al,[rsi]
    test al,al
    jz .end
    mov edx,1
    cmp al,0xc0
    jb .fit
    inc edx
    cmp al,0xe0
    jb .fit
    inc edx
    cmp al,0xf0
    jb .fit
    inc edx
.fit:
    lea rax,[r8+rdx]
    cmp rax,75
    jbe .copy
    mov word [r15],0x0a0d
    mov byte [r15+2],' '
    add r15,3
    mov r8d,1
.copy:
    add r8,rdx
    mov ecx,edx
.bytes:
    lodsb
    mov [r15],al
    inc r15
    loop .bytes
    jmp .character
.end:
    mov word [r15],0x0a0d
    add r15,2
    ret
