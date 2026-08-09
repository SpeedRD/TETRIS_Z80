; Programa que calcula la caida de la pieza


; Constantes para el cálculo del tiempo
TIEMPO_BASE       EQU 0x11FF  ; Tiempo base de espera
REDUCCION_TIEMPO  EQU 10      ; Reducción de tiempo por nivel
TIEMPO_MINIMO     EQU 200     ; Tiempo mínimo de espera

; Variables de tiempo
TIEMPO_CAIDA      EQU 0x7000  ; Dirección de la variable del tiempo de caída
NIVEL_ACTUAL      EQU 0x7002  ; Dirección de la variable del nivel actual

; Función para calcular y esperar el tiempo de caída
Tiempo:
    ; Guardar registros que vamos a usar
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    ; Calcular el tiempo de caída basado en el nivel actual
    LD A, (NIVEL_ACTUAL)
    LD HL, TIEMPO_BASE
    SUB A
    LD B, 0
    LD C, A
    LD DE, REDUCCION_TIEMPO
    LD A, 0
    SBC HL, BC ; Calcular el tiempo de caída: TIEMPO_BASE - (NIVEL_ACTUAL * REDUCCION_TIEMPO)
    LD A, H
    OR A
    JR NZ, SkipMinCheck
    CP L
    JR NC, SkipMinCheck
    LD HL, TIEMPO_MINIMO

SkipMinCheck:
    LD (TIEMPO_CAIDA), HL ; Guardar el tiempo calculado

    ; Esperar el tiempo de caída

EsperarCaida:
    LD DE, (TIEMPO_CAIDA)
    
EsperarLoop:
    DEC DE
    LD A, D
    OR A
    JR NZ, EsperarLoop
    LD A, E
    OR A
    JR NZ, EsperarLoop

    ; Restaurar registros usados
    POP HL
    POP DE
    POP BC
    POP AF

    RET

; Función para inicializar el tiempo de caída
InicializarTiempo:
    LD HL, TIEMPO_BASE
    LD (TIEMPO_CAIDA), HL
    RET
