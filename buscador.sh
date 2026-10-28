'#!/usr/bin/env bash
# buscador.sh - Resultados do TSE (Eleições 2026) por município, turno e cargo.
#
# Consulta os arquivos públicos de divulgação de resultados do TSE (EA20) e
# mostra, para cada município de uma UF, os candidatos mais votados de cada
# cargo, destacando os eleitos. Os eleitos são lidos no arquivo da abrangência
# em que o cargo é decidido (Brasil para Presidente; UF para os demais).
set -Eeuo pipefail

# Garante locale UTF-8 para contar caracteres (e não bytes) ao alinhar as tabelas
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
  *) export LC_ALL=C.UTF-8 ;;
esac

readonly VERSION="2.0.0"
readonly DEFAULT_BASE_URL="https://resultados.tse.jus.br/oficial"

# ---------------------------------------------------------------------------
# Configuração (variáveis de ambiente TSE_RESULTS_* ou opções de linha de comando)
# ---------------------------------------------------------------------------
BASE_URL="${TSE_RESULTS_BASE_URL:-$DEFAULT_BASE_URL}"
YEAR="${TSE_RESULTS_YEAR:-2026}"
UF="${TSE_RESULTS_UF:-ma}"
MUNICIPIO="${TSE_RESULTS_MUNICIPALITY:-}"   # vazio = todos os municípios da UF
LIMIT="${TSE_RESULTS_LIMIT:-20}"
TURNO="${TSE_RESULTS_TURNO:-1}"             # 1, 2 ou todos
CARGOS_OPT="${TSE_RESULTS_CARGOS:-}"        # vazio = todos os cargos do turno
COLOR_MODE="${TSE_RESULTS_COLOR:-auto}"
ONLY_ELECTED=false
LIST_ONLY=false

# Códigos de eleição do TSE (1º turno: 6257/6259; 2º turno: 6258/6260)
declare -A FEDERAL_ELECTION=(
  [1]="${TSE_RESULTS_FEDERAL_ELECTION:-6257}"
  [2]="${TSE_RESULTS_FEDERAL_ELECTION_2T:-6258}"
)
declare -A STATE_ELECTION=(
  [1]="${TSE_RESULTS_STATE_ELECTION:-6259}"
  [2]="${TSE_RESULTS_STATE_ELECTION_2T:-6260}"
)

# Cargos disputados em cada turno (1=Presidente 3=Governador 5=Senador
# 6=Dep. Federal 7=Dep. Estadual). Só Presidente e Governador têm 2º turno.
declare -A CARGOS_DO_TURNO=([1]="6 7 5 3 1" [2]="3 1")

readonly H_NAME="NOME" H_NUMBER="NÚMERO" H_VOTES="VOTOS" H_STATUS="SITUAÇÃO"

declare -gA ELECTED=()   # números dos eleitos do cargo corrente
declare -g ELECTED_JSON='[]'
declare -ga ELECTED_ROWS=()

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*" >&2; }

usage() {
  cat <<EOF
buscador.sh $VERSION - resultados do TSE por município, turno e cargo

Uso: $0 [opções]

Opções:
  -u, --uf UF               Sigla da UF (padrão: ma)
  -m, --municipio VALOR     Código TSE (5 dígitos) ou parte do nome do município.
                            Sem esta opção, consulta TODOS os municípios da UF.
  -t, --turno 1|2|todos     Turno a exibir (padrão: 1). "todos" mostra os dois,
                            cada um em seção separada.
  -c, --cargos LISTA        Cargos separados por vírgula (padrão: todos do turno)
                            1=Presidente 3=Governador 5=Senador
                            6=Deputado Federal 7=Deputado Estadual
  -l, --limite N            Candidatos por tabela (padrão: 20)
  -e, --somente-eleitos     Mostra apenas os candidatos eleitos
      --listar-municipios   Lista os municípios da UF e sai
      --cor auto|always|never
  -h, --help                Mostra esta ajuda
  -V, --version             Mostra a versão

Variáveis de ambiente equivalentes: TSE_RESULTS_UF, TSE_RESULTS_MUNICIPALITY,
TSE_RESULTS_TURNO, TSE_RESULTS_CARGOS, TSE_RESULTS_LIMIT, TSE_RESULTS_COLOR,
TSE_RESULTS_BASE_URL, TSE_RESULTS_YEAR e os códigos de eleição
TSE_RESULTS_FEDERAL_ELECTION[_2T] / TSE_RESULTS_STATE_ELECTION[_2T].

Exemplos:
  $0                              # 1º turno, todos os municípios do MA
  $0 -t 2 -c 3                    # 2º turno de Governador, todos os municípios
  $0 -m 07242 -t todos            # Imperatriz, 1º e 2º turnos
  $0 -m "são luís" -e             # só os eleitos, em São Luís
EOF
}

