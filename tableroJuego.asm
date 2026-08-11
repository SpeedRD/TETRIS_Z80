; Programa para pintar el área de juego del Tetris

; Rutina para dibujar el tablero de juego
dibujar_tablero:
    call CLEARSCR   ; Limpiar toda la pantalla

    ; Dibujar el borde izquierdo
    ld hl, $5800 + 0 * 32 + 6 ; Dirección de memoria de la pantalla para el borde izquierdo
    ld de, $0020              ; Posición vertical (Y)
    ld a, 6 * 8 + 7            ; Color del borde
    ld b, 22                  ; Número de filas del borde izquierdo

borde_izquierdo:
    ld (hl), a               ; Escribir el color en la pantalla
    add hl, de               ; Mover la posición a la siguiente fila
    djnz borde_izquierdo     ; Decrementar B y repetir hasta que B sea cero

    ; Dibujar el borde derecho
    ld hl, $5800 + 0 * 32 + 25 ; Dirección de memoria de la pantalla para el borde derecho
    ld de, $0020               ; Posición vertical (Y)
    ld a, 6 * 8 + 7            ; Color del borde
    ld b, 22                   ; Número de filas del borde derecho

borde_derecho:
    ld (hl), a               ; Escribir el color en la pantalla
    add hl, de               ; Mover la posición a la siguiente fila
    djnz borde_derecho       ; Decrementar B y repetir hasta que B sea cero

    ; Dibujar la base
    ld hl, $5800 + 22 * 32 + 6 ; Dirección de memoria de la pantalla para la base
    ld a, 6 * 8 + 7            ; Color de la base
    ld b, 20                   ; Número de columnas de la base

base:
    ld (hl), a               ; Escribir el color en la pantalla
    inc hl                   ; Mover la posición a la siguiente columna
    djnz base                ; Decrementar B y repetir hasta que B sea cero

    di                       ; Tetris_3D deja IY en $9FDF y no lo restaura
    call Tetris_3D           ; Aplicar el efecto 3D a los bloques
    ld iy, $5C3A             ; devolvemos IY a la base de variables del sistema
    ei


    ret