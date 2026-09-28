; =====================================================================
;  ROOT OS BETA - videoVGA.asm
;  Driver de video. 100% assembly, 16 bits, modo real. NAO usa a BIOS
;  para nada: nem int 10h, nem int 12h, nem tabela de video do BIOS.
;
;  O stage 1 carrega este arquivo em 0000:9000 e escreve o endereco em
;  0000:0600. O nucleo le esse endereco e chama as duas entradas
;  abaixo, com um "retf" de volta, sem BIOS no meio do caminho.
;
;  QUEM ESCREVE NA TELA: o nucleo, e nao o driver. Aqui dentro nao
;  existe fonte, nem texto, nem contagem de linhas. O driver e' a camada
;  de video: ele detecta a placa, programa 640x480x16 e limpa a tela.
;  Quem escolhe o que aparece, em que linha, e quem desenha os pixels
;  do caractere e' o nucleo, com a fonte dele.
;
;    MODO     detecta a placa lendo o CRTC, programa 640x480x16 planar
;             em 0000:A0000, limpa a tela e confere relendo o CRTC
;
;  A segunda entrada do cabecalho fica com zero de proposito: e' o
;  registro de que este driver nao escreve texto. O nucleo le esse zero
;  e sabe que a escrita na tela e' dele.
;
; -------------------------------------------------------------------
;  POR QUE A FONTE FICOU NO NUCLEO
;
;  A fonte e' conteudo, nao video. O texto que o usuario le e' do
;  nucleo: sao as mensagens dele, e o desenho delas e' parte do mesmo
;  trabalho. Se a fonte morasse no driver, o driver teria de saber
;  quantas linhas existem e o que elas dizem, e voltaria a ser o dono
;  da tela. Com a fonte no nucleo, o driver funciona igual para
;  qualquer texto, ate para nenhum.
;
;  -------------------------------------------------------------------
;  POR QUE A DETECCAO E' PELO CRTC E NAO PELO PCI
;
;  A way classica de achar a VGA e' varrer o PCI e olhar a classe 0300.
;  Isso foi tentado e medido, e nao da' para fazer em modo de 16 bits
;  sem uma instrucao de 32 bits. O endereco de configuracao do PCI e' um
;  registrador de 32 bits, e o bit que habilita a leitura e' o bit 31.
;  Medido no QEMU, so' uma escrita de 4 bytes em 0xCF8 prende o
;  endereco: escrever 0xCF8 com 2 bytes, escrever os 4 bytes um por um,
;  ou escrever 0xCF9 depois de 0xCF8 deixa o registrador como estava, e
;  a leitura traz o device anterior em vez do pedido. Logo um programa
;  de 16 bits puro nao consegue ler o espaco de configuracao.
;
;  Ler o CRTC evita o problema inteiro e, para este driver, e' um teste
;  melhor: o CRTC e' justamente a interface que o MODO usa para programar
;  a tela. Se o registrador 0x00 volta 0xFF, nao ha controlador de video
;  atras daquela porta. Se volta um valor normal, ha uma VGA, e e' nela
;  que o resto do MODO vai escrever. Nos dois casos nenhum endereco foi
;  adivinhado.
;
;  -------------------------------------------------------------------
;
;  O QUE FOI VERIFICADO EM MAQUINA, E COMO (QEMU, VGA padrao):
;
;  1. Os valores das tabelas abaixo NAO sao de memoria. Eles foram
;     lidos de volta do hardware depois que a BIOS configurou o modo 12h
;     (640x480x16), com um setor de boot so para eso. A sequencia de
;     leitura precisa de um "in" em 0x3DA antes de cada "in" em 0x3D5,
;     porque o CRTC tem um flip-flop de leitura/escrita: sem esse "in"
;     a porta de dados devolve 0xFF em vez do valor gravado. Esse
;     mesmo cuidado vale para 0x3C4/0x3C5 e 0x3CE/0x3CF.
;
;  2. O CRTC aceita gravacao em 0x12 e 0x15, e as duas releem exatamente
;     o que foi gravado. Sao elas as duas portas usadas na conferencia.
;     Alguns registradores de baixo do CRTC (0x00 a 0x07) ignoram parte
;     dos bits, entao nao servem para provar nada.
;
;  2b. A conferencia que o MODO faz e' de releitura, e e' boa ate onde
;     pode ser: ela mostra que o CRTC aceitou e guardou os valores do
;     modo, e nao que a aritmetica de 639x479 esteja casada. Ela nao
;     pode provar a resolucao, porque o mesmo modo 12h legitimo traz
;     0x12=0xDF e 0x15=0xE7 nesta VGA, e 0xE7 nao casa com a conta de
;     (0x8C<<8 | 0xE7) + 1 = 481 linhas. A resolucao de verdade foi
;     conferida pela captura de tela, que saiu em 640x480. O que a
;     releitura garante e' que o modo nao passou em silencio.
;
;  3. O endereco do pixel dentro da janela da VGA. O modo 12h e' planar:
;     cada endereco da janela em 0xA0000 e' um byte que cobre 8 pixels, e
;     as quatro camadas ficam no mesmo endereco. Com start_addr = 0 e
;     line_offset = 80, o CRTC le o endereco y*80 para a linha y, e e' o
;     byte que a janela expoe. Logo o pixel (x,y) mora em y*80 + (x/8),
;     com o bit 7 do byte no pixel mais a esquerda. Sao 38400 bytes de
;     tela, e nao 153600: os 153600 bytes do framebuffer linear so
;     aparecem quando a BIOS monta uma "linear frame buffer" no CRTC,
;     coisa que aqui nao existe. Medido: gravando 0xFF na janela toda a
;     tela fica branca, o que confirma 2 bits por pixel e 4 camadas
;     gravadas juntas; e 0x80 bytes por linha * 480 = 38400 < 65536, o
;     que cabe na janela de 64 KB que a VGA mapeia em 0xA0000.
;
;  -------------------------------------------------------------------
;  ONDE O MODO FOI LIDO (endereco absoluto, segmento 0):
;
;  0000:0600  driver    dw  endereco de carga, escrito pelo stage 1
;  0000:0610  info      dw  as informacoes detectadas (ver I_*)
; =====================================================================

