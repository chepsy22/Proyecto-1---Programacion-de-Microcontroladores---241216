/*
* Proyecto1-PuC-241216.asm
*
* Creado: 03-03-2026
* Autor : Jose Carlos Flores Rosales
* Descripción: Reloj digital con 4 displays usando maquina de estados finitos para ver fecha y hora
* Se multiplexaron 4 displays de 7 segmentos
* 3 botones (Arriba, Abajo y Cambio de Modo)
* Antirebote con software
* 8 modos: Hora, Fecha, Cambio de Hora, Cambio de Minuto,
* 8 modos: Cambio de Mes, Cambio de Fecha, Ajustar hora de alarma, Ajustar minuto de alarma
*/
/****************************************/
.include "M328PDEF.inc"     
.dseg
.org    SRAM_START

.cseg
// Tabla de Vectores de Interrupción 
.org 0x0000
    RJMP SETUP

.org 0x0008             ; PCINT1 (Puerto C)
    RJMP ISR_PCINT1     

.org 0x0020             ; Timer0 OVF
    RJMP ISR_TIMER0     

/****************************************/
SETUP:
/****************************************/
// Configuración de la pila
    LDI     R16, LOW(RAMEND)
    OUT     SPL, R16
    LDI     R16, HIGH(RAMEND)
    OUT     SPH, R16

// Puerto B - MUX (Transistores en PB0-PB3) y Alarma (PB5)
    LDI R16, 0x2F       ; 0b0010_1111 
    OUT DDRB, R16
    LDI R16, 0x00       ; inicia todo apagado
    OUT PORTB, R16

// Puerto C - Botones (A0-A2) y LEDs de Modo (A3-A5)
    LDI R16, 0x38       ; 0b0011_1000 
    OUT DDRC, R16
    LDI R16, 0x07       ; 0b0000_0111 (activa pull up interno en A0-A2)
    OUT PORTC, R16

// Puerto D - Display de 7 segmentos
    LDI R16, 0xFF       ; 0b1111_1111
    OUT DDRD, R16

// Interrupciones PCINT1 para el Puerto C (A0, A1, A2)
    LDI R16, (1 << PCIE1)      
    STS PCICR, R16
    LDI R16, (1 << PCINT8) | (1 << PCINT9) | (1 << PCINT10) 
    STS PCMSK1, R16

// Configuracion de Timer0
    LDI R16, 100
    OUT TCNT0, R16
    LDI R16, 0x04              ; prescaler 256
    OUT TCCR0B, R16
    LDI R16, (1 << TOIE0)      
    STS TIMSK0, R16

// Inicializar variables
    LDI R17,  1     ; unidad de mes
    CLR R18         ; decena de mes
    CLR R19         ; unidades (segundos)
    CLR R20         ; unidad de minutos
    CLR R21         ; decenas de minutos
    CLR R22         ; unidad de hora
    CLR R23         ; decena de hora
    CLR R24         ; milisegundos
    LDI R25, 3      ; bandera de mux
    CLR R26         ; modo
    CLR R27         ; anti rebote por delay 
    LDI R28, 1      ; unidad de dia
    CLR R29         ; decena de dia
    
// buffers
    CLR R2          
    CLR R3
    CLR R4
    CLR R5
	CLR R6			; unidad minuto de alarma
	CLR R7			; decena minuto de alarma
	CLR R8			; unidad hora de alarma
	CLR R9			; decena hora de alarma
	CLR R10			; estado de alarma (0=apagada, 1=armada, 2=sonando)

    SEI             ; habilitar interrupciones globales
    
/****************************************/
MAIN_LOOP:
// LEDs indicadoras de modo
    SBRC R26, 0           
    SBI PORTC, PC3        
    SBRS R26, 0           
    CBI PORTC, PC3        

    SBRC R26, 1
    SBI PORTC, PC4
    SBRS R26, 1
    CBI PORTC, PC4

    SBRC R26, 2
    SBI PORTC, PC5
    SBRS R26, 2
    CBI PORTC, PC5

