# horizonte: regras para mexer neste repo

Pacote Rainmeter de widgets (relógio, dia, agenda, máquina, Claude). Visão e fases:
[roadmap](roadmap/2026-10-02-horizonte-visao-e-plano.md). Hub local (fora deste
repo): `C:\Dev\cerebro\projetos\horizonte.md`.

1. **Repo público.** Nunca commitar URL de agenda, e-mail, título real de evento,
   `config.toml`/`*.json` de dados nem caminho com nome de usuário. Rodar
   `tools/varrer-segredos.sh` antes de todo commit (regra: roadmap § 3.1).
2. **Claude: só leitura do `snapshot.json` do claude-usage-tray**, nunca `cswap` nem
   API (segunda engine divide o orçamento por token). Regras visuais do anel: roadmap § 1.
3. **Recorrência de agenda só no helper Python**, nunca em Lua (roadmap § 5).
4. **`.ini`/`.inc` em UTF-16 LE com BOM**; `;` no meio de valor NÃO é comentário no Rainmeter.
5. **`agenda.json` só muda junto com [docs/CONTRATOS.md](docs/CONTRATOS.md)**; `uv run pytest`
   verde antes de commit; armadilhas em [docs/ARMADILHAS.md](docs/ARMADILHAS.md).