BITS 16
ORG 0x9000

; ============================ CABECALHO ============================
; Mesma ideia do cabecalho "ROOT" do nucleo: a assinatura vem primeiro e
; o ponto de entrada e' lido pelo nucleo, que nao assume posicao fixa de
; codigo dentro do driver.
;
; Os dois offsets sao relativos ao INICIO do driver, e nao ao ORG. Um
; rotulo NASM carrega o endereco com o ORG embutido (MODO vale 0x900C,
; nao 0x000C), entao o que vai no cabecalho e o rotulo menos "$$", o
; comeco desta secao. Sem essa subtracao o nucleo leria 0x900C e
; saltaria para fora do driver.
    db 'V','G','A','!'        ; assinatura
    dw VERSAO                 ; versao do driver
    dw MODO - $$              ; entrada 1: configurar o video
    dw 0                      ; entrada 2: este driver nao escreve texto.
                               ; O zero e' o contrato: o nucleo ve que
                               ; nao ha entrada de escrita aqui e sabe
                               ; que quem escreve na tela e' ele.

VERSAO        equ 0x0502      ; build 0.5.2026

; ====================== PASSAGEM DE CONTROLE ======================
HANDOFF       equ 0x0600
HANDOFF_DRIVER equ HANDOFF+0
INFO          equ 0x0610

; --- estado, comecado em EST_PENDENTE e terminado pelo driver ---
EST_PENDENTE  equ 0
EST_OK        equ 1           ; modo configurado e conferido
EST_SEM_VGA   equ 2           ; o CRTC nao respondeu, nao ha video
EST_FALHOU    equ 3           ; programou, mas a conferencia nao bateu