// Segun el modo, se asignan valores a los buffers
    CPI R26, 1
    BREQ mostrar_fecha
    CPI R26, 4
    BREQ mostrar_fecha
    CPI R26, 5
    BREQ mostrar_fecha
	CPI R26, 6
	BREQ mostrar_alarma
	CPI R26, 7
	BREQ mostrar_alarma
    RJMP mostrar_hora

// Si queremos mostrar hora, se usan las variables correspondientes en los buffers correspondientes.
mostrar_hora:
    MOV R5, R23     
    MOV R4, R22     
    MOV R3, R21     
    MOV R2, R20     
    RJMP MAIN_LOOP

// Si queremos mostrar fecha, se usan las variables correspondientes en los buffers correspondientes.
mostrar_fecha:
    MOV R5, R29     
    MOV R4, R28     
    MOV R3, R18     
    MOV R2, R17    
	RJMP MAIN_LOOP 

// Si queremos mostrar la configuracion de alarma, se usan sus variables unicas ajustables (empiezan en 00:00 y no avanzan, por eso no se usan las de la hora)
mostrar_alarma:
    MOV R5, R9      
    MOV R4, R8      
    MOV R3, R7      
    MOV R2, R6      
    RJMP MAIN_LOOP

/****************************************/
// NON-Interrupt subroutines
dispup:
    PUSH R15
    LDI ZH, HIGH(Table7seg << 1)
    LDI ZL, LOW(Table7seg << 1)
    ADD ZL, R16
    CLR R15
    ADC ZH, R15
    LPM R16, Z                 
    POP R15               
    RET 

// logica del avance del reloj
// se empieza por lo mas basico (milisegundos)
clklogic:
    INC R24
    CPI R24, 244          ; overflow de timer0 para 1 segundo
    BREQ seguir_segundos  ; al hacer overflow se pasa a la logica de segundos
    RJMP tmrend_logic     
    
// logica de segundos por overflow de milisegundos
seguir_segundos:
    CLR R24               ; reinicia los milisegundos a 0
    INC R19               ; sube (o avanza) un segundo
    CPI R19, 2            ; 2 usado para debugear, al presentar son 60 (segundos en un minuto)     
    BREQ seguir_minutos   ; al hacer overflow se pasa a la logica de minutos
    RJMP tmrend_logic     
    
// logica de unidad de minuto por overflow de minutos.
seguir_minutos:
    CLR R19              ; reinicia los segundos a 0  
    INC R20              ; sube (o avanza) un minuto 
    CPI R20, 10          ; overflow de unidad de minuto 
    BRNE salto_tmrend    ; si no se ha llegado al overflow, salimos de la rutina
    CLR R20				 ; al hacer overflow se resetean las unidades a 0
// logica de decenas de minutos por overflow de unidades
    INC R21              ; sube (o avanza) una decena de minuto
    CPI R21, 6           ; overflow de decena de minuto
    BRNE salto_tmrend    ; si no se ha llegado al overflow, salimos de la rutina 
    CLR R21				 ; al hacer overflow se resetean las decenas a 0
// logica de unidades de hora 
    INC R22              ; sube (o avanza) una hora 
    CPI R22, 10          ; overflow de unidad de hora 
    BREQ carry_hora      ; al hacer overflow, salta a sumar uno a decena de hora 
// logica de 24 horas
    CPI R23, 2			 ; comparamos la decena con 2
    BRNE salto_tmrend    ; si no es 2, no seguimos a la siguiente comparacion
    CPI R22, 4           ; si si era 2, compara con 4
    BRNE salto_tmrend	 ; si no era 4, salimos de la rutina
// reinicia decena y unidad de hora a 00:00
    CLR R22              
    CLR R23
// overflow por media noche
    INC R28              ; al llegar a las 00:00, se suma (o avanza) una unidad de dia   
    CPI R28, 10			 ; overflow de unidad de dia
    BRNE check_max_dias	 ; si no hay overflow de unidad, pasa a detectar el mes
    CLR R28				 ; al hacer overflow se resetean las unidades a 0
    INC R29              ; sube (o avanza) una decena

