;Pinta las pantallas principales (Inicio, Final, etc)

Pantalla_Ini:
    call CLEARSCR       ;borramos pantalla

    ld a, 6     ;Letra amarilla
    ld b, 4     ;Coordenadas para el mensaje de bienvenida
    ld c, 6
    ld ix, MensajeJuego
    call PRINTAT

    ld a, 2     ;Letra verde
    ld b, 11    ;Coordenadas para el mensaje de inicio
    LD c, 2       
    ld ix, MensajeIniciar
    call PRINTAT

    ld b, 11                  
    ld c, 30                  ; Para colocar el cursor
    call CalcularAtributo    ; Calcular la dirección del atributo
    ld a,2+$80               ; Verde parpadeante
    ld (hl),a                ; Establecer el atributo

    call EsperarTecla        ; Leer el teclado hasta que se pulse S o N
    ret

Pantalla_Final:
    call CLEARSCR  ; Clear the screen

    ; Display the first message
    ld a, 3               ; Set color to pink on black
    ld b, 5               ; Row position
    ld c, 12              ; Column position
    ld ix, MensajeGameOver  ; Address of the message
    call PRINTAT  ; Print the message

    ; Display the second message
    ld a, 1               ; Set color to blue on black, blinking
    ld b, 18              ; Row position
    ld c, 1               ; Column position
    ld ix, MensajeGameOver   ; Address of the message
    call PRINTAT  ; Print the message

    ; Set cursor attribute to blinking blue
    ld b, 18              ; Row position for attribute
    ld c, 30              ; Column position for attribute
    call CalcularAtributo ; Calculate attribute address
    ld a, 1 + $80         ; Blinking blue
    ld (hl), a            ; Set the attribute

    call LeerTecla     ; Wait for a key press (S or N)

    call inicializar          ; Restart the game


FinDelJuego:
    call CLEARSCR

    ld a,5+$80               ; Letra cian
    ld b,11                  ; Coordenadas para el mensaje final
    ld c,8       
    ld ix,MensajeFinal      
    call PRINTAT  

fin:    JR fin

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


EsperarTecla:
    call LeerTecla
    cp $FF
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
    cp $FF              ; Comprobar que no hay tecla pulsada
    jr nz,SoltarTecla   ; Esperar hasta que no haya tecla pulsada
    ret





MensajeFinal:     db "Gracias por jugar",0         ; Mensaje de agradecimiento
MensajeIniciar:   db "Empezamos una partida (S/N)? ",0  ; Mensaje para iniciar partida
MensajeJuego:     db "Tipo de Juego: Tipo-A",0   ; Mensaje del tipo de juego
MensajeReiniciar: db "¿Reiniciar el juego (S/N)?",0   ; Mensaje para reiniciar partida
MensajeGameOver:  db "¡Juego Terminado!",0        ; Mensaje de fin de juego
