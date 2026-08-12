; musica.asm -- musica de fondo en el altavoz de 1 bit. Korobeiniki.
;
; Diseno, presupuesto y decisiones: MUSIC_DESIGN.md. Lo imprescindible aqui:
;
;   * Presupuesto: 48.000 T por trama para el relleno de sonido (MUSIC_DESIGN 5),
;     de las 69.888 que tiene una trama de 48K. Se gasta EN CADA llamada, no de
;     media: la cuenta de semiperiodos de cada nota ya viene calculada para que
;     el producto cuenta x semiperiodo no pase de ahi.
;   * La llamada va al FINAL del cuerpo del bucle, detras del repintado
;     (MUSIC_DESIGN 7 regla 1). El par borrar/pintar tiene que seguir pegado al
;     HALT, dentro del borde superior, o la pieza se desgarra.
;   * Aqui NO se hace DI (MUSIC_DESIGN 7 regla 2). La interrupcion de la ULA es
;     un pulso corto: si se tapa no se retrasa, se PIERDE, y el HALT siguiente
;     espera una trama entera -> 25 fps. Se acepta el hueco de 889 T de la
;     rutina de la ROM. Este fichero no toca IY, asi que no necesita ninguna
;     pareja di/ei (interrupts-and-timing 1).
;   * Una trama que borra lineas va MUDA: ni siquiera un borrado de una fila
;     cabe con musica (MUSIC_DESIGN 6). Lo pide juego.asm por (musica_silencio).
;
; --- los dos drivers -------------------------------------------------------
;
; Coste de un semiperiodo, contado opcode a opcode sobre los dos bucles de
; abajo y confirmado midiendo T-estados en ZEsarUX:
;
;   mus_agudo (retardo DJNZ)     : 33 + 13 * C     C  = 1..255
;   mus_grave (retardo de 16 bits): 42 + 26 * HL   HL = 1..65535
;
; Se usa el driver DJNZ siempre que su constante quepa en un byte, porque su
; granularidad es de 13 T en vez de 26 y afina mejor; por debajo de ~523 Hz la
; constante pasa de 255 y hay que ir al de 16 bits. La frontera cae entre B4 y
; C5, la misma que en MUSIC_DESIGN 4.1.
;
; Esos dos numeros fijos (33 y 42) son de ESTOS bucles, no los 51,81 y 75,55 de
; MUSIC_DESIGN 4.1: aquellos venian de un banco de pruebas externo que nunca
; estuvo en el arbol. Un bucle mas corto necesita una constante de retardo mas
; larga para la misma nota, asi que las constantes de la tabla salen 1 o 2 por
; encima de las de la tabla de ejemplo de 4.1. Derivarlas del bucle que las
; toca es justo lo que mantiene la afinacion: copiar las del documento sobre un
; bucle mas corto desafinaria cada nota unos 4 cents hacia arriba.
;
; Error de afinacion peor de la tabla: -5,02 cents en G#5 (un semitono son 100,
; y el oido entrenado distingue 5-10 en el mejor de los casos). La tabla se
; genera y se vuelve a comprobar en tests/test_musica.py.

MUS_BIT     EQU %00010000   ; bit 4 del puerto $FE = altavoz
MUS_BORDE   EQU %00000000   ; bits 0-2 = color del BORDE. NEGRO, decidido en
                            ;  MUSIC_DESIGN 8: escribir $FE pone el borde
                            ;  quieras o no, y no se puede leer para
                            ;  conservarlo, asi que hay que elegir uno. Negro
                            ;  es el papel que ya usan el pozo y los paneles.
MUS_REPOSO  EQU MUS_BORDE   ; byte de reposo: borde negro y altavoz a 0

NOTA_SIL    EQU $FE         ; en la melodia: silencio que dura lo que diga
NOTA_FIN    EQU $FF         ; en la melodia: fin -> se vuelve al principio

