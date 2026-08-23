{*******************************************************************************
  App.Seed

  Carga de dados de exemplo para voce ter o que explorar no menu.

  ESTUDO:
    * Repare que o seed usa SOMENTE as interfaces publicas do dominio.
      Nada de "gambiarra" mexendo em campo privado.
    * O pedido 4 e criado ja com um cenario de erro proposital (estoque
      insuficiente) para voce ver o TResultado<T> em acao.
*******************************************************************************}
unit App.Seed;

interface

uses
  System.SysUtils,
  Core.Types,
  Domain.Entities,
  Domain.Enums,
  Domain.Producao,
  Domain.Producao.Services,
  App.Bootstrap;

type
  TSeed = class
  private
    class function NovoCliente(const ANome, ADoc, AEmail, ACidade, AUF: string;
      ACategoria: TCategoriaCliente; ALimite: Currency): TCliente; static;
    class function NovoProduto(const ACodigo, ADescricao, ACategoria: string;
      APreco: Currency; AEstoque, AMinimo: Integer): TProduto; static;
    class function NovoItem(AApp: TAplicacao; const ACodigo, ADescricao: string;
      ATipo: TTipoProduto; const AUnidade: string; ACusto: Currency;
      AEstoque, AMinimo: Integer): TProduto; static;
    class function NovoCentro(AApp: TAplicacao;
      const ACodigo, ADescricao: string; ACapacidade: Double;
      ACustoHora: Currency): TCentroTrabalho; static;
    class procedure PopularFabrica(AApp: TAplicacao); static;
  public
    class procedure Popular(AApp: TAplicacao); static;
  end;

implementation

{ TSeed }

class function TSeed.NovoCliente(const ANome, ADoc, AEmail, ACidade, AUF: string;
  ACategoria: TCategoriaCliente; ALimite: Currency): TCliente;
begin
  Result := TCliente.Create;
  Result.Nome := ANome;
  Result.Documento := ADoc;
  Result.Email := AEmail;
  Result.Cidade := ACidade;
  Result.UF := AUF;
  Result.Categoria := ACategoria;
  Result.LimiteCredito := ALimite;
  Result.Telefone := '(11) 90000-0000';
end;

class function TSeed.NovoProduto(const ACodigo, ADescricao, ACategoria: string;
  APreco: Currency; AEstoque, AMinimo: Integer): TProduto;
begin
  Result := TProduto.Create;
  Result.Codigo := ACodigo;
  Result.Descricao := ADescricao;
  Result.Categoria := ACategoria;
  Result.Preco := APreco;
  Result.Estoque := AEstoque;
  Result.EstoqueMinimo := AMinimo;
end;

class procedure TSeed.Popular(AApp: TAplicacao);
var
  LPedido: TPedido;
