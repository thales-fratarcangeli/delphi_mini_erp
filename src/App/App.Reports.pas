{*******************************************************************************
  App.Reports

  Relatorios: agregacao, agrupamento e ordenacao de dados em memoria.

  ESTUDO - conceitos demonstrados aqui:
    * TDictionary<K,V> para agrupar (o "GROUP BY" feito na unha)
    * Registros como acumuladores
    * TArray.Sort<T> com TComparer<T>.Construct e metodo anonimo
    * Curva ABC (regra de Pareto): ordenar + acumular percentual
    * Relatorios devolvem TArray<string> em vez de escrever na tela:
      isso os torna TESTAVEIS e reutilizaveis (console, arquivo, e-mail...)
*******************************************************************************}
unit App.Reports;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Core.Types,
  Domain.Entities,
  Domain.Enums,
  Domain.Interfaces,
  Domain.Producao,
  Domain.Producao.Services,
  Domain.Specifications,
  App.Bootstrap;

type
  TLinhaRanking = record
    Chave: string;
    Descricao: string;
    Quantidade: Integer;
    Valor: Currency;
  end;

  TRelatorios = class
  private
    FApp: TAplicacao;
    function Regua(const ATitulo: string): TArray<string>;
    /// Agrupa os itens de todos os pedidos "que valem" (nao cancelados/rascunho).
    function AgregarProdutosVendidos: TArray<TLinhaRanking>;
  public
    constructor Create(AApp: TAplicacao);

    function PosicaoDeEstoque: TArray<string>;
    function VendasPorStatus: TArray<string>;
    function TopProdutos(AQuantidade: Integer = 5): TArray<string>;
    function ClientesPorCategoria: TArray<string>;
    function CurvaABC: TArray<string>;
    function ExtratoMovimentos(AUltimos: Integer = 20): TArray<string>;
    function PainelGeral: TArray<string>;

    // ------------------------------- PCP -------------------------------
    /// Arvore de materiais de um item, nivel a nivel.
    function EstruturaExplodida(AProdutoId: Integer;
      AQuantidade: Double = 1): TArray<string>;
    /// Necessidade de compra consolidada (so itens comprados).
    function NecessidadeDeMateriais(AProdutoId: Integer;
      AQuantidade: Double): TArray<string>;
    /// Ficha de custo: material + transformacao do produto fabricado.
    function FichaDeCusto(AProdutoId: Integer): TArray<string>;
    function OrdensAbertas: TArray<string>;
    function CargaDeTrabalho: TArray<string>;
    /// Previsto x realizado das ordens ja concluidas.
    function EficienciaDeProducao: TArray<string>;
    function DetalheDaOrdem(AOrdemId: Integer): TArray<string>;
  end;

implementation

/// Sigla curta do tipo, para caber nas colunas dos relatorios.
function SiglaTipo(ATipo: TTipoProduto): string;
begin
  case ATipo of
    tpMateriaPrima:  Result := 'MP';
    tpIntermediario: Result := 'SEMI';
    tpAcabado:       Result := 'PA';
    tpConsumo:       Result := 'CONS';
    tpRevenda:       Result := 'REV';
  else
    Result := '?';
  end;
end;

{ TRelatorios }

constructor TRelatorios.Create(AApp: TAplicacao);
begin
  inherited Create;
  FApp := AApp;
end;

function TRelatorios.Regua(const ATitulo: string): TArray<string>;
begin
  Result := TArray<string>.Create(
    '',
    '=== ' + ATitulo + ' ' + StringOfChar('=', Max(3, 66 - Length(ATitulo))),
    '');
end;

