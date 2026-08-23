{*******************************************************************************
  Core.Validation

  Validacao declarativa por ATRIBUTOS + RTTI.

  ESTUDO - conceitos demonstrados aqui:
    * Atributos customizados (TCustomAttribute) e como o compilador os liga
      as propriedades
    * RTTI: TRttiContext / TRttiType / TRttiProperty / TValue
    * Como escrever validacao generica que serve para QUALQUER classe
    * Por padrao o Delphi gera RTTI para propriedades public e published,
      por isso as propriedades validadas devem ser publicas.

  Em vez de:
      if Nome = '' then Erros.Add('Nome obrigatorio');
  escrevemos:
      [Obrigatorio] [TamanhoMax(80)]
      property Nome: string read FNome write FNome;
*******************************************************************************}
unit Core.Validation;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  Core.Types;

type
  /// Rotulo amigavel para exibir nas mensagens de erro.
  RotuloAttribute = class(TCustomAttribute)
  private
    FTexto: string;
  public
    constructor Create(const ATexto: string);
    property Texto: string read FTexto;
  end;

  /// Base de todas as regras de validacao.
  ValidacaoAttribute = class abstract(TCustomAttribute)
  private
    FMensagem: string;
  public
    constructor Create(const AMensagem: string = '');
    function Valido(const AValor: TValue): Boolean; virtual; abstract;
    function MensagemPadrao: string; virtual; abstract;
    function Descrever(const ARotulo: string): string;
    property Mensagem: string read FMensagem write FMensagem;
  end;

  /// Nao pode ser vazio (string), zero (numero) nem data nula.
  ObrigatorioAttribute = class(ValidacaoAttribute)
  public
    function Valido(const AValor: TValue): Boolean; override;
    function MensagemPadrao: string; override;
  end;

  TamanhoMinAttribute = class(ValidacaoAttribute)
  private
    FMin: Integer;
  public
    constructor Create(AMin: Integer; const AMensagem: string = '');
    function Valido(const AValor: TValue): Boolean; override;
    function MensagemPadrao: string; override;
  end;

  TamanhoMaxAttribute = class(ValidacaoAttribute)
  private
    FMax: Integer;
  public
    constructor Create(AMax: Integer; const AMensagem: string = '');
    function Valido(const AValor: TValue): Boolean; override;
    function MensagemPadrao: string; override;
  end;

  /// Faixa numerica fechada [Min, Max].
  FaixaAttribute = class(ValidacaoAttribute)
  private
    FMin, FMax: Double;
  public
    constructor Create(AMin, AMax: Double; const AMensagem: string = '');
    function Valido(const AValor: TValue): Boolean; override;
    function MensagemPadrao: string; override;
  end;

  /// Numero >= 0.
  NaoNegativoAttribute = class(ValidacaoAttribute)
  public
    function Valido(const AValor: TValue): Boolean; override;
    function MensagemPadrao: string; override;
  end;

  EmailValidoAttribute = class(ValidacaoAttribute)
  public
    function Valido(const AValor: TValue): Boolean; override;
    function MensagemPadrao: string; override;
  end;

  /// Somente digitos, com quantidade permitida (ex.: CPF 11, CNPJ 14).
  CpfOuCnpjAttribute = class(ValidacaoAttribute)
  public
    function Valido(const AValor: TValue): Boolean; override;
    function MensagemPadrao: string; override;
  end;

  TValidador = class
  private
    class function RotuloDe(AProp: TRttiProperty): string; static;
  public
    /// Devolve a lista de problemas (vazia = tudo certo).
    class function Validar(AObjeto: TObject): TArray<string>; static;
    /// Igual a Validar, mas lanca EValidacao se houver problemas.
    class procedure ValidarOuFalhar(AObjeto: TObject); static;
    /// Lista as regras declaradas numa classe (util para documentacao/estudo).
    class function DescreverRegras(AClasse: TClass): TArray<string>; static;
  end;

