; =====================================================================
;  ROOT OS BETA - nucleo.asm
;  Nucleo da build 0.5.2026. 100% assembly, 16 bits, modo real.
;
;  O stage 1 carregou este arquivo em 0000:8000 e o videoVGA.dr em
;  0000:9000, e deixou o endereco do driver em 0000:0600. Aqui:
;
;    1. confere a assinatura "VGA!" do driver
;    2. chama a entrada MODO do driver, que configura 640x480x16
;       planar em 0000:A0000, limpa a tela e confere relendo o CRTC
;    3. escreve o nome do build sozinho, na linha 0, e espera 5
;       segundos
;    4. limpa a tela e escreve DUAS linhas: "kernel-0.5.2026" e
;       "videoVGA.dr configurado com sucesso". Nenhuma terceira linha,
;       e o nome do build nao volta
;    5. espera 5 segundos, contados no PIT, sem BIOS
;    6. passa o controle para o interface.grain, que pinta a tela. A
;       passagem e' definitiva: a interface nao devolve
;
;  QUEM ESCREVE NA TELA: o nucleo. O driver e' a camada de video, e nao
;  tem nenhuma mensagem, nem numero de linhas, nem posicao fixa: ele
;  programa a placa, limpa a tela e coloca um glifo onde for pedido.
;
;  O nucleo nao escreve nada na memoria de texto da BIOS (0xB8000), nem
;  antes do MODO nem depois. As linhas vao para a tela pelo TEXTO, uma
;  vez so cada, na fonte do nucleo. A UNICA excecao e' o aviso de erro:
;  se o driver nao configurou o video, o TEXTO nao tem janela onde
;  escrever, e o aviso_bios pede UMA linha a BIOS, "videoVGA.dr nao
;  configurado", e o boot para. Nao existe nenhum outro uso de BIOS de
;  video em todo o Root OS, e o build trava a regra.
;
;  -------------------------------------------------------------------
;  A CHAMADA AO DRIVER, E POR QUE ELA E' FEITA ASSIM
;
;  Nao existe "call far imediato" de 32 bits em modo de 16, e nao
;  queremos instrucao de 32 bits aqui. O par "push CS / push IP de
;  retorno / jmp dword [ptr]" monta na pilha exatamente o endereco que
;  um "retf" do driver espera encontrar: o "retf" desempilha o IP
;  primeiro e o CS depois, voltando para o ponto logo apos o jmp.
;
;  O ponteiro em 0000:0600 e' lido como dword, entao o segmento em
;  0000:0602 precisa estar zerado. E' o nucleo que zera: o stage 1
;  gasta bytes com tudo que e' dele, e aqui nao ha limite de tamanho.
; =====================================================================

BITS 16
ORG 0x8000

; ============================ CABECALHO ============================
; O stage 1 le a assinatura e o offset da entrada. A entrada tem de
; estar no offset 12, logo os 4 words do cabecalho vem primeiro.
    db 'R','O','O','T'     ; assinatura
    dw VERSAO               ; versao do nucleo
    dw H_ENT                ; offset da entrada
    dw 0, 0                 ; reservado

VERSAO   equ 0x0101                  ; a versao do Root OS: 0.1, sempre
H_ENT    equ 12

; ============================ PASSAGEM ============================
; O stage 1 escreve em 0000:0600 o endereco-base do driver. Esse par de
; palavras e' o PONTEIRO DE CHAMADA, e nao um deposito: o nucleo precisa
; escrever la o endereco da entrada antes de cada "jmp dword", porque o
; endereco da entrada so e' conhecido depois de ler o cabecalho.
;
; Por isso a base tambem fica em DRV_BASE, no fim deste arquivo. Sem
; essa copia, a segunda chamada usaria o valor deixado pela primeira:
; o ponteiro de MODO no lugar da base, some bytes a mais no offset, e o
; "jmp" cairia em endereco pequeno (0x000F no teste) em vez de no driver.
; Confiar em BX tambem nao resolveria: um "jmp" para outro segmento nao
; e' um "call", o driver nao preserva registrador nenhum, e BX chega de
; volta com o que o driver deixara.
HANDOFF       equ 0x0600
HANDOFF_DRIVER equ HANDOFF+0  ; dw  ponteiro de chamada (dword com o segmento)
HANDOFF_SEG   equ HANDOFF+2  ; dw  segmento, sempre 0
HANDOFF_MSG   equ 0x0604      ; dw  offset da mensagem de boot do stage 1
HANDOFF_IFACE equ 0x0606      ; dword  ponteiro far da interface: o offset
                              ;        do interface.grain carregado, e o
                              ;        segmento, que e' sempre 0. O offset
                              ;        aponta para a assinatura 'GRN!'.
HANDOFF_ERRO_BOOT equ 0x060A   ; dw: 0 enquanto o stage 1 esta' indo bem,
                              ;     ERRO_BOOT (0xBAD0) se ele parou
HANDOFF_ERRO_NUC equ 0x060C   ; dw: 0 enquanto o nucleo esta' indo bem.
                              ;     O nucleo nao escreve na tela quando
                              ;     o video nao esta' de pe, entao o
                              ;     aviso de erro vai para a memoria.
ERRO_SEM_DRIVER equ 0xBAD1    ; nenhum driver utilizavel em 0000:0600
ERRO_MODO       equ 0xBAD2    ; o driver rodou e recusou o modo
ERRO_SEM_VGA    equ 0xBAD3    ; o driver nao achou placa de video
ERRO_SEM_IFACE  equ 0xBAD4    ; a interface nao confere (esta desenha)
HANDOFF_TICKS equ 0x060E      ; dw: pulsos do PIT ja contados na espera.
; --- mouse: o que o mouse.dr escreve, e o que o nucleo publica ------
; A area de 0x062C a 0x063A e' do driver de mouse (MOUSE_*), com os
; mesmos nomes e o mesmo offset dos dois lados. A de 0x063C para baixo
; e' do nucleo, e e' o que a interface vai ler.
HANDOFF_MOUSE equ 0x0628      ; dword: endereco de carga do mouse.dr,
                              ;     escrito pelo stage 1
MOUSE_EST     equ 0x062C      ; dw:  um dos MEST_*, escrito pelo driver
MOUSE_IRQ     equ 0x062E      ; dw:  IRQ do mouse, escrito pelo driver
MOUSE_X       equ 0x0630      ; dw:  posicao do ponteiro, em pixels
MOUSE_Y       equ 0x0632      ; dw:  idem, na vertical
MOUSE_N       equ 0x0634      ; dw:  pacotes recebidos do mouse
HANDOFF_BOLA  equ 0x063C      ; dword: ponteiro far da rotina BOLA, que
                              ;     o nucleo publica para a interface.
                              ;     Zero quando nao ha mouse, e a
                              ;     interface entende: sem bolinha.
HANDOFF_DORME equ 0x0640      ; dword: ponteiro far da rotina DORME
BOLA_X        equ 0x0644      ; dw: centro da ultima bolinha pintada.
BOLA_Y        equ 0x0646      ;     0xFFFF em BOLA_X = nada pintado ainda
BOLA_N        equ 0x0648      ; dw: MOUSE_N no momento do ultimo repaint
                              ;     Fica num endereco fixo, e nao numa
                              ;     variavel do nucleo, de proposito: quem
                              ;     olha a memoria de fora (o teste, ou a
                              ;     interface quando ela souber esperar)
                              ;     precisa do mesmo numero de build em
                              ;     build, e uma variavel mudaria de
                              ;     endereco sempre que o nucleo encolhe
                              ;     ou cresce.
INFO          equ 0x0610      ; struct preenchida pelo driver
; Offsets da struct de info. Estao em ordem, sem buracos: o driver
; grave I_TOTAL bytes de uma vez. Eles combinam com os I_* de
; videoVGA.asm, e nao com uma versao anterior que tinha quatro campos
; de PCI a mais, porque o CRTC substituiu a varredura PCI.
I_ESTADO      equ 0
I_SONDA0      equ 2           ; CRTC 0x00 lido antes de programar
I_SONDA12     equ 4           ; CRTC 0x12 lido antes de programar
I_HI          equ 6           ; CRTC 0x12 lido de volta, apos programar
I_VI          equ 8           ; CRTC 0x15 lido de volta
I_H0          equ 10          ; CRTC 0x01
I_V0          equ 12          ; CRTC 0x07
I_LARGURA     equ 14
I_ALTURA      equ 16
I_TAM_FONTE   equ 18          ; dw  bytes por glifo: preenchido pelo
I_TAM_TAB     equ 20          ; dw  glifos guardados: tambem pelo nucleo,
                              ;     porque a fonte e' do nucleo

; --- offsets das entradas dentro do cabecalho "VGA!" do driver ---
H_MODO        equ 6
H_ESCRITA     equ 8             ; entrada 2 do driver: tem de ser 0

; --- pilha do nucleo ---
; 0x7000 fica entre o stage 1 (0x7C00) e o driver (0x9000), longe dos
; dois, e so' desce. O driver usa a dele em 0x7B00 (acima desta, ainda
; abaixo do stage 1), entao as duas pilhas nao se atropelam mesmo com o
; SS:SP trocado no meio do caminho. Nada de pilha entre 0x8000 e 0x8C1:
; ali dentro esta' o proprio nucleo, fonte 8x16 inclusive.
KSTACK        equ 0x7000

; ============================== TELA ==============================
; O nucleo nao tem constantes de modo texto: nao escreve no buffer de
; video da BIOS (0xB8000) e nao escolhe modo de video. Quem programa a
; placa e' o driver; quem escreve as linhas, com a fonte do nucleo, e'
; o TEXTO mais abaixo, direto na janela 640x480 do driver.
;
; Coluna e linha da grade de 80x30, ja no word que o TEXTO le: o byte
; baixo e' a coluna e o alto e' a linha. Nenhuma tela do boot passa da
; linha 2: a primeira tela mostra so' o nome do build, e a segunda
; mostra o nucleo, o driver de video e o driver de mouse.
CEL_0         equ (0 << 8) | 0
CEL_1         equ (1 << 8) | 0
CEL_2         equ (2 << 8) | 0

