{*******************************************************************************
  Infra.Mapping

  Um mini-ORM: descobre por RTTI quais propriedades da entidade viram colunas
  e monta o SQL (SELECT/INSERT/UPDATE/DELETE) sozinho.

  DECISAO DE ARQUITETURA IMPORTANTE
  ---------------------------------
  Muitos ORMs (Hibernate, Entity Framework, e varios em Delphi) pedem que voce
  anote a ENTIDADE:

      [Tabela('PRODUTOS')]
      TProduto = class ...
        [Coluna('CUSTO_MEDIO')]
        property CustoMedio: Currency ...

  E pratico, mas fura a arquitetura que este projeto defende: o dominio
  passaria a saber que existe banco, tabela e coluna. Aqui o mapeamento mora
  na INFRA - o dominio continua sem saber se e gravado em Firebird, em JSON
  ou em nada.

  Preco pago: o mapa precisa ser registrado a mao (ver RegistrarMapeamentos).
  Ganho: Domain.Entities nao muda uma linha se o banco mudar.

  CONVENCAO: coluna = nome da propriedade em MAIUSCULAS.
  Assim o mapa automatico acerta tudo e so listamos o que deve ser IGNORADO.

  ESTUDO:
    * RTTI para inspecionar propriedades em tempo de execucao
    * Geracao de SQL parametrizado (nunca por concatenacao de valores:
      isso e o que evita SQL injection)
    * Um registro global com finalizacao correta
*******************************************************************************}
unit Infra.Mapping;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  Core.Types;

type
  TMapaColuna = record
    Propriedade: string;
    Coluna: string;
    EhChave: Boolean;
  end;

  TMapaTabela = class
  private
    FClasse: TClass;
    FTabela: string;
    FGenerator: string;
    FColunas: TList<TMapaColuna>;
    FColunaChave: string;
    function Juntar(const ASufixo: string; AIncluirChave: Boolean;
      const ASeparador: string = ', '): string;
  public
    constructor Create(AClasse: TClass; const ATabela, AGenerator: string;
      const AColunaChave: string = 'ID');
    destructor Destroy; override;

    /// Mapeia automaticamente as propriedades publicas escalares.
    /// AIgnorar lista propriedades que NAO tem coluna (calculadas, colecoes).
    procedure MapearAutomatico(const AIgnorar: array of string);
    procedure Adicionar(const APropriedade: string; const AColuna: string = '');

    function Colunas: TArray<TMapaColuna>;
    function TemColuna(const AColuna: string): Boolean;

    // ---- SQL gerado ----
    function SqlSelect: string;
    function SqlSelectPorId: string;
    function SqlInsert: string;
    function SqlUpdate: string;
    function SqlDelete: string;
    function SqlContar: string;
    function SqlExiste: string;
    function SqlApagarTudo: string;

    property Classe: TClass read FClasse;
    property Tabela: string read FTabela;
    property Generator: string read FGenerator;
    property ColunaChave: string read FColunaChave;
  end;

  /// Registro central: "para esta classe, use este mapa".
  TMapeamento = class
  public
    class procedure Registrar(AMapa: TMapaTabela); static;
    class function Para(AClasse: TClass): TMapaTabela; static;
    class function Existe(AClasse: TClass): Boolean; static;
    class function Tabelas: TArray<string>; static;
    class procedure Limpar; static;
  end;

implementation

var
  GMapas: TObjectDictionary<TClass, TMapaTabela> = nil;

function ObterMapas: TObjectDictionary<TClass, TMapaTabela>;
begin
  if GMapas = nil then
    GMapas := TObjectDictionary<TClass, TMapaTabela>.Create([doOwnsValues]);
  Result := GMapas;
end;

{ TMapaTabela }

constructor TMapaTabela.Create(AClasse: TClass;
  const ATabela, AGenerator, AColunaChave: string);
begin
  inherited Create;
  FClasse := AClasse;
  FTabela := ATabela;
  FGenerator := AGenerator;
  FColunaChave := AColunaChave;
  FColunas := TList<TMapaColuna>.Create;
end;

destructor TMapaTabela.Destroy;
begin
  FColunas.Free;
  inherited;
end;

procedure TMapaTabela.Adicionar(const APropriedade, AColuna: string);
var
  LColuna: TMapaColuna;
begin
  LColuna.Propriedade := APropriedade;
  if AColuna <> '' then
    LColuna.Coluna := AColuna
  else
    LColuna.Coluna := UpperCase(APropriedade);
  LColuna.EhChave := SameText(LColuna.Coluna, FColunaChave);
  FColunas.Add(LColuna);
end;

procedure TMapaTabela.MapearAutomatico(const AIgnorar: array of string);
const
  // Tipos que viram coluna. O resto (objeto, colecao, metodo) fica de fora.
  TIPOS_ESCALARES = [tkInteger, tkInt64, tkFloat, tkString, tkUString,
                     tkLString, tkWString, tkEnumeration, tkChar, tkWChar];
