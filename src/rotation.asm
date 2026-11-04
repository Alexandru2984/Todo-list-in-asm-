%include "src/defs.inc"
DEFAULT ABS
extern strcmp, strlen, copy_string, auth_candidate
extern current_uid, res_buf, send_private_html

global rotation_form, rotation_target, rotation_saved, rotation_flags
 global rotation_reset, rotation_field, rotation_scope
section .data
    key_name db 'new_key',0
    saved_name db 'saved',0
    head db '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>Rotate recovery key — ASM TODO</title><link rel="stylesheet" href="/app.css"><script src="/app.js" defer></script></head><body data-page="rotation"><main class="native-import native-rotation"><a href="/app#workspace-tools">Back to workspace</a><h1>Replace your recovery key</h1>',0
    conflict db '<p class="notice" role="alert">The workspace changed. Your old key is still in use for this request. Review the latest tasks before confirming this same saved candidate again.</p>',0
    uncertain db '<p class="notice" role="alert">Rotation was not confirmed. Keep both keys. Try this same confirmation again: if your saved new key is already active, you will be signed in without another change. You can also restore access from the home page with the new key.</p>',0
    form db '<p>Save the new key first, then confirm. Rotation keeps your tasks, trash, history and last task undo. Every older key for this workspace stops working after the change.</p><form action="/rotate-key" method="post"><label for="rotation-key">New recovery key</label><textarea id="rotation-key" name="new_key" readonly rows="3" spellcheck="false" autocomplete="off">',0
    close db '</textarea><p class="query-hint">This candidate is inactive until you confirm. Keep the saved file private. Anyone holding the active key has full workspace access.</p><button class="secondary-button" type="submit" formaction="/rotation-key" formnovalidate>Save new key</button><label class="rotation-ack"><input type="checkbox" name="saved" value="1" required> <span>I saved this new key. I understand that older keys and open sessions using them will lose access.</span></label><div class="dialog-actions"><a class="secondary-button" href="/app">Cancel</a><button class="primary-button">Rotate and revoke old key</button></div></form><p>If the response is lost, restore with the new key you saved. Rotation cannot be undone. Downloads or requests already authorized before rotation cannot be recalled.</p></main></body></html>',0
section .bss
    rotation_target resb 65
    rotation_saved resq 1
    rotation_flags resq 1
section .text
rotation_reset:
    mov byte [rotation_target],0
    mov qword [rotation_saved],0
    mov qword [rotation_flags],0
    ret

; Decoded exact fields, kept separate from task properties/public recovery.
rotation_field:
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
    mov rsi,key_name
    call strcmp
    test rax,rax
    jz .target
    mov rdi,rbx
    mov rsi,saved_name
    call strcmp
    test rax,rax
    jnz .unknown
    test qword [rotation_flags],2
    jnz .bad
    cmp word [r12],'1'
    jne .bad
    or qword [rotation_flags],2
    mov qword [rotation_saved],1
    jmp .known
.target:
    test qword [rotation_flags],1
    jnz .bad
    mov rdi,r12
    call strlen
    cmp rax,64
    jne .bad
    xor ecx,ecx
.hex:
    mov al,[r12+rcx]
    cmp al,'0'
    jb .bad
    cmp al,'9'
    jbe .next
    cmp al,'a'
    jb .bad
    cmp al,'f'
    ja .bad
.next:
    inc ecx
    cmp ecx,64
    jb .hex
    or qword [rotation_flags],1
    mov rdi,rotation_target
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

rotation_scope:
    mov rdi,rotation_target
    mov rsi,current_uid
    mov ecx,32
    repe cmpsb
    jne .bad
    xor eax,eax
    ret
.bad:
    mov rax,-400
    ret

; fd/status; preserve a submitted candidate on conflicts/uncertain writes.
rotation_form:
    push rbx
    push r12
    push r13
    mov r12,rdi
    mov r13,rsi
    cmp byte [rotation_target],0
    jne .render
    mov rdi,rotation_target
    call auth_candidate
    test rax,rax
    js .done
.render:
    mov rdi,res_buf
    mov rsi,head
    call copy_string
    cmp r13,412
    jne .storage
    mov rsi,conflict
    call copy_string
    jmp .fields
.storage:
    cmp r13,507
    jne .fields
    mov rsi,uncertain
    call copy_string
.fields:
    mov rsi,form
    call copy_string
    mov rsi,rotation_target
    call copy_string ; strict lowercase hex, never arbitrary input
    mov rsi,close
    call copy_string
    mov rdx,rdi
    sub rdx,res_buf
    mov rdi,r12
    mov rsi,res_buf
    mov rcx,r13
    call send_private_html
    xor eax,eax
.done:
    pop r13
    pop r12
    pop rbx
    ret
