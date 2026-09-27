; =====================================================================
;  ROOT OS BETA - interface.asm
;  A interface. 100% assembly, 16 bits, modo real, sem BIOS.
;
;  Este arquivo e' SEPARADO do driver de video. O driver de video
;  programa a placa e limpa a tela; este arquivo pinta a tela. Os dois
;  nao se conhecem: nenhum menciona o nome do outro, e o build confere
;  isso. A interface e' um modulo de interface, e nao um driver.
;
;  Como entra aqui: o stage 1 procura "interface.grain" no diretorio
;  root da ISO, carrega em 0000:A000 e deixa o endereço em 0000:0606
;  (offset) e 0000:0608 (segmento, sempre zero). O nucleo configura o
;  video, escreve as tres linhas, espera 10 segundos e salta para ca
;  com um "jmp dword [0000:0606]". Nao ha retorno: quem entra aqui e'
;  o dono da tela daqui para frente.
;
;  O que este arquivo faz:
;
;    1. confere a assinatura "GRN!" no comeco, e aborta sem BIOS se ela
;       faltar
;    2. pinta a tela inteira de branco, escrevendo direto na janela
;       da VGA
;    3. para com "hlt", sem relogar o timer
;
;  -------------------------------------------------------------------
;  POR QUE UM BYTE NA JANELA E' UM PING (OU SEJA, UM PIXEL)
;
;  A janela em 0xA0000 tem 256 KB, e o modo 12h e' planar: quatro
;  camadas de cor separadas. Um endereco dessa janela nao e' um pixel,
;  e' o byte que descreve 8 pixels seguidos da MESMA linha em UMA das
;  quatro camadas. Sao 80 bytes por linha de 640 pixels, 480 linhas,
;  38400 bytes no total.
;
;  Por que escrever 0xFF pinta branco e nao estoura a memoria: o
;  sequenciador de atributos do driver foi programmed com GR00 = 0x00,
;  e um "Set/Reset" em zero deixa o dado que chega da memoria passar
;  direto para as quatro camadas. Entao 0xFF nas quatro camadas de uma
;  vez e' branco puro, e 0x00 e' preto puro. Uma cor nao e' escolhida
;  aqui: a cor e' o conteudo do byte, e o branco e' o byte todo em 1.
;
;  -------------------------------------------------------------------
;  POR QUE UM UNICO "rep stosb" E NAO UM LAÇO POR LINHA
;
;  "rep stosb" caminha em DI: ele aumenta DI a cada byte e para
;  quando CX chega a zero. Zerar DI dentro de um laco de linhas
;  reescreveria sempre as mesmas primeiras 80 bytes e o resto da tela
;  ficaria com o que o driver deixou, que e' preto. Por isso o
;  contador CX e' o total todo, 38400, e o laco interno do "rep" e'
;  quem respeita a geometria da tela: a sequencia de bytes e' a mesma
;  linha a linha, sem nenhum salto no endereco.
; =====================================================================

BITS 16
ORG 0xA000

; ============================ CABECALHO ============================
; Quatro bytes de assinatura no comeco do arquivo. O nucleo confere
; antes de saltar, e salta para DEPOIS deles: e' o mesmo combinado dos
; outros dois arquivos, com a diferenca de que aqui nao ha offset de
; entrada no cabecalho, porque este modulo comeca a executar no
; primeiro byte depois da assinatura.
    db 'G','R','N','!'

; ============================== ENTRADA =============================
entrada:
    cli                         ; para o timer no meio da pintura: uma
    cld                         ; interrupcao aqui mudaria CX e o
    xor ax, ax                  ; branco sairia pela metade
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, PILHA               ; pilha propria, abaixo da interface

    ; ---- a tela toda de branco, do primeiro byte ao ultimo ----
    mov ax, SEG_VGA
    mov es, ax
    mov di, 0                   ; primeiro byte da janela
    mov cx, BYTES_TELA          ; 38400: 80 bytes por linha, 480 linhas
    mov al, BRANCO              ; 0xFF: branco nas quatro camadas
    rep stosb

    ; Fim da interface. "cli" e' de proposito: a interface nao
    ; religa o timer, e por isso o processador fica parado de verdade
    ; no "hlt", gastando zero CPU.
    cli
.parado:
    hlt
    jmp .parado

; ============================== DADOS ==============================
SEG_VGA      equ 0xA000         ; a janela grafica do CRTC
BYTES_LINHA  equ 80             ; 640 / 8 pixels
ALTURA       equ 480
BYTES_TELA   equ BYTES_LINHA*ALTURA
BRANCO       equ 0xFF           ; todas as camadas: branco puro
PILHA        equ 0x6F00         ; a interface esta em 0xA000, e o
                                ; nucleo ja terminou quando ela entra
