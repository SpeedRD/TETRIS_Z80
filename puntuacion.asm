; puntuacion.asm -- puntos, lineas, nivel y su marcador en pantalla
;
; Las VARIABLES (PUNTOS, LINEAS, NIVEL, PROX_NIVEL, FRAMES_POR_FILA) se
; declaran en variables.asm y SOLO alli: declararlas tambien aqui es un error
; de etiqueta duplicada. Este fichero aporta el codigo y sus tablas de solo
; lectura.
;
; El marcador se pinta en las columnas 26-31, FUERA del pozo. Es una
; restriccion de correccion, no de gusto: "ocupado" significa "byte de
; atributo distinto de cero", asi que cualquier texto dentro de las columnas
; 7-24 se convertiria en un muro invisible para comprobar.

NIVEL_MAX EQU 10

PUNTOS_POR_LINEA: DW $0100, $0300, $0500, $0800  ; BCD, indice (filas-1)*2
FRAMES_POR_NIVEL: DB 48,40,33,27,22,18,15,12,10,8,6  ; niveles 0..10, a 50 fps

; anotar_lineas -- contabiliza un borrado de lineas.
;   Entrada: A = filas eliminadas (0..4). Si es 0 no hace nada.
;   Actualiza puntos, lineas, nivel y velocidad, y refresca el marcador.
;   Preserva BC, DE, HL, IX, IY. Destruye AF.
anotar_lineas:
    or a
    ret z                        ; no se elimino ninguna fila
    push bc : push de : push hl : push ix
    push af                      ; nos guardamos la cuenta

    dec a                        ; --- puntos: indice (filas-1)*2
    add a, a
    ld e, a : ld d, 0
    ld hl, PUNTOS_POR_LINEA
    add hl, de
    ld e, (hl) : inc hl : ld d, (hl)   ; DE = premio en BCD
    call SumarPuntos

    pop af                       ; --- lineas y nivel, una vuelta por fila
    ld b, a
al_bucle:
    ld a, (LINEAS) : inc a : ld (LINEAS), a
    ld a, (PROX_NIVEL) : dec a : ld (PROX_NIVEL), a
    jr nz, al_siguiente
    ld a, 10 : ld (PROX_NIVEL), a      ; otras 10 filas hasta el proximo nivel
    ld a, (NIVEL)
    cp NIVEL_MAX
    jr nc, al_siguiente                ; ya estamos en el tope
    inc a : ld (NIVEL), a
al_siguiente:
    djnz al_bucle

    call ActualizarVelocidad
    call ImprimirMarcador
    pop ix : pop hl : pop de : pop bc
    ret

; SumarPuntos -- suma DE (BCD de 4 digitos) al marcador de 6 digitos.
;   Destruye AF y HL.
SumarPuntos:
    LD HL, PUNTOS
    LD A, (HL) : ADD A, E : DAA : LD (HL), A          ; DAA vuelve decimal la
    INC HL : LD A, (HL) : ADC A, D : DAA : LD (HL), A ;  suma binaria. LD no
    INC HL : LD A, (HL) : ADC A, 0 : DAA : LD (HL), A ;  toca flags: el
    RET                                               ;  acarreo sobrevive.

; ActualizarVelocidad -- copia la velocidad del nivel actual a la gravedad.
;   Destruye AF, DE y HL.
ActualizarVelocidad:
    LD A, (NIVEL)
    CP NIVEL_MAX : JR C, NivelOK
    LD A, NIVEL_MAX             ; tope: nunca indexar mas alla de la tabla
NivelOK:
    LD E, A : LD D, 0
    LD HL, FRAMES_POR_NIVEL : ADD HL, DE
    LD A, (HL) : LD (FRAMES_POR_FILA), A   ; suelo de 6 frames (~120 ms):
    RET                                    ;  una tabla no puede dar 0

