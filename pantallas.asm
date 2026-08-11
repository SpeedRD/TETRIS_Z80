;Pinta las pantallas principales (Inicio, Final, etc)
;
; Las tres pantallas hablan ahora el mismo lenguaje visual que el marcador de
; la partida: paneles enmarcados con el MISMO byte de atributo que el borde del
; pozo (ATRIB_MARCO = 6*8+7 = 55, tableroJuego.asm:10), rotulos en amarillo
; (tinta 6) y textos y valores en blanco (tinta 7), igual que
; ImprimirEtiquetas e ImprimirMarcador (puntuacion.asm:95,107). Antes cada
; pantalla llevaba su propia combinacion -- verde, magenta, azul, cian -- y
; ninguna se parecia al marcador; ahora convergen las tres.
;
; Los TEXTOS no cambian: esto es un cambio de presentacion, no una reescritura.
;
; El dibujo esta separado de la espera de teclado: pintar_ini, pintar_final y
; pintar_gracias pintan y vuelven, sin tocar el teclado, asi que se pueden
; probar sin nadie delante (tests/test_pantallas.py). Pantalla_Ini y
; Pantalla_Final siguen siendo los puntos de entrada de siempre.
;
; El marco se dibuja SOLO con bytes de atributo, como el pozo y como el
; recuadro de la vista previa: no hace falta ningun glifo de dibujo de cajas,
; que ademas charset.bin no tiene (solo ASCII 32-127).

PANEL_ALTO   EQU 5          ; marco / hueco / texto / hueco / marco
ATRIB_MARCO  EQU 6 * 8 + 7  ; 55: papel amarillo, tinta blanca -- el borde del pozo
TINTA_ROTULO EQU 6          ; amarillo, como las etiquetas SCORE/LINES/LEVEL/NEXT
TINTA_TEXTO  EQU 7          ; blanco, como los valores del marcador
TINTA_CURSOR EQU 6 + $80    ; amarillo parpadeante: la celda que sigue al prompt.
                            ;  El bit 7 es FLASH; antes era verde (2+$80) en la
                            ;  pantalla de inicio y azul (1+$80) en la de fin

MEJOR_COL_ROTULO EQU 4      ; "MEJOR PUNTUACION" ocupa las columnas 4-19
MEJOR_COL_VALOR  EQU 22     ; los seis digitos ocupan las columnas 22-27

Pantalla_Ini:
    call pintar_ini
    call EsperarTecla        ; Leer el teclado hasta que se pulse S o N
    ret

Pantalla_Final:
    call ActualizarMejor     ; PUNTOS todavia vale lo de esta partida: es aqui,
                             ;  antes de que reiniciar_marcador lo ponga a cero
                             ;  en la siguiente, donde puede haber record
    call pintar_final
    call LeerTecla           ; Wait for a key press (S or N)

    jp inicializar            ; Restart the game. JP y no CALL: con CALL cada
                              ; reinicio dejaba 2 bytes de pila sin recuperar,
                              ; y lo que hubiera detras era codigo muerto.


FinDelJuego:
    call pintar_gracias

fin:    JR fin


EsperarTecla:
    call LeerTecla
    cp $1F              ; SoltarTecla devuelve el puerto enmascarado a los bits 0-4
    jr nz,EsperarTecla  ; Esperar hasta que no haya tecla pulsada
    ret

LeerTecla:
    ld bc,$7FFE         ; Escanear línea B,N,M,SYMB,Space
    in a,(c)
    bit 3,a
    jr z,FinDelJuego    ; Han pulsado N
    ld bc,$FDFE         ; Escanear línea G,F,D,S,A
    in a,(c)
    bit 1,a
    jr nz,LeerTecla     ; No han pulsado 'S'
    jr SoltarTecla

SoltarTecla:
    in a,(c)            ; Leer del puerto que se ha definido en LeerTecla
    and $1F             ; solo los bits 0-4 son teclado; el bit 6 (EAR) no es fiable
    cp $1F              ; Comprobar que no hay tecla pulsada
    jr nz,SoltarTecla   ; Esperar hasta que no haya tecla pulsada
    ret


; ---------------------------------------------------------------------------
; Dibujo de las pantallas. Ninguna lee el teclado y ninguna vuelve con estado
; a medias, asi que las tres se pueden llamar sueltas desde los tests.
;
; Los tres paneles de cada pantalla miden lo mismo (32 columnas x 5 filas) y
; van a las mismas columnas, para que las pantallas se lean como una familia.
; El texto va siempre en la fila central del panel (fila del panel + 2) y
; centrado en el interior, que son las columnas 1-30.