var
  LCtx: TRttiContext;
  LProp: TRttiProperty;
  LNome: string;
  LIgnorado: Boolean;
begin
  LCtx := TRttiContext.Create;
  try
    for LProp in LCtx.GetType(FClasse).GetProperties do
    begin
      // Somente leitura => e valor calculado => nao tem coluna.
      if (not LProp.IsReadable) or (not LProp.IsWritable) then
        Continue;
      if LProp.Visibility < mvPublic then
        Continue;
      if not (LProp.PropertyType.TypeKind in TIPOS_ESCALARES) then
        Continue;

      LIgnorado := False;
      for LNome in AIgnorar do
        if SameText(LNome, LProp.Name) then
        begin
          LIgnorado := True;
          Break;
        end;
      if LIgnorado then
        Continue;

      Adicionar(LProp.Name);
    end;
  finally
    LCtx.Free;
  end;
end;

function TMapaTabela.Colunas: TArray<TMapaColuna>;
begin
  Result := FColunas.ToArray;
end;

function TMapaTabela.TemColuna(const AColuna: string): Boolean;
var
  LColuna: TMapaColuna;
begin
  for LColuna in FColunas do
    if SameText(LColuna.Coluna, AColuna) then
      Exit(True);
  Result := False;
end;

function TMapaTabela.Juntar(const ASufixo: string; AIncluirChave: Boolean;
  const ASeparador: string): string;
var
  LColuna: TMapaColuna;
  LBuilder: TStringBuilder;
begin
  LBuilder := TStringBuilder.Create;
  try
    for LColuna in FColunas do
    begin
      if LColuna.EhChave and (not AIncluirChave) then
        Continue;
      if LBuilder.Length > 0 then
        LBuilder.Append(ASeparador);

      if ASufixo = '' then
        LBuilder.Append(LColuna.Coluna)                       // A, B
      else if ASufixo = ':' then
        LBuilder.Append(':').Append(LColuna.Coluna)           // :A, :B
      else
        LBuilder.Append(LColuna.Coluna).Append(' = :')
                .Append(LColuna.Coluna);                      // A = :A
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TMapaTabela.SqlSelect: string;
begin
  Result := Format('SELECT %s FROM %s', [Juntar('', True), FTabela]);
end;

function TMapaTabela.SqlSelectPorId: string;
begin
  Result := Format('%s WHERE %s = :%s', [SqlSelect, FColunaChave, FColunaChave]);
end;

function TMapaTabela.SqlInsert: string;
begin
  Result := Format('INSERT INTO %s (%s) VALUES (%s)',
    [FTabela, Juntar('', True), Juntar(':', True)]);
end;

function TMapaTabela.SqlUpdate: string;
begin
  Result := Format('UPDATE %s SET %s WHERE %s = :%s',
    [FTabela, Juntar('=', False), FColunaChave, FColunaChave]);
end;

function TMapaTabela.SqlDelete: string;
begin
  Result := Format('DELETE FROM %s WHERE %s = :%s',
    [FTabela, FColunaChave, FColunaChave]);
end;

function TMapaTabela.SqlContar: string;
begin
  Result := Format('SELECT COUNT(*) FROM %s', [FTabela]);
end;

function TMapaTabela.SqlExiste: string;
begin
  Result := Format('SELECT 1 FROM %s WHERE %s = :%s',
    [FTabela, FColunaChave, FColunaChave]);
end;

function TMapaTabela.SqlApagarTudo: string;
begin
  Result := Format('DELETE FROM %s', [FTabela]);
end;

{ TMapeamento }

class procedure TMapeamento.Registrar(AMapa: TMapaTabela);
begin
  if AMapa = nil then
    raise EInfra.Create('Mapa nulo.');
  ObterMapas.AddOrSetValue(AMapa.Classe, AMapa);
end;

class function TMapeamento.Para(AClasse: TClass): TMapaTabela;
begin
  if not ObterMapas.TryGetValue(AClasse, Result) then
    raise EInfra.CreateFmt(
      'Nao existe mapeamento de tabela para a classe %s. ' +
      'Registre em Infra.Mapping.RegistrarMapeamentos.', [AClasse.ClassName]);
end;

class function TMapeamento.Existe(AClasse: TClass): Boolean;
begin
  Result := ObterMapas.ContainsKey(AClasse);
end;

class function TMapeamento.Tabelas: TArray<string>;
var
  LMapa: TMapaTabela;
  LLista: TList<string>;
begin
  LLista := TList<string>.Create;
  try
    for LMapa in ObterMapas.Values do
      LLista.Add(LMapa.Tabela);
    Result := LLista.ToArray;
  finally
    LLista.Free;
  end;
end;

class procedure TMapeamento.Limpar;
begin
  if GMapas <> nil then
    GMapas.Clear;
end;

initialization

finalization
  FreeAndNil(GMapas);

end.
