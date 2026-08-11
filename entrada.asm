; entrada.asm -- lectura de teclado no bloqueante y limite lateral del pozo
;
; Sustituye a las dos esperas de "soltar tecla" (giro.asm, movimiento.asm), que
; congelaban gravedad y dibujado mientras una tecla estuviera pulsada.

COL_IZQ_POZO EQU 7    ; primera columna interior del pozo
COL_DER_POZO EQU 24   ; ultima columna interior del pozo

; leer_teclas -- lectura no bloqueante con deteccion de flanco.
;   Llamar UNA sola vez por pasada del bucle.
;   Salida: A = mascara de las teclas que han pasado de SUELTA a PULSADA desde
;           la llamada anterior:
;             bit0 = K (derecha)   bit1 = J (izquierda)
;             bit2 = Q (giro izq)  bit3 = W (giro drcha)
;           A = 0 si no hay ninguna nueva.
;   Preserva BC, DE, HL, IX, IY. Destruye AF.
leer_teclas:
    push bc : push de : push hl
    ld bc, $BFFE : in a,(c) ; media fila ENTER,L,K,J,H. ACTIVO A NIVEL BAJO:
    cpl                     ;  una tecla pulsada lee 0, asi que invertimos.
    rrca : rrca             ;  K esta en el bit2 y J en el bit3: los bajamos.
    and %00000011           ;  bit0 = K, bit1 = J (descarta bits 5-7, que no
    ld e, a                 ;  son teclado y tras el cpl valen basura)
    ld bc, $FBFE : in a,(c) ; media fila Q,W,E,R,T: Q en bit0, W en bit1
    cpl
    rlca : rlca             ;  los subimos a los bits 2 y 3
    and %00001100           ;  bit2 = Q, bit3 = W
    or e : ld e, a          ; E = las cuatro teclas, 1 = pulsada AHORA
    ld hl, teclas_ant       ; un byte: la misma mascara de la llamada anterior
    ld a,(hl) : ld (hl), e  ; leemos la vieja y guardamos la nueva
    cpl : and e             ; suelta antes Y pulsada ahora = pulsacion NUEVA
    pop hl : pop de : pop bc
    ret

; en_rango -- ¿cabe la pieza IX entera en la columna C?
;   comprobar no puede responder a esto: solo ve el borde porque su byte de
;   atributo es distinto de cero, asi que una candidata que se haya SALTADO el
;   borde lee celdas vacias fuera del pozo y la aceptaria.
;   Entrada: C = columna candidata, IX = registro de la pieza; (ix+1) = ancho.
;   Salida : A = 0 cabe, A = 1 se sale.
;   Preserva BC, DE, HL, IX, IY. Destruye AF.
en_rango:
    ld a, c
    cp COL_IZQ_POZO
    jr c, er_fuera          ; C < 7 -> a la izquierda de la pared izquierda
    add a,(ix+1)            ; A = C + ancho
    jr c, er_fuera          ; desbordo los 8 bits: C estaba lejisimos
    cp COL_DER_POZO + 2     ; la ultima celda es C+ancho-1 y debe ser <= 24,
    jr nc, er_fuera         ;  o sea C+ancho <= 25, o sea C+ancho < 26
    xor a                   ; A = 0: todas las celdas caen entre 7 y 24
    ret
er_fuera:
    ld a, 1
    ret
