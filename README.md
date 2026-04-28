# ASM TODO Server

A lightweight, high-performance TODO list application written entirely in **x86_64 Assembly** for Linux. It features a built-in HTTP server, a modern dark-mode web interface, and file-based persistence.

## Features

- **Built from Scratch:** No external libraries or high-level languages. Pure NASM and Linux system calls.
- **HTTP Server:** Implements a basic TCP/HTTP stack for handling web requests.
- **Modern UI:** Responsive dark-mode interface served directly from assembly.
- **CRUD Operations:**
    - View all tasks.
    - Add new tasks.
    - Mark tasks as completed.
    - Delete tasks.
- **Persistence:** Automatically saves and loads tasks from `data/todos.txt`.
- **Port Discovery:** Starts at port `8081` and automatically finds the next available port if it's in use.

## Architecture

- `src/main.asm`: Entry point, socket initialization, and request loop.
- `src/router.asm`: HTTP routing, HTML generation, and request parsing.
- `src/storage.asm`: Task management and file I/O logic.
- `src/utils.asm`: String manipulation and conversion utilities (`itoa`, `atoi`, `strlen`, etc.).
- `src/defs.inc`: System call numbers and common constants.

## Requirements

- **OS:** Linux (x86_64)
- **Assembler:** [NASM](https://nasm.us/)
- **Linker:** `ld` (GNU Binutils)
- **Build Tool:** `make`

## Getting Started

### 1. Build the project
```bash
make
```

### 2. Run the server
```bash
make run
```
The server will start and display the port it is listening on (default: `8081`).

### 3. Access the Web UI
Open your browser and navigate to:
```
http://localhost:8081
```

## Development

- **Build only:** `make all`
- **Clean build artifacts:** `make clean`
- **Project Structure:**
    - `bin/`: Compiled executable.
    - `data/`: Persistent storage.
    - `src/`: Assembly source files.

## License
MIT
