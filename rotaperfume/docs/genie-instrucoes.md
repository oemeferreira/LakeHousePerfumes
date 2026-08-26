# Instruções de Negócio para o Databricks Genie Space

## 1. Contexto da Empresa
**Rota do Perfume** é uma distribuidora B2B de perfumaria árabe importada no Brasil.
Vende para perfumarias, farmácias, lojas de shopping, revendedoras autônomas, e-commerces, salões, lojas de departamento e quiosques.
Período da base de dados: **setembro/2024 a agosto/2026** (24 meses).
Receita total faturada líquida: **R$ 102.303.828,05**.

---

## 2. Regra de Ouro: Sazonalidade Invertida (Varejo Compra Antes)
A distribuidora vende para o varejo, e o varejo abastece o estoque **no mês anterior** à data comemorativa:
* **Abril**: Pico de reposição para o *Dia das Mães* (maio).
* **Junho**: Pico de vendas para o *Dia dos Namorados*.
* **Outubro**: Pico de compras para a *Black Friday* (novembro).
* **Dezembro e Janeiro**: Período de **VALE** (o varejo já está abastecido para as festas e liquidando sobras).
  > **IMPORTANTE**: Queda em dezembro/janeiro é comportamento saudável e esperado do setor, nunca problema de desempenho ou churn operacional.

---

## 3. Glossário
* **Ruptura**: Produto com saldo zero no estoque. Em perfumaria de nicho/árabe, a falta do produto não migra para outro; a venda desaparece.
* **Carteira**: Vínculo entre cliente e vendedor com vigência temporal.
* **Oportunidade**: Negócio no CRM com etapas: *Prospecção*, *Qualificação*, *Proposta enviada*, *Negociação*, *Fechado ganho* e *Fechado perdido*.
* **Devolução**: Produto retornado fisicamente. Registrado na tabela fato com quantidade negativa, receita negativa e flag devolucao = true.
* **SKU**: Código único identificador do produto.
* **Segmento**: Tipo de canal de varejo do cliente (Perfumaria, Farmácia, Shopping, etc.), não a categoria do produto.
* **Curva ABC**: Classificação de produtos onde A representa até 70-80% da receita acumulada, B até 90-95% e C a cauda longa.
* **Cliente em Risco (Churn)**: Cliente sem pedidos há mais de **90 dias**.

---

## 4. Regras de Cálculo
* **Receita Líquida**: SUM(receita) em gold.fato_vendas (já desconta devoluções automaticamente).
* **Receita Bruta**: SUM(receita) FILTER (WHERE NOT devolucao) (apenas quando solicitado sem estornos).
* **Margem Bruta**: SUM(margem) ou 
eceita - custo.
* **Ticket Médio**: SUM(receita) / COUNT(DISTINCT pedido_id).
* **Atingimento de Meta**: 
eceita / meta_mensal * 100.
* **Pedidos Cancelados**: Já foram excluídos da camada Gold. Não é necessário filtrar status novamente.

---

## 5. Onde Consultar
Sempre prefira as views de negócio na camada gold:
1. 
eceita_mensal: Receita, margem e indicadores de pico/vale por mês.
2. 
anking_marcas: Vendas e market share por marca importada.
3. margem_por_categoria: Rentabilidade por categoria de produto (Kit Presente x Óleo Concentrado).
4. clientes_em_risco: Clientes inativos há > 90 dias e impacto financeiro mensal.
5. efeito_lancamento: Performance dos produtos nos 120 dias pós-lançamento.
6. 
uptura_por_marca: Frequência de indisponibilidade de estoque por marca.
