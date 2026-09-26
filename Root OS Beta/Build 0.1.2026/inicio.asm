; =====================================================================
;  ROOT OS BETA - inicio.asm
;  Stage 1 do bootloader. 100% assembly, 16 bits, modo real.
;
;  Carregado pela BIOS em 0000:7C00 via El Torito (hard-disk emulation),
;  com DL = 0x80. O binario tambem e uma MBR valida (particao + 0x55AA),
;  portanto os mesmos bytes funcionam como CD, pendrive, disco ou
;  imagem de disco virtual. Nenhum LBA de ISO e compilado aqui dentro.
;
;  Pilha: a BIOS nos entrega com SS:SP = 0000:7C00 (ou similar), logo
;  empilhar para baixo desde 0x7C00 cresce para dentro do espaco livre
;  entre o MBR e a tabela de particoes. Nao ha problema.
; =====================================================================

BITS 16
ORG 0x7C00

; ============================== CONFIG ==============================
ATTR_BRANCO  EQU 0x0F       ; atributo: 0F = branco puro sobre preto
                            ;           07 = cinza claro (branco "classico")
COLUNAS      EQU 80
LINHAS       EQU 25
SEG_VIDEO    EQU 0xB800     ; 0xB800 * 16 = 0xB8000 = memoria de texto VGA
                            ; cabe em 16 bits como segmento:offset

; =============================== BOOT ===============================
inicio:
    ; Modo texto 80x25 colorido. A BIOS tambem limpa a tela, mas nao
    ; confiamos nisso: limpamos o buffer de video mais abaixo.
    mov ax, 0x0003
    int 0x10

    ; DS = 0 para que DS:SI seja sempre endereco linear. Assim o
    ; lodsb consegue ler a mensagem que vive dentro do proprio
    ; boot sector, sem precisar calcular segmento.
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; --- 1) tela preta: zera as 80*25 celulas do buffer de texto ---
    ; cada celula = 2 bytes (caractere, atributo). Zerar = espaco
    ; com fundo preto.
    mov ax, SEG_VIDEO
    mov es, ax
    xor di, di
    mov cx, COLUNAS * LINHAS
    xor ax, ax
    rep stosw

    ; --- 2) reposiciona no inicio da tela ---
    ; o rep stosw deixou DI em 4000, entao precisa voltar a zero
    xor di, di

    ; --- 3) escreve a mensagem em branco ---
    mov si, msg
    mov cx, msg_tam
.escreve:
    lodsb                     ; AL = caractere, SI++
    mov ah, ATTR_BRANCO       ; AL = caractere, AH = atributo
    mov [es:di], ax           ; grava caractere + atributo na celula
    add di, 2                 ; 2 bytes por celula
    loop .escreve

    ; --- 4) fim do milestone ---
    ; Para o processador em vez de deixar o fluxo cair no lixo a
    ; frente: sem isto a CPU executaria os zeros do MBR e reiniciaria
    ; a maquina, apagando a mensagem que acabamos de escrever.
    cli
.parado:
    hlt
    jmp .parado

; ============================== DADOS ===============================
msg:    db "Root OS Beta v0.1 Build 0.1.2026"
msg_tam equ $ - msg

; ======================= TABELA DE PARTICAO ========================
; O genisoimage com -hard-disk-boot RECUSA a imagem se ela nao comecar
; por uma MBR com uma unica particao. Esta entrada reserva o setor 1
; do "disco" (ou seja, logo apos a MBR) para o stage 2.
;
; Repare que o LBA abaixo e relativo a imagem de boot, nunca a ISO.
; E o mesmo numero em qualquer midia: CD, USB, HD, IMG.
    times 0x1BE - ($ - $$) db 0        ; codigo ate a tabela de particoes

    db 0x80                  ; 1) particao ativa
    db 0x00, 0x01, 0x01      ; 2) CHS do primeiro setor
    db 0x06                  ; 3) tipo: FAT16
    db 0x00, 0x01, 0x01      ; 4) CHS do ultimo setor
    dd 1                     ; 5) LBA inicial  (relativo a imagem)
    dd 1                     ; 6) total de setores

    times 510 - ($ - $$) db 0        ; sobe ate o final do setor
    dw 0xAA55                       ; assinatura MBR

; ====================== AREA DO STAGE 2 (setor 1) ===================
; Reservado. Vai ser o stage 2, que sera carregado a partir daqui.
    times 512 db 0
