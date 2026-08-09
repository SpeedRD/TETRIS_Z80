;Funcionamiento del juego

iniciar:
    CALL seleccionar_pieza
    
    LD B, 255 ;me situo en la ultima línea
    ld a, 15
    LD (Medio), A

    CALL comprobar
    or a
    jr nz, end

ciclo_juego:
 
    ld a, b
    cp $FF
    jr z, siguiente_juego

    CALL borrar_tetromino: ; borrar el tetromino

siguiente_juego:
    inc b
    ld d, b
    ld a, (Medio)
    ld e, a
    
    
    call comprobar ; Validar la posición del tetromino
    or a

    jr z, cambiar_tetromino ; Si no se puede mover más abajo, cambiar tetromino

    dec b                  ; Si se puede mover, actualizar posición y dibujar
    ld c, e
    call pintar_tetromino
    jr iniciar
    
cambiar_tetromino:
    ld c, e
    call GIRAR
    call pintar_tetromino ; Pintar el tetromino en la parte superior
    call Tiempo 
    call MOVER
    jr ciclo_juego
    
end:
    ret

    
    