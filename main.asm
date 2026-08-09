;Programa principal del juego 
    
    DEVICE ZXSPECTRUM48
    ORG $8000
    LD SP, 0

    CALL InicioDePantalla ;pantalla de inicio

inicializar:
    CALL Pantalla_Ini ;mensaje de inicio

    CALL dibujar_tablero

    CALL iniciar




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
    INCLUDE "caida.asm" 
    INCLUDE "movimiento.asm"
    INCLUDE "giro.asm"