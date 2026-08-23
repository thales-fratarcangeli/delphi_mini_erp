{*******************************************************************************
  Tests.Framework

  Um mini framework de testes (estilo xUnit) escrito do zero, sem dependencias.

  ESTUDO:
    * Como um framework de teste funciona por dentro: um teste que "passa" e
      simplesmente um bloco de codigo que NAO lancou excecao
    * Metodos anonimos (TProc) guardados em uma lista = "casos de teste"
    * Overload de metodos para as varias formas de comparacao
    * TStopwatch para medir tempo de execucao
    * Comparacao de ponto flutuante com TOLERANCIA (nunca use = com Currency
      ou Double vindos de calculo!)
*******************************************************************************}
unit Tests.Framework;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  System.Generics.Collections;

type
  EFalhaTeste = class(Exception);

  /// Todas as verificacoes disponiveis nos testes.
  TVerificar = class
  public
    class procedure EhVerdade(ACondicao: Boolean; const AMensagem: string); static;
    class procedure EhFalso(ACondicao: Boolean; const AMensagem: string); static;
    class procedure Igual(AEsperado, AObtido: Integer;
      const AMensagem: string); overload; static;
    class procedure Igual(const AEsperado, AObtido: string;
      const AMensagem: string); overload; static;
    class procedure Igual(AEsperado, AObtido: Currency;
      const AMensagem: string); overload; static;
    class procedure Igual(AEsperado, AObtido: Boolean;
      const AMensagem: string); overload; static;
    class procedure Diferente(AEsperado, AObtido: Integer;
      const AMensagem: string); static;
    class procedure NaoNulo(AObjeto: TObject; const AMensagem: string); static;
    class procedure Nulo(AObjeto: TObject; const AMensagem: string); static;
    class procedure Contem(const ATexto, ATrecho, AMensagem: string); static;
    /// Verifica que o bloco lanca a excecao esperada (ou uma descendente).
    class procedure Lanca(AClasse: ExceptClass; const ABloco: TProc;
      const AMensagem: string); static;
    /// Verifica que o bloco NAO lanca nada.
    class procedure NaoLanca(const ABloco: TProc; const AMensagem: string); static;
  end;

  TSuiteTestes = class
  private type
    TCaso = record
      Grupo: string;
      Nome: string;
      Executar: TProc;
    end;
  private
    FCasos: TList<TCaso>;
    FGrupoAtual: string;
    FAprovados: Integer;
    FReprovados: Integer;
    FFalhas: TStringList;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Grupo(const ANome: string);
    procedure Teste(const ANome: string; const AExecutar: TProc);
    /// Roda tudo, imprime o relatorio e devolve True se passou 100%.
    function Rodar: Boolean;

    property Aprovados: Integer read FAprovados;
    property Reprovados: Integer read FReprovados;
  end;

implementation

uses
  System.Math;

{ TVerificar }

class procedure TVerificar.EhVerdade(ACondicao: Boolean; const AMensagem: string);
begin
  if not ACondicao then
    raise EFalhaTeste.Create(AMensagem + ' (esperava verdadeiro)');
end;

class procedure TVerificar.EhFalso(ACondicao: Boolean; const AMensagem: string);
begin
  if ACondicao then
    raise EFalhaTeste.Create(AMensagem + ' (esperava falso)');
end;

class procedure TVerificar.Igual(AEsperado, AObtido: Integer; const AMensagem: string);
begin
  if AEsperado <> AObtido then
    raise EFalhaTeste.CreateFmt('%s (esperava %d, obteve %d)',
      [AMensagem, AEsperado, AObtido]);
end;

class procedure TVerificar.Igual(const AEsperado, AObtido: string;
  const AMensagem: string);
begin
  if AEsperado <> AObtido then
    raise EFalhaTeste.CreateFmt('%s (esperava "%s", obteve "%s")',
      [AMensagem, AEsperado, AObtido]);
end;

class procedure TVerificar.Igual(AEsperado, AObtido: Currency;
  const AMensagem: string);
begin
  // 1 centavo de tolerancia: calculos com percentual quase nunca batem exato.
  if Abs(AEsperado - AObtido) > 0.005 then
    raise EFalhaTeste.CreateFmt('%s (esperava %m, obteve %m)',
      [AMensagem, AEsperado, AObtido]);
end;

class procedure TVerificar.Igual(AEsperado, AObtido: Boolean;
  const AMensagem: string);
begin
  if AEsperado <> AObtido then
    raise EFalhaTeste.CreateFmt('%s (esperava %s, obteve %s)',
      [AMensagem, BoolToStr(AEsperado, True), BoolToStr(AObtido, True)]);