; duraciones en TRAMAS de 50 Hz. Negra = 20 tramas = 400 ms -> 150 BPM, el
; tempo del original. La ultima trama de cada nota se calla siempre (hueco de
; articulacion, mas abajo), asi que ninguna duracion puede ser 1.
D_COR       EQU 10          ; corchea
D_NEG       EQU 20          ; negra
D_NGP       EQU 30          ; negra con puntillo
D_BLA       EQU 40          ; blanca

; indices en tabla_notas. Cromatica de A3 a C6: el rango que pide la melodia.
N_A3  EQU 0
N_AS3 EQU 1
N_B3  EQU 2
N_C4  EQU 3
N_CS4 EQU 4
N_D4  EQU 5
N_DS4 EQU 6
N_E4  EQU 7
N_F4  EQU 8
N_FS4 EQU 9
N_G4  EQU 10
N_GS4 EQU 11
N_A4  EQU 12
N_AS4 EQU 13
N_B4  EQU 14
N_C5  EQU 15
N_CS5 EQU 16
N_D5  EQU 17
N_DS5 EQU 18
N_E5  EQU 19
N_F5  EQU 20
N_FS5 EQU 21
N_G5  EQU 22
N_GS5 EQU 23
N_A5  EQU 24
N_AS5 EQU 25
N_B5  EQU 26
N_C6  EQU 27

; musica_frame -- avanza la melodia una trama y emite el tono de la nota actual.
;   Entrada: nada.  Salida: nada.
;   Preserva AF, BC, DE, HL, IX, IY -- el bucle sigue teniendo la pieza en
;   B, C e IX cuando esto vuelve (register-protocol). No hace DI ni EI.
;   Coste MEDIDO (cpu-step-over sobre las 28 notas de la tabla): 362 T de
;   gestion mas el relleno de tono. Peor relleno 47.920 T (B5) contra un
;   presupuesto de 48.000; peor llamada completa 48.378 T, en la trama en que
;   cambia de nota. Contra las 8.366 T de la peor pasada del juego quedan
;   13.144 T libres en la trama. Las tramas que callan cuestan 202 T (borrado
;   de lineas), 229 T (silencio de la melodia) o 187 T (ultima trama de nota).
musica_frame:
    push af
    push bc
    push de
    push hl

    ld hl, musica_silencio  ; la bandera es de UNA trama: se lee y se limpia
    ld a, (hl)              ;  SIEMPRE, aunque esta trama ya fuera a callar por
    ld (hl), 0              ;  otro motivo, o se quedaria pendiente y amordazaria
    ld c, a                 ;  tambien la siguiente. C != 0 -> muda.

    ld a, (musica_frames)   ; la nota anterior se agoto: toca la siguiente
    or a
    jr nz, mf_misma
    call mus_cargar         ; carga musica_nota y musica_frames de la melodia
mf_misma:
    ld hl, musica_frames
    dec (hl)                ; consumimos esta trama
    jr z, mf_fin            ; era la ULTIMA de la nota: se calla, y ese hueco de
                            ;  20 ms es lo que articula dos notas seguidas del
                            ;  MISMO tono (la melodia tiene tres parejas asi).
                            ;  Sin el, "A4 A4" suena como una sola nota larga.

    ld a, c
    or a
    jr nz, mf_fin           ; trama con borrado de lineas: muda (MUSIC_DESIGN 6)

    ld a, (musica_nota)
    cp NOTA_SIL
    jr z, mf_fin            ; silencio pedido por la propia melodia

    ld l, a                 ; entrada de la nota = tabla_notas + 4*nota
    ld h, 0
    add hl, hl
    add hl, hl              ; 28 notas x 4 bytes = 112: 4*nota cabe en un byte
    ld bc, tabla_notas      ; (esto se lleva C, pero ya hemos mirado la bandera)
    add hl, bc
    ld a, (hl)              ; selector: 0 = grave (16 bits), 1 = agudo (DJNZ)
    inc hl
    ld e, (hl)              ; constante de retardo, byte bajo
    inc hl
    ld d, (hl)              ;  ... y alto: solo lo usa el driver grave
    inc hl
    ld b, (hl)              ; numero de semiperiodos de esta nota
    or a
    jr z, mus_grave