// BRNE fuera de rango, por lo que se uso un puente
salto_tmrend:
    RJMP tmrend_logic
// logica de numero de dias en un mes (pasiva, simplemente avanza de manera natural)
check_max_dias:
// revisa que sea febrero
    CPI R18, 0            ; revisa que la decena sea 0 (unicamente unidades)
    BRNE check_meses_30   ; si no es 0, pasa a la logica de los proximos meses
    CPI R17, 2            ; revisa que la unidad sea 2 (segundo mes febrero)
    BRNE check_meses_30   ; si no es Febrero, salta a revisar otros meses
    CPI R29, 2            ; decena de día = 2
    BRNE tmrend_logic		
    CPI R28, 8          
    BREQ reset_nuevo_mes  ; se compara que sea el dia 28 (de serlo, regresa el dia a 01)
    RJMP tmrend_logic

check_meses_30:
// revisa que sea un mes de 30 dias (04, 06, 09, 11)
// empieza con noviembre (11)
    CPI R18, 1            
    BRNE check_otros_30	  ; si no empieza con 1 el mes, revisa el resto
    CPI R17, 1            
    BREQ limite_31        ; si es 11, el limite para saltar es el dia 31
    RJMP check_meses_31   ; si la decena es 1 pero no es noviembre, tiene 31 dias

check_otros_30:
// revisa el resto de meses con 30 dias
    CPI R17, 4
    BREQ limite_31
    CPI R17, 6
    BREQ limite_31
    CPI R17, 9
    BREQ limite_31
    RJMP check_meses_31   ; si no es ninguno, tiene 31 dias

limite_31:
// define el limite de overflow como 31 para los meses de 30
    CPI R29, 3            ; 3 decenas
    BRNE tmrend_logic
    CPI R28, 1            ; 1 unidad
    BREQ reset_nuevo_mes
    RJMP tmrend_logic

check_meses_31:
// logica usada para el resto de meses (32 overflow)
    CPI R29, 3            ; 3 decenas
    BRNE tmrend_logic
    CPI R28, 2            ; 2 unidades
    BREQ reset_nuevo_mes
    RJMP tmrend_logic

reset_nuevo_mes:
// reinicia el dia a 1 en cada mes nuevo
    LDI R16, 1
    MOV R28, R16
    CLR R29
    
// sube (o suma) 1 a la unidad de mes)
    INC R17               
    CPI R17, 10
    BRNE check_max_meses
    CLR R17
    INC R18               


check_max_meses:
// overflow de anho (13)
    CPI R18, 1		
    BRNE tmrend_logic
    CPI R17, 3
    BRNE tmrend_logic

// reset de anho (01)
    LDI R16, 1
    MOV R17, R16
    CLR R18
    RJMP tmrend_logic

carry_hora:
// acarreo de horas 
    CLR R22               
    INC R23               
    RJMP check_max_dias
    
tmrend_logic:
    RET
	
// trigger de alarma
trigger_alarma:
    MOV R16, R10          ; cargar estado de alarma
    CPI R16, 1            ; revisa si esta armada (1)
    BRNE fin_trigger      ; si no esta armada, sale de la rutina

    MOV R16, R19          ; carga segundos
    CPI R16, 0            ; al coincidir los segundos con 0 (o empezar el nuevo minuto) suena
    BRNE fin_trigger      

// compara horas y minutos
    CP R20, R6            
    BRNE fin_trigger
    CP R21, R7            
    BRNE fin_trigger
    CP R22, R8            
    BRNE fin_trigger
    CP R23, R9            
    BRNE fin_trigger

// al coincidir todo, suena
    LDI R16, 2            ; cambia estado a 2 (sonando)
    MOV R10, R16
    CLR R26               ; regresa a modo 0 (para ver la hora)

fin_trigger:
    RET             

/****************************************/
// Interrupt routines
ISR_PCINT1:
    PUSH R16
    IN R16, SREG
    PUSH R16

// override de alarma sonando
    MOV R16, R10
    CPI R16, 2            ; revisa si esta sonando
    BRNE antibounce     ; si no suena va al delay

