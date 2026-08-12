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
;   E  = mascara de leer_teclas: bits0-3 flanco nuevo (K/J/Q/W), bit4 = SPACE
;        mantenida AHORA (caida rapida / soft drop), no flanco
;   H  = 1 si en esta pasada toca bajar una fila, 0 si no
;HL, DE y AF son libres para las rutinas llamadas; B, C e IX no lo son.

FRAMES_CAIDA_RAPIDA EQU 4   ; frames entre caidas mientras SPACE esta pulsada.
                            ; Mas rapido que cualquier nivel normal (la tabla
                            ; FRAMES_POR_NIVEL de puntuacion.asm no baja de 6),
                            ; pero no instantaneo: esto es soft drop, no hard
                            ; drop.

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
    JP NZ, fin_partida      ;  B=255, que leia RAM fuera de la pantalla ($77EF).
                            ;  JP, no JR: fin_partida ha quedado fuera de rango

    CALL pintar_tetromino   ; pintamos una vez, para que el primer borrado
                            ;  del bucle tenga algo que borrar
paso:
    HALT                    ; dormimos hasta el tick de 50 Hz. El borrado y el
                            ;  repintado caen justo detras, en el borde superior.
    LD H, 0                 ; por defecto esta pasada no baja

    CALL leer_teclas        ; A = teclas; nunca bloquea. Se lee YA aqui, antes
                            ;  del borrado, porque la gravedad rapida de abajo
                            ;  necesita el bit4 (SPACE) de esta misma pasada.
                            ;  borrar_tetromino preserva DE, asi que E aguanta.
    LD E, A                 ; E sobrevive a borrar_tetromino, en_rango,
    LD D, 0                 ;  comprobar y GIRAR. D = desplazamiento lateral

    LD A,(contador_frames)  ; gravedad NORMAL: cuenta siempre, la mantenga o
    DEC A                   ;  no SPACE pulsada, para que soltar la tecla
    LD (contador_frames), A ;  vuelva a la velocidad normal sin ningun salto
    JR NZ, comprobar_rapida
    LD A,(FRAMES_POR_FILA)  ; se agoto la cuenta: recargamos y pedimos bajada
    LD (contador_frames), A
    LD H, 1
comprobar_rapida:
    BIT 4, E                ; gravedad RAPIDA (soft drop): SUMA una bajada
    JR Z, sin_gravedad       ;  mas si toca, nunca sustituye a la de arriba.
    LD A,(contador_rapido)  ;  Solo se decuenta mientras SPACE sigue pulsada:
    DEC A                   ;  al soltarla la cuenta se queda congelada donde
    LD (contador_rapido), A ;  estaba, lista para retomarse la proxima vez.
    JR NZ, sin_gravedad
    LD A, FRAMES_CAIDA_RAPIDA
    LD (contador_rapido), A
    LD H, 1
sin_gravedad:
    CALL borrar_tetromino   ; borra en el (B,C) ACTUAL con el IX ACTUAL

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
    LD (musica_silencio), A ; una trama que borra filas va MUDA: ni un borrado
                            ;  de una sola fila cabe junto al relleno de sonido
                            ;  (MUSIC_DESIGN.md 6). LD (nn),A no toca A ni los
                            ;  flags, asi que anotar_lineas sigue recibiendo
                            ;  intacta la cuenta que acaba de devolver.
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

    CALL musica_frame       ; el relleno de sonido va AQUI, al final del cuerpo
                            ;  y DETRAS del repintado (MUSIC_DESIGN.md 7 regla
                            ;  1): el par borrar/pintar tiene que seguir pegado
                            ;  al HALT, dentro del borde superior, o la pieza se
                            ;  desgarra. Delante del repintado lo echaria fuera
                            ;  de esa ventana; detras es inofensivo.
                            ;  Preserva AF, BC, DE, HL, IX e IY, y no hace DI.
    JP paso                 ; JP, no JR: paso ha quedado fuera de rango

fin_partida:
    CALL relleno_pozo       ; el pozo se llena de bloques antes de cortar a la
                            ;  pantalla final (relleno.asm). Aqui el bucle ya
                            ;  ha terminado: no hay presupuesto de frame que
                            ;  respetar, solo el borde superior para no
                            ;  desgarrar. No toca PUNTOS ni MEJOR.
    JP Pantalla_Final       ; JP, no CALL: no vuelve nunca
