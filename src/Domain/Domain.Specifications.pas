{*******************************************************************************
  Domain.Specifications

  Padrao SPECIFICATION: transforma uma regra de "quem se encaixa" em um OBJETO
  que pode ser nomeado, testado isoladamente e COMBINADO com outros.

  Em vez de espalhar filtros:
      for P in Todos do
        if (P.Ativo) and (P.Estoque < P.EstoqueMinimo) then ...

  escrevemos:
      Repo.Buscar(TProdutoAtivo.Create.E(TProdutoAbaixoMinimo.Create));

  ESTUDO:
    * Interfaces genericas (ISpecification<T>) - repare que elas NAO tem GUID:
      interfaces genericas nao podem ser usadas com Supports/QueryInterface
    * Composicao (E / Ou / Nao) formando uma arvore de decisao
    * Ponte com metodos anonimos via TEspecDe<T>.Predicado
*******************************************************************************}
unit Domain.Specifications;

interface

uses
  System.SysUtils,
  System.DateUtils,
  Domain.Entities,
  Domain.Enums;

type
  { Delegate proprio em vez de TPredicate<T> da RTL: TPredicate<T> declara o
    parametro SEM "const", o que forcaria uma copia a cada avaliacao e nao
    casaria com a assinatura de ISpecification. Assinaturas de metodos
    anonimos precisam bater EXATAMENTE, inclusive nos modificadores. }
  TFiltro<T> = reference to function(const AItem: T): Boolean;

  ISpecification<T> = interface
    function Satisfeita(const AItem: T): Boolean;
    function Nome: string;
  end;

  /// Base com os operadores de composicao ja prontos.
  TEspec<T> = class abstract(TInterfacedObject, ISpecification<T>)
  public
    function Satisfeita(const AItem: T): Boolean; virtual; abstract;
    function Nome: string; virtual;
    function E(const AOutra: ISpecification<T>): ISpecification<T>;
    function Ou(const AOutra: ISpecification<T>): ISpecification<T>;
    function Nao: ISpecification<T>;
  end;

  TEspecE<T> = class(TEspec<T>)
  private
    FA, FB: ISpecification<T>;
  public
    constructor Create(const AA, AB: ISpecification<T>);
    function Satisfeita(const AItem: T): Boolean; override;
    function Nome: string; override;
  end;

  TEspecOu<T> = class(TEspec<T>)
  private
    FA, FB: ISpecification<T>;
  public
    constructor Create(const AA, AB: ISpecification<T>);
    function Satisfeita(const AItem: T): Boolean; override;
    function Nome: string; override;
  end;

  TEspecNao<T> = class(TEspec<T>)
  private
    FInterna: ISpecification<T>;
  public
    constructor Create(const AInterna: ISpecification<T>);
    function Satisfeita(const AItem: T): Boolean; override;
    function Nome: string; override;
  end;

  /// Aceita tudo. Util como valor neutro ("sem filtro").
  TEspecTudo<T> = class(TEspec<T>)
  public
    function Satisfeita(const AItem: T): Boolean; override;
    function Nome: string; override;
  end;

  /// Ponte entre metodo anonimo e specification.
  TEspecDe<T> = class(TEspec<T>)
  private
    FPredicado: TFiltro<T>;
    FNome: string;
  public
    constructor Create(const APredicado: TFiltro<T>; const ANome: string = 'lambda');
    function Satisfeita(const AItem: T): Boolean; override;
    function Nome: string; override;
    class function Nova(const APredicado: TFiltro<T>;
      const ANome: string = 'lambda'): ISpecification<T>; static;
  end;

  { ---------------------- Specifications concretas ---------------------- }

  TProdutoAtivo = class(TEspec<TProduto>)
  public
    function Satisfeita(const AItem: TProduto): Boolean; override;
    function Nome: string; override;
  end;

  TProdutoAbaixoMinimo = class(TEspec<TProduto>)
  public
    function Satisfeita(const AItem: TProduto): Boolean; override;
    function Nome: string; override;
  end;

  TProdutoDaCategoria = class(TEspec<TProduto>)
  private
    FCategoria: string;
  public
    constructor Create(const ACategoria: string);
    function Satisfeita(const AItem: TProduto): Boolean; override;
    function Nome: string; override;
  end;

  TProdutoAcimaDe = class(TEspec<TProduto>)
  private
    FPreco: Currency;
  public
    constructor Create(APreco: Currency);
    function Satisfeita(const AItem: TProduto): Boolean; override;
    function Nome: string; override;
  end;

  TClienteAtivo = class(TEspec<TCliente>)
  public
    function Satisfeita(const AItem: TCliente): Boolean; override;
    function Nome: string; override;
  end;

  TClienteDaCategoria = class(TEspec<TCliente>)
  private
    FCategoria: TCategoriaCliente;
  public
    constructor Create(ACategoria: TCategoriaCliente);
    function Satisfeita(const AItem: TCliente): Boolean; override;
    function Nome: string; override;
  end;

  TClienteDaUF = class(TEspec<TCliente>)
  private
    FUF: string;
  public
    constructor Create(const AUF: string);
    function Satisfeita(const AItem: TCliente): Boolean; override;
    function Nome: string; override;
  end;

  TPedidoComStatus = class(TEspec<TPedido>)
  private
    FStatus: TStatusPedidoSet;
  public
    constructor Create(const AStatus: TStatusPedidoSet);
    function Satisfeita(const AItem: TPedido): Boolean; override;
    function Nome: string; override;
  end;

  TPedidoDoCliente = class(TEspec<TPedido>)
  private
    FClienteId: Integer;
  public
    constructor Create(AClienteId: Integer);
    function Satisfeita(const AItem: TPedido): Boolean; override;
    function Nome: string; override;
  end;

  TPedidoNoPeriodo = class(TEspec<TPedido>)
  private
    FInicio, FFim: TDateTime;
  public
    constructor Create(AInicio, AFim: TDateTime);
    function Satisfeita(const AItem: TPedido): Boolean; override;
    function Nome: string; override;
  end;

  TPedidoAcimaDe = class(TEspec<TPedido>)
  private
    FValor: Currency;
  public
    constructor Create(AValor: Currency);
    function Satisfeita(const AItem: TPedido): Boolean; override;
    function Nome: string; override;
  end;