function TRelatorios.PosicaoDeEstoque: TArray<string>;
var
  LLinhas: TList<string>;
  LProduto: TProduto;
  LTotal: Currency;
  LAlerta: string;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua('POSICAO DE ESTOQUE'));
    LLinhas.Add(Format('%-10s %-32s %8s %8s %14s',
      ['CODIGO', 'DESCRICAO', 'SALDO', 'MINIMO', 'VALOR']));
    LLinhas.Add(StringOfChar('-', 76));

    LTotal := 0;
    for LProduto in FApp.Produtos.Todos do
    begin
      if LProduto.EmFalta then
        LAlerta := ' <== SEM ESTOQUE'
      else if LProduto.AbaixoDoMinimo then
        LAlerta := ' <== REPOR'
      else
        LAlerta := '';

      LLinhas.Add(Format('%-10s %-32s %8d %8d %14s%s',
        [LProduto.Codigo, Copy(LProduto.Descricao, 1, 32), LProduto.Estoque,
         LProduto.EstoqueMinimo, TFmt.Moeda(LProduto.ValorEmEstoque), LAlerta]));
      LTotal := LTotal + LProduto.ValorEmEstoque;
    end;

    LLinhas.Add(StringOfChar('-', 76));
    LLinhas.Add(Format('%-60s %14s', ['TOTAL IMOBILIZADO EM ESTOQUE', TFmt.Moeda(LTotal)]));
    LLinhas.Add(Format('Itens abaixo do minimo: %d', [Length(FApp.Produtos.AbaixoDoMinimo)]));
    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.VendasPorStatus: TArray<string>;
var
  LLinhas: TList<string>;
  LStatus: TStatusPedido;
  LPedido: TPedido;
  LQtd: Integer;
  LValor, LTotalGeral: Currency;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua('PEDIDOS POR STATUS'));
    LLinhas.Add(Format('%-14s %10s %18s', ['STATUS', 'PEDIDOS', 'VALOR']));
    LLinhas.Add(StringOfChar('-', 44));

    LTotalGeral := 0;
    for LStatus := Low(TStatusPedido) to High(TStatusPedido) do
    begin
      LQtd := 0;
      LValor := 0;
      for LPedido in FApp.Pedidos.Todos do
        if LPedido.Status = LStatus then
        begin
          Inc(LQtd);
          LValor := LValor + LPedido.TotalLiquido;
        end;

      if LQtd = 0 then
        Continue;

      LLinhas.Add(Format('%-14s %10d %18s',
        [StatusPedidoDescr(LStatus), LQtd, TFmt.Moeda(LValor)]));

      // Faturamento "de verdade" = o que nao foi cancelado nem e rascunho
      if not (LStatus in [spRascunho, spCancelado]) then
        LTotalGeral := LTotalGeral + LValor;
    end;

    LLinhas.Add(StringOfChar('-', 44));
    LLinhas.Add(Format('%-14s %10s %18s',
      ['FATURAMENTO', '', TFmt.Moeda(LTotalGeral)]));
    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.AgregarProdutosVendidos: TArray<TLinhaRanking>;
var
  LMapa: TDictionary<Integer, TLinhaRanking>;
  LPedido: TPedido;
  LItem: TItemPedido;
  LLinha: TLinhaRanking;
begin
  LMapa := TDictionary<Integer, TLinhaRanking>.Create;
  try
    for LPedido in FApp.Pedidos.Todos do
    begin
      // Rascunho ainda nao vendeu; cancelado nao conta como venda.
      if LPedido.Status in [spRascunho, spCancelado] then
        Continue;

      for LItem in LPedido.Itens do
      begin
        if not LMapa.TryGetValue(LItem.ProdutoId, LLinha) then
        begin
          LLinha := Default(TLinhaRanking);
          LLinha.Chave := LItem.CodigoProduto;
          LLinha.Descricao := LItem.DescricaoProduto;
        end;
        Inc(LLinha.Quantidade, LItem.Quantidade);
        LLinha.Valor := LLinha.Valor + LItem.Total;
        LMapa.AddOrSetValue(LItem.ProdutoId, LLinha);
      end;
    end;

    Result := LMapa.Values.ToArray;
    // Do maior faturamento para o menor.
    TArray.Sort<TLinhaRanking>(Result, TComparer<TLinhaRanking>.Construct(
      function(const A, B: TLinhaRanking): Integer
      begin
        // comparacao explicita: evita ambiguidade de overload com Currency
        if B.Valor > A.Valor then
          Result := 1
        else if B.Valor < A.Valor then
          Result := -1
        else
          Result := 0;
      end));
  finally
    LMapa.Free;
  end;
end;