// si esta sonando, se hace un override para que todos los botones permitan apagarla
    LDI R16, 1            ; se regresa a 1 (armada)
    MOV R10, R16
    CLR R26               ; modo 0
    LDI R16, 100
    MOV R27, R16          ; antirebote por perdida de tiempo (delay)
    RJMP fin_botones      ; cancela el resto de acciones de los botones

antibounce:
// revisa el delay 
// revisa que la variable de perder tiempo este en 0, al estarlo lee el boton. si no lo esta, lo toma como rebote
    CPI R27, 0            
    BREQ leer_botones     
    RJMP fin_botones      

leer_botones:
// modo PC2 
    SBIC PINC, PC2        
    RJMP check_arriba     
// recargamos el valor del delay y aplicamos mascara a modos, cambiamos de modo
    LDI R16, 100           
    MOV R27, R16
    INC R26               
    ANDI R26, 0x07    
	
// armar alarma
	LDI R16, 1
	MOV R10, R16    
    RJMP fin_botones      

// arriba PC0
check_arriba:
    SBIC PINC, PC0        
    RJMP check_abajo

    LDI R16, 100           
    MOV R27, R16
// llama rutinas para comprobar que valor debemos incrementar segun el modo en el que se este
    CPI R26, 2            
    BREQ salto_up_hora
    CPI R26, 3            
    BREQ salto_up_minuto
	CPI R26, 5
	BREQ salto_up_mes
	CPI R26, 4
	BREQ salto_up_dia
	CPI R26, 6
	BREQ salto_up_alarma_hora
	CPI R26, 7
	BREQ salto_up_alarma_min
    RJMP fin_botones      

// BRNE fuera de rango, se usaron puentes
salto_up_hora:
    RJMP up_hora
salto_up_minuto:
    RJMP up_minuto
salto_up_mes:
	RJMP up_mes
salto_up_dia:
	RJMP up_dia
salto_up_alarma_hora:
	RJMP up_alarma_hora
salto_up_alarma_min:
	RJMP up_alarma_min

// abajo PC0
check_abajo:
    SBIC PINC, PC1        
    RJMP fin_botones      
    
    LDI R16, 100           
    MOV R27, R16
//llama rutinas para comprobar que valor debemos decrementar segun el modo en el que se este
    CPI R26, 2            
    BREQ salto_down_hora
    CPI R26, 3            
    BREQ salto_down_minuto
	CPI R26, 5
	BREQ salto_down_mes
	CPI R26, 4
	BREQ salto_down_dia
	CPI R26, 6
	BREQ salto_down_alarma_hora
	CPI R26, 7
	BREQ salto_down_alarma_min
    RJMP fin_botones      

// BRNE fuera de rango, se usaron puentes
salto_down_hora:
    RJMP down_hora
salto_down_minuto:
    RJMP down_minuto
salto_down_mes:
	RJMP down_mes
salto_down_dia:
	RJMP down_dia
salto_down_alarma_hora:
	RJMP down_alarma_hora
salto_down_alarma_min:
	RJMP down_alarma_min

// logicas de incremento
up_hora:
// aumenta la hora y comprueba que no se hayan superado las 24
    INC R22                 
    CPI R23, 2              
    BREQ filtro_24_horas    
    RJMP suma_normal        

filtro_24_horas:
// si las decenas eran 2, revisa si unidades son 4. de ser 24, salta a reiniciar.
    CPI R22, 4              
    BREQ reinicio_24_horas  
    RJMP fin_botones        

reinicio_24_horas:
// reinicia a 00:00 la hora
    CLR R22                 
    CLR R23                 
    RJMP fin_botones        

suma_normal:
// suma normal y si se llega a 10 unidades, se suma una decena
    CPI R22, 10             
    BREQ sumar_decena_hora  
    RJMP fin_botones        

sumar_decena_hora:
// se resetean las unidades y se suma una hora
    CLR R22                 
    INC R23                 
    RJMP fin_botones

