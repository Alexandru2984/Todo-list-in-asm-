%include "src/defs.inc"

global strlen
global print
global itoa
global atoi
global strcmp
global strncmp
global find_char

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
