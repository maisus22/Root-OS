; =====================================================================
;  ROOT OS BETA - nucleo.asm
;  Nucleo da build 0.3.2026. 100% assembly, 16 bits, modo real.
;
;  O stage 1 carregou este arquivo em 0000:8000 e o videoVGA.dr em
;  0000:9000, e deixou o endereco do driver em 0000:0600. Aqui:
;
;    1. confere a assinatura "VGA!" do driver
;    2. escreve as linhas 1 e 2 na memoria de texto: "nucleo-0.3.2026"
;       e "videoVGA.dr configurado com sucesso"
;    3. chama a entrada MODO do driver, que configura 640x480x16
;       planar em 0000:A0000, limpa a tela e confere relendo o CRTC
;    4. escreve a tela chamando o TEXTO do nucleo uma vez por linha, com
;       a string e a posicao que ele escolheu, usando a fonte do nucleo
;    5. para
;
;  QUEM ESCREVE NA TELA: o nucleo. O driver e' a camada de video, e nao
;  tem nenhuma mensagem, nem numero de linhas, nem posicao fixa: ele
;  programa a placa, limpa a tela e coloca um glifo onde for pedido. As
;  linhas 1 e 2 vao para a memoria de texto ANTES do MODO de proposito,
;  para o usuario ler tudo desde o começo e para o caminho de erro
;  funcionar sem ter que trocar de modo.
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
; dois. O driver usa a dele em 0x8800, entao as duas pilhas nao se
; atropelam mesmo com o SS:SP trocado no meio do caminho.
KSTACK        equ 0x7000

; ============================== TELA ==============================
ATTR_BRANCO  equ 0x0F
PREENCHER    equ ' '                ; o resto da linha fica em branco, sem til
ATRI_PREENCHER equ (ATTR_BRANCO << 8) | PREENCHER
SEG_VIDEO    equ 0xB800
COLUNAS      equ 80
OFF_L0       equ COLUNAS*2*0         ; 0
OFF_L1       equ COLUNAS*2*1         ; 160
OFF_L2       equ COLUNAS*2*2         ; 320
TOTAL_TEXTOS equ 3                   ; linha 0 (stage 1), 1 e 2 (nucleo)

; Coluna e linha da grade de 80x30, ja no word que o TEXTO le:
; o byte baixo e' a coluna e o alto e' a linha. As tres linhas do boot
; ficam na coluna 0, nas linhas 0, 1 e 2.
CEL_0         equ (0 << 8) | 0
CEL_1         equ (1 << 8) | 0
CEL_2         equ (2 << 8) | 0

; --- geometria do desenho, a mesma que o driver programou -----------
; O driver configurou a tela; aqui o nucleo escreve nela. Os numeros
; precisam bater com o que o driver program's, e por isso que sao os
; mesmos: 80 bytes por linha da janela e 16 pixels de altura de glifo.
LARGURA       equ 640            ; pixels por linha
ALTURA        equ 480            ; pixels por coluna
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

    ; A fonte e' do nucleo, entao quem anuncia o tamanho dela na struct
    ; de info e' o nucleo.
    mov word [INFO+I_TAM_FONTE], TAM_CELULA
    mov word [INFO+I_TAM_TAB], FONTE_QUANT

    ; ---- linha 1: o nucleo se anuncia ----
    mov si, msg_nucleo
    mov di, OFF_L1
    call escreve_texto

    ; ---- linha 2: o que o nucleo espera que aconteca ----
    ; Vai para a memoria de texto ANTES do MODO, e nao depois. A tela
    ; ainda esta em modo texto aqui, entao o usuario le as tres linhas
    ; desde o começo. E se o driver recusar o modo, o texto ainda esta
    ; na tela e o caminho de erro so' troca a linha 2 pelo aviso.
    mov si, msg_sucesso
    mov di, OFF_L2
    call escreve_texto

    ; ---- o driver configura o video e confere o CRTC ----
    call chama_modo
    jc .falhou

