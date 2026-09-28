; =====================================================================
;  ROOT OS BETA - inicio.asm
;  Stage 1. 100% assembly, 16 bits, modo real, sem nenhum registrador
;  de 32 bits e sem nenhuma instrucao com prefixo de operand size.
;
;  Recebido da BIOS em 0000:7C00 pelo El Torito (hard-disk emulation),
;  com DL = 0x80. NAO escreve nada na tela, nem no modo de video: quem
;  programa a tela e' o driver, e quem escreve texto e' o nucleo. Este
;  stage 1 so' carrega TRES arquivos da ISO, cada um em seu endereco,
;  sem nenhum LBA de arquivo e sem nenhum numero de drive escrito a mao:
;
;    1. varre DL de 0x00 a 0xFF pedindo o LBA 16 de cada drive
;    2. o drive que devolver "CD001" no offset 1 e' o CD
;    3. le o extent do diretorio root de dentro do PVD
;    4. procura um arquivo pelo nome, dentro do diretorio root
;    5. repete o passo 4 para o driver de video, para a interface e
;       para o nucleo
;    6. entrega ao nucleo, numa area de memoria fixa que os dois lados
;       combinam, o endereco do driver e o ponteiro far da interface
;    7. pula para a entrada do nucleo, indicada pelo cabecalho "ROOT"
;
;  Os tres arquivos sao independentes: videoVGA.dr e' o driver de video,
;  interface.grain e' a interface, e nucleo-0.5.2026 e' o nucleo. O
;  stage 1 so' carrega e passa o endereco; o que cada um faz depois e'
;  assunto de cada arquivo, e nenhum deles conhece o nome dos outros.
;
;  TRES ARMADILHAS DA BIOS, todas testadas aqui:
;    - todo int 13h destroi DS e ES, entao a subrotina "le" reconstroi
;      os dois depois de cada chamada;
;    - AH=41h tem de vir antes de AH=42h. Sem ele a leitura nao da
;      erro, nao transfere nada, e o codigo acha que leu;
;    - int 13h tambem pode mexer em DL, entao o numero do drive vive
;      em CNT e e' relido na hora de cada leitura, e nunca no registro.
;
;  O LIMITE FISICO: a area de codigo do MBR acaba em 0x1BE, onde comeca
;  a tabela de particoes. Sao 446 bytes, e o codigo esta orcamentado
;  para caber ali. Os DADOS nao cabem mais, entao moram no setor
;  seguinte, em 0x7E00, que a BIOS tambem carrega.
; =====================================================================

BITS 16
ORG 0x7C00

; ============================== CONFIG ==============================
SETOR        equ 2048

BUF_PVD      equ 0x4000        ; 0x4000-0x47FF  PVD
BUF_DIR      equ 0x4800        ; 0x4800-0x4FFF  diretorio root
SEG_PILHA    equ 0x6000
OFF_PILHA    equ 0x0FFF

; Area de passagem de controle entre o stage 1 e o nucleo. Fica em
; memoria convencional baixa, longe da pilha, dos buffers e do
; framebuffer. O stage 1 so ESCREVE aqui; o driver e o nucleo leem.
HANDOFF      equ 0x0600
HANDOFF_DRIVER equ HANDOFF+0  ; dw: endereco de carga do videoVGA.dr
HANDOFF_MSG   equ 0x0604      ; dw: offset da msg_boot, para o nucleo
                              ;     desenhar a linha 0 sem ter uma
                              ;     segunda copia do texto do boot
HANDOFF_IFACE equ 0x0606      ; dword: ponteiro far da interface, com o
                              ;     offset nas duas primeiras bytes e o
                              ;     segmento nas duas seguintes. E' o
                              ;     mesmo formato do "jmp dword", e e'
                              ;     nele que o nucleo salta depois das
                              ;     duas telas de espera.
HANDOFF_MOUSE equ 0x0628      ; dword: ponteiro far do mouse.dr, mesmo
                              ;     formato do jmp dword. E' o endereco
                              ;     de CARGA_MOUSE; se o arquivo faltar
                              ;     na ISO, este campo fica zero e o
                              ;     nucleo entra na interface sem
                              ;     bolinha, em vez de travar o boot.
