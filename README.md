# Web_Crawler_Eleicao_2026

Script em Shell (`buscador.sh`) que consulta os arquivos públicos de divulgação de resultados do TSE
(Eleições Gerais 2026) e mostra, **para cada município de uma UF**, os candidatos mais votados de cada
cargo, **separando 1º e 2º turno** e **indicando os eleitos**.

> Atividade prática de Engenharia de Software (UNIFACIMP Wyden): Manifesto Ágil e Extreme Programming,
> em duplas, com pair programming.

**Dupla:** `<Nome 1>` e `<Nome 2>`  ·  **Fork:** `https://github.com/<usuario>/Web_Crawler_Eleicao_2026`

---

## 1. Pré-requisitos

- Bash 4.3 ou superior (usa arrays associativos e `local -n`)
- `curl` e `jq`
- Acesso à internet para `https://resultados.tse.jus.br`

```bash
sudo apt install curl jq      # Debian/Ubuntu
```

## 2. Como executar

```bash
chmod +x buscador.sh
./buscador.sh                 # 1º turno, todos os municípios do Maranhão
./buscador.sh --help          # todas as opções
```

| Opção | Descrição |
|---|---|
| `-u, --uf UF` | UF consultada (padrão `ma`) |
| `-m, --municipio X` | Código TSE de 5 dígitos **ou** parte do nome. Sem a opção: todos os municípios |
| `-t, --turno 1\|2\|todos` | Turno exibido (padrão `1`); `todos` mostra os dois em seções separadas |
| `-c, --cargos LISTA` | `1` Presidente, `3` Governador, `5` Senador, `6` Dep. Federal, `7` Dep. Estadual |
| `-l, --limite N` | Candidatos por tabela (padrão `20`) |
| `-e, --somente-eleitos` | Mostra só os eleitos |
| `--listar-municipios` | Lista os municípios da UF e sai |
| `--cor auto\|always\|never` | Cores ANSI |

As variáveis `TSE_RESULTS_*` do script original continuam valendo (`TSE_RESULTS_UF`, `TSE_RESULTS_LIMIT`,
`TSE_RESULTS_COLOR`, `TSE_RESULTS_BASE_URL`…); foram acrescentadas `TSE_RESULTS_TURNO`, `TSE_RESULTS_CARGOS`
e os códigos do 2º turno (`TSE_RESULTS_FEDERAL_ELECTION_2T`, `TSE_RESULTS_STATE_ELECTION_2T`).

### Exemplos

```bash
./buscador.sh -t 2 -c 3                  # 2º turno de Governador, todos os municípios
./buscador.sh -m 07242 -t todos          # Imperatriz, 1º e 2º turnos
./buscador.sh -m "são luís" -e           # só os eleitos, em São Luís
./buscador.sh -c 1,3 -l 5 > resultado.txt
```

Exemplo de saída (dados ilustrativos):

```
ELEITOS - Governador (MA)
+--------------+--------+-------+----------+
| NOME         | NÚMERO | VOTOS | SITUAÇÃO |
+--------------+--------+-------+----------+
| GOVERNADOR X |     11 |  3000 | ELEITO   |
+--------------+--------+-------+----------+
```

**Como ler "ELEITO":** o eleito é definido na abrangência do cargo (Brasil para Presidente; UF para
Governador, Senador e deputados). Nas tabelas de cada município, o candidato é marcado como `ELEITO` se
foi eleito no cargo, mesmo que não tenha sido o mais votado naquele município. Eleitos aparecem primeiro.

## 3. Diagnóstico (antes de alterar o código)

Pontos encontrados ao executar e ler o script original:

