;Funcionamiento del juego -- bucle principal
;
;REGLA: se comprueba EXACTAMENTE la posicion que se va a pintar, con
;EXACTAMENTE el IX que se va a pintar. El bucle antiguo validaba con la
;columna de la pasada ANTERIOR y giraba DESPUES de comprobar, asi que
;validaba una posicion que la pieza no llegaba a ocupar nunca.
;
;Estado global mientras cae una pieza:
;   B  = fila       C  = columna      IX = registro de la pieza
;   (Medio) = copia en memoria de C; debe coincidir con C en cada comprobar
;   D  = desplazamiento lateral pedido en esta pasada (0, +1 o -1)
;   E  = mascara de teclas nuevas de leer_teclas
;   H  = 1 si en esta pasada toca bajar una fila, 0 si no
;HL, DE y AF son libres para las rutinas llamadas; B, C e IX no lo son.

iniciar:
    CALL iniciar_secuencia  ; semilla del azar y primera pieza anunciada

    CALL reiniciar_marcador ; puntos/lineas/nivel a cero y rotulos en pantalla.
                            ;  Aqui todavia no hay ninguna pieza, asi que es el
                            ;  unico sitio donde imprimir es gratis.

    CALL seleccionar_pieza  ; IX = pieza, B = 0, C = 15
    CALL pintar_siguiente   ; muestra la que viene detras
    LD A, C
    LD (Medio), A           ; Medio siempre refleja C

    CALL comprobar          ; fin de partida = la pieza nueva no cabe en su
    OR A                    ;  posicion de aparicion. Antes esto se hacia con
    JR NZ, fin_partida      ;  B=255, que leia RAM fuera de la pantalla ($77EF).

    CALL pintar_tetromino   ; pintamos una vez, para que el primer borrado
                            ;  del bucle tenga algo que borrar
paso:
    HALT                    ; dormimos hasta el tick de 50 Hz. El borrado y el
                            ;  repintado caen justo detras, en el borde superior.
    LD H, 0                 ; por defecto esta pasada no baja
    LD A,(contador_frames)
    DEC A
    LD (contador_frames), A
    JR NZ, sin_gravedad
    LD A,(FRAMES_POR_FILA)  ; se agoto la cuenta: recargamos y pedimos bajada
    LD (contador_frames), A
    LD H, 1
sin_gravedad:
    CALL borrar_tetromino   ; borra en el (B,C) ACTUAL con el IX ACTUAL

    CALL leer_teclas        ; A = teclas que acaban de pulsarse; nunca bloquea
    LD E, A                 ; E sobrevive a en_rango, comprobar y GIRAR
    LD D, 0                 ; D = desplazamiento lateral
    BIT 0, E
    JR Z, no_derecha
    INC D                   ; K -> una columna a la derecha
no_derecha:
    BIT 1, E
    JR Z, lateral
    DEC D                   ; J -> una columna a la izquierda
                            ;  (las dos a la vez se anulan: D = 0)
lateral:
    LD A, D
    OR A
    JR Z, sin_lateral
    LD A, C
    ADD A, D
    LD C, A                 ; C = columna candidata
    CALL en_rango           ; 1. ¿sigue dentro de las columnas 7-24?
    OR A
    JR NZ, lat_no
    CALL comprobar          ; 2. ¿libre de bloques ya asentados?
    OR A
    JR Z, lat_si
lat_no:
    LD A, C                 ; bloqueada: devolvemos la columna vieja. NO se
    SUB D                   ;  salta la gravedad de esta pasada.
    LD C, A
    JR sin_lateral
lat_si:
    LD A, C
    LD (Medio), A           ; Medio se actualiza en cada confirmacion
sin_lateral:

    LD A, E
    AND %00001100           ; ¿ni Q ni W recien pulsadas?
    JR Z, sin_giro
    BIT 2, E
    LD A, 0                 ; Q -> A = 0, girar a la izquierda
    JR NZ, girar_ya         ;  (LD no toca los flags de BIT)
    INC A                   ; W -> A = 1, girar a la derecha
girar_ya:
    CALL GIRAR              ; comprueba limites, retranquea, valida y CONFIRMA
sin_giro:                   ;  el solo. NUNCA envolverlo en comprobar.

    LD A, H
    OR A
    JR Z, dibujar           ; no es pasada de gravedad: solo repintar

    INC B                   ; B = fila candidata
    CALL comprobar
    OR A
    JR Z, dibujar           ; libre: la caida queda confirmada

    DEC B                   ; bloqueada: deshacemos la caida, la pieza se queda
    CALL pintar_tetromino   ; y la fijamos en el fichero de atributos

    CALL limpiar_lineas     ; A = filas eliminadas (0..4)
    CALL anotar_lineas      ; puntua, sube de nivel y refresca el marcador

    CALL seleccionar_pieza  ; IX = pieza siguiente, B = 0, C = 15
    CALL pintar_siguiente   ; refresca el recuadro con la nueva anunciada
    LD A, C
    LD (Medio), A
    CALL comprobar          ; fin de partida = la nueva no cabe al aparecer
    OR A
    JR NZ, fin_partida

dibujar:
    CALL pintar_tetromino   ; pintamos el (B, C, IX) ya validado
    JR paso

fin_partida:
    JP Pantalla_Final       ; JP, no CALL: no vuelve nunca
