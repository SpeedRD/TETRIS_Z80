GIRAR:
;--------------------------------------------------------------------
;Esta funcion es similar a la de desplazar.asm, pero para girar la 
;pieza y transformarla en su girado

;Param. de Entrada: IX, Teclado— Param. de Salida: IX
;--------------------------------------------------------------------
    PUSH BC
    LD BC,$FBFE         ; Escanear línea  T,R,E,W,Q
    IN A,(C)
    BIT 0,A
    JR Z, turn_left    ; Han pulsado Q -> Girar izquierda
    BIT 1,A
    JR Z, turn_right    ; Han pulsado W -> Girar drcha
    JR no_teclaturn
turn_left:
    LD D, (IX + 9) 
    LD E, (IX + 8)
    LD IX, DE ;Si se quiere girar la piezaa a la izq, se busca en el vector de la pieza las posiciones 8 y 9, que contienen la pieza a la que debería convertirse nuestro tetromino.
    JR Soltar_Tecla
    POP BC     ; Esperar q que suelten la tecla
    RET

turn_right:
    LD D, (IX + 11)
    LD E, (IX + 10)
    LD IX, DE ;Si se quiere girar la piezaa a la izq, se busca en el vector de la pieza las posiciones 10 y 11, que contienen la pieza a la que debería convertirse nuestro tetromino.
    JR Soltar_Tecla     ; Esperar q que suelten la tecla
    POP BC
    RET


Soltar_Tecla:           ; Rutina de espera hasta que se suelta la tecla
    IN A,(C)            ; Leer del puerto que se ha definido en Lee_Tecla
    CP $FF              ; Comprobar que no hay tecla pulsada
    JR NZ,Soltar_Tecla  ; esperar hasta que no haya tecla pulsada
    POP BC
    RET

no_teclaturn:
    POP BC
    RET