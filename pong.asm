; ============================================================
;  PONG - MS-DOS .COM  (NASM 16-bit, lo más simple posible)
;
;  Compilar:   nasm -f bin pong.asm -o pong.com
;  Ejecutar:   pong.com  (DOSBox, FreeDOS o MS-DOS real)
;
;  Controles:
;    W / S          -> Jugador 1 (izquierda)
;    Flecha Up/Down -> Jugador 2 (derecha)
;    ESC            -> Salir
; ============================================================

bits 16
org  0x100          ; .COM siempre empieza en 0x100

; ---------- constantes ----------
VRAM    equ 0xB800  ; segmento vídeo texto color
COLS    equ 80
ROWS    equ 25
PAD_H   equ 4
COL1    equ 2       ; columna pala izquierda
COL2    equ 77      ; columna pala derecha
WIN     equ 7       ; puntos para ganar

; atributos color
A_WALL  equ 0x0B   ; cyan
A_P1    equ 0x0A   ; verde
A_P2    equ 0x0C   ; rojo
A_BALL  equ 0x0F   ; blanco
A_SCR   equ 0x0E   ; amarillo

; ---------- entrada ----------
start:
    ; ES -> segmento VRAM
    mov  ax, VRAM
    mov  es, ax

    ; Guardar y fijar modo vídeo texto 80x25
    mov  ah, 0x0F
    int  0x10
    mov  [old_mode], al
    mov  ax, 0x0003
    int  0x10

    ; Ocultar cursor
    mov  ah, 0x01
    mov  cx, 0x2000
    int  0x10

    ; Inicializar variables
    mov  byte [p1y],  10
    mov  byte [p2y],  10
    mov  byte [bx_],  39
    mov  byte [by_],  12
    mov  byte [bvx],  1
    mov  byte [bvy],  1
    mov  byte [sc1],  0
    mov  byte [sc2],  0
    mov  byte [btmr], 0

    call draw_border
    call draw_score

; ============================================================
;  BUCLE PRINCIPAL
; ============================================================
loop:
    call read_key
    call move_ball
    call draw_all
    call wait_tick

    mov  al, [sc1]
    cmp  al, WIN
    jge  win1
    mov  al, [sc2]
    cmp  al, WIN
    jge  win2
    jmp  loop

win1: mov  si, msg1
      jmp  endgame
win2: mov  si, msg2
endgame:
    call show_msg
    mov  ah, 0x00   ; esperar tecla
    int  0x16
    jmp  restore

restore:
    mov  ah, 0x00
    mov  al, [old_mode]
    int  0x10
    mov  ah, 0x01
    mov  cx, 0x0607
    int  0x10
    mov  ax, 0x4C00
    int  0x21

; ============================================================
;  read_key  (non-blocking: INT 16h AH=1)
; ============================================================
read_key:
    mov  ah, 0x01
    int  0x16
    jz   .end          ; sin tecla
    mov  ah, 0x00
    int  0x16          ; AH=scancode

    cmp  ah, 0x01      ; ESC
    je   restore

    cmp  ah, 0x11      ; W -> p1 sube
    jne  .s
    mov  al, [p1y]
    cmp  al, 1
    jle  .end
    dec  byte [p1y]
    jmp  .end
.s: cmp  ah, 0x1F      ; S -> p1 baja
    jne  .up
    mov  al, [p1y]
    add  al, PAD_H
    cmp  al, ROWS-1
    jge  .end
    inc  byte [p1y]
    jmp  .end
.up:cmp  ah, 0x48      ; flecha arriba -> p2 sube
    jne  .dn
    mov  al, [p2y]
    cmp  al, 1
    jle  .end
    dec  byte [p2y]
    jmp  .end
.dn:cmp  ah, 0x50      ; flecha abajo -> p2 baja
    jne  .end
    mov  al, [p2y]
    add  al, PAD_H
    cmp  al, ROWS-1
    jge  .end
    inc  byte [p2y]
.end:
    ret

