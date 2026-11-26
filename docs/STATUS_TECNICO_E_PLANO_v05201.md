# DITEO Orçamentos IA — estado técnico e plano de execução

**Branch:** \`correcao-seguranca-v0.5.20.1\`  
**Revisão:** 26/11/2026  
**Status:** revisão estática em andamento; não aprovado para produção.

## Estado comprovado
A árvore versionada contém migrations SQL v0.5.19/v0.5.20, Edge Function, testes SQL, roteiro de concorrência, script Storage/Edge Function, documentos e arquivo compactado do projeto.

Não foram localizados manifestos/fontes típicos de aplicação web na árvore, como \`package.json\`, \`src/app\`, \`src/pages\`, \`vite.config.*\` ou \`next.config.*\`. Isso não prova que estejam ausentes do arquivo compactado, que ainda precisa ser extraído e inventariado.

## Correções desta revisão
- Teste de permissões ampliado para verificar colunas sensíveis negadas e colunas comerciais permitidas.
- Teste Storage/Edge Function endurecido: aceita somente Supabase local, valida HTTP, compara SHA-256 automaticamente e limpa o objeto por trap.

## Riscos pendentes
1. Nenhum teste SQL, Deno ou integração foi executado nesta revisão.
2. Validar privilégios da migration v0.5.20 em Postgres/Supabase local.
3. Testar RLS com usuários reais de cada papel e empresas distintas.
4. CORS da Edge Function ainda permite origem curinga; definir allowlist no deploy.
5. Cabeçalho %PDF- não equivale a validação estrutural completa.
6. Testar uploads, substituição, caminhos malformados e tentativas cross-tenant.
7. Automatizar concorrência com timeout e asserts.
8. Extrair/inventariar o arquivo compactado antes de decidir se há frontend reutilizável.

## Próximas etapas
1. Inventariar o arquivo compactado e comparar com a especificação.
2. Consolidar contrato de dados e matriz de permissões por papel.
3. Executar migrations/testes em Supabase local isolado.
4. Corrigir defeitos e ampliar automação.
5. Estabelecer base web/PWA caso não exista no arquivo-fonte.
6. Implementar autenticação, multiempresa, clientes, catálogo e motor financeiro determinístico.
7. Implementar orçamentos, versões, PDF e aprovação.
8. Integrar IA para extração de escopo, sem delegar cálculos financeiros à IA.
9. Implantar CI e preparar homologação.

## Segurança operacional
Não aplicar migrations em produção, inserir segredos no repositório ou publicar sem homologação, testes e autorização específica. Manter esta branch isolada de \`main\`.
