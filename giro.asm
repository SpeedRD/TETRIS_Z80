GIRAR:
;--------------------------------------------------------------------
;Gira la pieza actual: valida, aplica retranqueo (wall kick) y CONFIRMA
;aqui dentro. El llamante NO debe volver a comprobar el resultado.
;
;No lee el teclado ni espera a que se suelte ninguna tecla: el bucle
;llama a leer_teclas una vez por pasada y pasa la direccion en A. Leer
;aqui dejaria la pieza invisible entre el borrado y el repintado.
;
;Param. de Entrada: IX = registro actual, B = fila, C = columna,
;                   (Medio) = columna, A = 0 girar izquierda (Q),
;                   A distinto de 0 girar derecha (W)
;Param. de Salida : si cabe -> IX = registro nuevo, C y (Medio) = columna nueva
;                   si no cabe -> IX, C y (Medio) intactos
;Destruye AF y DE. Preserva B, HL, IY. C es SALIDA si el giro cabe.
;--------------------------------------------------------------------
    PUSH HL
    OR  A
    JR  NZ, giro_der
    LD  D,(IX + 9)          ; +8/+9 = sucesor al girar a la izquierda
    LD  E,(IX + 8)          ;  (byte bajo primero)
    JR  giro_probar
giro_der:
    LD  D,(IX + 11)         ; +10/+11 = sucesor al girar a la derecha
    LD  E,(IX + 10)

giro_probar:
    PUSH IX                 ; estado al que volver si no cabe en ningun sitio
    LD  A,(IX + 1)          ; ancho de la pieza VIEJA: leerlo antes de mover IX
    LD  IX, DE              ; IX = estado candidato (instruccion falsa, ver
                            ;  assembler-conventions: LD IXH,D : LD IXL,E)
    SUB (IX + 1)            ; A = ancho_viejo - ancho_nuevo, con signo (-3..+3)
    JP  P, giro_media
    INC A                   ; los negativos deben redondear hacia cero, no hacia
giro_media:                 ;  -infinito, para que girar e desgirar vuelva a la
    SRA A                   ;  misma columna. A = (viejo-nuevo)/2
    ADD A, C                ; anclamos por el centro, no por la esquina superior
    LD  E, A                ; E = columna base recentrada: aun es una CANDIDATA
    LD  HL, giro_kicks

giro_bucle:
    LD  A,(HL)
    INC HL
    CP  $80                 ; centinela: se han agotado las candidatas
    JR  Z, giro_deshacer
    ADD A, E                ; columna candidata = base recentrada + retranqueo
    LD  C, A                ; las dos pruebas leen la fila de B y la columna de C
    CALL en_rango           ; PRUEBA 1 geometria: ¿cabe entera en las columnas
    OR  A                   ;  7-24? comprobar no puede ver esto
    JR  NZ, giro_bucle
    CALL comprobar          ; PRUEBA 2 solape: A=0 cabe, A=1 choca con un bloque
    OR  A                   ;  o con el borde. Preserva BC/DE/HL/IX/IY.
    JR  NZ, giro_bucle
    LD  A, C
    LD  (Medio), A          ; CONFIRMAMOS tambien la columna en memoria: el bucle
    POP DE                  ;  recarga C desde Medio y deshariamos el retranqueo.
    JR  giro_fin            ; descartamos el IX viejo: vale el nuevo

giro_deshacer:
    POP IX                  ; no cabia en ningun sitio: recuperamos la forma...
    LD  A,(Medio)
    LD  C, A                ; ...y la columna. (Medio) es la copia de respaldo de C.
giro_fin:
    POP HL
    RET

giro_kicks: DB 0, -1, 1, -2, 2, $80   ; en el sitio, luego 1 y luego 2 celdas a
                                      ; cada lado. Datos de solo lectura,
                                      ; despues del RET: nunca se ejecutan.
