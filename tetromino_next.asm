;Programa para seleccionar y posicionar la proxima pieza

longitud_pieza EQU T_L1 - T_0      ;Longitud de un tetromino

seleccionar_pieza:
    ld ix, T_0       ; IX con la direccion del primer tetromino
    ld a, r         ; Usar el registro para obtener valor aleatorio
    and 31          ; Limita el valor a 0-31
    cp 19           ; Comparar con el numero maximo permitido (20)
    jr c, calc_posicion        ;Si el valor es >= 20, ajustarlo
    sub 19

calc_posicion:
    ld de, longitud_pieza       ; Cargar la longitud de la pieza en la variable
    or a        ; Verificar si A es 0
    jr z, pos_arriba        ; Si es 0, saltar a la rutina

ajustar_pos:
    add ix, de      ; Ajustar la posicion de IX sumando la longitud de la pieza
    dec A       ; Decrementar a para acercarse a 0
    jr nz, ajustar_pos      ; Repetir hasta que A sea 0

pos_arriba:
    ld b, 0     ; Inicializar B con 0   
    ld c, 15    ; Inicializar C con 15
    ret    

fin_selec_pieza: jr fin_selec_pieza