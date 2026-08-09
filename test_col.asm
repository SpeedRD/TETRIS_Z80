;Programa para validar la colision 

comprobar:
    push ix
    push iy
    push hl
    push de
    push bc

    CALL CalcularAtributo
    ; Configurar las filas y columnas del tetromino
    ld b, (ix)           ; Filas en B
    ld c, (ix+1)         ; Columnas en C
    ld iy, ix
    inc iy
    inc iy               ; Ajustar IY a la dirección del patrón de bits del tetromino
    
validar_fila:
    ld a, (iy)
    inc iy
    or a
    jr z, siguiente_cuadro

    ld a, (hl)
    or a
    jr nz, colision_detectada

siguiente_cuadro:
    inc hl
    dec c
    jr nz, validar_fila

    ; Avanzar a la siguiente fila del tetromino
    ld c, (ix+1)
    ld a, 32
    sub c
    ld d, 0
    ld e, a
    add hl, de
    djnz validar_fila

    ld a, 0              ; No hay colisión
    jr fin_comprobacion

colision_detectada:
    ld a, 1              ; Colisión detectada

fin_comprobacion:
    pop bc
    pop de
    pop hl
    pop iy
    pop ix

    ret