; System call numbers
%define SYS_READ    0
%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_STAT    4
%define SYS_FSTAT   5
%define SYS_FTRUNCATE 77
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
%define SYS_RENAME  82
%define SYS_FLOCK   73

; flock operations
%define LOCK_SH     1
%define LOCK_EX     2
%define LOCK_UN     8

; Signals
%define SIGPIPE     13
%define SIGCHLD     17

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

%define SYS_ALARM     37
%define SYS_FSYNC     74
%define SYS_GETRANDOM 318
%define O_NOFOLLOW    131072
%define O_DIRECTORY   65536
%define O_CLOEXEC     524288
%define O_NONBLOCK    2048
%define REQUEST_MAX   4095
%define TASK_MAX      1000
%define TITLE_MAX     110
%define QUERY_MAX     255
%define PATH_MAX      2048

; Shared planner ABI. The original ID/status/created/title prefix stays intact.
%define SLOT_MAX      1200
%define TASK_SIZE     512
%define STORAGE_MAX   2097152
%define RESPONSE_MAX  4194304
%define T_PRIORITY    128
%define T_DUE         136
%define T_COMPLETED   144
%define T_PARENT      152
%define T_REPEAT      160
%define T_PROJECT     168
%define T_TAGS        208
%define T_DELETED     280
%define T_DEPS        288
%define T_DEP_COUNT   352
%define T_STAGE       360
%define T_PREVIOUS    368
%define T_ANCHOR      376
%define T_META        400
%define T_COLOR       408
%define PROJECT_MAX   32
%define TAGS_MAX      64
%define DEP_MAX       8
