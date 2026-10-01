# Contribuindo

Obrigado por ajudar a melhorar o kit.

## Antes de abrir um PR

1. Abra uma issue descrevendo o problema ou a ideia, com um exemplo real.
2. Mantenha o PR pequeno e focado em uma coisa.
3. Rode as checagens:
   ```bash
   bash -n install.sh uninstall.sh kit/.dadosnow/gate.sh
   bash tests/test_kit.sh
   cd examples/demo-app && python3 -m unittest -q
   ```
4. Se mudou o instalador ou o gate, rode o roteiro de
   `examples/demo-app/README.md` num diretório descartável e conte no PR o
   que viu.
5. Se mudou uma skill ou um agente, mostre no PR um exemplo do comportamento
   antes e depois.

## Regras do projeto

- O instalador é aditivo: nunca sobrescreve arquivo do usuário sem `--force`.
- O gate é fail-open: só `VERDICT: BLOCK` bloqueia o push.
- Os subagentes são só leitura.
- Documentação para o usuário em português; código, skills, agentes e
  commits em inglês.

## Licença

Ao contribuir, você concorda que sua contribuição seja distribuída sob a
licença MIT do projeto.