HANDOFF_ERRO  equ HANDOFF+0x0A ; dw: 0 enquanto o boot esta' indo bem,
                              ;     ERRO_BOOT se o stage 1 parou. O
                              ;     nucleo nunca le este campo: ele so'
                              ;     existe para o boot mudo deixar
                              ;     rastro em memoria.

CARGA_NUCLEO equ 0x8000        ; = ORG do nucleo.asm
CARGA_DRIVER equ 0x9000        ; = ORG do videoVGA.asm
CARGA_IFACE  equ 0xA000        ; = ORG do interface.asm
CARGA_MOUSE  equ 0x9800        ; = ORG do mouse.asm
ASSIN_LO     equ 0x4F52        ; 'R','O'   little-endian
ASSIN_HI     equ 0x544F        ; 'O','T'   little-endian
H_ENT        equ 6             ; campo "entrada" dentro do cabecalho

; Assinatura "CD001" do PVD, lida a partir do offset 1 e comparada de
; 2 em 2 bytes. O PVD tem 01 'C' 'D' '0' '0' '1' 01 00, entao a partir
; do offset 1 as palavras em little-endian sao exatamente estas.
; Comparar palavra a palavra e obrigatorio: um "cmp word [PVD+1], 'C'"
; traria o byte seguinte junto e nunca casaria com 0x0043.
SIG_CD       equ 0x4443        ; 'C' 'D'
SIG_00       equ 0x3030        ; '0' '0'
SIG_1V       equ 0x0131        ; '1' no byte baixo, versao 0x01 no alto

; Offsets de um registro de diretorio ISO9660:
;   +0  comprimento do registro
;   +2  extent (LBA), 8 bytes nas duas ordens
;   +10 data length, 8 bytes nas duas ordens
;   +32 comprimento do identificador
;   +33 identificador
; Logo o comprimento do registro e 33 + comprimento do nome. O +33 do
; identificador e' o ponto classico de off-by-one: usar +34 faz o
; calculo do tamanho do registro estourar em 1 e o parser aceitar
; um registro corrompido em vez de recusar.
DIR_EXTENT   equ 2
DIR_TAMANHO  equ 10
DIR_NOME_TAM equ 32
DIR_NOME     equ 33

; =============================== BOOT ===============================
inicio:
    ; Nenhum int 10h aqui: o stage 1 nao escolhe modo de video nem limpa
    ; a tela. Quem faz isso e' o driver, depois que o nucleo chama ele, e
    ; quem escreve as linhas de texto e' o nucleo. Se este stage 1
    ; montasse a tela, o driver encontraria um modo ja posto por um
    ; codigo que ele nao controla e a tela mostraria o que o BIOS deixou.
    xor ax, ax
    mov ds, ax
    mov es, ax

    mov ax, SEG_PILHA
    mov ss, ax
    mov sp, OFF_PILHA

    ; A mensagem de boot fica so' como string na memoria. O nucleo
    ; desenha a linha 0 com ela, entao nao ha texto gravado no buffer de
    ; video: o ponteiro vai no handoff e o TEXTO do nucleo faz a conta.
    mov word [HANDOFF_MSG], msg_boot

    ; ============ acha o CD pela assinatura CD001, sem fixar DL ============
    ; O contador de drives fica na memoria, e NAO em CL: o int 13h pode
    ; clobberar CX, e um contador em registro transformaria a varredura
    ; numa corrida. O numero do drive e' sempre relido de CNT, e nunca
    ; guardado em registro, porque o int 13h pode mexer em DL tambem.
    ;
    ; A varredura caminha de 0x00 a 0xFF e para quando CNT dá a volta, em
    ; vez de tentar um numero fixo ou um decremento. Um "dec" antes de
    ; usar o contador comecaria em 0xFF, que nao e' drive nenhum: os 256
    ; DH falhariam no AH=41h e o boot cairia direto no erro. Aqui cada
    ; DL e' testado, e so e' descartado se o AH=41h responder que o
    ; drive nao existe ou se o LBA 16 nao for um PVD de CD.
    mov word [CNT], 0x0000          ; comeca no drive 0x00
