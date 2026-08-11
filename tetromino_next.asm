;Programa para seleccionar y posicionar la proxima pieza

; La version anterior elegia un ESTADO DE GIRO al azar entre los 19 registros,
; no una pieza: las piezas aparecian giradas al azar y las formas con 4 estados
; (L, J, T) salian el 75% de las veces. Ademas usaba "ld a,r" como fuente de
; azar (el contador de refresco, que avanza de forma casi fija por un camino de
; instrucciones fijo) y plegaba 19..31 sobre 0..12, con lo que los indices 0-12
; salian el doble que los 13-18.
;
; Ahora se elige una FORMA de una tabla de 7 estados de aparicion, todos
; verticales/canonicos, con un LFSR de 8 bits.

; sembrar_azar -- toma una semilla del contador de refresco. Se llama una vez
;   por partida, justo despues de que el jugador pulse S, asi que el numero de
;   vueltas de la espera de teclado la hace realmente variable.
;   Destruye AF.
sembrar_azar:
    ld a, r                 ; contador de refresco: 0..127
    or a
    jr nz, sembrar_ok
    ld a, $A5               ; un LFSR que valga cero se queda en cero para siempre
sembrar_ok:
    ld (semilla), a
    ret

; nueva_pieza -- sortea una forma y devuelve su registro de aparicion.
;   Salida: DE = direccion del registro. Destruye AF y DE. Preserva BC, HL, IX, IY.
nueva_pieza:
    push hl
np_tirar:
    ld a, (semilla)         ; LFSR de Galois de 8 bits, periodo 255, nunca da 0
    srl a                   ; desplaza a la derecha, el bit bajo va al acarreo
    jr nc, np_sin_tap
    xor $B4                 ; polinomio de realimentacion
np_sin_tap:
    ld (semilla), a
    and 7
    cp 7
    jr z, np_tirar          ; descartamos el 7 -> uniforme 0..6. El reintento
                            ;  queda por DEBAJO del push: no hay fuga de pila.
    add a, a                ; *2: cada entrada de la tabla son 2 bytes
    ld hl, spawn_table
    ld d, 0 : ld e, a
    add hl, de
    ld e, (hl) : inc hl : ld d, (hl)
    pop hl
    ret

; iniciar_secuencia -- semilla y primera pieza anunciada. Una vez por partida,
;   antes del primer seleccionar_pieza. Destruye AF.
iniciar_secuencia:
    call sembrar_azar
    push de
    call nueva_pieza
    ld (siguiente_pieza), de
    pop de
    ret

; seleccionar_pieza -- pone en juego la pieza ya anunciada y sortea la
;   siguiente, de modo que el jugador siempre ve una por adelantado.
;   Salida: IX = registro de aparicion, B = 0 (fila), C = 15 (columna).
;   Destruye AF, BC, DE, IX. Preserva HL e IY.
;   C = 15 es la UNICA definicion de la columna de aparicion; (Medio) se deriva
;   de ella en juego.asm.
seleccionar_pieza:
    push hl                 ; la version anterior preservaba HL: lo mantenemos
    ld hl, (siguiente_pieza)
    push hl                 ; la anunciada pasa a jugarse
    call nueva_pieza        ; DE = la proxima a anunciar
    ld (siguiente_pieza), de
    pop de                  ; DE = la que toca jugar ahora
    ld ix, de               ; instruccion falsa de sjasmplus -> LD IXH,D : LD IXL,E
    pop hl
    ld b, 0                 ; fila de aparicion
    ld c, 15                ; columna de aparicion
    ret

; ---------------------------------------------------------------------------
; Vista previa de la proxima pieza
;
; Se dibuja FUERA del pozo a proposito: "ocupado" es "byte de atributo distinto
; de cero", asi que cualquier cosa pintada en las columnas 7-24 se convertiria
; en geometria solida. en_rango mantiene la pieza en juego dentro de esas
; columnas, asi que el recuadro no puede tocarse nunca.
PREV_FILA EQU 10        ; esquina superior izquierda del recuadro
PREV_COL  EQU 27        ; columnas 27-30, filas 10-13: caja de 4x4

; pintar_siguiente -- borra el recuadro y dibuja en el la pieza anunciada.
;   Preserva AF, BC, DE, HL, IX, IY.
pintar_siguiente:
    push af : push bc : push de : push hl : push ix
    ld b, PREV_FILA
    ld d, 4                 ; 4 filas que limpiar
ps_fila:
    ld c, PREV_COL
    call CRtoATTR           ; HL = direccion del atributo; PRESERVA BC
    ld (hl), 0 : inc hl     ; las 4 celdas de la fila, a cero (negro), igual
    ld (hl), 0 : inc hl     ;  que el interior del pozo
    ld (hl), 0 : inc hl
    ld (hl), 0
    inc b
    dec d
    jr nz, ps_fila

    ld ix, (siguiente_pieza)
    ld b, PREV_FILA
    ld c, PREV_COL
    call pintar_tetromino
    pop ix : pop hl : pop de : pop bc : pop af
    ret
