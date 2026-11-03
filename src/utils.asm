%include "src/defs.inc"
DEFAULT ABS

global strlen
global print
global itoa
global atoi
global strcmp
global strncmp
global find_char
global write_all

section .text

; -----------------------------------------------------------------------------
; strlen - Calculate string length
; rdi: pointer to null-terminated string
; Returns: rax = length
; -----------------------------------------------------------------------------
strlen:
    xor rax, rax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; -----------------------------------------------------------------------------
; print - Print null-terminated string to stdout
; rdi: pointer to string
; -----------------------------------------------------------------------------
print:
    push rbp
    mov rbp, rsp
    push rdi          ; save string pointer
    call strlen
    mov rdx, rax      ; length
    pop rsi           ; restore string pointer to rsi
    mov rdi, STDOUT   ; fd
    mov rax, SYS_WRITE
    syscall
    pop rbp
    ret

; -----------------------------------------------------------------------------
; itoa - Convert integer to string (base 10)
; rdi: integer value
; rsi: pointer to buffer
; Returns: rax = number of bytes written
; -----------------------------------------------------------------------------
itoa:
    push rbx
    push r12
    mov rax, rdi      ; value
    mov rbx, 10       ; base
    mov r12, rsi      ; buffer
    xor rcx, rcx      ; digit count

    ; Handle 0 explicitly
    test rax, rax
    jnz .loop
    mov byte [r12], '0'
    mov byte [r12+1], 0
    mov rax, 1
    pop r12
    pop rbx
    ret

.loop:
    xor rdx, rdx
    div rbx           ; rax = rax / 10, rdx = rax % 10
    add dl, '0'       ; convert to ASCII
    push rdx          ; push character to stack
    inc rcx           ; increment count
    test rax, rax
    jnz .loop

    mov rax, rcx      ; return length
    mov rdi, r12      ; buffer pointer

.pop_loop:
    pop rdx
    mov [rdi], dl
    inc rdi
    dec rcx
    jnz .pop_loop

    mov byte [rdi], 0 ; null-terminate
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; atoi - Convert string to integer (base 10)
; rdi: pointer to string
; Returns: rax = integer value
; -----------------------------------------------------------------------------
atoi:
    xor rax, rax      ; result
    xor rcx, rcx      ; current char

.loop:
    mov cl, [rdi]
    test cl, cl
    jz .done
    cmp cl, '0'
    jl .done
    cmp cl, '9'
    jg .done

    ; overflow guard: stop before rax*10+9 can exceed INT64_MAX
    mov r11, 922337203685477580
    cmp rax, r11
    jae .done

    sub cl, '0'
    imul rax, 10
    add rax, rcx
    inc rdi
    jmp .loop

.done:
    ret

; -----------------------------------------------------------------------------
; strcmp - Compare two null-terminated strings
; rdi: string 1
; rsi: string 2
; Returns: rax = 0 if equal, non-zero otherwise
; -----------------------------------------------------------------------------
strcmp:
    xor rax, rax
.loop:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .diff
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp .loop
.diff:
    sub al, cl
    movsx rax, al
    ret
.equal:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; strncmp - Compare first n bytes of strings
; rdi: string 1
; rsi: string 2
; rdx: n
; Returns: rax = 0 if equal, non-zero otherwise
; -----------------------------------------------------------------------------
strncmp:
    xor rax, rax
    test rdx, rdx
    jz .equal
.loop:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .diff
    test al, al
    jz .equal
    inc rdi
    inc rsi
    dec rdx
    jz .equal
    jmp .loop
.diff:
    sub al, cl
    movsx rax, al
    ret
.equal:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; write_all - Write entire buffer to fd, handling partial writes and EINTR
; rdi: fd
; rsi: buffer
; rdx: length
; Returns: rax = 0 on success, negative errno on failure
; -----------------------------------------------------------------------------
write_all:
.loop:
    test rdx, rdx
    jz .ok
    mov rax, SYS_WRITE
    syscall
    cmp rax, 0
    jg .advance
    cmp rax, -4         ; -EINTR: retry
    je .loop
    test rax, rax
    jnz .failed
    mov rax, -5         ; a zero-byte write is an I/O error, never success
.failed:
    ret
.advance:
    add rsi, rax
    sub rdx, rax
    jmp .loop
.ok:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; find_char - Find character in string
; rdi: pointer to string
; rsi: character to find
; Returns: rax = pointer to character, or 0 if not found
; -----------------------------------------------------------------------------
find_char:
    mov rax, rdi
.loop:
    mov cl, [rax]
    test cl, cl
    jz .not_found
    cmp cl, sil
    je .found
    inc rax
    jmp .loop
.not_found:
    xor rax, rax
.found:
    ret

; Strict nonnegative decimal, <= INT64_MAX. Returns -1 on empty/invalid/overflow.
; Preserves r8-r15; clobbers rax, rcx, rdx, rsi.
global parse_uint
parse_uint:
    xor eax, eax
    cmp byte [rdi], 0
    je .bad
    mov rsi, rdi