; pintar_ini -- pantalla previa a la partida: tipo de juego, mejor puntuacion
;   de la sesion y peticion de confirmacion.
;   Destruye AF, BC, DE, HL, IX.
pintar_ini:
    call CLEARSCR       ;borramos pantalla

    ld b, 1             ; panel del titulo: filas 1-5
    call pintar_marco
    ld a, TINTA_ROTULO  ;Letra amarilla
    ld b, 3             ;Coordenadas para el mensaje de bienvenida
    ld c, 5             ; 21 caracteres centrados en las columnas 1-30
    ld ix, MensajeJuego
    call PRINTAT

    ld b, 8             ; panel de la mejor puntuacion: filas 8-12
    call pintar_mejor   ;  primero de los DOS sitios que leen MEJOR

    ld b, 15            ; panel del prompt: filas 15-19
    call pintar_marco
    ld a, TINTA_TEXTO   ;Letra blanca
    ld b, 17            ;Coordenadas para el mensaje de inicio
    ld c, 1             ; 29 caracteres: columnas 1-29
    ld ix, MensajeIniciar
    call PRINTAT

    ld b, 17                  ; Para colocar el cursor: la celda que sigue al
    ld c, 30                  ;  prompt, todavia dentro del panel
    call CRtoATTR             ; Calcular la dirección del atributo (preserva BC)
    ld (hl), TINTA_CURSOR     ; Establecer el atributo
    ret

; pintar_final -- pantalla de fin de partida. NO calcula el record: eso lo hace
;   ActualizarMejor una sola vez, antes de entrar aqui. Esta rutina solo lee.
;   Destruye AF, BC, DE, HL, IX.
pintar_final:
    call CLEARSCR  ; Clear the screen

    ld b, 3               ; panel del aviso: filas 3-7
    call pintar_marco
    ld a, TINTA_ROTULO    ; Set color to yellow on black
    ld b, 5               ; Row position
    ld c, 8               ; Column position: 16 caracteres centrados
    ld ix, MensajeGameOver  ; Address of the message
    call PRINTAT  ; Print the message

    ld b, 10              ; panel de la mejor puntuacion: filas 10-14
    call pintar_mejor     ;  segundo de los DOS sitios que leen MEJOR

    ld b, 17              ; panel del prompt: filas 17-21
    call pintar_marco
    ld a, TINTA_TEXTO     ; Set color to white on black
    ld b, 19              ; Row position
    ld c, 3               ; Column position: 25 caracteres centrados
    ld ix, MensajeReiniciar  ; Address of the message (antes cargaba
    call PRINTAT             ;  MensajeGameOver por segunda vez)

    ; Set cursor attribute to blinking yellow
    ld b, 19              ; Row position for attribute
    ld c, 28              ; Column position for attribute: tras el texto
    call CRtoATTR         ; Calculate attribute address (preserva BC)
    ld (hl), TINTA_CURSOR ; Set the attribute
    ret

; pintar_gracias -- pantalla de despedida. Un solo panel, centrado.
;   Destruye AF, BC, DE, HL, IX.
pintar_gracias:
    call CLEARSCR

    ld b, 9                  ; panel unico: filas 9-13
    call pintar_marco
    ld a, TINTA_ROTULO       ; Letra amarilla (antes cian parpadeante)
    ld b, 11                 ; Coordenadas para el mensaje final
    ld c, 7                  ; 17 caracteres centrados
    ld ix, MensajeFinal
    call PRINTAT
    ret

; pintar_marco -- marco de un panel: un rectangulo hueco de celdas de atributo,
;   de 32 columnas por PANEL_ALTO filas, con la esquina superior izquierda en
;   la columna 0 de la fila B.
;   Entrada: B = fila superior (0..23-PANEL_ALTO+1).
;   Preserva AF, BC, DE, HL, IX, IY.
;
;   Se pinta con atributos y nada mas, igual que el borde del pozo: el fichero
;   de pixeles queda a cero (CLEARSCR) y una celda de papel amarillo se ve como
;   un bloque solido. CRtoATTR en vez de CalcularAtributo porque preserva BC,
;   que aqui es la fila del panel (register-protocol).
pintar_marco:
    push af : push bc : push de : push hl
    ld c, 0
    call CRtoATTR            ; HL = atributo de (B,0); BC intacto
    ld a, ATRIB_MARCO
    ld de, 31                ; salto de la columna 0 a la 31 de la misma fila
    ld b, 32
pm_arriba:
    ld (hl), a               ; fila superior completa
    inc hl
    djnz pm_arriba           ; HL queda en la columna 0 de la fila siguiente
    ld b, PANEL_ALTO - 2
pm_lados:
    ld (hl), a               ; columna 0
    add hl, de
    ld (hl), a               ; columna 31
    inc hl                   ; columna 0 de la fila siguiente
    djnz pm_lados            ; djnz solo mira B: add hl,de no le afecta
    ld b, 32
pm_abajo:
    ld (hl), a               ; fila inferior completa
    inc hl
    djnz pm_abajo
    pop hl : pop de : pop bc : pop af
    ret

