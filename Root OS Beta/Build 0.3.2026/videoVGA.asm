; =====================================================================
;  ROOT OS BETA - videoVGA.asm
;  Driver de video. 100% assembly, 16 bits, modo real. NAO usa a BIOS
;  para nada: nem int 10h, nem int 12h, nem tabela de video do BIOS.
;
;  O stage 1 carrega este arquivo em 0000:9000 e escreve o endereco em
;  0000:0600. O nucleo le esse endereco e chama as duas entradas
;  abaixo, com um "retf" de volta, sem BIOS no meio do caminho.
;
;    MODO     detecta a placa lendo o CRTC, programa 640x480x16 planar
;             em 0000:A0000 e confere relendo o CRTC
;    DESENHA  limpa o framebuffer e redesenha as 3 linhas de texto
;             que o nucleo guardou na sombra em 0000:TEXTO
;
;  Por que o texto vem de uma sombra e nao de 0xB8000: em modo grafico
;  planar a janela da VGA esta mapeada em 0xA0000 e cobre 256 KB, ou
;  seja, ate 0xEFFFF. 0xB8000 esta dentro dessa janela, entao deixar de
;  fora da tela nao a torna RAM: ela vira o framebuffer no deslocamento
;  0x18000. Medido: depois do MODO, 0xB8000 devolvia 0xFF, e a
;  memoria de texto que estava ali sumiu. Como o nucleo escreve a
;  segunda e a terceira linhas so depois que o MODO retorna, nem da
;  para ler 0xB8000 antes de limpar. A saida e' o nucleo manter uma
;  cópia das tres linhas em RAM comum (TEXTO), fora da janela, que e'
;  o que o DESENHA consome.
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
; os dois pontos de entrada sao lidos pelo nucleo, que nao assume
; posicao fixa de codigo dentro do driver.
;
; Os dois offsets sao relativos ao INICIO do driver, e nao ao ORG. Um
; rotulo NASM carrega o endereco com o ORG embutido (MODO vale 0x900C,
; nao 0x000C), entao o que vai no cabecalho e o rotulo menos "$$", o
; comeco desta secao. Sem essa subtracao o nucleo leria 0x900C e
; saltaria para fora do driver.
    db 'V','G','A','!'        ; assinatura
    dw VERSAO                 ; versao do driver
    dw MODO - $$              ; entrada 1: configurar e conferir
    dw DESENHA - $$           ; entrada 2: blitar o texto na tela
    dw 0                      ; reservado

VERSAO        equ 0x0303      ; 0.3.2026

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
TAM_CELULA    equ 16          ; altura do glifo, em pixels
FONTE_BASE    equ 32          ; primeiro caractere guardado na tabela
FONTE_QUANT   equ 95          ; caracteres 32..126

; Onde as tres linhas comecam no framebuffer. Oito pixels de margem
; no topo, e 16 pixels de passo entre linhas, do mesmo jeito que o
; texto de 80x25 ficaria na memoria de video.
;
; MARGEM (a esquerda) e' 0 de proposito: 80 celulas de 8 pixels dao
; exatamente os 640 pixels de uma linha, entao a ultima celula escreve
; no byte 79 e nao invade a linha seguinte. Com margem de 8 a celula 80
; acabava no offset 80, ou seja, no primeiro byte da linha de baixo, e
; aparecia um pedaco de letra na coluna 0 das linhas seguintes.
MARGEM        equ 0
L0_Y          equ 8
L1_Y          equ L0_Y + TAM_CELULA
L2_Y          equ L0_Y + TAM_CELULA*2
TOTAL_LINHAS  equ 3           ; boot, nucleo, e a confirmacao

