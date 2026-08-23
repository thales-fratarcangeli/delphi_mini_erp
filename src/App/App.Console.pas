{*******************************************************************************
  App.Console

  A camada de APRESENTACAO. Trocar isto por um formulario VCL nao muda uma
  linha das camadas de baixo - e exatamente esse o objetivo da arquitetura.

  ESTUDO:
    * Tratamento de excecao na FRONTEIRA: o usuario nunca ve stack trace.
      EValidacao/EDominio viram mensagens amigaveis; o resto vira "erro
      inesperado" e vai para o log
    * Separacao entre "obter dados" (repositorios) e "mostrar dados" (aqui)
    * Metodos anonimos para reaproveitar o try/except de cada acao do menu
*******************************************************************************}
unit App.Console;

interface

uses
  System.SysUtils,
  App.Bootstrap,
  App.Reports;

type
  TConsoleUI = class
  private
    FApp: TAplicacao;
    FRelatorios: TRelatorios;
    FRodando: Boolean;

    // ---- utilidades de tela ----
    procedure Cabecalho(const ATitulo: string);
    procedure Escrever(const ALinhas: TArray<string>);
    procedure Pausa;
    procedure Sucesso(const AMensagem: string); overload;
    procedure Sucesso(const AMensagem: string; const AArgs: array of const); overload;
    procedure Falha(const AMensagem: string);

    // ---- utilidades de entrada ----
    function LerTexto(const APergunta: string; const APadrao: string = ''): string;
    function LerInteiro(const APergunta: string; APadrao: Integer = 0): Integer;
    function LerMoeda(const APergunta: string; APadrao: Currency = 0): Currency;
    function Confirmar(const APergunta: string): Boolean;
    function LerOpcao(const APergunta: string;
      const AOpcoes: array of string): Integer;

    /// Executa a acao capturando os erros previsiveis do dominio.
    procedure Acao(const ABloco: TProc);

    // ---- menus ----
    procedure MenuPrincipal;
    procedure MenuClientes;
    procedure MenuProdutos;
    procedure MenuPedidos;
    procedure MenuEstoque;
    procedure MenuRelatorios;
    procedure MenuSistema;
    procedure MenuEngenharia;
    procedure MenuProducao;
    procedure MenuRelatoriosPCP;

    // ---- listagens ----
    procedure ListarClientes;
    procedure ListarProdutos;
    procedure ListarPedidos;
    procedure DetalharPedido(APedidoId: Integer);
    procedure ListarCentros;
    procedure ListarOrdens;
    procedure ListarFabricados;
  public
    constructor Create(AApp: TAplicacao);
    destructor Destroy; override;
    procedure Executar;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Core.Types,
  Core.Validation,
  Domain.Entities,
  Domain.Enums,
  Domain.Interfaces,
  Domain.Producao,
  Domain.Producao.Services;

{ TConsoleUI }

constructor TConsoleUI.Create(AApp: TAplicacao);
begin
  inherited Create;
  FApp := AApp;
  FRelatorios := TRelatorios.Create(AApp);
end;

destructor TConsoleUI.Destroy;
begin
  FRelatorios.Free;
  inherited;
end;

{ ------------------------------------------------------------------- tela }

procedure TConsoleUI.Cabecalho(const ATitulo: string);
begin
  Writeln;
  Writeln(StringOfChar('=', 76));
  Writeln('  ', ATitulo);
  Writeln(StringOfChar('=', 76));
end;

procedure TConsoleUI.Escrever(const ALinhas: TArray<string>);
var
  LLinha: string;
begin
  for LLinha in ALinhas do
    Writeln(LLinha);
end;

procedure TConsoleUI.Pausa;
begin
  Writeln;
  Write('  [Enter para continuar] ');
  Readln;
end;

procedure TConsoleUI.Sucesso(const AMensagem: string);
begin
  Writeln('  >> ', AMensagem);
end;

procedure TConsoleUI.Sucesso(const AMensagem: string; const AArgs: array of const);
begin
  Writeln('  >> ', Format(AMensagem, AArgs));
end;

procedure TConsoleUI.Falha(const AMensagem: string);
begin
  Writeln('  !! ', AMensagem);
end;

{ ---------------------------------------------------------------- entrada }

function TConsoleUI.LerTexto(const APergunta, APadrao: string): string;
begin
  if APadrao <> '' then
    Write(Format('  %s [%s]: ', [APergunta, APadrao]))
  else
    Write(Format('  %s: ', [APergunta]));
  Readln(Result);
  Result := Trim(Result);
  if Result = '' then
    Result := APadrao;
end;

function TConsoleUI.LerInteiro(const APergunta: string; APadrao: Integer): Integer;
var
  LTexto: string;
begin
  LTexto := LerTexto(APergunta, IfThen(APadrao <> 0, IntToStr(APadrao), ''));
  Result := StrToIntDef(LTexto, APadrao);
