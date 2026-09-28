# AURP Trucker — Sistema de Logística de Caminhões v4.0.0

## O que é

Script completo de caminhoneiro para FiveM com sistema de empresas, economia de indústrias e interface React moderna. Jogadores criam ou entram em empresas de logística, aceitam jobs gerados automaticamente e transportam cargas entre indústrias de diferentes setores.

---

## Funcionalidades Principais

### Sistema de Empresas
- Criar empresa própria ou entrar em empresa recrutando
- Cofre empresarial (depósito / saque por cargo)
- Frota registrada por empresa (até 2 veículos)
- Gestão de membros: kick, controle de recrutamento
- Roles: **Owner** → **Manager** → **Driver**

### Jobs Automáticos
- Jobs gerados a cada ciclo com origem, destino, trailer e carga específicos
- Pagamento por distância + bônus de pontualidade (+20% em 5 min)
- Expiração visual na interface: amarelo (<15 min) → vermelho (<5 min)
- Mais de 40 localizações distribuídas pelo mapa

### Economia de Indústrias
- **Setor Primário** — produz sem insumos (portos, refinarias, fazendas)
- **Setor Secundário** — processa insumos do primário (fábricas, distribuidoras)
- **Setor Terciário** — compra produtos finais (varejistas, atacadistas)
- Preços dinâmicos: sobem com estoque baixo, caem com excesso
- Sistema resistente: NPC garante mínimo de produção sem jogadores

### Progressão e Skill Tree
- XP ganho em cada entrega; 30 níveis com 6 ranks (Aprendiz → Lenda)
- 4 tipos de skill (Distância, Valioso, Frágil, Velocidade), 6 níveis cada
- Cada nível de skill concede +2% de bônus no pagamento (máx +48%)
- Skill points ganhos ao subir de nível; compra via interface React
- Bônus aplicado automaticamente em cada entrega completa

### Interface React
- NUI em React + TypeScript + Tailwind CSS (sem dependência de framework externo)
- 6 abas: **Jobs**, **Entrega Ativa**, **Empresa**, **Garagem**, **Indústrias**, **Estatísticas**
- Aba Estatísticas: nível, rank, barra de XP, grid de stats, skill tree interativa
- Design escuro (zinc palette), responsivo, sem lag de DOM

### Integração
- Exports documentados para outros recursos (sistemas de inspeção, SALA, etc.)
- Callbacks lib.callback para dados on-demand (membros, veículos, indústrias)
- Suporte a integração com sistemas de multa/infração

---

## Stack Técnica

| Componente | Tecnologia |
|---|---|
| Framework | QBX (qbx_core) |
| Banco de dados | oxmysql — 13 tabelas `trucker_*` |
| Inventário | ox_inventory |
| Target | ox_target |
| UI lib | ox_lib |
| Frontend | React 18 + TypeScript 5 + Tailwind CSS 3 + Zustand 4 |
| Build | Vite 5 |

---

## Pronto para Escalar

O schema de banco de dados já inclui tabelas para funcionalidades futuras:
- Certificações ADR para cargas especiais
- Empréstimos empresariais
- Motoristas NPC
- Propriedade de indústrias
- Sistema Repo Man (repossessão de veículos)

---

## Compatibilidade

- **Framework:** QBX (qbx_core) — compatível com servidores QBox
- **OneSync:** Compatível
- **Performance:** 0.00ms idle, <0.05ms ativo

---

## Instalação

1. Copiar pasta para `resources/`
2. Importar `import.sql`
3. Adicionar `ensure AUST_trucker` no `server.cfg`
4. Pronto — tabelas criadas automaticamente no primeiro boot