; reiniciar_marcador -- pone a cero TODO el estado de una partida y pinta los
;   rotulos y los valores. Es el unico sitio donde se reinicia estado por
;   partida: hay uno solo, asi que no se puede olvidar (memory-map 6a).
;   Se llama al empezar una partida, cuando aun no hay ninguna pieza en juego.
;   NO toca MEJOR: la mejor puntuacion es de la SESION y sobrevive a
;   inicializar; la escribe solo ActualizarMejor. Zapearla aqui borraria
;   justo lo que existe para conservar.
;   Preserva AF, BC, DE, HL, IX, IY.
reiniciar_marcador:
    push af : push bc : push de : push hl : push ix
    xor a
    ld (PUNTOS), a : ld (PUNTOS+1), a : ld (PUNTOS+2), a
    ld (LINEAS), a
    ld (NIVEL), a
    ld a, 10 : ld (PROX_NIVEL), a
    call ActualizarVelocidad           ; FRAMES_POR_FILA = tabla[0] = 48
    ld a, (FRAMES_POR_FILA)
    ld (contador_frames), a
    call musica_reiniciar              ; la melodia vuelve a empezar por el
                                       ;  principio. Un fin de partida no borra
                                       ;  la RAM -- inicializar solo rehace SP --
                                       ;  asi que sin esta llamada la segunda
                                       ;  partida arrancaba a mitad de frase
                                       ;  (musica.asm; NO vale mus_cargar)
    call ImprimirEtiquetas
    call ImprimirMarcador
    pop ix : pop hl : pop de : pop bc : pop af
    ret

; ImprimirEtiquetas -- rotulos fijos, una sola vez por partida.
ImprimirEtiquetas:
    push ix : push bc                  ; IX = pieza, B/C = posicion de la pieza
    ld a, 6 : ld b, 0 : ld c, 26 : ld ix, MsgPuntos : call PRINTAT
    ld a, 6 : ld b, 3 : ld c, 26 : ld ix, MsgLineas : call PRINTAT
    ld a, 6 : ld b, 6 : ld c, 26 : ld ix, MsgNivel  : call PRINTAT
    ld a, 6 : ld b, 9 : ld c, 26 : ld ix, MsgProxima : call PRINTAT
    pop bc : pop ix
    ret

; ImprimirMarcador -- refresca los tres valores. Solo se llama cuando alguno
;   ha cambiado: repintar texto en cada frame es puro desperdicio.
;   Preserva BC e IX, que son la posicion y el puntero de la pieza en curso.
ImprimirMarcador:
    push ix : push bc
    ld a, 7 : ld b, 1 : ld c, 26
    call PREP_PRT                      ; fija atributo y los dos cursores
    ld a, (PUNTOS+2) : call ImprimirBCD ; el par mas significativo primero
    ld a, (PUNTOS+1) : call ImprimirBCD
    ld a, (PUNTOS)   : call ImprimirBCD
    ld a, 7 : ld b, 4 : ld c, 26
    call PREP_PRT
    ld a, (LINEAS) : call ImprimirDec3
    ld a, 7 : ld b, 7 : ld c, 26
    call PREP_PRT
    ld a, (NIVEL) : call ImprimirDec3
    pop bc : pop ix
    ret

; ImprimirBCD -- imprime los dos digitos del byte BCD en A.
;   El cursor debe estar ya puesto. Destruye AF, B, DE, HL. Preserva C, IX, IY.
ImprimirBCD:
    PUSH AF
    RRCA : RRCA : RRCA : RRCA   ; nibble alto a los bits 0-3
    AND $0F : ADD A, '0'        ; valor del digito -> codigo ASCII
    CALL PRINTCHNUM : POP AF
    AND $0F : ADD A, '0'        ; nibble bajo
    JP PRINTCHNUM               ; salto final: imprime, avanza cursor y vuelve

; ImprimirDec3 -- imprime A (0-255) como tres digitos decimales con ceros a la
;   izquierda, para que el campo no encoja y no queden digitos viejos.
;   El Z80 no divide, asi que restamos. Destruye AF, B, DE, HL. Preserva C.
ImprimirDec3:
    ld b, 0
id_cientos:
    cp 100
    jr c, id_fin_cientos
    sub 100
    inc b
    jr id_cientos
id_fin_cientos:
    push af
    ld a, b : add a, '0' : call PRINTCHNUM   ; PRINTCHNUM destruye B: por eso
    pop af                                   ;  se recarga en cada tramo
    ld b, 0
id_decenas:
    cp 10
    jr c, id_fin_decenas
    sub 10
    inc b
    jr id_decenas
id_fin_decenas:
    push af
    ld a, b : add a, '0' : call PRINTCHNUM
    pop af
    add a, '0'
    jp PRINTCHNUM

; Solo ASCII: cualquier byte >= 128 indexa fuera del juego de caracteres.
MsgPuntos: db "SCORE",0
MsgLineas: db "LINES",0
MsgNivel:  db "LEVEL",0
MsgProxima: db "NEXT",0
