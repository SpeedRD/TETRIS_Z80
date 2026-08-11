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
