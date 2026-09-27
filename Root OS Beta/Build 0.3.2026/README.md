build 0.3.2026 era fazer o Root OS Beta abrir e mostrar o próprio nome na tela sozinho, sem depender do BIOS para desenhar, e para isso o trabalho de verdade estava todo no driver de vídeo (videoVGA.dr): ele é quem encontra a placa de vídeo, programa o modo 640x480 com 16 cores, e o nucleo monta as três linhas de texto — "Root OS Beta v0.1 Build 0.3.2026", "nucleo-0.3.2026" e "videoVGA.dr configurado com sucesso"

QEMU: qemu-system-i386 -cdrom root_os_beta.iso -boot d

