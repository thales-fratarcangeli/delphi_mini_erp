{*******************************************************************************
  Core.Types

  Tipos fundamentais compartilhados por todas as camadas.

  ESTUDO - conceitos demonstrados aqui:
    * Hierarquia de excecoes customizadas (herdando de Exception)
    * Records avancados com metodos e class functions (TResultado<T>)
    * Generics em records + o padrao "Result" (alternativa a excecoes)
    * RTTI basico para converter enumerados <-> string (TEnumUtils)
*******************************************************************************}
unit Core.Types;

interface

uses
  System.SysUtils,
  System.TypInfo,
  System.Rtti;

type
  { --------------------------------------------------------------------------
    HIERARQUIA DE EXCECOES
    Uma boa hierarquia permite capturar por "familia":
      try ... except on E: EDominio do ... end;  // pega qualquer erro de negocio
    -------------------------------------------------------------------------- }
  EAppException = class(Exception);

  /// Erros de regra de negocio (culpa do usuario / dos dados)
  EDominio = class(EAppException);

  /// Falha de validacao: carrega a lista completa de problemas encontrados
  EValidacao = class(EDominio)
  private
    FErros: TArray<string>;
  public
    constructor Create(const AErros: TArray<string>); reintroduce;
    property Erros: TArray<string> read FErros;
  end;

  /// Entidade nao encontrada no repositorio
  ENaoEncontrado = class(EDominio)
  public
    constructor Create(const AEntidade: string; AId: Integer); reintroduce;
  end;

  /// Erros de infraestrutura (arquivo, banco, rede)
  EInfra = class(EAppException);

  /// Erros de configuracao do container de injecao de dependencia
  EConfiguracao = class(EAppException);

  { --------------------------------------------------------------------------
    TResultado<T> - o padrao "Result"

    Em vez de lancar excecao para TODO erro esperado, devolvemos um valor que
    diz "deu certo" ou "deu errado + motivo". Excecoes ficam para o inesperado.

      var R := TServico.Fazer;
      if R.Sucesso then ShowMessage(R.Valor.ToString) else ShowMessage(R.Erro);
    -------------------------------------------------------------------------- }
  TResultado<T> = record
  private
    FSucesso: Boolean;
    FValor: T;
    FErro: string;
  public
    class function Ok(const AValor: T): TResultado<T>; static;
    class function Falha(const AErro: string): TResultado<T>; static;
    class function FalhaFmt(const AErro: string;
      const AArgs: array of const): TResultado<T>; static;

    /// Retorna o valor ou, se falhou, o padrao informado (evita if espalhado)
    function ValorOu(const APadrao: T): T;
    /// Executa a acao somente em caso de sucesso; devolve self para encadear
    function SeOk(const AAcao: TProc<T>): TResultado<T>;
    /// Executa a acao somente em caso de falha; devolve self para encadear
    function SeErro(const AAcao: TProc<string>): TResultado<T>;
    /// Lanca EDominio se o resultado for falha; senao devolve o valor
    function ValorOuFalhar: T;

    property Sucesso: Boolean read FSucesso;
    property Valor: T read FValor;
    property Erro: string read FErro;
  end;

  { Par generico chave/valor. Existe porque devolver um TDictionary de um
    metodo obriga o chamador a destrui-lo; um array de records nao. }
  TPar<K, V> = record
    Chave: K;
    Valor: V;
    class function Criar(const AChave: K; const AValor: V): TPar<K, V>; static;
  end;

  { --------------------------------------------------------------------------
    TEnumUtils - conversao generica de enumerados usando RTTI.
    Funciona para QUALQUER enum sem escrever um "case" para cada um.
    -------------------------------------------------------------------------- }
  TEnumUtils = class
  public
    class function ParaTexto<T>(const AValor: T): string; static;
    class function DoTexto<T>(const ANome: string): T; static;
    class function Contagem<T>: Integer; static;
  end;

  /// Utilitarios de formatacao usados pela camada de apresentacao
  TFmt = class
  public
    class function Moeda(const AValor: Currency): string; static;
    class function Data(const AValor: TDateTime): string; static;
    class function DataHora(const AValor: TDateTime): string; static;
    class function Pad(const ATexto: string; ATamanho: Integer): string; static;
    class function PadEsq(const ATexto: string; ATamanho: Integer): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils;

