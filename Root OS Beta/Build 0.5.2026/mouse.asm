; =====================================================================
;  ROOT OS BETA - mouse.asm
;  Driver do mouse PS/2. 100% assembly, 16 bits, modo real, sem BIOS.
;
;  Este arquivo e' SEPARADO do driver de video e da interface. Ele nao
;  programa a placa de video, nao escreve na tela e nao sabe que a
;  interface existe: a unica coisa que ele faz e' conversar com o
;  controlador de teclado (o i8042) e com o mouse que esta' ligado
;  nele, e deixar a posicao do ponteiro em um lugar combinado.
;
;  Como entra aqui: o stage 1 procura "mouse.dr" no diretorio root da
;  ISO, carrega em 0000:9800 e deixa o endereco em 0000:0628 (offset) e
;  0000:062A (segmento, sempre zero). O nucleo confere a assinatura
;  "MOU!" e salta para DEPOIS dela.
;
;  ====================================================================
;  A CONVERSA COM O DISPOSITIVO
;
;  O mouse PS/2 nao tem porta propria: ele pendurado no mesmo
;  controlador do teclado, o i8042. Esse controlador tem duas portas:
;
;    0x60  dados     (escrita = mandar um byte pro dispositivo)
;    0x64  status    (escrita = mandar um comando pro controlador)
;
;  O status em 0x64 e' um byte com quatro bits que interessam:
;
;    bit 0  tem byte na fila de saida  (dado pronto para ler em 0x60)
;    bit 1  buffer de entrada cheio   (o controlador ainda nao leu o
;                                       ultimo byte que mandamos)
;    bit 2  dado do sistema, mouse    (1 = o byte veio do mouse)
;    bit 5  mouse sobre a porta 0x60  (0 = o dado e' do dispositivo)
;
;  Nenhum desses acessos passa pela BIOS: sao portas de hardware, e o
;  driver fala com elas direto. O que a BIOS faria (INT 15h, INT 33h)
;  nao e' usado em lugar nenhum deste arquivo.
;
;  A conversa de ligacao, na ordem em que ela acontece:
;
;    0xA8  escrito em 0x64, e' o comando que LIGA a porta do mouse no
;          controlador. Sem ele, o i8042 pode ignorar o que vier do
;          mouse, e a resposta seria um silencio que nao distingue
;          "mouse quebrado" de "porta desligada".
;    0xF6  defaults: o dispositivo volta ao estado de fabrica. E' o
;          primeiro comando de dados porque um mouse que ficou com o
;          relatorio ligado, ou com uma taxa estranha, precisa voltar
;          a zero antes de a gente falar com ele.
;    0xFA  resposta: todo comando de dados bem entendido e' confirmado
;          com 0xFA (FAK). E' o unico jeito de saber que quem
;          respondeu foi o mouse e nao um byte velho parado na fila.
;    0xF2  pedir identificacao: o mouse PS/2 responde 0x00, e o mouse
;          serial antigo nao responde. E' este teste que separa um do
;          outro, e por isso ele vem depois do 0xFA.
;    0xF4  ligar o envio de movimento: enquanto o mouse esta' em modo
;          de espera ele nao manda pacote nenhum. E' este comando que
;          faz a bolinha andar.
;
;  ANTES DE CADA COMANDO A FILA E' ESGOTADA. A BIOS pode ter deixado
;  um byte ali (uma tecla digitada antes do boot, por exemplo), e um
;  byte velho lido no lugar do 0xFA faria o driver declarar que nao
;  existe mouse numa maquina que tem. Esvaziar a fila antes de falar
;  e' o que faz o 0xFA valer como resposta.
;
;  Cada espera tem contagem, e nao e' espera eterna: um controlador
;  que nunca responde e' um controlador morto, e esperar sem contar
;  deixaria o boot preso para sempre.
;
;  ====================================================================
;  O PACOTE DE MOVIMENTO
;
;  Com o 0xF4 ligado, cada mexida do mouse vira um pacote de tres
;  bytes, sempre nessa ordem:
;
;    byte 0  botao (bit 0 sempre 1) | sinal de X (bit 3) |
;            sinal de Y (bit 4) | transbordou (bit 6 ou 7)
;    byte 1  quanto andou na horizontal, com sinal
;    byte 2  quanto andou na vertical, com sinal
;
;  O bit de sinal e' separado do valor, e nao faz parte dele: um
;  byte 0xFF e' menos 1, nao mais 255. Por isso o delta passa por
;  "cbw", que estende o byte com o sinal; somar o byte direto daria
;  um salto de 255 pixels para um movimento de 1 pixel para tras.
;
;  A IRQ12 e' o aviso de que tem pacote. O handler junta os tres
;  bytes e soma o movimento na posicao, e conta um pacote a mais em
;  MOUSE_N. Quem quiser saber se o ponteiro megeu olha esse contador:
;  ele so' muda quando o mouse mexeu de verdade.
;
;  ====================================================================
;  A POSICAO FICA NO HANDOFF
;
;  A posicao nao fica dentro deste driver. O driver e' carregado em
;  0x9800, e o nucleo nao pode depender de um offset interno de um
;  arquivo que ele nao conhece: se o driver crescer, o offset muda e
;  o nucleo le o byte errado sem nenhum aviso. Por isso a posicao vai
;  para a area de passagem, em 0x0630, que e' o mesmo lugar onde o
;  driver de video deixa a struct de info.
;
;  Alem da posicao, o driver escreve o numero da IRQ que acorda a
;  maquina quando o mouse mexe (MOUSE_IRQ). Quem programa o PIC le
;  esse numero em vez de cravar 12 no codigo: o numero da IRQ e' um
;  dado do dispositivo, nao um detalhe do driver.
;
;  O driver NAO programa o PIC. Quem faz isso e' o nucleo, na rotina
;  que dorme, porque quem decide quando a maquina pode dormir e' a
;  interface, e nao o driver. O driver's porao e' deixar o IVT
;  apontando para o handler e dizer qual IRQ e' a dele.
; =====================================================================

BITS 16
ORG 0x9800

; ============================ CABECALHO ============================
; Mesmo combinado do driver de video: assinatura primeiro, e o offset
; da entrada relativo ao comeco do arquivo (rotulo menos "$$").
    db 'M','O','U','!'        ; assinatura
    dw VERSAO                 ; versao do driver
    dw CONFIGURA - $$         ; entrada 1: conversar com o dispositivo
    dw 0                      ; entrada 2: este driver nao escreve nada
                               ; na tela. O zero e' o contrato: quem
                               ; escreve na tela e' o nucleo e a
                               ; interface, nao este driver.

VERSAO        equ 0x0502      ; build 0.5.2026

; ====================== PASSAGEM DE CONTROLE ======================
HANDOFF       equ 0x0600
HANDOFF_MOUSE equ 0x0628      ; dword: endereco de carga, escrito pelo
                              ;     stage 1: offset nas duas primeiras
                              ;     bytes, segmento nas duas seguintes
MOUSE_EST     equ 0x062C      ; dw:  um dos MEST_*
MOUSE_IRQ     equ 0x062E      ; dw:  numero da IRQ do mouse (12 no PS/2)
MOUSE_X       equ 0x0630      ; dw:  posicao horizontal, em pixels
MOUSE_Y       equ 0x0632      ; dw:  posicao vertical, em pixels
MOUSE_N       equ 0x0634      ; dw:  quantos pacotes o mouse ja mandou
MOUSE_LIM_X   equ 0x0636      ; dw:  limite de MOUSE_X
MOUSE_LIM_Y   equ 0x0638      ; dw:  limite de MOUSE_Y
MOUSE_I_TAM   equ 0x063A      ; dw:  bytes da area de posicao, para quem
                              ;     quiser conferir se ela esta' inteira

; --- estado, comecado em MEST_PENDENTE e terminado aqui ---
MEST_PENDENTE equ 0
MEST_OK       equ 1          ; o dispositivo respondeu e comecou a mandar
MEST_SEM_ACK  equ 2          ; nao respondeu 0xFA: nao ha mouse na porta
MEST_SEM_ID   equ 3          ; respondeu, mas nao devolveu identificacao

; ============================ PORTAS ==============================
; As duas portas do controlador i8042, mais as dos dois PICS. Os
; numeros sao do hardware e nao mudam: e' por isso que o driver pode
; escrever neles direto, sem passar pela INT 15h.
PORTA_DADOS  equ 0x60
PORTA_STATUS equ 0x64
PORTA_COMANDO equ 0x64        ; a MESMA porta do status: no i8042 quem
                              ; escreve em 0x64 manda comando, e quem
                              ; le em 0x64 le o estado. Sao as duas
                              ; metades de um so'registro
PIC_CMD_M    equ 0x20        ; comando do PIC master
PIC_CMD_S    equ 0xA0        ; comando do PIC slave
IRQ_MOUSE    equ 12          ; IRQ do mouse no barramento do i8042

; O IVT do Root OS nao remapeia os PICS: eles ficam onde a BIOS os
; deixou, master em 0x08 e slave em 0x70. A IRQ do mouse e' a 12 do
; barramento, ou seja a 4 do slave, e por isso o vetor dela e' 0x70+4
; = 0x74, e nao 0x0C. A entrada do IVT e' o vetor vezes quatro.
VET_IRQ_MOUSE equ (0x70+IRQ_MOUSE-8)

; --- o byte de comando do controlador (0x20 em 0x64, 0x60 para gravar)
CMD_LE      equ 0x20         ; "le o byte de comando" e a resposta dele
                              ; vem na fila de saida como qualquer byte
CMD_ESC     equ 0x60         ; "o byte seguinte em 0x60 e' o byte de
                              ; comando". E' um comando do CONTROLADOR,
                              ; nao do dispositivo: sem ele, o valor
                              ; escrito em 0x60 vai para o teclado e o
                              ; registro do controlador fica como estava
CMD_AUX_IRQ equ 0x02|0x40    ; bit 1 e bit 6, os dois. O 8042 de verdade
                              ; liga a IRQ12 do segundo canal pelo bit 6;
                              ; o modelo do QEMU (hw/input/pckbd.c) le o
                              ; mesmo registro com outra numeracao e usa o
                              ; bit 1 para a IRQ12 e o bit 6 para a
                              ; traducao de scancodes do TECLADO. Como
                              ; este driver nao le scancode de teclado,
                              ; ligar os dois bits serve aos dois: a IRQ12
                              ; passa a ser avisada no QEMU e num 8042 de
                              ; verdade. Sem este bit o controlador engole
                              ; o pacote: o byte fica na fila, o status
                              ; mostra "tem dado" (bit 0) e a IRQ12 nunca
                              ; aparece, e nenhuma sondagem por software
                              ; acha o motivo, porque o dado esta' ali
                              ; esperando um aviso que nao vem
CMD_MUS_REL equ 0x04         ; bit 2: 1 = relogio do mouse desligado
                              ; (no QEMU e' a flag do sistema, que tanto
                              ; faz; num 8042 de verdade e' o relogio, e
                              ; o mouse precisa dele ligado)
CMD_ESC_OUT equ 0x20         ; bit 5: no QEMU e' "desliga a interface do
                              ; mouse", e com ele ligado o byte do mouse
                              ; nem entra na fila; num 8042 de verdade e'
                              ; a escrita pendente, que so' serve durante
                              ; a propria escrita. Nos dois casos: zero
CMD_LIMPA   equ ~(CMD_MUS_REL | CMD_ESC_OUT)

; =====================================================================
;  ENTRADA 1 - CONFIGURA
;  Conversa com o mouse: liga a porta dele, volta ao estado de
;  fabrica, pede o identificador, liga o envio de movimento e
;  instala o handler da IRQ12. saida: CF=0 deu certo, CF=1 falhou.
;
;  Quem chama e' o nucleo, e ele le o resultado em MOUSE_EST, que
;  sempre fica preenchido mesmo na falha: e' o suficiente para o
;  nucleo escolher a linha da tela sem precisar perguntar nada.
; =====================================================================
CONFIGURA:
    mov [SS_SALVO], ss              ; o par de retorno do "retf" mora na
    mov [SP_SALVO], sp              ; pilha de quem chamou: nao se pode
    cli                             ; perder, senao o "retf" volta para o
    cld                             ; lugar errado
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, PILHA                   ; pilha do driver, no vao livre

    ; ---- a area de posicao comeca no meio da tela, nao no canto --
    ; MOUSE_X e MOUSE_Y nao comecam em zero porque o canto superior
    ; esquerdo e' um lugar valido, e comecar ali seria um salto de
    ; tres quartos da tela no primeiro movimento. No meio, a bolinha
    ; comeca onde o olho espera que ela comeca.
    mov word [MOUSE_EST], MEST_PENDENTE
    mov word [MOUSE_N], 0
    mov word [MOUSE_IRQ], IRQ_MOUSE
    mov word [MOUSE_I_TAM], (MOUSE_LIM_Y+2)-MOUSE_X
    mov word [MOUSE_LIM_X], TELA_LIM_X
    mov word [MOUSE_LIM_Y], TELA_LIM_Y
    mov word [MOUSE_X], TELA_LIM_X/2
    mov word [MOUSE_Y], TELA_LIM_Y/2
    mov byte [PAC_N], 0              ; nenhum byte do pacote em mãos

    ; ---- 0xA8: liga a porta do mouse no controlador ---------------
    ; Comando de controlador, e nao de dispositivo: nao existe
    ; resposta para ele, e o que confirma a execucao e' o proprio bit
    ; 1 do status voltando a zero, sinal de que o controlador leu o
    ; comando.
    call habilita_aux
    jc .sem_ack

    ; ---- o controlador passa a avisar a CPU dos bytes do mouse ----
    call mascara_aux
    jc .sem_ack

    ; ---- 0xF6 seguido de 0xFA: o Defaults, e o teste de presenca --
    ; O 0xFA e' o teste de presenca, e nao um comando a parte: se o
    ; dispositivo nao confirma, ele nao esta' la. Um teste anterior
    ; que so' olhasse "tem algo na fila de saida" nao diria nada,
    ; porque a fila vazia e' o estado normal logo apos o boot.
    call defaults
    jc .sem_ack

    ; ---- 0xF2: identificacao (o PS/2 responde, o serial antigo nao)
    call pede_id
    jc .sem_id

    ; ---- 0xF4: a partir daqui o mouse manda pacote a cada mexida --
    call liga_relatorio
    jc .sem_ack

    ; ---- handler da IRQ12 no lugar do da BIOS --------------------
    ; O IVT e' uma tabela de 256 pares CS:IP de 4 bytes, e a entrada de
    ; um vetor comeca no vetor vezes quatro. A BIOS poe em 0x74 um
    ; handler que so' chama a INT 33h, e nao queremos a INT 33h: este
    ; Root OS nao usa BIOS de mouse. Sem handler nosso, o processador
    ; entra no ROM da BIOS, executa la um `ret` que le qualquer coisa
    ; da pilha e volta para o meio do codigo do Root OS.
    ; O segmento vai zero, como todo o resto do Root OS, porque o
    ; driver esta' com ORG 0x9800 e o codigo vive num endereco linear.
    mov bx, mouse_irq
    mov word [VET_IRQ_MOUSE*4], bx
    mov word [VET_IRQ_MOUSE*4+2], 0
    mov word [MOUSE_EST], MEST_OK
    xor ax, ax                      ; CF = 0: deu certo
    jmp .volta

.sem_id:
    mov word [MOUSE_EST], MEST_SEM_ID
    stc
    jmp .volta
.sem_ack:
    mov word [MOUSE_EST], MEST_SEM_ACK
    stc
.volta:
    mov ss, [SS_SALVO]              ; devolve SS:SP a quem chamou e
    mov sp, [SP_SALVO]              ; executa o "retf" que consome o
    retf                            ; par CS:IP que estava na pilha

; =====================================================================
;  habilita_aux
;  Manda 0xA8 ao controlador (porta 0x64) para ligar a porta do mouse.
;  Nao ha resposta: o que confirma e' o bit 1 do status voltar a zero.
;  saida: CF=0 o controlador leu, CF=1 timeout
; =====================================================================
habilita_aux:
    call espera_livre
    jc .timeout
    mov al, 0xA8
    out PORTA_STATUS, al
    call espera_livre               ; o bit 1 zerando e' o "li o comando"
    ret
.timeout:
    stc
    ret

; =====================================================================
;  mascara_aux
;  Liga o aviso de IRQ do segundo canal no controlador.
;
;  O 0xA8 da habilita_aux liga a PORTA do mouse, mas nao diz para o
;  controlador chamar a CPU quando o mouse entrega byte: enquanto o
;  bit da IRQ12 estiver apagado no byte de comando, o controlador
;  guarda o pacote e nao levanta IRQ nenhuma. O byte fica la, o status
;  mostra "tem dado", e o ponteiro nao se mexe: um sintoma que parece
;  do driver e e do controlador.
;
;  O byte de comando tem dois passos, e o primeiro e' o que costuma
;  faltar: 0x20 em 0x64 manda o controlador colocar o byte na fila de
;  saida, e 0x60 em 0x64 e' o aviso de que o proximo byte escrito em
;  0x60 e' o proprio byte de comando. Sem esse 0x60, o valor vai
;  parar no dispositivo e o registro do controlador continua como
;  estava - e o driver nao tem como saber, porque a leitura de
;  confirmacao devolve o valor antigo, que e o da BIOS.
;  saida: CF=0 o byte foi regravado, CF=1 nao deu
; =====================================================================
mascara_aux:
    push bx                         ; o byte vai ficar em BL: nenhum dos
                                    ; helpers mexe em BX, e o AX nao
                                    ; sobrevive a uma espera
    call drena
    call espera_livre
    jc .timeout
    mov al, CMD_LE
    out PORTA_STATUS, al
    call le_qualquer                ; a resposta do controlador nao tem
                                    ; o bit 5 do mouse, e por isso nao
                                    ; pode passar pelo le_byte
    jc .timeout
    mov bl, al
    and bl, CMD_LIMPA
    or  bl, CMD_AUX_IRQ
    call espera_livre
    jc .timeout
    mov al, CMD_ESC                 ; "o byte seguinte em 0x60 e' o byte
                                    ;  de comando", e nao um comando de
                                    ;  dispositivo: sem esta linha o
                                    ;  valor abaixo vai para o teclado
    out PORTA_STATUS, al
    call espera_livre
    jc .timeout
    mov al, bl
    out PORTA_DADOS, al
    call espera_livre               ; o controlador tem de ter lido o
    ; byte antes do proximo comando. Como a gravacao nao tem
    ; resposta, esta espera e' a unica prova de que deu certo - e da
    ; para conferir: o 0x20 de leitura devolve o byte que ficou.
    pop bx
    clc
    ret
.timeout:
    pop bx
    stc
    ret

; =====================================================================
;  le_qualquer
;  Le um byte da fila de saida, seja do mouse, seja do teclado ou
;  seja resposta do proprio controlador. E o que o le_byte nao faz:
;  ele descarta o byte do teclado porque aqui os dois disputam a mesma
;  fila, e a resposta de um comando do controlador chega com o bit 5
;  do status apagado, do mesmo jeito que um byte de teclado.
;  saida: AL = byte, CF=0 leu; CF=1 fila vazia
; =====================================================================
le_qualquer:
    push cx
    mov cx, TENTATIVAS
.tente:
    in al, PORTA_STATUS
    test al, 01h                    ; bit 0 = tem dado pronto
    jz .vazio
    in al, PORTA_DADOS
    pop cx
    clc
    ret
.vazio:
    loop .tente
    pop cx
    stc
    ret

; =====================================================================
;  defaults
;  Esvazia a fila, manda 0xF6 e exige o 0xFA de resposta.
;  saida: CF=0 o dispositivo confirmou, CF=1 nao veio 0xFA
; =====================================================================
defaults:
    call drena
    mov al, 0xF6
    jmp manda_so

; =====================================================================
;  liga_relatorio
;  Esvazia a fila, manda 0xF4 e exige o 0xFA de resposta.
;  saida: CF=0 o dispositivo confirmou, CF=1 nao veio 0xFA
; =====================================================================
liga_relatorio:
    call drena
    mov al, 0xF4
    jmp manda_so

; =====================================================================
;  pede_id
;  Esvazia a fila, manda 0xF2 e le a identificacao. O PS/2 responde
;  0x00 (2 botoes) ou 0x03 (3 botoes com rolagem); o mouse serial
;  antigo nao responde nada. Qualquer outra coisa significa que quem
;  respondeu nao era um mouse.
;  saida: CF=0 identificacao ok, CF=1 nao veio
; =====================================================================
pede_id:
    call drena
    mov al, 0xF2
    ; A resposta do 0xF2 sao TRES bytes, e na' um: primeiro o 0xFA de
    ; "comando entendido", e so' depois os dois bytes do identificador.
    ; Ler um byte so' e comparar com o ID compara o ACK com o ID, e da
    ; "sem ID" num mouse que esta' la, respondendo certinho. Por isso
    ; o ACK vai pelo manda_so, que ja' o confere, e a leitura seguinte
    ; e' o ID.
    call manda_so
    jc .falhou
    call le_byte
    jc .falhou
    cmp al, 0x00                    ; 0x00: mouse PS/2 de 2 botoes
    je .ok
    cmp al, 0x03                    ; 0x03: PS/2 de 3 botoes com rolagem
    je .ok
    cmp al, 0x02                    ; 0x02: mouse de 2 botoes, responde
    je .ok                          ; pouco, mas e' mouse
    cmp al, 0x01                    ; 0x01: mouse de 1 botao
    je .ok
    stc
    ret
.ok:
    clc
    ret
.falhou:
    stc
    ret

; =====================================================================
;  manda_so
;  Manda o byte que esta' em AL e le a confirmacao, sem se preocupar
;  com o valor. O 0xFA (FAK) e' a resposta de todo comando de dados
;  entendido; um byte que nao seja 0xFA e' ou um erro do dispositivo
;  ou um byte velho, e nos dois casos o comando nao foi aceito.
;  saida: CF=0 veio 0xFA, CF=1 veio outra coisa
; =====================================================================
manda_so:
    call manda
    jc .falhou
    call le_byte
    jc .falhou
    cmp al, 0xFA
    je .ok
    stc
    ret
.ok:
    clc
    ret
.falhou:
    stc
    ret

; =====================================================================
;  manda
;  Manda um byte de DADOS para o dispositivo: espera a entrada do
;  controlador ficar livre e escreve em 0x60.
;  saida: CF=0 mandou, CF=1 a porta nao ficou livre
; =====================================================================
manda:
    push ax
    call espera_livre
    jc .timeout
    ; O 0xA8 da habilita_aux liga a PORTA do mouse, mas nao diz para ONDE
    ; vai o proximo byte: enquanto o bit "A2" nao estiver marcado, tudo
    ; que entra em 0x60 e' do TECLADO. Quem marca e' o 0xD4, e ele tem
    ; de vir antes de CADA byte de dados, nao uma vez so' no começo.
    ;
    ; Sem o 0xD4, o driver falaria de um jeito bem traiçoeiro: o teclado
    ; responde 0xFA (ACK) para quase tudo, entao o 0xF6 "passaria", e
    ; o 0xF2 viria 0xAB 0x41, que e' a identidade de um TECLADO. O
    ; boot diria "sem ID" com um mouse perfeitamente bem conectado, e o
    ; culpado pareceria ser o mouse.
    mov al, 0xD4                    ; o byte seguinte em 0x60 e' do mouse
    out PORTA_COMANDO, al
    pop ax                          ; AL = o byte de dados, de novo
    call espera_livre
    jc .timeout
    out PORTA_DADOS, al
    clc
    ret
.timeout:
    pop ax
    stc
    ret

; =====================================================================
;  drena
;  Joga fora tudo o que estiver na fila de saida, com um teto de
;  TENTATIVAS leituras. Esvaziar a fila antes de cada comando e' o
;  que garante que o 0xFA lido depois seja a resposta daquele comando
;  e nao um byte que a BIOS deixou la.
; =====================================================================
drena:
    push ax
    push cx
    mov cx, TENTATIVAS
.alguma:
    in al, PORTA_STATUS
    test al, 01h                    ; bit 0 = tem dado na fila
    jz .fim
    in al, PORTA_DADOS              ; le e descarta
    loop .alguma
.fim:
    pop cx
    pop ax
    ret

; =====================================================================
;  espera_livre
;  Espera o controlador esvaziar a fila de ENTRADA (bit 1 do status),
;  que e' a fila de comandos: enquanto o bit estiver posto, o
;  controlador ainda nao leu o ultimo byte e um novo comando seria
;  descartado. saida: CF=0 liberou a tempo, CF=1 deu timeout
; =====================================================================
espera_livre:
    push ax
    push cx
    mov cx, TENTATIVAS
.tente:
    in al, PORTA_STATUS
    test al, 02h                    ; bit 1 posto = entrada ocupada
    jz .livre
    loop .tente                     ; CX ainda nao zerou: tenta de novo
    pop cx
    pop ax
    stc                             ; timeout: o controlador nao saiu do
    ret                             ; lugar, e quem chamou trata
.livre:
    pop cx
    pop ax
    clc
    ret

; =====================================================================
;  le_byte
;  Le um byte da fila de saida, se houver.
;  saida: AL = byte, CF=0 leu; CF=1 fila vazia
; =====================================================================
le_byte:
    push cx
    mov cx, TENTATIVAS
.tente:
    in al, PORTA_STATUS
    test al, 01h                    ; bit 0 = tem dado pronto
    jz .vazio
    test al, 20h                    ; bit 5 = o dado veio do MOUSE
    jz .de_teclado                 ; tem dado, mas e' do teclado
    in al, PORTA_DADOS
    pop cx
    clc
    ret
.de_teclado:
    ; A fila e' uma so' para os dois: um pacote do mouse e uma tecla
    ; pressionada usam a mesma porta. Ler a tecla como se fosse o ACK do
    ; 0xF6 desalinharia toda a conversa, porque o proximo byte lido
    ; seria o ACK de verdade. Entao o byte do teclado e' lido e
    ; descartado, e a espera continua pelo do mouse.
    in al, PORTA_DADOS
    loop .tente
.vazio:
    loop .tente
    pop cx
    stc
    ret

; =====================================================================
;  mouse_irq
;  INT 74h: a IRQ12 do i8042. Uma IRQ do slave precisa de dois EOI,
;  um para cada PIC: sem o do master, o slave fica esperando e a
;  proxima IRQ12 nao entra.
;
;  O handler le o byte ANTES do "iret", e nao depois: se lesse depois,
;  a proxima IRQ12 chegaria antes do dado estar no lugar, e o byte
;  leria o pacote anterior.
;
;  DS e ES sao guardados e devolvidos: uma interrupcao que nao devolve
;  os segmentos que pegou deixa o programa interrompido com DS trocado,
;  e isso apareceria como um erro-winning em um lugar que nao tem
;  nada a ver com o mouse.
; =====================================================================
mouse_irq:
    pushf
    push ax
    push cx
    push dx
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov es, ax
    in al, PORTA_STATUS
    call soma_pacote
    mov al, PIC_CMD_S              ; EOI no slave
    out PIC_CMD_S, al
    mov al, PIC_CMD_M              ; EOI no master tambem
    out PIC_CMD_M, al
    pop es
    pop ds
    pop dx
    pop cx
    pop ax
    popf
    iret

; =====================================================================
;  soma_pacote
;  Le UM byte da fila e vai montando o pacote de 3, byte a byte.
;
;  Um IRQ por byte, e nao um IRQ por pacote: a fila de saida do i8042
;  guarda um byte de cada vez, e o controlador levanta IRQ12 de novo
;  assim que o byte lido sai, se o seguinte ja estiver esperando. Por
;  isso nao da para ler os tres bytes de uma vez dentro do handler:
;  quem trata o IRQ recebe um byte, e so um.
;
;  O bit 3 do primeiro byte tem de estar posto: um pacote de
;  movimento comeca sempre com 0x08, porque e' esse bit que marca o
;  primeiro byte do pacote. Testar o bit 0 - que no primeiro byte e'
;  sempre ZERO - rejeitaria todo pacote, e o ponteiro nunca andaria
;  sem que nenhuma IRQ aparecesse no contador. Se o bit 3 nao estiver
;  no lugar, o que chegou foi lixo: melhor descartar do que somar
;  meio pacote, que deixaria a bolinha num lugar que o mouse nunca
;  apontou.
; =====================================================================
soma_pacote:
    push ax
    call le_byte
    jc .fim

    cmp byte [PAC_N], 0
    jne .tem_um
    test al, 08h                    ; bit 3 posto = primeiro byte
    jz .desalinha                   ; nao e' inicio de pacote: descarta
    mov [byte0], al
    mov byte [PAC_N], 1
    jmp .fim
.tem_um:
    cmp byte [PAC_N], 1
    jne .terceiro
    mov [byte1], al
    mov byte [PAC_N], 2
    jmp .fim
.terceiro:
    mov [byte2], al
    mov byte [PAC_N], 0              ; pacote completo: volta ao comeco

    ; ---- os deltas, com o sinal no lugar certo --------------------
    ; "cbw" e' o que faz o trabalho: ele estende o byte em AL para a
    ; palavra AX com o sinal, de modo que 0xFF vira -1 em vez de 255.
    mov al, [byte1]                 ; horizontal
    cbw
    mov [DELTA_X], ax
    mov al, [byte2]                 ; vertical
    cbw
    mov [DELTA_Y], ax

    ; ---- soma em X, com limite nas duas bordas --------------------
    ; As comparacoes sao COM SINAL ("jle", "jge"): a soma pode dar
    ; negativo, e uma comparacao sem sinal veria 0xFFFF como um numero
    ; enorme e jogaria a bolinha no canto oposto em vez de parar na
    ; borda.
    mov ax, [MOUSE_X]
    add ax, word [DELTA_X]
    cmp ax, [MOUSE_LIM_X]
    jle .x_dentro
    mov ax, [MOUSE_LIM_X]           ; passou da direita: encosta
    jmp .x_grava
.x_dentro:
    cmp ax, TELA_MEN_X
    jge .x_grava
    mov ax, TELA_MEN_X              ; passou da esquerda: encosta
.x_grava:
    mov [MOUSE_X], ax

    ; ---- vertical: SUBTRAI, e nao soma -----------------------------
    ; E' a unica linha desta rotina que e' "sub" em vez de "add", e o
    ; motivo e' que os dois eixos nao contam para o mesmo lado: o
    ; mouse conta a vertical para CIMA (arrastar para longe de voce da
    ; um Y positivo), e a tela conta para BAIXO (a linha 0 e' o topo e
    ; a ultima linha e' a de baixo). Somar as duas daria um ponteiro
    ; que sobe na tela quando o mouse vai para baixo, e o inverso
    ; tamberem. A horizontal nao precisa disso, porque o mouse e a
    ; tela contam os dois para a direita.
    ;
    ; O limite continua nas duas bordas: com o Y subtraido, "passou de
    ; cima" e' um Y grande demais e "passou de baixo" e' um Y negativo.
    mov ax, [MOUSE_Y]
    sub ax, word [DELTA_Y]
    cmp ax, [MOUSE_LIM_Y]
    jle .y_dentro
    mov ax, [MOUSE_LIM_Y]           ; passou de baixo: encosta
    jmp .y_grava
.y_dentro:
    cmp ax, TELA_MEN_Y
    jge .y_grava
    mov ax, TELA_MEN_Y              ; passou de cima: encosta
.y_grava:
    mov [MOUSE_Y], ax

    inc word [MOUSE_N]              ; o ponteiro mexeu
    jmp .fim
.desalinha:
    mov byte [PAC_N], 0              ; o byte nao era o primeiro do
.fim:                               ; pacote: o meio se refaz
    pop ax
    ret

; ============================== DADOS ==============================
PILHA        equ 0x9700        ; o driver esta' em 0x9800, e a pilha
                              ; dele fica no vao livre logo abaixo
TENTATIVAS   equ 20000         ; quanto esperar pelo controlador antes
                              ; de desistir. Cada volta e' um par de
                              ; "in" num dispositivo que responde na
                              ; ordem de milissegundos: 20000 esperas
                              ; dao tempo de sobra para maquina de
                              ; verdade, e nao e' infinito.
TELA_MEN_X   equ 8              ; primeiro pixel util na horizontal: a
                              ; bolinha tem 15 de largura, entao o
                              ; CENTRO nao pode passar de 8 para a
                              ; esquerda (ele pintaria a linha -6) nem
                              ; de 631 para a direita
TELA_MEN_Y   equ 8              ; idem na vertical
TELA_LIM_X   equ 631
TELA_LIM_Y   equ 471

byte0:       db 0              ; byte 0 do pacote corrente
byte1:       db 0              ; byte 1
byte2:       db 0              ; byte 2
PAC_N:       db 0              ; quantos bytes do pacote ja chegaram
                              ; (0, 1 ou 2): o IRQ traz um byte por vez
DELTA_X:     dw 0              ; movimento horizontal do ultimo pacote
DELTA_Y:     dw 0              ; movimento vertical do ultimo pacote
SS_SALVO:    dw 0              ; SS e SP de quem chamou, para o "retf"
SP_SALVO:    dw 0