; --- geometria do desenho, a mesma que o driver programou -----------
; O driver configurou a tela; aqui o nucleo escreve nela. Os numeros
; precisam bater com o que o driver program's, e por isso que sao os
; mesmos: 80 bytes por linha da janela e 16 pixels de altura de glifo.
LARGURA       equ 640            ; pixels por linha
ALTURA        equ 480            ; pixels por coluna
; --- a bolinha e o mouse ---
; MEST_*: os mesmos valores que o mouse.asm escreve em MOUSE_EST. Os
; dois lados precisam concordir, e o build confere que as duas listas
; batem, para um dos dois mudar de ideia sem o outro perceber.
MEST_OK       equ 1
MEST_SEM_ACK  equ 2
MEST_SEM_ID   equ 3
MEST_SEM_ARQUIVO equ 4         ; o mouse.dr nao veio da ISO

BOLA_RAIO     equ 8              ; raio da bolinha, em pixels
BOLA_LADO     equ 2*BOLA_RAIO+1  ; lado da caixa: o diametro, 17. Sao 17
                                ; e nao 16 porque o raio conta para os
                                ; dois lados: a caixa vai de CX-8 ate
                                ; CX+8, e uma caixa de 16 linhas cortaria
                                ; a ponta de baixo do circulo.
BOLA_COR      equ 4              ; o indice de cor 4 da paleta de 16
                                ; e' o vermelho. Neste modo planar o
                                ; byte da janela E' o indice de cor
                                ; (0x00 preto, 0x0F branco), e nao um
                                ; indice de fonte como em modo texto.
BOLA_LIM_X    equ 631            ; ultimo pixel da tela na horizontal
BOLA_LIM_Y    equ 471            ; e na vertical
VET_IRQ12     equ 0x70+12-8    ; a IRQ12 do i8042 e' o vetor 0x74: os
                              ; PICS nao sao remapeados, entao o slave
                              ; continua contando a partir de 0x70 e a
                              ; 4a IRQ dele (a 12 do barramento, 12-8=4
                              ; no slave) cai em 0x74. Sem o "-8" o
                              ; vetor viraria 0x7C, a IRQ15, e o IVT
                              ; receberia o handler no lugar errado. A
                              ; entrada do IVT e' 0x74*4 = 0x1D0.
VGA_SEQ_IDX   equ 0x3C4          ; o sequenciador se escreve em DUAS
                                ; portas: o numero do registrador em
                                ; 0x3C4, e o valor em 0x3C5. O
                                ; registrador 2 e' a mascara de
                                ; camadas da escrita na janela
VGA_SEQ       equ 0x3C5          ; o dado do sequenciador
MIXA_TODAS    equ 0x0F           ; as quatro camadas
PIC_TUDO      equ 0xFF           ; mascara que bloqueia todas as IRQ
PIC_CASCATA   equ 0xFB           ; tudo bloqueado, menos a IRQ2: e' por
                                ; ela que o slave chega ao master
PIC_MASC_S    equ 0xA1           ; mascara do PIC slave, para a IRQ12
PIC_CMD_S     equ 0xA0           ; comando do PIC 8259 slave

BYTES_LINHA   equ 80             ; 640 / 8: bytes de uma linha da janela
TAM_CELULA    equ 16             ; altura do glifo, em pixels
PASSO_X       equ 8              ; largura do glifo, em pixels
FONTE_BASE    equ 32             ; primeiro caractere guardado na tabela
FONTE_QUANT   equ 95             ; caracteres 32..126

; Nao existe mais uma copia das linhas em RAM comum. Antes o driver
; lia a sombra em 0x5000, porque depois do MODO a memoria de texto
; some debaixo da janela grafica; agora o nucleo guarda as strings no
; proprio codigo e as entrega ao TEXTO, uma por linha.
; --- estados que o driver pode deixar em I_ESTADO ---
EST_OK        equ 1
EST_SEM_VGA   equ 2
EST_FALHOU    equ 3

; =====================================================================
;  ENTRADA
; =====================================================================
entrada:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, KSTACK              ; pilha do nucleo, longe do stage 1
    cld

    ; ---- confere o driver antes de chamar qualquer coisa dele ----
    mov bx, [HANDOFF_DRIVER]
    test bx, bx
    jz sem_driver
    mov [DRV_BASE], bx           ; guarda a base: 0600 vira ponteiro depois
    cmp word [bx], ASS_VGA       ; 'V','G'
    jne sem_driver
    cmp word [bx+2], ASS_EXPL    ; 'A','!'
    jne sem_driver

    ; ---- o driver e' so' video: a entrada 2 tem de vir vazia ----
    ; Se o driver voltasse a ter uma entrada de escrita de texto, o
    ; nucleo nao usaria, e o dono da tela passaria a ser o driver de
    ; novo. Recusar aqui deixa o conflito aparecer no boot, e nao como
    ; texto escrito no lugar errado.
    cmp word [bx+H_ESCRITA], 0
    jne sem_driver

    ; ---- o driver configura o video e confere o CRTC ----
    ; O nucleo nao escreve nada na tela antes disto. A tela ainda esta'
    ; no modo que a BIOS deixou, e escrever no buffer de texto dela
    ; (0xB8000) seria a unica forma de mostrar as linhas antes de o
    ; video estar pronto: mas o nucleo tem fonte propria e TEXTO, entao
    ; o texto sai depois, ja em 640x480, e sai uma vez so. O aviso de
    ; erro tambem nao passa por la: quando o driver nao responde nao ha
    ; modo grafico nem para o TEXTO nem para a BIOS, entao o caminho
    ; deixa o codigo do erro na memoria e para.
    call chama_modo
    jc .falhou

    ; A fonte e' do nucleo, entao quem anuncia o tamanho dela na struct
    ; de info e' o nucleo. E' aqui, DEPOIS do driver voltar, e' nao
    ; antes: o driver limpa a struct inteira no comeco, para nao
    ; sobrar lixo de uma chamada anterior, e escrever antes dele
    ; seria escrever em cima do que ele apaga logo depois.
    mov word [INFO+I_TAM_FONTE], TAM_CELULA
    mov word [INFO+I_TAM_TAB], FONTE_QUANT

; =====================================================================
;  O video ja esta em modo grafico e a tela esta limpa. Agora quem escreve
;  na tela e' o nucleo: ele chama o TEXTO uma vez por linha, e a ordem
;  das chamadas e' a ordem das linhas. O TEXTO e' do nucleo, com a fonte
;  do nucleo: o driver so' programou a placa e limpou a tela.
;
;  Sao dois tempos, e cada um com a sua tela. Primeiro so' o nome do
;  build, sozinho, por 5 segundos: e' o que esta' rodando, antes de
;  qualquer outra coisa. Depois a tela e' limpa e entram DUAS linhas, o
;  nome do nucleo e a confirmacao do driver, que ficam por 5 segundos.
;  A linha do build nao volta: nesta tela o que interessa e' o que o
;  Root OS conseguiu fazer, e nao o nome dele.
; =====================================================================
    ; linha 0: a mensagem de boot, a mesma string que o stage 1 deixou
    ; no handoff. O stage 1 nao escreve nada na tela: ele entrega o
    ; ponteiro e o nucleo desenha, para ela sair com a fonte do nucleo.
    mov si, [HANDOFF_MSG]
    xor dx, dx
    call TEXTO

; =====================================================================
;  CINCO SEGUNDOS COM O NOME DO BUILD SOZINHO
;
;  A espera e' contada no PIT, sem BIOS e sem interrupcao. O TEXTO nao
;  mexe na tela enquanto isso: quem escreve aqui e' o relogio.
; =====================================================================
    mov cx, TICKS_5S
    call espera_ticks

; =====================================================================
;  A TELA VOLTA A LIMPA, E AS DUAS LINHAS APARECEM
;
;  Quem limpa e' o nucleo, com o mesmo rep stosb que ele usa para o
;  TEXTO: ele e' o dono do conteudo da janela 640x480. O driver ja
;  limpou a tela uma vez, no MODO; esta e' a segunda limpeza, a do
;  momento em que as duas linhas substituem o nome do build.
; =====================================================================
    call limpa_tela

    ; linha 0: o nucleo
    mov si, msg_nucleo
    xor dx, dx
    call TEXTO

    ; linha 1: a confirmacao do driver
    mov si, msg_sucesso
    mov dx, CEL_1
    call TEXTO

; =====================================================================
;  O MOUSE: CONVERSA, BOLINHA E A TERCEIRA LINHA
;
;  A ordem aqui e' o que faz a bolinha ficar EM SEGUNDO PLANO: ela e'
;  desenhada antes das linhas de texto, entao o texto passa por cima
;  dela se algum dia as duas se cruzarem. Ela nao se cruza hoje, porque
;  a bolinha fica no meio da tela e o texto na faixa de cima.
;
;  Quem conversa com o dispositivo e' o driver, e nao o nucleo: o
;  mouse.dr sabe das portas 0x60 e 0x64, e o nucleo nao tem porque de
;  saber. O nucleo so' chama, olha MOUSE_EST e escreve a linha.
; =====================================================================
    call mouse_da_bolinha

    ; linha 2: o resultado da conversa, seja ela qual for
    cmp word [MOUSE_EST], MEST_OK
    jne .mouse_falhou
    mov si, msg_mouse_ok
    jmp .mouse_escreve
.mouse_falhou:
    mov si, msg_mouse_falha
.mouse_escreve:
    mov dx, CEL_2
    call TEXTO