function TRelatorios.TopProdutos(AQuantidade: Integer): TArray<string>;
var
  LLinhas: TList<string>;
  LRanking: TArray<TLinhaRanking>;
  I: Integer;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua(Format('TOP %d PRODUTOS', [AQuantidade])));
    LRanking := AgregarProdutosVendidos;

    if Length(LRanking) = 0 then
      LLinhas.Add('Nenhuma venda registrada ainda.')
    else
    begin
      LLinhas.Add(Format('%-4s %-10s %-32s %8s %14s',
        ['#', 'CODIGO', 'DESCRICAO', 'QTD', 'FATURAMENTO']));
      LLinhas.Add(StringOfChar('-', 72));
      for I := 0 to Min(AQuantidade, Length(LRanking)) - 1 do
        LLinhas.Add(Format('%-4d %-10s %-32s %8d %14s',
          [I + 1, LRanking[I].Chave, Copy(LRanking[I].Descricao, 1, 32),
           LRanking[I].Quantidade, TFmt.Moeda(LRanking[I].Valor)]));
    end;

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.ClientesPorCategoria: TArray<string>;
var
  LLinhas: TList<string>;
  LCategoria: TCategoriaCliente;
  LCliente: TCliente;
  LPedido: TPedido;
  LQtdClientes, LQtdPedidos: Integer;
  LTotal, LTicket: Currency;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua('CLIENTES POR CATEGORIA'));
    LLinhas.Add(Format('%-10s %10s %10s %16s %14s',
      ['CATEGORIA', 'CLIENTES', 'PEDIDOS', 'TOTAL COMPRADO', 'TICKET MEDIO']));
    LLinhas.Add(StringOfChar('-', 64));

    for LCategoria := Low(TCategoriaCliente) to High(TCategoriaCliente) do
    begin
      LQtdClientes := 0;
      LQtdPedidos := 0;
      LTotal := 0;

      for LCliente in FApp.Clientes.PorCategoria(LCategoria) do
      begin
        Inc(LQtdClientes);
        for LPedido in FApp.Pedidos.DoCliente(LCliente.Id) do
          if not (LPedido.Status in [spRascunho, spCancelado]) then
          begin
            Inc(LQtdPedidos);
            LTotal := LTotal + LPedido.TotalLiquido;
          end;
      end;

      if LQtdClientes = 0 then
        Continue;

      if LQtdPedidos = 0 then
        LTicket := 0
      else
        LTicket := LTotal / LQtdPedidos;

      LLinhas.Add(Format('%-10s %10d %10d %16s %14s',
        [CategoriaClienteDescr(LCategoria), LQtdClientes, LQtdPedidos,
         TFmt.Moeda(LTotal), TFmt.Moeda(LTicket)]));
    end;

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.CurvaABC: TArray<string>;
var
  LLinhas: TList<string>;
  LRanking: TArray<TLinhaRanking>;
  LTotal, LAcumulado: Currency;
  LPercAcum: Double;
  LClasse: string;
  I: Integer;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua('CURVA ABC DE PRODUTOS (Pareto)'));
    LRanking := AgregarProdutosVendidos;

    LTotal := 0;
    for I := 0 to High(LRanking) do
      LTotal := LTotal + LRanking[I].Valor;

    if LTotal <= 0 then
    begin
      LLinhas.Add('Sem vendas suficientes para calcular a curva ABC.');
      Exit(LLinhas.ToArray);
    end;

    LLinhas.Add('Classe A: ate 80% do faturamento | B: ate 95% | C: o restante');
    LLinhas.Add('');
    LLinhas.Add(Format('%-10s %-30s %14s %8s %6s',
      ['CODIGO', 'DESCRICAO', 'FATURAMENTO', '% ACUM', 'CLASSE']));
    LLinhas.Add(StringOfChar('-', 72));

    LAcumulado := 0;
    for I := 0 to High(LRanking) do
    begin
      LAcumulado := LAcumulado + LRanking[I].Valor;
      LPercAcum := (LAcumulado / LTotal) * 100;

      if LPercAcum <= 80 then
        LClasse := 'A'
      else if LPercAcum <= 95 then
        LClasse := 'B'
      else
        LClasse := 'C';

      LLinhas.Add(Format('%-10s %-30s %14s %7.1f%% %6s',
        [LRanking[I].Chave, Copy(LRanking[I].Descricao, 1, 30),
         TFmt.Moeda(LRanking[I].Valor), LPercAcum, LClasse]));
    end;

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.ExtratoMovimentos(AUltimos: Integer): TArray<string>;
var
  LLinhas: TList<string>;
  LMovimentos: TArray<TMovimentoEstoque>;
  I, LInicio: Integer;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua('EXTRATO DE MOVIMENTACOES'));
    LMovimentos := FApp.Movimentos.Todos;

    if Length(LMovimentos) = 0 then
      LLinhas.Add('Nenhuma movimentacao registrada.')
    else
    begin
      LInicio := Max(0, Length(LMovimentos) - AUltimos);
      for I := LInicio to High(LMovimentos) do
        LLinhas.Add(LMovimentos[I].Resumo);
      LLinhas.Add('');
      LLinhas.Add(Format('Exibindo %d de %d movimentacao(oes).',
        [Length(LMovimentos) - LInicio, Length(LMovimentos)]));
    end;

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.PainelGeral: TArray<string>;
var
  LLinhas: TList<string>;
  LEmAberto: Currency;
  LPedido: TPedido;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua('PAINEL GERAL'));

    LEmAberto := 0;
    for LPedido in FApp.Pedidos.ComStatus(STATUS_EM_ABERTO) do
      LEmAberto := LEmAberto + LPedido.TotalLiquido;

    LLinhas.Add(Format('Clientes cadastrados .......: %d', [FApp.Clientes.Contar]));
    LLinhas.Add(Format('Produtos cadastrados ......: %d', [FApp.Produtos.Contar]));
    LLinhas.Add(Format('Produtos a repor ..........: %d', [Length(FApp.Produtos.AbaixoDoMinimo)]));
    LLinhas.Add(Format('Pedidos ...................: %d', [FApp.Pedidos.Contar]));
    LLinhas.Add(Format('Valor a receber (em aberto): %s', [TFmt.Moeda(LEmAberto)]));
    LLinhas.Add(Format('Valor imobilizado .........: %s',
      [TFmt.Moeda(FApp.Estoque.ValorTotalEmEstoque)]));
    LLinhas.Add(Format('Eventos de dominio ........: %d', [FApp.Eventos.TotalPublicados]));
    LLinhas.Add(Format('Politica de desconto ......: %s', [FApp.Politica.Nome]));
    LLinhas.Add('');
    LLinhas.Add(Format('Centros de trabalho .......: %d', [FApp.Centros.Contar]));
    LLinhas.Add(Format('Ordens de producao ........: %d', [FApp.Ordens.Contar]));
    LLinhas.Add(Format('Ordens em aberto ..........: %d',
      [Length(FApp.Ordens.ComStatus(OP_ABERTAS))]));
    LLinhas.Add(Format('Persistencia ..............: %s',
      [IfThen(FApp.UsaBanco, 'Firebird', 'memoria')]));

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

