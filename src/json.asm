%include "src/defs.inc"
%include "src/import.inc"
DEFAULT ABS
extern valid_utf8

global json_begin, json_next, json_text, json_number
section .bss
    cursor resq 1
    json_text resq 1
    json_number resq 1
section .text
json_begin:
    cmp word [rdi],0xbbef
    jne .start
    cmp byte [rdi+2],0xbf
    jne .start
    add rdi,3
.start:
    mov [cursor],rdi
    ret

; Strict bounded-import lexer. The caller owns a padded NUL-terminated buffer.
; Strings decode in place, never expanding past their original bytes. The
; schema parser supplies structural/depth/row limits; no arbitrary recursion.
json_next:
    push rbx
    push r12
    push r13
    push r14
    mov rbx,[cursor]
.space:
    movzx eax,byte [rbx]
    cmp al,' '
    je .skip
    cmp al,9
    je .skip
    cmp al,10
    je .skip
    cmp al,13
    je .skip
    jmp .token
.skip:
    inc rbx
    jmp .space
.token:
    test al,al
    jz .end
    cmp al,'"'
    je .string
    cmp al,'0'
    jb .symbol
    cmp al,'9'
    jbe .number
.symbol:
    cmp al,'{'
    je .one
    cmp al,'}'
    je .one
    cmp al,'['
    je .one
    cmp al,']'
    je .one
    cmp al,':'
    je .one
    cmp al,','
    je .one
    cmp al,'t'
    je .true
    cmp al,'f'
    je .false
    cmp al,'n'
    je .null
    jmp .bad
.one:
    inc rbx
    jmp .end
.true:
    cmp dword [rbx],'true'
    jne .bad
    add rbx,4
    mov r12d,JSON_TRUE
    jmp .literal
.false:
    cmp dword [rbx],'fals'
    jne .bad
    cmp byte [rbx+4],'e'
    jne .bad
    add rbx,5
    mov r12d,JSON_FALSE
    jmp .literal
.null:
    cmp dword [rbx],'null'
    jne .bad
    add rbx,4
    mov r12d,JSON_NULL
.literal:
    call delimiter
    test eax,eax
    jz .bad
    mov eax,r12d
    jmp .end
.number:
    xor r12d,r12d
    cmp byte [rbx],'0'
    jne .digit
    movzx eax,byte [rbx+1]
    sub eax,'0'
    cmp eax,9
    jbe .bad
.digit:
    movzx ecx,byte [rbx]
    sub ecx,'0'
    cmp ecx,9
    ja .number_end
    mov rax,922337203685477580
    cmp r12,rax
    ja .bad
    jb .add
    cmp ecx,7
    ja .bad
.add:
    imul r12,10
    add r12,rcx
    inc rbx
    jmp .digit
.number_end:
    call delimiter
    test eax,eax
    jz .bad
    mov [json_number],r12
    mov eax,JSON_NUMBER
    jmp .end
.string:
    inc rbx
    mov r12,rbx ; decoded start
    mov r13,rbx ; write cursor
.character:
    movzx eax,byte [rbx]
    inc rbx
    cmp al,'"'
    je .string_end
    cmp al,32
    jb .bad
    cmp al,92
    je .escape
.put:
    mov [r13],al
    inc r13
    jmp .character
.escape:
    movzx eax,byte [rbx]
    inc rbx
    cmp al,'"'
    je .put
    cmp al,92
    je .put
    cmp al,'/'
    je .put
    cmp al,'b'
    je .backspace
    cmp al,'f'
    je .formfeed
    cmp al,'n'
    je .newline
    cmp al,'r'
    je .return
    cmp al,'t'
    je .tab
    cmp al,'u'
    jne .bad
    call hex4
    test rax,rax
    js .bad
    cmp eax,0xd800
    jb .unicode
    cmp eax,0xdbff
    ja .low_surrogate
    mov r14d,eax
    cmp word [rbx],0x755c ; backslash-u
    jne .bad
    add rbx,2
    call hex4
    cmp eax,0xdc00
    jb .bad
    cmp eax,0xdfff
    ja .bad
    sub r14d,0xd800
    shl r14d,10
    sub eax,0xdc00
    lea eax,[r14+rax+0x10000]
    jmp .unicode
.low_surrogate:
    cmp eax,0xdfff
    jbe .bad
.unicode:
    test eax,eax
    jz .bad ; private storage fields cannot represent NUL
    cmp eax,0x80
    jb .put
    mov edx,eax
    cmp eax,0x800
    jb .two
    cmp eax,0x10000
    jb .three
    shr eax,18
    or al,0xf0
    mov [r13],al
    inc r13
    mov eax,edx
    shr eax,12
    and al,63
    or al,0x80
    mov [r13],al
    inc r13
    jmp .tail
.three:
    shr eax,12
    or al,0xe0
    mov [r13],al
    inc r13
    jmp .tail
.two:
    shr eax,6
    or al,0xc0
    mov [r13],al
    inc r13
    jmp .last
.tail:
    mov eax,edx
    shr eax,6
    and al,63
    or al,0x80
    mov [r13],al
    inc r13
.last:
    mov eax,edx
    and al,63
    or al,0x80
    jmp .put
.backspace:
    mov al,8
    jmp .put
.formfeed:
    mov al,12
    jmp .put
.newline:
    mov al,10
    jmp .put
.return:
    mov al,13
    jmp .put
.tab:
    mov al,9
    jmp .put
.string_end:
    mov byte [r13],0
    mov [json_text],r12
    mov rdi,r12
    call valid_utf8
    test rax,rax
    js .bad
    mov eax,JSON_STRING
.end:
    mov [cursor],rbx
    jmp .done
.bad:
    mov rax,-422
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Check that a literal/number ends at a JSON delimiter; no prefix acceptance.
delimiter:
    movzx eax,byte [rbx]
    test al,al
    jz .yes
    cmp al,' '
    je .yes
    cmp al,9
    je .yes
    cmp al,10
    je .yes
    cmp al,13
    je .yes
    cmp al,','
    je .yes
    cmp al,']'
    je .yes
    cmp al,'}'
    je .yes
    xor eax,eax
    ret
.yes:
    mov eax,1
    ret

hex4:
    xor r8d,r8d
    mov r9d,4
.hex:
    movzx eax,byte [rbx]
    inc rbx
    sub eax,'0'
    cmp eax,9
    jbe .digit
    add eax,'0'
    or al,32
    sub eax,'a'
    cmp eax,5
    ja .bad
    add eax,10
.digit:
    shl r8d,4
    or r8d,eax
    dec r9d
    jnz .hex
    mov eax,r8d
    ret
.bad:
    mov rax,-1
    ret
