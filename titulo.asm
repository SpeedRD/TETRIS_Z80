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
    bit 0, a                ; ¿Está pulsada la Q? Activo a nivel bajo: 0 = pulsada.
    jr nz, EsperarEntrada   ; Todavía no: seguir esperando

LiberarTecla:               ; Pulsada: ahora esperamos a que la suelten
    in a, (c)
    and $1F                 ; solo los bits 0-4 son teclado; el bit 6 (EAR) no es fiable
    cp $1F                  ; $1F = ninguna tecla pulsada en esta media fila
    jr nz, LiberarTecla
    ret

datosPantalla: INCBIN "TETRIS.scr"  ; Contenido de la pantalla de inicio "TETRIS.scr"