{ ============================== PCP ============================== }

function TRelatorios.EstruturaExplodida(AProdutoId: Integer;
  AQuantidade: Double): TArray<string>;
var
  LLinhas: TList<string>;
  LProduto: TProduto;
  LExplosao: TArray<TLinhaExplosao>;
  LLinha: TLinhaExplosao;
  LTotal: Currency;
begin
  LLinhas := TList<string>.Create;
  try
    LProduto := FApp.Produtos.PorId(AProdutoId);
    LLinhas.AddRange(Regua('ESTRUTURA DE ' + LProduto.Codigo));
    LLinhas.Add(Format('Item: %s (%s) - explosao para %.2f %s',
      [LProduto.Descricao, TipoProdutoDescr(LProduto.Tipo), AQuantidade,
       LProduto.Unidade]));
    LLinhas.Add('');
    LLinhas.Add(Format('%-22s %-28s %-6s %12s %14s',
      ['NIVEL/CODIGO', 'DESCRICAO', 'TIPO', 'QUANTIDADE', 'CUSTO']));
    LLinhas.Add(StringOfChar('-', 86));

    LExplosao := FApp.Engenharia.Explodir(AProdutoId, AQuantidade);
    if Length(LExplosao) = 0 then
      LLinhas.Add('  (item sem estrutura cadastrada)');

    LTotal := 0;
    for LLinha in LExplosao do
    begin
      LLinhas.Add(Format('%-22s %-28s %-6s %12.4f %14s',
        [LLinha.Indentado, Copy(LLinha.Descricao, 1, 28),
         SiglaTipo(LLinha.Tipo), LLinha.QuantidadeTotal,
         TFmt.Moeda(LLinha.QuantidadeTotal * LLinha.CustoUnitario)]));
      // So as folhas compradas somam custo: os fabricados sao a soma delas.
      if LLinha.Tipo in TIPOS_COMPRADOS then
        LTotal := LTotal + LLinha.QuantidadeTotal * LLinha.CustoUnitario;
    end;

    LLinhas.Add(StringOfChar('-', 86));
    LLinhas.Add(Format('%-58s %14s',
      ['SOMA DAS FOLHAS COMPRADAS (MP/CONS/REV)', TFmt.Moeda(LTotal)]));
    LLinhas.Add('Obs.: nao inclui a transformacao dos semiacabados - para o');
    LLinhas.Add('custo cheio do item, veja a Ficha de Custo.');
    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.NecessidadeDeMateriais(AProdutoId: Integer;
  AQuantidade: Double): TArray<string>;