; Onde o nucleo mantem a copia das tres linhas de texto: 80 colunas de
; 2 bytes, uma linha por vez, entao 480 bytes a partir de TEXTO. Fica
; em RAM comum, longe de 0xA0000..0xEFFFF, para nao cair dentro da
; janela que a VGA abre quando o MODO entra em modo grafico. O nucleo
; preenche essa area antes de chamar o MODO e a cada linha nova, e e'
; daqui que o DESENHA le.
TEXTO         equ 0x5000

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
    mov sp, PILHA                   ; pilha do driver, abaixo dos 0x9000

    ; limpa a struct de info por inteiro, para nao sobrar lixo de
    ; uma tentativa anterior caso o driver seja chamado duas vezes
    mov cx, I_TOTAL/2
    mov di, INFO
    rep stosw
    mov word [INFO+I_ESTADO], EST_PENDENTE
    mov word [INFO+I_LARGURA], LARGURA
    mov word [INFO+I_ALTURA], ALTURA
    mov word [INFO+I_TAM_FONTE], TAM_CELULA
    mov word [INFO+I_TAM_TAB], FONTE_QUANT

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
;  ENTRADA 2 - DESENHA
;  Limpa o framebuffer e copia as 3 linhas de 0000:B8000 para
;  0000:A0000 usando a fonte 8x16 que esta no fim deste arquivo.
;
;  Rasterizacao de um pixel: o byte e' (y*80 + x/8) e o bit e'
;  7 - (x%8). Um byte so por endereco, e nao quatro: no modo planar cada
;  endereco da janela em 0xA0000 e' um byte que cobre 8 pixels, e como
;  GR00 esta em 0x00 o "Set/Reset" fica desligado, de modo que a VGA
;  grava esse byte nas quatro camadas de uma vez.
; =====================================================================
DESENHA:
    mov [SS_SALVO], ss              ; mesma razao do MODO: o "retf" tem de
    mov [SP_SALVO], sp              ; encontrar o par CS:IP na pilha do
    cli                            ; nucleo, e nao na pilha do driver
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, PILHA

    ; ---- limpa a tela inteira ----
    ; Sao 38400 bytes e nao 153600. No modo 12h a janela em 0xA0000 e'
    ; planar: cada endereco da janela e' um byte que cobre 8 pixels, e as
    ; quatro camadas ficam no mesmo endereco. Como GR00 esta em 0x00, o
    ; "Set/Reset" esta desligado e a VGA grava o byte nas quatro camadas
    ; de uma vez, entao um unico byte por endereco ja decide os 2 bits do
    ; pixel: 0xFF e' branco e 0x00 e' preto. Sao 480 linhas de 80 bytes.
    ;
    ; Duas contas que antes estavam erradas: 153600/256 = 600 e' o numero
    ; de blocos de 256 bytes, e num "rep stosb" limpava so 600 bytes; e
    ; 153600/2 = 76800 nao cabe em CX, o montador truncava para 0x2C00 e
    ; limpava 22528 bytes. Alem disso, a janela da VGA mapeada em
    ; 0xA0000 tem 64 KB: escrever nos offsets +80, +160 e +240 de cada
    ; linha passaria de 0xAFFFF e sairia da janela.
    mov ax, 0xA000
    mov es, ax
    ; DI comeca em 0 e nao volta a zero a cada linha: e' o "rep stosb"
    ; que o avanca, 80 bytes por vez. Zerar DI dentro do laco limparia
    ; sempre as mesmas 80 primeiras bytes e deixaria o resto da janela
    ; com o que a BIOS tinha deixado. No fim DI vale 38400 - 1, que
    ; cabe em 16 bits.
    mov di, 0
    mov bp, ALTURA                 ; 480 linhas; BP nao e' usado em mais lugar
.limpa:
    mov cx, BYTES_APERTURA         ; 80 bytes por linha
    xor al, al
    rep stosb
    dec bp
    jnz .limpa

    ; ---- uma linha por vez ----
    mov bx, TOTAL_LINHAS
    mov word [LINHA], 0
.linha:
    dec bx
    ; origem: 0000:TEXTO + linha*160, atributo em cada byte impar.
    ; 160 = 128 + 32, e o "shl" so' repete 2, entao sao dois shifts e
    ; uma soma. BX esta com a contagem do laco e nao pode ser usado aqui.
    mov al, [LINHA]
    mov ah, 0
    mov cx, ax                    ; cx = numero da linha
    shl ax, 5                     ; linha * 32
    shl ax, 2                     ; linha * 128
    mov dx, ax
    mov ax, cx
    shl ax, 5                     ; linha * 32
    add ax, dx                    ; linha * 160
    add ax, TEXTO                 ; origem do texto, 2 bytes por celula
    mov [ORIGEM], ax
    ; destino: x = MARGEM, y = L0_Y + linha*16
    mov al, [LINHA]
    mov ah, 0
    shl ax, 4
    add ax, L0_Y                    ; py = MARGEM + linha*16
    mov word [PY], ax
    mov word [PX], MARGEM
    call desenha_linha
    inc word [LINHA]
    cmp word [LINHA], TOTAL_LINHAS
    jb .linha
    sti
    jmp sai

