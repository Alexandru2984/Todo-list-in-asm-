; System call numbers
%define SYS_READ    0
%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_STAT    4
%define SYS_LSEEK   8
%define SYS_MMAP    9
%define SYS_MUNMAP  11
%define SYS_SOCKET  41
%define SYS_ACCEPT  43
%define SYS_BIND    49
%define SYS_LISTEN  50
%define SYS_FORK    57
%define SYS_EXIT    60
%define SYS_TIME    201
%define SYS_MKDIR   83

; File operations
%define O_RDONLY    0
%define O_WRONLY    1
%define O_RDWR      2
%define O_CREAT     64
%define O_APPEND    1024
%define O_TRUNC     512

; Socket constants
%define AF_INET     2
%define SOCK_STREAM 1
%define IPPROTO_TCP 6

; Standard FDs
%define STDIN       0
%define STDOUT      1
%define STDERR      2

; Macros
%macro syscall1 2
    mov rax, %1
    mov rdi, %2
    syscall
%endmacro

%macro syscall2 3
    mov rax, %1
    mov rdi, %2
    mov rsi, %3
    syscall
%endmacro

%macro syscall3 4
    mov rax, %1
    mov rdi, %2
    mov rsi, %3
    mov rdx, %4
    syscall
%endmacro