var
  LLinhas: TList<string>;
  LNecessidades: TArray<TLinhaExplosao>;
  LLinha: TLinhaExplosao;
  LProduto: TProduto;
  LFalta: Double;
  LTotalCompra: Currency;
begin
  LLinhas := TList<string>.Create;
  try
    LProduto := FApp.Produtos.PorId(AProdutoId);
    LLinhas.AddRange(Regua('NECESSIDADE DE MATERIAIS (MRP simplificado)'));
    LLinhas.Add(Format('Para produzir %.2f x %s',
      [AQuantidade, LProduto.Codigo]));
    LLinhas.Add('');
    LLinhas.Add(Format('%-12s %-28s %12s %10s %12s %14s',
      ['CODIGO', 'DESCRICAO', 'NECESSARIO', 'ESTOQUE', 'COMPRAR', 'VALOR']));
    LLinhas.Add(StringOfChar('-', 92));

    LTotalCompra := 0;
    LNecessidades := FApp.Engenharia.NecessidadeDeCompra(AProdutoId, AQuantidade);
    for LLinha in LNecessidades do
    begin
      { Necessidade LIQUIDA = bruta - o que ja existe em estoque.
        E o calculo central do MRP. }
      LFalta := LLinha.QuantidadeTotal;
      if FApp.Produtos.TentarPorId(LLinha.ProdutoId, LProduto) then
        LFalta := LLinha.QuantidadeTotal - LProduto.Estoque;
      if LFalta < 0 then
        LFalta := 0;

      LLinhas.Add(Format('%-12s %-28s %12.4f %10d %12.4f %14s',
        [LLinha.Codigo, Copy(LLinha.Descricao, 1, 28), LLinha.QuantidadeTotal,
         LProduto.Estoque, LFalta,
         TFmt.Moeda(LFalta * LLinha.CustoUnitario)]));
      LTotalCompra := LTotalCompra + LFalta * LLinha.CustoUnitario;
    end;

    LLinhas.Add(StringOfChar('-', 92));
    LLinhas.Add(Format('%-77s %14s',
      ['TOTAL A COMPRAR', TFmt.Moeda(LTotalCompra)]));
    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.FichaDeCusto(AProdutoId: Integer): TArray<string>;
var
  LLinhas: TList<string>;
  LProduto: TProduto;
  LOperacao: TOperacaoRoteiro;
  LCentro: TCentroTrabalho;
  LMaterial, LOperacional: Currency;
  LTempo: Double;
