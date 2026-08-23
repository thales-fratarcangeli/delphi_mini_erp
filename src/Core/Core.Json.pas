{*******************************************************************************
  Core.Json

  Serializacao JSON automatica via RTTI + utilitarios de arquivo.

  ESTUDO - conceitos demonstrados aqui:
    * Percorrer propriedades com RTTI e ler/escrever valores com TValue
    * Tratamento por TTypeKind (string, inteiro, float, enum, boolean, data)
    * Atributo [NaoSerializar] para excluir propriedades calculadas
    * System.JSON (TJSONObject, TJSONArray, TJSONNumber, TJSONBool)
    * Datas em ISO-8601 (padrao de intercambio, independe de locale)
    * Gerencia de memoria de TJSONValue: quem cria, destroi (AddPair transfere
      a posse para o objeto pai)
*******************************************************************************}
unit Core.Json;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Rtti,
  System.TypInfo,
  System.DateUtils,
  System.IOUtils;

type
  /// Marca propriedades que NAO devem ir para o JSON (ex.: totais calculados).
  NaoSerializarAttribute = class(TCustomAttribute);

  TJsonRtti = class
  private
    class function ValorParaJson(const AValor: TValue): TJSONValue; static;
    class procedure AplicarJson(AProp: TRttiProperty; AObjeto: TObject;
      AJson: TJSONValue); static;
    class function EhData(AProp: TRttiProperty): Boolean; static;
    class function Ignorar(AProp: TRttiProperty): Boolean; static;
  public
    /// Cria um TJSONObject com as propriedades publicas legiveis de AObjeto.
    class function ObjetoParaJson(AObjeto: TObject): TJSONObject; static;
    /// Preenche AObjeto a partir do JSON (propriedades ausentes sao ignoradas).
    class procedure JsonParaObjeto(AJson: TJSONObject; AObjeto: TObject); static;
  end;

  TArquivoJson = class
  public
    class procedure Salvar(AJson: TJSONValue; const AArquivo: string); static;
    /// Devolve nil se o arquivo nao existir. O chamador destroi o resultado.
    class function Carregar(const AArquivo: string): TJSONValue; static;
    class function Formatar(AJson: TJSONValue): string; static;
  end;

implementation

uses
  Core.Types;

{ TJsonRtti }

class function TJsonRtti.Ignorar(AProp: TRttiProperty): Boolean;
var
  LAttr: TCustomAttribute;
begin
  if (not AProp.IsReadable) or (not AProp.IsWritable) then
    Exit(True);
  if AProp.Visibility < mvPublic then
    Exit(True);
  for LAttr in AProp.GetAttributes do
    if LAttr is NaoSerializarAttribute then
      Exit(True);
  Result := False;
end;

class function TJsonRtti.EhData(AProp: TRttiProperty): Boolean;
var
  LNome: string;
begin
  LNome := AProp.PropertyType.Name;
  Result := SameText(LNome, 'TDateTime') or SameText(LNome, 'TDate') or
            SameText(LNome, 'TTime');
end;

class function TJsonRtti.ValorParaJson(const AValor: TValue): TJSONValue;
begin
  case AValor.Kind of
    tkInteger, tkInt64:
      Result := TJSONNumber.Create(AValor.AsInt64);
    tkFloat:
      Result := TJSONNumber.Create(AValor.AsExtended);
    tkEnumeration:
      if AValor.TypeInfo = TypeInfo(Boolean) then
        Result := TJSONBool.Create(AValor.AsBoolean)
      else
        Result := TJSONString.Create(GetEnumName(AValor.TypeInfo, AValor.AsOrdinal));
  else
    Result := TJSONString.Create(AValor.AsString);
  end;
end;

class function TJsonRtti.ObjetoParaJson(AObjeto: TObject): TJSONObject;
var
  LCtx: TRttiContext;
  LProp: TRttiProperty;
  LValor: TValue;
begin
  Result := TJSONObject.Create;
  if AObjeto = nil then
    Exit;

  LCtx := TRttiContext.Create;
  try
    for LProp in LCtx.GetType(AObjeto.ClassType).GetProperties do
    begin
      if Ignorar(LProp) then
        Continue;

      LValor := LProp.GetValue(AObjeto);

      if EhData(LProp) then
      begin
        // ISO-8601 evita o inferno de dd/mm x mm/dd entre maquinas.
        if LValor.AsExtended = 0 then
          Result.AddPair(LProp.Name, TJSONNull.Create)
        else
          Result.AddPair(LProp.Name, DateToISO8601(LValor.AsExtended, False));
        Continue;
      end;

      case LProp.PropertyType.TypeKind of
        tkClass, tkInterface, tkRecord, tkDynArray, tkArray, tkSet, tkMethod:
          Continue; // tipos compostos ficam por conta de quem sobrescreve ToJson
      end;

      Result.AddPair(LProp.Name, ValorParaJson(LValor));
    end;
  finally
    LCtx.Free;
  end;
