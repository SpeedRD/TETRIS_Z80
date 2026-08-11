; lineas.asm -- deteccion y borrado de lineas completas
;
; El fichero de atributos ES el tablero: una celda esta ocupada si su byte de
; atributo es distinto de cero. El interior del pozo son las columnas 7-24
; (18 celdas) y las filas 0-21; la fila 22 es el suelo y las columnas 6 y 25
; son las paredes. NUNCA se escribe en el borde: nadie lo vuelve a pintar
; despues de dibujar_tablero, y un solo byte suelto abre un agujero permanente.

COL_IZQ    EQU 7        ; primera columna interior
ANCHO_POZO EQU 18       ; ancho interior: columnas 7..24 inclusive
FILA_BAJA  EQU 21       ; fila interior mas baja (la 22 es el suelo)

; limpiar_lineas -- elimina todas las filas completas y compacta el tablero.
;   Entrada: nada.  Salida: A = numero de filas eliminadas (0..4 en la practica)
;   Preserva BC, DE, HL, IX, IY. Destruye AF.
limpiar_lineas:
    push bc : push de : push hl : push ix  ; BC = fila/columna de la pieza e
    ld c, 0                  ; C = cuenta de filas eliminadas
    ld b, FILA_BAJA          ; B = fila a examinar; empezamos abajo y subimos
ll_probar:
    call fila_llena : or a   ; A = 1 si la fila B esta completa
    jr z, ll_arriba          ; no lo esta -> subimos una fila
    inc c
    call bajar_filas         ; bajamos sobre ella todo lo que tenia encima
    jr ll_probar             ; VOLVEMOS A PROBAR LA MISMA FILA B: tras el
                             ;  desplazamiento en el indice B hay una fila
                             ;  DISTINTA. Poner "dec b" aqui es el fallo
                             ;  clasico: un doble hueco borraria una sola fila.
ll_arriba:
    ld a, b : or a
    jr z, ll_fin             ; la fila 0 era la ultima por probar -> hemos acabado
    dec b : jr ll_probar
ll_fin:
    ld a, c                  ; devolvemos la cuenta; la consume puntuacion.asm
    pop ix : pop hl : pop de : pop bc   ; espejo exacto de los push
    ret

; fila_llena -- Entrada: B = fila 0..21.  Salida: A = 1 completa, 0 no.
;   Preserva BC, DE, HL. Destruye AF.
fila_llena:
    push bc : push de : push hl
    ld c, COL_IZQ
    call CRtoATTR            ; HL = $5800 + B*32 + 7. A diferencia de
                             ;  CalcularAtributo, esta PRESERVA BC, que es lo
                             ;  que mantiene vivo el contador de filas.
    ld e, ANCHO_POZO         ; exactamente 18 celdas: nunca 32, o los bytes de
fl_celda:                    ;  la pared (siempre 55) darian toda fila por llena
    ld a, (hl) : or a
    jr z, fl_hueco           ; con una celda vacia basta: la fila no esta completa
    inc hl : dec e
    jr nz, fl_celda          ; dec e fija los flags; inc hl no los toca
    ld a, 1 : jr fl_fin
fl_hueco:
    ld a, 0
fl_fin:
    pop hl : pop de : pop bc
    ret

; bajar_filas -- Entrada: B = la fila recien eliminada (0..21).
;   Copia una fila hacia abajo todo lo que hay encima y deja la fila 0 vacia.
;   Preserva AF, BC, DE, HL.
bajar_filas:
    push af : push bc : push de : push hl
    ld a, b : or a           ; A = numero de copias a hacer = B
    jr z, bf_fila0           ; se elimino la fila 0: no hay nada encima
    ld c, COL_IZQ
    push af                  ; CRtoATTR TERMINA EN "LD A,L" (L30.3 - printat.asm):
    call CRtoATTR            ;  destruye A. Sin este push la cuenta de copias se
    pop af                   ;  perdia y el bucle giraba (bajo de $5800+B*32+7)
                             ;  veces en vez de B: 167 en vez de 21 para la fila
                             ;  21. Las 146 vueltas de mas seguian copiando por
                             ;  debajo del fichero de atributos y ensuciaban 230
                             ;  bytes del fichero de pixeles en cada linea hecha.
                             ;  El tablero acababa bien -- bf_cero repara la fila
                             ;  0 -- asi que el fallo solo se veia como fondo
                             ;  corrupto y como un frame de 119.000 T en vez de
                             ;  38.000. Preservar AF, y no fiarlo a que CRtoATTR
                             ;  respete B, es lo que mantiene esto a salvo si
                             ;  alguien cambia la rutina de direccion.
    ex de, hl                ; DE = destino
    ld hl, -32 : add hl, de  ; HL = origen = destino - 32 = una fila mas arriba
bf_copiar:
    ld bc, ANCHO_POZO
    ldir                     ; 18 bytes (HL)->(DE); ambos avanzan 18, BC -> 0
    ld bc, -(ANCHO_POZO + 32); deshacemos los 18 y subimos una fila mas
    add hl, bc               ; HL -= 50
    ex de, hl : add hl, bc : ex de, hl   ; DE -= 50 (el Z80 no tiene "add de,bc")
    dec a                    ; add hl,bc no toca Z; dec a si
    jr nz, bf_copiar
bf_fila0:
    ld b, 0 : ld c, COL_IZQ  ; vaciamos las 18 celdas de la fila 0, o la fila
    call CRtoATTR            ;  de arriba se duplicaria hacia abajo para siempre
    ld b, ANCHO_POZO
bf_cero:
    ld (hl), 0 : inc hl
    djnz bf_cero
    pop hl : pop de : pop bc : pop af
    ret