up_minuto:
// sube el minuto y comprueba si se hace overflow de unidades
    INC R20                 
    CPI R20, 10             
    BREQ sumar_decena_min   
    RJMP fin_botones        

sumar_decena_min:
// se resetean las unidades y se suma un minuto
    CLR R20                 
    INC R21                 
    CPI R21, 6              
    BREQ reset_decena_min   
    RJMP fin_botones        

reset_decena_min:
// si se llego a 60, reinicia la decena y unidad a 00
    CLR R21                 
    RJMP fin_botones

// logica de decremento
down_hora:
// reduce la hora y comprueba el underflow
    CPI R23, 0              
    BREQ check_unidades_00  
    RJMP resta_normal       

check_unidades_00:
// si ambos son 00, se regresa a 23 por underflow
    CPI R22, 0              
    BREQ forzar_23          
    RJMP resta_normal       

forzar_23:
// carga el 23 de underflow a las horas
    LDI R16, 2
    MOV R23, R16            
    LDI R16, 3
    MOV R22, R16            
    RJMP fin_botones        

resta_normal:
// resta normal a la unidad de hora y si se llega a 255, se hace underflow
    DEC R22                 
    CPI R22, 255            
    BREQ prestar_hora       
    RJMP fin_botones        

prestar_hora:
// unidad pasa a ser 9 y resta 1 a decena
    LDI R16, 9              
    MOV R22, R16            
    DEC R23                 
    RJMP fin_botones        

down_minuto:
// resta a la unidad minuto y revisa underflow
    DEC R20                 
    CPI R20, 255            
    BREQ prestar_minuto     
    RJMP fin_botones        

prestar_minuto:
// underflow por minuto, si la decena tambien hace underflow resta
    LDI R16, 9              
    MOV R20, R16
    DEC R21                 
    CPI R21, 255            
    BREQ underflow_minuto   
    RJMP fin_botones        

underflow_minuto:
// underflow por minuto, decena pasa a ser 5
    LDI R16, 5              
    MOV R21, R16
    RJMP fin_botones

fin_botones:
    POP R16
    OUT SREG, R16
    POP R16
    RETI

// logica de mes
up_mes:
    INC R17               ; suma un mes
    CPI R17, 10			  ; comprueba overflow de unidad de mes
    BREQ carry_up_mes
    RJMP check_limit_mes

carry_up_mes:
// overflow de unidad de mes, suma 1 a decena
    CLR R17
    INC R18
    RJMP check_limit_mes

check_limit_mes:
    CPI R18, 1            ; revisa si es 1
    BREQ check_unidad_mes ; si es 1, revisa unidad
    RJMP validar_dia_por_mes ; dias maximos

check_unidad_mes:
    CPI R17, 3            ; overflow de diciembre a enero
    BREQ reset_mes        ; si es mes 13, se reinicia
    RJMP validar_dia_por_mes ; dias maximos

reset_mes:
    LDI R16, 1            ; regresa a enero 01
    MOV R17, R16
    CLR R18
    RJMP validar_dia_por_mes ; dias maximos

down_mes:
    DEC R17
    CPI R17, 255          ; dnderflow unidad
    BREQ borrow_down_mes
    CPI R18, 0            ; revisa si decena es 0
    BREQ check_zero_mes   ; si es 0, revisa si se llego al mes 00
    RJMP validar_dia_por_mes ; dias maximos

check_zero_mes:
    CPI R17, 0            ; si se llega al mes 00 hace underflow a 12
    BREQ forzar_mes_12    ; 
    RJMP validar_dia_por_mes ; dias maximos

borrow_down_mes:
// acarreo negativo por resta de unidad
    LDI R16, 9
    MOV R17, R16
    DEC R18
    RJMP validar_dia_por_mes ; dias maximos

forzar_mes_12:
// underflow a diciembre
    LDI R16, 1
    MOV R18, R16          
    LDI R16, 2
    MOV R17, R16          
    RJMP validar_dia_por_mes ; dias maximos