.loop:
    movzx ecx, byte [rsi]
    test ecx, ecx
    jz .done
    sub ecx, '0'
    cmp ecx, 9
    ja .bad
    mov rdx, 922337203685477580
    cmp rax, rdx
    ja .bad
    jb .digit
    cmp ecx, 7
    ja .bad
.digit:
    imul rax, 10
    add rax, rcx
    inc rsi
    jmp .loop
.bad:
    mov rax, -1
.done:
    ret

; Validate NUL-terminated UTF-8 (reject overlong encodings, surrogates, >U+10FFFF).
global valid_utf8
valid_utf8:
    mov rsi,rdi
.loop:
    movzx eax,byte [rsi]
    test eax,eax
    jz .ok
    inc rsi
    cmp al,128
    jb .loop
    cmp al,0xc2
    jb .bad
    cmp al,0xdf
    jbe .two
    cmp al,0xef
    jbe .three
    cmp al,0xf4
    ja .bad
    mov ecx,3
    mov dl,0x80
    mov dh,0xbf
    cmp al,0xf0
    jne .not_f0
    mov dl,0x90
.not_f0:
    cmp al,0xf4
    jne .check_second
    mov dh,0x8f
    jmp .check_second
.three:
    mov ecx,2
    mov dl,0x80
    mov dh,0xbf
    cmp al,0xe0
    jne .not_e0
    mov dl,0xa0
.not_e0:
    cmp al,0xed
    jne .check_second
    mov dh,0x9f
    jmp .check_second
.two:
    mov ecx,1
    mov dl,0x80
    mov dh,0xbf
.check_second:
    mov al,[rsi]
    cmp al,dl
    jb .bad
    cmp al,dh
    ja .bad
    inc rsi
    dec ecx
    jz .loop
.cont:
    mov al,[rsi]
    sub al,0x80
    cmp al,0x3f
    ja .bad
    inc rsi
    dec ecx
    jnz .cont
    jmp .loop
.ok:
    xor eax,eax
    ret
.bad:
    mov rax,-1
    ret

; Epoch seconds -> exactly YYYY-MM-DDTHH:MM:SSZ + NUL, or 0 out of range.
; Gregorian calendar from 1970 through 9999; only integer arithmetic/syscalls.
global format_utc
format_utc:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rsi
    mov rax,253402300799
    cmp rdi,rax
    ja .invalid
    mov rax,rdi
    xor edx,edx
    mov ecx,86400
    div rcx
    mov r13,rdx ; seconds within day
    add rax,719468
    xor edx,edx
    mov ecx,146097
    div rcx
    imul r14,rax,400 ; era years
    mov rbx,rdx ; day of era
    mov rax,rbx
    xor edx,edx
    mov ecx,1460
    div rcx
    mov r15,rbx
    sub r15,rax
    mov rax,rbx
    xor edx,edx
    mov ecx,36524
    div rcx
    add r15,rax
    mov rax,rbx
    xor edx,edx
    mov ecx,146096
    div rcx
    sub r15,rax
    mov rax,r15
    xor edx,edx
    mov ecx,365
    div rcx
    add r14,rax ; provisional year
    mov r15,rax ; year of era
    imul r8,rax,365
    mov rax,r15
    shr rax,2
    add r8,rax
    mov rax,r15
    xor edx,edx
    mov ecx,100
    div rcx
    sub r8,rax
    sub rbx,r8 ; day of year, March based
    lea rax,[rbx*4+rbx+2]
    xor edx,edx
    mov ecx,153
    div rcx
    mov r15,rax ; month index
    imul rax,153
    add rax,2
    xor edx,edx
    mov ecx,5
    div rcx
    sub rbx,rax
    inc rbx ; day of month
    lea r8,[r15+3]
    cmp r15,10
    jb .month
    lea r8,[r15-9]
.month:
    cmp r8,2
    ja .year
    inc r14
.year:
    mov rdi,r12
    mov rax,r14
    xor edx,edx
    mov ecx,100
    div rcx
    push rdx
    call .two_digits
    pop rax
    call .two_digits
    mov al,'-'
    stosb
    mov rax,r8
    call .two_digits
    mov al,'-'
    stosb
    mov rax,rbx
    call .two_digits
    mov al,'T'
    stosb
    mov rax,r13
    xor edx,edx
    mov ecx,3600
    div rcx
    mov r13,rdx
    call .two_digits
    mov al,':'
    stosb
    mov rax,r13
    xor edx,edx
    mov ecx,60
    div rcx
    mov r13,rdx
    call .two_digits
    mov al,':'
    stosb
    mov rax,r13
    call .two_digits
    mov word [rdi],'Z'
    mov eax,20
    jmp .done
.two_digits:
    xor edx,edx
    mov ecx,10
    div rcx
    add al,'0'
    stosb
    lea eax,[rdx+'0']
    stosb
    ret
.invalid:
    mov byte [r12],0
    xor eax,eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