# ---------------------------------------------------------------------------
# Leitura e validação dos parâmetros
# ---------------------------------------------------------------------------
parse_args() {
  while (($#)); do
    case "$1" in
      -u|--uf|-m|--municipio|-t|--turno|-c|--cargos|-l|--limite|--cor)
        (($# >= 2)) || die "a opção $1 exige um valor" ;;
    esac
    case "$1" in
      -u|--uf)             UF="$2"; shift 2 ;;
      -m|--municipio)      MUNICIPIO="$2"; shift 2 ;;
      -t|--turno)          TURNO="$2"; shift 2 ;;
      -c|--cargos)         CARGOS_OPT="$2"; shift 2 ;;
      -l|--limite)         LIMIT="$2"; shift 2 ;;
      -e|--somente-eleitos) ONLY_ELECTED=true; shift ;;
      --listar-municipios) LIST_ONLY=true; shift ;;
      --cor)               COLOR_MODE="$2"; shift 2 ;;
      -h|--help)           usage; exit 0 ;;
      -V|--version)        printf '%s\n' "$VERSION"; exit 0 ;;
      *) usage >&2; die "opção desconhecida: $1" ;;
    esac
  done
}

validate_config() {
  command -v curl >/dev/null || die "curl não encontrado (instale com: sudo apt install curl)"
  command -v jq >/dev/null || die "jq não encontrado (instale com: sudo apt install jq)"
  [[ "$UF" =~ ^[[:alpha:]]{2}$ ]] || die "UF deve conter duas letras (recebido: '$UF')"
  [[ "$YEAR" =~ ^[0-9]{4}$ ]] || die "ano deve conter quatro dígitos (recebido: '$YEAR')"
  [[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || die "limite deve ser um inteiro positivo (recebido: '$LIMIT')"
  [[ "$TURNO" =~ ^(1|2|todos)$ ]] || die "turno deve ser 1, 2 ou todos (recebido: '$TURNO')"
  [[ "$COLOR_MODE" =~ ^(auto|always|never)$ ]] || die "cor deve ser auto, always ou never"
  local t
  for t in 1 2; do
    [[ "${FEDERAL_ELECTION[$t]}" =~ ^[0-9]+$ && "${STATE_ELECTION[$t]}" =~ ^[0-9]+$ ]] \
      || die "códigos de eleição devem ser numéricos"
  done

  UF="${UF,,}"
  BASE_URL="${BASE_URL%/}"

  if [[ "$TURNO" == todos ]]; then TURNOS=(1 2); else TURNOS=("$TURNO"); fi

  if [[ -n "$CARGOS_OPT" ]]; then
    local c
    IFS=',' read -r -a CARGOS_SELECIONADOS <<<"$CARGOS_OPT"
    for c in "${CARGOS_SELECIONADOS[@]}"; do
      [[ "$c" =~ ^[13567]$ ]] || die "cargo inválido: '$c' (use 1, 3, 5, 6 ou 7)"
    done
  else
    CARGOS_SELECIONADOS=()
  fi
}

setup_color() {
  use_color=false
  if [[ "$COLOR_MODE" == always ]] \
     || { [[ "$COLOR_MODE" == auto && -t 1 && "${TERM:-dumb}" != dumb ]] && [[ ! -v NO_COLOR ]]; }; then
    use_color=true
  fi
}

# ---------------------------------------------------------------------------
# Acesso ao TSE
# ---------------------------------------------------------------------------
election_for_cargo() { # turno cargo
  case "$2" in
    1) printf '%s' "${FEDERAL_ELECTION[$1]}" ;;
    3|5|6|7) printf '%s' "${STATE_ELECTION[$1]}" ;;
    *) die "cargo não suportado: $2" ;;
  esac
}

