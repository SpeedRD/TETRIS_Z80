; Programa para definir y dibujar cada pieza o tetromino

; Datos de los tetrominos: filas, columnas, patrón de bits, giros
;Tetromino O
T_0: DB 2, 2, 6*8, 6*8, 6*8, 6*8, 0, 0: DW T_0, T_0
;Tetromino L
T_L1: DB 3, 2, 4*8, 0, 4*8, 0, 4*8, 4*8: DW T_L2, T_L3
T_L2: DB 2, 3, 0, 0, 4*8, 4*8, 4*8, 4*8: DW T_L4, T_L1
T_L3: DB 2, 3, 4*8, 4*8, 4*8, 4*8, 0, 0: DW T_L1, T_L4
T_L4: DB 3, 2, 4*8, 4*8, 0, 4*8, 0, 4*8: DW T_L3, T_L2
;Tetromino J
T_J1: DB 3, 2, 0, 2*8, 0, 2*8, 2*8, 2*8: DW T_J2, T_J3
T_J2: DB 2, 3, 2*8, 2*8, 2*8, 0, 0, 2*8: DW T_J4, T_J1
T_J3: DB 2, 3, 2*8, 0, 0, 2*8, 2*8, 2*8: DW T_J1, T_J4
T_J4: DB 3, 2, 2*8, 2*8, 2*8, 0, 2*8, 0: DW T_J3, T_J2
;Tetromino T
T_T1: DB 2, 3, 5*8, 5*8, 5*8, 0, 5*8, 0 : DW T_T2, T_T3
T_T2: DB 3, 2, 5*8, 0, 5*8, 5*8, 5*8, 0 : DW T_T4, T_T1
T_T3: DB 3, 2, 0, 5*8, 5*8, 5*8, 0, 5*8 : DW T_T1, T_T4
T_T4: DB 2, 3, 0, 5*8, 0, 5*8, 5*8, 5*8 : DW T_T3, T_T2
;Tetromino I -- era 6*8, el mismo amarillo que la O. Ahora 1*8 (azul).
T_I1: DB 4, 1, 1*8, 1*8, 1*8, 1*8, 0, 0 : DW T_I2, T_I2
T_I2: DB 1, 4, 1*8, 1*8, 1*8, 1*8, 0, 0 : DW T_I1, T_I1
;Tetromino Z
T_Z1: DB 2, 3, 7*8, 7*8, 0, 0, 7*8, 7*8 : DW T_Z2, T_Z2
T_Z2: DB 3, 2, 0, 7*8, 7*8, 7*8, 7*8, 0 : DW T_Z1, T_Z1
;Tetromino S -- era 7*8, el mismo blanco que la Z. Ahora 3*8 (magenta).
T_S1: DB 2, 3, 0, 3*8, 3*8, 3*8, 3*8, 0 : DW T_S2, T_S2
T_S2: DB 3, 2, 3*8, 0, 3*8, 3*8, 0, 3*8 : DW T_S1, T_S1

; Estados de aparicion, uno por FORMA (no por giro). Son datos de SOLO LECTURA,
; asi que no les afecta el problema de adyacencia que tenia "Medio": al elegir
; de aqui, nada vuelve a indexar aritmeticamente la tabla de registros, con lo
; que desaparece el riesgo de que un indice se pase del ultimo registro.
spawn_table: DW T_0, T_L1, T_J1, T_T1, T_I1, T_Z1, T_S1

; "Medio" (la columna en curso) vivia aqui, incrustado en la imagen de codigo
; justo detras del ultimo registro de pieza y sin ningun margen. Ahora esta en
; variables.asm, con el resto del estado mutable.

; Rutina para pintar el tetromino en pantalla
pintar_tetromino:
    push af
    push iy
    push hl
    push de
    push bc
    di                     ; IY va a apuntar al patron; la ROM ($0038) exige IY=$5C3A

    call CalcularAtributo  ; Calcular la dirección en HL
    ld b, (ix)             ; Obtener filas en B
    ld c, (ix+1)           ; Obtener columnas en C 
    ld iy, ix
    inc iy : inc iy        ; Ajustar IY a la dirección del patrón de bits del tetromino

pintar_loop:
    ld a, (iy)
    inc iy
    cp 0                   ; Verificar si el byte es cero
    jr z, siguiente_byte

    ld (hl), a             ; Pintar el byte en pantalla
siguiente_byte:
    inc hl                 ; Mover a la siguiente posición en memoria de video
    dec c                  ; Decrementar el contador de columnas
    jr nz, pintar_loop     ; Repetir hasta que C sea cero

    ld c, (ix+1)           ; Resetear C para la siguiente fila
    ld a, 32
    sub c
    ld d, 0
    ld e, a
    add hl, de             ; Mover a la siguiente fila en memoria de video
    djnz pintar_loop       ; Repetir para todas las filas

    pop bc
    pop de
    pop hl
    pop iy
    ei                     ; IY ya vale lo que tenia el llamante: seguro reanudar
    pop af

    ret