end;

class procedure TVerificar.Diferente(AEsperado, AObtido: Integer;
  const AMensagem: string);
begin
  if AEsperado = AObtido then
    raise EFalhaTeste.CreateFmt('%s (os dois valores sao %d)',
      [AMensagem, AObtido]);
end;

class procedure TVerificar.NaoNulo(AObjeto: TObject; const AMensagem: string);
begin
  if AObjeto = nil then
    raise EFalhaTeste.Create(AMensagem + ' (objeto nulo)');
end;

class procedure TVerificar.Nulo(AObjeto: TObject; const AMensagem: string);
begin
  if AObjeto <> nil then
    raise EFalhaTeste.Create(AMensagem + ' (esperava nulo)');
end;

class procedure TVerificar.Contem(const ATexto, ATrecho, AMensagem: string);
begin
  if not ATexto.Contains(ATrecho) then
    raise EFalhaTeste.CreateFmt('%s ("%s" nao contem "%s")',
      [AMensagem, ATexto, ATrecho]);
end;

class procedure TVerificar.Lanca(AClasse: ExceptClass; const ABloco: TProc;
  const AMensagem: string);
var
  LLancou: Boolean;
begin
  LLancou := False;
  try
    ABloco();
  except
    on E: Exception do
    begin
      LLancou := True;
      // "is" nao aceita variavel de classe -> usamos InheritsFrom
      if not E.ClassType.InheritsFrom(AClasse) then
        raise EFalhaTeste.CreateFmt('%s (esperava %s, veio %s: %s)',
          [AMensagem, AClasse.ClassName, E.ClassName, E.Message]);
    end;
  end;

  if not LLancou then
    raise EFalhaTeste.CreateFmt('%s (nenhuma excecao lancada; esperava %s)',
      [AMensagem, AClasse.ClassName]);
end;

class procedure TVerificar.NaoLanca(const ABloco: TProc; const AMensagem: string);
begin
  try
    ABloco();
  except
    on E: Exception do
      raise EFalhaTeste.CreateFmt('%s (lancou %s: %s)',
        [AMensagem, E.ClassName, E.Message]);
  end;
end;

{ TSuiteTestes }

constructor TSuiteTestes.Create;
begin
  inherited Create;
  FCasos := TList<TCaso>.Create;
  FFalhas := TStringList.Create;
  FGrupoAtual := 'Geral';
end;

destructor TSuiteTestes.Destroy;
begin
  FCasos.Free;
  FFalhas.Free;
  inherited;
end;

procedure TSuiteTestes.Grupo(const ANome: string);
begin
  FGrupoAtual := ANome;
end;

procedure TSuiteTestes.Teste(const ANome: string; const AExecutar: TProc);
var
  LCaso: TCaso;
begin
  LCaso.Grupo := FGrupoAtual;
  LCaso.Nome := ANome;
  LCaso.Executar := AExecutar;
  FCasos.Add(LCaso);
end;

function TSuiteTestes.Rodar: Boolean;
var
  LCaso: TCaso;
  LRelogio: TStopwatch;
  LGrupo: string;
  LFalha: string;
begin
  FAprovados := 0;
  FReprovados := 0;
  FFalhas.Clear;
  LGrupo := '';

  Writeln;
  Writeln('================ SUITE DE TESTES ================');
  LRelogio := TStopwatch.StartNew;

  for LCaso in FCasos do
  begin
    if LCaso.Grupo <> LGrupo then
    begin
      LGrupo := LCaso.Grupo;
      Writeln;
      Writeln('-- ', LGrupo);
    end;

    try
      LCaso.Executar();
      Inc(FAprovados);
      Writeln('   [ok]     ', LCaso.Nome);
    except
      on E: Exception do
      begin
        Inc(FReprovados);
        Writeln('   [FALHOU] ', LCaso.Nome);
        Writeln('              ', E.ClassName, ': ', E.Message);
        FFalhas.Add(Format('%s / %s -> %s: %s',
          [LCaso.Grupo, LCaso.Nome, E.ClassName, E.Message]));
      end;
    end;
  end;

  LRelogio.Stop;

  Writeln;
  Writeln('------------------------------------------------');
  Writeln(Format('Total: %d | Aprovados: %d | Reprovados: %d | Tempo: %d ms',
    [FCasos.Count, FAprovados, FReprovados, LRelogio.ElapsedMilliseconds]));

  if FReprovados > 0 then
  begin
    Writeln;
    Writeln('Falhas:');
    for LFalha in FFalhas do
      Writeln('  * ', LFalha);
  end;
  Writeln('================================================');

  Result := FReprovados = 0;
end;

end.
