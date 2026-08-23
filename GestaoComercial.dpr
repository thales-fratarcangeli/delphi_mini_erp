{*******************************************************************************
  SISTEMA DE GESTAO COMERCIAL
  Projeto de estudo de Delphi / Object Pascal moderno.

  Modos de execucao:
    GestaoComercial.exe              -> menu interativo
    GestaoComercial.exe --demo       -> roteiro automatico comentado
    GestaoComercial.exe --testes     -> suite de testes (ExitCode 0 = tudo ok)
    GestaoComercial.exe --vazamentos -> liga o detector de memory leaks

  Arquitetura (dependencias sempre apontando para dentro):

      App  ->  Domain  <-  Infra
       |         ^          |
       +------ Core --------+

    Core   : utilidades genericas, sem regra de negocio
    Domain : entidades, regras e CONTRATOS (interfaces) - nao conhece ninguem
    Infra  : implementa os contratos do dominio (memoria, JSON, gateway)
    App    : monta tudo (bootstrap) e conversa com o usuario
*******************************************************************************}
program GestaoComercial;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Core.Types in 'src\Core\Core.Types.pas',
  Core.Logger in 'src\Core\Core.Logger.pas',
  Core.Container in 'src\Core\Core.Container.pas',
  Core.Events in 'src\Core\Core.Events.pas',
  Core.Validation in 'src\Core\Core.Validation.pas',
  Core.Json in 'src\Core\Core.Json.pas',
  Domain.Enums in 'src\Domain\Domain.Enums.pas',
  Domain.Entities in 'src\Domain\Domain.Entities.pas',
  Domain.Events in 'src\Domain\Domain.Events.pas',
  Domain.Specifications in 'src\Domain\Domain.Specifications.pas',
  Domain.Interfaces in 'src\Domain\Domain.Interfaces.pas',
  Domain.Services in 'src\Domain\Domain.Services.pas',
  Domain.Producao in 'src\Domain\Domain.Producao.pas',
  Domain.Producao.Services in 'src\Domain\Domain.Producao.Services.pas',
  Infra.Repositories in 'src\Infra\Infra.Repositories.pas',
  Infra.Mapping in 'src\Infra\Infra.Mapping.pas',
  Infra.Database in 'src\Infra\Infra.Database.pas',
  Infra.Schema in 'src\Infra\Infra.Schema.pas',
  Infra.Repositories.Firebird in 'src\Infra\Infra.Repositories.Firebird.pas',
  Infra.UnitOfWork in 'src\Infra\Infra.UnitOfWork.pas',
  Infra.Gateway in 'src\Infra\Infra.Gateway.pas',
  Infra.Persistence in 'src\Infra\Infra.Persistence.pas',
  App.Bootstrap in 'src\App\App.Bootstrap.pas',
  App.Seed in 'src\App\App.Seed.pas',
  App.Reports in 'src\App\App.Reports.pas',
  App.Console in 'src\App\App.Console.pas',
  App.Demo in 'src\App\App.Demo.pas',
  Tests.Framework in 'src\Tests\Tests.Framework.pas',
  Tests.Suite in 'src\Tests\Tests.Suite.pas';

/// Aceita -x, /x, --x, sem diferenciar maiusculas.
function TemParametro(const ANome: string): Boolean;
var
  I: Integer;
  LParam: string;
begin
  for I := 1 to ParamCount do
  begin
    LParam := ParamStr(I);
    while (LParam <> '') and CharInSet(LParam[1], ['-', '/']) do
      Delete(LParam, 1, 1);
    if SameText(LParam, ANome) then
      Exit(True);
  end;
  Result := False;
end;

/// Modo de persistencia escolhido na linha de comando.
function ModoEscolhido: TModoPersistencia;
begin
  if TemParametro('db') or TemParametro('firebird') then
    Result := mpFirebird
  else
    Result := mpMemoria;
end;

/// --dbcriar: garante o arquivo .fdb e aplica o schema.
procedure ModoCriarBanco;
var
  LConfig: TConfigBanco;
  LConexao: IConexaoBanco;
  LLogger: ILogger;
begin
  LLogger := TConsoleLogger.Create;
  LConfig := TConfigBanco.DoArquivo(ArquivoConfigPadrao);

  Writeln('Configuracao lida de: ', ArquivoConfigPadrao);
  Writeln('Banco: ', LConfig.StringDeConexao);
  Writeln;

  if LConfig.Senha = '' then
  begin
    Writeln('A senha esta vazia em firebird.ini. Preencha e rode de novo.');
    ExitCode := 3;
    Exit;
  end;

  if not TSchema.GarantirBanco(LConfig, LLogger) then
  begin
    Writeln('Nao foi possivel criar/localizar o arquivo do banco.');
    ExitCode := 3;
    Exit;
  end;

  LConexao := TConexaoFirebird.Create(LConfig, LLogger);
  TSchema.Aplicar(LConexao, LLogger);
  Writeln;
  Writeln('Schema pronto. Rode com --db para usar o Firebird.');
end;

/// --dbscript: imprime o DDL (util para gerar bd\schema.sql).
procedure ModoScript;
begin
  Write(TSchema.Script);
end;

procedure ModoInterativo;
var
  LApp: TAplicacao;
  LUI: TConsoleUI;
  LResposta: string;
begin
  LApp := TAplicacao.Create(False, '', ModoEscolhido);
  try
    // Se existirem dados salvos, continua de onde parou; senao, popula exemplos.
    if not LApp.Armazenamento.CarregarTudo then
      TSeed.Popular(LApp);

    LUI := TConsoleUI.Create(LApp);
    try
      LUI.Executar;
    finally
      LUI.Free;
    end;

    Writeln;
    Write('  Salvar os dados antes de sair? (s/n) [s]: ');
    Readln(LResposta);
    if not SameText(Copy(Trim(LResposta), 1, 1), 'n') then
    begin
      LApp.Armazenamento.SalvarTudo;
      Writeln('  Dados gravados em: ', LApp.Armazenamento.Pasta);
    end;
  finally
    LApp.Free;
  end;
end;

var
  LTudoOk: Boolean;
begin
  if TemParametro('vazamentos') then
    ReportMemoryLeaksOnShutdown := True;

  try
    if TemParametro('dbscript') then
      ModoScript
    else if TemParametro('dbcriar') then
      ModoCriarBanco
    else if TemParametro('testes') then
    begin
      LTudoOk := RodarTodosOsTestes(ModoEscolhido = mpFirebird);
      if not LTudoOk then
        ExitCode := 1;
    end
    else if TemParametro('demo') then
      RodarDemonstracao
    else
      ModoInterativo;
  except
    on E: Exception do
    begin
      Writeln;
      Writeln('ERRO FATAL: ', E.ClassName, ' - ', E.Message);
      ExitCode := 2;
    end;
  end;

  if TemParametro('demo') or TemParametro('testes') then
  begin
    Writeln;
    Write('Pressione Enter para fechar...');
    Readln;
  end;
end.