begin
  LLinhas := TList<string>.Create;
  try
    LProduto := FApp.Produtos.PorId(AProdutoId);
    LLinhas.AddRange(Regua('FICHA DE CUSTO - ' + LProduto.Codigo));

    if not LProduto.EhFabricado then
    begin
      LLinhas.Add(Format('%s e item %s: o custo e o de aquisicao (%s).',
        [LProduto.Codigo, TipoProdutoDescr(LProduto.Tipo),
         TFmt.Moeda(LProduto.CustoMedio)]));
      Exit(LLinhas.ToArray);
    end;

    LMaterial := FApp.Engenharia.CustoMaterialPadrao(AProdutoId);
    LOperacional := FApp.Engenharia.CustoOperacionalPadrao(AProdutoId, 1);

    LLinhas.Add('OPERACOES DO ROTEIRO (para 1 unidade):');
    LLinhas.Add(Format('  %-4s %-28s %-12s %10s %14s',
      ['SEQ', 'OPERACAO', 'CENTRO', 'MINUTOS', 'CUSTO']));
    for LOperacao in FApp.Engenharia.Roteiro(AProdutoId) do
    begin
      LTempo := LOperacao.TempoParaLote(1);
      if FApp.Centros.TentarPorId(LOperacao.CentroId, LCentro) then
        LLinhas.Add(Format('  %-4d %-28s %-12s %10.2f %14s',
          [LOperacao.Sequencia, Copy(LOperacao.Descricao, 1, 28),
           LOperacao.CodigoCentro, LTempo,
           TFmt.Moeda(LCentro.CustoDeMinutos(LTempo))]));
    end;

    LLinhas.Add('');
    LLinhas.Add(Format('  Custo de material .......: %s', [TFmt.Moeda(LMaterial)]));
    LLinhas.Add(Format('  Custo de transformacao ..: %s', [TFmt.Moeda(LOperacional)]));
    LLinhas.Add(Format('  CUSTO PADRAO UNITARIO ...: %s',
      [TFmt.Moeda(LMaterial + LOperacional)]));
    LLinhas.Add(Format('  Preco de venda ..........: %s', [TFmt.Moeda(LProduto.Preco)]));
    if LProduto.Preco > 0 then
      LLinhas.Add(Format('  Margem bruta ............: %.1f%%',
        [(1 - (LMaterial + LOperacional) / LProduto.Preco) * 100]));

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.OrdensAbertas: TArray<string>;
var
  LLinhas: TList<string>;
  LOrdem: TOrdemProducao;
  LOrdens: TArray<TOrdemProducao>;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua('ORDENS DE PRODUCAO'));
    LLinhas.Add(Format('%-4s %-10s %-12s %-22s %10s %10s %-12s %14s',
      ['ID', 'NUMERO', 'PRODUTO', 'DESCRICAO', 'PLANEJ.', 'PRODUZ.',
       'STATUS', 'CUSTO PREV.']));
    LLinhas.Add(StringOfChar('-', 100));

    LOrdens := FApp.Ordens.Todos;
    if Length(LOrdens) = 0 then
      LLinhas.Add('  (nenhuma ordem cadastrada)');

    for LOrdem in LOrdens do
      LLinhas.Add(Format('%-4d %-10s %-12s %-22s %10.2f %10.2f %-12s %14s',
        [LOrdem.Id, LOrdem.Numero, LOrdem.CodigoProduto,
         Copy(LOrdem.DescricaoProduto, 1, 22), LOrdem.QuantidadePlanejada,
         LOrdem.QuantidadeProduzida, StatusOPDescr(LOrdem.Status),
         TFmt.Moeda(LOrdem.CustoPrevisto)]));

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.CargaDeTrabalho: TArray<string>;
var
  LLinhas: TList<string>;
  LCarga: TArray<TPar<string, Double>>;
  LItem: TPar<string, Double>;
  LCentro: TCentroTrabalho;
  LDias: Double;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua('CARGA POR CENTRO DE TRABALHO'));
    LLinhas.Add('Minutos ainda nao apontados nas ordens em aberto.');
    LLinhas.Add('');
    LLinhas.Add(Format('%-12s %-30s %12s %12s %10s',
      ['CENTRO', 'DESCRICAO', 'MINUTOS', 'HORAS', 'DIAS']));
    LLinhas.Add(StringOfChar('-', 80));

    LCarga := FApp.Producao.CargaPorCentro;
    if Length(LCarga) = 0 then
      LLinhas.Add('  (nenhuma carga pendente)');

    for LItem in LCarga do
    begin
      LCentro := FApp.Centros.PorCodigo(LItem.Chave);
      LDias := 0;
      if (LCentro <> nil) and (LCentro.CapacidadeMinutosDia > 0) then
        LDias := LItem.Valor / LCentro.CapacidadeMinutosDia;

      LLinhas.Add(Format('%-12s %-30s %12.1f %12.2f %10.2f',
        [LItem.Chave,
         IfThen(LCentro <> nil, Copy(LCentro.Descricao, 1, 30), '?'),
         LItem.Valor, LItem.Valor / 60, LDias]));
    end;

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.EficienciaDeProducao: TArray<string>;
var
  LLinhas: TList<string>;
  LOrdem: TOrdemProducao;
  LOrdens: TArray<TOrdemProducao>;
  LIndice: Double;