// revision de dias maximos (activa, se usa al ajustar de mes para cambiar el limite de dias)
validar_dia_por_mes:
// revisa si es febrero
    CPI R18, 0
    BRNE val_meses_30
    CPI R17, 2
    BRNE val_meses_30
// si es febrero, revisa si los dias superan los 28 maximos
    CPI R29, 3
    BREQ forzar_29_feb    ; si la decena es 3, llama a subrutina correctora
    RJMP fin_botones      

forzar_29_feb:
    LDI R16, 2            ; Forzar día a 29
    MOV R29, R16
    LDI R16, 9
    MOV R28, R16
    RJMP fin_botones

val_meses_30:
// usa la misma logica de revision de mes de 30 dias, empezando por noviembre
    CPI R18, 1           
    BRNE val_otros_30
    CPI R17, 1
    BREQ clamp_30
    RJMP fin_botones      ; si es 10 o 12, tiene 31 dias

val_otros_30:
// revisa el resto de meses con 30 dias
    CPI R17, 4
    BREQ clamp_30
    CPI R17, 6
    BREQ clamp_30
    CPI R17, 9
    BREQ clamp_30
    RJMP fin_botones      ; si no es ninguno, tiene 31 dias

clamp_30:
// para los meses de 30 dias, asegura que el dia no pueda ser 31
    CPI R29, 3            
    BREQ clamp_30_unidad  
    RJMP fin_botones      

clamp_30_unidad:
// despues de revisar si son 3 decenas, revisa si la unidad es 1
    CPI R28, 1            
    BREQ forzar_30_dia    
    RJMP fin_botones      

forzar_30_dia:
// de ser 1 (31), baja a 30
    LDI R16, 0         
    MOV R28, R16
    RJMP fin_botones

// logica de dias 
// subir dias
up_dia:
// sube un dia, si hace overflow de decena tiene acarreo
    INC R28
    CPI R28, 10
    BREQ carry_up_dia
    RJMP check_limite_boton_dia

carry_up_dia:
// acarreo por overflow de decena, resetea unidades
    CLR R28
    INC R29
    RJMP check_limite_boton_dia

// logica de dias maximos, activa (donde el mes no cambia por llegar al overflow del dia durante un ajuste)
check_limite_boton_dia:
// revisa si es febrero
    CPI R18, 0            
    BRNE check_30_boton   
    CPI R17, 2            
    BRNE check_30_boton   
// si es febrero los dias no pueden pasar de 29
    CPI R29, 3            
    BREQ reset_dia_boton
    RJMP fin_botones

check_30_boton:
// revisa si es un mes de 30 dias, empezando por noviembre
    CPI R18, 1            
    BRNE check_otros_30_btn
    CPI R17, 1            
    BREQ limite_31_boton  
    RJMP check_31_boton   

check_otros_30_btn:
// revisa el resto de meses de 30 dias
    CPI R17, 4
    BREQ limite_31_boton
    CPI R17, 6
    BREQ limite_31_boton
    CPI R17, 9
    BREQ limite_31_boton
    RJMP check_31_boton   

limite_31_boton:
// limite de 30 dias, no se pueden poner 31
    CPI R29, 3            
    BREQ limite_30_decena
    RJMP fin_botones
limite_30_decena:
    CPI R28, 1            
    BREQ reset_dia_boton
    RJMP fin_botones

check_31_boton:
// limite de 31 dias, no se pueden poner 32
    CPI R29, 3            
    BREQ limite_31_decena
    RJMP fin_botones
limite_31_decena:
    CPI R28, 2            
    BREQ reset_dia_boton
    RJMP fin_botones

reset_dia_boton:
// regresa al dia 1
    LDI R16, 1            
    MOV R28, R16
    CLR R29
    RJMP fin_botones

// bajar dias
down_dia:
// resta dias y hace underflow
    DEC R28
    CPI R28, 255          
    BREQ borrow_down_dia
    CPI R29, 0            
    BREQ check_zero_dia   
    RJMP fin_botones      

borrow_down_dia:
// acarreo de decena por underflow de unidades
    LDI R16, 9
    MOV R28, R16
    DEC R29
    RJMP fin_botones