| # | Problema | Efeito |
|---|---|---|
| 1 | UF e município fixos (`ma` / `07242`) | Só um município era consultado |
| 2 | Códigos de eleição fixos do 1º turno (`6257`/`6259`) | Impossível ver o 2º turno (`6258`/`6260`) |
| 3 | Nenhum uso do campo de eleito | Resultado não indicava quem foi eleito |
| 4 | `--retry-all-errors` no `curl` | Repete requisições 404; o TSE avisa que muitos 404 podem bloquear o IP |
| 5 | Qualquer falha (inclusive 404) encerrava tudo, com mensagem sem URL nem código HTTP | Um município/cargo sem arquivo derrubava a execução |
| 6 | Alinhamento da tabela com `printf %-*s` | Colunas desalinhadas com acentos fora de locale UTF-8 |
| 7 | Configuração só por variáveis de ambiente, sem `--help` | Difícil de usar e de descobrir |
| 8 | Lógica toda dentro de um `for` | Difícil de testar e de manter |

Melhorias planejadas: municípios da UF lidos do arquivo de configuração do TSE (EA12); parâmetro de turno
com códigos de eleição por turno; eleitos lidos do arquivo EA20 da abrangência do cargo; tratamento de 404
por cargo/município; opções de linha de comando; funções pequenas; testes automatizados.

## 4. Melhorias e correções realizadas

1. **Todos os municípios do MA** – a lista vem de `ele2026/<eleição>/config/mun-e<eleição>-cm.json`;
   `--municipio` agora é filtro opcional (código ou nome).
2. **1º e 2º turno** – `--turno 1|2|todos`, com códigos `6257/6259` (1º) e `6258/6260` (2º) e seções separadas.
   No 2º turno só são consultados os cargos que têm 2º turno (Presidente e Governador).
3. **Eleitos** – coluna `SITUAÇÃO` e quadro `ELEITOS` por cargo, a partir do campo `e == "s"` do EA20 da UF
   (ou do Brasil, para Presidente). `--somente-eleitos` filtra.
4. **Robustez** – 404 vira aviso "sem dados" (sem repetir a requisição); erros de rede, bloqueio (403/429),
   JSON inválido, UF inexistente e parâmetros inválidos têm mensagem clara e saída ≠ 0.
5. **Legibilidade** – funções por responsabilidade, `--help`, alinhamento por caracteres (UTF-8), legenda.

## 5. Pair programming

| Ciclo | Driver | Navigator | O que foi feito |
|---|---|---|---|
| 1 | `<Nome 1>` | `<Nome 2>` | `<ex.: diagnóstico e lista de problemas>` |
| 2 | `<Nome 2>` | `<Nome 1>` | `<ex.: municípios do MA>` |
| 3 | … | … | … |

> Preencham com o que realmente aconteceu; os papéis foram trocados a cada ciclo/commit.

## 6. Validação

`tests/run_tests.sh` sobe um servidor HTTP local com arquivos no mesmo formato do TSE
(`tests/make_fixtures.py`) e executa 21 verificações: todos os municípios, turnos separados, eleitos
marcados, filtros, limite, município sem arquivo, parâmetros e servidor inválidos, ausência de ANSI.

```bash
tests/run_tests.sh
# ... 21 ok, 0 falha(s)
```

**Evidência com dados reais:** `<cole aqui a saída de ./buscador.sh -m 07242 -t todos -c 3,1 -l 5 executado no seu computador>`

## 7. Limitações conhecidas

- A estrutura dos JSON (campos `abr/mu`, `carg/cand`, `e`, `vap`) segue a documentação do TSE e o script
  original; os testes automatizados usam dados simulados.
- O código de eleição do 2º turno estadual (`6260`) vem da página técnica do TSE; se mudar, use
  `TSE_RESULTS_STATE_ELECTION_2T`.
- São ~217 municípios × até 5 cargos: a execução completa faz centenas de requisições sequenciais.
  Use `-m`, `-c` e `-t` para consultas rápidas.

## 8. Fonte dos dados

Tribunal Superior Eleitoral, divulgação de resultados:
<https://www.tse.jus.br/eleicoes/informacoes-tecnicas-sobre-a-divulgacao-de-resultados>
