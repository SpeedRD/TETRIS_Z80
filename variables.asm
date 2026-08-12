; variables.asm -- TODO el estado mutable nuevo del juego, en un solo sitio.
;
; Se INCLUDE el ULTIMO en main.asm, asi que aterriza en $A2C7, el primer byte
; libre despues de la imagen del programa: memoria no contendida, separada del
; codigo y de la tabla de piezas, y referenciada siempre por etiqueta.
;
; NO declarar ninguna de estas variables en otro fichero: una segunda
; declaracion es un error de etiqueta duplicada.
; NO copiar el patron de "Medio" (piezas.asm:31), que vive incrustado en la
; imagen de codigo justo detras del ultimo registro de pieza y sin margen.

; --- puntuacion ------------------------------------------------------------
PUNTOS:          DB 0, 0, 0 ; BCD empaquetado, 6 digitos: pares 1-2, 3-4, 5-6
LINEAS:          DB 0       ; total de filas eliminadas (binario de 8 bits)
NIVEL:           DB 0       ; nivel actual (binario de 8 bits)
PROX_NIVEL:      DB 10      ; filas que faltan para subir de nivel
MEJOR:           DB 0, 0, 0 ; mejor puntuacion de la SESION, mismo formato que
                            ; PUNTOS (BCD empaquetado, 6 digitos) para poder
                            ; reutilizar ImprimirBCD. Se escribe en un solo
                            ; sitio -- ActualizarMejor, al entrar en
                            ; Pantalla_Final -- y se lee en dos, la pantalla de
                            ; inicio y la de fin de partida. Sobrevive a
                            ; inicializar: nadie lo pone a cero, y por eso es de
                            ; la sesion y no de la partida

; --- gravedad --------------------------------------------------------------
FRAMES_POR_FILA: DB 48      ; frames entre dos caidas de una fila (nivel 0)
contador_frames: DB 48      ; frames que faltan para la proxima caida
contador_rapido: DB 4       ; frames que faltan para la proxima caida RAPIDA
                            ; (soft drop, SPACE mantenida). Solo se decuenta
                            ; mientras SPACE esta pulsada -- juego.asm; no
                            ; toca ni reemplaza a contador_frames, que sigue
                            ; su cuenta normal por debajo sin interrupcion

; --- entrada ---------------------------------------------------------------
teclas_ant:      DB 0       ; mascara de la lectura anterior de leer_teclas.
                            ; Convenio de leer_teclas: bit a 1 = tecla PULSADA
                            ; (ya invertida), por eso el valor inicial es 0.

; --- seleccion y posicion de pieza -----------------------------------------
semilla:         DB $A5     ; estado del LFSR. DEBE ser distinto de cero: un
                            ; LFSR que llega a cero se queda en cero para siempre
siguiente_pieza: DW T_0     ; puntero al registro de la proxima pieza (preview).
                            ; Arranca en un registro VALIDO, no en 0: iniciar
                            ; siempre llama antes a iniciar_secuencia, pero con
                            ; un 0 aqui cualquier camino que se saltara ese paso
                            ; dejaria IX=$0000 y pintar_tetromino leeria las
                            ; filas/columnas de la ROM.
Medio:           DB 15      ; copia en memoria de la columna en curso (C).
                            ; El valor inicial es indiferente: juego.asm lo
                            ; escribe desde C en cuanto aparece la primera
                            ; pieza. Antes vivia en piezas.asm, dentro de la
                            ; imagen de codigo, pegado al ultimo registro.

; --- musica ----------------------------------------------------------------
; Las tres primeras son la posicion del reproductor dentro de melodia
; (musica.asm); la cuarta es la unica que escribe alguien de fuera.
musica_puntero:  DW melodia  ; siguiente pareja (nota, duracion) por leer.
                             ; Referencia adelantada a musica.asm, igual que
                             ; siguiente_pieza lo es a piezas.asm.
musica_nota:     DB NOTA_SIL ; indice en tabla_notas de la nota que suena
                             ; AHORA. NOTA_SIL = ninguna (silencio de la
                             ; propia melodia).
musica_frames:   DB 0        ; tramas que le quedan a esa nota. 0 = agotada:
                             ; la proxima llamada a musica_frame carga la
                             ; pareja siguiente. Por eso el valor inicial es 0
                             ; y no hace falta ninguna rutina de arranque.
musica_silencio: DB 0        ; distinto de cero = esta trama va MUDA.
                             ; La escribe juego.asm con el numero de filas que
                             ; devuelve limpiar_lineas: una trama que borra
                             ; lineas no tiene presupuesto para el relleno de
                             ; sonido (MUSIC_DESIGN.md 6). musica_frame la lee
                             ; y la vuelve a poner a cero SIEMPRE, asi que es
                             ; una bandera de una sola trama.