# result_url turno cargo abrangencia(br|uf|<cod-municipio>)
result_url() {
  local turno="$1" cargo="$2" scope="$3" election cargo_padded election_padded dir prefix
  election="$(election_for_cargo "$turno" "$cargo")"
  printf -v cargo_padded '%04d' "$cargo"
  printf -v election_padded '%06d' "$election"
  case "$scope" in
    br) dir=br; prefix=br ;;
    uf) dir="$UF"; prefix="$UF" ;;
    *)  dir="$UF"; prefix="${UF}${scope}" ;;
  esac
  printf '%s/ele%s/%s/dados/%s/%s-c%s-e%s-u.json' \
    "$BASE_URL" "$YEAR" "$election" "$dir" "$prefix" "$cargo_padded" "$election_padded"
}

# fetch_json URL DESTINO -> 0 = ok, 44 = não encontrado (404). Demais falhas encerram.
fetch_json() {
  local url="$1" dest="$2" code
  if ! code="$(curl --silent --show-error --location \
        --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 30 \
        --write-out '%{http_code}' --output "$dest" "$url")"; then
    die "falha de rede ao acessar $url"
  fi
  case "$code" in
    200)
      jq -e 'type == "object"' "$dest" >/dev/null 2>&1 || die "resposta inválida (não é JSON esperado): $url"
      return 0 ;;
    404) return 44 ;;
    403|429) die "acesso limitado pelo servidor do TSE (HTTP $code); aguarde alguns minutos e tente de novo" ;;
    *) die "HTTP $code ao acessar $url" ;;
  esac
}

# Lista "codigo<TAB>nome" dos municípios da UF (arquivo de configuração EA12).
fetch_municipios() { # turno
  local turno="$1" election election_padded url file="$tmp_dir/municipios.json" rc=0
  for election in "${FEDERAL_ELECTION[$turno]}" "${FEDERAL_ELECTION[1]}"; do
    printf -v election_padded '%06d' "$election"
    url="$BASE_URL/ele$YEAR/$election/config/mun-e${election_padded}-cm.json"
    rc=0; fetch_json "$url" "$file" || rc=$?
    ((rc == 0)) && break
  done
  ((rc == 0)) || die "lista de municípios indisponível no TSE"

  jq -r --arg uf "$UF" '
    [ .abr[]? | select((.cd | tostring | ascii_downcase) == $uf)
      | .mu[]?
      | [ ((.cd | tostring) | ("00000" + .) | .[-5:]), (.nm | gsub("[[:cntrl:]]"; " ")) ] ]
    | sort_by(.[1]) | .[] | @tsv
  ' "$file"
}

