; Programa para borrar un tetromino de la pantalla

borrar_tetromino:
    push af
    push iy
    push hl
    push de
    push bc
    di                    ; IY va a apuntar al patron; la ROM ($0038) exige IY=$5C3A

    call CalcularAtributo
    ld b, (ix)            ; Guardar filas en B
    ld c, (ix+1)          ; Guardar columnas en C
    ld iy, ix
    inc iy
    inc iy                ; Ajustar IY a la dirección del patrón de bits del tetromino
    
loop_filas:
    ld c, (ix+1)          ; Restaurar columnas en C para la nueva fila
loop_columnas:
    ld a, (iy)            ; Cargar el byte del patrón del tetromino
    inc iy
    or a                  ; Verificar si el byte es cero
    jr z, siguiente_columna ; Si es cero, saltar a la siguiente columna

    ld (hl), 0            ; Borrar el byte en pantalla

siguiente_columna:
    inc hl                ; Mover a la siguiente posición en memoria de video
    dec c                 ; Decrementar el contador de columnas
    jr nz, loop_columnas  ; Repetir hasta que C sea cero

    ld a, 32
    sub (ix+1)            ; Calcular el offset para la siguiente fila
    ld d, 0
    ld e, a
    add hl, de            ; Mover a la siguiente fila en memoria de video
    djnz loop_filas       ; Repetir para todas las filas

    pop bc
    pop de
    pop hl
    pop iy
    ei                    ; IY ya vale lo que tenia el llamante: seguro reanudar
    pop af

    ret