; ============================================================
;  move_ball
; ============================================================
move_ball:
    inc  byte [btmr]
    mov  al, [btmr]
    cmp  al, 3
    jl   .skip
    mov  byte [btmr], 0

    ; mover X
    mov  al, [bx_]
    add  al, [bvx]
    mov  [bx_], al

    ; mover Y
    mov  al, [by_]
    add  al, [bvy]
    mov  [by_], al

    ; rebote top/bottom
    mov  al, [by_]
    cmp  al, 1
    jle  .bv_top
    cmp  al, ROWS-2
    jge  .bv_bot
    jmp  .check_paddles
.bv_top:
    neg  byte [bvy]
    mov  byte [by_], 1
    jmp  .check_paddles
.bv_bot:
    neg  byte [bvy]
    mov  byte [by_], ROWS-2

.check_paddles:
    mov  al, [bx_]

    ; --- pala izquierda: si X <= COL1 ---
    cmp  al, COL1
    jg   .check_p2

    ; ¿está dentro de la pala?
    mov  bl, [p1y]
    mov  cl, [by_]
    cmp  cl, bl
    jl   .miss_p1
    mov  dl, bl
    add  dl, PAD_H-1
    cmp  cl, dl
    jg   .miss_p1
    ; rebote
    mov  byte [bvx], 1
    mov  byte [bx_], COL1+1   ; sacar pelota de dentro
    jmp  .skip

.miss_p1:
    ; punto para J2
    inc  byte [sc2]
    call draw_score
    call reset_ball
    jmp  .skip

    ; --- pala derecha: si X >= COL2 ---
.check_p2:
    cmp  al, COL2
    jl   .skip

    mov  bl, [p2y]
    mov  cl, [by_]
    cmp  cl, bl
    jl   .miss_p2
    mov  dl, bl
    add  dl, PAD_H-1
    cmp  cl, dl
    jg   .miss_p2
    ; rebote
    mov  byte [bvx], 0xFF     ; -1
    mov  byte [bx_], COL2-1
    jmp  .skip

.miss_p2:
    inc  byte [sc1]
    call draw_score
    call reset_ball

.skip:
    ret
; ============================================================
;  reset_ball
; ============================================================
reset_ball:
    mov  byte [bx_], 39
    mov  byte [by_], 12
    mov  byte [bvy], 1
    mov  byte [btmr], 0
    ; alternar dirección X limpiamente
    mov  al, [bvx]
    cmp  al, 1
    je   .neg
    mov  byte [bvx], 1
    ret
.neg:
    mov  byte [bvx], 0xFF
    ret

; ============================================================
;  draw_border  (una sola vez)
; ============================================================
draw_border:
    ; fila 0
    xor  di, di
    mov  cx, COLS
.t: mov  byte [es:di],   0xCD
    mov  byte [es:di+1], A_WALL
    add  di, 2
    loop .t
    ; fila 24
    mov  di, (ROWS-1)*COLS*2
    mov  cx, COLS
.b: mov  byte [es:di],   0xCD
    mov  byte [es:di+1], A_WALL
    add  di, 2
    loop .b
    ; laterales
    mov  bx, 1
.s: cmp  bx, ROWS-1
    jge  .sd
    mov  ax, bx
    mov  cl, 5          ; ax * 32
    shl  ax, cl
    mov  di, ax
    mov  ax, bx
    mov  cl, 3          ; ax * 8  -> total ax*160 = ax*128+ax*32
    ; En realidad fila*160: usamos mul
    mov  ax, bx
    mov  dx, 160
    mul  dx             ; AX = bx*160
    mov  di, ax
    mov  byte [es:di],   0xBA
    mov  byte [es:di+1], A_WALL
    add  di, (COLS-1)*2
    mov  byte [es:di],   0xBA
    mov  byte [es:di+1], A_WALL
    inc  bx
    jmp  .s
.sd:
    ret