.varre:
    mov dl, byte [CNT]
    mov ah, 0x41                    ; o drive tem extensao?
    mov bx, 0x55AA
    int 0x13
    jc .proximo                     ; drive inexistente
    mov si, dap                    ; le o PVD: buffer e LBA 16 ja estao
    call le                        ; gravados nos bytes do proprio DAP
    jc .proximo
    cmp word [BUF_PVD+1], SIG_CD    ; "CD001" no offset 1 do PVD
    jne .proximo
    cmp word [BUF_PVD+3], SIG_00
    jne .proximo
    cmp word [BUF_PVD+5], SIG_1V
    jne .proximo
    jmp achou_cd
.proximo:
    inc byte [CNT]                 ; 0xFF -> 0x00 encerra a varredura
    jnz .varre
    jmp erro

achou_cd:
    ; --------- le o diretorio root, com o extent vindo do PVD ---------
    ; O segmento do DAP ja e' zero desde a definicao, entao o diretorio
    ; (0000:4800), o nucleo (0000:8000) e o driver (0000:9000) sao todos
    ; so um offset: basta mexer em dap+4.
    mov si, BUF_PVD+158        ; registro do root = PVD+156, extent = +2
    mov di, dap+8
    mov cx, 4
    rep movsb                  ; copia o extent direto para dentro do DAP
    mov word [dap+4], BUF_DIR
    mov si, dap
    call le
    jc erro

; =================== carrega o driver de video primeiro ===================
; A ordem importa por dois motivos: o driver precisa estar em memoria
; antes de o nucleo rodar, e a pasta BUF_DIR precisa sobreviver intacta
; ate o segundo carregamento. 0x9000 fica abaixo do framebuffer 0xA0000
; e da janela de texto 0xB8000, e a 64 KB de espaco livre.
    mov si, nome_drv
    mov bp, nome_drv_tam
    mov di, CARGA_DRIVER
    call carrega
    jc erro
    mov [HANDOFF_DRIVER], di   ; o endereco que o nucleo vai ler

; ================== carrega a interface (arquivo separado) ==========
; A interface e' um terceiro arquivo da ISO, e nao parte do driver:
; o driver so' programa a placa. Ela entra logo acima do driver, e o
; ponteiro far completo fica em 0x0606, no formato que o "jmp dword"
; do nucleo le: offset nas duas primeiras bytes, segmento nas duas
; seguintes. O segmento e' zero porque o ORG dela e' 0xA000 com
; segmento zero, entao 0xA000 e' um endereco linear.
    mov si, nome_ifc
    mov bp, nome_ifc_tam
    mov di, CARGA_IFACE
    call carrega
    jc erro
    mov [HANDOFF_IFACE], di       ; offset: 0xA000
    mov word [HANDOFF_IFACE+2], 0 ; segmento: 0

; =================== carrega o driver do mouse ==================
; O mouse.dr e' um QUARTO arquivo da ISO, e o ultimo a ser carregado:
; ele so' precisa estar na memoria antes de o nucleo comecar, e a
; pasta BUF_DIR ja foi reescrita pelas tres cargas anteriores, o que
; nao atrapalha porque o diretorio inteiro cabe num setor.
;
; Este arquivo e' o unico dontem "falha nao derruba o boot": se o
; mouse.dr nao estiver na ISO, o ponteiro em 0x0628 fica zero, o
; nucleo escreve "mouse.dr nao configurado" e segue para a interface
; sem bolinha. Um driver de video faltando trava o boot, porque sem
; video nao ha nem erro para mostrar; um mouse faltando so' tira a
; bolinha.
    mov si, nome_mou
    mov bp, nome_mou_tam
    mov di, CARGA_MOUSE
    call carrega
    jnc .tem_mouse
    ; nao achou o arquivo: o ponteiro e' que fica em zero, e o
    ; segmento tambem, para o "jmp dword" do nucleo ter um par
    ; coherente mesmo sem nada para executar
    mov word [HANDOFF_MOUSE], 0
    mov word [HANDOFF_MOUSE+2], 0
    jmp carrega_nucleo
.tem_mouse:
    mov [HANDOFF_MOUSE], di       ; offset: 0x9800
    mov word [HANDOFF_MOUSE+2], 0 ; segmento: 0, como o ORG do mouse.asm

; ====================== carrega o nucleo ======================
carrega_nucleo:
    mov si, nome_nuc
    mov bp, nome_nuc_tam
    mov di, CARGA_NUCLEO
    call carrega
    jc erro

