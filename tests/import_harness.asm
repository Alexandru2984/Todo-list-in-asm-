; Development harness: execute the actual import/apply/export modules against
; the disposable cwd supplied by the Python test runner, without an HTTP layer.
%include "src/defs.inc"
%include "src/import.inc"
DEFAULT ABS
extern init_storage, load_todos, current_uid, import_json, import_csv
extern import_apply, export_json

global _start
section .bss
    input resb IMPORT_MAX+9
    output resb RESPONSE_MAX
    kind resq 1
    mode resq 1
section .text
_start:
    cmp qword [rsp],3
    jne failed
    mov rax,[rsp+16]
    movzx eax,byte [rax]
    mov [kind],rax
    mov rax,[rsp+24]
    movzx eax,byte [rax]
    mov [mode],rax
    mov rdi,current_uid
    mov ecx,32
    mov al,'a'
    rep stosb
    mov byte [rdi],0
    call init_storage
    test rax,rax
    js failed
    call load_todos
    test rax,rax
    js failed
    xor r13d,r13d
.read:
    mov eax,SYS_READ
    xor edi,edi
    lea rsi,[input+r13]
    mov edx,IMPORT_MAX+1
    sub rdx,r13
    syscall
    cmp rax,-4
    je .read
    test rax,rax
    js failed
    jz .parse
    add r13,rax
    cmp r13,IMPORT_MAX
    ja failed
    jmp .read
.parse:
    mov rcx,r13
    mov rdi,input
.nul_check:
    test rcx,rcx
    jz .terminated
    cmp byte [rdi],0
    je failed
    inc rdi
    dec rcx
    jmp .nul_check
.terminated:
    mov byte [input+r13],0
    mov rdi,input
    cmp qword [kind],'c'
    je .csv
    call import_json
    jmp .apply
.csv:
    call import_csv
.apply:
    test rax,rax
    js failed
    mov edi,1
    cmp qword [mode],'m'
    jne .transaction
    xor edi,edi
.transaction:
    call import_apply
    test rax,rax
    js failed
    mov rdi,output
    call export_json
    mov rdx,rax
    mov rsi,output
    mov eax,SYS_WRITE
    mov edi,STDOUT
    syscall
    mov eax,SYS_EXIT
    xor edi,edi
    syscall
failed:
    mov eax,SYS_EXIT
    mov edi,1
    syscall