begin
  if AApp.Clientes.Contar > 0 then
    Exit; // ja existem dados carregados

  // ------------------------------------------------------------- CLIENTES
  AApp.Clientes.Adicionar(NovoCliente('Mercado Sao Jorge Ltda',
    '12345678000199', 'compras@saojorge.com.br', 'Sao Paulo', 'SP',
    ccOuro, 30000));
  AApp.Clientes.Adicionar(NovoCliente('Ana Paula Ferreira',
    '52998224725', 'ana.ferreira@email.com', 'Campinas', 'SP',
    ccPrata, 5000));
  AApp.Clientes.Adicionar(NovoCliente('Distribuidora Norte SA',
    '98765432000188', 'pedidos@norte.com.br', 'Belem', 'PA',
    ccVip, 80000));
  AApp.Clientes.Adicionar(NovoCliente('Carlos Eduardo Lima',
    '11144477735', 'carlos.lima@email.com', 'Curitiba', 'PR',
    ccComum, 1500));
  AApp.Clientes.Adicionar(NovoCliente('Padaria Do Bairro ME',
    '11222333000181', 'contato@padariadobairro.com', 'Santos', 'SP',
    ccComum, 800));

  // ------------------------------------------------------------- PRODUTOS
  AApp.Produtos.Adicionar(NovoProduto('NB-1420', 'Notebook 14" 16GB',
    'Informatica', 4299.90, 12, 4));
  AApp.Produtos.Adicionar(NovoProduto('MON-27U', 'Monitor 27" UltraWide',
    'Informatica', 1899.00, 8, 3));
  AApp.Produtos.Adicionar(NovoProduto('TEC-MEC', 'Teclado mecanico ABNT2',
    'Perifericos', 349.90, 40, 10));
  AApp.Produtos.Adicionar(NovoProduto('MOU-ERG', 'Mouse ergonomico sem fio',
    'Perifericos', 189.90, 55, 15));
  AApp.Produtos.Adicionar(NovoProduto('SSD-1TB', 'SSD NVMe 1TB',
    'Componentes', 529.00, 25, 8));
  AApp.Produtos.Adicionar(NovoProduto('RAM-16G', 'Memoria DDR4 16GB',
    'Componentes', 289.00, 3, 10));   // ja nasce abaixo do minimo!
  AApp.Produtos.Adicionar(NovoProduto('CAD-A4', 'Cadeira ergonomica',
    'Mobiliario', 1249.00, 6, 2));
  AApp.Produtos.Adicionar(NovoProduto('HUB-USBC', 'Hub USB-C 7 portas',
    'Perifericos', 279.90, 2, 5));    // quase esgotado

  // -------------------------------------------------------------- PEDIDOS
  // Pedido 1: cliente Ouro, confirmado, pago e entregue (fluxo feliz completo)
  LPedido := AApp.Vendas.CriarPedido(1);
  AApp.Vendas.AdicionarItem(LPedido.Id, 1, 2);
  AApp.Vendas.AdicionarItem(LPedido.Id, 3, 4);
  AApp.Vendas.ConfirmarPedido(LPedido.Id);
  AApp.Vendas.PagarPedido(LPedido.Id, fpPix);
  AApp.Vendas.EnviarPedido(LPedido.Id);
  AApp.Vendas.EntregarPedido(LPedido.Id);

  // Pedido 2: cliente VIP, confirmado (reservando estoque) e aguardando pgto
  LPedido := AApp.Vendas.CriarPedido(3);
  AApp.Vendas.AdicionarItem(LPedido.Id, 5, 10);
  AApp.Vendas.AdicionarItem(LPedido.Id, 4, 12);
  AApp.Vendas.ConfirmarPedido(LPedido.Id);

  // Pedido 3: em rascunho, para voce brincar no menu
  LPedido := AApp.Vendas.CriarPedido(2);
  AApp.Vendas.AdicionarItem(LPedido.Id, 2, 1);
  AApp.Vendas.AdicionarItem(LPedido.Id, 4, 2, 0.05); // 5% de desconto no item

  // Pedido 4: pede mais do que existe -> ConfirmarPedido devolve Falha
  LPedido := AApp.Vendas.CriarPedido(5);
  AApp.Vendas.AdicionarItem(LPedido.Id, 8, 50);      // so ha 2 em estoque

  // ------------------------------------------------------- CHAO DE FABRICA
  PopularFabrica(AApp);

  AApp.Logger.Info('Dados de exemplo carregados: %d clientes, %d produtos, ' +
    '%d pedidos, %d centros, %d ordens.',
    [AApp.Clientes.Contar, AApp.Produtos.Contar, AApp.Pedidos.Contar,
     AApp.Centros.Contar, AApp.Ordens.Contar]);
end;

class function TSeed.NovoItem(AApp: TAplicacao;
  const ACodigo, ADescricao: string; ATipo: TTipoProduto;
  const AUnidade: string; ACusto: Currency;
  AEstoque, AMinimo: Integer): TProduto;
begin
  Result := TProduto.Create;
  Result.Codigo := ACodigo;
  Result.Descricao := ADescricao;
  Result.Categoria := 'Fabrica';
  Result.Tipo := ATipo;
  Result.Unidade := AUnidade;
  Result.CustoMedio := ACusto;
  // Preco de venda so faz sentido no acabado; nos demais e referencia.
  Result.Preco := ACusto * 2;
  Result.Estoque := AEstoque;
  Result.EstoqueMinimo := AMinimo;
  Result.LeadTimeDias := 5;
  AApp.Produtos.Adicionar(Result);
end;

class function TSeed.NovoCentro(AApp: TAplicacao;
  const ACodigo, ADescricao: string; ACapacidade: Double;
  ACustoHora: Currency): TCentroTrabalho;
begin
  Result := TCentroTrabalho.Create;
  Result.Codigo := ACodigo;
  Result.Descricao := ADescricao;
  Result.CapacidadeHorasDia := ACapacidade;
  Result.CustoHora := ACustoHora;
  AApp.Centros.Adicionar(Result);
end;

{ Uma fabrica de mesas, pequena mas com tudo que um PCP precisa:
  materia-prima comprada, um semiacabado FABRICADO, um produto acabado,
  estrutura em DOIS NIVEIS e roteiro passando por tres centros. }