function SomenteDigitos(const ATexto: string): string;

implementation

uses
  System.Character,
  System.Math;

function SomenteDigitos(const ATexto: string): string;
var
  LChar: Char;
  LBuilder: TStringBuilder;
begin
  LBuilder := TStringBuilder.Create;
  try
    for LChar in ATexto do
      if LChar.IsDigit then
        LBuilder.Append(LChar);
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

{ RotuloAttribute }

constructor RotuloAttribute.Create(const ATexto: string);
begin
  inherited Create;
  FTexto := ATexto;
end;

{ ValidacaoAttribute }

constructor ValidacaoAttribute.Create(const AMensagem: string);
begin
  inherited Create;
  FMensagem := AMensagem;
end;

function ValidacaoAttribute.Descrever(const ARotulo: string): string;
begin
  if FMensagem <> '' then
    Result := Format('%s: %s', [ARotulo, FMensagem])
  else
    Result := Format('%s: %s', [ARotulo, MensagemPadrao]);
end;

{ ObrigatorioAttribute }

function ObrigatorioAttribute.Valido(const AValor: TValue): Boolean;
begin
  case AValor.Kind of
    tkString, tkUString, tkLString, tkWString:
      Result := Trim(AValor.AsString) <> '';
    tkInteger, tkInt64:
      Result := AValor.AsInt64 <> 0;
    tkFloat:
      Result := not SameValue(AValor.AsExtended, 0);
    tkClass:
      Result := AValor.AsObject <> nil;
  else
    Result := not AValor.IsEmpty;
  end;
end;

function ObrigatorioAttribute.MensagemPadrao: string;
begin
  Result := 'e obrigatorio.';
end;

{ TamanhoMinAttribute }

constructor TamanhoMinAttribute.Create(AMin: Integer; const AMensagem: string);
begin
  inherited Create(AMensagem);
  FMin := AMin;
end;

function TamanhoMinAttribute.Valido(const AValor: TValue): Boolean;
begin
  Result := Length(Trim(AValor.AsString)) >= FMin;
end;

function TamanhoMinAttribute.MensagemPadrao: string;
begin
  Result := Format('deve ter no minimo %d caracteres.', [FMin]);
end;

{ TamanhoMaxAttribute }

constructor TamanhoMaxAttribute.Create(AMax: Integer; const AMensagem: string);
begin
  inherited Create(AMensagem);
  FMax := AMax;
end;

function TamanhoMaxAttribute.Valido(const AValor: TValue): Boolean;
begin
  Result := Length(Trim(AValor.AsString)) <= FMax;
end;

function TamanhoMaxAttribute.MensagemPadrao: string;
begin
  Result := Format('deve ter no maximo %d caracteres.', [FMax]);
end;

{ FaixaAttribute }

constructor FaixaAttribute.Create(AMin, AMax: Double; const AMensagem: string);
begin
  inherited Create(AMensagem);
  FMin := AMin;
  FMax := AMax;
end;

function FaixaAttribute.Valido(const AValor: TValue): Boolean;
var
  LNumero: Double;
begin
  if AValor.Kind in [tkInteger, tkInt64] then
    LNumero := AValor.AsInt64
  else if AValor.Kind = tkFloat then
    LNumero := AValor.AsExtended
  else
    Exit(True); // regra nao se aplica a tipos nao numericos
  Result := (LNumero >= FMin) and (LNumero <= FMax);
end;

function FaixaAttribute.MensagemPadrao: string;
begin
  Result := Format('deve estar entre %s e %s.',
    [FormatFloat('#,##0.##', FMin), FormatFloat('#,##0.##', FMax)]);
end;

{ NaoNegativoAttribute }

function NaoNegativoAttribute.Valido(const AValor: TValue): Boolean;
begin
  if AValor.Kind in [tkInteger, tkInt64] then
    Result := AValor.AsInt64 >= 0
  else if AValor.Kind = tkFloat then
    Result := AValor.AsExtended >= 0
  else
    Result := True;