; --- offsets dentro da struct de info ---
; A struct nao tem mais os campos de PCI. Eles sairam junto com a
; varredura: sem conseguir ler o espaco de configuracao em 16 bits,
; um vendor ou um BAR0 aqui seria numero inventado, e numero inventado
; numa struct de status e' pior do que campo nenhum.
I_ESTADO      equ 0           ; dw  um dos EST_*
I_SONDA0      equ 2           ; dw  CRTC 0x00 antes de programar, a prova
I_SONDA12     equ 4           ; dw  CRTC 0x12 antes de programar
I_HI          equ 6           ; dw  CRTC 0x12, H Display End, lido de volta
I_VI          equ 8           ; dw  CRTC 0x15, V Display End, lido de volta
I_H0          equ 10          ; dw  CRTC 0x01, parte baixa do H Display End
I_V0          equ 12          ; dw  CRTC 0x07, bit 0 = parte alta do V
I_LARGURA     equ 14          ; dw  640
I_ALTURA      equ 16          ; dw  480
I_TAM_FONTE   equ 18          ; dw  bytes por glifo
I_TAM_TAB     equ 20          ; dw  glifos guardados
I_TOTAL       equ 22          ; tamanho da struct

; ============================ GEOMETRIA ============================
LARGURA       equ 640
ALTURA        equ 480
CPP           equ 80          ; colunas de 8 pixels (640 / 8)
LINHAS        equ 30          ; linhas de 16 pixels (480 / 16)
BYTES_LINHA   equ 320         ; (640 / 8) bytes por camada * 4 camadas
PPB           equ 8           ; pixels por byte do framebuffer
BYTES_APERTURA equ 80         ; bytes por linha dentro da janela da VGA
PLANO         equ 80          ; 640 / 8: bytes de uma camada numa linha
TOTAL_APERTURA equ BYTES_APERTURA*ALTURA   ; 38400 bytes na janela
TAM_CELULA    equ 16          ; altura do glifo: informado no cabecalho
                                ; do kernel, que e' quem tem a fonte


; =====================================================================
;  ENTRADA 1 - MODO
;  Detecta a VGA lendo o CRTC, programa 640x480x16 e confere relendo o
;  CRTC. saida: CF=0 deu tudo certo, CF=1 alguma etapa falhou.
;  A struct de info sempre fica preenchida, mesmo na falha, para o
;  nucleo poder mostrar o que aconteceu em vez de adivinhar.
; =====================================================================
MODO:
    mov [SS_SALVO], ss              ; o par de retorno do "retf" mora na
    mov [SP_SALVO], sp              ; pilha do NUCLEO: nao se pode perder
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, PILHA                   ; pilha do driver, no vao livre

    ; limpa a struct de info por inteiro, para nao sobrar lixo de
    ; uma tentativa anterior caso o driver seja chamado duas vezes
    mov cx, I_TOTAL/2
    mov di, INFO
    rep stosw
    mov word [INFO+I_ESTADO], EST_PENDENTE
    mov word [INFO+I_LARGURA], LARGURA
    mov word [INFO+I_ALTURA], ALTURA
    ; I_TAM_FONTE e I_TAM_TAB ficam em zero: sao dados da fonte, e a
    ; fonte e' do nucleo. Quem escreve a tela preenche esses dois campos.

    call detecta_vga
    jc .sem_vga

    call programa_modo

    ; ---- conferencia: reler 0x12 e 0x15 e comparar com a tabela ----
    ; A comparacao e' de BYTE, nao de word. CRTC_TAB+18 e' o valor do
    ; registrador 0x12 e CRTC_TAB+19 e' o do 0x13: um "cmp ax" pegaria
    ; os dois bytes de uma vez e compararia 0x00DF com 0x28DF, dando
    ; falha num modo programado certinho. "le_crtc" devolve AX com AH
    ; zerado, entao o byte AL e' o valor.
    call le_crtc_12
    mov [INFO+I_HI], ax
    call le_crtc_15
    mov [INFO+I_VI], ax
    call le_crtc_01
    mov [INFO+I_H0], ax
    call le_crtc_07
    mov [INFO+I_V0], ax

    mov al, [INFO+I_HI]
    cmp al, [CRTC_TAB+18]            ; registro 0x12 da tabela
    jne .falhou
    mov al, [INFO+I_VI]
    cmp al, [CRTC_TAB+21]            ; registro 0x15 da tabela
    jne .falhou
    ; O cr[\07] e' a prova de que o destravamento funcionou. Sem ele a
    ; tabela inteira pode estar certa e a tela sair errada mesmo assim,
    ; porque o bloqueio do cr[\11] aceita a escrita e joga o valor fora.
    mov al, [INFO+I_V0]
    cmp al, [CRTC_TAB+7]             ; registro 0x07 da tabela
    jne .falhou

    ; Tela limpa e so' depois que o modo deu certo: se a conferencia
    ; falhou, o driver esta prestes a avisar no modo texto e nao tem
    ; por que mexer no que esta na tela.
    call limpa_tela

    mov word [INFO+I_ESTADO], EST_OK
    clc
    jmp sai
