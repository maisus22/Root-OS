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
;    3. repinta a bolinha e espera o proximo movimento do ponteiro, para
;       sempre
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
;  sequenciador de atributos do driver foi programado com GR00 = 0x00,
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
    ; A propria interface declara a mascara de camadas que o repaint
    ; usa. Sem isto ela herda a ultima que o nucleo programou: se a
    ; bolinha passou por uma passada de uma camada so, o "rep stosb"
    ; escreveria 0xFF so' naquela camada e a tela viraria vermelha.
    mov dx, 0x3C4
    mov al, 2                      ; registrador 2 = mascara de camadas
    out dx, al
    inc dx                         ; 0x3C5: agora o dado
    mov al, 0x0F                   ; as quatro camadas
    out dx, al
    mov ax, SEG_VGA
    mov es, ax
    mov di, 0                   ; primeiro byte da janela
    mov cx, BYTES_TELA          ; 38400: 80 bytes por linha, 480 linhas
    mov al, BRANCO              ; 0xFF: branco nas quatro camadas
    rep stosb

    ; ---- tem bolinha para mostrar? ----
    ; O ponteiro em BOLA_PTR e' zero enquanto o nucleo nao passou o
    ; driver do ponteiro para ca, e e' o que impede a tela de
    ; aparecer quando o ponteiro nao veio: sem as duas rotinas nao ha
    ; o que pintar, e o certo e' ficar parado de branco.
    mov bx, [BOLA_PTR]
    test bx, bx
    jz .fim
    mov ax, [BOLA_PTR+2]
    test ax, ax
    jnz .fim                 ; segmento diferente de zero: nao e' o
                             ; mesmo address space, e chamar seria
                             ; pular para o lugar nenhum
    mov bx, [DORME_PTR]
    test bx, bx
    jz .fim                 ; a rotina que espera o movimento tem de
                             ; vir junto com a que pinta
    mov ax, [DORME_PTR+2]
    test ax, ax
    jnz .fim

; ---- o laco: pinta, e dorme ate o ponteiro se mexer ----
; A bolinha e' pintada pelo nucleo, nao aqui: e' ele que sabe o
; tamanho, a cor e a geometria da caixa. A interface so' diz QUAL e' o
; fundo (em AL) e chama. O AL e' o fundo que a BOLA usa para
; repintar a caixa velha antes de desenhar a bolinha nova, e por isso
; e' branco e nao o preto do boot: a tela daqui para frente e' branca.
; O segmento do ponteiro e' zero porque as duas rotinas moram no
; nucleo, carregado no inicio da memoria baixa.
.laco:
    mov al, BRANCO
    call dword [BOLA_PTR]     ; "call dword": as duas rotinas terminam
.bola_volta:                  ; em "retf", e o par CS:IP volta inteiro
    call dword [DORME_PTR]     ; so' a IRQ do ponteiro acorda o "hlt"
.dorme_volta:
    jmp .laco

.fim:
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
BOLA_PTR     equ 0x063C         ; dword: ponteiro far da rotina que
                                ; pinta a bolinha, publicado pelo
                                ; nucleo no momento da passagem
DORME_PTR    equ 0x0640         ; dword: ponteiro far da rotina que
                                ; espera o proximo movimento
