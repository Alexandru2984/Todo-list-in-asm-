; SHA-256, RFC 6234. No libc, external executable or CPU-extension requirement.
DEFAULT ABS
global sha256
section .rodata
initial dd 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
rounds dd 0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5
 dd 0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174
 dd 0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da
 dd 0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967
 dd 0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85
 dd 0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070
 dd 0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3
 dd 0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
section .bss
state resd 8
schedule resd 64
padding resb 128
section .text
; rdi=bytes, rsi=length, rdx=32-byte output. Single-process utility context.
sha256:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13,rsi
    mov r14,rdx
    mov r15,rsi
    mov rsi,initial
    mov rdi,state
    mov ecx,8
    rep movsd
.blocks:
    cmp r13,64
    jb .pad
    mov rdi,r12
    call compress
    add r12,64
    sub r13,64
    jmp .blocks
.pad:
    mov rdi,padding
    xor eax,eax
    mov ecx,128
    rep stosb
    mov rsi,r12
    mov rdi,padding
    mov rcx,r13
    rep movsb
    mov byte [rdi],0x80
    mov rax,r15
    shl rax,3
    bswap rax
    cmp r13,56
    jb .one
    mov [padding+120],rax
    mov rdi,padding
    call compress
    mov rdi,padding+64
    call compress
    jmp .output
.one:
    mov [padding+56],rax
    mov rdi,padding
    call compress
.output:
    xor ecx,ecx
.loop:
    mov eax,[state+rcx*4]
    bswap eax
    mov [r14+rcx*4],eax
    inc ecx
    cmp ecx,8
    jb .loop
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
compress:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor ecx,ecx
.load:
    mov eax,[rdi+rcx*4]
    bswap eax
    mov [schedule+rcx*4],eax
    inc ecx
    cmp ecx,16
    jb .load
.expand:
    mov eax,[schedule+rcx*4-60]
    mov edx,eax
    mov esi,eax
    ror eax,7
    ror edx,18
    shr esi,3
    xor eax,edx
    xor eax,esi
    mov edx,[schedule+rcx*4-8]
    mov esi,edx
    mov edi,edx
    ror edx,17
    ror esi,19
    shr edi,10
    xor edx,esi
    xor edx,edi
    add eax,edx
    add eax,[schedule+rcx*4-64]
    add eax,[schedule+rcx*4-28]
    mov [schedule+rcx*4],eax
    inc ecx
    cmp ecx,64
    jb .expand
    mov r8d,[state]
    mov r9d,[state+4]
    mov r10d,[state+8]
    mov r11d,[state+12]
    mov r12d,[state+16]
    mov r13d,[state+20]
    mov r14d,[state+24]
    mov r15d,[state+28]
    xor ebx,ebx
.round:
    mov eax,r12d
    mov edx,eax
    mov ecx,eax
    ror eax,6
    ror edx,11
    ror ecx,25
    xor eax,edx
    xor eax,ecx
    mov edi,r13d
    xor edi,r14d
    and edi,r12d
    xor edi,r14d
    add eax,edi
    add eax,r15d
    add eax,[rounds+rbx*4]
    add eax,[schedule+rbx*4] ; T1
    mov edx,r8d
    mov ecx,edx
    mov esi,edx
    ror edx,2
    ror ecx,13
    ror esi,22
    xor edx,ecx
    xor edx,esi
    mov esi,r8d
    xor esi,r9d
    and esi,r10d
    mov edi,r8d
    and edi,r9d
    xor esi,edi
    add edx,esi ; T2
    mov r15d,r14d
    mov r14d,r13d
    mov r13d,r12d
    lea r12d,[r11d+eax]
    mov r11d,r10d
    mov r10d,r9d
    mov r9d,r8d
    lea r8d,[eax+edx]
    inc ebx
    cmp ebx,64
    jb .round
    add [state],r8d
    add [state+4],r9d
    add [state+8],r10d
    add [state+12],r11d
    add [state+16],r12d
    add [state+20],r13d
    add [state+24],r14d
    add [state+28],r15d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