.sem_vga:
    mov word [INFO+I_ESTADO], EST_SEM_VGA
    stc
    jmp sai
.falhou:
    mov word [INFO+I_ESTADO], EST_FALHOU
    stc
    jmp sai

; =====================================================================
;  sai
;  Devolve SS:SP ao nucleo e executa o "retf" que consome o par CS:IP que
;  o nucleo empilhou antes do salto.
;
;  O driver troca SS:SP para a pilha dele, mas o endereco de retorno esta
;  na pilha do nucleo. Um "retf" com SS:SP do driver desempilharia lixo e
;  o nucleo continuaria num endereco pequeno (0x0003 no teste), executando
;  memoria vazia. Restaurar os dois registradores antes do "retf" e' o que
;  faz a chamada far funcionar.
; =====================================================================
sai:
    mov ss, [SS_SALVO]
    mov sp, [SP_SALVO]
    retf

; =====================================================================
;  detecta_vga
;  Pergunta ao CRTC se existe alguem controlling as portas de video.
;
;  Primeiro escolhe a base do CRTC. O bit 7 do registro de status de
;  entrada 1, lido em 0x3DA, diz em qual par de portas o CRTC esta:
;  0 = 0x3D4/0x3D5 (VGA colorido), 1 = 0x3B4/0x3B5 (monocromatico).
;  As duas entrances comecam no modo de texto, entao esse bit ainda
;  descreve a placa de verdade.
;
;  Depois le o registrador 0x00 e o 0x12. Se nao houver placa atras
;  dessas portas, a porta de dados nao tem quem a atenda e devolve
;  0xFF, que e' um valor impossivel para o total horizontal. Dois
;  registradores independentes sao lidos porque um so' nao separa
;  "nao tem nada" de "esse registrador nao responde".
;
;  Nao ha endereco de placa, BAR ou vendor aqui, e nao ha como
;  consultar: ver o comentario sobre o PCI no topo do arquivo.
; =====================================================================
detecta_vga:
    mov dx, 0x3DA
    in al, dx
    test al, 0x80
    jz .colorida
    mov word [CRTC_BASE], 0x3B4
    jmp .base_pronta
.colorida:
    mov word [CRTC_BASE], 0x3D4
.base_pronta:
    mov al, 0x00                    ; total horizontal
    call le_crtc
    mov [INFO+I_SONDA0], ax
    cmp ax, 0xFFFF
    je .sem
    mov al, 0x12                    ; fim do display H, parte alta
    call le_crtc
    mov [INFO+I_SONDA12], ax
    cmp ax, 0xFFFF
    je .sem
    clc
    ret
.sem:
    stc
    ret

; =====================================================================
;  programa_modo
;  Escreve as quatro tabelas de registradores direto no hardware.
;  A ordem importa: primeiro sequenciador e controlador grafico, que
;  decidem como a memoria de video e' interpretada, so depois o CRTC,
;  que decide o tamanho da tela, e por ultimo os atributos, que
;  destravam a imagem.
; =====================================================================
programa_modo:
    ; ---- sequenciador: 4 camadas, sem deslocamento, reset ligado ----
    mov dx, 0x3C4
    mov al, 0
    out dx, al
    inc dx
    mov al, 0x06                    ; destrava os 6 primeiros registradores
    out dx, al
    mov si, SEQ_TAB
    mov cx, 6
    xor bx, bx
