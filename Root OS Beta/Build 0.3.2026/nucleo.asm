; =====================================================================
;  ROOT OS BETA - nucleo.asm
;  Nucleo da build 0.3.2026. 100% assembly, 16 bits, modo real.
;
;  O stage 1 carregou este arquivo em 0000:8000 e o videoVGA.dr em
;  0000:9000, e deixou o endereco do driver em 0000:0600. Aqui:
;
;    1. confere a assinatura "VGA!" do driver
;    2. escreve "nucleo-0.3.2026" na linha 1 da memoria de texto
;    3. chama a entrada MODO do driver, que configura 640x480x16
;       planar em 0000:A0000 e confere relendo o CRTC
;    4. escreve "videoVGA.dr configurado com sucesso" na linha 2
;    5. chama a entrada DESENHA, que leva as tres linhas da memoria de
;       texto para o framebuffer com a fonte 8x16 do driver
;    6. para
;
;  O passo 5 existe porque a linha 2 e' escrita DEPOIS da troca de
;  modo: em modo grafico a memoria em 0xB8000 nao e' mais o que a tela
;  mostra. O driver le as tres linhas de la e as redesenha em 0xA0000,
;  entao o que fica na tela e' o texto novo, e nao o antigo.
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

; --- offsets das entradas dentro do cabecalho "VGA!" do driver ---
H_MODO        equ 6
H_DESENHA     equ 8

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

; Copia das tres linhas em RAM comum, que o videoVGA.dr le no DESENHA.
; Precisa existir porque, com a janela grafica de 256 KB aberta sobre
; 0xA0000, o endereco 0xB8000 cai dentro da janela: ele deixa de ser
; RAM e passa a ser o framebuffer no deslocamento 0x18000. Medido: depois
; do MODO, 0xB8000 devolvia 0xFF. 480 bytes a partir de TEXTO, longe da
; janela. O mesmo endereco e' o TEXTO do videoVGA.asm.
TEXTO        equ 0x5000

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

    ; ---- linha 1: o nucleo se anuncia ----
    mov si, msg_nucleo
    mov di, OFF_L1
    call escreve_texto

    ; ---- leva as tres linhas para a sombra, ainda no modo texto ----
    call copia_sombra

    ; ---- o driver configura o video e confere o CRTC ----
    call chama_modo
    jc .falhou

    ; ---- linha 2: deu tudo certo ----
    mov si, msg_sucesso
    mov di, OFF_L2
    call escreve_texto

; =====================================================================
;  Ultimo passo: leva as tres linhas para o framebuffer, com a fonte do
;  driver. A tela so fica correta depois daqui, porque em modo grafico
;  o que esta em 0xB8000 nao aparece na tela.
; =====================================================================
    call chama_desenha
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
;  chama_modo / chama_desenha
;  Montam o par CS:IP na pilha e saltam para a entrada do driver, que
;  devolve com "retf". Devolvem CF=1 se o driver nao deixou I_ESTADO
;  igual a EST_OK.
;
;  Os dois NAO mexem em SS:SP. O driver salva o par na entrada e o
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

chama_desenha:
    mov bx, [DRV_BASE]
    mov ax, [bx+H_DESENHA]
    add ax, bx
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
;  Escreve em dois lugares de proposito: na memoria de texto, que e' o
;  que aparece enquanto a tela for modo texto, e na sombra em 0000:TEXTO,
;  que e' o que o driver consegue ler depois que o MODO abriu a janela
;  grafica sobre 0xA0000. So' a sombra bastaria para a tela final, mas a
;  copia em 0xB8000 e' o que faz a linha 2 aparecer sozinha no caminho
;  em que o driver recusa o modo e o boot para ainda no modo texto.
; =====================================================================
escreve_texto:
    push ax
    push cx
    push di
    push si
    mov bx, di                    ; deslocamento da linha, nas duas copias
    mov dx, si                    ; a string

    ; ---- a sombra: e' daqui que o DESENHA le depois do MODO ----
    xor ax, ax
    mov es, ax
    mov di, bx
    add di, TEXTO
    mov si, dx
    call linha_texto

    ; ---- a memoria de texto, enquanto ela ainda for a tela ----
    ; SI volta ao comeco da string nos dois destinos: "linha_texto" le
    ; com "lodsb", que avanca SI. Sem isso o segundo destino receberia o
    ; fim da string e ficaria so com os espacos da limpeza.
    mov ax, SEG_VIDEO
    mov es, ax
    mov di, bx
    mov si, dx
    call linha_texto

    pop si
    pop di
    pop cx
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
;  copia_sombra
;  Copia as tres linhas de 0xB8000 para 0000:TEXTO. Roda depois que a
;  linha 1 foi escrita e antes do MODO, ou seja, enquanto 0xB8000 ainda
;  e' a memoria de texto de verdade. E' o que leva a linha 0, que veio
;  do stage 1, para a sombra: na hora em que a linha 2 e' escrita o
;  MODO ja trocou o modo, e 0xB8000 ja nao tem mais texto nenhum.
; =====================================================================
copia_sombra:
    push ax
    push cx
    push si
    push di
    push ds
    push es
    cld
    mov ax, SEG_VIDEO
    mov ds, ax                     ; fonte: 0xB800:0 = 0xB8000
    xor ax, ax
    mov es, ax                     ; destino: 0:0x5000
    xor si, si
    mov di, TEXTO
    mov cx, COLUNAS*2*TOTAL_TEXTOS ; 480 bytes
    rep movsb
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    ret

; ============================== DADOS ==============================
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