; =====================================================================
;  desenha_linha
;  Percorre as 80 colunas do texto da linha apontada por ORIGEM, e para
;  cada caractere escreve as 16 linhas do glifo no framebuffer.
;  PX e PY sao a posicao do proximo caractere, em pixels.
; =====================================================================
desenha_linha:
    mov cx, CPP
.desenha:
    ; ---- escolhe o glifo ----
    mov si, [ORIGEM]
    mov al, [si]                   ; caractere (o atributo vem depois)
    sub al, FONTE_BASE
    cmp al, FONTE_QUANT
    jb .glifo_ok
    mov al, FONTE_QUANT-1          ; fora da faixa vira o ultimo glifo
.glifo_ok:
    ; glifo = FONT + al*16
    mov ah, 0
    shl ax, 4
    add ax, FONT
    mov bx, ax                     ; BX aponta para o glifo

    mov ax, [PY]
    mov [SY], ax
    mov dx, TAM_CELULA             ; 16 linhas do glifo
.linha_glifo:
    mov al, [bx]
    inc bx
    call px_byte
    mov ax, [SY]
    inc ax
    mov [SY], ax
    dec dx
    jnz .linha_glifo

    mov ax, [PX]
    add ax, 8                      ; 8 pixels para a proxima celula
    mov [PX], ax
    mov si, [ORIGEM]
    add si, 2                      ; pula o atributo: so o caracter conta
    mov [ORIGEM], si
    loop .desenha
    ret

; =====================================================================
;  px_byte
;  AL = mascara dos 8 pixels de uma linha do glifo (bit 7 = pixel mais a
;  esquerda). Grava UM byte, o da coluna, em y*80 + x/8.
;
;  Por que um byte so, e nao quatro: no modo 12h cada endereco da janela
;  da VGA e' um byte de 8 pixels, e as quatro camadas sao gravadas juntas
;  porque GR00 = 0x00 deixa o "Set/Reset" desligado. A conta e' y*80, e
;  nao y*320: 320 bytes por linha e' o layout linear do framebuffer, que
;  so existe quando a BIOS monta uma "linear frame buffer" no CRTC. Com
;  start_addr = 0 e line_offset = 80, o endereco que o CRTC le para a
;  linha y e' y*80, e e' esse byte que a janela expoe. Dar 0xFF e' branco
;  e 0x00 e' preto, entao nao ha cor a escolher.
;
;  O endereco vai em SI, e nao em DX, porque em modo de 16 bits so
;  BX, BP, SI e DI servem de endereco: um "[es:dx]" nao assembla.
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
    mov [es:si], al                ; a mascara da propria linha do glifo:
                                    ; o bit 7 e' o pixel da esquerda, e e'
                                    ; ela que decide o desenho. Escrever
                                    ; 0xFF aqui pintava um bloco inteiro
                                    ; em vez do letra.
.fim:
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
ATT_TAB:
    db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07
    db 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F
    db 0x01, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

; ========================== DADOS / PILHA ==========================
CRTC_BASE:    dw 0x3D4          ; par de portas do CRTC, 3D4 ou 3B4
SS_SALVO:     dw 0              ; SS e SP de quem chamou, para o "retf"
SP_SALVO:     dw 0
LINHA:        dw 0
ORIGEM:       dw 0              ; TEXTO + linha*160
; Mascara do bit de cada coluna, da 7 (bit mais alto) ate a 0. Existe
; porque "shl cl, bl" nao existe: no 8086 o contador de um shift e' so
; CL ou um imediato, nunca um outro registrador.
MASCARA:      db 0x80,0x40,0x20,0x10,0x08,0x04,0x02,0x01
PX:           dw 0
PY:           dw 0
SY:           dw 0
PILHA         equ 0x8800           ; abaixo dos 0x9000, longe do codigo

; ============================== FONTE ==============================
; Os glifos vem do fonte8x16.inc, gerado a partir do vgabios.bin do
; SeaBIOS. 95 glifos, do espaco (0x20) ate o til (0x7E), 16 bytes cada.
; O rotulo FONT e' o que o desenho usa: glifo = FONT + (char-32)*16.
FONT:
%include "fonte8x16.inc"