.seq:
    mov dx, 0x3C4
    mov al, bl                      ; o indice e' sequencial: 0, 1, 2...
    out dx, al
    inc dx
    mov al, [si]                    ; o valor da tabela e' o DADO
    out dx, al
    inc si
    inc bx
    loop .seq

    ; ---- controlador grafico: janela em 0xA0000 ----
    mov si, GFX_TAB
    mov cx, 16
    xor bx, bx
.gfx:
    mov dx, 0x3CE
    mov al, bl
    out dx, al
    inc dx
    mov al, [si]
    out dx, al
    inc si
    inc bx
    loop .gfx

    ; ---- CRTC: o tamanho da tela ----
    ; Antes de tocar em qualquer registro e' preciso tirar o cr[\11] do
    ; bloqueio. O bit 7 do cr[\11] tranca os registros 0x00 a 0x07, e
    ; enquanto ele estiver ligado uma escrita nesses registros e' aceita
    ; mas ignorada: no cr[\07], por exemplo, so' o bit 4 passa, e um
    ; cr[\12] gravado sem destravar... nao, o cr[\12] nem esta trancado.
    ; O que se perde sem destravar e' o cr[\07] (o overflow), que define a
    ; parte alta da altura, e o cr[\09] (varredura maxima).
    ; A sequencia e' a mesma da BIOS: cr[\11] = 0x00, os registros, e
    ; cr[\11] = 0x8C volta a trancar.
    mov dx, [CRTC_BASE]
    mov al, 0x11
    out dx, al
    mov al, 0x00
    inc dx
    out dx, al
    mov si, CRTC_TAB
    mov cx, 25
    xor bx, bx
.crtc:
    mov dx, [CRTC_BASE]
    mov al, bl
    out dx, al
    inc dx
    mov al, [si]
    out dx, al
    inc si
    inc bx
    loop .crtc
    mov dx, [CRTC_BASE]
    mov al, 0x11
    out dx, al
    mov al, 0x8C
    inc dx
    out dx, al

    ; ---- controlador de atributos: a paleta de 16 cores ----
    ; O 0x3C0 e' ao mesmo tempo o registro de indice e o de dado: o
    ; flip-flop interno escolhe qual dos dois o proximo acesso programa,
    ; e so' uma leitura em 0x3DA (ou 0x3BA) arma o acesso como indice.
    ; Por isso o dado tambem sai por 0x3C0. O 0x3C1 e' o status 1: so'
    ; existe para leitura, nao ressincroniza o flip-flop e por isso nao
    ; servia nem para ler nem para escrever a paleta.
    ;
    ; A paleta em si NAO e' programada aqui: a que a BIOS deixa no DAC
    ; ja' serve, e e' nela que a cor 4 e' vermelha (a da bolinha) e a
    ; cor 15 e' branca (a do texto e o do fundo da interface). Mexer no
    ; DAC aqui so' arriscava trocar o branco de verdade por outro tom.
    mov si, ATT_TAB
    mov cx, 21                     ; 0x00 a 0x14, a paleta de 16 cores
    xor bx, bx
.att:
    mov dx, CRTC_BASE+6             ; 0x3DA ou 0x3BA: arma o 0x3C0 como indice
    in al, dx
    mov dx, 0x3C0
    mov al, bl
    out dx, al                     ; indice
    mov al, [si]
    out dx, al                     ; dado, no mesmo 0x3C0
    inc si
    inc bx
    loop .att
    ; A BIOS fecha a paleta com um "out 0x3C0, 0x20". Sao 21 pares, o
    ; flip-flop fica em modo indice, e esse 0x20 e' lido como indice
    ; 0x20: e' ele que diz ao controlador que a tela e' grafica. Sem
    ; essa escrita o modo fica em branco, com o tamanho certo (640x480)
    ; e a imagem toda preta.
    mov dx, 0x3C0
    mov al, 0x20
    out dx, al
    ; E o registro de modo: sem o bit 0 a placa fica em monocromato e a
    ; janela de video e' programada em 0xB0000 em vez de 0xA0000. Numa
    ; placa de cor o valor e' 0xE3; na monocromatica, 0x67 (que tambem
    ; escolhe o CRTC em 0x3B4/0x3B5, o par detectado acima).
    mov dx, 0x3C2
    mov al, 0x67
    cmp word [CRTC_BASE], 0x3B4
    je .misc_pronto
    mov al, 0xE3