{ EValidacao }

constructor EValidacao.Create(const AErros: TArray<string>);
begin
  FErros := AErros;
  inherited Create('Falha de validacao:' + sLineBreak + '  - ' +
    string.Join(sLineBreak + '  - ', AErros));
end;

{ ENaoEncontrado }

constructor ENaoEncontrado.Create(const AEntidade: string; AId: Integer);
begin
  inherited CreateFmt('%s com Id %d nao foi encontrado(a).', [AEntidade, AId]);
end;

{ TResultado<T> }

class function TResultado<T>.Ok(const AValor: T): TResultado<T>;
begin
  Result.FSucesso := True;
  Result.FValor := AValor;
  Result.FErro := '';
end;

class function TResultado<T>.Falha(const AErro: string): TResultado<T>;
begin
  Result.FSucesso := False;
  Result.FValor := Default(T);
  Result.FErro := AErro;
end;

class function TResultado<T>.FalhaFmt(const AErro: string;
  const AArgs: array of const): TResultado<T>;
begin
  Result := TResultado<T>.Falha(Format(AErro, AArgs));
end;

function TResultado<T>.ValorOu(const APadrao: T): T;
begin
  if FSucesso then
    Result := FValor
  else
    Result := APadrao;
end;

function TResultado<T>.SeOk(const AAcao: TProc<T>): TResultado<T>;
begin
  if FSucesso and Assigned(AAcao) then
    AAcao(FValor);
  Result := Self;
end;

function TResultado<T>.SeErro(const AAcao: TProc<string>): TResultado<T>;
begin
  if (not FSucesso) and Assigned(AAcao) then
    AAcao(FErro);
  Result := Self;
end;

function TResultado<T>.ValorOuFalhar: T;
begin
  if not FSucesso then
    raise EDominio.Create(FErro);
  Result := FValor;
end;

{ TPar<K, V> }

class function TPar<K, V>.Criar(const AChave: K; const AValor: V): TPar<K, V>;
begin
  Result.Chave := AChave;
  Result.Valor := AValor;
end;

{ TEnumUtils }

class function TEnumUtils.ParaTexto<T>(const AValor: T): string;
var
  LValor: TValue;
begin
  TValue.Make(@AValor, TypeInfo(T), LValor);
  Result := GetEnumName(TypeInfo(T), LValor.AsOrdinal);
end;

class function TEnumUtils.DoTexto<T>(const ANome: string): T;
var
  LOrdinal: Integer;
  LValor: TValue;
begin
  LOrdinal := GetEnumValue(TypeInfo(T), ANome);
  if LOrdinal < 0 then
    raise EDominio.CreateFmt('Valor "%s" invalido para o enumerado %s.',
      [ANome, string(PTypeInfo(TypeInfo(T))^.Name)]);
  LValor := TValue.FromOrdinal(TypeInfo(T), LOrdinal);
  Result := LValor.AsType<T>;
end;

class function TEnumUtils.Contagem<T>: Integer;
var
  LDados: PTypeData;
begin
  LDados := GetTypeData(TypeInfo(T));
  Result := LDados^.MaxValue - LDados^.MinValue + 1;
end;

{ TFmt }

class function TFmt.Moeda(const AValor: Currency): string;
begin
  Result := FormatFloat('#,##0.00', AValor);
end;

class function TFmt.Data(const AValor: TDateTime): string;
begin
  if AValor = 0 then
    Exit('--/--/----');
  Result := FormatDateTime('dd/mm/yyyy', AValor);
end;

class function TFmt.DataHora(const AValor: TDateTime): string;
begin
  if AValor = 0 then
    Exit('--/--/---- --:--');
  Result := FormatDateTime('dd/mm/yyyy hh:nn', AValor);
end;

class function TFmt.Pad(const ATexto: string; ATamanho: Integer): string;
begin
  Result := Copy(ATexto, 1, ATamanho);
  Result := Result + StringOfChar(' ', Max(0, ATamanho - Length(Result)));
end;

class function TFmt.PadEsq(const ATexto: string; ATamanho: Integer): string;
begin
  Result := Copy(ATexto, 1, ATamanho);
  Result := StringOfChar(' ', Max(0, ATamanho - Length(Result))) + Result;
end;

end.