; =====================================================================
;  CINCO SEGUNDOS COM AS DUAS LINHAS, E DEPOIS A INTERFACE ASSUME
;
;  A tela fica de pe por 5 segundos, para dar tempo de ler, e so' entao
;  entra a interface, que e' um arquivo separado do driver e que pinta a
;  tela. Quem decide a hora e' o nucleo: ele configurou o video,
;  escreveu o texto e conta o tempo.
;
;  A espera e' contada no PIT, sem BIOS e sem interrupcao. A passagem
;  e' definitiva: a interface nao devolve o controle.
; =====================================================================
    mov cx, TICKS_5S
    call espera_ticks

    ; A assinatura vem antes do salto, e e' conferida no ARQUIVO
    ; carregado, ou seja, no endereco que o ponteiro aponta. Sem ela,
    ; um arquivo errado em 0xA000 seria executado como se fosse
    ; programa, e o processador entraria no meio de um dado sem saber o
    ; que estava fazendo.
    ;
    ; Note que o ponteiro em 0x0606 guarda o ENDEREÇO de carga (0xA000),
    ; nao a assinatura. Comparar a assinatura contra o ponteiro
    ; compararia 0xA000 contra 'G','R' e sempre falharia.
    mov bx, [HANDOFF_IFACE]      ; onde o stage 1 carregou a interface
    test bx, bx
    jz sem_interface            ; ponteiro vazio: arquivo nao veio
    cmp word [bx], ASSIN_IFC_LO  ; 'G','R' no comeco do arquivo
    jne sem_interface
    cmp word [bx+2], ASSIN_IFC_HI ; 'N','!'
    jne sem_interface
    cmp word [HANDOFF_IFACE+2], 0 ; o segmento tem de ser zero, como o ORG
    jne sem_interface

    ; A entrada do modulo e' DEPOIS dos 4 bytes da assinatura. O par
    ; far vai para a pilha e o "retf" salta: e' o mesmo montagem do
    ; "jmp dword" que se usa para chamar o driver, so' que aqui nao ha
    ; retorno, e quem entra e' a interface.
    add bx, 4
    push word [HANDOFF_IFACE+2]  ; CS = 0, como o ORG do interface.asm
    push bx                      ; IP = carga + 4
    retf

; ---- o driver recusou o modo -------------------------------------
; Nao ha framebuffer 640x480: o driver disse que nao conseguiu, e o que
; a tela e' agora e' o que a BIOS deixou. O TEXTO do nucleo nao tem
; janela onde escrever, entao este caminho chama o aviso_bios, a
; unica vez em que o Root OS deixa a BIOS falar com a tela: UMA linha,
; "videoVGA.dr nao configurado". O codigo em HANDOFF_ERRO_NUC
; diferencia os dois casos para quem olhar a memoria: EST_SEM_VGA e'
; "nao achei placa de video", o resto e' "o driver recusou o modo".
; Na tela os dois aparecem a mesma linha, porque para o usuario a
; resposta e' a mesma: o video nao ficou pronto.
.falhou:
    mov ax, [INFO+I_ESTADO]
    cmp ax, EST_SEM_VGA
    je .sem_placa
    mov word [HANDOFF_ERRO_NUC], ERRO_MODO
    call aviso_bios
    cli
    hlt
    jmp $
.sem_placa:
    mov word [HANDOFF_ERRO_NUC], ERRO_SEM_VGA
    call aviso_bios
    cli
    hlt
    jmp $

; ---- a interface nao estava na ISO, ou o ponteiro nao confere ----
; O video continua programado e a tela continua com as duas linhas, so
; que a interface nao entra. Este e' o unico aviso que o nucleo
; consegue DESENHAR, porque aqui o modo grafico ja esta' de pe: ele sai
; pelo mesmo TEXTO das duas linhas, na linha 0, com a fonte do nucleo.
; O codigo em HANDOFF_ERRO_NUC fica junto, para quem olha a memoria.
;
; Este caminho fica DEPOIS do ".falhou" de proposito: um rotulo com
; ponto pertence ao proximo rotulo sem ponto, e colocar "sem_interface"
; no meio do caminho principal faria o ".falhou" passar a pertencer a
; ele, e o "jc .falhou" do MODO deixaria de casar.
sem_interface:
    mov word [HANDOFF_ERRO_NUC], ERRO_SEM_IFACE
    mov si, msg_sem_interface
    mov dx, CEL_0
    call TEXTO
    cli
    hlt
    jmp $

; =====================================================================
;  espera_ticks - a espera das telas, contada no PIT
;
;  O PIT (8253/8254) recebe 1.193182 MHz de um oscilador proprio e
;  divide por um numero de 16 bits. Programando o canal 0 com divisor
;  65536 (os dois bytes do divisor em zero) ele vira um gerador de
;  18.206 Hz, ou seja, um pulso a cada 54.93 ms. Cada tela espera
;  91 pulsos, 4.998 segundos, e o contador comeca do zero a cada espera.
;
;  -------------------------------------------------------------------
;  POR QUE O TEMPO E' CONTADO POR INTERRUPT, E NAO LENDO A PORTA
;
;  A porta 0x40 responde de duas maneiras, e parece leitura de status
;  quando nao e'. Sem o comando de latch, ela devolve o VALOR do
;  contador, que muda a 1.193182 MHz: o bit que se quer olhar muda
;  varias vezes dentro de um pulso. Com o latch, ela devolve o status
;  das saidas, e ai o bit 5 e' mesmo o estado de OUT0. O problema do
;  status e' outro: ele e' um estado de saida, e nao um relogio, e
;  nao ha garantia de que a leitura pegue as duas bordas de um pulso.
;
;  A interrupcao do timer e' o relogio que a propria placa mantem: o
;  canal 0 e' ligado ao IRQ0, e cada pulso gera uma interrupcao, na
;  media exata. O tratamento e' NOSSO: o nucleo troca o handler do
;  INT 08h por um proprio que so' incrementa um contador, avisa o PIC
;  que terminou e devolve o controle. Nenhuma rotina de BIOS entra
;  nesse caminho, e o total de pulsos fica contavel na memoria, o que
;  faz a espera verificavel de fora.
; -------------------------------------------------------------------
; =====================================================================
PIT_CMD      equ 0x43          ; porta de comando do PIT
PIT_C0       equ 0x40          ; dados do canal 0
PIT_MODO_C0  equ 0x34          ; canal 0, lobyte/hibyte, modo 3
PIT_IRQ0     equ 0x08          ; numero da interrupcao do timer
PIC_CMD      equ 0x20          ; comando do PIC 8259
PIC_MASC     equ 0x21          ; mascara do PIC 8259
TICKS_5S     equ 91             ; 91 / 18.206 Hz = 4.998 s

; =====================================================================
;  espera_ticks
;  CX = quantos pulsos contar. Programa o PIT, conta, e devolve a mascara
;  do PIC e os interrupts como estavam. O CX e' destruido.
;
;  Sao duas esperas no boot, as duas de 5 s, e cada uma conta do zero.
;  O contador vive em 0x060E, num endereco fixo do handoff, e por isso
;  da para conferir de fora que a espera foi a pedida: 91 na troca de
;  tela e 91 na passagem para a interface.
;
;  A contagem vem em CX, e nao em BX, porque o corpo da rotina precisa
;  do BX para o endereco do handler do INT 08h. O CX nao e' usado por
;  nada aqui: nem a programacao do PIT, nem a mascara do PIC, nem a
;  comparacao do laco mexem nele.
; =====================================================================
espera_ticks:
    pushf
    cli

    ; ---- o canal 0 a 18.206 Hz, por conta propria ----
    mov al, PIT_MODO_C0
    out PIT_CMD, al
    xor al, al
    out PIT_C0, al               ; 0 na palavra baixa
    out PIT_C0, al               ; 0 na palavra alta = 65536 pulsos

    ; ---- nosso handler no lugar do da BIOS ----
    mov bx, timer_irq
    mov word [PIT_IRQ0*4], bx   ; IVT: offset do handler
    mov word [PIT_IRQ0*4+2], 0   ; IVT: segmento 0, como todo o nucleo
    mov word [HANDOFF_TICKS], 0

    ; ---- garante o IRQ0 ligado no PIC, guardando a mascara ----
    ; No 8259 o bit 1 da mascara significa BLOQUEADO, e nao ligado:
    ; quem nao tem nada a fazer deixa o canal com o bit em 1. Abrir o
    ; IRQ0 e' portanto limpar o bit, e nao liga-lo.
    in al, PIC_MASC
    mov ah, al                   ; a mascara original, para devolver
    and al, 0FEh
    out PIC_MASC, al

    ; ---- conta os pulsos pedidos ----
    sti
.espere:
    cmp word [HANDOFF_TICKS], cx
    jb .espere

    ; ---- devolve a mascara do PIC e os interrupts como estavam ----
    mov al, ah
    out PIC_MASC, al
    popf
    ret

; ---- INT 08h: um pulso do PIT, um incremento, e o PIC avisado ----
; O handler e' curto de proposito: ele existe so' para contar o pulso
; e avisar o PIC. Quem estava Interrupted e' retomado pelo "iret".
timer_irq:
    pushf
    push ax
    mov al, 0x20                 ; EOI: sem isso o PIC nao aceita mais
    out PIC_CMD, al              ; nenhuma interrupcao, e o timer para
    inc word [HANDOFF_TICKS]
    pop ax
    popf
    iret

; =====================================================================
;  chama_modo
;  Monta o par CS:IP na pilha e salta para a entrada do driver, que
;  devolve com "retf". Devolve CF=1 se o driver nao deixou I_ESTADO
;  igual a EST_OK. E' a unica entrada do driver: escrever na tela e'
;  do nucleo (TEXTO, mais acima).
;
;  Nao mexe em SS:SP. O driver salva o par na entrada e o
;  restaura antes do "retf", entao a pilha do nucleo ja volta inteira.
;  Reposicionar SP aqui, como se fez antes, apagava o endereco de
;  retorno do "call" que chamou o driver, e o "ret" final do nucleo
;  saltava para o lugar errado.
; =====================================================================
chama_modo:
    mov bx, [DRV_BASE]
    mov ax, [bx+H_MODO]
    add ax, bx                    ; entrada = base + offset
    mov [HANDOFF_DRIVER], ax
    jmp chama