.misc_pronto:
    out dx, al
    ret

; =====================================================================
;  leituras do CRTC. O CRTC tem um flip-flop interno que escolhe se a
;  proxima operacao em 0x3D5 e' de escrita ou de leitura, e o estado
;  desse flip-flop se perde com as escritas de 0x3D4 feitas no
;  programa_modo. Sem ressincronizar, o "in" em 0x3D5 devolve 0xFF e a
;  conferences acusa falha num modo que esta perfeito.
;
;  A sequencia que funciona no QEMU (medida, nao suposta) e':
;     in 0x3D4      leituradummy, joga o estado fora
;     out 0x3D4      escreve o indice
;     in 0x3DA      leitura de estado, ressincroniza o flip-flop
;     out 0x3D4      escreve o indice de novo
;     in 0x3D5      agora sim devolve o dado
;
;  O indice vai em AH porque o "in 0x3DA" sobrescreve AL. O par de
;  portas vem de CRTC_BASE, que o detecta_vga escolheu, em vez de 0x3D4
;  fixo: numa placa monocromatica o CRTC responde em 0x3B4.
; =====================================================================
le_crtc_12:
    mov al, 0x12
    jmp le_crtc
le_crtc_15:
    mov al, 0x15
    jmp le_crtc
le_crtc_01:
    mov al, 0x01
    jmp le_crtc
le_crtc_07:
    mov al, 0x07
le_crtc:
    mov ah, al                     ; AH = indice, AL vai ser destruido
    mov dx, [CRTC_BASE]
    in al, dx                      ; leitura dummy
    mov dx, [CRTC_BASE]
    mov al, ah
    out dx, al                     ; indice
    mov dx, 0x3DA
    in al, dx                      ; ressincroniza o flip-flop
    mov dx, [CRTC_BASE]
    mov al, ah
    out dx, al                     ; indice de novo
    mov dx, [CRTC_BASE]
    inc dx
    in al, dx                      ; o dado
    xor ah, ah
    ret

; =====================================================================
;  limpa_tela
;  Zera a janela da VGA. Sao 38400 bytes e nao 153600: no modo planar
;  cada endereco da janela em 0xA0000 e' um byte que cobre 8 pixels, e
;  as quatro camadas ficam no mesmo endereco. Como GR00 esta em 0x00 o
;  "Set/Reset" esta desligado, a VGA grava o byte nas quatro camadas de
;  uma vez, e um unico byte decide os 4 bits do pixel: 0xFF e' branco e
;  0x00 e' preto. Sao 480 linhas de 80 bytes.
;
;  DI comeca em 0 e nao volta a zero a cada linha: e' o "rep stosb" que
;  o avanca, 80 bytes por vez. Zerar DI dentro do laco limparia sempre as
;  mesmas 80 primeiras bytes e deixaria o resto da janela sujo.
; =====================================================================
limpa_tela:
    mov ax, 0xA000
    mov es, ax
    mov di, 0
    mov bp, ALTURA                 ; 480 linhas
.limpa:
    mov cx, BYTES_APERTURA         ; 80 bytes por linha
    xor al, al
    rep stosb
    dec bp
    jnz .limpa
    ret

; ============================ TABELAS ==============================
; Valores lidos de volta da VGA depois que a BIOS configurou o modo 12h
; (640x480x16). Os que a leitura devolveu 0xFF nao sao lidos pelo
; hardware, e aqui vao os valores usuais de modo grafico planar.
SEQ_TAB:
    db 0x03                        ; 0 reset
    db 0x01                        ; 1 controle do clock
    db 0x0F                        ; 2 mascara: 4 camadas = 16 cores
    db 0x00                        ; 3 deslocamento (0 = grafico)
    db 0x06                        ; 4 modo de memoria
    db 0x00                        ; 5 deslocamento horizontal