end;

function NaoNegativoAttribute.MensagemPadrao: string;
begin
  Result := 'nao pode ser negativo.';
end;

{ EmailValidoAttribute }

function EmailValidoAttribute.Valido(const AValor: TValue): Boolean;
var
  LTexto: string;
  LArroba, LPonto: Integer;
begin
  LTexto := Trim(AValor.AsString);
  if LTexto = '' then
    Exit(True); // vazio e problema do [Obrigatorio], nao deste atributo
  LArroba := Pos('@', LTexto);
  LPonto := LastDelimiter('.', LTexto);
  Result := (LArroba > 1) and (LPonto > LArroba + 1) and (LPonto < Length(LTexto));
end;

function EmailValidoAttribute.MensagemPadrao: string;
begin
  Result := 'nao e um e-mail valido.';
end;

{ CpfOuCnpjAttribute }

function CpfOuCnpjAttribute.Valido(const AValor: TValue): Boolean;
var
  LDigitos: string;
begin
  LDigitos := SomenteDigitos(AValor.AsString);
  if LDigitos = '' then
    Exit(True);
  Result := (Length(LDigitos) = 11) or (Length(LDigitos) = 14);
end;

function CpfOuCnpjAttribute.MensagemPadrao: string;
begin
  Result := 'deve ser um CPF (11 digitos) ou CNPJ (14 digitos).';
end;

{ TValidador }

class function TValidador.RotuloDe(AProp: TRttiProperty): string;
var
  LAttr: TCustomAttribute;
begin
  for LAttr in AProp.GetAttributes do
    if LAttr is RotuloAttribute then
      Exit(RotuloAttribute(LAttr).Texto);
  Result := AProp.Name;
end;

class function TValidador.Validar(AObjeto: TObject): TArray<string>;
var
  LCtx: TRttiContext;
  LTipo: TRttiType;
  LProp: TRttiProperty;
  LAttr: TCustomAttribute;
  LRegra: ValidacaoAttribute;
  LErros: TList<string>;
  LValor: TValue;
begin
  if AObjeto = nil then
    Exit(nil);

  LErros := TList<string>.Create;
  LCtx := TRttiContext.Create;
  try
    LTipo := LCtx.GetType(AObjeto.ClassType);
    for LProp in LTipo.GetProperties do
    begin
      if not LProp.IsReadable then
        Continue;

      LValor := TValue.Empty;
      for LAttr in LProp.GetAttributes do
      begin
        if not (LAttr is ValidacaoAttribute) then
          Continue;

        if LValor.IsEmpty then
          LValor := LProp.GetValue(AObjeto);

        LRegra := ValidacaoAttribute(LAttr);
        if not LRegra.Valido(LValor) then
          LErros.Add(LRegra.Descrever(RotuloDe(LProp)));
      end;
    end;
    Result := LErros.ToArray;
  finally
    LCtx.Free;
    LErros.Free;
  end;
end;

class procedure TValidador.ValidarOuFalhar(AObjeto: TObject);
var
  LErros: TArray<string>;
begin
  LErros := Validar(AObjeto);
  if Length(LErros) > 0 then
    raise EValidacao.Create(LErros);
end;

class function TValidador.DescreverRegras(AClasse: TClass): TArray<string>;
var
  LCtx: TRttiContext;
  LProp: TRttiProperty;
  LAttr: TCustomAttribute;
  LLista: TList<string>;
begin
  LLista := TList<string>.Create;
  LCtx := TRttiContext.Create;
  try
    for LProp in LCtx.GetType(AClasse).GetProperties do
      for LAttr in LProp.GetAttributes do
        if LAttr is ValidacaoAttribute then
          LLista.Add(ValidacaoAttribute(LAttr).Descrever(RotuloDe(LProp)));
    Result := LLista.ToArray;
  finally
    LCtx.Free;
    LLista.Free;
  end;
end;

end.
