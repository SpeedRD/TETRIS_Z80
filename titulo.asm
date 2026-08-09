;Pinta la pantalla de inicio del Tetris

InicioDePantalla:
    ld hl, datosPantalla  
    call PintarPantalla ; Abajo definimos esto
    ret

PintarPantalla:
    push bc
    push de

    ld de, $4000    ;Direccion de la video RAM
    ld bc, 6912     ;Size de la video RAM
    ldir            ;Mueve datos de hl hasta de hasta que bc sea 0

    pop de          ;Recupera registros usados
    pop bc

EsperarEntrada:
    ld bc, $FBFE
    in a, (c)               ; Leer el puerto de entrada del teclado
    bit 0, a                ; Comprobar si todas las teclas están liberadas
    jr nz, EsperarEntrada   ; Si todas las teclas no están liberadas, seguir esperando
    ld d, 1
    jr LiberarTecla

LiberarTecla:
    in a, (c)
    cp $FF
    jr nz, LiberarTecla
    ret

datosPantalla: INCBIN "TETRIS.scr"  ; Contenido de la pantalla de inicio "TETRIS.scr"