chama:
    mov word [HANDOFF_SEG], 0     ; o "jmp dword" le 4 bytes: 0600 e 0602
    push 0                        ; CS de retorno
    push .volta                   ; IP de retorno
    jmp dword [HANDOFF_DRIVER]
    ; Nao se mexe em SS:SP aqui. O "call" de quem chamou ja enfileirou o
    ; endereco de retorno na pilha do nucleo, e reposicionar SP aqui
    ; apagaria esse par. E o driver que devolve SS:SP intactos: ele
    ; salva os dois na entrada e restaura antes do "retf".
.volta:
    cmp word [INFO+I_ESTADO], EST_OK
    jne .ruim
    clc
    ret
.ruim:
    stc
    ret

; =====================================================================
;  sem_driver: o stage 1 nao conseguiu deixar um driver utilizavel em
;  0000:0600. Sem driver nao ha framebuffer 640x480 e nao ha modo
;  grafico, entao o TEXTO do nucleo nao tem onde escrever. Este e' o
;  caminho da unica excecao: a BIOS escreve UMA linha dizendo que o
;  driver nao ficou configurado, e o boot para. O codigo do erro fica
;  na memoria junto, para quem olhar.
; =====================================================================
sem_driver:
    mov word [HANDOFF_ERRO_NUC], ERRO_SEM_DRIVER
    call aviso_bios
    cli
    hlt
    jmp $

; =====================================================================
;  aviso_bios
;  A UNICA CHAMADA DE BIOS DO NUCLEO, e ela nao existe para o boot
;  funcionar: existe para o boot FALHAR de um jeito legivel.
;
;  Todo o resto do nucleo escreve a tela pelo TEXTO, na fonte do
;  nucleo, direto na janela que o driver programou. Quando o driver nao
;  programou nada, nao ha janela: o TEXTO escreveria por cima de uma
;  tela que nem existe. A unica saida que sobrou e a da BIOS, no modo
;  texto em que a tela ja esta' (ou que a BIOS pode escolher), e e'
;  por isso que este e' o unico ponto do Root OS que aceita a BIOS
;  falando com a tela. Uma linha, "videoVGA.dr nao configurado", e nada
;  mais: o Root OS nao escreve no modo texto em nenhum outro lugar.
; =====================================================================
aviso_bios:
    push ax
    push bx
    push cx
    push dx
    push bp
    push es
    ; ---- 80x25 em modo texto, que limpa a tela ----
    ; O modo e' escolhido aqui porque o driver pode ter falhado no meio
    ; de uma programacao e deixado a placa em um modo qualquer, onde a
    ; linha abaixo sairia invisivel ou embaralhada.
    mov ax, 0x0003
    int 0x10
    ; ---- uma linha, na linha 1, coluna 0 ----
    ; ES:BP e' a string, e o segmento e' 0 porque a string esta' no
    ; codigo do nucleo, em 0000. DH e' a linha, DL a coluna; BH e' a
    ; pagina, BL o atributo (branco sobre preto).
    xor ax, ax
    mov es, ax
    mov bp, msg_nao_configurado
    mov cx, msg_nao_configurado_fim - msg_nao_configurado
    mov dx, 0x0100
    xor bh, bh
    mov bl, 0x0F
    mov ax, 0x1300
    int 0x10
    pop es
    pop bp
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =====================================================================
;  limpa_tela
;  Pinta a janela 640x480 inteira com a cor de fundo do boot, que e'
;  o preto, o mesmo 0x00 com que o driver limpou a tela no MODO.
;
;  Quem limpa e' o nucleo, e nao a BIOS nem o driver: o conteudo da
;  janela e' do nucleo desde o MODO, e a limpeza do meio do boot (a
;  linha 0 sozinha sai daqui para as duas linhas) e' um desenho como
;  outro. Sao 38400 bytes, 80 por linha, em BYTES_LINHA, e 480 linhas.
;
;  O valor e' 0x00 e nao 0xFF de proposito. Neste modo planar cada byte
;  da janela e' um indice de cor dos quatro planos: 0x00 e' o indice 0
;  (preto) e 0xFF e' o indice 15 (branco). O fundo do boot e' preto, e
;  o TEXTO escreve os bytes da fonte, que tem o pixel aceso em cinza
;  claro. Um
;  fundo branco deixaria o texto quase invisivel. O branco de 0xFF e'
;  a tela da interface, no fim do boot, que e' outro desenho.
; =====================================================================
limpa_tela:
    push ax
    push cx
    push di
    mov ax, 0xA000
    mov es, ax
    xor di, di                   ; a janela inteira, a partir do byte 0
    mov cx, BYTES_LINHA*ALTURA
    xor al, al                    ; 0x00: preto, o fundo do boot
    rep stosb
    pop di
    pop cx
    pop ax
    ret

; =====================================================================
;  TEXTO - o nucleo escreve na tela
;  Uma string, numa celula da grade de 80x30. Quem chama e' o nucleo, e
;  cada linha e' uma chamada: a ordem das chamadas e' a ordem das linhas.
;
;  entrada:  SI = ponteiro da string (0000:offset, terminada em 0)
;            DL = coluna, de 0 a 79
;            DH = linha, de 0 a 29
;
;  Um pixel e' um bit: no modo planar cada endereco da janela em
;  0xA0000 e' um byte que cobre 8 pixels da mesma linha, e como o
;  sequenciador esta com GR00 = 0x00 o "Set/Reset" fica desligado, de
;  modo que a VGA grava esse byte nas quatro camadas de uma vez. O
;  endereco do pixel e' y*80 + x/8, e o bit 7 e' o pixel da esquerda.
;  Dar 0xFF e' branco e 0x00 e' preto, entao nao ha cor a escolher.
; =====================================================================
TEXTO:
    mov ax, 0xA000
    mov es, ax                     ; a janela da VGA
    cld

    ; x = coluna * 8 e y = linha * 16, dois "shl": coluna * 8 vem de um
    ; "shl al,3" com AH zerado, e linha * 16 de um "shl ax,4".
    mov al, dl
    mov ah, 0
    shl ax, 3
    mov [PX], ax                   ; PX e' o cursor: e' ele que o px_byte
    mov al, dh                     ; le, e' por isso que e' ele que anda
    mov ah, 0
    shl ax, 4
    mov [PY], ax

.l:
    lodsb                          ; o "lodsb" le em DS:SI, e DS ja e' 0
    test al, al
    jz .fim                        ; acabou no 0 do fim da string
    call desenha_glifo
    mov ax, [PX]
    add ax, PASSO_X                ; 8 pixels para a proxima celula
    mov [PX], ax
    cmp ax, LARGURA                ; passou da ultima coluna: para
    jb .l
.fim:
    xor ax, ax                     ; quem vem depois e' o MODO, que e'
    mov es, ax                     ; lido de ES:DI; devolve ES = 0
    ret

; =====================================================================
;  desenha_glifo
;  Escreve as 16 linhas do glifo do caractere em AL na posicao PX,PY.
;  Um caractere fora de 32..126 vira o glifo do espaco: e' melhor deixar
;  um buraco em branco do que pintar um caractere errado na tela.
; =====================================================================
desenha_glifo:
    push bx
    push si                       ; o px_byte usa SI para o endereco do
    sub al, FONTE_BASE             ; framebuffer, e quem esta' percorrendo
    cmp al, FONTE_QUANT            ; a string precisa do SI de volta
    jb .glifo_ok
    xor al, al                     ; fora da faixa: glifo 0, o espaco
.glifo_ok:
    mov ah, 0
    shl ax, 4                      ; glifo = FONT + (caractere-32)*16
    add ax, FONT
    mov bx, ax

    mov ax, [PY]
    mov [SY], ax
    mov dx, TAM_CELULA
.linha_glifo:
    mov al, [bx]
    inc bx
    call px_byte
    mov ax, [SY]
    inc ax
    mov [SY], ax
    dec dx
    jnz .linha_glifo
    pop si
    pop bx
    ret

; =====================================================================
;  px_byte
;  AL = mascara dos 8 pixels de uma linha do glifo. Grava UM byte, o da
;  coluna, em y*80 + x/8. O endereco vai em SI porque em modo de 16 bits
;  so' BX, BP, SI e DI servem de endereco: um "[es:dx]" nao assembla.
;  A conta e' y*80, e nao y*320: 320 bytes por linha e' o layout linear
;  do framebuffer, que so' existe quando o CRTC ganha start_addr e
;  line_offset de 640/8. Aqui o CRTC le y*80, e e' esse byte que a
;  janela expoe.
; =====================================================================
px_byte:
    test al, al
    jz .fim                       ; linha em branco: o 0 da limpeza vale
    mov si, [SY]
    mov di, si
    shl si, 6                      ; y * 64
    shl di, 4                      ; y * 16
    add si, di                     ; y * 80
    mov di, [PX]
    shr di, 3                      ; x / 8: qual byte da linha
    add si, di
    mov [es:si], al
.fim:
    ret