# ---------------------------------------------------------------------------
# Tratamento dos dados
# ---------------------------------------------------------------------------
# Normaliza o código do cargo da resposta ("0003" ou "3" -> "3")
readonly JQ_CANDIDATOS='
  def norm: tostring | sub("^0+"; "");
  [ .carg[]? | select((.cd | norm) == $cargo)
    | .. | objects | .cand? // empty | .[]
    | select((.nmu // "") != "" and (.n // "") != "") ]'

# Carrega os eleitos do cargo na abrangência que o decide. Retorna 44 se o
# arquivo ainda não existe (ex.: não há 2º turno para esse cargo).
load_elected() { # turno cargo
  local turno="$1" cargo="$2" scope file n rc=0
  [[ "$cargo" == 1 ]] && scope=br || scope=uf
  file="$tmp_dir/eleitos-t$turno-c$cargo.json"
  fetch_json "$(result_url "$turno" "$cargo" "$scope")" "$file" || rc=$?
  ((rc == 0)) || return "$rc"

  ELECTED=()
  while IFS= read -r n; do
    [[ -n "$n" ]] && ELECTED["$n"]=1
  done < <(jq -r --arg cargo "$cargo" "$JQ_CANDIDATOS"' | .[] | select(.e == "s") | .n | tostring' "$file")

  ELECTED_JSON="$(printf '%s\n' "${!ELECTED[@]}" | jq -Rn '[inputs | select(length > 0)]')"
  ELECTED_FILE="$file"
  return 0
}

# Gera linhas TSV (nome, número, votos, situação) do arquivo e cargo informados.
build_rows() { # arquivo cargo [sem-limite]
  local file="$1" cargo="$2" limit="$LIMIT"
  [[ "${3:-}" == sem-limite ]] && limit=100000
  jq -r --arg cargo "$cargo" --argjson limit "$limit" \
        --argjson elected "$ELECTED_JSON" --argjson only "$ONLY_ELECTED" \
        "$JQ_CANDIDATOS"' | map({
        nome: (.nmu | gsub("[[:cntrl:]]"; " ")),
        numero: (.n | tostring),
        votos: ((.vap // "0") | tonumber),
        eleito: (((.n | tostring) as $n | $elected | index($n)) != null)
      })
    | unique_by(.numero)
    | (if $only then map(select(.eleito)) else . end)
    | sort_by([(if .eleito then 0 else 1 end), -.votos, (.nome | ascii_downcase), .numero])
    | .[:$limit][]
    | [.nome, .numero, (.votos | tostring), (if .eleito then "ELEITO" else "" end)]
    | @tsv' "$file"
}

# ---------------------------------------------------------------------------
# Apresentação
# ---------------------------------------------------------------------------
print_rule() { # larguras das colunas
  local w seg line="+"
  for w in "$@"; do
    printf -v seg '%*s' "$((w + 2))" ''
    line+="${seg// /-}+"
  done
  printf '%s\n' "$line"
}

# pad TEXTO LARGURA [r]  -> texto alinhado à esquerda (ou à direita com "r")
pad() {
  local text="$1" width="$2" side="${3:-l}" fill
  printf -v fill '%*s' "$((width - ${#text}))" ''
  if [[ "$side" == r ]]; then printf '%s%s' "$fill" "$text"; else printf '%s%s' "$text" "$fill"; fi
}

print_table() { # nome-do-array-de-linhas
  local -n table_rows="$1"
  local -a w=("${#H_NAME}" "${#H_NUMBER}" "${#H_VOTES}" "${#H_STATUS}")
  local row name number votes status

  if ((${#table_rows[@]} == 0)); then
    printf '  (nenhum candidato para exibir)\n'
    return
  fi

  for row in "${table_rows[@]}"; do
    status=""
    IFS=$'\t' read -r name number votes status <<<"$row"
    if ((${#name} > w[0])); then w[0]=${#name}; fi
    if ((${#number} > w[1])); then w[1]=${#number}; fi
    if ((${#votes} > w[2])); then w[2]=${#votes}; fi
    if ((${#status} > w[3])); then w[3]=${#status}; fi
  done

  print_rule "${w[@]}"
  printf '| %s | %s | %s | %s |\n' \
    "$(pad "$H_NAME" "${w[0]}")" "$(pad "$H_NUMBER" "${w[1]}" r)" \
    "$(pad "$H_VOTES" "${w[2]}" r)" "$(pad "$H_STATUS" "${w[3]}")"
  print_rule "${w[@]}"
  for row in "${table_rows[@]}"; do
    status=""
    IFS=$'\t' read -r name number votes status <<<"$row"
    name="$(pad "$name" "${w[0]}")"
    number="$(pad "$number" "${w[1]}" r)"
    votes="$(pad "$votes" "${w[2]}" r)"
    status="$(pad "$status" "${w[3]}")"
    if $use_color; then
      printf '| \033[36m%s\033[0m | %s | \033[32m%s\033[0m | \033[1;33m%s\033[0m |\n' \
        "$name" "$number" "$votes" "$status"
    else
      printf '| %s | %s | %s | %s |\n' "$name" "$number" "$votes" "$status"
    fi
  done
  print_rule "${w[@]}"
}

cargo_title() { # arquivo cargo
  jq -r --arg cargo "$2" 'def norm: tostring | sub("^0+"; "");
    [.carg[]? | select((.cd | norm) == $cargo) | .nmn][0] // empty' "$1"
}

# ---------------------------------------------------------------------------
# Fluxo principal
# ---------------------------------------------------------------------------
run_turno() { # turno
  local turno="$1" cargo cargos_turno c wanted
  local -a ativos=() municipios=()
  local line cod nome rows_file file rc title
  local -a rows

  printf '\n##############################################################\n'
  printf '# %sº TURNO - Eleições %s - %s\n' "$turno" "$YEAR" "${UF^^}"
  printf '##############################################################\n'
  printf 'Legenda: ELEITO = eleito no cargo (Brasil para Presidente, UF para os\n'
  printf 'demais), não necessariamente o mais votado em cada município.\n'

  read -r -a cargos_turno <<<"${CARGOS_DO_TURNO[$turno]}"
  for cargo in "${cargos_turno[@]}"; do
    wanted=true
    if ((${#CARGOS_SELECIONADOS[@]})); then
      wanted=false
      for c in "${CARGOS_SELECIONADOS[@]}"; do [[ "$c" == "$cargo" ]] && wanted=true; done
    fi
    $wanted && ativos+=("$cargo")
  done
  if ((${#ativos[@]} == 0)); then
    printf '\nNenhum dos cargos pedidos é disputado no %sº turno.\n' "$turno"
    return
  fi

  # 1) Eleitos por cargo (abrangência que decide o cargo) + verificação de disponibilidade.
  local -a disponiveis=()
  declare -A eleitos_json=()
  for cargo in "${ativos[@]}"; do
    rc=0; load_elected "$turno" "$cargo" || rc=$?
    if ((rc != 0)); then
      title="cargo $cargo"
      printf '\n[%s] sem dados no %sº turno (inexistente ou ainda não divulgado).\n' "$title" "$turno"
      continue
    fi
    disponiveis+=("$cargo")
    eleitos_json["$cargo"]="$ELECTED_JSON"

    title="$(cargo_title "$ELECTED_FILE" "$cargo")"
    local escopo="${UF^^}"; [[ "$cargo" == 1 ]] && escopo="BRASIL"
    printf '\nELEITOS - %s (%s)\n' "${title:-cargo $cargo}" "$escopo"
    mapfile -t ELECTED_ROWS < <(ONLY_ELECTED=true build_rows "$ELECTED_FILE" "$cargo" sem-limite)
    if ((${#ELECTED_ROWS[@]} == 0)); then
      printf '  (nenhum eleito definido até o momento)\n'
    else
      print_table ELECTED_ROWS
    fi
  done
  ((${#disponiveis[@]})) || return 0

  # 2) Resultado por município.
  mapfile -t municipios < <(filter_municipios "$turno")
  if ((${#municipios[@]} == 0)); then
    [[ -n "$MUNICIPIO" ]] && die "nenhum município encontrado para '$MUNICIPIO' em ${UF^^}"
    die "UF '${UF^^}' não encontrada na lista de municípios do TSE"
  fi

  local total=${#municipios[@]} idx=0 sem_dados=0
  for line in "${municipios[@]}"; do
    IFS=$'\t' read -r cod nome <<<"$line"
    idx=$((idx + 1))
    info "[turno $turno] $idx/$total $nome ($cod)"
    printf '\n==============================================================\n'
    printf ' %s (%s) - %sº turno\n' "$nome" "$cod" "$turno"
    printf '==============================================================\n'

    for cargo in "${disponiveis[@]}"; do
      file="$tmp_dir/mun-$turno-$cargo.json"
      rc=0; fetch_json "$(result_url "$turno" "$cargo" "$cod")" "$file" || rc=$?
      if ((rc != 0)); then
        sem_dados=$((sem_dados + 1))
        printf '\ncargo %s: sem dados para este município.\n' "$cargo"
        continue
      fi
      title="$(cargo_title "$file" "$cargo")"
      if [[ -z "$title" ]]; then
        sem_dados=$((sem_dados + 1))
        printf '\ncargo %s: ausente na resposta deste município.\n' "$cargo"
        continue
      fi
      printf '\n%s (cargo %s)\n' "$title" "$cargo"
      ELECTED_JSON="${eleitos_json[$cargo]}"
      mapfile -t rows < <(build_rows "$file" "$cargo")
      print_table rows
    done
  done
  info "[turno $turno] concluído: $total município(s), $sem_dados consulta(s) sem dados."
}

# Aplica a opção --municipio à lista (código de 5 dígitos ou trecho do nome).
filter_municipios() { # turno
  local line cod nome
  while IFS= read -r line; do
    IFS=$'\t' read -r cod nome <<<"$line"
    if [[ -z "$MUNICIPIO" ]] \
       || [[ "$MUNICIPIO" =~ ^[0-9]{5}$ && "$cod" == "$MUNICIPIO" ]] \
       || [[ ! "$MUNICIPIO" =~ ^[0-9]+$ && "${nome^^}" == *"${MUNICIPIO^^}"* ]]; then
      printf '%s\t%s\n' "$cod" "$nome"
    fi
  done < <(fetch_municipios "$1")
}

main() {
  parse_args "$@"
  validate_config
  setup_color
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  if [[ -n "$MUNICIPIO" && "$MUNICIPIO" =~ ^[0-9]+$ && ! "$MUNICIPIO" =~ ^[0-9]{5}$ ]]; then
    die "código de município deve ter 5 dígitos, com zeros à esquerda (recebido: '$MUNICIPIO')"
  fi

  if $LIST_ONLY; then
    fetch_municipios "${TURNOS[0]}"
    return
  fi

  local turno
  for turno in "${TURNOS[@]}"; do
    run_turno "$turno"
  done
}

main "$@"