; ===== o cabecalho "ROOT" fica no offset 0 do arquivo, por contrato =====
; Conferir direto no offset 0 em vez de varrer o binario inteiro poupa
; codigo no MBR, e o proprio cabecalho e' a razao pela qual a busca e'
; suficiente: se a assinatura nao estiver no comeco, o arquivo esta
; corrompido e abortar e' a resposta certa.
    cmp word [CARGA_NUCLEO], ASSIN_LO
    jne erro
    cmp word [CARGA_NUCLEO+2], ASSIN_HI
    jne erro
    mov bx, [CARGA_NUCLEO+H_ENT]  ; offset da entrada dentro do arquivo
    add bx, CARGA_NUCLEO          ; endereco linear da entrada
    push 0                        ; CS = 0, igual ao ORG do nucleo
    push bx
    retf

; =====================================================================
;  carrega: procura um arquivo pelo nome no diretorio root e o le
;  entrada:  SI = nome procurado (ASCII, sem 0)
;            BP = comprimento do nome
;            DI = endereco de carga
;  saida:    CF=0 carregou, CF=1 nao achou ou a leitura falhou
;  nota:     BUF_DIR e' reescrito, mas o diretorio inteiro cabe num
;            setor, entao da para carregar os arquivos em sequencia.
; =====================================================================
carrega:
    mov bx, BUF_DIR
.registro:
    cmp byte [bx], 0            ; comprimento 0 = fim do diretorio
    je .falha
    mov cx, bp
    cmp byte [bx+DIR_NOME_TAM], cl  ; so compara nomes do mesmo tamanho
    jne .pular
    push si
    push bx
    push di
    mov di, si                  ; ES:DI = nome procurado
    mov si, bx
    add si, DIR_NOME            ; DS:SI = nome do registro
    mov cx, bp
    repe cmpsb
    pop di
    pop bx
    pop si
    jne .pular
    jmp .achou
.pular:
    xor ah, ah
    mov al, [bx]                ; avanca pelo comprimento do registro
    add bx, ax
    jmp .registro
.achou:
    mov si, bx
    add si, DIR_EXTENT          ; o extent fica em +2, NAO no inicio do
    push di                     ; registro: sem este add, o DAP recebe o
    mov di, dap+8               ; comprimento e o atributo estendido no
    mov cx, 4                   ; lugar do LBA, e a leitura pega o setor
    rep movsb                   ; errado (parece funcionar, da erro)
    pop di
    mov ax, [bx+DIR_TAMANHO]    ; data length, palavra baixa
    add ax, di
    mov [FIM], ax

    ; Le ate o ponteiro de destino cobrir o data length. Comparar
    ; ponteiro em vez de contar setores evita dividir 32 bits por 2048.
    ; O DAP e' lido e reescrito no lugar, entao o LBA avanca em 1.
    mov ax, di
    mov [dap+4], ax
.le:
    mov si, dap
    call le
    jc .falha
    add word [dap+4], SETOR     ; proximo setor vai para 2048 adiante
    inc word [dap+8]           ; LBA + 1
    jnz .lba_ok
    inc word [dap+10]          ; estoura a palavra baixa? sobe a alta
.lba_ok:
    mov ax, [dap+4]
    cmp ax, [FIM]
    jb .le
    clc
    ret
.falha:
    stc
    ret

; ============ le 1 setor: SI = DAP, DL = drive. CF = erro ============
; O drive vem de CNT, que ainda guarda o numero que casou com "CD001":
; assim nao existe mais nenhum "mov dl,[DRV]" espalhado pelo codigo,
; e nenhum caminho pode ler com o DL destruido pelo int 13h.
le:
    mov dl, byte [CNT]
    mov ah, 0x42
    int 0x13
    pushf
    xor ax, ax                  ; a BIOS destruiu DS e ES
    mov ds, ax
    mov es, ax
    popf
    ret

; ============================== ERRO ================================
; Sem CD, sem arquivo ou sem cabecalho "ROOT" o boot para aqui. Como o
; stage 1 nao escreve na tela, nao ha 'E' para o usuario ver: o rastro
; fica na memoria, num campo do handoff que o nucleo nunca le. Assim o
; stage 1 continua mudo e o erro ainda da' para depurar pelo monitor.
erro:
    mov word [HANDOFF_ERRO], ERRO_BOOT
    cli
.parado:
    hlt
    jmp .parado

