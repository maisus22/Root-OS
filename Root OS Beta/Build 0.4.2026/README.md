Na Build 0.4.2026, o Root OS Beta tem como foco o funcionamento do Núcleo e a transição para a interface. Depois que o sistema é inicializado, o Núcleo assume o controle e realiza sua etapa inicial de execução(configura drivers). Após os 10 segundos, o Núcleo finaliza essa etapa e passa o controle para a interface do Root OS. A partir desse momento, a interface começa a assumir o controle da parte visual do sistema. Como etapa final desta build, a interface gráfica pinta toda a tela de branco e o sistema permanece parado nesse estado. Essa tela branca representa a primeira transição entre o Núcleo do Root OS e a futura interface que será utilizada pelo usuário.

QEMU: qemu-system-i386 -cdrom root_os_beta.iso -boot d

<img width="645" height="542" alt="image" src="https://github.com/user-attachments/assets/8f5bb200-ebdd-4148-ba23-fcf310619c56" />