end;

function TConsoleUI.LerMoeda(const APergunta: string; APadrao: Currency): Currency;
var
  LTexto: string;
begin
  LTexto := LerTexto(APergunta);
  if LTexto = '' then
    Exit(APadrao);
  // Aceita tanto 1234,56 quanto 1234.56, independente do idioma do Windows.
  LTexto := StringReplace(LTexto, '.', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  LTexto := StringReplace(LTexto, ',', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  Result := StrToCurrDef(LTexto, APadrao);
end;

function TConsoleUI.Confirmar(const APergunta: string): Boolean;
var
  LTexto: string;
begin
  LTexto := LowerCase(LerTexto(APergunta + ' (s/n)', 'n'));
  Result := StartsText('s', LTexto);
end;

function TConsoleUI.LerOpcao(const APergunta: string;
  const AOpcoes: array of string): Integer;
var
  I: Integer;
begin
  Writeln;
  for I := 0 to High(AOpcoes) do
    Writeln(Format('    %d) %s', [I + 1, AOpcoes[I]]));
  Result := LerInteiro(APergunta, 1) - 1;
  if (Result < 0) or (Result > High(AOpcoes)) then
    Result := 0;
end;

procedure TConsoleUI.Acao(const ABloco: TProc);
var
  LErro: string;
begin
  try
    ABloco();
  except
    // Erros PREVISTOS viram mensagem amigavel...
    on E: EValidacao do
    begin
      Falha('Corrija os seguintes pontos:');
      for LErro in E.Erros do
        Writeln('       - ', LErro);
    end;
    on E: EDominio do
      Falha(E.Message);
    on E: EInfra do
      Falha('Problema de infraestrutura: ' + E.Message);
    // ...e o resto e bug: registra no log para investigacao.
    on E: Exception do
    begin
      Falha(Format('Erro inesperado (%s). Detalhes no log.', [E.ClassName]));
      FApp.Logger.ErroExcecao(E, 'ConsoleUI');
    end;
  end;
end;

{ ------------------------------------------------------------------ menus }

procedure TConsoleUI.Executar;
begin
  FRodando := True;
  Cabecalho('SISTEMA DE GESTAO COMERCIAL - projeto de estudo em Delphi');
  Writeln('  Dica: comece pelo item 6 (Relatorios) para ver os dados de exemplo.');
  while FRodando do
    MenuPrincipal;
end;

procedure TConsoleUI.MenuPrincipal;
begin
  Writeln;
  Writeln(StringOfChar('-', 76));
  Writeln('  MENU PRINCIPAL');
  Writeln('    1) Clientes          5) Relatorios comerciais');
  Writeln('    2) Produtos          6) Sistema (salvar, log, eventos, banco)');
  Writeln('    3) Pedidos           7) Engenharia (estrutura e roteiro)');
  Writeln('    4) Estoque           8) Producao (ordens e apontamento)');
  Writeln('                         9) Relatorios de PCP');
  Writeln('    0) Sair');
  Writeln(StringOfChar('-', 76));

  case LerInteiro('Opcao', 0) of
    1: MenuClientes;
    2: MenuProdutos;
    3: MenuPedidos;
    4: MenuEstoque;
    5: MenuRelatorios;
    6: MenuSistema;
    7: MenuEngenharia;
    8: MenuProducao;
    9: MenuRelatoriosPCP;
    0: FRodando := False;
  else
    Falha('Opcao invalida.');
  end;
end;

{ --------------------------------------------------------------- clientes }

procedure TConsoleUI.ListarClientes;
var
  LCliente: TCliente;
begin
  Cabecalho('CLIENTES');
  Writeln(Format('  %-4s %-28s %-18s %-8s %14s %6s',
    ['ID', 'NOME', 'DOCUMENTO', 'CATEG.', 'LIMITE', 'ATIVO']));
  Writeln('  ', StringOfChar('-', 82));
  for LCliente in FApp.Clientes.Todos do
    Writeln(Format('  %-4d %-28s %-18s %-8s %14s %6s',
      [LCliente.Id, Copy(LCliente.Nome, 1, 28), LCliente.DocumentoFormatado,
       CategoriaClienteDescr(LCliente.Categoria),
       TFmt.Moeda(LCliente.LimiteCredito),
       IfThen(LCliente.Ativo, 'sim', 'nao')]));
end;

procedure TConsoleUI.MenuClientes;
var
  LCliente: TCliente;
  LId: Integer;
begin
  case LerOpcao('Clientes', ['Listar', 'Cadastrar', 'Alterar limite',
    'Ativar/inativar', 'Ver credito disponivel', 'Voltar']) of
    0: begin
         ListarClientes;
         Pausa;
       end;
    1: Acao(
         procedure
         var
           LNovo: TCliente;
         begin
           LNovo := TCliente.Create;
           try
             LNovo.Nome := LerTexto('Nome');
             LNovo.Documento := LerTexto('CPF/CNPJ');
             LNovo.Email := LerTexto('E-mail');
             LNovo.Telefone := LerTexto('Telefone');
             LNovo.Cidade := LerTexto('Cidade');
             LNovo.UF := LerTexto('UF', 'SP');
             LNovo.Categoria := TCategoriaCliente(
               LerOpcao('Categoria', ['Comum', 'Prata', 'Ouro', 'VIP']));
             LNovo.LimiteCredito := LerMoeda('Limite de credito', 1000);
             LNovo.Validar;                    // regras declarativas + programadas
             FApp.Clientes.Adicionar(LNovo);   // so aqui o repositorio assume a posse
             Sucesso('Cliente #%d cadastrado.', [LNovo.Id]);
           except
             LNovo.Free;                       // se algo falhou, ninguem ficou dono
             raise;
           end;
         end);
    2: Acao(
         procedure
         begin
           ListarClientes;
           LId := LerInteiro('Id do cliente');
           LCliente := FApp.Clientes.PorId(LId);
           LCliente.LimiteCredito := LerMoeda(
             Format('Novo limite (atual %s)', [TFmt.Moeda(LCliente.LimiteCredito)]),
             LCliente.LimiteCredito);
           LCliente.Validar;
           FApp.Clientes.Atualizar(LCliente);
           Sucesso('Limite atualizado para %s.', [TFmt.Moeda(LCliente.LimiteCredito)]);
         end);
    3: Acao(
         procedure
         begin
           ListarClientes;
           LCliente := FApp.Clientes.PorId(LerInteiro('Id do cliente'));
           LCliente.Ativo := not LCliente.Ativo;
           FApp.Clientes.Atualizar(LCliente);
           Sucesso('Cliente %s agora esta %s.',
             [LCliente.Nome, IfThen(LCliente.Ativo, 'ATIVO', 'INATIVO')]);
         end);
    4: Acao(
         procedure
         begin
           ListarClientes;
           LId := LerInteiro('Id do cliente');
           LCliente := FApp.Clientes.PorId(LId);
           Writeln;
           Sucesso('Limite total .....: %s', [TFmt.Moeda(LCliente.LimiteCredito)]);
           Sucesso('Em aberto ........: %s',
             [TFmt.Moeda(FApp.Pedidos.TotalEmAbertoDoCliente(LId))]);
           Sucesso('Disponivel .......: %s',
             [TFmt.Moeda(FApp.Vendas.CreditoDisponivel(LId))]);
           Pausa;
         end);
  end;
end;

{ --------------------------------------------------------------- produtos }

procedure TConsoleUI.ListarProdutos;
var
  LProduto: TProduto;
begin
  Cabecalho('PRODUTOS');
  Writeln(Format('  %-4s %-10s %-30s %12s %8s %8s',
    ['ID', 'CODIGO', 'DESCRICAO', 'PRECO', 'ESTOQUE', 'MINIMO']));
  Writeln('  ', StringOfChar('-', 78));
  for LProduto in FApp.Produtos.Todos do
    Writeln(Format('  %-4d %-10s %-30s %12s %8d %8d%s',
      [LProduto.Id, LProduto.Codigo, Copy(LProduto.Descricao, 1, 30),
       TFmt.Moeda(LProduto.Preco), LProduto.Estoque, LProduto.EstoqueMinimo,
       IfThen(LProduto.AbaixoDoMinimo, '  <== repor', '')]));
end;

procedure TConsoleUI.MenuProdutos;
begin
  case LerOpcao('Produtos', ['Listar', 'Cadastrar', 'Alterar preco',
    'Buscar por codigo', 'Voltar']) of
    0: begin
         ListarProdutos;
         Pausa;
       end;
    1: Acao(
         procedure
         var
           LNovo: TProduto;
         begin
           LNovo := TProduto.Create;
           try
             LNovo.Codigo := LerTexto('Codigo');
             LNovo.Descricao := LerTexto('Descricao');
             LNovo.Categoria := LerTexto('Categoria', 'Geral');
             LNovo.Preco := LerMoeda('Preco');
             LNovo.Estoque := LerInteiro('Estoque inicial');
             LNovo.EstoqueMinimo := LerInteiro('Estoque minimo', 5);
             LNovo.Validar;
             FApp.Produtos.Adicionar(LNovo);
             Sucesso('Produto #%d cadastrado.', [LNovo.Id]);
           except
             LNovo.Free;
             raise;
           end;
         end);
    2: Acao(
         procedure
         var
           LProduto: TProduto;
         begin
           ListarProdutos;
           LProduto := FApp.Produtos.PorId(LerInteiro('Id do produto'));
           LProduto.Preco := LerMoeda(
             Format('Novo preco (atual %s)', [TFmt.Moeda(LProduto.Preco)]),
             LProduto.Preco);
           LProduto.Validar;
           FApp.Produtos.Atualizar(LProduto);
           Sucesso('Preco atualizado. Pedidos ja fechados mantem o preco antigo.');
         end);
    3: Acao(
         procedure
         var
           LProduto: TProduto;
         begin
           LProduto := FApp.Produtos.PorCodigo(LerTexto('Codigo'));
           if LProduto = nil then
             Falha('Nenhum produto com esse codigo.')
           else
             Sucesso(LProduto.Resumo);
           Pausa;
         end);
  end;
end;

{ ---------------------------------------------------------------- pedidos }

procedure TConsoleUI.ListarPedidos;
var
  LPedido: TPedido;
begin
  Cabecalho('PEDIDOS');
  Writeln(Format('  %-4s %-11s %-26s %6s %14s %-12s',
    ['ID', 'NUMERO', 'CLIENTE', 'ITENS', 'TOTAL', 'STATUS']));
  Writeln('  ', StringOfChar('-', 80));
  for LPedido in FApp.Pedidos.Todos do
    Writeln(Format('  %-4d %-11s %-26s %6d %14s %-12s',
      [LPedido.Id, LPedido.Numero, Copy(LPedido.NomeCliente, 1, 26),
       LPedido.Itens.Count, TFmt.Moeda(LPedido.TotalLiquido),
       StatusPedidoDescr(LPedido.Status)]));
end;

procedure TConsoleUI.DetalharPedido(APedidoId: Integer);
var
  LPedido: TPedido;
  LItem: TItemPedido;
  I: Integer;
begin
  LPedido := FApp.Pedidos.PorId(APedidoId);
  Cabecalho('PEDIDO ' + LPedido.Numero);
  Writeln(Format('  Cliente ..: %s (#%d)', [LPedido.NomeCliente, LPedido.ClienteId]));
  Writeln(Format('  Status ...: %s', [StatusPedidoDescr(LPedido.Status)]));
  Writeln(Format('  Criado em : %s', [TFmt.DataHora(LPedido.CriadoEm)]));
  Writeln;
  Writeln('  ITENS:');
  for I := 0 to LPedido.Itens.Count - 1 do
  begin
    LItem := LPedido.Itens[I];
    Writeln(Format('   %2d) %s', [I + 1, LItem.Resumo]));
  end;
  Writeln;
  Writeln(Format('  Total bruto ........: %s', [TFmt.Moeda(LPedido.TotalBruto)]));
  Writeln(Format('  Desconto nos itens .: %s', [TFmt.Moeda(LPedido.TotalDescontoItens)]));
  Writeln(Format('  Desconto negociado .: %s', [TFmt.Moeda(LPedido.DescontoNegociado)]));
  Writeln(Format('  Frete ..............: %s', [TFmt.Moeda(LPedido.Frete)]));
  Writeln(Format('  TOTAL A PAGAR ......: %s', [TFmt.Moeda(LPedido.TotalLiquido)]));
  if LPedido.Observacao <> '' then
    Writeln(Format('  Observacao .........: %s', [LPedido.Observacao]));
end;

procedure TConsoleUI.MenuPedidos;
begin
  case LerOpcao('Pedidos', ['Listar', 'Detalhar', 'Novo pedido',
    'Adicionar item', 'Remover item', 'Confirmar', 'Pagar', 'Enviar/Entregar',
    'Cancelar', 'Voltar']) of
    0: begin
         ListarPedidos;
         Pausa;
       end;
    1: Acao(
         procedure
         begin
           ListarPedidos;
           DetalharPedido(LerInteiro('Id do pedido'));
           Pausa;
         end);
    2: Acao(
         procedure
         var
           LPedido: TPedido;
         begin
           ListarClientes;
           LPedido := FApp.Vendas.CriarPedido(LerInteiro('Id do cliente'));
           Sucesso('Pedido %s criado (Id %d). Agora adicione itens.',
             [LPedido.Numero, LPedido.Id]);
         end);
    3: Acao(
         procedure
         var
           LPedidoId, LProdutoId, LQtd: Integer;
           LDesconto: Currency;
         begin
           ListarPedidos;
           LPedidoId := LerInteiro('Id do pedido');
           ListarProdutos;
           LProdutoId := LerInteiro('Id do produto');
           LQtd := LerInteiro('Quantidade', 1);
           LDesconto := LerMoeda('Desconto do item em % (0 a 100)', 0);
           FApp.Vendas.AdicionarItem(LPedidoId, LProdutoId, LQtd, LDesconto / 100);
           DetalharPedido(LPedidoId);
         end);
    4: Acao(
         procedure
         var
           LPedidoId: Integer;
         begin
           ListarPedidos;
           LPedidoId := LerInteiro('Id do pedido');
           DetalharPedido(LPedidoId);
           FApp.Vendas.RemoverItem(LPedidoId, LerInteiro('Numero do item') - 1);
           Sucesso('Item removido.');
         end);
    5: Acao(
         procedure
         var
           LPedidoId: Integer;
           LResultado: TResultado<Currency>;
         begin
           ListarPedidos;
           LPedidoId := LerInteiro('Id do pedido');
           LResultado := FApp.Vendas.ConfirmarPedido(LPedidoId);
           if LResultado.Sucesso then
             Sucesso('Pedido confirmado! Total: %s', [TFmt.Moeda(LResultado.Valor)])
           else
             Falha(LResultado.Erro);   // falha ESPERADA: nao e excecao
           Pausa;
         end);
    6: Acao(
         procedure
         var
           LPedidoId: Integer;
           LForma: TFormaPagamento;
           LResultado: TResultado<string>;
         begin
           ListarPedidos;
           LPedidoId := LerInteiro('Id do pedido');
           LForma := TFormaPagamento(LerOpcao('Forma de pagamento',
             ['Dinheiro', 'PIX', 'Cartao de debito', 'Cartao de credito', 'Boleto']));
           LResultado := FApp.Vendas.PagarPedido(LPedidoId, LForma);
           if LResultado.Sucesso then
             Sucesso('Pagamento aprovado. Autorizacao: %s', [LResultado.Valor])
           else
             Falha(LResultado.Erro);
           Pausa;
         end);
    7: Acao(
         procedure
         var
           LPedidoId: Integer;
         begin
           ListarPedidos;
           LPedidoId := LerInteiro('Id do pedido');
           if LerOpcao('Acao', ['Marcar como enviado', 'Marcar como entregue']) = 0 then
             FApp.Vendas.EnviarPedido(LPedidoId)
           else
             FApp.Vendas.EntregarPedido(LPedidoId);
           Sucesso('Status atualizado.');
         end);
    8: Acao(
         procedure
         var
           LPedidoId: Integer;
         begin
           ListarPedidos;
           LPedidoId := LerInteiro('Id do pedido');
           if Confirmar('Confirma o cancelamento?') then
           begin
             FApp.Vendas.CancelarPedido(LPedidoId, LerTexto('Motivo', 'nao informado'));
             Sucesso('Pedido cancelado e estoque devolvido.');
           end;
         end);
  end;
end;

{ ---------------------------------------------------------------- estoque }

procedure TConsoleUI.MenuEstoque;
begin
  case LerOpcao('Estoque', ['Posicao de estoque', 'Entrada de mercadoria',
    'Ajuste de inventario', 'Extrato de movimentacoes', 'Produtos a repor',
    'Voltar']) of
    0: begin
         Escrever(FRelatorios.PosicaoDeEstoque);
         Pausa;
       end;
    1: Acao(
         procedure
         var
           LProdutoId, LQtd: Integer;
         begin
           ListarProdutos;
           LProdutoId := LerInteiro('Id do produto');
           LQtd := LerInteiro('Quantidade recebida', 1);
           FApp.Estoque.RegistrarEntrada(LProdutoId, LQtd,
             LerTexto('Motivo', 'Compra de mercadoria'));
           Sucesso('Entrada registrada. Novo saldo: %d',
             [FApp.Produtos.PorId(LProdutoId).Estoque]);
         end);
    2: Acao(
         procedure
         var
           LProdutoId, LSaldo: Integer;
         begin
           ListarProdutos;
           LProdutoId := LerInteiro('Id do produto');
           LSaldo := LerInteiro('Saldo contado no inventario');
           FApp.Estoque.AjustarInventario(LProdutoId, LSaldo,
             LerTexto('Motivo', 'Inventario ciclico'));
           Sucesso('Inventario ajustado.');
         end);
    3: begin
         Escrever(FRelatorios.ExtratoMovimentos(30));
         Pausa;
       end;
    4: Acao(
         procedure
         var
           LProduto: TProduto;
         begin
           Cabecalho('PRODUTOS A REPOR');
           for LProduto in FApp.Produtos.AbaixoDoMinimo do
             Writeln('  ', LProduto.Resumo);
           Pausa;
         end);
  end;
end;

{ ------------------------------------------------------------- relatorios }

procedure TConsoleUI.MenuRelatorios;
begin
  case LerOpcao('Relatorios', ['Painel geral', 'Posicao de estoque',
    'Pedidos por status', 'Top produtos', 'Clientes por categoria',
    'Curva ABC', 'Voltar']) of
    0: Escrever(FRelatorios.PainelGeral);
    1: Escrever(FRelatorios.PosicaoDeEstoque);
    2: Escrever(FRelatorios.VendasPorStatus);
    3: Escrever(FRelatorios.TopProdutos(10));
    4: Escrever(FRelatorios.ClientesPorCategoria);
    5: Escrever(FRelatorios.CurvaABC);
  else
    Exit;
  end;
  Pausa;
end;

{ --------------------------------------------------------------- fabrica }

procedure TConsoleUI.ListarCentros;
var
  LCentro: TCentroTrabalho;
begin
  Cabecalho('CENTROS DE TRABALHO');
  Writeln(Format('  %-4s %-14s %-32s %10s %14s',
    ['ID', 'CODIGO', 'DESCRICAO', 'H/DIA', 'CUSTO/HORA']));
  Writeln('  ', StringOfChar('-', 78));
  for LCentro in FApp.Centros.Todos do
    Writeln(Format('  %-4d %-14s %-32s %10.1f %14s',
      [LCentro.Id, LCentro.Codigo, Copy(LCentro.Descricao, 1, 32),
       LCentro.CapacidadeHorasDia, TFmt.Moeda(LCentro.CustoHora)]));
end;

procedure TConsoleUI.ListarFabricados;
var
  LProduto: TProduto;
begin
  Cabecalho('ITENS FABRICADOS (tem estrutura e roteiro)');
  Writeln(Format('  %-4s %-12s %-34s %-16s %14s',
    ['ID', 'CODIGO', 'DESCRICAO', 'TIPO', 'CUSTO PADRAO']));
  Writeln('  ', StringOfChar('-', 84));
  for LProduto in FApp.Produtos.Todos do
    if LProduto.EhFabricado then
      Writeln(Format('  %-4d %-12s %-34s %-16s %14s',
        [LProduto.Id, LProduto.Codigo, Copy(LProduto.Descricao, 1, 34),
         TipoProdutoDescr(LProduto.Tipo),
         TFmt.Moeda(FApp.Engenharia.CustoPadrao(LProduto.Id))]));
end;

procedure TConsoleUI.ListarOrdens;
begin
  Escrever(FRelatorios.OrdensAbertas);
end;

procedure TConsoleUI.MenuEngenharia;
begin
  case LerOpcao('Engenharia', ['Itens fabricados', 'Ver estrutura (BOM)',
    'Definir componente', 'Remover componente', 'Onde e usado',
    'Ver roteiro', 'Definir operacao', 'Centros de trabalho',
    'Cadastrar centro', 'Voltar']) of
    0: begin
         ListarFabricados;
         Pausa;
       end;
    1: Acao(
         procedure
         var
           LProdutoId: Integer;
           LQtd: Currency;
         begin
           ListarFabricados;
           LProdutoId := LerInteiro('Id do item');
           LQtd := LerMoeda('Explodir para quantas unidades', 1);
           Escrever(FRelatorios.EstruturaExplodida(LProdutoId, LQtd));
           Pausa;
         end);
    2: Acao(
         procedure
         var
           LPaiId, LCompId: Integer;
           LQtd, LPerda: Currency;
         begin
           ListarFabricados;
           LPaiId := LerInteiro('Id do item PAI (o que sera fabricado)');
           ListarProdutos;
           LCompId := LerInteiro('Id do COMPONENTE');
           LQtd := LerMoeda('Quantidade por unidade do pai', 1);
           LPerda := LerMoeda('Perda tecnica em % (0 a 90)', 0);
           FApp.Engenharia.DefinirComponente(LPaiId, LCompId, LQtd, LPerda / 100);
           Sucesso('Estrutura atualizada.');
           Escrever(FRelatorios.EstruturaExplodida(LPaiId, 1));
           Pausa;
         end);
    3: Acao(
         procedure
         var
           LPaiId: Integer;
         begin
           ListarFabricados;
           LPaiId := LerInteiro('Id do item pai');
           Escrever(FRelatorios.EstruturaExplodida(LPaiId, 1));
           FApp.Engenharia.RemoverComponente(LPaiId,
             LerInteiro('Id do componente a remover'));
           Sucesso('Componente removido da estrutura.');
         end);
    4: Acao(
         procedure
         var
           LLinha: TItemEstrutura;
           LProduto: TProduto;
         begin
           ListarProdutos;
           LProduto := FApp.Produtos.PorId(LerInteiro('Id do componente'));
           Cabecalho('ONDE E USADO: ' + LProduto.Codigo);
           for LLinha in FApp.Estruturas.OndeEUsado(LProduto.Id) do
             Writeln(Format('  usado em %-12s quantidade %10.4f',
               [FApp.Produtos.PorId(LLinha.ProdutoPaiId).Codigo,
                LLinha.Quantidade]));
           Pausa;
         end);
    5: Acao(
         procedure
         var
           LOperacao: TOperacaoRoteiro;
           LProdutoId: Integer;
         begin
           ListarFabricados;
           LProdutoId := LerInteiro('Id do item');
           Cabecalho('ROTEIRO DE FABRICACAO');
           for LOperacao in FApp.Engenharia.Roteiro(LProdutoId) do
             Writeln('  ', LOperacao.Resumo);
           Writeln;
           Writeln(Format('  Tempo para um lote de 10: %.1f minutos',
             [FApp.Engenharia.TempoDoLote(LProdutoId, 10)]));
           Pausa;
         end);
    6: Acao(
         procedure
         var
           LProdutoId, LSeq, LCentroId: Integer;
           LSetup, LUnitario: Currency;
         begin
           ListarFabricados;
           LProdutoId := LerInteiro('Id do item');
           LSeq := LerInteiro('Sequencia da operacao (10, 20, ...)', 10);
           ListarCentros;
           LCentroId := LerInteiro('Id do centro de trabalho');
           LSetup := LerMoeda('Tempo de setup em minutos', 0);
           LUnitario := LerMoeda('Tempo por peca em minutos', 1);
           FApp.Engenharia.DefinirOperacao(LProdutoId, LSeq,
             LerTexto('Descricao da operacao'), LCentroId, LSetup, LUnitario);
           Sucesso('Roteiro atualizado.');
         end);
    7: begin
         ListarCentros;
         Pausa;
       end;
    8: Acao(
         procedure
         var
           LCentro: TCentroTrabalho;
         begin
           LCentro := TCentroTrabalho.Create;
           try
             LCentro.Codigo := LerTexto('Codigo');
             LCentro.Descricao := LerTexto('Descricao');
             LCentro.CapacidadeHorasDia := LerMoeda('Capacidade em horas/dia', 8);
             LCentro.CustoHora := LerMoeda('Custo por hora', 0);
             LCentro.Validar;
             FApp.Centros.Adicionar(LCentro);
             Sucesso('Centro #%d cadastrado.', [LCentro.Id]);
           except
             LCentro.Free;
             raise;
           end;
         end);
  end;
end;

procedure TConsoleUI.MenuProducao;
begin
  case LerOpcao('Producao', ['Listar ordens', 'Detalhar ordem',
    'Criar ordem', 'Conferir material', 'Liberar (requisitar material)',
    'Apontar producao', 'Concluir ordem', 'Cancelar ordem', 'Voltar']) of
    0: begin
         ListarOrdens;
         Pausa;
       end;
    1: Acao(
         procedure
         begin
           ListarOrdens;
           Escrever(FRelatorios.DetalheDaOrdem(LerInteiro('Id da ordem')));
           Pausa;
         end);
    2: Acao(
         procedure
         var
           LProdutoId: Integer;
           LQtd: Currency;
           LResultado: TResultado<TOrdemProducao>;
         begin
           ListarFabricados;
           LProdutoId := LerInteiro('Id do item a fabricar');
           LQtd := LerMoeda('Quantidade', 1);
           LResultado := FApp.Producao.CriarOrdem(LProdutoId, LQtd,
             Date + LerInteiro('Entrega em quantos dias', 7));
           if LResultado.Sucesso then
           begin
             Sucesso('Ordem %s criada (Id %d). Custo previsto: %s',
               [LResultado.Valor.Numero, LResultado.Valor.Id,
                TFmt.Moeda(LResultado.Valor.CustoPrevisto)]);
             Escrever(FRelatorios.DetalheDaOrdem(LResultado.Valor.Id));
           end
           else
             Falha(LResultado.Erro);
           Pausa;
         end);
    3: Acao(
         procedure
         var
           LFaltas: TArray<string>;
           LFalta: string;
         begin
           ListarOrdens;
           LFaltas := FApp.Producao.FaltaDeMaterial(LerInteiro('Id da ordem'));
           if Length(LFaltas) = 0 then
             Sucesso('Material completo: a ordem pode ser liberada.')
           else
           begin
             Falha('Falta material:');
             for LFalta in LFaltas do
               Writeln('       - ', LFalta);
           end;
           Pausa;
         end);
    4: Acao(
         procedure
         var
           LResultado: TResultado<Currency>;
         begin
           ListarOrdens;
           LResultado := FApp.Producao.LiberarOrdem(LerInteiro('Id da ordem'));
           if LResultado.Sucesso then
             Sucesso('Ordem liberada. Material requisitado: %s',
               [TFmt.Moeda(LResultado.Valor)])
           else
             Falha(LResultado.Erro);
           Pausa;
         end);
    5: Acao(
         procedure
         var
           LOrdemId, LSeq: Integer;
           LBoas, LRefugo, LTempo: Currency;
           LMotivo: string;
           LResultado: TResultado<Double>;
           LOrdem: TOrdemProducao;
           LOperacao: TOperacaoOP;
         begin
           ListarOrdens;
           LOrdemId := LerInteiro('Id da ordem');
           LOrdem := FApp.Ordens.PorId(LOrdemId);

           Writeln;
           Writeln('  Operacoes do roteiro:');
           for LOperacao in LOrdem.Operacoes do
             Writeln('   ', LOperacao.Resumo);

           LSeq := LerInteiro('Sequencia da operacao', 10);
           LBoas := LerMoeda('Quantidade boa', 0);
           LRefugo := LerMoeda('Quantidade refugada', 0);
           LTempo := LerMoeda('Tempo gasto em minutos', 0);
           LMotivo := '';
           if LRefugo > 0 then
             LMotivo := LerTexto('Motivo do refugo');

           LResultado := FApp.Producao.Apontar(LOrdemId, LSeq, LBoas, LRefugo,
             LTempo, LerTexto('Operador', 'operador'), LMotivo);

           if LResultado.Sucesso then
             Sucesso('Apontado. Total produzido na ordem: %.2f',
               [LResultado.Valor])
           else
             Falha(LResultado.Erro);
           Pausa;
         end);
    6: Acao(
         procedure
         var
           LResultado: TResultado<TFechamentoOP>;
         begin
           ListarOrdens;
           LResultado := FApp.Producao.ConcluirOrdem(LerInteiro('Id da ordem'));
           if LResultado.Sucesso then
           begin
             Sucesso('Ordem concluida.');
             Writeln('       ', LResultado.Valor.Resumo);
           end
           else
             Falha(LResultado.Erro);
           Pausa;
         end);
    7: Acao(
         procedure
         var
           LOrdemId: Integer;
         begin
           ListarOrdens;
           LOrdemId := LerInteiro('Id da ordem');
           if Confirmar('Confirma o cancelamento?') then
           begin
             FApp.Producao.CancelarOrdem(LOrdemId,
               LerTexto('Motivo', 'nao informado'));
             Sucesso('Ordem cancelada e material devolvido ao estoque.');
           end;
         end);
  end;
end;

procedure TConsoleUI.MenuRelatoriosPCP;
begin
  case LerOpcao('Relatorios de PCP', ['Ordens de producao',
    'Estrutura explodida', 'Necessidade de materiais (MRP)',
    'Ficha de custo', 'Carga por centro de trabalho',
    'Eficiencia da producao', 'Voltar']) of
    0: Escrever(FRelatorios.OrdensAbertas);
    1: Acao(
         procedure
         begin
           ListarFabricados;
           Escrever(FRelatorios.EstruturaExplodida(LerInteiro('Id do item'),
             LerMoeda('Quantidade', 1)));
         end);
    2: Acao(
         procedure
         begin
           ListarFabricados;
           Escrever(FRelatorios.NecessidadeDeMateriais(
             LerInteiro('Id do item'), LerMoeda('Quantidade a produzir', 10)));
         end);
    3: Acao(
         procedure
         begin
           ListarFabricados;
           Escrever(FRelatorios.FichaDeCusto(LerInteiro('Id do item')));
         end);
    4: Escrever(FRelatorios.CargaDeTrabalho);
    5: Escrever(FRelatorios.EficienciaDeProducao);
  else
    Exit;
  end;
  Pausa;
end;

{ ---------------------------------------------------------------- sistema }

procedure TConsoleUI.MenuSistema;
begin
  case LerOpcao('Sistema', ['Salvar dados em JSON', 'Recarregar dados do disco',
    'Ver mural de eventos', 'Ver log da sessao', 'Ver regras de validacao',
    'Ver servicos registrados', 'Apagar dados salvos', 'Voltar']) of
    0: Acao(
         procedure
         begin
           FApp.Armazenamento.SalvarTudo;
           Sucesso('Dados gravados em: %s', [FApp.Armazenamento.Pasta]);
         end);
    1: Acao(
         procedure
         begin
           if FApp.Armazenamento.CarregarTudo then
             Sucesso('Dados recarregados do disco.')
           else
             Falha('Nao ha arquivos salvos ainda.');
         end);
    2: begin
         Cabecalho('MURAL DE EVENTOS DE DOMINIO');
         if Length(FApp.Mural) = 0 then
           Writeln('  (nenhum evento ainda)')
         else
           Escrever(FApp.Mural);
         Pausa;
       end;
    3: begin
         Cabecalho('LOG DA SESSAO');
         Escrever(FApp.LinhasDeLog);
         Pausa;
       end;
    4: begin
         Cabecalho('REGRAS DECLARADAS POR ATRIBUTOS (lidas via RTTI)');
         Writeln('  --- TCliente ---');
         Escrever(TValidador.DescreverRegras(TCliente));
         Writeln('  --- TProduto ---');
         Escrever(TValidador.DescreverRegras(TProduto));
         Writeln('  --- TItemPedido ---');
         Escrever(TValidador.DescreverRegras(TItemPedido));
         Pausa;
       end;
    5: begin
         Cabecalho('SERVICOS REGISTRADOS NO CONTAINER');
         Escrever(FApp.Container.Registros);
         Pausa;
       end;
    6: Acao(
         procedure
         begin
           if Confirmar('Apagar os arquivos JSON salvos?') then
           begin
             FApp.Armazenamento.Apagar;
             Sucesso('Arquivos apagados.');
           end;
         end);
  end;
end;

end.
