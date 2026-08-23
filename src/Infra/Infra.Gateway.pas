{*******************************************************************************
  Infra.Gateway

  Simulacao de um servico EXTERNO de pagamento.

  ESTUDO:
    * Toda dependencia externa (API, e-mail, SMS, impressora fiscal) deve
      entrar no sistema por uma INTERFACE. Assim:
        - em producao usa-se a implementacao real
        - em teste usa-se um "dublê" (stub/fake) deterministico
    * Repare que o dominio nunca sabe se o pagamento foi por HTTP ou por sorteio
*******************************************************************************}
unit Infra.Gateway;

interface

uses
  System.SysUtils,
  Core.Logger,
  Domain.Enums,
  Domain.Interfaces;

type
  /// Gateway de mentira, porem com regras plausiveis, para o modo demonstracao.
  TGatewaySimulado = class(TInterfacedObject, IGatewayPagamento)
  private
    FLogger: ILogger;
    FTetoAprovacao: Currency;
    FContador: Integer;
  public
    constructor Create(const ALogger: ILogger; ATetoAprovacao: Currency = 50000);
    function Autorizar(AValor: Currency; AForma: TFormaPagamento;
      out AAutorizacao: string): Boolean;
    function Nome: string;
  end;

  /// Dublê para testes: aprova sempre.
  TGatewaySempreAprova = class(TInterfacedObject, IGatewayPagamento)
  public
    function Autorizar(AValor: Currency; AForma: TFormaPagamento;
      out AAutorizacao: string): Boolean;
    function Nome: string;
  end;

  /// Dublê para testes: recusa sempre.
  TGatewaySempreRecusa = class(TInterfacedObject, IGatewayPagamento)
  public
    function Autorizar(AValor: Currency; AForma: TFormaPagamento;
      out AAutorizacao: string): Boolean;
    function Nome: string;
  end;

implementation

uses
  Core.Types;

{ TGatewaySimulado }

constructor TGatewaySimulado.Create(const ALogger: ILogger;
  ATetoAprovacao: Currency);
begin
  inherited Create;
  if Assigned(ALogger) then
    FLogger := ALogger
  else
    FLogger := TLoggerNulo.Create;
  FTetoAprovacao := ATetoAprovacao;
end;

function TGatewaySimulado.Nome: string;
begin
  Result := 'Gateway Simulado';
end;

function TGatewaySimulado.Autorizar(AValor: Currency; AForma: TFormaPagamento;
  out AAutorizacao: string): Boolean;
begin
  Inc(FContador);

  if AValor <= 0 then
  begin
    AAutorizacao := 'valor invalido';
    Exit(False);
  end;

  if AValor > FTetoAprovacao then
  begin
    AAutorizacao := Format('acima do teto de %s', [TFmt.Moeda(FTetoAprovacao)]);
    FLogger.Aviso('Gateway recusou %s: %s', [TFmt.Moeda(AValor), AAutorizacao]);
    Exit(False);
  end;

  // Regra ficticia: boleto acima de 10 mil cai em analise manual.
  if (AForma = fpBoleto) and (AValor > 10000) then
  begin
    AAutorizacao := 'boleto em analise manual';
    Exit(False);
  end;

  AAutorizacao := Format('AUT-%s-%.4d',
    [FormatDateTime('yyyymmddhhnnss', Now), FContador]);
  FLogger.Info('Gateway autorizou %s via %s (%s)',
    [TFmt.Moeda(AValor), FormaPagamentoDescr(AForma), AAutorizacao]);
  Result := True;
end;

{ TGatewaySempreAprova }

function TGatewaySempreAprova.Nome: string;
begin
  Result := 'Gateway (sempre aprova)';
end;

function TGatewaySempreAprova.Autorizar(AValor: Currency; AForma: TFormaPagamento;
  out AAutorizacao: string): Boolean;
begin
  AAutorizacao := 'AUT-TESTE-OK';
  Result := True;
end;

{ TGatewaySempreRecusa }

function TGatewaySempreRecusa.Nome: string;
begin
  Result := 'Gateway (sempre recusa)';
end;

function TGatewaySempreRecusa.Autorizar(AValor: Currency; AForma: TFormaPagamento;
  out AAutorizacao: string): Boolean;
begin
  AAutorizacao := 'recusado para teste';
  Result := False;
end;

end.