check_zero_dia:
// revisa si el dia es 0 y revisa el dia maximo del mes
    CPI R28, 0           
    BREQ set_max_dia     
    RJMP fin_botones

set_max_dia:
// comprueba dias maximos por mes
    CPI R18, 0            
    BRNE techo_30
    CPI R17, 2
    BRNE techo_30
// dia maximo de febrero es 29
    LDI R16, 2
    MOV R29, R16          
    LDI R16, 9
    MOV R28, R16          
    RJMP fin_botones

techo_30:
// revisia noviembre con dia maximo 30
    CPI R18, 1            
    BRNE otros_techo_30
    CPI R17, 1
    BREQ forzar_30
    RJMP forzar_31

otros_techo_30:
// revisa el resto de meses con dia maximo 30
    CPI R17, 4
    BREQ forzar_30
    CPI R17, 6
    BREQ forzar_30
    CPI R17, 9
    BREQ forzar_30
    RJMP forzar_31

forzar_30:
// hace que el dia sea 30 si se hace underflow
    LDI R16, 3
    MOV R29, R16          
    LDI R16, 0
    MOV R28, R16          
    RJMP fin_botones

forzar_31:
// hace que el dia sea 31 si se hace underflow
    LDI R16, 3
    MOV R29, R16          
    LDI R16, 1
    MOV R28, R16          
    RJMP fin_botones

// logica de alarma
// sumar a alarma
up_alarma_hora:
// sube la hora de la alarma y revisa si hay 2 decenas
    INC R8                  
    MOV R16, R9            
    CPI R16, 2              
    BREQ filtro_24_alarma    
    RJMP suma_normal_alarma        

filtro_24_alarma:
// si si hay 2 decenas y 4 unidades, overflow a la alarma
    MOV R16, R8             
    CPI R16, 4               
    BREQ reinicio_24_alarma  
    RJMP fin_botones        

reinicio_24_alarma:
// overflow y reset a 00
    CLR R8                  
    CLR R9                  
    RJMP fin_botones        

suma_normal_alarma:
// si no se cumple lo anterior, suma normal a la hora
    MOV R16, R8            
    CPI R16, 10              
    BREQ sumar_decena_alarma_hora  
    RJMP fin_botones        

sumar_decena_alarma_hora:
// al hacer overflow las unidades, se resetean y suma uno a decena
    CLR R8                  
    INC R9                  
    RJMP fin_botones

up_alarma_min:
// sube los minutos de la alarma y revisa si hay 10 unidades
    INC R6                  
    MOV R16, R6             
    CPI R16, 10              
    BREQ sumar_decena_alarma_min   
    RJMP fin_botones        

sumar_decena_alarma_min:
// si si hay 10 unidaes, hace acarreo a decenas. revisa si hay 6 decenas
    CLR R6                  
    INC R7                  
    MOV R16, R7             
    CPI R16, 6               
    BREQ reset_decena_alarma_min   
    RJMP fin_botones        

reset_decena_alarma_min:
// si hay 6 decenas se resetea a 00
    CLR R7                  
    RJMP fin_botones

// restar a alarma
down_alarma_hora:
// resta a hora de alarma y revisa si decenas son 0
    MOV R16, R9             
    CPI R16, 0              
    BREQ check_unidades_00_alarma  
    RJMP resta_normal_alarma       

check_unidades_00_alarma:
// si decenas y unidades son 0 y se resta mas, hace underflow a 23
    MOV R16, R8             
    CPI R16, 0              
    BREQ forzar_23_alarma          
    RJMP resta_normal_alarma       

forzar_23_alarma:
// underflow a 23 horas
    LDI R16, 2              
    MOV R9, R16            
    LDI R16, 3
    MOV R8, R16            
    RJMP fin_botones        

resta_normal_alarma:
// si no se cumple lo anterior, resta normal
    DEC R8                  
    MOV R16, R8            
    CPI R16, 255            
    BREQ prestar_hora_alarma       
    RJMP fin_botones        

