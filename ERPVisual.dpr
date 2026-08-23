{*******************************************************************************
  ERP INDUSTRIAL - versao com TELAS (VCL)

  Este projeto e o exercicio 14 do README resolvido: uma SEGUNDA interface de
  usuario sobre o mesmo sistema, sem alterar nada abaixo da camada App.

  Compare a lista de units abaixo com a de GestaoComercial.dpr:
  src\Core, src\Domain e src\Infra sao IDENTICOS. So a camada de cima muda:

      GestaoComercial.dpr  ->  App.Console  (Writeln/Readln)
      ERPVisual.dpr        ->  UI.Principal (TForm, TListView, TTreeView)

  Se voce precisar mexer em algo de src\Domain para uma tela funcionar,
  a regra de negocio estava no lugar errado.

  Uso:
    ERPVisual.exe          -> dados em memoria (nao precisa de nada instalado)
    ERPVisual.exe --db     -> dados no Firebird (servidor precisa estar no ar)
*******************************************************************************}
program ERPVisual;

uses
  Vcl.Forms,
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
  Domain.Producao in 'src\Domain\Domain.Producao.pas',
  Domain.Interfaces in 'src\Domain\Domain.Interfaces.pas',
  Domain.Services in 'src\Domain\Domain.Services.pas',
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
  UI.Principal in 'src\UI\UI.Principal.pas' {FormPrincipal},
  UI.Apontamento in 'src\UI\UI.Apontamento.pas' {FormApontamento};

{$R *.res}
{ Manifesto com a dependencia de comctl32 v6: e o que faz o Windows desenhar
  os controles com aparencia moderna. Gerado a partir de src\UI\Manifesto.rc
  com:  brcc32 Manifesto.rc -foManifesto.res  }
{$R src\UI\Manifesto.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'ERP Industrial';
  Application.CreateForm(TFormPrincipal, FormPrincipal);
  Application.Run;
end.
