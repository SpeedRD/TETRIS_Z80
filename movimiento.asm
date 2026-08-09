MOVER:
;----------------------------------------
;Desplazar.asm es una funcion encargada de 
; guardar y modificar Medio, de desplazar 
;la pieza

;Param. de Entrada: Teclado — Param. de Salida: Medio
;----------------------------------------
    PUSH BC
    LD BC,$BFFE       ; Escanear línea  H,J,K,L,ENTER
    IN A,(C)
    BIT 3,A
    JR Z, move_left    ; Han pulsado J -> Mover izquierda
    BIT 2,A
    JR Z, move_right  ; Han pulsado K -> Mover derecha
    BIT 0,A          
    JR no_tecla_move     ; No hay tecla pulsada

move_right:
    LD A, (Medio) 
    INC A
    LD (Medio), A
    JR SoltarTeclaMv
    POP BC     ; Esperar que suelten la tecla
    RET

move_left:
    LD A, (Medio) 
    DEC A
    LD (Medio), A
    JR SoltarTeclaMv     ; Esperar que suelten la tecla
    POP BC
    RET



SoltarTeclaMv:           ; Rutina de espera hasta que se suelta la tecla
    IN A,(C)            ; Leer del puerto que se ha definido en Lee_Tecla
    CP $FF              ; Comprobar que no hay tecla pulsada
    JR NZ,SoltarTeclaMv  ; esperar hasta que no haya tecla pulsada
    POP BC
    RET

no_tecla_move:
    POP BC
    RET