end;

class procedure TJsonRtti.AplicarJson(AProp: TRttiProperty; AObjeto: TObject;
  AJson: TJSONValue);
var
  LOrdinal: Integer;
  LFloat: Double;
begin
  if (AJson = nil) or (AJson is TJSONNull) then
  begin
    if EhData(AProp) then
      AProp.SetValue(AObjeto, TValue.From<TDateTime>(0));
    Exit;
  end;

  if EhData(AProp) then
  begin
    AProp.SetValue(AObjeto,
      TValue.From<TDateTime>(ISO8601ToDate(AJson.Value, False)));
    Exit;
  end;

  case AProp.PropertyType.TypeKind of
    tkInteger:
      AProp.SetValue(AObjeto, StrToIntDef(AJson.Value, 0));
    tkInt64:
      AProp.SetValue(AObjeto, StrToInt64Def(AJson.Value, 0));
    tkFloat:
      begin
        // Currency, Single e Double sao todos tkFloat, mas TValue e estrito
        // quanto ao tipo exato: precisamos montar o TValue certo.
        LFloat := StrToFloatDef(AJson.Value, 0, TFormatSettings.Invariant);
        if AProp.PropertyType.Handle = TypeInfo(Currency) then
          AProp.SetValue(AObjeto, TValue.From<Currency>(LFloat))
        else if AProp.PropertyType.Handle = TypeInfo(Single) then
          AProp.SetValue(AObjeto, TValue.From<Single>(LFloat))
        else
          AProp.SetValue(AObjeto, TValue.From<Double>(LFloat));
      end;
    tkEnumeration:
      begin
        if AProp.PropertyType.Handle = TypeInfo(Boolean) then
        begin
          if AJson is TJSONBool then
            AProp.SetValue(AObjeto, TJSONBool(AJson).AsBoolean)
          else
            AProp.SetValue(AObjeto, SameText(AJson.Value, 'true'));
        end
        else
        begin
          LOrdinal := GetEnumValue(AProp.PropertyType.Handle, AJson.Value);
          if LOrdinal >= 0 then
            AProp.SetValue(AObjeto,
              TValue.FromOrdinal(AProp.PropertyType.Handle, LOrdinal));
        end;
      end;
    tkString, tkUString, tkLString, tkWString, tkChar, tkWChar:
      AProp.SetValue(AObjeto, AJson.Value);
  end;
end;

class procedure TJsonRtti.JsonParaObjeto(AJson: TJSONObject; AObjeto: TObject);
var
  LCtx: TRttiContext;
  LProp: TRttiProperty;
begin
  if (AJson = nil) or (AObjeto = nil) then
    Exit;

  LCtx := TRttiContext.Create;
  try
    for LProp in LCtx.GetType(AObjeto.ClassType).GetProperties do
    begin
      if Ignorar(LProp) then
        Continue;
      if (not EhData(LProp)) and
         (LProp.PropertyType.TypeKind in
          [tkClass, tkInterface, tkRecord, tkDynArray, tkArray, tkSet, tkMethod]) then
        Continue;
      if AJson.GetValue(LProp.Name) = nil then
        Continue;

      AplicarJson(LProp, AObjeto, AJson.GetValue(LProp.Name));
    end;
  finally
    LCtx.Free;
  end;
end;

{ TArquivoJson }

class function TArquivoJson.Formatar(AJson: TJSONValue): string;
begin
  if AJson = nil then
    Exit('null');
  Result := AJson.Format(2);
end;

class procedure TArquivoJson.Salvar(AJson: TJSONValue; const AArquivo: string);
var
  LPasta: string;
begin
  LPasta := TPath.GetDirectoryName(AArquivo);
  if (LPasta <> '') and (not TDirectory.Exists(LPasta)) then
    TDirectory.CreateDirectory(LPasta);
  try
    TFile.WriteAllText(AArquivo, Formatar(AJson), TEncoding.UTF8);
  except
    on E: Exception do
      raise EInfra.CreateFmt('Falha ao gravar "%s": %s', [AArquivo, E.Message]);
  end;
end;

class function TArquivoJson.Carregar(const AArquivo: string): TJSONValue;
var
  LTexto: string;
begin
  if not TFile.Exists(AArquivo) then
    Exit(nil);
  try
    LTexto := TFile.ReadAllText(AArquivo, TEncoding.UTF8);
  except
    on E: Exception do
      raise EInfra.CreateFmt('Falha ao ler "%s": %s', [AArquivo, E.Message]);
  end;
  Result := TJSONObject.ParseJSONValue(LTexto);
  if Result = nil then
    raise EInfra.CreateFmt('Conteudo invalido em "%s".', [AArquivo]);
end;

end.