class procedure TSeed.PopularFabrica(AApp: TAplicacao);
var
  LCorte, LMontagem, LEmbalagem: TCentroTrabalho;
  LMdf, LVerniz, LPe, LParafuso, LCaixa: TProduto;
  LTampo, LMesa: TProduto;
begin
  if AApp.Centros.Contar > 0 then
    Exit;

  // --------------------------------------------------- centros de trabalho
  LCorte := NovoCentro(AApp, 'CT-CORTE', 'Serra esquadrejadeira', 8, 95.00);
  LMontagem := NovoCentro(AApp, 'CT-MONT', 'Bancada de montagem', 16, 62.50);
  LEmbalagem := NovoCentro(AApp, 'CT-EMB', 'Linha de embalagem', 8, 38.00);

  // ------------------------------------------------------- materia-prima
  LMdf := NovoItem(AApp, 'CHAPA-MDF', 'Chapa MDF 18mm 2750x1840',
    tpMateriaPrima, 'M2', 85.00, 120, 30);
  LVerniz := NovoItem(AApp, 'VERNIZ-PU', 'Verniz poliuretano',
    tpMateriaPrima, 'L', 42.00, 60, 20);
  LPe := NovoItem(AApp, 'PE-METAL', 'Pe metalico 70cm',
    tpMateriaPrima, 'UN', 18.50, 400, 100);
  LParafuso := NovoItem(AApp, 'PARAF-4X40', 'Parafuso 4x40mm',
    tpMateriaPrima, 'UN', 0.35, 5000, 1000);
  LCaixa := NovoItem(AApp, 'CX-PAPELAO', 'Caixa de papelao 130x80',
    tpMateriaPrima, 'UN', 6.20, 150, 40);

  // -------------------------------------- semiacabado e produto acabado
  LTampo := NovoItem(AApp, 'TAMPO-120', 'Tampo envernizado 120x60',
    tpIntermediario, 'UN', 0, 20, 5);
  LMesa := NovoItem(AApp, 'MESA-120', 'Mesa de escritorio 120x60',
    tpAcabado, 'UN', 0, 0, 3);
  LMesa.Preco := 890.00;

  { ------------------------------ ESTRUTURA (BOM) -------------------------
    Nivel 1: a mesa leva 1 tampo + 4 pes + 16 parafusos + 1 caixa
    Nivel 2: o tampo leva 1,2 m2 de MDF (com 5% de perda de corte) + verniz
    Repare que o MDF aparece so no segundo nivel: a explosao multinivel e
    que revela a necessidade real de chapa para fabricar uma mesa. }
  AApp.Engenharia.DefinirComponente(LTampo.Id, LMdf.Id, 1.2, 0.05);
  AApp.Engenharia.DefinirComponente(LTampo.Id, LVerniz.Id, 0.25);

  AApp.Engenharia.DefinirComponente(LMesa.Id, LTampo.Id, 1);
  AApp.Engenharia.DefinirComponente(LMesa.Id, LPe.Id, 4);
  AApp.Engenharia.DefinirComponente(LMesa.Id, LParafuso.Id, 16, 0.02);
  AApp.Engenharia.DefinirComponente(LMesa.Id, LCaixa.Id, 1);

  // ------------------------------------ ROTEIRO DE FABRICACAO ------------
  AApp.Engenharia.DefinirOperacao(LTampo.Id, 10, 'Corte da chapa',
    LCorte.Id, 15, 4.0);
  AApp.Engenharia.DefinirOperacao(LTampo.Id, 20, 'Envernizamento',
    LMontagem.Id, 10, 6.0);

  AApp.Engenharia.DefinirOperacao(LMesa.Id, 10, 'Montagem da mesa',
    LMontagem.Id, 10, 12.0);
  AApp.Engenharia.DefinirOperacao(LMesa.Id, 20, 'Embalagem',
    LEmbalagem.Id, 5, 3.0);

  { Custo padrao do semiacabado calculado pelo roll-up; gravamos no cadastro
    para que a mesa seja custeada corretamente. }
  LTampo.CustoMedio := AApp.Engenharia.CustoPadrao(LTampo.Id);
  AApp.Produtos.Atualizar(LTampo);

  // Uma ordem ja aberta, para o menu ter o que mostrar.
  AApp.Producao.CriarOrdem(LMesa.Id, 10, Date + 3);
end;

end.