; ============================================================
;  draw_all: limpia interior, dibuja palas y pelota
; ============================================================
draw_all:
    ; limpiar filas 1..23, cols 1..78
    mov  bx, 1
.cr:cmp  bx, ROWS-1
    jge  .cd
    mov  ax, bx
    mov  dx, 160
    mul  dx
    mov  di, ax
    add  di, 2
    mov  cx, COLS-2
.cc:mov  word [es:di], 0x0020
    add  di, 2
    loop .cc
    inc  bx
    jmp  .cr
.cd:
    ; pala 1
    movzx bx, byte [p1y]
    mov  cx, PAD_H
.d1:mov  ax, bx
    mov  dx, 160
    mul  dx
    mov  di, ax
    add  di, COL1*2
    mov  byte [es:di],   0xDB
    mov  byte [es:di+1], A_P1
    inc  bx
    loop .d1
    ; pala 2
    movzx bx, byte [p2y]
    mov  cx, PAD_H
.d2:mov  ax, bx
    mov  dx, 160
    mul  dx
    mov  di, ax
    add  di, COL2*2
    mov  byte [es:di],   0xDB
    mov  byte [es:di+1], A_P2
    inc  bx
    loop .d2
    ; pelota
    movzx bx, byte [by_]
    mov  ax, bx
    mov  dx, 160
    mul  dx
    mov  di, ax
    movzx ax, byte [bx_]
    shl  ax, 1
    add  di, ax
    mov  byte [es:di],   0x04   ; ♦
    mov  byte [es:di+1], A_BALL
    ret

; ============================================================
;  draw_score: fila 0, centrado
; ============================================================
draw_score:
    mov  di, 34*2       ; col 34
    mov  si, sj1
.l1:lodsb
    test al, al
    jz   .e1
    mov  [es:di], al
    mov  byte [es:di+1], A_SCR
    add  di, 2
    jmp  .l1
.e1:
    movzx ax, byte [sc1]
    add  al, '0'
    mov  [es:di], al
    mov  byte [es:di+1], A_SCR
    add  di, 2
    mov  si, ssep
.l2:lodsb
    test al, al
    jz   .e2
    mov  [es:di], al
    mov  byte [es:di+1], A_SCR
    add  di, 2
    jmp  .l2
.e2:
    mov  si, sj2
.l3:lodsb
    test al, al
    jz   .e3
    mov  [es:di], al
    mov  byte [es:di+1], A_SCR
    add  di, 2
    jmp  .l3
.e3:
    movzx ax, byte [sc2]
    add  al, '0'
    mov  [es:di], al
    mov  byte [es:di+1], A_SCR
    ret

; ============================================================
;  show_msg: imprime string [si] centrado en fila 12
; ============================================================
show_msg:
    push si
    xor  cx, cx
.ln:lodsb
    test al, al
    jz   .ld
    inc  cx
    jmp  .ln
.ld:pop  si
    mov  ax, 80
    sub  ax, cx
    shr  ax, 1
    mov  di, 12*160
    shl  ax, 1
    add  di, ax
.lm:lodsb
    test al, al
    jz   .lx
    mov  [es:di], al
    mov  byte [es:di+1], 0x4F
    add  di, 2
    jmp  .lm
.lx:ret

; ============================================================
;  wait_tick: espera 1 tick BIOS (~55ms)
; ============================================================
wait_tick:
    mov  ah, 0x00
    int  0x1A
    mov  bx, dx
.wt:mov  ah, 0x00
    int  0x1A
    cmp  dx, bx
    je   .wt
    ret

; ============================================================
;  DATOS
; ============================================================
old_mode db 3
p1y      db 10
p2y      db 10
bx_      db 39
by_      db 12
bvx      db 1
bvy      db 1
btmr     db 0
sc1      db 0
sc2      db 0

sj1  db 'J1:',0
ssep db ' vs ',0
sj2  db 'J2:',0
msg1 db '** GANA JUGADOR 1 **',0
msg2 db '** GANA JUGADOR 2 **',0