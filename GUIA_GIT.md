# Guia de entrega (Git/GitHub) – não precisa ir para o repositório

## 1. Fork, clone e branch

1. No GitHub, abra <https://github.com/aXR6/Web_Crawler_Eleicao_2026> e clique em **Fork** (conta de um dos integrantes).
2. Clone o **seu fork**:
   ```bash
   git clone https://github.com/<usuario>/Web_Crawler_Eleicao_2026.git
   cd Web_Crawler_Eleicao_2026
   git checkout -b melhoria-xp
   ```
3. O PDF pede para adicionar `thalles_tsc@hotmail.com`: convide essa conta em
   *Settings → Collaborators* do fork (ou envie o link, conforme o professor orientar).

## 2. Diagnóstico antes do código

Copie o `README.md` deste pacote, deixe só as seções 1–3 preenchidas, e faça o primeiro commit:

```bash
git add README.md
git commit -m "docs: diagnostica problemas e planeja melhorias"
```

## 3. Commits pequenos, na ordem sugerida

Copie o `buscador.sh` final para o repositório e vá reconstruindo em etapas (ou use `git add -p`
para separar os trechos). Rode o script depois de cada etapa. Alternem Driver/Navigator a cada commit.

| # | Mensagem sugerida | O que entra |
|---|---|---|
| 1 | `docs: diagnostica problemas e planeja melhorias` | README (diagnóstico) |
| 2 | `refactor: separa o script em funções e adiciona --help` | `parse_args`, `usage`, `validate_config`, `print_table` |
| 3 | `fix: trata 404 por cargo e remove retry de erros 404` | `fetch_json` |
| 4 | `feat: consulta todos os municípios da UF` | `fetch_municipios`, `filter_municipios` |
| 5 | `feat: permite escolher 1º e 2º turno` | `--turno`, códigos 6258/6260 |
| 6 | `feat: indica candidatos eleitos` | `load_elected`, coluna SITUAÇÃO |
| 7 | `fix: alinha tabelas com caracteres acentuados` | `pad`, locale UTF-8 |
| 8 | `test: adiciona testes de aceitação com dados simulados` | `tests/` |
| 9 | `docs: documenta uso, pair programming e validação` | README final |

## 4. Publicar e fazer o merge na main do fork

```bash
git status
git push -u origin melhoria-xp
git checkout main
git merge melhoria-xp
git push origin main
./buscador.sh -m 07242 -c 3 -l 3     # confirma que a main continua executável
```

## 5. Antes de entregar

- [ ] Link do **fork** com a `main` atualizada
- [ ] `git log --oneline` mostra vários commits pequenos
- [ ] README com nomes da dupla, divisão Driver/Navigator e evidência real de execução
- [ ] Rodou `./buscador.sh` no seu computador com a internet do TSE (mudanças do site podem exigir ajuste)