; --- driver agudo: retardo DJNZ, granularidad 13 T -------------------------
; semiperiodo = 33 + 13*C.  A = byte del puerto, C = constante, E = cuenta.
; B queda libre porque el retardo lo gasta con djnz.
mus_agudo:
    ld c, e                 ; la constante cabe en un byte en este driver
    ld e, b                 ; E = cuenta de semiperiodos
    xor a                   ; A = MUS_REPOSO: borde negro, altavoz a 0
ma_medio:
    xor MUS_BIT             ;  7  conmutamos el altavoz
    out ($FE), a            ; 11  y lo sacamos; bits 0-2 = borde negro
    ld b, c                 ;  4  recargamos el retardo
ma_espera:
    djnz ma_espera          ; 13*(C-1) + 8
    dec e                   ;  4
    jr nz, ma_medio         ; 12
    jr mf_reposo

; --- driver grave: retardo de 16 bits, granularidad 26 T -------------------
; semiperiodo = 42 + 26*HL.  DE = constante, B = cuenta, C = byte del puerto.
; El byte del puerto vive en C y no en A porque el retardo necesita A para
; probar si HL ha llegado a cero (el Z80 no da flags en "dec hl").
mus_grave:
    ld c, MUS_REPOSO
mg_medio:
    ld a, c                 ;  4
    xor MUS_BIT             ;  7
    ld c, a                 ;  4
    out ($FE), a            ; 11
    ld h, d                 ;  4  HL = copia de trabajo de la constante
    ld l, e                 ;  4
mg_espera:
    dec hl                  ;  6
    ld a, h                 ;  4
    or l                    ;  4
    jr nz, mg_espera        ; 12
    djnz mg_medio           ; 13

mf_reposo:
    xor a                   ; el altavoz queda SIEMPRE en reposo: la cuenta de
    out ($FE), a            ;  semiperiodos puede ser impar, y dejarlo a 1 seria
                            ;  continua en el altavoz durante el resto de la
                            ;  trama. Tambien es lo unico que fija el borde.
mf_fin:
    pop hl                  ; espejo exacto de los push
    pop de
    pop bc
    pop af
    ret

; mus_cargar -- toma de la melodia la siguiente pareja (nota, duracion).
;   Entrada: nada.  Salida: (musica_nota) y (musica_frames) cargadas y
;   (musica_puntero) avanzado.  Preserva BC, DE, IX, IY. Destruye AF y HL.
;   BC importa: musica_frame lleva ahi la bandera de silencio cuando llama.
mus_cargar:
    ld hl, (musica_puntero)
    ld a, (hl)
    cp NOTA_FIN
    jr nz, mc_nota
    ld hl, melodia          ; se acabo la melodia: volvemos al principio. Una
    ld a, (hl)              ;  sola relectura basta, porque la primera entrada
mc_nota:                    ;  de melodia nunca es NOTA_FIN.
    ld (musica_nota), a
    inc hl
    ld a, (hl)              ; duracion en tramas; nunca 0 (ver D_COR y compania)
    ld (musica_frames), a
    inc hl
    ld (musica_puntero), hl
    ret

; musica_reiniciar -- devuelve el reproductor al principio de la melodia.
;   Entrada: nada.  Salida: nada.  Preserva AF, BC, DE, HL, IX, IY.
;   Deja las cuatro variables EXACTAMENTE en el valor inicial que declara
;   variables.asm, sea cual sea el estado del que venga.
;
;   La llama reiniciar_marcador (puntuacion.asm) al empezar cada partida, junto
;   con el resto del estado por-partida. Hace falta porque un fin de partida no
;   borra la RAM: Pantalla_Final salta a inicializar, que solo rehace SP, asi
;   que sin esto la melodia seguia donde la habia dejado la partida anterior.
;   NO toca MEJOR ni nada del marcador: eso es de la SESION, no de la partida.
;
;   OJO -- mus_cargar NO sirve para esto y no hay que llamarla en su lugar.
;   mus_cargar AVANZA la melodia, no la reinicia: lee la pareja que haya en
;   musica_puntero (solo rebobina si justo es NOTA_FIN), adelanta el puntero dos
;   bytes y deja musica_frames con la DURACION de esa nota en vez de 0. Y no
;   toca musica_silencio. Usarla aqui se comeria una nota de la melodia en cada
;   partida nueva -- empeorando el fallo en vez de arreglarlo -- y dejaria que
;   una bandera de borrado de la partida anterior amordazase la primera trama
;   de la nueva.
musica_reiniciar:
    push af
    push hl
    ld hl, melodia
    ld (musica_puntero), hl ; la proxima pareja por leer es la primera
    ld a, NOTA_SIL
    ld (musica_nota), a     ; todavia no suena nada
    xor a
    ld (musica_frames), a   ; 0 = agotada, asi que la primera llamada a
                            ;  musica_frame carga ya la primera pareja
    ld (musica_silencio), a ; y esta trama no viene amordazada de antes
    pop hl
    pop af
    ret