prestar_hora_alarma:
// acarreo de decenas a unidades si son 9
    LDI R16, 9              
    MOV R8, R16            
    DEC R9                 
    RJMP fin_botones        

down_alarma_min:
// resta a minuto de alarma y revisa si unidades son 255 (underflow)
    DEC R6                  
    MOV R16, R6             
    CPI R16, 255            
    BREQ prestar_minuto_alarma     
    RJMP fin_botones        

prestar_minuto_alarma:
// acarreo de decenas a unidades si son 9
    LDI R16, 9              
    MOV R6, R16
    DEC R7                  
    MOV R16, R7             
    CPI R16, 255            
    BREQ underflow_minuto_alarma   
    RJMP fin_botones        

underflow_minuto_alarma:
// underflow a 59 minutos
    LDI R16, 5              
    MOV R7, R16
    RJMP fin_botones


ISR_TIMER0:
// interrupciones del timer0
    PUSH R16
    IN R16, SREG
    PUSH R16
    PUSH ZL               
    PUSH ZH

// antirebote por perdida de tiempo
    CPI R27, 0            
    BREQ recargar_timer   
    DEC R27               

recargar_timer:
    LDI R16, 100               
    OUT TCNT0, R16

    RCALL clklogic
	RCALL trigger_alarma
    
// alarma parpadea
// comprueba si esta en modo sonar
    MOV R16, R10
    CPI R16, 2            
    BREQ parpadear_led
    CBI PORTB, PB5       
    RJMP apagar_fantasmas

parpadear_led:
// parpadeo de led alarma, compara con 500ms
    CPI R24, 122         
    BRSH apagar_led       
    SBI PORTB, PB5        
    RJMP apagar_fantasmas

apagar_led:
    CBI PORTB, PB5        

apagar_fantasmas:
//  apaga displays momentaneamente para proteger alarma
    IN R16, PORTB         
    ANDI R16, 0xE0        ; 0b1110_0000 - Apaga MUX (PB0-PB3) y PB4, protegiendo la alarma en PB5
    OUT PORTB, R16        

// Mux (4 estados por mascara de ANDI)
// va incrementando el registro que indica que display encender
    INC R25
    ANDI R25, 0x03        
    CPI R25, 0
    BREQ dechora
    CPI R25, 1
    BREQ unihora
    CPI R25, 2
    BREQ decmin
    RJMP unimin

dechora:
// decena de hora, manda valor de R5 a PORTD 
    MOV R16, R5          
    RCALL dispup          
    OUT PORTD, R16
    IN R16, PORTB         
    ANDI R16, 0xE0        
    ORI R16, (1 << PB0)   
    OUT PORTB, R16        
    RJMP end_timer

unihora:
// unidad de hora, manda valor de R4 a PORTD
// aqui tambien controlamos el parpadeo del colon, encendiendolo cada 500ms
    MOV R16, R4
    RCALL dispup          
    CPI R24, 122          
    BRSH imprimir_uni     
    ORI R16, 0x80         
imprimir_uni:
    OUT PORTD, R16        
    IN R16, PORTB         
    ANDI R16, 0xE0        
    ORI R16, (1 << PB1)   
    OUT PORTB, R16
    RJMP end_timer

decmin:
// decena de minuto, manda valor de R3 a PORTD
    MOV R16, R3
    RCALL dispup
    OUT PORTD, R16        
    IN R16, PORTB         
    ANDI R16, 0xE0        
    ORI R16, (1 << PB2)   
    OUT PORTB, R16
    RJMP end_timer

unimin:
// unidad de minuto, manda valor de R2 a PORTD
    MOV R16, R2        
    RCALL dispup
    OUT PORTD, R16        
    IN R16, PORTB         
    ANDI R16, 0xE0        
    ORI R16, (1 << PB3)   
    OUT PORTB, R16

end_timer:
    POP ZH
    POP ZL
    POP R16
    OUT SREG, R16
    POP R16
    RETI

// Tabla de 7 segmentos (catodo comun)
Table7seg:
    .db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0X07, 0x7F, 0x6F, 0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71