implementation

uses
  Core.Types;

{ TEspec<T> }

function TEspec<T>.Nome: string;
begin
  Result := ClassName;
end;

function TEspec<T>.E(const AOutra: ISpecification<T>): ISpecification<T>;
begin
  Result := TEspecE<T>.Create(Self, AOutra);
end;

function TEspec<T>.Ou(const AOutra: ISpecification<T>): ISpecification<T>;
begin
  Result := TEspecOu<T>.Create(Self, AOutra);
end;

function TEspec<T>.Nao: ISpecification<T>;
begin
  Result := TEspecNao<T>.Create(Self);
end;

{ TEspecE<T> }

constructor TEspecE<T>.Create(const AA, AB: ISpecification<T>);
begin
  inherited Create;
  FA := AA;
  FB := AB;
end;

function TEspecE<T>.Satisfeita(const AItem: T): Boolean;
begin
  // avaliacao curto-circuito: se FA falhar, FB nem e chamada
  Result := FA.Satisfeita(AItem) and FB.Satisfeita(AItem);
end;

function TEspecE<T>.Nome: string;
begin
  Result := Format('(%s E %s)', [FA.Nome, FB.Nome]);
end;

{ TEspecOu<T> }

constructor TEspecOu<T>.Create(const AA, AB: ISpecification<T>);
begin
  inherited Create;
  FA := AA;
  FB := AB;
end;

function TEspecOu<T>.Satisfeita(const AItem: T): Boolean;
begin
  Result := FA.Satisfeita(AItem) or FB.Satisfeita(AItem);
end;

function TEspecOu<T>.Nome: string;
begin
  Result := Format('(%s OU %s)', [FA.Nome, FB.Nome]);
end;

{ TEspecNao<T> }

constructor TEspecNao<T>.Create(const AInterna: ISpecification<T>);
begin
  inherited Create;
  FInterna := AInterna;
end;

function TEspecNao<T>.Satisfeita(const AItem: T): Boolean;
begin
  Result := not FInterna.Satisfeita(AItem);
end;

function TEspecNao<T>.Nome: string;
begin
  Result := Format('(NAO %s)', [FInterna.Nome]);
end;

{ TEspecTudo<T> }

function TEspecTudo<T>.Satisfeita(const AItem: T): Boolean;
begin
  Result := True;
end;

function TEspecTudo<T>.Nome: string;
begin
  Result := 'tudo';
end;

{ TEspecDe<T> }

constructor TEspecDe<T>.Create(const APredicado: TFiltro<T>; const ANome: string);
begin
  inherited Create;
  FPredicado := APredicado;
  FNome := ANome;
end;

class function TEspecDe<T>.Nova(const APredicado: TFiltro<T>;
  const ANome: string): ISpecification<T>;
begin
  Result := TEspecDe<T>.Create(APredicado, ANome);
end;

function TEspecDe<T>.Satisfeita(const AItem: T): Boolean;
begin
  Result := Assigned(FPredicado) and FPredicado(AItem);
end;

function TEspecDe<T>.Nome: string;
begin
  Result := FNome;
end;

{ TProdutoAtivo }

function TProdutoAtivo.Satisfeita(const AItem: TProduto): Boolean;
begin
  Result := (AItem <> nil) and AItem.Ativo;
end;