; --- tabla de notas --------------------------------------------------------
; Datos de solo lectura, detras del ultimo ret. Cuatro bytes por nota:
;   +0 selector de driver (0 = mus_grave, 1 = mus_agudo)
;   +1 constante de retardo, byte bajo
;   +2 constante de retardo, byte alto (0 en todo el tramo agudo)
;   +3 numero de semiperiodos = 48000 / semiperiodo, truncado
; La cuenta cambia con la nota para que el TIEMPO se mantenga constante: con
; una cuenta fija de 8 semiperiodos, A3 costaria 63.632 T y B5 solo 14.176
; (MUSIC_DESIGN 5). tests/test_musica.py vuelve a derivar los cuatro bytes de
; cada fila con las dos formulas de la cabecera y los compara byte a byte.
tabla_notas:
    DB 0 : DW 304 : DB  6   ;  0 A3    220.00 Hz ->  220.24 (+1.86c)   47671 T
    DB 0 : DW 287 : DB  6   ;  1 A#3   233.08 Hz ->  233.21 (+0.94c)   45019 T
    DB 0 : DW 271 : DB  6   ;  2 B3    246.94 Hz ->  246.90 (-0.32c)   42523 T
    DB 0 : DW 256 : DB  7   ;  3 C4    261.63 Hz ->  261.27 (-2.34c)   46881 T
    DB 0 : DW 241 : DB  7   ;  4 C#4   277.18 Hz ->  277.43 (+1.52c)   44151 T
    DB 0 : DW 228 : DB  8   ;  5 D4    293.66 Hz ->  293.13 (-3.14c)   47755 T
    DB 0 : DW 215 : DB  8   ;  6 D#4   311.13 Hz ->  310.72 (-2.24c)   45051 T
    DB 0 : DW 203 : DB  9   ;  7 E4    329.63 Hz ->  328.95 (-3.58c)   47875 T
    DB 0 : DW 191 : DB  9   ;  8 F4    349.23 Hz ->  349.44 (+1.05c)   45067 T
    DB 0 : DW 180 : DB 10   ;  9 F#4   369.99 Hz ->  370.61 (+2.86c)   47215 T
    DB 0 : DW 170 : DB 10   ; 10 G4    392.00 Hz ->  392.20 (+0.91c)   44615 T
    DB 0 : DW 160 : DB 11   ; 11 G#4   415.30 Hz ->  416.47 (+4.84c)   46217 T
    DB 0 : DW 151 : DB 12   ; 12 A4    440.00 Hz ->  441.03 (+4.04c)   47611 T
    DB 0 : DW 143 : DB 12   ; 13 A#4   466.16 Hz ->  465.43 (-2.74c)   45115 T
    DB 0 : DW 135 : DB 13   ; 14 B4    493.88 Hz ->  492.68 (-4.22c)   46171 T
    DB 1 : DW 255 : DB 14   ; 15 C5    523.25 Hz ->  522.70 (-1.82c)   46867 T
    DB 1 : DW 240 : DB 15   ; 16 C#5   554.37 Hz ->  555.03 (+2.07c)   47290 T
    DB 1 : DW 227 : DB 16   ; 17 D5    587.33 Hz ->  586.46 (-2.56c)   47739 T
    DB 1 : DW 214 : DB 17   ; 18 D#5   622.25 Hz ->  621.67 (-1.63c)   47850 T
    DB 1 : DW 202 : DB 18   ; 19 E5    659.26 Hz ->  658.14 (-2.93c)   47857 T
    DB 1 : DW 190 : DB 19   ; 20 F5    698.46 Hz ->  699.16 (+1.75c)   47552 T
    DB 1 : DW 179 : DB 20   ; 21 F#5   739.99 Hz ->  741.53 (+3.59c)   47195 T
    DB 1 : DW 169 : DB 21   ; 22 G5    783.99 Hz ->  784.75 (+1.68c)   46825 T
    DB 1 : DW 160 : DB 22   ; 23 G#5   830.61 Hz ->  828.21 (-5.02c)   46481 T
    DB 1 : DW 150 : DB 24   ; 24 A5    880.00 Hz ->  882.50 (+4.91c)   47587 T
    DB 1 : DW 142 : DB 25   ; 25 A#5   932.33 Hz ->  931.35 (-1.82c)   46970 T
    DB 1 : DW 134 : DB 27   ; 26 B5    987.77 Hz ->  985.92 (-3.25c)   47920 T
    DB 1 : DW 126 : DB 28   ; 27 C6   1046.50 Hz -> 1047.28 (+1.28c)   46783 T

