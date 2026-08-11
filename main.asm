;Programa principal del juego 
    
    DEVICE ZXSPECTRUM48
    ORG $8000
    LD SP, 0

    DI                    ;fijamos el estado de interrupciones en vez de heredarlo
    LD IY, $5C3A          ;base de las variables del sistema: la rutina de la ROM en
    IM 1                  ; $0038 direcciona con (IY+n) y la corrompe si IY no es esto
    EI                    ;el tick de 50 Hz queda disponible para HALT

    CALL InicioDePantalla ;pantalla de inicio

inicializar:
    LD SP, 0              ;reinicio limpio. Aqui no hay ningun marco vivo: se
                          ; llega por JP desde Pantalla_Final. Hace falta
                          ; porque el CALL iniciar de abajo NUNCA retorna (el
                          ; fin de partida salta a Pantalla_Final), asi que
                          ; cada partida dejaria 2 bytes de pila sin recuperar.

    CALL Pantalla_Ini ;mensaje de inicio

    CALL dibujar_tablero

    CALL iniciar

fin_del_programa:         ;iniciar no deberia volver (el fin de partida salta a
    JR fin_del_programa   ; Pantalla_Final). Si vuelve, paramos aqui: sin este
                          ; terminador la ejecucion caia en InicioDePantalla.

    INCLUDE "titulo.asm"
    INCLUDE "pantallas.asm"
    INCLUDE "L30.3 - printat.asm" 
    INCLUDE "L35 - Tetris_3D.asm" 
    INCLUDE "tableroJuego.asm"
    INCLUDE "juego.asm"
    INCLUDE "tetromino_next.asm"
    INCLUDE "piezas.asm"
    INCLUDE "test_col.asm"
    INCLUDE "clear.asm"
    INCLUDE "giro.asm"
    INCLUDE "entrada.asm"
    INCLUDE "lineas.asm"
    INCLUDE "puntuacion.asm"
    INCLUDE "relleno.asm"
    INCLUDE "variables.asm"   ; SIEMPRE el ultimo: el estado mutable va al final
