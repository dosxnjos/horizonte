#!/usr/bin/env sh
# Varre o que vai ser commitado atrás de segredo ou dado pessoal (roadmap § 3.1).
# Padrões genéricos aqui; termos reais (domínios, nomes) em .segredos-locais, fora do repo.
# Uso: tools/varrer-segredos.sh            -> varre arquivos rastreados + staged
# Sai com 1 se achar algo.
set -eu
cd "$(git rev-parse --show-toplevel)"
# Formas concretas (não o nome do padrão), para a doc que descreve a regra não disparar.
padroes='calendar\.google\.com/calendar/ical/|private-[0-9a-f]{16}|[A-Za-z0-9._%+-]+@gmail\.com|s Organization|[A-Za-z]:\\Users\\[A-Za-z]'
if [ -f .segredos-locais ]; then
  extra=$(grep -v '^[[:space:]]*#' .segredos-locais | grep -v '^[[:space:]]*$' | paste -sd'|' -)
  [ -n "$extra" ] && padroes="$padroes|$extra"
fi
arquivos=$(git ls-files --cached --others --exclude-standard | grep -v '^tools/varrer-segredos.sh$' || true)
[ -z "$arquivos" ] && exit 0
if echo "$arquivos" | tr '\n' '\0' | xargs -0 grep -n -i -E "$padroes" 2>/dev/null; then
  echo "varrer-segredos: achado acima. Nada de commit até limpar." >&2
  exit 1
fi
echo "varrer-segredos: limpo ($(echo "$arquivos" | wc -l | tr -d ' ') arquivos)."
