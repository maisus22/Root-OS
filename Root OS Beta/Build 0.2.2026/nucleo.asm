; =====================================================================
;  ROOT OS BETA - nucleo.asm
;  Nucleo, arquivo SEPARADO do inicio.asm. Vai para a ISO como
;  nucleo-0.2.2026 e e encontrado pelo inicio.asm em runtime.
;
;  NUNCA e concatenado com o inicio.asm. Os dois binarios andam
;  soltos, e o inicio.asm acha este arquivo pelo nome dentro do
;  diretorio ISO9660 e o ponto de entrada pela assinatura "ROOT".
;
;  Este arquivo e montado com ORG 0x8000, que e o endereco onde o
;  inicio.asm carrega o nucleo. O inicio.asm pula para 0:0x8000+entrada.
; =====================================================================

BITS 16
ORG 0x8000

; ============================== CONFIG ==============================
ATTR_BRANCO  equ 0x0F
SEG_VIDEO    equ 0xB800
COLUNAS      equ 80
VERSAO       equ 0x0206          ; 0.2.2026

; =====================================================================
;  CABECALHO COM ASSINATURA
;  O inicio.asm varre o binario carregado procurando 'R','O','O','T'.
;  Achando, le o campo H_ENTRADA para saber onde comeca o codigo.
;  Se a assinatura nao aparecer, o inicio.asm aborta em vez de pular
;  para o meio do arquivo.
; =====================================================================
    db  'R','O','O','T'         ; 0: assinatura magica
    dw  VERSAO                  ; 4: versao do nucleo
    dw  entrada - $$            ; 6: offset da entrada a partir do cabecalho
    dw  0, 0                    ; 8: reservado para uso futuro (8 bytes)

entrada:
    ; Nao se assume nada do que o inicio.asm deixou nos registradores,
    ; exceto CS:IP, que e o contrato do cabecalho. O DS e' zerado aqui
    ; porque o lodsb abaixo le em DS:SI, e DS=0 e' o que o stage 1
    ; herdou, mas depender disso seria fragil.
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7000              ; pilha propria, abaixo do boot sector e do
                                ; codigo em 0x8000, e acima da pilha do
                                ; stage 1 (que fica em 0x6000:0x0FFF)

    ; O inicio.asm NAO limpou a tela e o cursor nao importa: a gente
    ; escreve direto na memoria de video, logo abaixo da mensagem de
    ; boot do inicio.asm (que esta na linha 0).
    mov ax, SEG_VIDEO
    mov es, ax
    mov di, COLUNAS * 2         ; celula 80 = coluna 0 da linha 1
    mov si, msg
    mov cx, msg_tam
.escreve:
    lodsb
    mov ah, ATTR_BRANCO
    mov [es:di], ax
    add di, 2
    loop .escreve

    ; Fim do milestone. O inicio.asm tambem faz o mesmo: sem parar o
    ; processador, a CPU cairia no lixo e reiniciaria a maquina.
    cli
.parado:
    hlt
    jmp .parado

msg:    db "nucleo-0.2.2026"
msg_tam equ $ - msg