; =====================================================================
;  O video ja esta em modo grafico e a tela esta limpa. Agora quem escreve
;  na tela e' o nucleo: ele chama o TEXTO uma vez por linha, e a ordem
;  das chamadas e' a ordem das linhas. O TEXTO e' do nucleo, com a fonte
;  do nucleo: o driver so' programou a placa e limpou a tela.
; =====================================================================
    ; linha 0: a mensagem de boot, a mesma string que o stage 1 deixou
    ; na memoria de texto. O ponteiro dela veio no handoff, para o
    ; nucleo nao precisar ter uma segunda copia do texto do boot.
    mov si, [HANDOFF_MSG]
    xor dx, dx
    call TEXTO

    ; linha 1: o nucleo
    mov si, msg_nucleo
    mov dx, CEL_1
    call TEXTO

    ; linha 2: a confirmacao
    mov si, msg_sucesso
    mov dx, CEL_2
    call TEXTO

    cli
    hlt
    jmp $

; ---- o driver recusou o modo: o texto ainda esta no modo texto, entao
; ---- o aviso na linha 2 aparece sozinho. Nao ha framebuffer para
; ---- blitar, e por isso o caminho termina aqui.
.falhou:
    mov ax, [INFO+I_ESTADO]
    cmp ax, EST_SEM_VGA
    je .sem_placa
    mov si, msg_falha
    jmp .escreve_falha
.sem_placa:
    mov si, msg_sem_vga
.escreve_falha:
    mov di, OFF_L2
    call escreve_texto
    cli
    hlt
    jmp $

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
;  0000:0600. Escreve o aviso na linha 1 e para: sem driver nao ha
;  framebuffer 640x480, entao nao ha para onde levar o texto.
; =====================================================================
sem_driver:
    mov si, msg_sem_driver
    mov di, OFF_L1
    call escreve_texto
    cli
    hlt
    jmp $

; =====================================================================
;  escreve_texto
;  SI = string ASCII, DI = deslocamento da linha dentro de 0xB8000.
;  Escreve caractere e atributo branco, e enche o resto da linha com
;  espacos, para o texto nunca ficar com o resto da tela antiga.
;
;  So' escreve na memoria de texto. Quem escreve na tela grafica e' o
;  TEXTO do nucleo, chamado com a mesma string: quem decide o que
;  aparece e onde, e quem desenha os pixels, e' o nucleo.
; =====================================================================
escreve_texto:
    push ax
    push di
    mov ax, SEG_VIDEO
    mov es, ax                     ; destino unico: a memoria de texto
    call linha_texto
    pop di
    pop ax
    ret

; =====================================================================
;  linha_texto
;  SI = string ASCII, ES:DI = destino, limpa COLUNAS e escreve o texto.
;  Sem o 0 no fim, para a linha nao vazar na linha seguinte.
; =====================================================================
linha_texto:
    push ax
    push si
    push di
    ; O resto da linha vai em branco, e o branco tem de ser o espaco
    ; 0x20. Encher com 0x00 parecia mais limpo, mas no driver um
    ; caractere fora da faixa 32..126 cai no ultimo glifo da fonte, que
    ; e' o til, e a linha aparecia cheia de '~' ate a coluna 80. Com
    ; 0x20 o glifo e' o do espaco, a linha acaba onde a string acaba, e
    ; o mesmo preenchimento serve no modo texto e na tela final.
    mov cx, COLUNAS
    mov ax, ATRI_PREENCHER
    rep stosw
    pop di
    pop si
    mov cx, COLUNAS
.l:
    lodsb
    test al, al
    jz .fim
    mov ah, ATTR_BRANCO
    mov [es:di], ax
    add di, 2
    dec cx
    jnz .l
.fim:
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
    mov ax, SEG_VIDEO              ; quem vem depois e' o MODO, que e'
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
DRV_BASE:   dw 0                    ; copia estavel da base do driver
msg_nucleo:     db "nucleo-0.3.2026", 0
msg_sucesso:    db "videoVGA.dr configurado com sucesso", 0
msg_falha:      db "videoVGA.dr falhou ao configurar o video", 0
msg_sem_vga:    db "videoVGA.dr nao achou video nas portas do CRTC", 0
msg_sem_driver: db "videoVGA.dr nao foi encontrado", 0

; ============================== FONTE ==============================
; A fonte e' do nucleo: o texto e' conteudo do sistema, e quem escreve
; na tela e' o nucleo. O driver so' programa a placa e limpa a tela,
; entao nao tem fonte nenhuma dentro.
;
; O rotulo FONT e' o que o TEXTO usa: glifo = FONT + (caractere-32)*16.
; O "%include" cola aqui os 95 glifos de 16 bytes, 32 ate 126.
FONT:
%include "fonte8x16.inc"
