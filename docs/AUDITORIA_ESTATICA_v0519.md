# Auditoria estática preliminar — DITEO Orçamentos IA v0.5.19

## Escopo e limitações

Auditoria baseada exclusivamente no arquivo original `Texto colado(10).txt` enviado nesta conversa. O repositório GitHub `Diteohub/DITEO-Or-amentos-IA.` foi consultado e retornou público, branch `main`, tamanho 0 KB. Portanto, não há código remoto para comparar.

Esta é uma revisão estática do material. Não foi possível executar a migration, os testes SQL, a Edge Function ou o teste de Storage: neste ambiente não foram encontrados `psql`, `supabase` CLI ou `deno`, e não foi fornecida uma instância Supabase de teste. Nenhum teste deve ser considerado aprovado.

## Achados que bloqueiam aprovação

### 1. Dados internos de custo e margem acessíveis a todos os membros
**Severidade: alta — confidencialidade**

As políticas `quotes_select` e `versions_select` permitem SELECT a qualquer membro ativo da empresa. Entretanto, `quotes` contém `total_cost`, `estimated_profit`, taxas e margem aplicada; `quote_versions.snapshot` também inclui custos unitários/totais e lucro estimado. Assim, perfis `viewer`, `technician` e `sales` podem ler dados internos que podem não fazer parte de suas permissões comerciais.

**Correção recomendada:** definir matriz de acesso por campo/perfil. Não confiar apenas em ocultar campos na interface. Usar views/RPCs com projeção segura para perfis sem permissão e restringir leitura direta das tabelas sensíveis. Rever também acesso ao JSON `snapshot`.

### 2. GRANTs sem políticas RLS correspondentes
**Severidade: alta — funcionalidade e consistência de autorização**

O SQL concede `UPDATE, DELETE` em `catalog_items` e `price_history`, mas não cria políticas RLS de DELETE para `catalog_items`, nem políticas de UPDATE/DELETE para `price_history`. Com RLS habilitado, essas operações ficam bloqueadas apesar dos GRANTs. A matriz de permissões declara operações que a migration não implementa.

**Correção recomendada:** decidir explicitamente quais papéis podem atualizar/excluir esses registros e criar políticas alinhadas; alternativamente remover os GRANTs não utilizados. Atualizar a matriz e os testes para verificar efetivamente GRANT + RLS, não apenas presença de políticas.

### 3. Teste 9 não cobre a matriz anunciada
**Severidade: média/alta — falsa confiança de segurança**

O Teste 9 verifica RLS e presença de políticas SELECT nas 13 tabelas, e verifica algumas políticas de escrita em `customers` e `suppliers`. Não verifica as permissões efetivas de `catalog_items` e `price_history`, nem compara `information_schema`/`pg_catalog` com a matriz de GRANTs. Portanto, pode passar mesmo com as lacunas apontadas no item 2.

**Correção recomendada:** ampliar os testes para cada tabela/operação/papel, incluindo tentativas reais sob `SET ROLE authenticated` e claims JWT, além da conferência de privilégios.

### 4. Teste de Storage não é automatizado nem autoverificável
**Severidade: média — evidência insuficiente**

O script faz upload, chama a Edge Function e imprime a resposta, mas não compara automaticamente `verified_sha256` com `LOCAL_SHA256`, não falha quando a resposta HTTP contém erro e não garante limpeza em caso de falha. A própria instrução pede conferência manual.

**Correção recomendada:** usar `set -euo pipefail`, validar códigos HTTP e JSON, comparar o hash com `jq`, e usar trap para limpeza. Executar contra projeto Supabase isolado.

### 5. Edge Function: tratamento e robustez operacional
**Severidade: média**

A função valida JWT com `auth.getUser()` e revalida associação na RPC privilegiada — isso é um bom controle. Porém, o `catch` externo descarta a causa, as respostas de erro e sucesso incluem os headers CORS definidos, mas a função baixa o arquivo inteiro antes de verificar o tamanho, permitindo alocação de memória acima do limite declarado. O limite de 10 MB é verificado somente depois de `arrayBuffer()`.

**Correção recomendada:** limitar o tamanho antes/durante a leitura quando possível, validar `Content-Length` como defesa adicional, impor limite real de bytes no stream, registrar erro internamente sem expor segredos e testar métodos/headers CORS.

### 6. Testes de concorrência são procedimento manual, não teste automatizado
**Severidade: média**

O documento descreve corretamente duas conexões independentes e inspeção de `pg_stat_activity`, mas não automatiza a execução nem coleta evidência. A verificação de ausência de deadlocks por leitura de contador global não prova, isoladamente, que a operação testada não sofreu deadlock.

**Correção recomendada:** transformar o roteiro em teste de integração reproduzível, capturando bloqueio, resultado final e timeout controlado.

## Pontos positivos observados

- Uso consistente de `SECURITY DEFINER SET search_path = ''` nas funções apresentadas.
- RPCs de escrita para operações críticas, com validação de papel e escopo da empresa.
- Chaves estrangeiras compostas com `company_id` em entidades comerciais, reduzindo risco de referências cruzadas entre empresas.
- A confirmação do PDF usa usuário obtido de JWT validado e revalida o vínculo do usuário dentro da RPC.
- O hash SHA-256 é calculado sobre os bytes baixados do Storage, não aceito diretamente do cliente.
- O snapshot canônico é comparado antes da transição para `sent`.

## Observações adicionais para a próxima revisão

- A migration cria triggers e policies sem `DROP ... IF EXISTS`; é adequada para execução única em banco limpo, mas não é rerun-safe. Não executar novamente sobre um banco já migrado sem plano de migração.
- O teste SQL insere diretamente em `auth.users`; a compatibilidade precisa ser confirmada na versão real do Supabase Auth usada no projeto.
- A política `storage_proposals_insert` depende de caminho com UUID na primeira pasta e de uma versão `pending`; testar nomes malformados, tentativas cross-tenant e substituição de objetos.
- A checagem de PDF valida apenas o cabeçalho `%PDF-`; isso confirma assinatura inicial, não integridade estrutural completa do documento.
- A regra financeira deve ser validada contra decisões de produto: o SQL calcula preço por `custo / (1 - margem - imposto - comissão)` e calcula lucro líquido descontando imposto e comissão. Confirmar se a taxa de imposto usada por empresa é compatível com o enquadramento tributário real; não assumir 6% como valor universal.
- Confirmar se o papel `sales` pode visualizar custo, margem e lucro, ou se esses dados devem ficar restritos a owner/admin/manager.

## Status da versão

**Não aprovada para produção.** O material está organizado, mas os achados de confidencialidade, RLS/GRANT e cobertura dos testes precisam ser resolvidos. Não houve execução de testes nem validação em Supabase.

## Estrutura preparada

- `supabase/migrations/20261126000100_migration_v0519.sql`
- `supabase/functions/confirm-proposal-pdf/index.ts`
- `tests/security/v0519_security_tests.sql`
- `tests/integration/storage_sha256_edge_function.sh`
- `tests/integration/procedimento_concorrencia.md`
- `docs/matriz_permissoes_v0519.txt`

Os arquivos de código foram separados do texto original, mas preservados sem correções funcionais nesta primeira organização. A migration ainda precisa de revisão e correção antes de ser aplicada.