begin
  LLinhas := TList<string>.Create;
  try
    LLinhas.AddRange(Regua('EFICIENCIA DA PRODUCAO (ordens encerradas)'));
    LLinhas.Add(Format('%-10s %-12s %10s %10s %8s %14s %14s %10s',
      ['NUMERO', 'PRODUTO', 'PRODUZ.', 'REFUGO', '%REF', 'PREVISTO',
       'REAL', 'VARIACAO']));
    LLinhas.Add(StringOfChar('-', 96));

    LOrdens := FApp.Ordens.ComStatus([opConcluida]);
    if Length(LOrdens) = 0 then
      LLinhas.Add('  (nenhuma ordem concluida ainda)');

    for LOrdem in LOrdens do
    begin
      LIndice := 0;
      if (LOrdem.QuantidadeProduzida + LOrdem.QuantidadeRefugada) > 0 then
        LIndice := LOrdem.QuantidadeRefugada /
          (LOrdem.QuantidadeProduzida + LOrdem.QuantidadeRefugada);

      LLinhas.Add(Format('%-10s %-12s %10.2f %10.2f %7.1f%% %14s %14s %10s',
        [LOrdem.Numero, LOrdem.CodigoProduto, LOrdem.QuantidadeProduzida,
         LOrdem.QuantidadeRefugada, LIndice * 100,
         TFmt.Moeda(LOrdem.CustoPrevisto), TFmt.Moeda(LOrdem.CustoReal),
         TFmt.Moeda(LOrdem.CustoReal - LOrdem.CustoPrevisto)]));
    end;

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

function TRelatorios.DetalheDaOrdem(AOrdemId: Integer): TArray<string>;
var
  LLinhas: TList<string>;
  LOrdem: TOrdemProducao;
  LComponente: TComponenteOP;
  LOperacao: TOperacaoOP;
  LApontamento: TApontamento;
begin
  LLinhas := TList<string>.Create;
  try
    LOrdem := FApp.Ordens.PorId(AOrdemId);
    LLinhas.AddRange(Regua('ORDEM DE PRODUCAO ' + LOrdem.Numero));

    LLinhas.Add(Format('Produto ....: %s - %s',
      [LOrdem.CodigoProduto, LOrdem.DescricaoProduto]));
    LLinhas.Add(Format('Quantidade .: %.2f planejada | %.2f produzida | %.2f refugada',
      [LOrdem.QuantidadePlanejada, LOrdem.QuantidadeProduzida,
       LOrdem.QuantidadeRefugada]));
    LLinhas.Add(Format('Status .....: %s (%.0f%% concluida)',
      [StatusOPDescr(LOrdem.Status), LOrdem.PercentualConcluido * 100]));
    LLinhas.Add(Format('Prevista p/ : %s', [TFmt.Data(LOrdem.DataPrevista)]));

    LLinhas.Add('');
    LLinhas.Add('LISTA DE MATERIAL (congelada na abertura):');
    for LComponente in LOrdem.Componentes do
      LLinhas.Add('  ' + LComponente.Resumo);

    LLinhas.Add('');
    LLinhas.Add('ROTEIRO:');
    for LOperacao in LOrdem.Operacoes do
      LLinhas.Add('  ' + LOperacao.Resumo);

    LLinhas.Add('');
    LLinhas.Add('APONTAMENTOS:');
    if LOrdem.Apontamentos.Count = 0 then
      LLinhas.Add('  (nenhum)');
    for LApontamento in LOrdem.Apontamentos do
      LLinhas.Add('  ' + LApontamento.Resumo);

    LLinhas.Add('');
    LLinhas.Add(Format('Custo material ....: previsto %s | real %s',
      [TFmt.Moeda(LOrdem.CustoMaterialPrevisto),
       TFmt.Moeda(LOrdem.CustoMaterialReal)]));
    LLinhas.Add(Format('Custo transformacao: previsto %s | real %s',
      [TFmt.Moeda(LOrdem.CustoOperacionalPrevisto),
       TFmt.Moeda(LOrdem.CustoOperacionalReal)]));
    LLinhas.Add(Format('CUSTO TOTAL .......: previsto %s | real %s',
      [TFmt.Moeda(LOrdem.CustoPrevisto), TFmt.Moeda(LOrdem.CustoReal)]));
    if LOrdem.QuantidadeProduzida > 0 then
      LLinhas.Add(Format('Custo unitario real: %s',
        [TFmt.Moeda(LOrdem.CustoUnitarioReal)]));
    LLinhas.Add(Format('Tempo .............: previsto %.1f min | realizado %.1f min',
      [LOrdem.TempoPrevistoTotal, LOrdem.TempoRealizadoTotal]));

    Result := LLinhas.ToArray;
  finally
    LLinhas.Free;
  end;
end;

end.
