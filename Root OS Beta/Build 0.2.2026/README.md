A build 0.2.2026 é o primeiro milestone em que o Root OS Beta deixa de ser um único arquivo e passa a ter dois: o inicio.asm monta um setor de boot de 1024 bytes com MBR válida, e o nucleo.asm monta um binário separado, nucleo-0.2.2026, que entra na ISO como arquivo comum ao lado do inicio.root. Na hora de bootar, o stage 1 assume o controle em modo real, monta a tela, imprime a mensagem de boot na linha 0 e então procura o núcleo em runtime: varre os drives de 0x00 a 0xFF, identifica o CD pela assinatura CD001 do descritor primário de volume, lê o extent do diretório root de dentro do PVD e percorre os registros ISO9660 comparando byte a byte o nome nucleo-0.2.2026, sem nenhum LBA ou número de drive escrito a mão. Achando o registro, extrai o extent e o tamanho do arquivo, carrega os setores em 0:0x8000 e varre o binário procurando a assinatura ROOT, que guarda o offset do ponto de entrada; daí salta para 0:0x8000+entrada e o núcleo imprime nucleo-0.2.2026 na linha 1 e para com cli/hlt.

QEMU: qemu-system-i386 -cdrom root_os_beta.iso -boot d

<img width="721" height="466" alt="image" src="https://github.com/user-attachments/assets/d1840ba1-6808-4374-aa36-a26c30c669af" />

OBS:. Esqueci de trocar o numero da Build!!!
