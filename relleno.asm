; relleno.asm -- animacion de relleno del pozo al perder la partida
;
; Al llegar a fin_partida (juego.asm) el pozo se llena de bloques de abajo
; arriba antes de cortar a la pantalla de fin de partida, en vez del corte seco
; de antes.
;
; TIEMPO. Aqui ya no rige el presupuesto de frame del bucle de juego
; (interrupts-and-timing seccion 2): el bucle ha TERMINADO -- fin_partida es lo
; ultimo que se ejecuta de la partida -- asi que no hay entrada que leer, ni
; gravedad que contar, ni pieza viva que repintar. Lo que si sigue rigiendo es
; el desgarro: escribir en el fichero de atributos mientras la ULA esta
; leyendo la zona visible se ve. Por eso cada fila se pinta JUSTO detras de un
; HALT, en el borde superior, igual que el borrado y el repintado del bucle:
; 18 escrituras de atributo (~400 T) caben de sobra en la ventana de ~14.000 T.
;
; Y sigue rigiendo el estado de interrupciones: HALT solo vuelve si estan
; habilitadas. Lo estan -- main.asm:7-10 las deja activas con IY = $5C3A y
; ninguna de las parejas di/ei del arbol (piezas.asm, clear.asm, test_col.asm,
; tableroJuego.asm) vuelve sin reactivarlas. Esta rutina no toca IY, asi que no
; necesita pareja propia.
;
; Por eso la animacion es frame a frame y no una sola pasada rapida: una pasada
; unica no seria mas segura -- solo mas rapida y peor sincronizada -- y contar
; frames con HALT es lo que ya hace el juego. Lo que NO se hace en ningun caso
; es una espera por bucle vacio: su velocidad depende del emulador
; (interrupts-and-timing seccion 4).
;
; No toca ni PUNTOS, ni LINEAS, ni NIVEL, ni MEJOR: solo escribe en el fichero
; de atributos, entre $5800 y $5AFF. La captura del record (ActualizarMejor)
; ocurre despues, ya dentro de Pantalla_Final, y lee un PUNTOS intacto.

RELL_FILA_BAJA   EQU 21     ; ultima fila del interior del pozo (la 22 es el suelo)
RELL_COL_IZQ     EQU 7      ; primera columna del interior
RELL_ANCHO       EQU 18     ; columnas 7-24
RELL_FRAMES_FILA EQU 3      ; frames por fila: 22 filas x 3 = 66 frames, ~1,3 s
RELL_PAUSA       EQU 25     ; ~0,5 s con el pozo lleno antes de cambiar de
                            ;  pantalla, para que se vea el resultado
                            ; total ~91 frames, ~1,8 s

; relleno_pozo -- llena el interior del pozo de abajo arriba.
;   Sin entrada ni salida. Preserva AF, BC, DE, HL, IX, IY.
relleno_pozo:
    push af : push bc : push de : push hl
    ld b, RELL_FILA_BAJA
    ld c, RELL_COL_IZQ       ; CRtoATTR toma (B,C) y preserva BC
    ld d, 1                  ; D = color en curso, 1..7
rp_fila:
    ld e, RELL_FRAMES_FILA
rp_esperar:
    HALT                     ; dormimos hasta el tick de 50 Hz
    dec e
    jr nz, rp_esperar

    call CRtoATTR            ; HL = atributo de (B,7), ya en el borde superior
    ld a, d
    add a, a : add a, a : add a, a   ; color*8 = PAPEL, tinta 0: la misma
                                     ;  codificacion que las piezas (piezas.asm)
    ld e, RELL_ANCHO
rp_celda:
    ld (hl), a
    inc hl
    dec e
    jr nz, rp_celda

    inc d                    ; siguiente color de la paleta de las piezas
    ld a, d
    cp 8
    jr c, rp_fila_hecha
    ld d, 1                  ; 1..7: los siete que ya usan los tetrominos
rp_fila_hecha:
    ld a, b
    or a
    jr z, rp_pausa           ; acabamos de pintar la fila 0: el pozo esta lleno
    dec b                    ; subimos una fila
    jr rp_fila

rp_pausa:
    ld b, RELL_PAUSA
rp_pausa_bucle:
    HALT
    djnz rp_pausa_bucle
    pop hl : pop de : pop bc : pop af
    ret