; ---------------------------------------------------------------------------
; Mejor puntuacion de la sesion
;
; MEJOR (variables.asm) es la puntuacion mas alta desde que se cargo el juego:
; tres bytes de BCD empaquetado, exactamente el mismo formato que PUNTOS, para
; poder reutilizar ImprimirBCD (puntuacion.asm:125) sin convertir nada.
;
; Se ESCRIBE en un solo sitio, ActualizarMejor, al entrar en Pantalla_Final.
; Se LEE en dos, y los dos pasan por pintar_mejor: la pantalla de inicio y la
; de fin de partida. Nada mas la toca; no hay una tabla de records ni entrada
; de nombre, es un unico numero.

; pintar_mejor -- panel completo de la mejor puntuacion: marco, rotulo y valor.
;   Entrada: B = fila superior del panel.
;   Destruye AF, BC, DE, HL, IX.
pintar_mejor:
    call pintar_marco
    push bc                  ; PRINTAT deja B a cero (register-protocol)
    ld a, TINTA_ROTULO
    inc b : inc b            ; la fila del texto es la central del panel
    ld c, MEJOR_COL_ROTULO
    ld ix, MsgMejor
    call PRINTAT
    pop bc
    inc b : inc b
    ld c, MEJOR_COL_VALOR
    call ImprimirMejor
    ret

; ImprimirMejor -- imprime los seis digitos de MEJOR. Solo lee.
;   Entrada: B = fila, C = columna.
;   Destruye AF, B, DE, HL. Preserva C, IX, IY.
ImprimirMejor:
    ld a, TINTA_TEXTO        ; blanco, como los valores del marcador
    call PREP_PRT            ; fija atributo y los dos cursores
    ld a, (MEJOR+2) : call ImprimirBCD   ; el par mas significativo primero
    ld a, (MEJOR+1) : call ImprimirBCD
    ld a, (MEJOR)   : jp ImprimirBCD     ; salto final: imprime y vuelve

; ActualizarMejor -- si la puntuacion de la partida que acaba de terminar supera
;   a MEJOR, la copia. Se llama UNA vez, al entrar en Pantalla_Final.
;   Destruye AF, BC, DE, HL.
;
;   La comparacion va del par de digitos mas significativo al menos: en BCD
;   empaquetado cada byte lleva dos digitos decimales, asi que el orden de los
;   bytes coincide con el orden numerico y basta un CP normal.
ActualizarMejor:
    ld hl, PUNTOS + 2
    ld de, MEJOR + 2
    ld b, 3
am_comparar:
    ld a, (de)               ; A = par de digitos de MEJOR
    cp (hl)                  ; MEJOR - PUNTOS
    jr c, am_copiar          ; MEJOR < PUNTOS: hay record nuevo
    ret nz                   ; MEJOR > PUNTOS: no lo hay, y no seguimos mirando
    dec hl : dec de          ; iguales hasta aqui: decide el par siguiente
    djnz am_comparar
    ret                      ; empate exacto: no hay nada que copiar
am_copiar:
    ld hl, PUNTOS
    ld de, MEJOR
    ld bc, 3
    ldir
    ret


CalcularAtributo:
                        ; Rutina que recibe en B,C las coordenadas de la pantalla (fila, columna)
                        ; y devuelve en HL la dirección del atributo correspondiente
    PUSH AF             ; Guardamos A en el stack
    LD H,b              ; Los bits 4,5 de B deben ser los bits 0,1 de H
    SRL H : SRL H : SRL H
    LD A,B              ; Los bits 0,1,2 de B deben ser los bits 5,6,7 de L
    SLA A : SLA A : SLA A : SLA A : SLA a
    OR c                ; Y C son los bits 0-4 de L
    LD L,A
    LD BC, $5800        ; Le sumamos la dirección de comienzo de los atributos
    ADD HL,BC
    POP AF
    RET




MensajeFinal:     db "Gracias por jugar",0         ; Mensaje de agradecimiento
MensajeIniciar:   db "Empezamos una partida (S/N)? ",0  ; Mensaje para iniciar partida
MensajeJuego:     db "Tipo de Juego: Tipo-A",0   ; Mensaje del tipo de juego
; Solo ASCII: el fuente es UTF-8, asi que "¿" y "¡" se ensamblaban como dos
; bytes ($C2 $BF y $C2 $A1). PRINTCHNUM indexa CHARSET con (codigo-32)*8 y el
; juego de caracteres solo cubre los codigos 32-127, asi que cualquier byte
; >= 128 apuntaba fuera y pintaba dos glifos de basura delante del texto.
MensajeReiniciar: db "Reiniciar el juego (S/N)?",0   ; Mensaje para reiniciar partida
MensajeGameOver:  db "Juego Terminado!",0        ; Mensaje de fin de juego
MsgMejor:         db "MEJOR PUNTUACION",0        ; Rotulo del panel de record
