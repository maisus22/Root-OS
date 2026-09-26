; =====================================================================
;  ROOT OS BETA - inicio.asm
;  Stage 1. 100% assembly, 16 bits, modo real, sem nenhum registrador
;  de 32 bits e sem nenhuma instrucao com prefixo de operand size.
;
;  Recebido da BIOS em 0000:7C00 pelo El Torito (hard-disk emulation),
;  com DL = 0x80. Verifica a assinatura 0x55AA, monta a tela, imprime a
;  mensagem de boot e entao procura, em runtime, o arquivo do nucleo.
;  Nenhum LBA de ISO e nenhum numero de drive e fixo:
;
;    1. varre DL de 0x00 a 0xFF pedindo o LBA 16 de cada drive
;    2. o drive que devolver "CD001" no offset 1 e' o CD
;    3. le o extent do diretorio root de dentro do PVD
;    4. percorre os registros do diretorio ate casar o nome do nucleo
;    5. le o arquivo do disco para 0:0x8000
;    6. varre o binario carregado procurando a assinatura "ROOT"
;    7. salta para o offset de entrada que o cabecalho do nucleo guardou
;
;  DUAS ARMADILHAS DA BIOS, ambas Macs testadas aqui:
;    - todo int 13h destroi DS e ES, entao a subrotina "le" reconstroi
;      os dois depois de cada chamada;
;    - AH=41h tem de vir antes de AH=42h. Sem ele a leitura nao da
;      erro, nao transfere nada, e o codigo acha que leu.
; =====================================================================

BITS 16
ORG 0x7C00

; ============================== CONFIG ==============================
ATTR_BRANCO  equ 0x0F
SEG_VIDEO    equ 0xB800
SETOR        equ 2048
COLUNAS      equ 80

BUF_PVD      equ 0x4000        ; 0x4000-0x47FF  PVD
BUF_DIR      equ 0x4800        ; 0x4800-0x4FFF  diretorio root
SEG_PILHA    equ 0x6000        ; 0x6000-0x6FFF  pilha
OFF_PILHA    equ 0x0FFF

CARGA_BASE   equ 0x8000        ; = ORG do nucleo.asm
H_ENT        equ 6             ; campo "entrada" dentro do cabecalho
ASSIN_LO     equ 0x4F52        ; 'R','O'   little-endian
ASSIN_HI     equ 0x544F        ; 'O','T'   little-endian

; Assinatura "CD001" do PVD, lida a partir do offset 1 e comparada de
; 2 em 2 bytes. O PVD tem 01 'C' 'D' '0' '0' '1' 01 00, entao a partir
; do offset 1 as palavras em little-endian sao exatamente estas.
; Comparar palavra a palavra e obrigatorio: um "cmp word [PVD+1], 'C'"
; traria o byte seguinte junto e nunca casaria com 0x0043.
SIG_CD       equ 0x4443        ; 'C' 'D'
SIG_00       equ 0x3030        ; '0' '0'
SIG_1V       equ 0x0131        ; '1' e o byte de versao 0x01 (0x01 na
                              ; palavra ALTA: little-endian, '1' = 0x31
                              ; ocupa o byte baixo, a versao o alto)

; Offsets de um registro de diretorio ISO9660:
;   +0  comprimento do registro
;   +2  extent (LBA), 8 bytes nas duas ordens
;   +10 data length, 8 bytes nas duas ordens
;   +32 comprimento do identificador
;   +33 identificador
; Logo o comprimento do registro e 33 + comprimento do nome. O +33 do
; identificador e o ponto classico de off-by-one: usar +34 faz o
; calculo do tamanho do registro estourar em 1 e o parser aceitar
; registro corrompido em vez de recusar.
DIR_EXTENT   equ 2
DIR_TAMANHO  equ 10
DIR_NOME_TAM equ 32
DIR_NOME     equ 33

; =============================== BOOT ===============================
inicio:
    mov ax, 0x0003              ; 80x25 colorido, limpa a tela
    int 0x10
    xor ax, ax
    mov ds, ax
    mov es, ax

    mov ax, SEG_PILHA
    mov ss, ax
    mov sp, OFF_PILHA

    ; ---- mensagem de boot, branco, direto na memoria de video ----
    mov ax, SEG_VIDEO
    mov es, ax
    xor di, di
    mov si, msg_boot
    mov cx, msg_boot_tam
.escreve:
    lodsb
    mov ah, ATTR_BRANCO
    mov [es:di], ax
    add di, 2
    loop .escreve
    xor ax, ax
    mov es, ax

    ; ============ acha o CD pela assinatura CD001, sem fixar DL ============
    ; O contador de drives fica na memoria, e NAO em CL: o int 13h pode
    ; clobberar CX, e um contador em registro transformaria a varredura
    ; numa corrida. Pelo mesmo motivo DL e' recarregado da memoria antes
    ; da segunda chamada.
    mov word [dap+4], BUF_PVD  ; buffer do DAP
    mov word [dap+8], 16       ; LBA 16 (palavra baixa; a alta ja e 0)
    mov word [CNT], 0x0100      ; 256 tentativas
.varre:
    dec word [CNT]
    mov dl, byte [CNT]         ; 0xFF, 0xFE, ... , 0x01, 0x00
    mov ah, 0x41                ; o drive tem extensao?
    mov bx, 0x55AA
    int 0x13
    jc .proximo
    cmp bx, 0xAA55
    jne .proximo
    mov si, dap
    mov dl, byte [CNT]          ; o int 13h pode ter mexido em DL
    call le
    jc .proximo
    cmp word [BUF_PVD+1], SIG_CD    ; "CD001" no offset 1 do PVD
    jne .proximo
    cmp word [BUF_PVD+3], SIG_00
    jne .proximo
    cmp word [BUF_PVD+5], SIG_1V
    jne .proximo
    jmp achou_cd
