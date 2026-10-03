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
# Arquivos do skin\ ficam em UTF-16 LE com BOM na working tree: o grep direto não enxerga
# nada neles (cada letra vem colada a um byte zero). Esses passam por iconv antes.
achados=$(echo "$arquivos" | while IFS= read -r f; do
  [ -f "$f" ] || continue
  if [ "$(head -c 2 "$f" | od -An -tx1 | tr -d ' \n')" = "fffe" ]; then
    iconv -f UTF-16 -t UTF-8 "$f" 2>/dev/null | grep -n -i -E "$padroes" | sed "s|^|$f (utf-16):|"
  else
    grep -n -i -E "$padroes" "$f" /dev/null 2>/dev/null
  fi
done || true)
if [ -n "$achados" ]; then
  echo "$achados"
  echo "varrer-segredos: achado acima. Nada de commit até limpar." >&2
  exit 1
fi
echo "varrer-segredos: limpo ($(echo "$arquivos" | wc -l | tr -d ' ') arquivos)."