function TProdutoAtivo.Nome: string;
begin
  Result := 'produto ativo';
end;

{ TProdutoAbaixoMinimo }

function TProdutoAbaixoMinimo.Satisfeita(const AItem: TProduto): Boolean;
begin
  Result := (AItem <> nil) and AItem.AbaixoDoMinimo;
end;

function TProdutoAbaixoMinimo.Nome: string;
begin
  Result := 'estoque abaixo do minimo';
end;

{ TProdutoDaCategoria }

constructor TProdutoDaCategoria.Create(const ACategoria: string);
begin
  inherited Create;
  FCategoria := ACategoria;
end;

function TProdutoDaCategoria.Satisfeita(const AItem: TProduto): Boolean;
begin
  Result := (AItem <> nil) and SameText(AItem.Categoria, FCategoria);
end;

function TProdutoDaCategoria.Nome: string;
begin
  Result := 'categoria = ' + FCategoria;
end;

{ TProdutoAcimaDe }

constructor TProdutoAcimaDe.Create(APreco: Currency);
begin
  inherited Create;
  FPreco := APreco;
end;

function TProdutoAcimaDe.Satisfeita(const AItem: TProduto): Boolean;
begin
  Result := (AItem <> nil) and (AItem.Preco >= FPreco);
end;

function TProdutoAcimaDe.Nome: string;
begin
  Result := 'preco >= ' + TFmt.Moeda(FPreco);
end;

{ TClienteAtivo }

function TClienteAtivo.Satisfeita(const AItem: TCliente): Boolean;
begin
  Result := (AItem <> nil) and AItem.Ativo;
end;

function TClienteAtivo.Nome: string;
begin
  Result := 'cliente ativo';
end;

{ TClienteDaCategoria }

constructor TClienteDaCategoria.Create(ACategoria: TCategoriaCliente);
begin
  inherited Create;
  FCategoria := ACategoria;
end;

function TClienteDaCategoria.Satisfeita(const AItem: TCliente): Boolean;
begin
  Result := (AItem <> nil) and (AItem.Categoria = FCategoria);
end;

function TClienteDaCategoria.Nome: string;
begin
  Result := 'categoria = ' + CategoriaClienteDescr(FCategoria);
end;

{ TClienteDaUF }

constructor TClienteDaUF.Create(const AUF: string);
begin
  inherited Create;
  FUF := AUF;
end;

function TClienteDaUF.Satisfeita(const AItem: TCliente): Boolean;
begin
  Result := (AItem <> nil) and SameText(AItem.UF, FUF);
end;

function TClienteDaUF.Nome: string;
begin
  Result := 'UF = ' + FUF;
end;

{ TPedidoComStatus }

constructor TPedidoComStatus.Create(const AStatus: TStatusPedidoSet);
begin
  inherited Create;
  FStatus := AStatus;
end;

function TPedidoComStatus.Satisfeita(const AItem: TPedido): Boolean;
begin
  Result := (AItem <> nil) and (AItem.Status in FStatus);
end;

function TPedidoComStatus.Nome: string;
begin
  Result := 'status do pedido';
end;

{ TPedidoDoCliente }

constructor TPedidoDoCliente.Create(AClienteId: Integer);
begin
  inherited Create;
  FClienteId := AClienteId;
end;

function TPedidoDoCliente.Satisfeita(const AItem: TPedido): Boolean;
begin
  Result := (AItem <> nil) and (AItem.ClienteId = FClienteId);
end;

function TPedidoDoCliente.Nome: string;
begin
  Result := Format('cliente = %d', [FClienteId]);
end;

{ TPedidoNoPeriodo }

constructor TPedidoNoPeriodo.Create(AInicio, AFim: TDateTime);
begin
  inherited Create;
  FInicio := DateOf(AInicio);
  FFim := DateOf(AFim);
end;

function TPedidoNoPeriodo.Satisfeita(const AItem: TPedido): Boolean;
var
  LData: TDate;
begin
  if AItem = nil then
    Exit(False);
  LData := DateOf(AItem.CriadoEm);
  Result := (LData >= FInicio) and (LData <= FFim);
end;

function TPedidoNoPeriodo.Nome: string;
begin
  Result := Format('periodo %s a %s', [TFmt.Data(FInicio), TFmt.Data(FFim)]);
end;

{ TPedidoAcimaDe }

constructor TPedidoAcimaDe.Create(AValor: Currency);
begin
  inherited Create;
  FValor := AValor;
end;

function TPedidoAcimaDe.Satisfeita(const AItem: TPedido): Boolean;
begin
  Result := (AItem <> nil) and (AItem.TotalLiquido >= FValor);
end;

function TPedidoAcimaDe.Nome: string;
begin
  Result := 'total >= ' + TFmt.Moeda(FValor);
end;

end.