; =====================================================================
;  mouse_da_bolinha
;  Chama o mouse.dr e, se o dispositivo respondeu, publica na area de
;  passagem as duas rotinas de que a interface precisa: BOLA, que
;  redesenha, e DORME, que espera o proximo movimento.
;
;  Se o ponteiro nao veio (o arquivo faltou na ISO, ou a assinatura
;  esta' fora do lugar), os dois ponteiros ficam zero. A interface le o
;  primeiro e, vendo zero, para no branco como parava antes de o mouse
;  existir: um ponteiro a mais na area de passagem nao pode virar a
;  unica coisa que trava a tela.
; =====================================================================
mouse_da_bolinha:
    mov word [HANDOFF_BOLA], 0     ; sem isto, um ponteiro velho de
    mov word [HANDOFF_DORME], 0    ; uma tentativa anterior valeria

    ; ---- a IRQ do mouse nao pode cair na BIOS ----
    ; A partir daqui o i8042 pode levantar a IRQ12 a qualquer momento
    ; (cada byte que o dispositivo entrega levanta uma), e o IVT ainda
    ; aponta o vetor 0x74 para o handler que a BIOS deixou. Sem handler
    ; nosso, o processador entra no ROM da BIOS, executa la um `ret` que
    ; le qualquer coisa da pilha e volta para o meio do codigo do
    ; Root OS: foi assim que a bolinha comecou a se pintar sozinha mil
    ; vezes e a tela a piscar. O handler e' o menor possivel - EOI e
    ; IRET: quem trata o mouse de verdade e' o driver, por sondagem, e
    ; aqui so' interessa o processador nao cair fora.
    mov bx, mouse_irq
    mov word [VET_IRQ12*4], bx
    mov word [VET_IRQ12*4+2], 0

    mov bx, [HANDOFF_MOUSE]       ; o stage 1 deixou o endereco de carga
    test bx, bx
    jz .sem_arquivo
    cmp word [bx], ASSIN_MOU_LO    ; 'M','O' no comeco do arquivo
    jne .sem_arquivo
    cmp word [bx+2], ASSIN_MOU_HI  ; 'U','!'
    jne .sem_arquivo
    cmp word [HANDOFF_MOUSE+2], 0  ; o segmento tem de ser zero, como o ORG
    jne .sem_arquivo

    ; A chamada e' a mesma do driver de video: monta-se o par CS:IP na
    ; pilha e salta-se com "jmp dword", porque o driver devolve com
    ; "retf" e o par de retorno tem de estar no mesmo formato. O
    ; endereco da entrada e' o offset do cabecalho mais a base, ja que
    ; um rotulo NASM vem com o ORG dentro.
    mov ax, [bx+H_MOUSE_CFG]
    add ax, bx
    mov [HANDOFF_MOUSE], ax
    mov word [HANDOFF_MOUSE+2], 0
    push 0                        ; CS de retorno
    push .voltou                  ; IP de retorno
    jmp dword [HANDOFF_MOUSE]
.voltou:
    ; ---- os ponteiros da interface so' sao publicados com o
    ;      dispositivo de pe ----
    ; Publicar antes deixaria a interface chamando uma bolinha que
    ; nunca vai andar: o driver falhou, entao nao ha o que pintar.
    cmp word [MOUSE_EST], MEST_OK
    jne .so_volta
    mov word [HANDOFF_BOLA], BOLA     ; a rotina que pinta a bolinha
    mov word [HANDOFF_BOLA+2], 0
    mov word [HANDOFF_DORME], DORME   ; e a que espera o proximo movimento
    mov word [HANDOFF_DORME+2], 0

    ; ---- a bolinha NAO e' pintada aqui ----
    ; Quem pinta a bolinha e' a interface, e so' a interface: nas telas
    ; de boot do nucleo nao ha' bolinha nenhuma. Aparecer antes dela
    ; era um erro de desenho E de contrato - a BOLA e' a rotina da
    ; interface, e uma tela de boot que a chama mostra o ponteiro do
    ; mouse num lugar onde o mouse ainda nem pertence.
    ; O que fica para tras e' so' o "ainda nao pintei nada": sem isso a
    ; primeira BOLA da interface comecaria apagando uma bolinha em
    ; (0,0) que nunca existiu, e o apagamento com centro em 0 gera uma
    ; caixa com X0 = -8, que vira 0xFFF8 e escreve em endereco
    ; selvagem.
    mov word [BOLA_X], 0xFFFF
    mov word [BOLA_Y], 0xFFFF
.so_volta:
    ret

.sem_arquivo:
    mov word [MOUSE_EST], MEST_SEM_ARQUIVO
    ret

; =====================================================================
;  BOLA - a bolinha vermelha
;
;  E' esta a rotina que a interface chama, e nao a interface que
;  desenha a bolinha: quem guarda a posicao e' o driver do mouse, e
;  quem pinta e' o nucleo. A interface so' pede o redesenho e dorme
;  ate o proximo movimento.
;
;  entrada:  AL = o byte de fundo onde a bolinha vai ser pintada. A
;            interface chama com 0xFF, o branco da tela dela; o
;            desenho tambem funciona sobre 0x00, o preto, e por isso
;            o fundo entra por AL em vez de ser um constante aqui
;            dentro. As telas de boot do nucleo NAO chamam a BOLA:
;            a bolinha so' existe dentro da interface.
;  saida:    nada. Quem chamou nao pode contar com registro nenhum
;            depois do "retf", entao todos entram guardados.
;
;  Quem chama a BOLA tres vezes por pacote de mouse (uma por byte do
;  PS/2) so' repinta de verdade quando o ponteiro mudou de lugar: ver
;  o "o ponteiro nao se moveu" mais abaixo, e bola_uniao, que faz o
;  repaint numa passada unica para a bolinha nao piscar.
; =====================================================================
BOLA:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    ; O fundo chega em AL e a cor na constante. Estes dois tem de sair
    ; para a memoria ANTES de qualquer "mov ax, 0xA000": esse "mov"
    ; troca AL por 0x00 e o fundo viraria sempre zero, e a bolinha
    ; pintaria a propria caixa de preto em cima de uma tela branca.
    mov dh, al                     ; DH = o fundo
    mov dl, BOLA_COR               ; DL = a cor da bolinha
    mov [MIXA_FUNDO], dh           ; os dois vao para a memoria antes de
    mov [MIXA_COR], dl             ; qualquer coisa mexer em DX

    mov ax, 0xA000
    mov es, ax                     ; a janela da VGA
    cld

    ; ---- o centro novo, com a bolinha inteira dentro da tela ----
    ; MOUSE_X e MOUSE_Y sao o CENTRO do ponteiro, e nao da bolinha: o
    ; driver nao sabe que a bolinha tem 16 pixels de lado. BOLA_RAIO e'
    ; a folga do raio, e BOLA_LIM_X/Y ja' vem contada de forma que o
    ; centro nestas limites ainda tenha o circulo inteiro dentro: 631
    ; = 639 - 8 e 471 = 479 - 8. O que o driver entrega ja' esta' nes-
    ; tes limites; estes dois ajustes sao so' a rede de seguranca para
    ; um MOUSE_X corrompido, e nao um segundo limite escondido.
    mov cx, [MOUSE_X]
    cmp cx, BOLA_LIM_X
    jle .x_ajustado
    mov cx, BOLA_LIM_X
.x_ajustado:
    cmp cx, BOLA_RAIO
    jge .x_pronto
    mov cx, BOLA_RAIO
.x_pronto:
    mov dx, [MOUSE_Y]
    cmp dx, BOLA_LIM_Y
    jle .y_ajustado
    mov dx, BOLA_LIM_Y
.y_ajustado:
    cmp dx, BOLA_RAIO
    jge .y_pronto
    mov dx, BOLA_RAIO
.y_pronto:

    ; ---- o ponteiro nao se moveu: nao ha' o que repintar ----
    ; Cada byte do PS/2 levanta a IRQ12, e a interface acorda e chama
    ; a BOLA uma vez por byte - tres vezes por pacote, das quais duas
    ; com o ponteiro ainda parado. Repintar nessas duas era trabalho
    ; que existia so' para piscar: a BOLA apagava a bolinha e a pintava
    ; de novo no mesmo lugar, e o CRT, que varre a tela enquanto a CPU
    ; escreve, podia mostrar a janela apagada. Sair antes de tocar na
    ; VGA e' o que faz a bolinha parar de piscar quando o mouse se
    ; move devagar ou fica parado.
    cmp cx, [BOLA_X]
    jne .moveu
    cmp dx, [BOLA_Y]
    je .so_conta
.moveu:

    ; ---- a primeira pintura limpa a caixa do fundo ----
    ; BOLA_X comeca em 0xFFFF, que nao e' uma posicao valida de pixel:
    ; e' o "ainda nao pintei nada", e evita ter um flag a parte. Neste
    ; primeiro caso ainda nao ha' bolinha nenhuma na tela, e' seguro
    ; deixar a caixa do centro novo toda no fundo antes do circulo.
    cmp word [BOLA_X], 0xFFFF
    jne .sem_limpeza
    mov [MIXA_CX], cx
    mov [MIXA_CY], dx
    mov byte [MIXA_MODO], 0        ; so' limpa a caixa
    call caixa_bola
.sem_limpeza:

    ; ---- o movimento, numa passada so' ----
    ; Uma bolinha e' apagada antes de ser redesenhada porque o desenho
    ; de um circulo de 16 pixels cabe num quadrado de 16, e os quatro
    ; cantos do quadrado ficariam para tras de cada movimento. Mas
    ; "apagar a caixa velha" e "pintar a caixa nova" sao duas escritas
    ; separadas na tela, e entre elas a bolinha nao esta' em lugar
    ; nenhum: e' esse o intervalo que o CRT pegava e que fazia a
    ; bolinha piscar. Por isso bola_uniao escreve as DUAS caixas numa
    ; passada unica, com o valor final de cada byte - o que o CRT
    ; encontrar ali, le o que era para ficar.
    call bola_uniao

    ; O centro novo volta de MIXA_CX/MIXA_CY e nao de CX/DX: a uniao
    ; usa os dois como rascunho para montar a caixa, e voltar a ler
    ; deles aqui gravaria o rascunho na bolinha.
    mov ax, [MIXA_CX]
    mov [BOLA_X], ax               ; fica escrito para a proxima
    mov ax, [MIXA_CY]              ; chamada saber onde apagar
    mov [BOLA_Y], ax
.so_conta:
    mov ax, [MOUSE_N]
    mov [BOLA_N], ax               ; e quantos pacotes o mouse mandou
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    retf                           ; a interface chamou com "call dword"

; =====================================================================
;  caixa_bola
;  Escreve a caixa de BOLA_LADO x BOLA_LADO centrada em CX,DX. Com
;  BP = 0 preenche tudo com o fundo DH; com BP = 1 desenha o circulo
;  na cor DL, misturando os dois no mesmo byte da janela.
;
;  O circulo vem de uma tabela de meias-larguras, e nao de uma conta
;  de raio: para cada uma das 16 linhas da caixa, a tabela diz quantos
;  pixels o circulo alcanca para cada lado do centro. Calcular a raiz
;  a cada pixel custaria varias vezes mais codigo para dar o mesmo
;  desenho, e com um erro de arredondamento a mais.
;
;  A mascara e' montada com os 8 pixels do byte, um a um, e o bit
;  entra pela esquerda primeiro: dentro de um byte o bit 7 e' o pixel
;  da esquerda, entao o pixel mais a esquerda tem de ser o primeiro a
;  entrar na mascara, senao a bolinha sairia espelhada.
; =====================================================================

; =====================================================================
;  caixa_bola
;
;     entrada: CX = centro X, DX = centro Y
;              DH = cor de fundo, DL = cor da bolinha
;              BL = modo (0 so' limpa a caixa, 1 desenha o circulo)
;
;  Repinta a caixa de 16x16 em volta do centro: primeiro ela inteira
;  com o fundo, depois o circulo por cima. Sao tres passadas porque o
;  modo 12h e' planar e um byte so' tem UMA cor: os oito pixels que
;  dividem um byte nao podem ser um vermelho e um branco ao mesmo
;  tempo. Quemmistura as duas cores no mesmo byte nao desenha um
;  circulo: desenha oito pixels da cor do byte, e o byte inteiro tem
;  de ser de uma cor so'.
;
;  A mistura se resolve com a MASCARA DE PLANOS do sequenciador
;  (registrador 2, nas portas 0x3C4/0x3C5), que diz em quais das
;  quatro camadas a escrita vale:
;
;      passo 1  todas as camadas, o valor e' o fundo
;      passo 2  so' as camadas que o fundo tem em 0 e a cor tem em 1,
;               o valor e' a mascara do circulo
;      passo 3  so' as camadas que o fundo tem em 1 e a cor tem em 0,
;               o valor e' zero
;
;  Com fundo preto e bolinha vermelha, so' o passo 2 acontece. Com
;  fundo branco e bolinha vermelha, so' o passo 3. Sao as duas
; situacoes que o Root OS usa: a bolinha aparece sobre a tela preta do
;  boot e sobre a tela branca da interface.
; =====================================================================
; =====================================================================
;  caixa_bola
;
;  O fundo, a cor e o modo chegam prontos em MIXA_FUNDO, MIXA_COR e
;  MIXA_MODO: quem chama e' que sabe o que quer. So' o centro vem em
;  registrador, CX:DX - e e' por isso que o fundo NAO pode vir em DH:
;  ali viaja a coordenada Y do centro, e o fundo se perderia no meio do
;  caminho.
; =====================================================================
caixa_bola:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov [MIXA_CX], cx              ; o centro fica guardado: cada
    mov [MIXA_CY], dx              ; linha precisa dele de novo

    ; ---- a geometria da caixa, em bytes da janela ----
    ; A borda esquerda e a de cima sao limitadas a zero aqui, e nao
    ; so' em BOLA: um centro em (0,0) daria X0 = -8, que em 16 bits
    ; vira 0xFFF8, e o byte de onde a linha comeca passaria a valer
    ; 0x1FFF. O laco escreveria 4609 bytes por linha a partir de um
    ; endereco sem relacao com a tela. BOLA ja limita o centro, mas
    ; esta rotina nao pode depender de quem a chama.
    mov ax, cx
    sub ax, BOLA_RAIO              ; AX = o primeiro pixel da caixa
    jnc .x0_pronto
    xor ax, ax                     ; entrou abaixo do zero: 0
.x0_pronto:
    mov [MIXA_X0], ax
    mov bx, ax
    shr bx, 3
    mov [MIXA_B0], bx              ; o primeiro byte da caixa
    add ax, BOLA_LADO-1            ; AX = o ultimo pixel da caixa, e o
    shr ax, 3                      ; byte em que ele cai: sao tres bytes
    inc ax                         ; entre o primeiro e o ultimo, e um
    mov [MIXA_FIMB], ax            ; a mais e' onde o laco para
    mov ax, dx
    sub ax, BOLA_RAIO
    jnc .l0_pronto
    xor ax, ax
.l0_pronto:
    mov [MIXA_L0], ax              ; a primeira linha da caixa: cada
    mov [MIXA_Y], ax               ; passada recomeca' nela, porque as
    mov ax, BOLA_LADO              ; duas usam o mesmo MIXA_Y
    add ax, [MIXA_L0]
    mov [MIXA_FIML], ax            ; uma linha depois da ultima

    ; ---- passo 1: a caixa inteira no fundo ------------------------
    mov al, MIXA_TODAS             ; as quatro camadas
    call planos
    mov al, [MIXA_FUNDO]
    mov [MIXA_VAL], al
    call preenche_caixa

    ; ---- passo 2 e 3: o circulo, so' quando o modo e' desenhar ----
    cmp byte [MIXA_MODO], 1
    jne .fim

    ; As duas mascaras de camada: quais planos o fundo tem em 0 e a cor
    ; tem em 1 (C1, que recebem a mascara do circulo) e quais o fundo
    ; tem em 1 e a cor tem em 0 (C0, que recebem zero).
    mov al, [MIXA_FUNDO]
    not al
    and al, [MIXA_COR]             ; C1: cor em 1, fundo em 0
    mov [MIXA_C1], al
    mov al, [MIXA_COR]
    not al
    and al, [MIXA_FUNDO]            ; C0: fundo em 1, cor em 0. So' estas
    and al, 0x0F                    ; duas camadas mudam no circulo: as
    mov [MIXA_C0], al               ; outras ja' nascem certas na caixa

    cmp byte [MIXA_C1], 0
    jz .sem_c1
    mov al, [MIXA_C1]
    call planos
    mov byte [MIXA_PASSO], 1       ; 1 = escreve a mascara do circulo
    call circulo_caixa
.sem_c1:
    cmp byte [MIXA_C0], 0
    jz .sem_c0
    mov al, [MIXA_C0]
    call planos
    mov byte [MIXA_PASSO], 2       ; 2 = escreve zero
    call circulo_caixa
.sem_c0:
.fim:
    mov al, MIXA_TODAS             ; devolve as quatro camadas, como o
    call planos                    ; driver de video deixou
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =====================================================================
;  bola_uniao
;
;  Repinta a bolinha em UMA passada, percorrendo as duas caixas - a do
;  centro velho e a do centro novo - juntas, do canto que as duas tem
;  em comum ate o canto mais longe. Cada byte da janela ja' e' escrito
;  com o valor final: o fundo onde nao ha' circulo, a cor onde ha'.
;
;  E' esse detalhe que acaba com o piscar. Antes o repaint eram tres
;  escritas: a caixa velha no fundo, a caixa nova no fundo, e o
;  circulo por cima. Entre a primeira e a ultima a bolinha nao estava
;  em lugar nenhum, e o CRT - que varre a tela de cima para baixo
;  enquanto a CPU escreve nela - chegava a varer essa janela e
;  mostrava a bolinha apagada, uma vez por byte do pacote do mouse.
;  Numa passada so' nao existe estado intermediario para ele pegar.
;
;  O que faz o circulo caber na mesma passada e' a mascara de camadas:
;  so' as camadas em que a cor da bolinha difere do fundo mudam, e o
;  valor de cada byte e' o fundo menos a mascara do circulo (C0) ou a
;  mascara do circulo (C1). Fora do circulo o byte leva o fundo, e
;  dentro dele a cor - que e' o que as escritas separadas faziam, sem
;  a bolinha sumir no meio do caminho.
;
;  entrada:  CX/DX = o centro novo, ja' limitado por BOLA
;            MIXA_FUNDO/MIXA_COR = o fundo e a cor da bolinha
;  saida:    nada. CX e DX sao rascunho, e por isso o centro novo
;            fica guardado em MIXA_CX/MIXA_CY.
; =====================================================================
bola_uniao:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov [MIXA_CX], cx              ; o circulo desta passada e' o do
    mov [MIXA_CY], dx              ; centro NOVO

    ; ---- a caixa: a uniao das duas ----
    ; Cada lado comeca' na caixa do centro novo so' recuando para a do
    ; centro velho, e nunca avanca: o que importa e' a caixa que
    ; alcança mais para aquele lado. Um BOLA_X = 0xFFFF e' o "ainda nao
    ; pintei nada", e como 0xFFFF e' maior que qualquer posicao ele
    ; perde a comparacao e some sozinho, sem nenhum teste a parte.
    mov ax, cx
    sub ax, BOLA_RAIO              ; o primeiro pixel do circulo novo
    jnc .x0_novo
    xor ax, ax                     ; entrou abaixo do zero: 0
.x0_novo:
    mov bx, [BOLA_X]
    sub bx, BOLA_RAIO
    jnc .x0_velho
    xor bx, bx
.x0_velho:
    cmp bx, ax
    jae .x0_pronto                 ; o velho nao chega mais a esquerda
    mov ax, bx
.x0_pronto:
    mov [MIXA_X0], ax
    shr ax, 3                      ; o pixel menor e' o byte menor
    mov [MIXA_B0], ax              ; o primeiro byte da uniao
    mov bx, cx
    add bx, BOLA_RAIO              ; o ultimo pixel do circulo novo
    mov di, [BOLA_X]               ; o do velho, com o mesmo raio, e
    add di, BOLA_RAIO              ; fica em DI para comparar: a uniao
    cmp di, bx                     ; vai ate o maior dos dois
    jbe .x1_pronto                 ; o velho nao chega mais a direita
    mov bx, di                     ; senao e' ele que manda
.x1_pronto:
    shr bx, 3
    inc bx                         ; um byte depois do ultimo
    mov [MIXA_FIMB], bx
    mov ax, dx
    sub ax, BOLA_RAIO
    jnc .l0_novo
    xor ax, ax
.l0_novo:
    mov cx, [BOLA_Y]               ; o CX e' rascunho: o centro novo
    sub cx, BOLA_RAIO              ; ja' esta' em MIXA_CX
    jnc .l0_velho
    xor cx, cx
.l0_velho:
    cmp cx, ax
    jae .l0_pronto
    mov ax, cx
.l0_pronto:
    mov [MIXA_L0], ax              ; a primeira linha da uniao
    mov [MIXA_Y], ax               ; e por onde a passada comeca'
    mov bx, dx
    add bx, BOLA_RAIO
    mov di, [BOLA_Y]               ; como no X1: a uniao vai ate a
    add di, BOLA_RAIO              ; linha do velho mais o raio
    cmp di, bx
    jbe .l1_pronto
    mov bx, di
.l1_pronto:
    inc bx                         ; uma linha depois da ultima
    mov [MIXA_FIML], bx

    ; ---- as camadas que mudam ----
    ; As mesmas duas mascaras de caixa_bola: C1 sao as camadas onde a
    ; cor tem 1 e o fundo tem 0, e recebem a mascara do circulo; C0
    ; sao as onde o fundo tem 1 e a cor tem 0, e recebem zero - isto
    ; e', o fundo MENOS a mascara do circulo. Sao as duas situacoes que
    ; o Root OS usa: com fundo preto e bolinha vermelha so' C1
    ; acontece, com fundo branco so' C0.
    mov al, [MIXA_FUNDO]
    not al
    and al, [MIXA_COR]             ; C1: cor em 1, fundo em 0
    mov [MIXA_C1], al
    mov al, [MIXA_COR]
    not al
    and al, [MIXA_FUNDO]            ; C0: fundo em 1, cor em 0
    and al, 0x0F
    mov [MIXA_C0], al

    ; ---- passada das C1, quando ha' alguma ----
    cmp byte [MIXA_C1], 0
    jz .sem_c1
    mov al, [MIXA_C1]
    call planos
    mov byte [MIXA_PASSO], 1       ; 1 = escreve a mascara do circulo
    call circulo_caixa
.sem_c1:
    ; ---- passada das C0 ----
    cmp byte [MIXA_C0], 0
    jz .fim
    mov al, [MIXA_C0]
    call planos
    mov byte [MIXA_PASSO], 2       ; 2 = o fundo menos a mascara
    call circulo_caixa
.fim:
    mov al, MIXA_TODAS             ; devolve as quatro camadas, como o
    call planos                    ; driver de video deixou
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =====================================================================
;  planos
;
;  Escreve em AL a mascara de camadas do sequenciador. Sao DUAS portas:
;  o numero do registrador em 0x3C4 e o valor em 0x3C5. Esquecer o
;  numero seria o erro classico aqui: o registrador fica apontado para
;  outra coisa (o driver deixa o indice no 5, o deslocamento), e a
;  bolinha sai com a cor do byte da sequencia errada.
; =====================================================================
planos:
    push dx                        ; o DX e' restaurado por ultimo: a
    push ax                        ; pilha cresce para baixo, e o topo
    mov dx, VGA_SEQ_IDX            ; tem de ser o AX, que guarda a
    mov al, 2                      ; mascara que entra em AL
    out dx, al
    inc dx                         ; 0x3C5: agora o dado
    pop ax                         ; AL = a mascara, intacta
    out dx, al
    pop dx
    ret

; =====================================================================
;  preenche_caixa
;
;  Escreve MIXA_VAL em todos os bytes da caixa, sem se importar com o
;  desenho. E' o que faz o fundo: a caixa toda na cor de fundo, antes
;  de o circulo ser posto por cima.
; =====================================================================
preenche_caixa:

    mov ax, [MIXA_L0]              ; a passada comeca' na primeira
    mov [MIXA_Y], ax               ; linha da caixa
    push ax
    push bx
    push bp
.linha:
    mov bp, [MIXA_B0]              ; a coluna recomeca' a cada linha:
    mov ax, [MIXA_Y]               ; DI = y * 80, sem multiplicar
    mov di, ax
    shl di, 6                      ; 80 = 64 + 16
    mov bx, ax
    shl bx, 4
    add di, bx
    add di, bp
.byte:
    mov al, [MIXA_VAL]

    mov [es:di], al
    inc di
    inc bp

    cmp bp, [MIXA_FIMB]
    jb .byte
    inc word [MIXA_Y]
    mov ax, [MIXA_Y]
    cmp ax, [MIXA_FIML]
    jb .linha
    pop bp
    pop bx
    pop ax
    ret

; =====================================================================
;  circulo_caixa
;
;  Segunda passada: monta a mascara de 8 pixels de cada byte da caixa e
;  escreve o valor que o MIXA_PASSO pede - a mascara (passo 1) ou zero
;  (passo 2). E' aqui que a linha vira circulo: a tabela de
;  meias-larguras diz quantos pixels o circulo alcana em cada
;  distancia vertical, e a mascara diz quais dos 8 pixels do byte estao
;  dentro.
;
;  A comparacao e' feita com AX inteiro, e nao com AL: um pixel na
;  direita da tela passa de 255, e um AL que virou 0 la colocaria a
;  bolinha no canto esquerdo em vez de acompanhar o mouse.
; =====================================================================
circulo_caixa:
    mov ax, [MIXA_L0]              ; a passada comeca' na primeira
    mov [MIXA_Y], ax               ; linha da caixa
    push ax
    push bx
    push cx
    push bp
.linha:
    mov bp, [MIXA_B0]              ; como em preenche_caixa: sem isto o
                                  ; circulo também vira um risco
    ; ---- a meia-largura do circulo nesta linha ----
    ; A tabela e' lida com "xlat", que e' AL = DS:[BX+AL]. Nao ha
    ; outro jeito em 16 bits: o endereco de um byte so' aceita BX, BP,
    ; SI ou DI como indice, e o indice da tabela aqui cabe em CX. Um
    ; "mov cl,[tabela+cx]" nao assembla, e trocar o papel dos
    ; registradores a cada uso seria pior que o "xlat".
    mov ax, [MIXA_Y]
    sub ax, [MIXA_CY]              ; AX = a distancia vertical, com sinal
    mov cx, ax
    jns .distancia
    neg cx
.distancia:
    ; A tabela so' tem uma entrada por linha da caixa (0 a 8), e a
    ; caixa da uniao passa disso: nas pontas, a linha esta' acima ou
    ; abaixo do circulo e nao ha' meia-largura para ela. Ler a tabela
    ; fora do fim pegaria o proximo dado do programa como raio, e a
    ; bolinha ganharia um chapeu. Estas linhas vao com a mascara
    ; vazia - e o salto vai para DEPOIS do calculo do endereco do
    ; byte, porque a linha continua precisando do DI e do MIXA_PX
    ; para escrever o fundo nela.
    cmp cx, BOLA_RAIO
    jbe .meia_ok
    mov word [MIXA_XMIN], 0xFFFF   ; nenhum pixel pode satisfazer os
    mov word [MIXA_XMAX], 0        ; dois limites ao mesmo tempo
    jmp .endereco
.meia_ok:
    mov al, cl
    mov bx, BOLA_MEIA              ; BX = o endereco da tabela
    xlat                            ; AL = BOLA_MEIA[distancia]
    mov [MIXA_MEIA], al

    ; ---- onde o circulo começa e termina nesta linha ----
    mov ax, [MIXA_CX]
    sub ax, [MIXA_MEIA]            ; a borda esquerda do circulo
    mov [MIXA_XMIN], ax
    mov ax, [MIXA_CX]
    add ax, [MIXA_MEIA]            ; e a direita
    mov [MIXA_XMAX], ax

.endereco:
    mov ax, [MIXA_Y]               ; DI = y * 80 + o byte da caixa
    mov di, ax
    shl di, 6
    mov bx, ax
    shl bx, 4
    add di, bx
    add di, bp
    mov ax, bp
    shl ax, 3                      ; AX = o primeiro pixel do byte
    mov [MIXA_PX], ax
.byte:
    ; ---- a mascara: 8 pixels, o mais a esquerda primeiro ----
    mov ax, [MIXA_PX]
    xor cx, cx                      ; CX = a mascara do byte
    mov bx, 8
.px:
    cmp ax, [MIXA_XMIN]
    jb .fora
    cmp ax, [MIXA_XMAX]
    ja .fora
    shl cx, 1
    inc cx                          ; dentro do circulo
    jmp .proximo
.fora:
    shl cx, 1
.proximo:
    inc ax                         ; o pixel que vem a seguir esta' no
    inc word [MIXA_PX]             ; registrador: e' AX que o laco
    dec bx                         ; compara, e nao so' a memoria. Sem
    jnz .px                        ; o "inc ax" o byte inteiro repetia

    ; ---- o valor do byte, conforme o passo ----
    cmp byte [MIXA_PASSO], 1
    jne .zera
    mov [MIXA_TMP], cx             ; a mascara do circulo
    jmp .escreve
.zera:
    ; No passo 2 as camadasEnabled sao as que o fundo tem em 1 e a cor
    ; nao tem: dentro do circulo elas precisam virar 0, e fora do
    ; circulo precisam CONTINUAR como o fundo. Por isso o que se escreve
    ; e' o complemento da mascara do circulo, e nao zero: zero aqui
    ; apagaria a caixa inteira e a bolinha viraria um bloco da cor,
    ; do tamanho da caixa, em vez de um circulo.
    not cx
    mov [MIXA_TMP], cx
.escreve:
    mov al, [MIXA_TMP]
    mov [es:di], al
    inc di
    inc bp
    cmp bp, [MIXA_FIMB]
    jb .byte
    inc word [MIXA_Y]
    mov ax, [MIXA_Y]
    cmp ax, [MIXA_FIML]
    jb .linha
    pop bp
    pop cx
    pop bx
    pop ax
    ret

; =====================================================================
;  mouse_irq
;
;  INT 74h, a IRQ12 do i8042. O IVT aponta para aqui desde o começo de
;  mouse_da_bolinha, e o que este codigo faz e' o minimo: avisar ao PIC
;  que a interrupcao foi atendida e devolver. Sem o EOI o 8259 para de
;  aceitar interrupcoes depois da primeira; sem o handler, o processador
;  entraria no ROM da BIOS (veja o comentario da instalacao).
; =====================================================================
mouse_irq:
    push ax
    push dx
    mov al, 0x20                 ; A IRQ12 e' do PIC SLAVE, e uma
    out PIC_CMD_S, al            ; interrupcao que veio por ele e'
    mov al, 0x20                 ; avisada nos dois: no slave primeiro,
    out PIC_CMD, al              ; e no master depois. Avisar so' o
    pop dx                       ; master deixava o slave com a IRQ12
    pop ax                       ; marcada, e o master com a cascata
    iret                         ; marcada: nenhuma outra interrupcao

; =====================================================================
;  DORME - espera o mouse mexer
;
;  A interface chama esta rotina entre um repaint e o seguinte. Ela
;  nao desenha nada: ela fecha a mascara dos dois PICS, abre so' a
;  IRQ que o mouse.dr declarou, e dorme no "hlt".
;
;  Fechar as outras IRQ e' o que faz a interface gastar zero CPU: o
;  PIT continua batendo a 18 pulsos por segundo, e o teclado continua
;  com a IRQ1 habilitada, mas com a mascara fechada nenhum dos dois
;  acorda o processador. Sem isso, o "hlt" voltaria dezoito vezes por
;  segundo para repintar uma bolinha que nao se mexeu.
;
;  A IRQ do mouse esta' no PIC slave, porque e' a 12. O slave so'
;  chega a falar com a CPU se a cascata (a IRQ2) estiver aberta no
;  master, entao abrir uma e' abrir as duas.
;
;  O numero da IRQ vem de MOUSE_IRQ, escrito pelo driver: 12 e' um
;  dado do i8042, e cravar o numero aqui seria deixar o nucleo com o
;  mouse na mao, que e' justamente o que o driver existe para evitar.
; =====================================================================
DORME:
    push ax
    push bx
    push cx
    mov cx, [MOUSE_IRQ]            ; a IRQ que o driver declarou

    ; ---- as duas mascaras fechadas, e so' a cascata aberta ----
    ; O PIT continua batendo a 18 pulsos por segundo e o teclado
    ; continua com a IRQ1 habilitada, mas com a mascara fechada nenhum
    ; dos dois acorda o processador. Sem isso, o "hlt" abaixo voltaria
    ; dezoito vezes por segundo para repintar uma bolinha parada, e a
    ; interface gastaria CPU acordando sem motivo.
    mov al, PIC_TUDO                ; slave: todas as IRQ bloqueadas
    out PIC_MASC_S, al
    mov al, PIC_CASCATA             ; master: todas, menos a IRQ2
    out PIC_MASC, al               ; (a cascata e' o caminho do slave)

    ; ---- abre so' a IRQ do mouse, no PIC que a numera ----
    ; No 8259 o bit 1 da mascara significa BLOQUEADO, e nao ligado: quem
    ; nao tem nada a fazer deixa o canal com o bit em 1. Abrir uma IRQ
    ; e' portanto limpar o bit dela, e nao liga-lo.
    cmp cx, 8
    jae .abre_slave
    mov bx, 1
    shl bx, cx                     ; o numero da IRQ, virado em bit
    mov al, PIC_TUDO
    not bx
    and al, bl
    out PIC_MASC, al               ; IRQ do master
    jmp .dorme
.abre_slave:
    sub cx, 8                      ; o numero dentro do slave
    mov bx, 1
    shl bx, cx
    mov al, PIC_TUDO
    not bx
    and al, bl
    out PIC_MASC_S, al             ; IRQ do slave
    sti                             ; as interrupcoes vem ANTES do hlt,
                                    ; e nao depois: quem acorda o hlt e'
                                    ; justamente a IRQ do mouse
.dorme:
    hlt                             ; so' a IRQ do mouse tira daqui
    pop cx
    pop bx
    pop ax
    retf                           ; a interface chamou com "call dword"

; ============================== DADOS ==============================
; Cursor e linha do desenho. O PX anda de 8 em 8; o PY fica na linha
; pedida e o SY e' a linha do glifo que esta' saindo.
PX:           dw 0
PY:           dw 0
SY:           dw 0

; 'VGA!' lido como dois words em memoria, byte baixo primeiro:
;   word 0 = 'V' 'G' = 0x56 | (0x47 << 8) = 0x4756
;   word 1 = 'A' '!' = 0x41 | (0x21 << 8) = 0x2141
ASS_VGA     equ 0x4756
ASS_EXPL    equ 0x2141
; Assinatura 'GRN!' do interface.grain, nos mesmos dois words do
; 'VGA!' do driver: byte baixo primeiro, como sempre.
ASSIN_IFC_LO equ 0x5247        ; 'G','R'
ASSIN_IFC_HI equ 0x214E        ; 'N','!'
; Assinatura 'MOU!' do mouse.dr, nos mesmos dois words.
ASSIN_MOU_LO equ 0x4F4D        ; 'M','O'
ASSIN_MOU_HI equ 0x2155        ; 'U','!'
H_MOUSE_CFG equ 6              ; offset da entrada 1 no cabecalho do
                              ; mouse.dr, como H_MODO no do driver
DRV_BASE:   dw 0                    ; copia estavel da base do driver
msg_nucleo:     db "kernel-0.5.2026", 0
msg_sucesso:    db "videoVGA.dr configurado com sucesso", 0
msg_mouse_ok:   db "mouse.dr configurado com sucesso", 0
; A linha do mouse que nao respondeu. Sem acento, como todas: a fonte
; e' so' de 32 a 126. O boot NAO para aqui: a interface entra do mesmo
; jeito, so' sem a bolinha, porque um mouse que falta e' motivo para
; perder um ponteiro, nao para perder a tela.
msg_mouse_falha: db "mouse.dr nao configurado", 0
; A linha do aviso de erro do video. Os tres casos que levam ate ela (sem
; driver, driver recusou o modo, placa nao encontrada) mostram a MESMA
; linha, porque e' a mesma resposta para o usuario: o video nao ficou
; pronto. A diferenca entre eles fica em HANDOFF_ERRO_NUC, na memoria.
; O texto vai para a BIOS, e nao para o TEXTO: sem video programado o
; TEXTO nao tem janela. Nao ha acento porque a fonte e' de 32 a 126.
msg_nao_configurado:
    db "videoVGA.dr nao configurado"
msg_nao_configurado_fim:
    db 0
; A interface e' a excecao do outro lado: o video ja esta' de pe quando
; ela falta, entao esse aviso sai pelo TEXTO, na tela grafica.
msg_sem_interface: db "interface.grain nao foi encontrado", 0

; --- dados da bolinha ---
; A tabela de meias-larguras: para uma distancia vertical de 0 a 8
; pixels, quantos pixels o circulo alcanca para cada lado do centro.
; Sao 9 bytes, lidos com "xlat" (veja a nota em caixa_bola). Os
; valores vem de floor(sqrt(64 - d^2)), com raio 8: em d = 7 sobra
; 15, e sqrt(15) e' 3.87, entao o circulo ali ja' cabe em 3 pixels.
BOLA_MEIA:   db 8,7,7,7,6,6,5,3,0

; Area de trabalho de caixa_bola. Sao campos separados e nao
; registradores porque a rotina usa todos os seis ao mesmo tempo: o
; centro, o fundo e a cor ficam fixos durante as 16 linhas, e cada
; linha precisa dos quatro lados ao mesmo tempo.
MIXA_CX:     dw 0              ; centro X
MIXA_CY:     dw 0              ; centro Y
MIXA_X0:     dw 0              ; primeiro pixel da caixa
MIXA_L0:     dw 0              ; primeira linha da caixa
MIXA_B0:     dw 0              ; primeiro byte da caixa
MIXA_FIMB:   dw 0              ; um byte depois do ultimo da caixa
MIXA_Y:      dw 0              ; a linha que a caixa esta' Pintando
MIXA_FIML:   dw 0              ; uma linha depois da ultima
MIXA_PX:     dw 0              ; primeiro pixel do byte corrente
MIXA_XMIN:   dw 0              ; borda esquerda do circulo na linha
MIXA_XMAX:   dw 0              ; borda direita
MIXA_MEIA:   dw 0              ; meia-largura do circulo na linha
MIXA_TMP:    dw 0              ; a mascara de 8 pixels do circulo
MIXA_VAL:    db 0              ; o valor a escrever na passada do fundo
MIXA_PASSO:  db 0              ; 1 = mascara do circulo, 2 = zero
MIXA_C1:     db 0              ; camadas que o fundo tem em 0
MIXA_C0:     db 0              ; camadas que o fundo tem em 1
MIXA_FUNDO:  db 0              ; o byte de fundo de entrada
MIXA_COR:    db 0              ; a cor da bolinha
MIXA_MODO:   db 0              ; 0 = so' limpa, 1 = desenha o circulo

; ============================== FONTE ==============================
; A fonte e' do nucleo: o texto e' conteudo do sistema, e quem escreve
; na tela e' o nucleo. O driver so' programa a placa e limpa a tela,
; entao nao tem fonte nenhuma dentro.
;
; O rotulo FONT e' o que o TEXTO usa: glifo = FONT + (caractere-32)*16.
; O "%include" cola aqui os 95 glifos de 16 bytes, 32 ate 126.
FONT:
%include "fonte8x16.inc"