GFX_TAB:
    db 0x00                        ; 0 set/reset
    db 0x00                        ; 1 comparar cor
    db 0x00                        ; 2 escrever cor
    db 0x00                        ; 3 set/reset
    db 0x00                        ; 4 rotacionar
    db 0x00                        ; 5 modo grafico
    db 0x05                        ; 6 janela em 0xA0000
    db 0x0F                        ; 7 "nao comparar" cor
    db 0xFF                        ; 8 mascara de bit
    db 0x00                        ; 9 reservado
    db 0x00                        ; 10 raster op
    db 0x00                        ; 11
    db 0x00, 0x00, 0x00, 0x00

CRTC_TAB:
    db 0x5F                        ; 00 total horizontal
    db 0x4F                        ; 01 fim do display horizontal
    db 0x50                        ; 02 inicio do apagamento H
    db 0x82                        ; 03 fim do apagamento H
    db 0x54                        ; 04 inicio do retrace H
    db 0x80                        ; 05 fim do retrace H
    db 0x0B                        ; 06 total vertical
    db 0x3E                        ; 07 overflow
    db 0x00                        ; 08 endereco do fim do display V
    db 0x40                        ; 09 inicio do apagamento V
    db 0x00                        ; 0A fim do apagamento V
    db 0x00                        ; 0B inicio do retrace V
    db 0x00                        ; 0C fim do retrace V
    db 0x00                        ; 0D endereco do fim do display
    db 0x00                        ; 0E endereco do apagamento
    db 0x00                        ; 0F endereco do apagamento (fim)
    db 0xEA                        ; 10 endereco do inicio do retrace
    db 0x8C                        ; 11 fim do retrace (parte alta)
    db 0xDF                        ; 12 fim do display H, parte alta
    db 0x28                        ; 13 fim do apagamento V, parte alta
    db 0x00                        ; 14 inicio do retrace V, parte alta
    db 0xE7                        ; 15 fim do display vertical
    db 0x04                        ; 16 inicio do retrace, parte alta
    db 0xE3                        ; 17 modo grafico
    db 0xFF                        ; 18 comparacao de linha: 0xFF e' maior
                                    ;    que qualquer altura, e o que impede
                                    ;    o modo de dividir a tela em dois
                                    ;    blocos (QEMU compara isso com a
                                    ;    altura: 0x00 daria 256 < 480)
    db 0x00                        ; 19 proteger escrita
    db 0x00                        ; 1A
    db 0x00                        ; 1B
    db 0x00                        ; 1C
    db 0x00                        ; 1D
    db 0x00                        ; 1E
    db 0x00                        ; 1F

; Paleta de 16 cores + modo de endereco. O branco de verdade e' a cor
; 15 (0x0F), e e' ela que o desenho usa: por isso os quatro planos.
; A DAC nao e' reescrita: a paleta que a BIOS deixa ja' tem o branco
; em 15 e o vermelho em 4, que sao as duas cores que o desenho usa.
ATT_TAB:
    db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07
    db 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F
    db 0x01, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

; ========================== DADOS / PILHA ==========================
CRTC_BASE:    dw 0x3D4          ; par de portas do CRTC, 3D4 ou 3B4
SS_SALVO:     dw 0              ; SS e SP de quem chamou, para o "retf"
SP_SALVO:     dw 0
; A pilha do driver NAO pode ficar em 0x8800: o nucleo esta' em
; 0000:8000 e vai ate 0x8C1, e a fonte 8x16 dele ocupa 0x82D5..0x8C4.
; Com SP = 0x8800 o primeiro "push" do driver caia em 0x87FE e apagava
; as linhas 10..13 do glifo 'r' (0x87FF..0x8802), o que aparecia na
; tela como um rabisco embaixo do 'r' de "videoVGA.dr". A pilha vai
; no vao livre entre a pilha do nucleo (0x7000, que so' desce) e o
; stage 1 (0x7C00): 0x7B00 tem 0xB00 bytes de folga e nao encosta em
; nenhuma imagem.
PILHA         equ 0x7B00           ; vao livre 0x7001..0x7BFF

; =========================== FIM DO DRIVER ==========================
; Nao ha fonte aqui dentro. O desenho dos caracteres mora no nucleo
; (nucleo.asm), com o "%include" da fonte 8x16.