; ======================= TABELA DE PARTICAO ========================
    times 0x1BE - ($ - $$) db 0
    db 0x80, 0x00, 0x01, 0x01  ; ativa, CHS inicial
    db 0x06, 0x00, 0x01, 0x01  ; tipo FAT16, CHS final
    dd 1                         ; LBA inicial, relativo a imagem
    dd 1                         ; total de setores
    times 510 - ($ - $$) db 0
    dw 0xAA55

; =====================================================================
;  SETOR 1 - OS DADOS DO STAGE 1
;
;  A area de codigo do MBR acaba em 0x1BE, onde comeca a tabela de
;  particoes: sao 446 bytes para o codigo E para os dados, e nao ha
;  como crescer. Como o codigo grew para dentro disso (o terceiro
;  arquivo da ISO, a interface, custou 31 bytes), os dados foram para
;  o setor seguinte, que antes era um bloco de zeros reservado.
;
;  Isso e' seguro por dois motivos. O primeiro e' que o boot carrega a
;  imagem inteira, 2 setores, entao 0x7E00-0x7FFF chega na memoria
;  junto com o codigo. O segundo e' que o codigo em si nao passa de
;  446 bytes: os rotulos de dados sao enderecos absolutos, e o
;  "carrega" e o "le" nao mudaram de lugar nenhum. O stage 1 ter
;  parado de mexer na tela tambem deu folga: antes ele gastava ~40
;  bytes com o modo de video e com a mensagem de boot.
; =====================================================================
dados:
; ============================== DADOS ===============================
; O "v" e' a versao do Root OS e nunca muda: e' 0.1. O que muda a
; cada build e' so' o BUILD depois da palavra "Build", que vem do
; build.sh e tem que bater com o nome do nucleo na ISO.
; msg_boot nao vai mais para a tela: ela e' so' a string que o nucleo
; desenha na linha 0, e o 0 do fim e' o que o TEXTO usa para saber onde
; a string acaba. Sem ele a linha 0 continuaria pelos nomes de arquivo
; que vem a seguir, e a tela mostraria "videoVGA.dr" do lado dela.
msg_boot:    db "Root OS Beta v0.1 Build 0.5.2026", 0
nome_nuc:    db "nucleo-0.5.2026"
nome_nuc_tam equ $ - nome_nuc
nome_drv:    db "videoVGA.dr"
nome_drv_tam equ $ - nome_drv
nome_ifc:    db "interface.grain"
nome_ifc_tam equ $ - nome_ifc
nome_mou:    db "mouse.dr"
nome_mou_tam equ $ - nome_mou
ERRO_BOOT    equ 0xBAD0          ; marcador de "o boot parou aqui"
CNT:         dw 0
FIM:         dw 0

; DAP do INT 13h. size=0x10, 1 setor, buffer 0000:4000, LBA 16. Os
; bytes de buffer e de LBA sao reescritos pelo codigo conforme a
; necessidade; o resto ja nasce certo, e por isso o boot nao gasta
; bytes com "mov word [dap+4], ..." so para montar o primeiro pedido.
;
; A ordem dos 4 bytes do buffer e' OFFSET (2 bytes, little endian) e
; depois SEGMENTO (2 bytes). "0000:4000" e' offset 0x4000 com segmento
; zero, ou seja 00 40 00 00. Escrever 00 00 00 40 aqui nao apontaria
; para 0x4000: apontaria para 0000:0000 com segmento 0x4000, isto e,
; o endereco linear 0x40000. O PVD seria lido 64 KB acima de onde o
; codigo procura "CD001", a busca falharia em todos os 256 drives e o
; boot cairia no erro sem nunca chegar a mensagem de sucesso.
;
; Como o segmento ja e' zero, todos os buffers seguintes (diretorio
; root, nucleo e driver) sao enderecos lineares de memoria baixa e
; precisam apenas do offset: e' por isso que o codigo mexe so em
; dap+4 e nunca em dap+6.
dap:         db 0x10, 0x00, 1, 0          ; tamanho, reservado, setores
              db 0x00, 0x40, 0x00, 0x00    ; buffer 0000:4000 (offset, segmento)
              db 16, 0, 0, 0               ; LBA 16
              db 0, 0, 0                  ; (resto do LBA, 64 bits)


    times 512 - ($ - dados) db 0     ; sobra do setor, zerada