; --- melodia ---------------------------------------------------------------
; Korobeiniki completa: la parte A (8 compases, la que todo el mundo reconoce)
; y la parte B (8 compases, la lenta), y al llegar a NOTA_FIN se vuelve al
; principio. 16 compases de 4/4 a 80 tramas cada uno = 1.280 tramas = 25,6 s
; por vuelta. 54 notas, 110 bytes: la imagen tiene RAM libre de sobra por
; encima, asi que no hay ningun motivo para recortar la melodia
; (MUSIC_DESIGN 8 punto 3).
;
; Parejas (nota, duracion en tramas). Cada compas es una linea; la suma de
; cada compas es 80 y tests/test_musica.py lo comprueba.
melodia:
; -- parte A ----------------------------------------------------------------
    DB N_E5,D_NEG : DB N_B4,D_COR : DB N_C5,D_COR : DB N_D5,D_NEG : DB N_C5,D_COR : DB N_B4,D_COR
    DB N_A4,D_NEG : DB N_A4,D_COR : DB N_C5,D_COR : DB N_E5,D_NEG : DB N_D5,D_COR : DB N_C5,D_COR
    DB N_B4,D_NGP : DB N_C5,D_COR : DB N_D5,D_NEG : DB N_E5,D_NEG
    DB N_C5,D_NEG : DB N_A4,D_NEG : DB N_A4,D_BLA
    DB N_D5,D_NGP : DB N_F5,D_COR : DB N_A5,D_NEG : DB N_G5,D_COR : DB N_F5,D_COR
    DB N_E5,D_NGP : DB N_C5,D_COR : DB N_E5,D_NEG : DB N_D5,D_COR : DB N_C5,D_COR
    DB N_B4,D_NEG : DB N_B4,D_COR : DB N_C5,D_COR : DB N_D5,D_NEG : DB N_E5,D_NEG
    DB N_C5,D_NEG : DB N_A4,D_NEG : DB N_A4,D_BLA
; -- parte B ----------------------------------------------------------------
    DB N_E5,D_BLA : DB N_C5,D_BLA
    DB N_D5,D_BLA : DB N_B4,D_BLA
    DB N_C5,D_BLA : DB N_A4,D_BLA
    DB N_GS4,D_BLA : DB N_B4,D_BLA
    DB N_E5,D_BLA : DB N_C5,D_BLA
    DB N_D5,D_BLA : DB N_B4,D_BLA
    DB N_C5,D_NEG : DB N_E5,D_NEG : DB N_A5,D_BLA
    DB N_GS5,D_BLA : DB NOTA_SIL,D_BLA

    DB NOTA_FIN, 0          ; vuelve a melodia. La duracion de esta pareja no
                            ;  se lee nunca: mus_cargar mira la nota primero.