.proximo:
    cmp word [CNT], 0
    jne .varre
    jmp erro

achou_cd:
    ; DL e' recuperado do contador, e nao do registro: a subrotina "le"
    ; chama o int 13h, que pode destruir DL. Sem esta linha o DRV
    ; guardado seria o que sobrou no registro (0x00 no QEMU), e a
    ; proxima leitura falharia com CF=1 num drive que existe.
    mov dl, byte [CNT]
    mov [DRV], dl              ; so agora o numero do drive e' conhecido

    ; --------- le o diretorio root, com o extent vindo do PVD ---------
    mov si, BUF_PVD+158        ; registro do root = PVD+156, extent = +2
    mov di, dap+8
    mov cx, 4
    rep movsb                  ; copia o extent direto para dentro do DAP
    mov word [dap+4], BUF_DIR
    mov si, dap
    mov dl, [DRV]
    call le
    jc erro

    ; ------- percorre os registros do diretorio casando pelo nome -------
    mov si, BUF_DIR
.registro:
    cmp byte [si], 0            ; comprimento 0 = fim do diretorio
    je erro
    cmp byte [si+DIR_NOME_TAM], NOME_TAM  ; tamanho do nome bate?
    jne .pular
    push si
    mov di, si
    add di, DIR_NOME
    mov si, nome_nuc
    mov cx, NOME_TAM
    repe cmpsb
    pop si
    jne .pular
    jmp achou_arq
.pular:
    xor ah, ah
    mov al, [si]                ; avanca pelo comprimento do registro
    add si, ax
    jmp .registro

achou_arq:
    push si
    add si, DIR_EXTENT         ; o extent fica em +2, NAO no inicio do
    mov di, dap+8              ; registro: sem este add, o DAP recebe o
    mov cx, 4                  ; comprimento e o byte de atributo estendido
    rep movsb                  ; no lugar do LBA, e a leitura pega o setor
    pop si                     ; errado (aparenta funcionar, retorna erro)
    add si, DIR_TAMANHO
    mov di, TAM
    mov cx, 4
    rep movsb

    ; ============ le o nucleo para 0:0x8000, ate cobrir o tamanho ============
    ; Compara o ponteiro de destino com o fim, em vez de contar setores.
    ; O DAP e' lido e reescrito no lugar, entao o LBA avanca em 1 por volta.
    mov ax, [TAM]               ; palavra baixa do data length
    add ax, CARGA_BASE
    mov [FIM], ax
    mov word [dap+4], CARGA_BASE
.carrega:
    mov si, dap
    mov dl, [DRV]
    call le
    jc erro
    add word [dap+4], SETOR     ; proximo setor vai para 2048 adiante
    inc word [dap+8]           ; LBA + 1
    jnz .lba_ok
    inc word [dap+10]          ; estoura a palavra baixa? sobe a alta
.lba_ok:
    mov ax, [dap+4]
    cmp ax, [FIM]
    jb .carrega

    ; ======= varre o binario carregado atrás da assinatura "ROOT" =======
    mov cx, SETOR              ; a assinatura esta no primeiro setor
    mov di, CARGA_BASE
.assinatura:
    cmp word [di], ASSIN_LO      ; "RO"
    jne .prox_byte
    cmp word [di+2], ASSIN_HI    ; "OT"
    je .achou
.prox_byte:
    inc di
    loop .assinatura
    jmp erro
.achou:
    mov bx, [di+H_ENT]          ; offset da entrada dentro do arquivo
    add bx, di                  ; endereco linear da entrada
    push 0                      ; CS = 0, igual ao ORG 0x8000 do nucleo
    push bx
    retf

; ============ le 1 setor: SI = DAP, DL = drive. CF = erro ============
le:
    mov ah, 0x42
    int 0x13
    pushf
    xor ax, ax                  ; a BIOS destruiu DS e ES
    mov ds, ax
    mov es, ax
    popf
    ret

; ============================== ERRO ================================
erro:
    mov ax, SEG_VIDEO
    mov es, ax
    mov di, COLUNAS * 2         ; 'E' no comeco da linha 1
    mov word [es:di], 0x0F45
    cli
.parado:
    hlt
    jmp .parado

; ============================== DADOS ===============================
msg_boot:    db "Root OS Beta v0.1 Build 0.1.2026"
msg_boot_tam equ $ - msg_boot
nome_nuc:    db "nucleo-0.2.2026"
; Derivado da string, e nao digitado a mao: assim o comprimento que o
; parser exige e o comprimento que o nome realmente tem, por construcao.
NOME_TAM     equ $ - nome_nuc
DRV:         db 0
CNT:         dw 0
TAM:         dw 0, 0
FIM:         dw 0

; DAP do INT 13h. size=0x10, 1 setor, segmento 0, LBA alto 0.
; Os campos de offset e LBA sao reescritos pelo codigo.
dap:         db 0x10, 0x00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ======================= TABELA DE PARTICAO ========================
    times 0x1BE - ($ - $$) db 0
    db 0x80, 0x00, 0x01, 0x01  ; ativa, CHS inicial
    db 0x06, 0x00, 0x01, 0x01  ; tipo FAT16, CHS final
    dd 1                         ; LBA inicial, relativo a imagem
    dd 1                         ; total de setores
    times 510 - ($ - $$) db 0
    dw 0xAA55

; ================ AREA DO STAGE 2 (setor 1, reservado) ==============
    times 512 db 0
