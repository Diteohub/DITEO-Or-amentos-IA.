# Avaliação do protótipo Python — aproveitamento no DITEO Orçamentos IA

**Data:** 26/11/2026  
**Origem:** código Python/SQLite + HTML/JavaScript compartilhado na conversa.  
**Decisão:** usar como referência funcional e de UX; não substituir a arquitetura Next.js + Supabase.

## 1. Funcionalidades demonstradas pelo protótipo

- Cadastro de empresa e usuário; login/logout.
- Cadastro, edição e exclusão de clientes.
- Cadastro, edição e exclusão de itens de catálogo com unidade, custo e preço.
- Criação e edição de orçamentos, seleção de cliente e itens do catálogo ou avulsos.
- Quantidade, preço, custo, desconto percentual e taxa percentual.
- Cálculo de subtotal, desconto, taxa, total, custo e lucro estimado.
- Status: rascunho, pendente, aprovado, recusado e pago.
- Painel com contagem e totais por status, custos e lucro estimado.
- Visualização e download de PDF.
- Interface responsiva e acesso na rede local.

## 2. Fluxo funcional a preservar

Empresa → Clientes → Catálogo → Orçamento → Itens e condições → Cálculo → Revisão/PDF → Atualização de status → Painel.

A interface deve priorizar esse fluxo simples. O protótipo é uma referência de comportamento, não uma especificação completa de produto.

## 3. Regras e limitações identificadas no código

- O cálculo usa ponto flutuante binário (float/Number), inadequado como motor financeiro definitivo. Implementar cálculo decimal determinístico e testes de arredondamento.
- O lucro é calculado como subtotal após desconto menos custo; não considera comissão, impostos como despesa, taxas financeiras, custos indiretos ou demais componentes. Definir fórmula configurável e mostrar claramente o significado de cada indicador.
- A taxa é aplicada como percentual simples sobre a base após desconto; não há gross-up tributário. Não transportar essa fórmula sem validação de produto/contabilidade.
- O painel soma orçamentos aprovados e pagos em “Cobrado”, embora aprovado não signifique recebido. Separar contratado/aprovado, faturado e efetivamente recebido.
- O status é alterado diretamente; faltam trilha de auditoria, regras de transição, permissões e registro de quem/quando.
- Não há versões imutáveis nem snapshots históricos do orçamento.
- O PDF é básico, sem identidade visual configurável, assinatura, condições comerciais estruturadas ou controle de versão.
- O protótipo permite somente uma empresa por usuário e não implementa convites, associação de múltiplas empresas ou papéis.
- Cadastro é aberto e a senha mínima é de seis caracteres; isso não atende ao padrão de segurança desejado.

## 4. Riscos técnicos e de segurança do protótipo

- Sessões guardadas em memória: reinício encerra sessões; não há expiração/rotação persistida.
- Cookie de sessão sem atributo Secure e sem expiração explícita.
- Servidor escuta em 0.0.0.0 por padrão e não oferece TLS; inadequado para exposição pública.
- Sem proteção robusta contra força bruta, abuso de cadastro e automação.
- Sem matriz de autorização por função.
- SQLite local e arquivo de banco ao lado do script: sem operação multi-instância, backup gerenciado ou armazenamento central.
- Sem testes automatizados de autenticação, isolamento entre empresas, concorrência, cálculos e PDF.
- Uso de float em cálculos e persistência.
- Não há controle de anexos, armazenamento seguro ou histórico de alterações.

## 5. Mapeamento para a arquitetura oficial

| Área | Referência do protótipo | Implementação definitiva |
|---|---|---|
| Empresa/usuários | companies/users | Supabase Auth + companies + company_members + RLS |
| Clientes | clients | customers com isolamento por empresa |
| Catálogo | items | catalog_items + fornecedores + histórico de preços |
| Orçamentos | quotes/lines | quotes + quote_items + quote_versions |
| Cálculos | calc()/cj() | motor decimal determinístico, configurável e testado |
| PDF | make_pdf()/quote_pdf() | geração server-side a partir de snapshot imutável |
| Painel | painel() | indicadores com semântica financeira correta |
| Status | STATUS/setSt() | workflow com permissões e audit_logs |
| Sessão | SESS/cookie | Supabase Auth, sessão segura e políticas RLS |

## 6. Requisitos de aceitação derivados

1. Usuário autenticado só acessa empresas às quais pertence.
2. Dados de clientes, catálogo, orçamentos e arquivos permanecem isolados entre empresas.
3. Catálogo permite reutilizar itens e registrar custos internos sem expô-los a papéis não autorizados.
4. Orçamento aceita itens de catálogo e itens avulsos, com quantidade, unidade, preço e custo.
5. Motor financeiro usa decimal, configuração por empresa e regras explícitas para desconto, tributos, comissão, margem e arredondamento.
6. PDF do cliente não contém custos, margens, lucro ou taxas internas.
7. Cada emissão gera versão/snapshot imutável, com hash do PDF e trilha de auditoria.
8. Painel distingue valores propostos, aprovados/contratados, faturados e recebidos.
9. Mudanças de status obedecem a papéis e transições permitidas.
10. Fluxo completo coberto por testes: login → cliente → catálogo → orçamento → cálculo → salvar/reabrir → PDF → permissões/isolamento.

## 7. Decisões

- Preservar a simplicidade do fluxo e os elementos úteis da interface.
- Não copiar a implementação de autenticação, sessão, persistência, cálculos ou PDF do protótipo.
- Não usar valores fiscais padrão do protótipo como configuração real.
- Não considerar o protótipo como evidência de que a aplicação oficial já está implementada.
- Validar o arquivo compactado do repositório separadamente; este documento não comprova seu conteúdo.

## 8. Próxima execução técnica

1. Inventariar o arquivo compactado do repositório para localizar eventual frontend já existente.
2. Comparar os fluxos do protótipo com os schemas/RPCs já versionados.
3. Executar migrations e testes em ambiente local isolado antes de ampliar a aplicação.
4. Converter os requisitos de aceitação acima em testes e tarefas incrementais.